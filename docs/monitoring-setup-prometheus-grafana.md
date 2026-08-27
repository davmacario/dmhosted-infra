---
id: monitoring-setup-prometheus-grafana
author: Davide Macario
date: 2026-02-28
tags:
  - homelab
  - k3s
  - monitoring
  - observability
---

# Monitoring Setup with Prometheus and Grafana

This guide explains the installation steps and configuration of the [Kube-Prometheus Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack),
used as monitoring and observability setup in my Kubernetes cluster.

## Tech stack

- Prometheus
- Grafana
- Alertmanager

### Prometheus

Backbone of the setup.

It scrapes the metrics endpoints and/or exporters of all applications and stores the metrics in a time-series DB.

Then, it exposes an API (w/ GraphQL) through which other applications (Grafana, in our case) can query the data.

Prometheus can also be configured to have alerts, which are triggered based on the scraped measurements.
Alerts can then be pushed to Alertmanager.

It can also be enabled to perform service discovery (in Kubernetes).

### Grafana

Client for Prometheus, used to display the data in custom Dashboards.

### Alertmanager

Component that is used to handle, filter, and propagate alerts coming from Prometheus.

## Installation

Installation will be done via Helm.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Show values:

```bash
# This will store the default values in a file
helm show values prometheus-community/kube-prometheus-stack > default-values.yaml
```

After configuring values to your preference in a `monitoring/values.yaml` file, deploy the stack in the `monitoring` namespace using:

```bash
helm install prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --values monitoring/values.yaml
```

Take note of the returned text: it instructs on how to get the default password.

### Created resources

In my installation (no custom `values.yaml`), here are some notable resources created:

- `prometheus-stack-grafana` service: Service in front of Grafana
- `prometheus-operated` service: Service in front of Prometheus (headless)
- Pods:
  - `alertmanager-prometheus-stack-kube-prom-alertmanager-0`: alertmanager
  - `prometheus-prometheus-stack-kube-prom-prometheus-0`
  - `prometheus-stack-grafana-665db8cc57-z8zgc`
  - `prometheus-stack-kube-prom-operator-56857c79d4-rgpmr`
  - `prometheus-stack-kube-state-metrics-6657c57b48-6jkmb`
  - `prometheus-stack-prometheus-node-exporter-lqn2j`
  - `prometheus-stack-prometheus-node-exporter-ngfnm`
  - `prometheus-stack-prometheus-node-exporter-z7jmm`

You can log into Prometheus via port forwarding, as it is not normally exposed:

```bash
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
```

Most importantly, the Helm chart deployed the Prometheus operator, which includes several CRDs, such as `ServiceMonitor`.

### Exposing Grafana

See [grafana-ingressroute.yaml](../kubernetes/monitoring/grafana-ingressroute.yaml).
Just deploy the resources using `kubectl apply`.

## Scraping metrics from deployed applications

In order to automatically have Prometheus scrape for metrics from deployed applications, we first need to make sure that the app exposes its metrics (i.e., it is **instrumented**).

Then, create a `ServiceMonitor` resource that:

- Points to the metrics endpoint of a `Service` fronting your application
- Has a label matching the auto-discovery one set for the deployed `Prometheus`
  - To find it, run

    ```bash
    kubectl get prometheus -n monitoring -o yaml
    ```

    and look for the setting `serviceMonitorSelector`:

    ```yaml
    serviceMonitorSelector:
      matchLabels:
        release: prometheus-stack
    ```

    then, you have to set that label in your `ServiceMonitor` object's metadata.

> [!TIP]
>
> To verify that discovery was successful, log into Prometheus' UI by running:
> `kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090`
> and navigating to <http://localhost:9090> in your browser.
> In the "Status > Service Discovery" panel, you should see your application listed.
> If it is not, something went wrong.

### Setting up Longhorn monitoring

Most apps deployed with a Helm chart will optionally take care of creating a `ServiceMonitor` for you.
Longhorn is one of those apps.

In order to enable the `ServiceMonitor`, just add the following to the [values.yaml file](../kubernetes/longhorn/values.yaml):

```yaml
metrics:
  serviceMonitor:
    enabled: true
    additionalLabels:
      release: prometheus-stack # Should match your Prometheus' matchLabels
```

## How it works - Prometheus Operator

### Prometheus Operator

The Prometheus Operator is the core component of the Kube-Prometheus stack.

At its core, it is a SW component that allows to configure Prometheus by means of CRDs, instead of prometheus YAML files.

