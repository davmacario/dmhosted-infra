---
id: application-upgrades
author: Davide Macario
date: 2026-09-24
aliases: []
tags:
  - homelab
  - kubernetes
---

# Application Upgrade Strategy

This document discusses the (automated) application upgrade strategy for apps running on Kubernetes.

## Requirements

### Functional

- New PR opened automatically on repo for each new version of an application/helm chart
- Ability to preview changes to resources (ArgoCD diff) before merging
- (extra) Ability to have AI review changes, injecting context about the application itself and what is going to change

### Non functional

- Free solution
- Self-hostable (if needed to avoid paying)
- Check for new apps done regularly, every 2 hours
- (extra) Supports using self-hosted AI models

## Tools

- [Renovate](https://github.com/renovatebot/renovate)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) (already available)
