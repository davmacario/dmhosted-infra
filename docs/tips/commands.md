---
id: commands
author: Davide Macario
date: 2026-07-09
tags:
  - kubernetes
---

# Useful Commands

## Kubectl

Ephemeral pod in namespace:

```bash
k run tmp-shell -n <namespace> --rm -it --image busybox:latest --restart=never -- /bin/sh
```

> [!TIP]
>
> The typical choice for network debugging is the `nicolaka/netshoot` image.

If needing to mount an existing PersistentVolume (from PVC):

```bash
k run tmp-shell -n <namespace> --rm -it --restart=Never --image=busybox \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "tmp-shell",
      "image": "busybox",
      "command": ["sh"],
      "stdin": true,
      "tty": true,
      "volumeMounts": [{"name": "data", "mountPath": "/data"}]
    }],
    "volumes": [{
      "name": "data",
      "persistentVolumeClaim": {"claimName": "<pvc-name>"}
    }]
  }
}'
```

where `pvc-name` is the name of the PVC.

## Helm

```bash
# Add a Helm repository
helm repo add <helm-repo-url>
```

```bash
# List all available repos (string is used to search)
helm search repo [string]
```

Showing values:
```bash
helm show values repo_name

# For OCI repo:
helm show values oci://repo.url
```