The available CRDs include:

- `Prometheus`: full Prometheus deployment and configuration
- `PrometheusAgent`: like Prometheus, but in agent mode (no local persistent storage)
  - Especially used in Cloud deployments, where Prometheus (DB) is an external service (e.g., Amazon Managed Prometheus)
- `Alertmanager`: defines an Alertmanager cluster
- `ThanosRuler`: Thanos Ruler instance for evaluating rules against Thanos-backed store
- `ServiceMonitor`: configuration for Prometheus to scrape a specific `Service` for Prometheus-compatible metrics
  - Associated to a specific `Prometheus` resource
- `PodMonitor`: same as `ServiceMonitor`, but for individual pods
- `Probe`: black-box probing for resources like `Ingress`
- `ScrapeConfig`: low-level, raw Prometheus scrape config (advanced)
- `PrometheusRule`: defines recording rules and alerting rules for Prometheus (same format as Prometheus rule-file)
- `AlertmanagerConfig`: defines alert routing, receivers, and inhibition rules (scoped by namespace)

### Prometheus configuration

Prometheus is deployed using the `prometheuses.monitoring.coreos.com` CRD, used to create `Prometheus` resources.

Get the name of the deployed `Prometheus` by running:

```bash
kubectl get -n monitoring prometheus
```

```text
NAME                                    VERSION   DESIRED   READY   RECONCILED   AVAILABLE   AGE
prometheus-stack-kube-prom-prometheus   v3.10.0   1         1       True         True        22d
```

