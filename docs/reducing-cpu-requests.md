# Reducing CPU requests

CPU requests in k8s should represent the expected steady-state upper bound of utilization for pods in a ReplicaSet (incl. deployment, statefulset, daemonset).
In principle, these values are highly dependent on the specific pod contents, and are hard to guess beforehand.

CPU requests are counted by K8s towards the total amount of "allocated" cpu capacity, which is bounded by the total number of cores in the cluster.
For HA / redundancy reasons, it is important to ensure that the total requested CPU does not exceed the total available CPUs when the maximum number of failing nodes would be down.
In other words, it is important to ensure that even if the cluster experiences the worst failure within the bound of allowed failing nodes (e.g., 3 nodes -> max 1 failure), we still can allocate the total requested capacity - this way we can ensure fault tolerance, as it will be possible to schedule all required pods on the remaining nodes.

As of 2026-11-10, I found out, during a Longhorn upgrade, that i was dangerously close to the limit.
I have 3 nodes with 4 CPU cores each, meaning my overall total capacity is 12 CPU.
The maximum allowed number of failed nodes is 1, which would leave me with 8 CPU left.

Therefore, I must ensure that the total CPU requests are safely below 8 CPUs, to accommodate for a full node failure, alongside with some slack for peak CPU usages and space for new apps.

For this, I decided to get some help from Claude to find out which pods (or better, which Deployments / ReplicaSets) should have their CPU requests lowered.

Since I have an instance of Prometheus running in my cluster, it is possible to easily extract pod CPU usage data and look at it in relation to the resource requests associated with it.
Turns out Claude is really good at this, as it came up with a very simple python script that fetched data from the API, calculated p95 CPU usage per pod, and then came up with updated CPU request values with the rationale of

```text
request ~= max(2 * p95, 7d max)
```

Claude came out with:

```bash
#!/usr/bin/env bash
# Compare each container's CPU request with its p95 and max CPU usage over a time window.
# Queries Prometheus through the Kubernetes API service proxy (read-only, no port-forward).
# Usage: ./cpu-usage-vs-requests.sh [window] [min_request_millicores]   e.g. ./cpu-usage-vs-requests.sh 7d 50
set -euo pipefail

WINDOW="${1:-7d}"
MIN_REQ="${2:-50}"
PROM=/api/v1/namespaces/monitoring/services/prometheus-stack-kube-prom-prometheus:9090/proxy/api/v1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

q() { python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$1"; }

# Per-container CPU usage (cores), sampled every 5m via a subquery, then p95 / max over the window
USAGE='sum by (namespace,pod,container)(rate(container_cpu_usage_seconds_total{container!=""}[5m]))'
kubectl get --raw "$PROM/query?query=$(q "quantile_over_time(0.95,(${USAGE})[${WINDOW}:5m])")" >"$TMP/p95.json"
kubectl get --raw "$PROM/query?query=$(q "max_over_time((${USAGE})[${WINDOW}:5m])")" >"$TMP/max.json"
kubectl get pods -A -o json >"$TMP/pods.json"

python3 - "$TMP" "$MIN_REQ" <<'EOF'
import json, sys
tmp, min_req = sys.argv[1], float(sys.argv[2])

def cpu(v):
    if v is None:
        return 0
    return float(v[:-1]) if v.endswith("m") else float(v) * 1000

def load(f):
    return {
        (r["metric"]["namespace"], r["metric"]["pod"], r["metric"]["container"]): float(r["value"][1]) * 1000
        for r in json.load(open(f))["data"]["result"]
    }

p95, mx = load(f"{tmp}/p95.json"), load(f"{tmp}/max.json")
rows = []
for p in json.load(open(f"{tmp}/pods.json"))["items"]:
    if p["status"].get("phase") != "Running":
        continue
    ns, name = p["metadata"]["namespace"], p["metadata"]["name"]
    for c in p["spec"]["containers"]:
        r = cpu(c.get("resources", {}).get("requests", {}).get("cpu"))
        if r < min_req:
            continue
        k = (ns, name, c["name"])
        rows.append((ns, name, c["name"], r, p95.get(k, 0), mx.get(k, 0)))

print(f"{'NAMESPACE':18} {'POD':45} {'CONTAINER':22} {'REQ':>6} {'P95':>6} {'MAX':>6}  (millicores)")
for ns, name, cname, r, a, b in sorted(rows):
    print(f"{ns:18} {name[:45]:45} {cname[:22]:22} {r:6.0f} {a:6.0f} {b:6.0f}")
EOF
```
