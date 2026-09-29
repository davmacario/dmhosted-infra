---
id: security-hardening
author: Davide Macario
date: 2026-09-28
tags:
  - homelab
  - containers
  - kubernetes
---

# Security Hardening for Containers in Kubernetes

This document explains the recommended configuration used to improve the security stance of containers deployed in Kubernetes.
It works under the assumption that the container image is given.

## Workload-level

There are 2 levels of security hardening when it comes to the running applications:

- **Pod-level** security options -> `spec.securityContext` (in Pods, Deployments, ReplicaSets, StatefulSets)
- **Container-level** security options -> `spec.containers[i].securityContext`

Some of these options can be defined at both levels, but the container ones will take priority.

Both levels:

- `runAsUser` / `runAsGroup`: UID and GID the container/pod should run.

  > [!NOTE]
  >
  > It is possible to set `runAsUser` and `runAsRoot` to UIDs / GIDs not explicitly defined in the container image.
  > The only drawbacks are:
  >
  > - File ownership might be wrong (_the only realistic one_)
  >   - Typically corrected by means of startup container
  > - Failing identity lookups (`whoami`)
  > - Missing `$HOME`

- `runAsNonRoot`: if set to `true`, kubelet refuses to start the container if it would run as UID 0.

  > [!NOTE]
  >
  > If the image `USER` is a _name_, kubelet can't verify this.
  > To avoid, set a _numeric_ `runAsUser`

- `seccompProfile`: restricts syscalls available to the process.
  - `RuntimeDefault`: the container runtime's default filter (_recommended_)
  - `Localhost`: custom profile on the node (e.g., `localhostProfile: profiles/aaa.json`)
  - `Unconfined`: no filters (_to be avoided_)
- `seLinuxOptions`: assigns SELinux labels (`user`, `role`, `type`, `level`); only works on SELinux-enabled nodes
- `appArmorProfile`: ...
- `windowsOptions`: windows-specific

**Pod-level**:

- `fsGroup`: supported volumes are changed group ownership by this GID.
  This is **required for non-root processes** to **write to mounted volumes**!
- `fsGroupChangePolicy`: either
  - `Always`: recursively chowns all mounts (can be slow for larger ones)
  - `OnRootMismatch`: only chowns if the volume root does not match
- `supplementalGroups`: extra GIDs added to all container processes
- `sysctls`: namespaced kernel parameters

**Container-level**:

- `privileged`: if set to `true`, gives the container nearly all host capabilities and device access.
  **Avoid** outside of CNI components or storage drivers.
- `allowPrivilegeEscalation`: if set to `false`, sets `no_new_privs` flag in Linux (avoids privilege escalation via binary).
  Forced to `true` if `privileged: true` or container has `CAP_SYS_ADMIN`.
- `capabilities`: fine-grained root powers
  - Baseline to start from: `drop: ["ALL"]`
  - Add required ones with `add: [...]`, e.g., `add: ["NET_BIND_SERVICE"]` (allows binding ports < 1024 without root permissions)
- `readOnlyRootFilesystem`: if `true`, root filesystem is immutable.
  - If needing to write to specific locations, mount an `emptyDir` (see [Read-only fs](#read-only-fs))
- `procMount`: can be `Default` (recommended), or `Unmasked`

**Others** (outside of `securityContext`, part of `spec`):

- `hostNetwork`, `hostPID`, `hostIPC`: if set to `true`, allow to share the node's namespace, which is a **huge security risk**.
- `hostUsers`: if set to `true`, runs pod in a user namespace (container root maps to unprivileged host UID).
  Node runtime and kernel need to support this.
- `automountServiceAccountToken`: if `true`, mounts the Kube API token in the container.
  Should be **avoided** unless the container needs access to the Kube API.

### Read-only fs

Setting a read-only filesystem is a standard security practice, as it reduces the attack surface and prevents malicious users from modifying/deleting files and / or affecting the node.

The typical approach is:

- `readOnlyRootFilesystem: true`
- Mount a volume or an `emptyDir` ephemeral volume on paths that need to be writeable.
  - The typical location is `/tmp`, where `emptyDir` is usually mounted

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
      - name: app
        image: myapp:1.2.3
        securityContext:
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir:
          sizeLimit: 100Mi
```

`emptyDir` supports (optionally):

- `sizeLimit`: kubelet evicts the pod if exceeded.
- `medium: Memory`: use tmpfs (in RAM); default is `""`, i.e., using the kubelet's data directory on the node.

Note that `emptyDir` takes up resources allocated for `ephemeral-storage` (resource with its own limits and requests).

### Pod Security Standard

Kubernetes provides 3 different **policies** enforced on all _pods_ in a _namespace_, and that broadly cover the security spectrum.
These policies are applied to _namespaces_ via **labels** (`pod-security.kubernetes.io/<MODE>` and `pod-security.kubernetes.io/<MODE>-version`).
The policies target pod configurations and, if violated, they can prevent a pod from starting, warn about the violation, or simply log it.

The policies are:

- `privileged`: no restrictions are enforced (default for unlabeled namespaces)
- `baseline`: blocks known privilege escalations (privileged containers / host namespaces / `hostPath` volumes / dangerous capabilities)
- `restricted`: `baseline` + hardening requirements (non-root, no privilede escalation, drop `ALL` caps)

The available **modes** are:

- `enforce`: reject pods violating policy
- `audit`: violations allowed, but recorded as annotations in the API server audit log
- `warn`: violations allowed, but `kubectl` (or whatever client calls the k8s API) shows a warning

Example:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: v1.34
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
```

> [!NOTE]
>
> `version` refers to the K8s version the policies are obtained from.
> It is just a feature to avoid version upgrades to start rejecting pods.

Existing pods are not affected when updating the namespace labels, only new ones are.
To preview existing pods that would violate the level:

```bash
kubectl label --dry-run=server --overwrite ns <namespace> pod-security.kubernetes.io/enforce=restricted
```

## Network-level

At the network level, hardening is handled by `NetworkPolicy` resources, which are essentially firewall rules for pods.

Each NetworkPolicy defines:

- `podSelector`: used to match pods to which it applies to (using labels)
- `ingress` rules (only if `policyTypes` contains `Ingress`): used to define allowed ingress routes to the pod
- `egress` rules (only if `policyTypes` includes `Egress`): used to define outbound traffic from the pod

Sources / destinations of ingress / egress policies can be identified with (a combination of) namespace selectors, pod selectors, and IP blocks (CIDR).