> [!NOTE]
>
> There are 2 possible strategies to set up metric collection with Prometheus:
>
> - One "global" Prometheus instance
> - One Prometheus instance per namespace
>
> The 1st one is recommended for small clusters, as it is difficult to manage if the number of monitored apps increases.
>
> The second one is the recommended approach for production environments, where it is desirable to isolate instances of Prometheus
> to their namespace.
> This allows delegating maintenance and configuration (incl. alerts) to different namespaces, and, usually, different teams.
>
> Other valid approaches could be those of separating Prometheus instances based on the type of workloads (apps vs. cluster).
>
> Make sure to correctly add the new Prometheus instances as data sources Grafana (you'll need persistent data in Grafana).

An important configuration value for Prometheus is the `serviceMonitorSelector`:

```yaml
# from `k get prometheus -n monitoring -o yaml`:
# ...
serviceMonitorSelector:
  matchLabels:
    release: prometheus-stack
```

this is the label we need to assign to CRDs (e.g., `ServiceMonitor`s), so that they are automatically discovered by our Prometheus.

#### Configuring Prometheus to scrape targets

Prometheus needs to be configured to scrape specific endpoints.
To achieve this, the chart installs the `ServiceMonitor` CRD.

A `ServiceMonitor` specifies how to scrape Prometheus endpoints from a defined `Service` resource, allowing to retrieve metrics.

By default, the Helm chart creates a number of `ServiceMonitor` resources, which can be seen by running:

```bash
kubectl -n monitoring get servicemonitors
```

Sample output (no custom `ServiceMonitor`s defined):

```text
NAME                                                 AGE
grafana                                              2m46s
node-exporter                                        2m44s
prometheus-operator                                  2m35s
prometheus-stack-kube-prom-alertmanager              22d
prometheus-stack-kube-prom-apiserver                 22d
prometheus-stack-kube-prom-coredns                   22d
prometheus-stack-kube-prom-kube-controller-manager   22d
prometheus-stack-kube-prom-kube-etcd                 22d
prometheus-stack-kube-prom-kube-proxy                22d
prometheus-stack-kube-prom-kube-scheduler            22d
prometheus-stack-kube-prom-kubelet                   22d
prometheus-stack-kube-prom-prometheus                22d
prometheus-stack-kube-state-metrics                  22d
```

`ServiceMonitor`s point automatically to `Service`s to scrape via `LabelSelector`s.

Behind the scenes, `ServiceMonitor`s also configure Prometheus Scrape Configs.
Adding a `ServiceMonitor` does not require restarting Prometheus!

#### Example: ServiceMonitor configuration

Let's view the configuration of the `node-exporter`.

```bash
kubectl -n monitoring describe servicemonitor node-exporter
```

Output:

```yaml
Name:         node-exporter
Namespace:    monitoring
Labels:       app.kubernetes.io/component=metrics
              app.kubernetes.io/instance=prometheus-stack
              app.kubernetes.io/managed-by=Helm
              app.kubernetes.io/name=prometheus-node-exporter
              app.kubernetes.io/part-of=prometheus-node-exporter
              app.kubernetes.io/version=1.10.2
              helm.sh/chart=prometheus-node-exporter-4.52.1
              release=prometheus-stack
Annotations:  meta.helm.sh/release-name: prometheus-stack
              meta.helm.sh/release-namespace: monitoring
API Version:  monitoring.coreos.com/v1
Kind:         ServiceMonitor
Metadata:
  Creation Timestamp:  2026-03-22T16:36:17Z
  Generation:          1
  Resource Version:    51878014
  UID:                 259ef24c-ff5f-4cb2-8d5e-ce82e9b5fec0
Spec:
  Attach Metadata:
    Node:  false
  Endpoints:
    Interval:  30s
    Port:      http-metrics
    Scheme:    http
  Job Label:   jobLabel
  Selector:
    Match Labels:
      app.kubernetes.io/instance:  prometheus-stack
      app.kubernetes.io/name:      prometheus-node-exporter
Events:                            <none>
```

See the `Selector:Match Labels` section.
What this tells us, is that the `ServiceMonitor` will automatically pick up services with the labels `app.kubernetes.io/instance` set to `prometheus-stack`, and `app.kubernetes.io/name` set to `prometheus-node-exporter`.

#### Example (2): Cloudflared ServiceMonitor

Defined [here](../kubernetes/cloudflare-tunnel/monitoring.yaml).

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cloudflared-servicemonitor
  namespace: cloudflare
  labels:
    release: prometheus-stack # Matches deployed Prometheus' ServiceMonitorSelector
spec:
  selector:
    matchLabels:
      app: cloudflared
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
  targetLabels: # Propagate labels from target Service
    - app
    - tunnel-name
```

### Alerting - Alertmanager and Prometheus rule groups

This section explains how to set up Alertmanager to forward alerts to Telegram, and how to configure alert rules in Prometheus.

#### Alertmanager configuration

Alertmanager is configured in the Helm values:

```yaml
alertmanager:
  enabled: true
  alertmanagerSpec:
    secrets: # mounted at /etc/alertmanager/secrets/<secret_name>/<key>
      - telegram-bot-secret
    configMaps: # mounted at /etc/alertmanager/configmaps/
      - telegram-message-template
    resources:
      requests:
        cpu: 100m
        memory: 200Mi
      limits:
        cpu: 500m
        memory: 400Mi
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn-data-local
          resources:
            requests:
              storage: 2Gi

  # Root config
  config:
    global:
      resolve_timeout: 5m
    receivers:
      - name: "null"
      - name: "telegram-bot"
        telegram_configs:
          - send_resolved: true
            api_url: "https://api.telegram.org"
            bot_token_file: "/etc/alertmanager/secrets/telegram-bot-secret/token"
            chat_id_file: "/etc/alertmanager/secrets/telegram-bot-secret/chat_id"
            message: '{{ template "telegram.default.message" . }}'

    route:
      group_by:
        - alertname
        - namespace
      group_interval: 5m
      group_wait: 30s
      receiver: "null"
      repeat_interval: 12h
      routes:
        - receiver: telegram-bot
          matchers:
            - alertname = "Watchdog"
        - receiver: telegram-bot
          matchers: # Only forward alerts that are critical/warnings
            - severity =~ "critical|warning|error"

    templates:
      - /etc/alertmanager/configmaps/telegram-message-template/*.tmpl
```

With the following being the secret containing the Telegram bot token and chat ID:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: telegram-bot-secret
  namespace: monitoring
type: Opaque
stringData:
  token: <bot-token>
  chat_id: "<chat-id>" # Quotes are needed, as ID is number
```

And the following being the Telegram message template ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: telegram-message-template
  namespace: monitoring
data:
  telegram-message-template.tmpl: |
    {{ define "alert_list" }}{{ range . }}
    ---
    🪪 <b>{{ .Labels.alertname }}</b>
    {{- if eq .Labels.severity "critical" }}
    🚨 CRITICAL 🚨 {{ end }}
    {{- if eq .Labels.severity "warning" }}
    ⚠️ WARNING ⚠️{{ end }}
    {{- if .Annotations.summary }}
    📝 {{ .Annotations.summary }}{{ end }}
    {{- if .Annotations.description }}
    📖 {{ .Annotations.description }}{{ end }}

    🏷 Labels:
    {{ range .Labels.SortedPairs }}  <i>{{ .Name }}</i>: <code>{{ .Value }}</code>
    {{ end }}{{ end }}
    🛠 <a href="https://grafana.internal.dmhosted.com">Grafana</a>🛠
    {{ end }}

    {{ define "telegram.default.message" }}
    {{ if gt (len .Alerts.Firing) 0 }}
    🔥 Alerts Firing 🔥
    {{ template "alert_list" .Alerts.Firing }}
    {{ end }}
    {{ if gt (len .Alerts.Resolved) 0 }}
    ✅ Alerts Resolved ✅
    {{ template "alert_list" .Alerts.Resolved }}
    {{ end }}
    {{ end }}
```

Explaination:

- `alertmanagerSpec` is the section about the StatefulSet for Alertmanager. Here we can define resources and mounts.
  - We mount the secret as file, which means that we will be able to access the 2 values of the secret at:
    - `/etc/alertmanager/secrets/telegram-bot-secret/token`
    - `/etc/alertmanager/secrets/telegram-bot-secret/chat_id`
  - We mount the configmap as file, which will end up in `/etc/alertmanager/configmaps/telegram-message-template/telegram-message-template.tmpl`
    - The file defines a template named `telegram.default.message` which can be referenced when defining receivers.
    - The file is then referenced in the `config` section.
- `config` is the "root" Alertmanager config.
  - The spec follows the one of the [Alertmanager config file](https://prometheus.io/docs/alerting/latest/configuration/)
  - Here, we define:
    - `receivers`, including the Telegram receiver
      - Note the reference to the message template defined in the ConfigMap
    - `route`: alert routing tree.
      - By default, we discard alerts that are not critical/error/warning.
      - ...except for `Watchdog` (used for debugging purposes, to test the message flow)

> [!TIP]
>
> It is also possible to extend the Alertmanager configuration by using `AlertmanagerConfig` CRDs.
> These CRDs essentially define extra `config.route` and `config.receivers` sections, which will be merged
> into the global one, with the important consideration that routes defined this way will only apply to alerts coming from
> the specific namespace where the `AlertmanagerConfig` resource is defined.

#### Configuring alerting rules in Prometheus

> TODO

> [!NOTE]
>
> The Kube-Prometheus stack comes with some default alert rules which are good enough to start.

---

## Incidents

### Incident: Longhorn instance-manager CPU spikes (2026-08-27)

> Report is AI generated; investigation was carried out with Claude

#### Symptom

`longhorn-system` instance-manager pods showed 540–690m CPU. Baseline is
`overvecht 82m`, `gouda 177m`, `heiloo 101m`.

Note: `kubectl top` served a _stale cached peak_, overstating the steady state.
Per-process accounting inside the pod and Prometheus `container_cpu_usage_seconds_total`
gave the real picture. Bursts were genuine but lasted hours, not seconds.

#### Root cause

Longhorn was the victim, not the cause.

1. **Cardinality bomb.** TSDB head held 407,570 series; the top 8 metrics were all
   apiserver/etcd histogram buckets (~223k series, ~55% of the TSDB). The apiserver
   job scraped 201,085 samples per scrape.

   | series | metric                                          |
   | ------ | ----------------------------------------------- |
   | 63,614 | `apiserver_request_duration_seconds_bucket`     |
   | 43,996 | `etcd_request_duration_seconds_bucket`          |
   | 37,890 | `apiserver_request_sli_duration_seconds_bucket` |
   | 25,280 | `apiserver_request_body_size_bytes_bucket`      |

2. **`kube-apiserver-burnrate.rules`** ran 14 rules over windows
   `[5m 30m 1h 2h 6h 1d 3d]` against `apiserver_request_sli_duration_seconds_bucket`
   (22,860 series match its `verb=~"LIST|GET"` selector). A single `[1d]` rate scans
   ~66M samples; the group scans hundreds of millions per evaluation.

3. The working set exceeded page cache, so reads came off historical TSDB blocks on disk.

4. Every read traversed the Longhorn userspace data path
   (Prometheus → `/dev/longhorn/…` → `tgtd` → Go engine → replicas). The engine process
   for this one volume had accumulated 20,908 CPU-seconds.

5. **Self-sustaining.** The group took 43.7s against a 30s evaluation interval, so it
   missed 40.7 iterations/hour and immediately re-ran.

| metric            | baseline | peak     |
| ----------------- | -------- | -------- |
| rule eval         | 0.33 s/s | 1.13 s/s |
| `sdd` utilisation | 15%      | ~100%    |
| disk reads        | 1.7 MB/s | 21 MB/s  |
| major page faults | 12/s     | 139/s    |
| volume read IOPS  | 0        | 491      |

`sdd` is `rotational=1` (QEMU VIRTUAL-DISK), topping out near 21 MB/s random reads.
All three instance managers rose together because the volume has 3 replicas and reads
fan out.

#### Ruled out

- **Memory pressure** — `node_memory_Cached_bytes` and `MemAvailable` stayed flat.
- **`--debug` flag** — Longhorn hardcodes it in instance-manager args; log rate was zero.
- **Snapshots** — only 11, no recurring jobs configured.
- **Replica rebuilds** — all 28 volumes `healthy`, `rebuildRetryCount: 0`.
- **TSDB compaction** — 0.000 s/s throughout the window; it only fired _after_.

#### Fixes applied

1. Disabled `kubeApiserverBurnrate`, `kubeApiserverSlos`, `kubeApiserverAvailability`,
   `kubeApiserverHistogram` in `defaultRules.rules`. Verified
   `apiserver_request_sli_duration_seconds_bucket` is referenced only by these three
   groups, so nothing else breaks.

   > [!NOTE]
   > The bundled _Kubernetes / API server_ Grafana dashboard loses its latency and
   > availability panels — they depend on the dropped histograms and the disabled recording
   > rules.

2. Added name-based `drop` relabelings on the apiserver ServiceMonitor for the eight
   histograms above (~50% TSDB reduction). Verified seven of them are referenced by no
   rules at all. The chart's default bucket-thinning relabeling was _preserved_ rather
   than replaced, since setting `metricRelabelings` overrides the chart default.
3. `retentionSize: 60GiB` → `40GiB`. It exceeded the 50Gi volume, so size-based
   retention could never trigger before the disk filled (was at 26.86 GiB — latent,
   not yet firing).

4. Prometheus PVC moved from `longhorn-data-local` (3 replicas, `best-effort`) to
   `longhorn-singlecopy` (1 replica, `strict-local`). The TSDB is the highest-IO volume
   in the cluster and 3-way synchronous replication of expendable metrics across
   rotational virtual disks is poor value. Dropping 3→1 also removes the cross-node
   replica reads that made `gouda` and `heiloo` rise alongside `overvecht`.

   `local-path` was considered and rejected: it would additionally remove the local
   userspace path (`tgtd` → engine → replica), but that is the smaller half of the
   saving, and it cannot expand volumes (`allowVolumeExpansion: false`) or report the
   `longhorn_volume_*` metrics that made this incident diagnosable. Longhorn's usual
   counter-argument does not apply either — `backup-target` is empty, so it provides
   this volume no off-cluster protection.

#### Migration (destructive)

A StatefulSet's `volumeClaimTemplate` is immutable, so changing the storage class
requires recreating the PVC. ~27 GiB of history was discarded deliberately.

Order matters: the values change must be synced by ArgoCD _before_ the PVC is deleted,
otherwise the operator re-provisions it against the old storage class.

```sh
# 1. only after ArgoCD has synced the new storageClassName
kubectl delete sts -n monitoring prometheus-prometheus-stack-kube-prom-prometheus
kubectl delete pvc -n monitoring \
  prometheus-prometheus-stack-kube-prom-prometheus-db-prometheus-prometheus-stack-kube-prom-prometheus-0

# 2. the operator recreates the STS, provisioning a fresh PVC from longhorn-singlecopy
```

The old PV lingers as `Released` (`longhorn-data-local` is `reclaimPolicy: Retain`) and
its Longhorn volume keeps consuming disk until deleted manually.

> [!NOTE]
>
> `nodeDrainPolicy: block-if-contains-last-replica` means a single-replica volume blocks
> drains of its node, which matters given `system-upgrade` performs automatic k3s
> upgrades. Not introduced by this change: 17 single-replica volumes already existed
> across all three nodes.

---

## Links

- [Techno Tim's video](https://youtu.be/fzny5uUaAeY?si=TD5OXGl0MXKc2iyC)
- [Full Tutorial: AlertManager Set up and PrometheusRules](https://youtu.be/HwB2oWUdoT4?si=2vAAHELMM7kkEAV2)
