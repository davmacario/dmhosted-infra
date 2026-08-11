---
id: homelab-setup
author: Davide Macario
date: 2026-08-11
tags:
  - homelab
---

# Homelab Setup - Bare-Metal

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

### NAS-UGO

[Ugreen NASync DXP4800 Plus](https://ai.ugreen.com/products/ugreen-nasync-dxp4800-plus-nas-storage), with 4x4 TB drives.
Runs [TrueNAS](https://www.truenas.com/) instead of the pre-installed Ugreen OS.

IPs:

- local: 192.168.178.254
- tailscale: 100.78.244.112

Specs:

- Intel Pentium Gold 8505 (5c/5t)
- 8 GB ddr5 RAM
- 128 GB SSD (boot)
- 4 x 4 TB hard-drives (RAIDZ1, so approx. 12 TB usable)

[Installation](./setting-up-truenas.md)

---

### _Network setup_

**CIDR**: `192.168.178.0/24`

- Router (default GW): `192.168.178.1`
- DHCP range: `192.168.178.30`-`192.168.178.255`
  - This means that anything we want to use a static IP for should be in `192.168.178.2`-`192.168.178.29`
  - This includes Kubernetes services.

> [!NOTE]
>
> This information is outdated.
> See [DNS setup using AdGuardHome](./self-hosted-dns-adguard-home.md).

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

### DNS setup

To easily create DNS records for private services, I decided to deploy a custom DNS
server for my network (which came with the added benefit of including network-wide
ad blocking): AdGuard Home.

The installation is documented [here](./self-hosted-dns-adguard-home.md).
