# DMHosted

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36.5-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/releases/) <!-- renovate: datasource=github-releases depName=k3s-io/k3s version=v1.36.5+k3s1 -->
[![K3s](https://img.shields.io/badge/distro-K3s-FFC61C?logo=k3s&logoColor=black)](./docs/k3s-installation.md)
[![Argo CD](https://img.shields.io/badge/Argo%20CD-v3.5.6-EF7B4D?logo=argo&logoColor=white)](./kubernetes/argocd/kustomization.yaml) <!-- renovate: datasource=github-releases depName=argoproj/argo-cd version=v3.5.6 -->
[![Renovate](https://img.shields.io/badge/Renovate-enabled-1A1F6C?logo=renovatebot&logoColor=white)](https://github.com/davmacario/dmhosted-infra/issues/10)
[![License](https://img.shields.io/github/license/davmacario/dmhosted-infra)](./LICENSE)

This repository is the source of truth for (most of) my homelab and personal infra.

Stack:

- Kubernetes (K3s)
- Proxmox
- TrueNAS
- AdGuard Home
- Ansible
- Docker (Compose) - incomplete

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
