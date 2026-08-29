---
id: sealed-secrets
author: Davide Macario
date: 2026-06-18
tags:
  - homelab
  - secrets
---

# Sealed Secrets

Sealed Secrets is a tool that makes Kubernetes secrets management easier.
It achieves this by providing "Sealed Secrets", which are an encrypted version of Secrets, which can be safely be tracked in Version Control.

It is based on private-public key pair and on a Kubernetes controller.
Secrets can be encrypted using the `kubeseal` utility, which uses the public key, and can only be decrypted by using the private key, which lives in the Controller.

This also allows for a CI-safe way to manage secrets, as it is just possible to commit to Git the Sealed Secrets, and let tools like [ArgoCD](./argocd.md) carry out the deployment.

## Installation

Installing version **0.38.1** (latest at the time of writing).

### Cluster-side

Using the released manifest (see [releases](https://github.com/bitnami/sealed-secrets/releases)):

```bash
kubectl apply -f https://github.com/bitnami/sealed-secrets/releases/download/v0.38.1/controller.yaml
```

This installs **CRDs** and the **Controller** (in the `kube-system` ns).

### Client side

To install the `kubeseal` client (used to create Sealed Secrets via the public key), it is possible to use Homebrew:

```bash
brew install kubeseal
```

Alternatively, for x86_64 Linux clients:

```bash
curl -OL "https://github.com/bitnami/sealed-secrets/releases/download/v0.38.1/kubeseal-0.38.1-linux-amd64.tar.gz"
tar -xvzf kubeseal-0.38.1-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Managing with ArgoCD

The controller was originally installed with `kubectl apply` (see above).
It is now managed by [ArgoCD](./argocd.md) via
[`kubernetes/argocd-apps/sealed-secrets.yaml`](../kubernetes/argocd-apps/sealed-secrets.yaml), and
should not be applied by hand any more.

### Switch to Helm

ArgoCD `Application`s only support local (in Git) YAML manifests, Helm charts, or Kustomize, meaning
there is no way to point to the remote manifest mentioned in [previous section](#cluster-side).
For this reason, it was required to move to an alternative method, and Helm was chosen.
The helm chart is found at <https://bitnami.github.io/sealed-secrets>.

Chart `2.19.0` maps to app version `0.38.1`, i.e. exactly what the release manifest had installed,
so the migration changes the delivery mechanism without upgrading the controller.

Values can be found in [`kubernetes/sealed-secrets/values.yaml`](../kubernetes/sealed-secrets/values.yaml).
The only setting is `fullnameOverride: sealed-secrets-controller`, which keeps the resource names
the release manifest used - the chart otherwise names everything `sealed-secrets`, which would
spin up a second controller instead of adopting the running one and would break
`kubeseal --controller-name=sealed-secrets-controller`.

To bump the version, find the chart revision and update `targetRevision` in the Application:

```bash
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm search repo sealed-secrets/sealed-secrets --versions | head
```

### Adopting the existing installation

Most objects are adopted in place, because the names already match: the `sealedsecrets.bitnami.com`
CRD, the `secrets-unsealer` ClusterRole, the `sealed-secrets-controller` ClusterRoleBinding /
ServiceAccount / Services.

Two things need manual intervention.

1. The Deployment must be deleted before the first sync. The release manifest selects pods on
   `name: sealed-secrets-controller`, the chart on `app.kubernetes.io/{name,instance}`, and
   `spec.selector` is immutable — so the sync fails with `field is immutable` until the old object is
   gone:

   ```bash
   kubectl -n kube-system delete deployment sealed-secrets-controller
   ```

   ArgoCD recreates it on sync. The controller is briefly unavailable, which only means SealedSecrets
   are not unsealed during that window; already-created Secrets are owned by their SealedSecret
   resources and are unaffected.

2. Four RBAC objects are renamed and the originals are left behind as orphans (ArgoCD does not
   track them, so it will not prune them). Delete them once the sync is healthy:

   ```bash
   kubectl -n kube-system delete role sealed-secrets-key-admin sealed-secrets-service-proxier
   kubectl -n kube-system delete rolebinding sealed-secrets-controller sealed-secrets-service-proxier
   ```

> [!NOTE]
>
> **No re-sealing is required.** The chart runs the controller with
> `--key-prefix sealed-secrets-key`, which matches the existing `sealed-secrets-key*` secrets, so
> it picks up the same private keys. Those secrets are generated at runtime and are not part of
> the chart, so ArgoCD never manages (or prunes) them.

## Usage

Given a secret stored in the file `test-secret.yaml` (not committed to Git):

```bash
kubeseal -f test-secret.yaml -w test-secret-sealed.yaml --format=yaml
```

This will store the sealed secret in the `test-secret-sealed.yaml` file, which can be:

- Committed to Git
- Applied on the cluster (it contains a `SealedSecret` resource), which will result in the secret described in `test-secret.yaml` to be deployed

> [!NOTE]
>
> You can find test files in [here](../kubernetes/sealed-secrets/test/)

> [!WARNING]
>
> Secrets generated by Sealed Secrets have their lifecycle tied to the SealedSecret!
> Deleting the SealedSecret resource will delete the Secret too!

### Tip: SealedSecret resources

- `describe`ing the resource also shows the unseal status (whether it was possible to decrypt and apply the secret or not)
- Metadata is preserved, but **unencrypted**

### Tip: "importing" existing Secrets

Trying to deploy a SealedSecret that should create a Secret that already exists will result in errors when trying to unseal it.
To solve this, it is first required to add the following annotation:

```yaml
sealedsecrets.bitnami.com/managed: "true"
```

### Private Keys

To extract the private key(s):

```bash
kubectl get secret -n kube-system | grep sealed-secrets
# Note down secret name
kubectl get secret -n kube-system sealed-secrets-<random> -o yaml > sealed-secrets-key-backup.yaml
```

**Do NOT store this in git**.

Getting the public key:

```bash
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > kube-seal/pub-cert.pem
```

> [!NOTE]
>
> Key pairs are _renewed_ every 30 days (by default).
> This does **not invalidate** the old ones, but rather it only appends a new one to the set of used keys.
> Calling `kubeseal` will always use the latest key pair.

For disaster recovery, check [how to do a backup](https://github.com/bitnami/sealed-secrets#how-can-i-do-a-backup-of-my-sealedsecrets)

## Conventions

In this repository, the convention is:

- Secrets manifests are part of files named `*secret.yaml` or `*secrets.yaml`.
  These files are Git-ignored.
- SealedSecrets are part of files named `*secret-sealed.yaml` (not Git-itnored).

---

## Links

- [Sealed Secrets repo](https://github.com/bitnami-labs/sealed-secrets)
- [Medium article](https://medium.com/@gokulnath70/sealed-secrets-in-kubernetes-a-practical-guide-to-secure-secret-management-bd40d5bed988)
