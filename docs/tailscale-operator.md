---
id: tailscale-operator
author: Davide Macario
date: 2026-02-13
aliases: []
tags:
  - k3s
  - homelab
  - tailscale
---

# Setting up the Tailscale Kubernetes Operator

[Docs](https://tailscale.com/kb/1236/kubernetes-operator).

> [!CAUTION]
>
> Make sure you are running the open-source version of `tailscaled` (this is only the default on Linux machines).
> If not, it will not be possible to configure Kubectl to use the Tailscale API proxy.

First, edit the tailnet [policy file](https://login.tailscale.com/admin/acls/file), by adding tags for K8s and K8s operator.

```json
{
  // ...
  "tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"]
    "tag:k8s-readers": [], // Will be assigned to tailnet devices allowed to reach Kube API, see later section
  }
  // ...
}
```

Then, create an OAuth client in the [Trust credentials page](https://login.tailscale.com/admin/settings/trust-credentials), having as scope `Devices Core`, `Auth Keys`, and `Services` (all _write_), and as tag `tag:k8s-operator`.

> [!NOTE]
>
> The `Services` scope is required for proxying the Kube API server over Tailscale!!

Then, install the tailscale operator using Helm.
First, add the repository to the local Helm repositories:

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
```

Update the Helm cache:

```bash
helm repo update
```

> [!TIP]
>
> With Helm charts, it is possible to show the available configuration _values_ (i.e., the default `values.yaml` file) by running `helm show values <helm_chart>`.
>
> For example, to see all possible configuration values of the Tailscale operator, you can run `helm show values tailscale/tailscale-operator`.

Install the operator by passing the previously created credentials (OAuth client).

```bash
helm upgrade \
  --install \
  tailscale-operator \
  tailscale/tailscale-operator \
  --namespace=tailscale \
  --create-namespace \
  --set-string oauth.clientId="<OAauth client ID>" \
  --set-string oauth.clientSecret="<OAuth client secret>" \
  --set-string apiServerProxyConfig.allowImpersonation="true" \
  --set deployment.replicas=3 \
  --wait
```

> [!note]
>
> The `apiServerProxyConfig.allowImpersonation` value will be used for [setting up access to the kube API over Tailscale](#access-the-kubernetes-control-plane-using-an-api-server-proxy).

> [!TIP]
>
> If not using a `values.yaml` file to configure the chart, it is still possible to update
> the deployment without "resetting" the previous values passed via CLI by adding the
> `--reuse-values` argument in `helm upgrade`.
>
> Example:
>
> ```bash
> helm upgrade tailscale-operator tailscale/tailscale-operator --namespace tailscale --reuse-values --set operatorConfig.logging=info
> ```

You should now be able to see a node named "tailscale-operator" in your [Machines](https://login.tailscale.com/admin/machines) page.

> [!DANGER]
>
> By running
>
> ```bash
> helm get values tailscale-operator -n tailscale --all > ./kubernetes/tailscale-operator/values.yaml
> ```
>
> it is possible to write all values to file.
> Then, just update `values.yaml` and run
>
> ```bash
> helm upgrade tailscale-operator tailscale/tailscale-operator \
>   -n tailscale \
>   -f ./kubernetes/tailscale-operator/values.yaml
> ```
>
> to upgrade the operator in-place.
>
> Since the configuration of the operator contains secrets (`oauth.clientSecret`), though, it is
> recommended to remove the secret values before committing the file to Git.
> `

## Pre-creating a `ProxyGroup`

[Reference](https://tailscale.com/kb/1236/kubernetes-operator#optional-pre-creating-a-proxygroup).

Configuring an ingress/egress[^2] proxy using the default installation of the Kubernetes Operator results in a new tailnet device deployed as a `StatefulSet` over a single Pod.
The issue is that this is not really HA, resulting in downtime during upgrades.

We can create a multi-replica `ProxyGroup` (Tailscale Operator CRD - `proxygroups.tailscale.com`).

> [!IMPORTANT]
>
> This is not required.
> I personally only define `type: ingress` `ProxyGroup`s when I need them.

Manifest (see [./kubernetes/tailscale-operator/proxygroup-egress.yaml](./kubernetes/tailscale-operator/proxygroup-egress.yaml)):

```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyGroup
metadata:
  name: ts-proxies
spec:
  type: egress
  replicas: 3
```

Apply it with

```bash
kubectl apply -f ./kubernetes/tailscale-operator/proxygroup-egress.yaml
```

> [!TIP]
>
> The command to delete resources defined in a manifest, effectively "undoing" the contents of the
> manifest is: `kubectl delete -f path/to/manifest.yaml`

`ProxyGroup`s take some times to become ready.
You can wait for the one we created by running:

```bash
kubectl wait proxygroup ts-proxies --for=condition=ProxyGroupReady=true

# Until 'proxygroup.tailscale.com/ts-proxies condition met'
```

> [!TIP]
>
> Full `ProxyGroup` spec [here](https://github.com/tailscale/tailscale/blob/main/k8s-operator/api.md#proxygroup).
> It is possible to define it for `type:`: `egress`, `ingress`, `kube-apiserver`.

[^2]: Ingress: exposing a Kubernetes cluster workload to tailnet; Egress: exposing a Tailnet service to the workload.

## Access the Kubernetes control plane using an API server proxy

[Docs](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy).

Requirements:

- [x] **Kubernetes Operator** is installed
- [x] [HTTPS is enabled](https://tailscale.com/kb/1153/enabling-https#configure-https) for the tailnet
- [x] Access Control Policies allow devices and users to access the API server proxy devices on ports 80 and 443 over TCP:

  ```json
  "grants": [
    {
      "src": ["tag:k8s-readers"],
      "dst": ["tag:k8s"],
      "ip": ["tcp:80", "tcp:443"]
    }
  ]
  ```

- [x] Update `autoApprovers` in the tailnet policy file to let a `ProxyGroup` advertise Tailscale Services with tag `tag:k8s`:

  ```json
  "autoApprovers": {
    "services": {
      "tag:k8s": ["tag:k8s"],
    }
  }
  ```

> [!IMPORTANT]
>
> In order to be able to reach the Kube API from a specific Tailnet device, you must assign it the tag `tag:k8s-readers`.

Then, apply [this](./kubernetes/tailscale-operator/proxygroup-apiserver.yaml) manifest file to create a set of Tailscale devices acting as API server proxies (using 2 replicas).

```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyGroup
metadata:
  name: k3s-api # Assign a custom name!
spec:
  type: kube-apiserver
  replicas: 2
  tags: ["tag:k8s"]
  kubeAPIServer:
    mode: auth
```

You can wait for the `ProxyGroup` to be up by running:

```bash
kubectl wait proxygroup utrecht-apiserver --for=condition=ProxyGroupReady=true
```

> [!NOTE]
>
> We are deploying the API proxy in [auth mode](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy):
>
> > Auth mode: In auth mode, requests from the tailnet proxied over to the Kubernetes API
> > server are additionally impersonated using the sender's tailnet identity.
> > Kubernetes RBAC can then be used to configure granular API server permissions for
> > individual tailnet identities or groups.

Before moving forward, we should set up Tailscale ACL policies that allow us to filter traffic to our Kube API proxy based on specific tags/users.
For the full list of possible set-ups, refer to the [docs](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy#configuring-api-server-proxy-in-noauth-mode).

> [!IMPORTANT]
>
> The following steps will be used to set up ClusterRoles, which are user-facing roles used to regulate access at
> the Kubernetes API side (not a Tailscale thing!!).
> You can find the relevant documentation [here](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles).

1. Setting up access based on tailscale device [tags](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy#impersonating-kubernetes-groups-with-tagged-tailnet-nodes):

   ```bash
   kubectl create clusterrolebinding <role_name> --group="<tailscale_tag>" --clusterrole="<clusterrole>"

   # E.g.,
   kubectl create clusterrolebinding tailnet-readers --group="tag:k8s-readers" --clusterrole=view
   ```

2. Setting up access based on sender tailnet [user](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy#impersonating-kubernetes-users):

   ```bash
   kubectl create clusterrolebinding <role_name> --user="<tailscale_user_email>" --clusterrole="<clusterrole>"

   # E.g.,
   kubectl create clusterrolebinding dmacario-cluster-admin --user="dav.macario@gmail.com" --clusterrole=cluster-admin
   ```

To configure access to the Kube API using the Tailscale Operator API proxy, we need to configure `kubectl`.
Note down the URL of the `ProxyGroup` we just created, by running

```bash
kubectl get proxygroup <your.metadata.name> # `k3s-api` in my case
```

(`https://k3s-api.taila7b4c.ts.net` in my case), and run:

```bash
tailscale configure kubeconfig <proxygroup_url>
```

You should now be able to access your nodes by running:

```bash
# Do not include `https://`
kubectl --context=<proxygroup_url> get nodes
```

You can make this your default context by running:

```bash
kubectl config set-context <proxygroup_url>
```

## Expose Kubernetes cluster workload to your tailnet

2 possible approaches work for me:

1. If exposing a non-HTTP service, follow the [docs](https://tailscale.com/docs/kubernetes-operator/ingress).
   This will create a "registered" Tailscale service, with a dedicated tailscale IP.
2. If exposing HTTP services, follow the guide in [./k8s-tailscale-custom-dns.md](./k8s-tailscale-custom-dns.md), where I explain how to set up a "secondary" Traefik instance in the cluster that maps to a Tailscale IP, allowing you to define custom domain names for different applications (and use host-based routing).
