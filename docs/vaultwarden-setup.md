---
id: vaultwarden-setup
author: Davide Macario
date: 2026-03-11
tags:
  - homelab
  - k3s
---

# Vaultwarden Setup on K3s

**Goal**: set up [Vaultwarden](https://github.com/dani-garcia/vaultwarden) in a HA manner.

This should be possible according to [this forum post](https://vaultwarden.discourse.group/t/running-highly-available-vaultwarden/3285/8).
We will just have to configure RWX volumes properly with Longhorn.

> [!NOTE]
>
> This setup is _way too overkill_ for personal usage, which is the whole point! 😉

## Installation

We will use Helm.

To add the repo:

```bash
helm repo add vaultwarden https://guerzon.github.io/vaultwarden
```

### Setting up RWX Volume with Longhorn

In the [PR that added support for HA](https://github.com/guerzon/vaultwarden/pull/131), the note specifies that concurrent access to the persistent repo should be handled by the cluster admin, by means of a proper StorageClass.

With Longhorn, it is possible to set up RWX StorageClasses, as per [documentation](https://longhorn.io/docs/1.11.0/nodes-and-volumes/volumes/rwx-volumes/).

The only requirements are:

- [x] An NFSv4 client is installed on each node (for Ubuntu 24.04, NFSv4 support is enabled, and we can install `nfs-common` from APT)
- [x] The nodes have unique hostnames

We need to define a custom StorageClass that supports ReadWriteMany and (**very important**) that is **not migratable**.
See [extra storageclasses](../kubernetes/longhorn/extra-storageclasses.yaml):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rwx
provisioner: driver.longhorn.io
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  migratable: "false" # This is key!
  fsType: "ext4"
  nfsOptions: "vers=4.2,noresvport,softerr,timeo=600,retrans=5"
```

Note the extra NFS options.
They are all default, except for the version, but they all have to be present in the string, even if not overwritten.

### Configuring Vaultwarden

See [values.yaml](../kubernetes/apps/vaultwarden/values.yaml).

#### Database setup

Using CNPG, handling secrets externally.
See [manifest](../kubernetes/apps/vaultwarden/database.yaml).

Need a secret for the DB user (`vaultwarden-app-db-secret`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vaultwarden-app-db-secret
  namespace: vaultwarden
type: Opaque
stringData:
  username: vaultwarden
  password: <secret-string>
```

#### Admin Token

The admin token is a secret string used to manage access to the `/admin` endpoint of Vaultwarden.

To increase security, the token should be provided to vaultwarden hashed.

```bash
echo -n "YourRandomPassword" | argon2 "$(openssl rand -base64 32)" -e -id -k 19456 -t 2 -p 1
```

(You may need to install `argon2` on your system).

The output can then be stored inside a secret that will be referenced in the `adminToken:existingSecret` section of values.yaml.

#### PVC creation

We will manage our PVC for the app (not DB) independently.
See the [manifest](../kubernetes/apps/vaultwarden/pvc.yaml).
This defines the `vaultwarden-rwx-pvc` PVC.

#### Installing the Helm chart

Vaultwarden is deployed via Argo CD, and it consists of the [Helm chart](https://guerzon.github.io/vaultwarden), plus some manifests to define other resources:

- App secrets
- Database (CNPG cluster)
- IngressRoute + certificate + middlewares
- NetworkPolicies
- HorizontalPodAutoscaler

To preview what the chart will render before syncing:

```bash
helm template vaultwarden vaultwarden/vaultwarden --version <targetRevision> \
  -n vaultwarden --values ./values.yaml
```

## Configuration - admin console

`/admin` is **blocked on the public route** (see [Hardening](#hardening)), so reach it through a port-forward instead:

```bash
kubectl -n vaultwarden port-forward svc/vaultwarden 8080:80
```

Then navigate to `http://localhost:8080/admin` and provide your admin token created [before](#admin-token).

### SMTP

See [SMTP Configuration](./smtp-configuration.md)

### YubiKey configuration

> Not that interesting - using it as MFA device with WebAuthn.

---

## Hardening

Vaultwarden is the highest-value workload in the cluster, so it important it gets locked down properly.

### Pod and container

Set in [`values.yaml`](../kubernetes/apps/vaultwarden/values.yaml):

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
securityContext:
  allowPrivilegeEscalation: false
  privileged: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

# Avoids issues with readOnlyRootFilesystem
extraVolumes:
  - name: tmp
    emptyDir:
      medium: Memory
      sizeLimit: 64Mi
extraVolumeMounts:
  - name: tmp
    mountPath: /tmp
```

### Network

[`networkpolicy.yaml`](../kubernetes/apps/vaultwarden/networkpolicy.yaml) default-denies the **app pods only** and allows:

- ingress from primary Traefik
- ingress from the node subnet (kubelet probes)
- egress to DNS
- egress to the CNPG instance pods on 5432
- egress to `:587` for the Brevo SMTP relay
- egress to `:443`/`:80` for favicon fetching.

Every public-internet egress rule excludes the RFC1918 / tailnet / link-local ranges.
With `iconService: internal` Vaultwarden fetches favicons itself, which means it will HTTP-GET any hostname a user stores a login for - an SSRF primitive.
The exclusions are defence in depth behind the app's own `ICON_BLACKLIST_NON_GLOBAL_IPS=true`.

> Pod selectors use `app.kubernetes.io/{component,name,instance}: vaultwarden`.
> **Never** select on `app: vaultwarden` - that label is on the _Service_ and, via `inheritedMetadata` in `database.yaml`, on the _CNPG pods_.
> Using it would deny the database instead of the app.

The CNPG cluster itself is **not** yet covered by a policy.
Doing so needs rules for replication (5432/8000), the instance manager's kube-apiserver access, the `cnpg-system` operator, and barman-cloud S3 egress to the NAS - a separate change.

### Edge

`/admin` is denied on the public IngressRoute by the `vaultwarden-deny` middleware in [`middlewares.yaml`](../kubernetes/apps/vaultwarden/middlewares.yaml) (an `ipAllowList` of `127.0.0.1/32`, which the cloudflared source address can never match).

### Application settings

- `ipHeader: CF-Connecting-IP`: every request arrives via the Cloudflare tunnel, so Traefik's `X-Real-IP` (the chart default) is always the cloudflared pod's address.
  That would make `adminRateLimitSeconds` / `adminRateLimitMaxBurst` and the login limiter key on a single value for the entire internet.
  Note a LAN client could forge this header, since the Traefik LoadBalancer is reachable locally; public traffic cannot.
- `orgCreationUsers: none`, `requireDeviceEmail: true`, `showPassHint: false`.
- `orgEventsEnabled: true` + `eventsDayRetain: 90` - audit log. `eventsDayRetain` is also what enables the `eventCleanupSched` job; without it events are kept forever.

---

## Links

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
- [Vaultwarden Helm Chart](https://github.com/guerzon/vaultwarden)
- [Longhorn documentation - Creation and Usage of Generic RWX Volumes](https://longhorn.io/docs/1.11.0/nodes-and-volumes/volumes/rwx-volumes/#creation-and-usage-of-generic-non-migratable-rwx-volumes)
- [Medium article on RWX Longhorn volumes](https://medium.com/@nsalexamy/longhorn-how-to-use-shared-readwritemany-volumes-for-stateful-applications-57a9454df908)
