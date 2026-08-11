---
id: docs-index
author: Davide Macario
date: 2026-08-11
tags:
  - homelab
---

# Documentation Index

This directory contains write-ups covering the setup, configuration, and maintenance of this homelab, from bare-metal to the applications running on top of Kubernetes.

## Bare-Metal & Cluster Lifecycle

- [Homelab Setup - Bare-Metal](./homelab-setup.md): hardware inventory and network layout
- [Setting Up TrueNAS on New NAS](./setting-up-truenas.md)
- [Ansible Setup](./ansible-setup.md)
- [K3s Installation](./k3s-installation.md)
- [Upgrading K3s Version (Using Ansible)](./k3s-version-upgrade.md)
- [Automatic K3s Upgrades](./automatic-kubernetes-upgrade.md)
- [ArgoCD](./argocd.md): enabling GitOps
- [Sealed Secrets](./sealed-secrets.md): managing secrets in a GitOps way

## Networking & Tailscale

- [Traefik Setup - K3s](./traefik-setup.md)
- [Setting Up the Tailscale Kubernetes Operator](./tailscale-operator.md)
- [Exposing Kubernetes Workloads to Tailnet with Custom Domain Names](./k8s-tailscale-custom-dns.md)
- [CoreDNS Fix: Tailscale/Custom Domain Resolution Failures (ENOTFOUND)](./coredns-fix-tailscale.md)
- [Cloudflare Tunnel for Ingress K8s Traffic](./cloudflare-tunnel.md)
- [Self-Hosted DNS (& DHCP) with Adguard Home](./self-hosted-dns-adguard-home.md)
- [Setting Up DNS on MacOS (Tailscale)](./dns-setup-macos.md)

## Storage & Databases

- [Longhorn Storage Provider](./longhorn.md)
- [Democratic-CSI](./democratic-csi.md): NFS volumes on K8s
- [CSI Driver for NFS](./csi-driver-nfs.md)
- [CloudNativePG - Databases on Kubernetes](./cloudnativepg.md)
- [PostgreSQL Major Version Upgrade - CNPG](./postgres-major-version-upgrade-cnpg.md)
- [Database Migration for Sparkyfitness](./db-migration-sparkyfitness.md)
- [Migrating Firefly-III](./firefly-iii-migration.md)

## Apps & Observability

- [Forgejo (on K8s)](./forgejo.md)
- [Vaultwarden Setup on K3s](./vaultwarden-setup.md)
- [Homepage Setup - K8s Cluster](./homepage.md)
- [SMTP Configuration](./smtp-configuration.md)
- [Monitoring Setup with Prometheus and Grafana](./monitoring-setup-prometheus-grafana.md)

## Misc

- [TODO List](./todo.md): what's on the radar for future applications to be installed
- [Useful Commands](./tips/commands.md)
