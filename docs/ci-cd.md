---
id: ci-cd
author: Davide Macario
date: 2026-10-20
tags:
  - ci/cd
  - kubernetes
---

# CI-CD Configuration

This document describes the CI/CD setup of the repository

## CI

CI happens via [GitHub Workflows](../.github/workflows/).

### Pull request

- [**Argo CD Diff Preview**](https://dag-andersen.github.io/argocd-diff-preview/): tool used to preview Kubernetes manifest diffs via ArgoCD by means of an ephemeral K8s cluster running in [_kind_](https://kind.sigs.k8s.io/).
  - Only runs when any change in the [Kubernetes directory](../kubernetes/) happens.

## CD

> TODO
