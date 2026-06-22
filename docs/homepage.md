---
id: homepage
author: Davide Macario
date: 2026-02-14
aliases: []
tags:
  - homelab
  - k3s
---

# Homepage setup - K8s cluster

[Homepage](https://gethomepage.dev/) is a customizable application dashboard for your homelab.

We will deploy it using Kubernetes, following the [official docs](https://gethomepage.dev/installation/k8s/).
All YAML files are stored under [kubernetes/homepage](../kubernetes/homepage/).

## Deploying the application

What we need (in order):

- [ ] [Namespace](../kubernetes/homepage/01_namespace.yaml)
- [ ] [ServiceAccount](../kubernetes/homepage/02_serviceaccount.yaml)
- [ ] [Secret for ServiceAccount](../kubernetes/homepage/03_secret_serviceaccount.yaml)
- [ ] [ConfigMap](../kubernetes/homepage/04_configmap.yaml)
  - This is the configuration for the application itself (bookmarks, services, widgets are defined here!)
- [ ] [ClusterRole and ClusterRoleBinding](../kubernetes/homepage/05_clusterrole.yaml)
- [ ] [Service](../kubernetes/homepage/06_service.yaml)
- [ ] [Deployment](../kubernetes/homepage/07_deployment.yaml)
  - **Note**: configure the value for `HOMEPAGE_ALLOWED_HOSTS` properly!
- [ ] [IngressRoute - local](../kubernetes/homepage/08_ingressroute_local.yaml)
  - Includes cert for `homepage.local.dmhosted.com`
- [ ] [IngressRoute - internal (Tailscale)](../kubernetes/homepage/09_ingressroute_internal.yaml)
  - Includes cert for `homepage.internal.dmhosted.com`
