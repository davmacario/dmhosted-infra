---
id: commands
author: Davide Macario
date: 2026-07-09
tags:
  - kubernetes
---

# Useful Commands

## Kubectl

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
