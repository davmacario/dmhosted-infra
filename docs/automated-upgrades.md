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

The goal of this section is to define the way upgrades to K3s, Flannel (CNI, bundled with K3s), MetalLB, and Kube VIP.

> [!NOTE]
>
> The [technotim Ansible roles](https://github.com/timothystewart6/k3s-ansible) used in the [cluster install playbook](../playbooks/k3s_install.yml) installs MetalLB and KubeVIP using plain manifests.
> See:
>
> - [MetalLB task](https://github.com/timothystewart6/k3s-ansible/blob/master/roles/k3s_server/tasks/metallb.yml)
> - [KubeVIP task](https://github.com/timothystewart6/k3s-ansible/blob/master/roles/k3s_server/tasks/kube-vip.yml)
>
> In practice, the manifests are installed on the primary node at `/tmp/k3s/` and applied once.
> In theory, this method can also be used for updating the 2 apps, but it is prone to breaking and can't be properly reviewed.

### Requirements

- Upgrades to these components are always reviewed by me (unattended is fine only if rollback strategy is clear)
- [Ansible playbook](../playbooks/k3s_install.yml) is used for first install
- Upgrades don't depend on something external - if there is software to be ran somewhere, it should be running in the cluster
- Upgrades come in the form of pull requests to the GitOps repo (current repository)
- Frequency of upgrade checks is every 2 hours
- "Handoff" from Ansible-managed to the long-term auto upgrade solution should be automated as much as possible

### Decisions

> Assisted by Claude

- [Renovate](https://docs.renovatebot.com/) is the tool used to discover new software versions in the cluster.
  - Runs in the cluster as a CronJob (every 2 hours), authenticating as a GitHub App (_this allows potentially switching to Forgejo as source of truth in the future + more lightweight than the mend/renovate CE app_)
- All system components have an associated ArgoCD application which includes the version of the software (targeted by Renovate)
- K3s (and Flannel) upgrades are rolled out using the [K3s System Upgrade controller](https://docs.k3s.io/upgrades/automated)
- MetalLB and KubeVIP are migrated to Helm Charts (_caution needed_ to properly adopt resources) - one-off action
- Renovate creates PRs, which are reviewed by me and then merged on main.
  - ArgoCD still requires manual action (_until a method to preview the changes in the MR is found_)
- For K3s upgrades, configure target on the NAS to execute etcd snapshots
- Ansible used to only install k3s and bootstrap ArgoCD
  - `k3s_install.yml` playbook needs to be refactored to not install MetalLB and KubeVIP
    - Done: MetalLB is disabled, and the K3s auto-deploy manifests the roles write are disabled with `.skip` markers (kube-vip is still needed while servers join)

## Application Upgrades

The assumption is that all (relevant) applications are deployed by means of ArgoCD, in a GitOps fashion.

---

## Solution Overview

Responsibilities get split:

- [Ansible playbook - `k3s_install.yml`](../playbooks/k3s_install.yml): bootstrap K3s, Kube VIP (needed for Kube API), and install ArgoCD
  - Also supports restoring from existing cluster for migrations
- **ArgoCD + Renovate**: manage lifecycle of all applications and automate version bumps (via PR)

### Responsibilities

#### System Components

| Component                 | Managed by                                                                 | Version lives in                                                                                     | Renovate group                        |
| ------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------- |
| K3s (+ Flannel)           | [system-upgrade-controller](../kubernetes/argocd-apps/system-upgrade.yaml) | `version` in [upgrade-plan.yaml](../kubernetes/system-upgrade/upgrade-plan.yaml) + `k3s_version`[^1] | `k3s-io/k3s` (one PR per patch/minor) |
| system-upgrade-controller | [Argo CD app](../kubernetes/argocd-apps/system-upgrade.yaml) (Kustomize)   | [kustomization.yaml](../kubernetes/system-upgrade/kustomization.yaml)                                | `system-upgrade-controller`           |
| kube-vip                  | [Argo CD app](../kubernetes/argocd-apps/kube-vip.yaml) (Helm)              | chart version + [values.yaml](../kubernetes/kube-vip/values.yaml) + `kube_vip_tag_version`[^1]       | `kube-vip`                            |
| MetalLB                   | [Argo CD app](../kubernetes/argocd-apps/metallb.yaml) (Helm)               | chart version                                                                                        | `metallb`                             |
| Renovate                  | [Argo CD app](../kubernetes/argocd-apps/renovate.yaml) (plain manifests)   | image tag in [cronjob.yaml](../kubernetes/renovate/cronjob.yaml)                                     | `renovate`                            |

> [!NOTE]
>
> The versions in [group_vars](../inventory/group_vars/k3s_cluster.yml) are only used for a fresh install.
>
> Renovate bumps them in the same PR as the manifests, so a re-install using this same repo matches what is running.

[^1]: From [`k3s_cluster` Ansible group vars](../inventory/group_vars/k3s_cluster.yml)

#### Applications

> TODO: use the same Renovate cronjob, update renovate.json.
> Should also include apps in docker/* (dmhosted-blog should be in the same group).

### Upgrade flow

1. Renovate (every 2 hours) opens a **PR** and lists it in the **Dependency Dashboard issue**.
2. Review the **release notes** linked in the PR (for K3s, also the Kubernetes changelog for minor bumps), then merge.
3. In Argo CD, check the diff of the application, then **Sync**.
4. For K3s, watch the rollout: `kubectl -n system-upgrade get plans,jobs` and `kubectl get nodes -o wide`.
   Nodes are cordoned and upgraded one at a time (`concurrency: 1`).

Rollback strategy:

- K3s: **cannot be downgraded in place.** Revert the PR (so a sync doesn't upgrade again), then restore the pre-upgrade etcd snapshot ([restore runbook](#restore-runbook))
- _All other apps_: revert Renovate PR

## Renovate setup

Renovate runs as a [CronJob](../kubernetes/renovate/cronjob.yaml) (every 2 hours) in the `renovate` namespace, authenticating as a private **GitHub App**.
An init container exchanges the App private key for a 1-hour token (see [script](../kubernetes/renovate/github-app-token-script.yaml)) used for the job.

The _global_ configuration of renovate is in the [renovate-env ConfigMap](../kubernetes/renovate/configmap.yaml), while the current repo config is in [renovate.json](../renovate.json).

> [!NOTE]
>
> This setup also supports adding other target repos in the future, to run renovate for those too.
>
> Once the number of repositories grows larger than ~10, Mend Renovate CE becomes the better alternative (if still on GitHub - not available for Forgejo).

### Installation

The setup is:

- K8s CronJob running Renovate on a schedule
- GitHub App attached to specific repositories, used to provide the "identity" to the cronjob (via private key)

Setting this up (see [renovate folder](../kubernetes/renovate/)):

1. Create a **GitHub App** ("Settings" > "Developer settings" > "GitHub Apps" > "New"):
   - (chosen) **Name**: dmhosted-renovate
   - **Homepage URL**: anything (e.g. the repo URL)
   - **Webhook**: uncheck **Active**
   - **Repository permissions**: Checks (read/write), Commit statuses (read/write), Contents (read/write), Issues (read/write), Pull requests (read/write), Workflows (read/write), Administration (read), Metadata (read)
   - **Where can it be installed**: only this account.
2. Generate a _private key_ (and download it), note the _App ID_, and install the App on the desired repos (starting with the current one - `davmacario/dmhosted-infra`).
3. Get the bot App ID and place them in [configmap.yaml](../kubernetes/renovate/configmap.yaml).
   The App ID can be found in the app page ("Settings" > "Developer settings" > "GitHubApps" > "<your app name>").
4. Create secret containing app ID and private key:

   ```yaml
   ---
   # github-app-secret.yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: github-app
     namespace: renovate
   type: Opaque
   stringData:
     app-id: "<app id>"
     private-key: |
       -----BEGIN RSA PRIVATE KEY-----
       ...
       -----END RSA PRIVATE KEY-----
   ```

5. Seal the secret against the live controller:

   ```bash
   kubeseal -f github-app-secret.yaml -w github-app-secret-sealed.yaml -o yaml
   ```

6. Commit, merge, and sync the `renovate` application.
   This applies the `CronJob` manifest.
7. Trigger a first run instead of waiting for the schedule, and check the detected dependencies in the logs:

   ```bash
   kubectl -n renovate create job --from=cronjob/renovate renovate-manual-$(date +%s)
   kubectl -n renovate logs -f job/<job name> -c renovate
   ```

   The same command is useful after merging a PR, to get the other open PRs rebased right away.

### Renovate Configuration (this repo)

Renovate can be customized with global and local settings.
For local settings, this can be done via a `renovate.json` file.

[renovate.json](../renovate.json) contains the configuration for this repository.

---

## Handoff from Ansible (one-time migration) - 2026-10-12

The current cluster was installed by Ansible.
These steps move the system components under Argo CD without upgrading anything (all apps are pinned to the versions currently running).

> [!WARNING]
>
> The Ansible roles install kube-vip and MetalLB through the K3s [auto-deploy manifests](https://docs.k3s.io/installation/packaged-components) directory (`/var/lib/rancher/k3s/server/manifests/`: `vip.yaml`, `vip-rbac.yaml`, `metallb-crds.yaml`).
> K3s re-applies these files on every restart, and when the objects are deleted, so the Ansible-managed objects come back after step 2 and 3 below.
> Failed runs of the `k3s_install.yml` playbook might leave those behind.
>
> `kubectl -n kube-system get addon` lists them.
>
> Disable them on all server nodes **before** deleting any object (step 0).
> This can be achieved by deleting those files, or creating the following:
>
> - `/var/lib/rancher/k3s/server/manifests/vip.yaml.skip`
> - `/var/lib/rancher/k3s/server/manifests/vip-rbac.yaml.skip`
> - `/var/lib/rancher/k3s/server/manifests/metallb-crds.yaml.skip`
>
> Which prevents k3s from applying the problematic files (see [Using .skip files](https://docs.k3s.io/installation/packaged-components#using-skip-files)).
> This is also automatically executed by point 1 in the [k3s_install.yml playbook](../playbooks/k3s_install.yml) - see below.

1. **K3s auto-deploy manifests**: run the `handoff` play, which deletes the files and creates a `.skip` marker for each of them on all server nodes, without affecting running objects.
   The play is idempotent and runs at the end of every playbook run: the markers stay in place, so a later run of the `k3s_server` role on the same cluster (which writes the files again) does not bring the Ansible-managed objects back.

   ```bash
   ansible-playbook playbooks/k3s_install.yml --tags handoff
   ```

2. **system-upgrade-controller** (no downtime):
   - Sync `system-upgrade`. Argo CD adopts the hand-installed objects (same names, v0.19.0).
   - SUC runs one Job per node because the Plans are new. The version already matches, so K3s is not upgraded, but each node is **cordoned briefly**.
   - Check: `kubectl -n system-upgrade get plans,jobs` and that all nodes are `Ready` and schedulable.
3. **kube-vip** (no downtime expected):

   - Sync `kube-vip`. The new `kube-vip` DaemonSet starts next to `kube-vip-ds`; both use the `plndr-cp-lock` lease, so only one announces the VIP.
   - Check: `kubectl -n kube-system get pods -o wide | grep kube-vip` (6 pods running) and `kubectl -n kube-system get lease plndr-cp-lock`.
   - Delete the Ansible-managed objects:

     ```bash
     kubectl -n kube-system delete ds kube-vip-ds
     kubectl delete clusterrolebinding system:kube-vip-binding
     kubectl delete clusterrole system:kube-vip-role
     ```

   - Check: `kubectl --server https://192.168.178.15:6443 get nodes` works, and the lease holder is a pod of the new DaemonSet.

4. **MetalLB** (short blip in LoadBalancer IP announcements, do it at a quiet moment):

   - Delete the Ansible-managed controller, speaker and RBAC. Keep the namespace, the CRDs, the `IPAddressPool` and the `L2Advertisement`, so Services keep their IPs:

     ```bash
     kubectl -n metallb-system delete deployment controller
     kubectl -n metallb-system delete daemonset speaker
     kubectl -n metallb-system delete serviceaccount controller speaker
     kubectl -n metallb-system delete role controller pod-lister
     kubectl -n metallb-system delete rolebinding controller pod-lister
     kubectl -n metallb-system delete secret memberlist
     kubectl delete clusterrolebinding metallb-system:controller metallb-system:speaker
     kubectl delete clusterrole metallb-system:controller metallb-system:speaker
     ```

   - Immediately sync `metallb`. The IP pool and L2 advertisement are synced last (sync wave 1) and retried until the webhook is up.
   - If the sync fails with `no endpoints available for service "metallb-webhook-service"`, the adopted Service kept the old `component: controller` selector next to the chart's labels, so it matches no pod.
     Remove the stale key, check that the endpoints point to the new controller, then sync again:

     ```bash
     kubectl -n metallb-system patch svc metallb-webhook-service --type=json \
       -p '[{"op":"remove","path":"/spec/selector/component"}]'
     kubectl -n metallb-system get endpointslices -l kubernetes.io/service-name=metallb-webhook-service
     ```

   - Check: `kubectl -n metallb-system get pods`, `kubectl get svc -A | grep LoadBalancer` (same external IPs), and that Traefik answers on its IP.
   - Check that the handoff holds: restart K3s on one server (`sudo systemctl restart k3s`), then verify that only `metallb-*` objects exist in `metallb-system` (`kubectl -n metallb-system get deploy,ds,sa`) and that `kube-vip-ds` did not come back.

5. **Renovate**: follow [Renovate setup](#renovate-setup).

## Fresh install

[k3s_install.yml](../playbooks/k3s_install.yml) installs K3s and kube-vip (needed for the API VIP while servers join), then the `Bootstrap GitOps` play:

1. applies the plain upstream Argo CD manifests, at the version referenced in [kubernetes/apps/argocd/kustomization.yaml](../kubernetes/apps/argocd/kustomization.yaml)
2. creates the repository credentials from `argocd_repo_username`/`argocd_repo_password` (vault-encrypted, in group_vars)
3. optionally restores the Sealed Secrets keys from `sealed_secrets_key_manifest` (vault-encrypted output of `kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml`), so existing SealedSecrets can be decrypted
4. applies the [root app](../kubernetes/root-app.yaml)

The play is skipped if the `argocd` namespace already exists.
The last play (`handoff`) disables the K3s auto-deploy manifests of kube-vip, see [step 1 of the handoff](#handoff-from-ansible-one-time-migration).
MetalLB is not installed by Ansible (`metal_lb_enabled: false`).

Afterwards, sync the applications in Argo CD (starting with `sealed-secrets` and `argocd`); kube-vip is adopted the same way as in the handoff above.

---

## Links

- [Official docs](https://docs.renovatebot.com/)
- [Self-hosting examples: Kubernetes CronJob](https://docs.renovatebot.com/examples/self-hosting/#kubernetes)
- [Lessons learned self-hosting Renovate](https://www.jvt.me/posts/2024/05/03/renovate-self-hosting-lessons/)
