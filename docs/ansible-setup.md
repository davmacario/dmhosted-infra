---
id: ansible-setup
author: Davide Macario
date: 2026-06-11
aliases: []
tags:
  - homelab
  - ansible
---

# Ansible setup

This document contains information about the Ansible setup in this project, from the perspective of an Ansible noob.

## Inventory

Found at [./inventory](../inventory/)

- `hosts.ini`: the inventory file. Defines the hosts and groups.
- `group_vars`: each of the files in this directory defines variables associated with either _all hosts_ (`all.yml`), or specific groups (`<group_name>.yml`).
  - This is built into Ansible
- `host_vars`: contains files with names `<host_name>.yml`, defining variables for specific hosts from the inventory.

> [!note]
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
