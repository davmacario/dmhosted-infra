---
id: k3s-installation
author: Davide Macario
date: 2026-08-11
tags:
  - k3s
  - homelab
  - ansible
---

# K3s Installation

K3s is installed via Ansible on the 3 cluster nodes.

The installation uses the Ansible collection defined in [k3s-ansible](https://github.com/timothystewart6/k3s-ansible).
This allows to effortlessly provision a K3s cluster with Highly Available control plane (using kube-vip as the load balancer), and MetalLB as service load balancer.

The main playbook is [../playbooks/k3s_install.yml](../playbooks/k3s_install.yml), and all configuration variables are defined in [../inventory/group_vars/k3s_cluster.yml](../inventory/group_vars/k3s_cluster.yml).
Notice that this file is a "simplified" version of [the "original" variables file](https://github.com/timothystewart6/k3s-ansible/blob/master/inventory/sample/group_vars/all.yml).

> [!IMPORTANT]
>
> The cluster does not use Tailscale IPs.
> This is because there is currently no way to define Virtual IP addresses in the Tailnet to assign to the load balancers (kube-vip, in particular), so the set up would not truly be HA.
>
> Unfortunately, this also prevents including nodes in the cluster that are not connected to the same LAN.
>
> It is however possible, by means of the [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator), to expose Kubernetes services to the Tailnet - see [installation](./tailscale-operator.md).

## IP address selection

- **Control plane virtual IP**: `192.168.178.15`
- **MetalLB range**: `192.168.178.20`-`192.168.178.29`
  - _Note_: DHCP is set up not to assign addresses in this range.

## Tip: using Ansible Vault to handle `k3s_token` variable

We need to set up a password, which we will [store inside a file](https://docs.ansible.com/projects/ansible/latest/vault_guide/vault_managing_passwords.html#storing-passwords-in-files).
First, add the following to `.gitignore`:

```gitignore
*.enc  # We will use `.enc` as extension
```

Then, create a file `vault-password.enc` with proper permissions, and add your password to the file, like so:

```bash
echo "<your_password>" > ./vault-password.enc
chmod 600 ./vault-password.enc
```

> [!NOTE]
>
> The file [../vault-password.enc](../vault-password.enc) is set as the default vault password file in [../ansible.cfg](../ansible.cfg),
> so it will be used any time we invoke `ansible-vault` without the `--vault-password-file` argument.

Then, we can use the password to encrypt `k3s_token`, avoiding to store it in plaintext.

First, generate a suitable value for `k3s_token`, e.g., using `uuidgen` in Bash:

```bash
k3s_token=$(uuidgen)
```

Then, encrypt it:

```bash
ansible-vault encrypt_string --name k3s_token $k3s_token
```

Copy the output and paste it in [../inventory/group_vars/k3s_cluster.yml](../inventory/group_vars/k3s_cluster.yml).
Make sure you overwrite the pre-existing `k3s_token` value.

To decrypt the value (e.g., if you want to add nodes by hand), you can run:

```bash
ansible localhost -m ansible.builtin.debug -a var="k3s_token" -e "@inventory/group_vars/k3s_cluster.yml"
```

> [!NOTE]
>
> Once the cluster is set up, you can always retrieve the token from any master node, as it will be stored in `/var/lib/rancher/k3s/server/token`.

## Follow up steps

### Installing Traefik Ingress Controller (& cert-manager)

See [./traefik-setup.md](./traefik-setup.md)

### Setting up Longhorn (storage provider)

[Longhorn Storage Provider](./longhorn.md)

### NFS volumes on K8s

[Democratic-CSI](./democratic-csi.md)

### Tailscale Kubernetes Operator

[Tailscale Operator setup](./tailscale-operator.md)

### Exposing workloads to Tailnet with custom domains

[Exposing K8s Services over Tailscale](./k8s-tailscale-custom-dns.md)

### Keeping Kubernetes up to date

[Automatic K3s Upgrades](./automatic-kubernetes-upgrade.md).

> [!WARNING]
>
> This may or may not break compatibility with the Ansible setup.
> So far, it didn't.

### Managing secrets in a GitOps way

Using [Sealed-Secrets](./sealed-secrets.md)

### Exposing public services with Cloudflare Tunnels

[Cloudflare tunnels on K8s](./cloudflare-tunnel.md)

### CloudNativePG - DBs on K8s

[CloudNativePG](./cloudnativepg.md)

### Monitoring setup

[Kube-Prometheus Stack](./monitoring-setup-prometheus-grafana.md)

### ArgoCD - enabling GitOps

[ArgoCD setup](./argocd.md)
