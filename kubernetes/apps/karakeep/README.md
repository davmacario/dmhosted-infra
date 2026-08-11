---
id: karakeep
author: Davide Macario
date: 2026-06-22
tags:
  - homelab
  - k3s
  - app
---

# Kubernetes Installation with Kustomize

Before installing for the 1st time:

- edit the configuration in `.env` (these values can be updated later)
- edit the secrets in `.secrets`

Then run `make deploy`.
This will create `_manifest.yaml` with all resources.

To update the manifest, run:

```bash
make clean
make deploy
```

See [Makefile](./Makefile) for the full list of options

---

Based on [repo](https://github.com/karakeep-app/karakeep/tree/main/kubernetes).
Introduced the following changes:

- Updated Makefile to use `kubectl kustomize` as base command (Kustomize is now included in kubectl)
- Specified StorageClass to `longhorn-data-local` for all PVCs
- Web Service is now of type ClusterIP
- Added resource requests + limits for all containers in Deployments
- Changed `strategy` to `type: Recreate` in Deployments that use PVCs, as they are all RWO, so we need clean release
- Added definition of [IngressRoute](./web-ingressroute.yaml) and [Certificate](./web-certificate.yaml)
