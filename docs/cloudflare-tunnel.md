---
id: cloudflare-tunnel
author: Davide Macario
date: 2026-04-07
tags:
  - k3s
  - cloudflare
  - homelab
---

# Cloudflare Tunnel for Ingress K8s Traffic

Goal: setting up Cloudflare Tunnel for sample application ("whoami"), making it accessible from the public internet without needing to open ports on the router.

## Sample application: 'Whoami'

See [whoami directory](../kubernetes/apps/whoami).

This web application simply returns information about the client.

## Cloudflare tunnel setup

Requirement: [install cloudflared](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/) on your local computer.
It is a CLI to manage some Cloudflare services, including tunnels.

Then, log in by running:

```bash
cloudflared tunnel login
```

### Kubernetes resources

See [cloudflare-tunnel directory](../kubernetes/cloudflare-tunnel/).

First, create the `cloudflare` [namespace](../kubernetes/cloudflare-tunnel/namespace.yaml).

Then, run the following to create a new tunnel:

```bash
cloudflare tunnel create <tunnel-name>
```

In my case, the tunnel is `k3s-traefik`.

> [!NOTE]
>
> This creates a _**locally-managed tunnel**_ (i.e., its config will not be stored at Cloudflare's side, but in the cluster).
>
> Also, the exact configuration for this setup is not documented on the official websites, as it is a weird hybrid that:
>
> - uses a tunnel token (like remotely-managed tunnels)
> - with a custom config file (like locally-managed tunnels)

Then, navigate to the Cloudflare dashboard.

- In the "Networking" > "Tunnels" section, you should see your new tunnel
- Navigating to the "Domains" section, and then to "SSL/TLS", you should:
  - Configure "Full encryption" from the "Overview" section
  - In the "Edge certificates" section, make sure that certs for your domain (and the `*.<your-domain>`) have been produced.

> [!NOTE]
>
> Due to limitations in the free plan, we will only be able to generate valid certs for URLs using your domain as the _top-level_ domain.
> In other words, `test.mydomain.com` will have valid certs, while `test.aaa.mydomain.com` will not!

This will also create a JSON file at `$HOME/.cloudflared/<tunnel-id>.json`.
We can import it as a secret in K8s by running:

```bash
kubectl create secret generic tunnel-credentials -n cloudflare --from-file="$HOME/.cloudflared/<tunnel-id>.json"
```

Next, let's also generate a _tunnel token_:

```bash
cloudflared tunnel token <tunnel-name>
```

Let's copy it and create a secret:

```bash
kubectl create secret generic tunnel-token -n cloudflare --from-literal=token="<your-token-here>"
```

> [!WARNING]
>
> This setup is **undocumented**.
> It may break in future releases of `cloudflared`.

Then, create the [ConfigMap](../kubernetes/cloudflare-tunnel/configmap.yaml):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: cloudflare
data:
  config.yaml: |
    # Name of the tunnel you want to run
    tunnel: k3s-traefik
    # The location of the secret containing the tunnel credentials
    credentials-file: /etc/cloudflared/creds/credentials.json
    # General purpose TCP routing for the network
    warp-routing:
      enabled: false
    # Serves the metrics server under /metrics and the readiness server under /ready
    metrics: 0.0.0.0:2000
    # Autoupdates applied in a k8s pod will be lost when the pod is removed or restarted, so
    # autoupdate doesn't make sense in Kubernetes. However, outside of Kubernetes, we strongly
    # recommend using autoupdate.
    no-autoupdate: true
    # The `ingress` block tells cloudflared which local service to route incoming
    # requests to. For more about ingress rules, see
    # https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/ingress
    ingress:
      - hostname: "*.dmhosted.com"
        service: "https://traefik.traefik.svc.cluster.local:443"
        originRequest:
          noTLSVerify: true
      # This rule matches any traffic which didn't match a previous rule, and responds with HTTP 404.
      - service: http_status:404
```

The `config.yaml` (which will be passed to cloudflared) defines routing from the tunnel to destinations within the cluster.
In this case, since the goal is to route all tunnel traffic through Traefik, we are just pointing the `*.dmhosted.com` routes to
the Traefik service in our cluster, using the HTTPS endpoint.

The `noTLSVerify` option is needed because the cert exposed by the Traefik service (which is not the one that will be used by the apps) is self-signed, and in any case traffic from the `cloudflared` pods towards Traefik will stay inside the cluster.

Next, create the [Deployment](../kubernetes/cloudflare-tunnel/deployment.yaml):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared-deployment
  namespace: cloudflare
spec:
  replicas: 2
  selector:
    matchLabels:
      pod: cloudflared
  template:
    metadata:
      labels:
        pod: cloudflared
    spec:
      securityContext:
        sysctls:
          # Allows ICMP traffic (ping, traceroute) to resources behind cloudflared.
          - name: net.ipv4.ping_group_range
            value: "65532 65532"
      containers:
        - image: cloudflare/cloudflared:2026.5.0
          name: cloudflared
          # NOTE: can use token with config + credentials files!
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: tunnel-token
                  key: token
          command:
            # Configures tunnel run parameters
            - cloudflared
            - tunnel
            - --no-autoupdate
            - --loglevel
            - info
            - --metrics
            - 0.0.0.0:2000
            - --config
            - /etc/cloudflared/config/config.yaml
            - run
          livenessProbe:
            httpGet:
              path: /ready
              port: 2000
            failureThreshold: 1
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            limits:
              cpu: "100m"
              memory: "128Mi"
            requests:
              cpu: "100m"
              memory: "128Mi"
          volumeMounts:
            - name: config
              mountPath: /etc/cloudflared/config
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: cloudflared-config
            items:
              - key: config.yaml
                path: config.yaml
```

Most of this file was grabbed from the [official docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/#5-create-pods-for-cloudflared).

The issue with the official docs is that I want to manage the tunnel configuration locally, i.e., with the YAML file created in the previous ConfigMap, as it is better for IaC and automation (no need to clicky-clicky in the Cloudflare console).

The main differences compared to the docs are:

- Mounted the ConfigMap at `/etc/cloudflared/config[/config.yaml]`
- Referenced the configuration in the `--config` CLI argument
- (Added resource requests/limits)

This set up is not documented, as in the docs there is no mention of using a token to manage locally-managed tunnels.

> Actually, in my initial experiments, I was trying to use the [Helm chart](https://github.com/cloudflare/helm-charts/tree/main/charts/cloudflare-tunnel),
> which mounts the tunnel credentials file (`$HOME/.cloudflared/<tunnel-id>.json`) as secret file, alongside the `config.yaml`.
> This did not work because the container would crash due to a missing `cert.pem` (which I assume should have been the one
> that's normally found in `$HOME/.cloudflared/cert.pem`).
> Removing that secret and instead defining the `TUNNEL_TOKEN` secret solved it for me, but I don't know why.

From the Cloudflare dashboard we should then see our tunnel up and running.
From now on, any service exposed via the main Traefik instance will be reachable over the tunnel (provided the route is properly configured).

### External DNS setup for cloudflare

We will provide an alternative installation to `External DNS` from the one explained in [k8s-tailscale-custom-dns.md](./k8s-tailscale-custom-dns.md#external-dns-for-adguardhome).

We will use the `cloudflare` provider for external-dns.
The configuration can be found in the [values file](../kubernetes/external-dns/values-cloudflare.yaml).

Notice that it needs a secret to exist, containing an API token for Cloudflare, as it will be modifying DNS records for us.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-key
  namespace: cloudflare
stringData:
  email: <your-email>
  apiKey: <your-API-key>
```

Then, install the chart with:

```bash
helm upgrade --install external-dns-cloudflare external-dns/external-dns --namespace cloudflare --values ./kubernetes/external-dns/values-cloudflare.yaml
```

### Monitoring

We will install a ServiceMonitor resource (see [monitoring setup](./monitoring-setup-prometheus-grafana.md) for reference) to tell Prometheus to scrape the metrics exposed on port 2000 by the cloudflared pods.

See [manifest](../kubernetes/cloudflare-tunnel/monitoring.yaml) for the following resources:

- `Service` for port 2000 (exposed via [Deployment](../kubernetes/cloudflare-tunnel/deployment.yaml))
- `ServiceMonitor`: configures the existing Prometheus instance (see [kube-prometheus stack values](../kubernetes/monitoring/values.yaml)), which is identified by `metadata:labels`, to scrape the Service above.
  - Additionally, it propagates the labels `app` and `tunnel-name` attached to the Service (useful for grouping metrics, as we are running cloudflared in HA).

Once the manifest is applied, we will start to receive metrics from cloudflared.

---

## Links

- [Cloudflare docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/)
