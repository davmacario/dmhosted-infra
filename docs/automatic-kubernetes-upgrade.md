---
id: automatic-kubernetes-upgrade
author: Davide Macario
date: 2026-03-04
aliases: []
tags:
  - k3s
  - homelab
---

# Automatic K3s upgrades

This document explains the set up in place to automatically keep K3s up-to-date.
We will follow the [K3s guide](https://docs.k3s.io/upgrades/automated).

The end goal is to install a special _Controller_ in our cluster that is able to automatically check for upgrades to stable releases of K3s by means of a CRD.

> [!WARNING]
>
> **IMPORTANT NOTICE**: the following will probably break the usability of the Ansible playbook used to install the cluster, as it
> will update hte version of K3s running there.
> Use with caution.
>
> (on a side note, I am not sure that the roles used in that playbook are still kept up to date)

## Installing the System Upgrade Controller

This can be simply done by running:

```bash
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/crd.yaml -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
```

> [!note]
>
> All resources defined in `system-upgrade-controller.yaml` will be created in the `system-upgrade` namespace.

The created resources are:

- A `Deployment` for 1 Pod, running the system upgrade controller
- A `ConfigMap` that configures the upgrade controller

## Setting up automatic upgrades

We will use the `Plan` CRD (`plans.upgrade.cattle.io`).
See [upgrade-plan.yaml](../kubernetes/system-upgrade/upgrade-plan.yaml) for the definition.

At the time of writing, the cluster is running version `v1.33.5+k3s1`.
We will first set up the Plans to look for new versions pushed on the `v1.33` channel.

Note that the `upgrade-plan.yaml` file also defines a `Plan` for upgrading agent nodes.
This is purely a placeholder since the current cluster does not have agent nodes.

> [!note]
>
> The YAML present in the [guide](https://docs.k3s.io/upgrades/automated) uses the `rancher/k3s-upgrade` images, which are private.
> We need to use the `ghcr.io/k3s-io/k3s-upgrade` images.

## Follow ups

See [k3s-version-upgrade](./k3s-version-upgrade.md) for the upgrade guide to 1.35
