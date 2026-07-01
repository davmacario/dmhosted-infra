---
id: argocd
author: Davide Macario
date: 2026-06-18
aliases: []
tags:
  - homelab
  - cicd
---

# ArgoCD

ArgoCD is a tool used to automate deployment and lifecycle of applications running on a Kubernetes cluster by following **GitOps**[^1] best practices.

[^1]: _GitOps_ refers to the practice of using Git repositories as source of truth to define the desired application/infrastructure state.

## Installation

To install ArgoCD on K8s:

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> [!NOTE]
>
> Will also work for upgrading

To install the CLI (MacOS):

```bash
brew install argocd
```

For alternative installation methods, see [here](https://argo-cd.readthedocs.io/en/stable/cli_installation/).

### Installation and patching

To move towards GitOps, I decided to use Kustomize to manage the application.
This is because all the configuration of ArgoCD can be done declarative using a mix of ConfigMaps (and patches to them), and CRDs.

This method allows to easily manage the settings and add new apps to ArgoCD, including ArgoCD itself.
Also, this allows to skip the manual steps done [here](#exposing-argocd).

See the [argocd directory](../kubernetes/apps/argocd/) for the setup.

You can deploy the stack by running:

```bash
make all
```

> [!IMPORTANT]
>
> The contents of the `argocd-secret` Secret are fully managed by ArgoCD, so we don't need to handle them!
> Passwords and API keys should be configured from the UI or via the `argocd` CLI.

## Exposing ArgoCD

> [!NOTE]
>
> This is automatically taken care of if using [Kustomize to install ArgoCD](#installation-and-patching).

The manifest also creates a _Service_ (of type _ClusterIP_), called `argocd-server`.
We can expose this service using a Traefik _IngressRoute_, with a certificate from CertManager.

Before doing so, however, we need to deactivate SSL termination from the ArgoCD Server, by editing the _ArgoCD Deployment_:

```bash
kubectl edit -n argocd deployments.apps argocd-server
```

And setting:

```yaml
- args:
    - /usr/local/bin/argocd-server
    - --insecure # <-- this
```

In the ArgoCD Server container definition.

> [!TIP]
>
> While we are at it, might as well set the `resources:` section.

Then, we can define the _IngressRoute_ as follows.
Note that ArgoCD exposes both an HTTPS and a gRPC (over TCP) interface, and it is important to route both.

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: traefik-tailscale
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`argocd.internal.dmhosted.com`)
      priority: 10
      services:
        - name: argocd-server
          port: 80
    - kind: Rule
      match: Host(`argocd.internal.dmhosted.com`) && Header(`Content-Type`, `application/grpc`)
      priority: 11
      services:
        - name: argocd-server
          port: 80
          scheme: h2c
  tls:
    secretName: argocd-server-internal-cert
```

See [here](../kubernetes/apps/argocd/ingress.yaml) for the full manifest (including the _Certificate_).

## First login

Following [previous section](#exposing-argocd), the UI should be accessible at `https://argocd.internal.dmhosted.com`.

The default credentials are:

- Username: `admin`
- Password: stored in the secret `argocd-initial-admin-secret`. Can be retrieved via the CLI:

  ```bash
  argocd admin initial-password -n argocd
  ```

After the first login, head to "User Info" > "Update password", and update the password.

Then, we can delete the secret:

```bash
kubectl delete -n argocd secret argocd-initial-admin-secret
```

After this, log into the ArgoCD server via the CLI:

```bash
argocd login argocd.internal.dmhosted.com
```

And supply the username (`admin`), and the new password.

To be able to manage the current cluster, make sure that `https://kubernetes.default.svc` is listed when running

```bash
argocd cluster list
```

> [!TIP]
>
> Using `argocd cluster add <CONTEXTNAME>`, where `CONTEXTNAME` is one of the contexts listed when running
> `kubectl config get-contexts -o name`, i.e., one of the clusters configured in your kubeconfig.

## Using ArgoCD

### Create an application from the CLI

> [!DANGER]
>
> Discouraged - follow [declarative setup guide](#declarative-setup).

First, set the default context for Kubectl to `argocd`.

```bash
kubectl config set-context --current --namespace=argocd
```

Then, given a Git repository, you can configure it as app:

```bash
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
```

The above command will deploy the "Guestbook" example application from the ArgoCD example apps.
The `--path` is also the name used to reference the app.

To see the status, run:

```bash
argocd app get guestbook
```

Sample output:

```text
Name:               guestbook
Server:             https://kubernetes.default.svc
Namespace:          default
URL:                https://10.97.164.88/applications/guestbook
Repo:               https://github.com/argoproj/argocd-example-apps.git
Target:
Path:               guestbook
Sync Policy:        <none>
Sync Status:        OutOfSync from  (1ff8a67)
Health Status:      Missing

GROUP  KIND        NAMESPACE  NAME          STATUS     HEALTH
apps   Deployment  default    guestbook-ui  OutOfSync  Missing
       Service     default    guestbook-ui  OutOfSync  Missing
```

The initial status is `OutOfSync`.
To force sync (and deploy the app), run:

```bash
argocd app sync guestbook
```

This command will pull the repo contents, and apply the manifests.

### Declarative setup

It is possible to configure ArgoCD _applications_, i.e., apps deployed on the cluster via ArgoCD, using `Application` CRDs.

The CRD's API defines, at a high level:

- `source`: reference to the desired state in Git (a repo + tag/ref + path)
- `destination`: reference to the target cluster + namespace

#### Configuring access to a repository (github)

Assuming the repo on which you keep the manifests/configuration for your K8s apps is private, we need to set up credentials to access it.

First, we need to create a secret (`github-repo-creds-secret.yaml`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-repo-credentials
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  username: x-token
  password: github_pat_xxxx
  type: git
  url: https://github.com/davmacario/dmhosted-infra
```

Where the value of `password` is a fine-grained GitHub token with read-only access on the repo.

Then, seal it:

```bash
kubeseal -f github-repo-creds-secret.yaml -w github-repo-creds-secret-sealed.yaml --format=yaml
```

and add the sealed secret file in the `resources` section of the [Kustomization](../kubernetes/apps/argocd/kustomization.yaml).

#### Manifest-only kube workloads

> Taking [Sparkyfitness](../kubernetes/apps/sparkyfitness) as reference.

Definition of the Application CRD:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sparkyfitness
  namespace: argocd
spec:
  project: default  # Not relevant for now
  source:
    repoURL: https://github.com/davmacario/dmhosted-infra
    targetRevision: HEAD
    path: kubernetes/apps/sparkyfitness
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
```

#### Helm-based kube workloads

#### Kustomize-based kube workloads

Example: ArgoCD

```yaml

```

## App-Of-Apps Pattern

In my cluster, I went with an `app-of-apps` pattern.

What this means is, I have defined a "main" `root` Application (defined [here](../kubernetes/root-app.yaml)), which "watches" the [argocd-apps](../kubernetes/argocd-apps/) directory, which in turn contains the definition of other Applications.

This way, to enroll/deploy a new application, it's enough to create a YAML for the Application resource and add it in the argocd-apps directory, so that ArgoCD can pick it up.

## Configuring ArgoCD

It is best to use a declarative setup for configuring the settings, as the default deployment for the Server does not use any persistent storage.
Everything is configured using a ConfigMap called `argocd-cm`.

The customizations can be added to [argocd-cm-patch.yaml](../kubernetes/apps/argocd/argocd-cm-patch.yaml), and deployed using Kustomize.

---

## Links

- [Official ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/)
- [Exposing ArgoCD with Traefik IngressController](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#traefik-v30)
