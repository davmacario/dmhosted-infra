---
id: setting-up-truenas
author: Davide Macario
date: 2026-05-09
aliases: []
tags:
  - homelab
  - nas
---

# Setting up TrueNAS on new NAS

This guide explains the NAS setup on my new [Ugreen NASync DXP4800 Plus](https://nas.ugreen.com/products/ugreen-nasync-dxp4800-plus-nas-storage), running TrueNAS.

## Installation

1. Created bootable drive with [TrueNAS "Community Edition"](https://www.truenas.com/truenas-community-edition/) (formerly "TrueNAS Scale") using [BalenaEtcher](https://etcher.balena.io/).
   - For some reason, the bootable USB created using `dd` (usual iso -> bootable USB stick method) did not work, but I did not investigate it much.
1. Started the NAS with keyboard + mouse + screen.
   Pressed Ctrl + F12 to enter BIOS, and under "Advanced", disabled the watchdog.
   This prevents UGreen OS from automatically launching regardless of the selected boot drive.
1. Plugged the USB into the NAS, and booted, pressing Ctrl + F12 to enter boot menu.
   Then, followed all the steps to install TrueNAS on the main `nvme` drive (the 128 GB built-in one).

   > [!DANGER]
   >
   > This completely wipes Ugreen OS.
   > As of 2026, it is possible to get ISOs for UGOS from the [Ugreen website](https://nas.ugreen.com/pages/downloads).
   >
   > Alternatively, you can install an NVME drive and use it for TrueNAS, but running 2 OSes on the NAS is cumbersome, as one of the 2 will be the owner of the disks.

1. Logged into NAS locally (from IP displayed via screen connected) and created the `truenas_admin` user.

After this, the NAS is set up.
I unplugged the keyboard, mouse, and screen, and placed the NAS in its final location, with all four 4 TB disks inserted.

## Networking

Static IP assigned via DHCP: `192.167.178.254`

> [!note]
>
> `X.X.X.15` is assigned as virtual IP for the k8s api - see [cluster variables](../inventory/group_vars/k3s_cluster.yml)

## Configuring ZFS pool

I'm using 4 x 4 TB disks, and to maximize the usable space while still having redundancy, I created a RAIDZ1 pool.
This means that I achieve 12 TB of usable space and redundancy for up to 1 drive failure.

The pool is not encrypted, as I will keep the NAS in my house, and I didn't want to go through the hassle of managing encryption keys for it.
I will encrypt sensitive data anyways.

## Configuring Tailscale access

Following [Tailscale guide](https://tailscale.com/docs/integrations/truenas).

IP: `100.78.244.112`

### Set up access via K8s Traefik (Tailscale)

This is purely optional, but nice to have.

To allow connecting to the NAS over HTTPS with valid certs (using the `dmhosted.com` domain), we can use the Traefik instance(s) running in k8s as reverse proxies.

Needed K8s resources:

- `Service` to provide the route
- `EndpointSlice` to register the NAS IP + port
- `IngressRoute` to create the route
- `Certificate`

See [manifest](../kubernetes/networking/nas.yaml).

## Setting up SMB share

**Goal**: set up SMB share for documents.

Following [official docs](https://www.truenas.com/docs/scale/25.10/gettingstarted/configure/setupsharing/).

Required the creation of a dedicated user (`smb_admin`) with admin rights on SMB.
This achieves separation of concerns w.r.t. the `truenas_admin` user, used for management.

## Configuring Time Machine SMB share

Following [official guide](https://www.truenas.com/docs/scale/25.10/scaletutorials/shares/smb/setupbasictimemachinesmbshare/).

## S3-compatible storage - RustFS

Installed via TrueNAS Apps.

Ports:

- Service: 30292
- Web UI: 30293

Credentials for the UI stored in Bitwarden.

Current installation is without SSL certificate (no cert selected from TrueNAS UI).
This is to allow reaching RustFS over HTTP (for now, the traffic is witing LAN).

After creating bucket + access key from the console, verify that it works using the AWS CLI.

```bash
aws configure --profile rustfs
# ...and enter access key + secret key (+ region - anything)

# List buckets (assuming access key allows it), to skip SSL cert validation (if enabling self-signed cert) use '--no-verify-tls'
aws s3 ls --profile rustfs --endpoint-url https://192.168.178.254:30292
```

### Configuring TLS cert + domain for RustFS

To possibly expose the service over the public internet in the future, we need to encrypt traffic.
We can use the Traefik instance(s) running in K8s to act as reverse proxies to terminate the TLS connection and then forward the traffic to the NAS.

To do so, we need:

- A `Service` resource to expose the endpoints
- An `EndpointSlice` resource to register both the UI and Data endpoints of RustFS (ports 30293 and 30292, respectively), linked to the `Service`
- An `IngressRoute` resource for each port, mapping them to a specific hostname
- A `Certificate` resource per `IngressRoute` to provision valid certs

See the [manifest](../kubernetes/networking/rustfs-nas.yaml) for reference.
