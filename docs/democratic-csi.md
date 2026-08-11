---
id: democratic-csi
author: Davide Macario
date: 2026-06-13
tags:
  - homelab
  - storage
  - nas
---

# Democratic-CSI

[Democratic-CSI](https://github.com/democratic-csi/democratic-csi) is a Container Storage Interface that allows using NAS as Kubernetes storage.
In my case, the goal is to use my TrueNAS system as K8s storage.

> [!WARNING]
>
> At the time of writing (2026-06), TrueNAS deprecated the HTTP API, used by this installation of Democratic-CSI.
> For NFS storage, the alternative is [CSI-driver-NFS](./csi-driver-nfs.md).

## Why

The main benefits are:

- Easy support for RWX (read-write-many) volumes via NFS (or SMB)
- No need for local storage on each node
- No need to manually configure NFS mounts/NFS PVs on K8s, as we will have a StorageClass

## Setup

Following [this](https://wazaari.dev/blog/truenas-talos-democratic-csi) blog post for **TrueNAS Community Edition** (formerly known as _Scale_).

### On the nodes

```bash
sudo apt install nfs-common open-iscsi multipath-tools scsitools lsscsi
sudo cat <<EOF > /etc/multipath.conf
defaults {
    user_friendly_names yes
    find_multipaths yes
}
EOF
```

Actually, the commands above have been included in the [cluster installation playbook](../playbooks/install_cluster.yml).

### On the NAS

First, create a new TrueNAS user ("democratic-csi") with TrueNAS access set to "Full Admin".

Then, click on your profile (top right), and then "My API Keys".
From there, create a new key for the user created before, and store the key, as it will be needed to make Democratic-CSI work.

Then, also create another user ("democratic-csi-nfs"), with disabled password auth, that will be used as the owner of the NFS volumes.
Note down its UID and GID (3002:3002, in my case).

Next, from the "Datasets" section, create a new dataset called "k8s" and 2 children datasets "nfs" and "iscsi"[^1].
Then, further nest the "nfs" one in "volumes" and "snapshots"[^2].

Then, from the "Shares" section you can create an NFS share, and an iSCSI schare target using the 2 datasets created before, respectively.

[^1]: iSCSI will not be used for now.

[^2]: Snapshots are not set up currently, as the cluster does not have a snapshot controller yet. <https://github.com/kubernetes-csi/external-snapshotter>.

### On K8s

We will install Democratic-CSI via Helm.

```bash
helm repo add democratic-csi https://democratic-csi.github.io/charts/
helm repo update

# Get default values
helm show values democratic-csi/democratic-csi
```

#### NFS

For NFS, we need:

- Secret containing the "driver config", referencing:
  - API key (allows API calls on behalf of user "democratic-csi")
  - NAS IP
  - Owner of the created datasets (will have to match with the "democratic-csi-nfs" user), and its UID and GID
  - Path of the volumes dataset and of the snapshots dataset
- [values.yaml](../kubernetes/democratic-csi/nfs/values.yaml), referencing:
  - The secret from above (still, the `driver` needs to be entered here too)
  - The `StorageClasses` created using this driver. We will create 2:
    - `democratic-nfs`, with reclaim policy `Delete`
    - `democratic-nfs-retain`, with reclaim policy `Retain`
  - **Note**: for now, we disable snapshots, as the cluster does not support them yet

Then, deploy democratic-csi with the name `nfs`:

```bash
kubectl apply -f nfs/driver-config-secret.yaml
helm upgrade --install --namespace democratic-csi --values nfs/values.yaml nfs democratic-csi/democratic-csi
```

To check that everything worked, deploy the [test manifests](../kubernetes/democratic-csi/nfs/test-sc.yaml), which include a pod and a PVC using the newly created `democratic-nfs` StorageClass.
You can log into the pod and navigate to `/data`, where the PV is mounted, to verify the configuration worked.

#### iSCSI

> Not done now, as not needed (nodes have 1 TB of disk).
