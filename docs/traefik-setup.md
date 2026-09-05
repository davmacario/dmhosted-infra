---
id: traefik-setup
author: Davide Macario
date: 2026-02-08
tags:
  - k3s
  - homelab
  - traefik
---

# Traefik Setup - K3s

The Ansible playbook to install the K3s cluster does not include any Ingress Controller, so we will install Traefik _from scratch_ using Helm.

## Installation

Requirements:

- K3s cluster is correctly set up using the Ansible playbook.
- Can successfully run `kubectl get nodes` from the manager host.
- `helm` is installed on the host managing the cluster.
  - [Installing Helm](https://helm.sh/docs/intro/install/)

First, create a namespace for Traefik:

```bash
kubectl create namespace traefik

# Check it was created successfully
kubectl get namespaces
```

Then, add the Traefik Helm repository:

```bash
helm repo add traefik https://helm.traefik.io/traefik
```

Update the local Helm repositories:

```bash
helm repo update
```

Install Traefik using the custom [values.yml](../kubernetes/traefik/values.yaml) file:

```bash
helm install --namespace=traefik traefik traefik/traefik --values=./kubernetes/traefik/values.yaml
```

> [!TIP]
>
> To get the default values, run `helm show values traefik/traefik`

> [!TIP]
>
> To uninstall Traefik in case any step does not work as expected, just run `helm uninstall traefik -n traefik`.

Also, pinging the IP should result in packets being rerouted to any of the hosts.

### Check

As a check, run:

```bash
kubectl get pods -n traefik  # Verify 3 pods are running Traefik (see custom values.yaml)
kubectl get svc -n traefik -o wide  # Verify external IP is MetalLB one, and the service is of type 'LoadBalancer'
```

Note that any traffic that will be sent to the virtual IP assigned to the Traefik service (of type `LoadBalancer`) will reach Traefik.

## Default security headers

A `default-headers` middleware sets HSTS, `X-Content-Type-Options`, `X-Frame-Options` and
`X-XSS-Protection` on every response.

Defining a `Middleware` object is not enough on its own: it does nothing until some IngressRoute
explicitly references it by name. To make it global, the object is created via the chart's
`extraObjects`, and then attached to the `websecure` **entrypoint** in the static config:

```yaml
# kubernetes/traefik/values.yaml
extraObjects:
  - apiVersion: traefik.io/v1alpha1
    kind: Middleware
    metadata:
      name: default-headers
    spec:
      headers: { ... }

ports:
  websecure:
    http:
      middlewares:
        - traefik-default-headers@kubernetescrd
```

An entrypoint middleware is prepended to the chain of **every** router on that entrypoint, no
matter which provider produced it - so it covers `IngressRoute` CRDs and plain `Ingress` objects
alike, and needs no per-route opt-in. Both Traefik installs declare it independently, so neither
depends on the other.

Verify:

```bash
kubectl get middleware -A | grep default-headers   # one per Traefik install
curl -sI https://whoami.internal.dmhosted.com | grep -i strict-transport-security
```

> [!WARNING]
>
> The qualified name is `<namespace>-<name>@kubernetescrd`, so the two installs reference
> **different** strings: `traefik-default-headers@kubernetescrd` and
> `traefik-tailscale-default-headers@kubernetescrd`. Moving either release to another namespace
> silently breaks the reference, and every router on `websecure` will start erroring — keep
> `ports.websecure.http.middlewares` in sync with the release namespace.

> [!IMPORTANT]
>
> This applies to _every_ route on `websecure`, including the Traefik dashboards. In particular
> `customRequestHeaders.X-Forwarded-Proto: https` **overwrites** the incoming header for all
> backends. That is correct here because `websecure` is TLS-only, but it means backends can no
> longer see the original scheme.

## Setting up dashboard access

> [!CAUTION]
>
> Even though authenticated, this is not recommended for publicly-exposed Traefik instances.
>
> See [how to expose Traefik dashboard over VPN](#setting-up-dashboard-access-from-vpn).

By default, the Traefik dashboard is not authenticated.
Indeed, exposing it without setting up proper authentication is **extremely discouraged**.

We will make use of a Traefik `middleware` CRD to provide basic auth.
This setup is not the most secure, but it is definitely much better than no auth.

> TODO: improve on authentication

Let's create the Traefik dashboard credentials.

Make sure `htpasswd` is installed on your system (if not, run `apt-get install apache2-utils`, or an equivalent command for your package manager).
Then, decide on a `<username>` and `<password>`, then run:

```bash
htpasswd -nb <username> <password> | openssl base64
```

This will output a Base64-encoded secret, which we will plug into [../kubernetes/traefik/dashboard/dashboard-secret.yaml](../kubernetes/traefik/dashboard/dashboard-secret.yaml), in `data:users:`.

Then, apply the manifest:

```bash
kubectl apply -f ./kubernetes/traefik/dashboard/dashboard-secret.yaml
```

To check the secret was created, run

```bash
kubectl get secrets -n traefik
```

> [!NOTE]
>
> You will probably also see Helm secrets, this is normal.

Keep in mind: we set up the dashboard correctly, however, we haven't defined a route to the dashboard.
To do so, we will use an `IngressRoute` resource, defined in [../kubernetes/traefik/dashboard/ingress-internal.yaml](../kubernetes/traefik/dashboard/ingress-internal.yaml).

> [!IMPORTANT]
>
> If you look at `routes[0].match:`, you can see that the traffic should come on either `traefik.local.dmhosted.io` (a DNS name that should resolve to `192.168.178.20`, the LB IP assigned to Traefik), or the LB IP itself, `192.168.178.20`.
>
> To enable resolution of `traefik.local.dmhosted.io`, you can temporarily edit `/etc/hosts`.

Note that this `IngressRoute` needs the definition of a middleware (see [../kubernetes/traefik/dashboard/middleware.yaml](../kubernetes/traefik/dashboard/middleware.yaml)) that applies the `traefik-dashboard-auth` secret we just created to the route (effectively triggering auth request when connecting).

```bash
kubectl apply -f ./kubernetes/traefik/dashboard/middleware.yaml
kubectl apply -f ./kubernetes/traefik/dashboard/ingress-internal.yaml
```

Check the `IngressRoute` was created:

```bash
kubectl get ingressroute -n traefik
```

We can now log into the dashboard by visiting <https://traefik.local.dmhosted.io>, or <https://192.168.178.20> and entering username and password.

### Setting up dashboard access from VPN

This section assumes that a secondary Traefik installation was deployed in your cluster, allowing to expose services within a VPN (see [guide](./k8s-tailscale-custom-dns.md)).

The issue with the setup described in [previous section](#setting-up-dashboard-access) is that once we expose services publicly (over Cloudflare tunnel - TODO), we will route traffic to the main Traefik instance's endpoint.
This means that, if we expose its dashboard via the same endpoint, we will make it possible to reach it from the public internet.
The basic-auth middleware is not enough of a security feature for me, and, since I also have a secondary Traefik instance running to expose services over my VPN, I will be using it to expose the main Traefik's dashboard.

What follows are the steps and explainations on how to achieve this.

First of all, Traefik (installed with Helm), exposes the dashboard on port 8080.
The issue is, by default, the dashboard is not reachable via port 8080 of a Traefik pod (HTTP 404),
but only via a "_meta_" service called `api@internal` (see [dashboard ingressroute](../kubernetes/traefik/dashboard/ingress-internal.yaml)),
which can only be targeted by `IngressRoute`s that use that specific Traefik instance[^1].

[^1]: Not 100% sure about how `api@internal` works, to be honest. The docs probably explain it better.

Therefore, we have to tweak the installation settings, i.e., the [Helm values](../kubernetes/traefik/values.yaml),
to actually expose the dashboard on the port.
This is done by adding the following to the values file:

```yaml
api:
  dashboard: true # This is a default value
  insecure: true # This MUST be set
```

The name `insecure` is not a concern - the dashboard will not be exposed in an _insecure_ way.
It is just there to remind users to make sure to secure the access to the dashboard, which is something
that we will do (VPN only + basicauth).

Then, apply the changes:

```bash
# From <repo_dir>/kubernetes/traefik
helm upgrade --install traefik traefik/traefik -n traefik --values ./values.yaml
```

Then, to verify the changes work, run the following commands to HTTP GET the dashboard:

```bash
# Note down the pod ID
kubectl get pods -n traefik

kubectl exec -n traefik <pod-id> -- wget -qO- http://localhost:8080/dashboard/
```

If this returns valid HTML and no HTTP error, the dashboard is now successfully exposed on port 8080.

Next, we will create a K8s `Service` + `IngressRoute` + `Middleware` \[+ `Certificate`\] to expose the dashboard using the Tailscale Traefik instance.

The `Service` will have to select the right pod(s), and for this we will use labels.
First, get the labels of your Traefik pods:

```bash
kubectl get pods -n traefik --show-labels
```

In particular, note down the values of:

- `app.kubernetes.io/instance` (`traefik-traefik`)
- `app.kubernetes.io/name` (`traefik`)

as we will use these.

The `Service` will be defined as follows:

```yaml
# Custom service exposing the dashboard of the "local" traefik, in traefik ns
apiVersion: v1
kind: Service
metadata:
  name: traefik-primary-dashboard
  namespace: traefik
spec:
  selector: # Labels from traefik pod(s)
    app.kubernetes.io/instance: traefik-traefik
    app.kubernetes.io/name: traefik
  ports:
    - name: dashboard
      port: 8080
      targetPort: 8080
  type: ClusterIP
```

Next, we will need an `IngressRoute` provisioned using the Tailscale Traefik instance.

First, though, we will do a QoL improvement for the URL of the dashboard.

By default, the dashboard is exposed at the `/dashboard` endpoint.
Since we will create a single domain for the dashboard, ideally we would like to access it at `/`.
To fix this, we can use the `middlewares.traefik.io` CRD (part of Traefik) to create a _redirect_.
Here is the definition:

```yaml
# Redirect `/` to `/dashboard`
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: traefik-dashboard-redirect
  namespace: traefik
spec:
  redirectRegex:
    regex: ^https://([^/]+)/?$
    replacement: https://${1}/dashboard/
    permanent: true
```

Next, we are finally ready to deploy the `IngressRoute`:

```yaml
# Expose 'local' Traefik dashboard to VPN
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-primary-dashboard-tailscale
  namespace: traefik
  annotations:
    kubernetes.io/ingress.class: traefik-tailscale
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`traefik-primary.internal.dmhosted.com`)
      kind: Rule
      middlewares:
        - name: traefik-dashboard-basicauth
          namespace: traefik
        - name: traefik-dashboard-redirect
          namespace: traefik
      services:
        - name: traefik-primary-dashboard
          port: 8080
  tls:
    secretName: traefik-primary-internal-dmhosted
```

Notice that this assumes a certificate was created and stored in the `traefik-primary-internal-dmhosted` secret.

Also, we are still using the `traefik-dashboard-basicauth` middleware created in [previous section](#setting-up-dashboard-access).

Once these resources are created (and the cert is provisioned), we will be able to reach the dashboard at the
`traefik-primary.internal.dmhosted.com` endpoint, effectively only accessible from the VPN

## Updating Traefik

Updates are still going to be done using Helm.

1. Refresh Helm charts:

   ```bash
   helm repo update traefik
   ```

2. [Optional]: modify your `values.yaml` file
3. Deploy updated version:

   ```bash
   helm upgrade traefik traefik/traefik -n traefik --values ./kubernetes/traefik/values.yaml
   ```

## Ingress vs (traefik) IngressRoute

Traefik can be used in Kubernetes both via its own CRD (`IngressRoute` provider), and via the kubernetes `Ingress` provider (and even with Gateway).

Typically, the main reason to choose the default `Ingress` is when we may want to switch between different `IngressController`s (e.g., Traefik/Nginx).
`IngressRoute` is generally easier to set up.

See [Nginx Ingress](../kubernetes/nginx/ingress.yaml) and [Nginx IngressRoute](../kubernetes/nginx/ingressroute.yaml) for a comparison.

## Issuing trusted certificates - cert-manager

Traefik would store certificates in persistent volumes, which is not the best.

Using [cert-manager](https://cert-manager.io/) allows to store the certificates in `etcd`, as Kubernetes Secrets.
Additionally, it is very convenient, as it takes care of rotation as well.

### Installing cert-manager

We will follow the [official installation steps](https://cert-manager.io/docs/installation/), and we will use Helm.

Installing from chart (with custom values) - version 1.19.2:

```bash
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.19.2 \
  --namespace cert-manager \
  --create-namespace \
  --values ./kubernetes/cert-manager/values.yaml
```

### Issuer configuration

Issuers are CAs that create and sign certificates.

In cert manager, we can use `Issuer` and `ClusterIssuer` resources (CRDs).
`Issuers` are limited to individual namespaces, while the `ClusterIssuer` is cluster-spaced.

We will use the Cloudflare CA.

First, we need to create a Kubernetes Secret containing our cloudflare token (with Edit Zone.DNS permissions).
The file will have to look like:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-token-secret
  namespace: cert-manager
type: Opaque
stringData:
  api-token: <your_cf_token>
```

Then apply it:

```bash
kubectl apply -f kubernetes/cert-manager/issuers/secret-cf-token.yaml
```

Then, we can create our `ClusterIssuer`, using the secret just created.
We will first use the letsencrypt "staging" server (to prevent API throttling in the "prod" one), which will create certs

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cloudflare-clusterissuer
spec:
  acme:
    email: dav.macario@gmail.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: cloudflare-clusterissuer-staging
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-token-secret
              key: api-token
```

Observations:

- `server:` is the "staging" one
- In `solvers[0].cloudflare.apiTokenSecretRef`, we are referencing the secret we created before
  - `name`: is the kube resource name
  - `key`: is the secret key as defined in the secret itself

Then, apply it:

```bash
kubectl apply -f kubernetes/cert-manager/issuer/cloudflare-clusterissuer-staging.yaml
```

You can confirm it was created successfully by running:

```bash
kubectl get clusterissuers.cert-manager.io # NOTE: no --namespace
```

### Creating certificates to associate to Ingress/IngressRoutes

Certificates are created with Kuberneter CRDs of type `certificates.cert-manager.io`, such as (see [nginx/certificate.yaml](../kubernetes/nginx/certificate.yaml)):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nginx-ingressroute-certificate
  namespace: nginx
spec:
  # This is the name of the Kube secret where the cert will be stored
  secretName: nginx-certificate-secret
  issuerRef: # Reference cluster issuer
    name: cloudflare-clusterissuer
    kind: ClusterIssuer
  dnsNames: # Specify DNS names for which the cert will be valid (see nginx ingressroute hosts)
    - nginx.local.dmhosted.com
```

Make sure the cert `dnsNames` includes the DNS(s) FQDN for which it is created.

> [!NOTE]
>
> Certificates are not cluster-scoped (unlike `ClusterIssuer`s).
> Make sure to create them in the correct namespace.

Applying this will create the secret containing the certificate.

> [!NOTE]
>
> Cert creation takes a while.
> You may have to wait some time before `READY` is True when running `kubectl get certificates.cert-manager.io -n nginx`.

Now, to attach the cert to the existing IngressRoute object, just add a `spec.tls` section like so:

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nginx-ingressroute
  namespace: nginx
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`nginx.local.dmhosted.com`)
      kind: Rule
      services:
        - name: nginx
          port: 80
    - match: Host(`nginx.internal.dmhosted.com`)
      kind: Rule
      services:
        - name: nginx
          port: 80
  tls:
    secretName: nginx-certificate-secret
```

Deploying the updated IngressRoute will allow it to use the cert!

> [!TIP]
>
> Once you have ensured that the deployment works, you can switch to the non-staging Let's Encrypt issuer.

Now, nginx will be accessible with a valid TLS cert!

---

## Links

- [Christian Lempa video](https://youtu.be/vJweuU6Qrgo?si=1CrRBo18DIgzfdcT)
