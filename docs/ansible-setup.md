---
id: ansible-setup
author: Davide Macario
date: 2026-06-11
tags:
  - homelab
  - ansible
---

# Ansible Setup

This document contains information about the Ansible setup in this project, from the perspective of an Ansible noob.

```tree
dmhosted-infra/
├── ansible.cfg                 # Contains the ansible configuration & defaults
├── collections/
│   └── requirements.yml        # Contains required collections
├── inventory/
│   ├── group_vars/
│   │   ├── all.yml             # Contains shared variables for all nodes in the inventory (./inventory/hosts.ini)
│   │   └── k3s_cluster.yml     # Contains variables applying to the `k3s_cluster` group
│   ├── host_vars/
│   │   ├── gouda.yml           # Contains variables specific for host `gouda`
│   │   ├── heiloo.yml          # Contains variables specific for host `heiloo`
│   │   └── overvecht.yml       # Contains variables specific for host `overvecht`
│   └── hosts.ini               # Inventory file
├── playbooks
│   ├── install_cluster.yml     # Install requirements for all nodes in the cluster (incl. Docker) + configure (ufw, swap)
│   ├── k3s_install.yml         # Install K3s and create cluster (flannel, kube-vip, MetalLB)
│   ├── k3s_teardown.yml        # Uninstall K3s from all cluster nodes (undo `k3s_install.yml`)
│   └── update_packages.yml     # Update packages in all nodes of the inventory
└── README.md                   # This file
```

## Inventory

Found at [./inventory](../inventory/)

- `hosts.ini`: the inventory file. Defines the hosts and groups.
- `group_vars`: each of the files in this directory defines variables associated with either _all hosts_ (`all.yml`), or specific groups (`<group_name>.yml`).
  - This is built into Ansible
- `host_vars`: contains files with names `<host_name>.yml`, defining variables for specific hosts from the inventory.

> [!NOTE]
>
> Host vars have higher prio than group vars.
> Group vars for parent groups (i.e., groups containing groups) have lower prio than child groups.

## Collections

[./collections](../collections/)

This directory contains the list of collections referenced in the playbooks.
**Collections** are a "distribution format" for Ansible content, that may include playbooks, roles, modules, and plugins.

[**Roles**](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html) are a way to package vars, files, tasks, and handlers based on a known file structure.
Roles can be referenced by tasks in a playbook, e.g.,

```yaml
- name: Setup k3s servers
  hosts: k3s_master
  environment: "{{ proxy_env | default({}) }}"
  roles:
    - role: techno_tim.k3s_ansible.k3s_server
      become: true
```

## Playbooks

[./playbooks](../playbooks/)

**Playbooks** are YAML files containing _plays_, i.e., the basic unit of Ansible execution.

Plays contain:

- variables
- roles
- tasks

Taking as reference [k3s_install.yml](../playbooks/k3s_install.yml), the playbook is composed of 6 _plays_.
These plays can contain:

- `pre_tasks`
- `tasks`
- `roles`

which will determine its behavior.

**Tasks** are basic actions that make up roles.

It is possible to use [playbook keywords](https://docs.ansible.com/projects/ansible/latest/reference_appendices/playbooks_keywords.html#playbook-keywords) at the playbook, play, or task level.
