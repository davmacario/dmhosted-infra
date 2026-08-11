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

Command (both for installation and upgrade):

```bash
helm upgrade --install vaultwarden vaultwarden/vaultwarden -n vaultwarden --values ./values.yaml
```

#### Setting up HTTPS access (IngressRoute)

See [manifest](../kubernetes/apps/vaultwarden/ingressroute.yaml) for the `Certificate` + `IngressRoute` used to expose Vaultwarden.

## Configuration

Navigate to `https://<your-vaultwarden-domain>/admin` to log into the admin console.

Then, provide your admin token created [before](#admin-token).

### SMTP

See [SMTP Configuration](./smtp-configuration.md)

---

## Links

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
- [Vaultwarden Helm Chart](https://github.com/guerzon/vaultwarden)
- [Longhorn documentation - Creation and Usage of Generic RWX Volumes](https://longhorn.io/docs/1.11.0/nodes-and-volumes/volumes/rwx-volumes/#creation-and-usage-of-generic-non-migratable-rwx-volumes)
- [Medium article on RWX Longhorn volumes](https://medium.com/@nsalexamy/longhorn-how-to-use-shared-readwritemany-volumes-for-stateful-applications-57a9454df908)
