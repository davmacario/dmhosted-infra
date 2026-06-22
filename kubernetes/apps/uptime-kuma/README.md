---
id: README
author: Davide Macario
date: 2026-02-18
aliases: []
tags:
  - homelab
  - k3s
  - monitoring
---

# Uptime-Kuma deployment

Using [helm chart](https://github.com/dirsigler/uptime-kuma-helm).

Add helm repo:

```bash
helm repo add uptime-kuma https://helm.irsigler.cloud
```

Configure [values](./values.yaml).

Then, run:

```bash
helm upgrade my-uptime-kuma uptime-kuma/uptime-kuma --install --namespace uptime-kuma --create-namespace --values ./values.yaml
```

## Important points

- Since I want to monitor the status of nodes that are only reachable through VPN (Tailscale), I am configuring `dnsConfig` and `dnsPolicy` to fall back to my VPN DNS server (100.127.99.35).
