# Homelab setup

## Italy

> ToDo

## Netherlands (Utrecht)

3 mini-PCs

### `gouda`

IPs:

- Local: 192.168.178.13 (configured via DHCP settings of router)
- Tailscale: 100.117.107.103

Specs:

- Intel i3-7100 (3.40 GHz - 4c/4t)
- 16 GB ddr4 RAM
- 500 GB NVME drive (boot) -> `/dev/nvme0n1`
  - Root fs (lvm[^1] `/dev/mapper/ubuntu--vg-ubuntu--lv` on `nvme0n1p3` partition)
- 1 TB (900 GB) SATA drive (data) -> `/dev/sda`
  - Mounted on `/data`

OS: Ubuntu Server 24.04 LTS

[^1]: [Logical Volume Manager](https://wiki.archlinux.org/title/LVM)

### `pve-dmacario`

IPs:

- Local: 192.168.178.11
- Tailscale: 100.70.245.78

Specs:

- Intel i5-6500 (4c/4t)
- 32 GB ddr4 RAM
- 1 TB NVME (boot)
- 1 TB SATA SSD

OS: Proxmox VE

#### Specific configuration

- Disabled license warning: [guide](https://www.reddit.com/r/Proxmox/comments/tgojp1/removing_proxmox_subscription_notice/)
- Fix apt sources (remove licensed/enterprise ones): [guide](https://www.reddit.com/r/Proxmox/comments/1atx7ay/comment/kr06p2w/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button)
- Enabled cert generation using Tailscale (prevents having to "accept the risk" when logging in via browser):
  - [certs generation for proxmox](https://tailscale.com/kb/1133/proxmox)
  - [enabling HTTPS](https://tailscale.com/kb/1153/enabling-https)
  - Script:

    ```bash
    #!/bin/bash

    CERTS_DIR="/root/certs"
    if [[ ! -d "$CERTS_DIR" ]]; then
      mkdir -p "$CERTS_DIR"
    fi

    NAME="$(tailscale status --json | jq '.Self.DNSName | .[:-1]' -r)"

    pushd "$CERTS_DIR"
    tailscale cert "${NAME}"
    pvenode cert set "${NAME}.crt" "${NAME}.key" --force --restart
    popd
    ```

  - Runs on `0 4 1 * *` schedule; certs have a lifetime of 90 days.

#### `overvecht`

> "Persistent" VM deployed in proxmox on pve-dmacario.

IPs:

- local: 192.168.178.14
- tailscale: 100.65.65.83

Specs:

- 4 core ('host')
- 16 GB RAM
- 500 GB from nvme
- 500 GB from sata

### `heiloo`

IPs:

- local: 192.168.178.12
- tailscale: 100.80.15.112

Specs:

- Intel i3-9300 (4c/4t)
- 16 GB ddr4 RAM
- 1 TB NVME (boot)

### _Network setup_

**CIDR**: `192.168.178.0/24`

- Router (default GW): `192.168.178.1`
- DHCP range: `192.168.178.30`-`192.168.178.255`
  - This means that anything we want to use a static IP for should be in `192.168.178.2`-`192.168.178.29`
  - This includes Kubernetes services.

> [!NOTE]
>
> This information is outdated.
> See [DNS setup using AdGuardHome](./docs/self-hosted-dns-adguard-home.md).

### Scripts

> A collection of things I ran on the first PC I configured ([gouda](#gouda))

```bash
sudo apt install -y nmap jq

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# ... and then follow the link to add the device

# Passwordless sudo configuration
echo -e "$USER ALL=(ALL:ALL) NOPASSWD: ALL\nDefaults:$USER verifypw=any\n" | sudo tee "/etc/sudoers.d/no-sudo-password-$USER"

# Mounting secondary drive (gouda, overvecht)
df -h  # Display disks
lsblk -f  # Display volumes
sudo wipefs -a /dev/sda  # Wipe secondary disk (replace /dev/sda with correct one)
sudo fdisk /dev/sda  # press `n` to create a new partition, follow the steps, and then press `w` to save and quit
sudo mkfs.ext4 -F -L data /dev/sda1  # Make filesystem
sudo mkdir /mnt/data
sudo blkid /dev/sda1
sudo fdisk -l
sudo vim /etc/fstab  # add line: /dev/sda1 /mnt/data defaults 0 0
systemctl daemon-reload
sudo mount /mnt/data
sudo chown -R dmacario:dmacario /mnt/data
```

Guide: [installing new disks](https://www.tecmint.com/add-new-disk-to-an-existing-linux/)

### Ansible setup

#### Files

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

#### Tip: using Ansible Vault to handle `k3s_token` variable

First, we need to set up a password, which we will [store inside a file](https://docs.ansible.com/projects/ansible/latest/vault_guide/vault_managing_passwords.html#storing-passwords-in-files).
First, add the following to `.gitignore`:

```gitignore
*.enc  # We will use `.enc` as extension
```

Then, create a file `vault-password.enc` with proper permissions, and add your password to the file, like so:

```bash
echo "<your_password>" > ./vault-password.enc
chmod 600 ./vault-password.enc
```

> [!note]
>
> The file [./vault-password.enc](./vault-password.enc) is set as the default vault password file in [./ansible.cfg](./ansible.cfg),
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

Copy the output and paste it in [./inventory/group_vars/k3s_cluster.yml](./inventory/group_vars/k3s_cluster.yml).
Make sure you overwrite the pre-existing `k3s_token` value.

To decrypt the value (e.g., if you want to add nodes by hand), you can run:

```bash
ansible localhost -m ansible.builtin.debug -a var="k3s_token" -e "@inventory/group_vars/k3s_cluster.yml"
```

> [!note]
>
> Once the cluster is set up, you can always retrieve the token from any master node, as it will be stored in `/var/lib/rancher/k3s/server/token`.

### K3s setup

Installation of K3s cluster via Ansible, using the collection defined in <https://github.com/timothystewart6/k3s-ansible>.
This allows to effortlessly provision a K3s cluster with Highly Available control plane (using kube-vip as the load balancer), and MetalLB as service load balancer.

The main playbook is [./playbooks/k3s_install.yml](./playbooks/k3s_install.yml), and all configuration variables are defined in [./inventory/group_vars/k3s_cluster.yml](./inventory/group_vars/k3s_cluster.yml).
Notice that this file is a "simplified" version of [the "original" variables file](https://github.com/timothystewart6/k3s-ansible/blob/master/inventory/sample/group_vars/all.yml).

> [!important]
>
> The cluster does not use Tailscale IPs.
> This is because there is currently no way to define Virtual IP addresses in the Tailnet to assign to the load balancers (kube-vip, in particular), so the set up would not truly be HA.
>
> Unfortunately, this also prevents including nodes in the cluster that are not connected to the same LAN.
>
> It is however possible, by means of the [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator), to expose Kubernetes services to the Tailnet - see [installation](#setting-up-the-tailscale-kubernetes-operator).

#### IP address selection

- **Control plane virtual IP**: `192.168.178.15`
- **MetalLB range**: `192.168.178.20`-`192.168.178.29`
  - _Note_: DHCP is set up not to assign addresses in this range.

#### Installing Traefik Ingress Controller (& cert-manager)

See [./docs/traefik-setup.md](./docs/traefik-setup.md)

#### Setting up Longhorn (storage provider)

[[longhorn-storage-provider]]

#### Tailscale Kubernetes Operator

[[setting-up-the-tailscale-kubernetes-operator]]

#### Exposing workloads to Tailnet with custom domains

[[k8s-tailscale-custom-dns]]

#### Keeping Kubernetes up to date

See [Automatic K3s upgrades](/dmhome/docs/automatic-kubernetes-upgrade.md).

Keep in mind that this will (probably) break compatibility with the Ansible playbook (if planning on adding new nodes to the cluster using it).

#### Managing secrets in a GitOps way

Using [Sealed-Secrets](./docs/sealed-secrets.md)
