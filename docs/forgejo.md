---
id: forgejo
author: Davide Macario
date: 2026-07-24
tags:
  - homelab
  - app
  - git
---

# Forgejo (on K8s)

> **Goal**: deploy Forgejo on K8s, including CICD runners support

## Requirements

- Able to clone repos on HTTPS
- Can run CICD using self-hosted runners (in K8s)
- Bulk data is stored on the NAS
- DB backed up on nas (daily/biweekly)
- Managed by ArgoCD
  - ideally, this is the source of truth (and what Argo points to), mirrored on github
- Enabled for metrics scraping (expose + scrape)

Optional:

- supports SSH for git operations
  - expecting complications due to exposing port 22 outside the cluster (can't use CF tunnel)
  - [docs](https://code.forgejo.org/forgejo-helm/forgejo-helm#ssh-and-ingress)
- HA setup
  - [not recommended](https://code.forgejo.org/forgejo-helm/forgejo-helm/src/branch/main/docs/ha-setup.md)
- Dedicated redis instance

## Application layout

Components:

- App (container)
- DB (posggres via CNPG)
- Cache (Redis) - optional, can make do with the built-in redis
- External bucket storage (s3-compatible) (via rutsfs, running on NAS)

### Metrics collection

Need to plug into the existing Prometheus setup via a `ServiceMonitor` resource.

---

## Installation

Using the [Helm chart](https://code.forgejo.org/forgejo-helm/forgejo-helm).

See [values.yaml file](../kubernetes/apps/forgejo/values.yaml), containing the plaintext configuration, excluding secrets.
Configuration secrets are passed via a custom secret (`forgejo-config-secrets`).

### Requirement: forgejo CLI

Needed to configure some of the required secrets:

- `SECRET_KEY`: used to encrypt sensitive data
- `INTERNAL_TOKEN`
- `JWT_SECRET`
- `LFS_JWT_SECRET`
