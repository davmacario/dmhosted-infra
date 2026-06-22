---
id: k3s-version-upgrade
author: Davide Macario
date: 2026-06-11
aliases: []
tags:
  - k8s
  - k3s
  - homelab
---

# Upgrading k3s version (using Ansible)

**Issue**: the 'k3s-ansible' repo by TechnoTim has not been updated in a while, and attempting to upgrade from k3s 1.33 is not working.
Luckily, the community came to the rescue, and [this fork](https://github.com/panoptikoe/k3s-ansible) saved the day.

Changes:

- (If enabled) Deactivate the automatic upgrades by destroying all resources defined [here](../kubernetes/system-upgrade/upgrade-plan.yaml)
- Point to the new repo among the [Ansible collections](../collections/requirements.yml)
  - Apply the changes by running:

    ```bash
    ansible-galaxy collection install -r collections/requirements.yml --upgrade
    ansible-galaxy install -r collections/requirements.yml
    ```

- Update the versions of k3s, calico, and cilium:
  - K3s: `v1.33.5+k3s1` -> `v1.35.5+k3s1`
  - Calico: `v3.28.0` -> `v3.31.0`
  - Cilium: `v1.16.0` -> `v1.18.5`
- Run the k3s install playbook:

  ```bash
  ansible-playbook playbooks/k3s_install.yml
  ```

- Update the version to track in the automatic upgrade plans [here](../kubernetes/system-upgrade/upgrade-plan.yaml)
