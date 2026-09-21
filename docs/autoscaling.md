---
id: autoscaling
author: Davide Macario
date: 2026-09-20
aliases: []
tags:
  - homelab
  - kubernetes
  - autoscaling
---

# Autoscaling workloads

This doc contains all the information about setting up HorizontalPodAutoscaler and VerticalPodAutoscaler.

## Requirement: `metrics-server`

> [!NOTE]
>
> Not actually needed if running K3s, as it comes bundled with metrics server (not HA though, but good enough)...

Metrics-Server is the component that enables autoscaling in K8s cluster.
It works by exposing container resource metrics to be used by K8s' built-in autoscaling APIs (`autoscaling/v2`).

It can be installed using the [remote manifest](https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability-1.21+.yaml).

> [!note]
>
> There is both a "standalone" version (1 pod) and a "high-availability" one (the one linked above).

See [kustomization](../kubernetes/metrics-server/kustomization.yaml).
This enables deploying the metrics-server with ArgoCD.

## Autoscaling Pods

### Horizontal Scaling

Can be achieved via a `HorizontalPodAutoscaler`.
