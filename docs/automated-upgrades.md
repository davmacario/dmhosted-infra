---
id: automated-upgrades
author: Davide Macario
date: 2026-09-20
tags:
  - kubernetes
  - upgrades
  - homelab
  - ci/cd
---

# Automated Upgrades

This document contains all information related to automated/unattended upgrades of software running on my Kubernetes cluster, including **system upgrades** (i.e., K3s version itself, or core components of the infra - e.g., MetalLB).

## System Upgrades

**Issue**: the [readme](https://github.com/timothystewart6/k3s-ansible#-upgrading-an-existing-cluster) of the `k3s-ansible` repo (containing the definitions of all Ansible roles used to _install_ the cluster and its core components) explicitly states that these should not be used to perform in-place upgrades of components.
This was confirmed when upgrading k3s from 1.35 to 1.36 using the latest version of the roles, which resulted in a deadlock due to the k3s systemd service not being up in the nodes.

The goal of this section is to define the way upgrades to K3s, MetalLB, and

## Application Upgrades

The assumption is that all (relevant) applications are deployed by means of ArgoCD, in a GitOps fashion.
