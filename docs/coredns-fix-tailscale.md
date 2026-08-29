---
id: coredns-fix-tailscale
author: Davide Macario
date: 2026-08-06
tags:
  - homelab
  - k8s
  - dns
---

# CoreDNS Fix: Tailscale/Custom Domain Resolution Failures (ENOTFOUND)

> **Disclaimer**: this writeup was written by AI

> TODO: fix it following K3s guide: <https://docs.k3s.io/advanced#coredns-custom-configuration-imports>

## Symptom

Workloads in the cluster (e.g. Uptime Kuma) intermittently fail to resolve Tailscale/tailnet
hostnames or custom domains served by our internal Tailscale DNS server, throwing `ENOTFOUND`
or similar DNS resolution errors — even though the same hostnames resolve fine from local
machines or other tailnet devices.

This can happen suddenly, with no changes to application config, typically correlating with a
restart or reschedule of the `kube-dns` (CoreDNS) pod.

> Happened at around 9 pm on 2026-08-05; out of the blue - it worked fine for months and then
> it stopped, resulting in Uptime Kuma showing all hosts down, while services were flaky.

## Root Cause

By default, CoreDNS's `Corefile` includes a catch-all forwarding rule:

```text
forward . /etc/resolv.conf
```

This tells CoreDNS to forward any query it doesn't own (i.e. not `cluster.local`) to whatever
nameservers are listed in the **node's** `/etc/resolv.conf` — read at CoreDNS pod startup.

This is fragile for a few reasons:

- If the CoreDNS pod restarts and gets scheduled onto a different node, it inherits that node's
  DNS config, which may not point to our Tailscale DNS server.
- Even when a pod's own `dnsConfig` explicitly lists our Tailscale DNS server as a secondary
  nameserver, **glibc's resolver does not fall through to it** unless the first nameserver
  (CoreDNS) is unreachable. If CoreDNS answers with `NXDOMAIN` (domain not found), glibc treats
  that as final and never tries the second server.

Net effect: resolution of our tailnet/custom domains depends entirely on the CoreDNS pod's node
having correct DNS config at the moment CoreDNS started — which isn't guaranteed and isn't
something we control directly.

### Complete Corefile (pre-fix)

Obtained via:

```bash
kubectl -n kube-system get configmap coredns -o yaml
```

```yaml
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        hosts /etc/coredns/NodeHosts {
          ttl 60
          reload 15s
          fallthrough
        }
        prometheus :9153
        cache 30
        loop
        reload
        loadbalance
        import /etc/coredns/custom/*.override
        forward . /etc/resolv.conf
    }
    import /etc/coredns/custom/*.server
  NodeHosts: |
    192.168.178.12 heiloo
    192.168.178.13 gouda
    192.168.178.14 overvecht
kind: ConfigMap
metadata:
  annotations:
    objectset.rio.cattle.io/applied: ...
    objectset.rio.cattle.io/id: ""
    objectset.rio.cattle.io/owner-gvk: k3s.cattle.io/v1, Kind=Addon
    objectset.rio.cattle.io/owner-name: coredns
    objectset.rio.cattle.io/owner-namespace: kube-system
  creationTimestamp: "2025-11-22T23:56:58Z"
  labels:
    objectset.rio.cattle.io/hash: ...
  name: coredns
  namespace: kube-system
  resourceVersion: "129403976"
  uid: ...
```

## Fix

Configure CoreDNS to explicitly forward our internal (VPN) domain(s) to our Tailscale DNS server,
independent of node-level resolv.conf. This makes resolution deterministic and cluster-wide for
all workloads, not just the one we noticed the issue on.

> [!NOTE]
>
> This is a _permanent_ fix that overrides the local node DNS config from within pods.
> This does _not_ have any effect on the nodes' DNS settings.

### Steps

For K3s, the [advanced guide](https://docs.k3s.io/advanced#coredns-custom-configuration-imports)
explains how to do it properly.

What we need to do is simply create a ConfigMap named `coredns-custom` to introduce overrides to
the default config obtained above.

The end result will have to look like:

```corefile
internal.dmhosted.com ts.net:53 {
    errors
    cache 30
    forward . <TAILSCALE_DNS_SERVER_IP>
}
.:53 {
    errors
    health
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

Thus, we need to add a new _server_ section to match the internal domains (`internal.dmhosted.com` and `ts.net`).
This can be achieved with the following [ConfigMap](../kubernetes/system-configuration/coredns-custom.yaml):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  tailscale.server: |
    internal.dmhosted.com ts.net:53 {
        errors
        cache 30
        forward . 100.127.99.35
    }
```

> [!TIP]
>
> An alternative could be to just add a `forward` rule in the existing _server_ section,
> but this would make the query go through every thing that is already defined in the section.
> Since we don't need most of the things defined there to process our internal DNS query,
> it is best to just add another server section.

## Why This Is the Durable Fix

- Removes dependency on the CoreDNS pod's node having correct/consistent `/etc/resolv.conf`.
- Removes dependency on per-pod `dnsConfig` secondary nameservers, which are unreliable due to
  glibc's fallback behavior (only triggers on unreachable server, not on NXDOMAIN).
- Fix is cluster-wide: any pod in the cluster can now resolve these domains correctly without
  needing custom `dnsConfig` in its own deployment spec.

## Related Notes

- This CoreDNS ConfigMap change is cluster-scoped and will persist across CoreDNS pod
  restarts/reschedules, since it no longer depends on node-level DNS state.
- If our Tailscale DNS server IP ever changes, this ConfigMap must be updated to match.
- Consider monitoring/alerting on CoreDNS pod restarts, since a restart briefly interrupts
  DNS resolution cluster-wide during the reload.
