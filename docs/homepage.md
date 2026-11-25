---
id: homepage
author: Davide Macario
date: 2026-02-14
tags:
  - homelab
  - k3s
---

# Homepage Setup - K8s Cluster

[Homepage](https://gethomepage.dev/) is a customizable application dashboard for your homelab.

It is deployed following the [official docs](https://gethomepage.dev/installation/k8s/), and managed by Argo CD ([Application](../kubernetes/argocd-apps/homepage.yaml)).
All manifests live under [kubernetes/apps/homepage](../kubernetes/apps/homepage/), tied together by a [Kustomization](../kubernetes/apps/homepage/kustomization.yaml).

**Note**: configure the value for `HOMEPAGE_ALLOWED_HOSTS` in the [Deployment](../kubernetes/apps/homepage/deployment.yaml) properly!

## Configuration

The Homepage config files (`services.yaml`, `settings.yaml`, `widgets.yaml`, ...) are plain files in [config/](../kubernetes/apps/homepage/config/).
Kustomize turns them into the `homepage-config` ConfigMap through a `configMapGenerator`, mounted file by file under `/app/config/`.
The generated ConfigMap name has a content hash suffix, so any config change rolls out the Deployment automatically.

## Widget credentials

API keys, usernames and passwords are not stored in the config files, but rather use Homepage's [environment variable substitution](https://gethomepage.dev/installation/docker/#using-environment-secrets), like so:

```yaml
widget:
  type: argocd
  url: https://argocd.internal.dmhosted.com/
  key: "{{HOMEPAGE_VAR_ARGOCD_KEY}}"
```

The values are in the `homepage-credentials` Secret, loaded into the container with `envFrom`, and deployed as sealed secret.
