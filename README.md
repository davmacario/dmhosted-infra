---
id: dmhosted-infra
author: Davide Macario
date: 2026-06-22
tags:
  - homelab
---

# DMHosted

This repository is the source of truth for (most of) my homelab and personal infra.

Stack:

- Kubernetes (K3s)
- Proxmox
- TrueNAS
- AdGuard Home
- Ansible
- ~Docker (Compose)~ (old set-up, missing)

_Everything runs on Linux._

## Quick links

- [Documentation index](./docs/README.md): full list of write-ups, from bare-metal to applications
- [TODO List](./docs/todo.md): what's on my radar for future applications to be installed
- [K3s Installation](./docs/k3s-installation.md)

## Repo structure

- [docs](./docs/): documentation (from installation to hotfixes, to post-mortems)
- [collections](./collections/): Ansible collections
- [inventory](./inventory/): Ansible inventory (target hosts)
- [kubernetes](./kubernetes/): everything Kubernetes, from infra setup, to applications
- [playbooks](./playbooks/): Ansible playbooks
