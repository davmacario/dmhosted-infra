---
id: longhorn
author: Davide Macario
date: 2026-02-14
aliases: []
tags:
  - homelab
  - k3s
  - storage
  - data
---

# Longhorn storage provider

## Installing Longhorn

> Longhorn is a distributed block storage system for Kubernetes, allowing to create PV and PVCs.

First, run

```bash
kubectl apply -f ./kubernetes/longhorn/namespace.yaml
```

Verify namespace creation:

```bash
kubectl get namespaces | grep longhorn
```

To ensure the requirements are installed, run the [install_cluster.yml](./playbooks/install_cluster.yml) playbook.

Additionally, it is possible to install the Longhorn Command Line Tool, following the [documentation](https://longhorn.io/docs/1.10.1/deploy/install/#longhorn-command-line-tool).
Then, run it to check and install dependencies.

> [!note]
>
> This can be done on 1 machine (either your host machine or a cluster server node).
> Dependencies will be installed on all nodes.

It is also necessary to either disable or change some settings of `multipathd`.
I chose to disable it:

<!-- TODO: add to ansible playbook -->

```bash
sudo systemctl stop multipathd
sudo systemctl disable multipathd
sudo reboot
```

Install Longhorn using Helm:

```bash
# Add the repo
helm repo add longhorn https://charts.longhorn.io

# Fetch latest charts
helm repo update

# Install Longhorn in 'longhorn-system' namespace
helm install longhorn longhorn/longhorn --namespace longhorn-system --version 1.10.1
```

Confirm successful deployment:

```bash
kubectl -n longhorn-system get pods
```

Next, set up Ingress for the Longhorn UI.

> [!tip]
>
> You can edit the value of `spec.rules[0].host` to any value you like.
> We will use local DNS (at this stage) to forward traffic directed at that domain name to the Traefik LB IP (192.168.178.20 in my case).

```bash
kubectl apply -f ./kubernetes/longhorn/longhorn-ingress.yaml
```

> [!note]
>
> Unlike the set up for the Traefik UI, we are not setting up any middleware for auth in this case.
> You can follow the same steps as in [[traefik-setup-k3s]] to do so.

Then, edit the contents of `/etc/hosts` by adding:

```conf
# Longhorn UI
192.168.178.20  longhorn.local.dmhosted.io
```

You can now access the Longhorn UI by visiting <https://longhorn.local.dmhosted.io> in your browser.

It is now possible to use `longhorn` as storage class for PVs and PVCs in Kubernetes.
Longhorn should also be the default storage class, you can check by running:

```bash
kubectl get storageclass
```

### Tip: adding secondary disks on Longhorn

2 of my nodes (`gouda` and `overvecht`) also have a secondary SATA SSD mounted at `/mnt/data`.

It is possible to tell Longhorn to also use the secondary disk by editing the node settings in the UI.

1. SSH into each of the nodes that have a secondary drive, and create a `longhorn` directory inside.
   - E.g., `mkdir /mnt/data/longhorn`
1. Log into the [Longhorn UI](https://longhorn.local.dmhosted.io)
1. Navigate to "Nodes"
1. Click on the drop-down menu for a specific node (under "Operation"), and select "Edit Node and Disks"
1. Scroll down and select "Add Disk"
1. Enter a "Name", while for "Disk Type" leave "File System".
1. The "Path" will be the path of the `longhorn` directory created previously, e.g., `/mnt/data/longhorn`
1. You can reserve some storage if you want, by setting the "Storage Reserved" value (this avoids taking up the full disk).
1. Make sure to enable "Scheduling"

Once this is set up, you should see the available size growing.

## Verify installation

[Sample manifest](https://longhorn.io/docs/1.11.0/references/examples/#pod-with-persistentvolumeclaim) for verifying that Longhorn is installed properly.

After deploying, you should see a new volume appear in the Longhorn UI.

Deleting the resources also deletes the volume.

## Adding extra storageclasses

Using the [values.yaml](../kubernetes/longhorn/values.yaml) found in this repo, the created Longhorn StorageClass will have the following settings (from `kubectl get storageclass longhorn -o yaml`):

```yaml
allowVolumeExpansion: true
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    longhorn.io/last-applied-configmap: |
      kind: StorageClass
      apiVersion: storage.k8s.io/v1
      metadata:
        name: longhorn
        annotations:
          storageclass.kubernetes.io/is-default-class: "true"
      provisioner: driver.longhorn.io
      allowVolumeExpansion: true
      reclaimPolicy: "Retain"
      volumeBindingMode: Immediate
      parameters:
        numberOfReplicas: "3"
        staleReplicaTimeout: "30"
        fromBackup: ""
        fsType: "ext4"
        dataLocality: "disabled"
        unmapMarkSnapChainRemoved: "ignored"
        disableRevisionCounter: "true"
        dataEngine: "v1"
        backupTargetName: "default"
    storageclass.kubernetes.io/is-default-class: "true"
  creationTimestamp: "2026-02-28T15:15:44Z"
  name: longhorn
  resourceVersion: "41012390"
  uid: 7baf2f37-e9af-41d6-8a02-4618d475dd39
parameters:
  backupTargetName: default
  dataEngine: v1
  dataLocality: disabled
  disableRevisionCounter: "true"
  fromBackup: ""
  fsType: ext4
  numberOfReplicas: "3" # Each volume will have 3 replicas by default
  staleReplicaTimeout: "30"
  unmapMarkSnapChainRemoved: ignored
provisioner: driver.longhorn.io
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

**Note** that this is also the default StorageClass for the cluster.

We will create extra storage classes:

- `longhorn-data-local`: same as the above, `dataLocality` is `best-effort`
- `longhorn-no-retain`: same as the above, `reclaimPolicy` is `Delete`
- `longhorn-singlecopy`: same as the above, but `numberOfReplicas` is 1, `reclaimPolicy` is `Delete`, and `dataLocality` is `strict-local`

See [extra-storageclasses.yaml](../kubernetes/longhorn/extra-storageclasses.yaml).

This allows to customize PVs and PVCs based on the specific requirements.

E.g., using `dataLocality: best-effort` guarantees that a pod and the attached PV are deployed on the same node, which minimizes latency for disk operations.

## Upgrading Longhorn (v1.11.0 -> v1.11.1)

```bash
helm repo update
```

then, upgrade all image versions referenced in [values.yaml](../kubernetes/longhorn/values.yaml) to point to the latest.
Then, apply:

```bash
helm upgrade longhorn longhorn/longhorn -n longhorn-system --values ./kubernetes/longhorn/values.yaml
```

This will upgrade all pods.

Attention points:

- Old instance manager pods will remain running until all volumes are not controlled by them anymore
  - An "easy" fix is to reboot all cluster nodes one at a time, as this will detach the volumes (when pods are turned off), and re-attach them, allowing to make the switch automatically
- Old engine images remain running, as existing volumes are still managed by them
  - To solve this, see [next section](#migrating-volumes-to-upgraded-longhorn-engine)

### Migrating volumes to upgraded Longhorn Engine

After an upgrade, you will be left with 2 running versions of the Longhorn Engine: the old one, and the new one.
Running `kubectl get engineimage -n longhorn-system` returns:

```text
NAME          INCOMPATIBLE   STATE      IMAGE                                          REFCOUNT   BUILDDATE   AGE
ei-75a03ec3   false          deployed   docker.io/longhornio/longhorn-engine:v1.11.1   35         5d5h        18h
ei-ff1cedad   false          deployed   docker.io/longhornio/longhorn-engine:v1.11.0   18         48d         34d
```

This is because the existing volumes are still "tracked" by the "old" engine.
We need to switch them over to the new engine.

This can either be done [automatically](https://longhorn.io/docs/1.11.1/deploy/upgrade/auto-upgrade-engine/), or [manually](https://longhorn.io/docs/1.11.1/deploy/upgrade/upgrade-engine/).

We will do it manually for now, but we will also add `concurrentAutomaticEngineUpgradePerNodeLimit: 2` in the [values.yaml](../kubernetes/longhorn/values.yaml), so that in the future this will (to an extent - see later) be automatic.

Manual upgrade has to be done via the Longhorn UI.

Navigate to the "Nodes" section.
If you upgraded Longhorn, you will see a green circled arrow next to the volumes whose engine version can be upgraded.
Click on the "Operation" menu for the specific volume, and select "Upgrade Engine".
Then, choose the new version you want to upgrade the volume to.

This works well for _non-strictly-local_ volumes, for which you don't even need to detach[^1] them, however, if a volume is "_strictly-local_", it is required to detach it in order to perform the upgrade.
This is the case for CNPG volumes defined using the `longhorn-singlecopy` storageclass (defined [here](../kubernetes/longhorn/extra-storageclasses.yaml)), as data locality is the best way to achieve high throughput.

[^1]: Detaching volumes is typically achieved by scaling down the deployment/statefulset/... so that all pods are shut down, and volumes are not actively being used. See [here](https://longhorn.io/docs/1.11.1/nodes-and-volumes/volumes/detaching-volumes/) for an extensive guide.

#### Migrating strictly-local Longhorn volumes

> **Disclaimer**: the steps below will cause downtime in your cluster services.
> The only way to avoid downtime when upgrading Longhorn Engine versions is to create duplicate workloads and migrate the data, then re-route traffic to the new instance(s), and, finally, shut down the old workload.
> This is clearly overkill for a homelab setup.

Steps:

1. Scale workload down
2. Manual upgrade (via Longhorn UI)
3. Scale workload up again (and check it works)

The [Longhorn documentation](https://longhorn.io/docs/1.11.1/nodes-and-volumes/volumes/detaching-volumes/) shows how to scale down common (built-in) workload resources.
For CNPG `Cluster` resources, this is achieved by means of the `hibernation` feature, which allows to gracefully shut down DB replicas without losing data.

> [!NOTE]
>
> If you have a DB, you most likely also have another workload that is supposed to use it.
> To avoid weird issues and data loss, also scale down the other workload if scaling a DB down.

##### Example: upgrading Longhorn Engine version for Vaultwarden's DB

Assuming Vaultwarden was deployed as described [here](./vaultwarden-setup.md).

We are only going to focus on the DB volumes.
The application volume can be upgraded manually (non strictly-local, as RWX).

1. Identify the workload resource for the app:

   ```bash
   kubectl get all -n vaultwarden
   ```

   which produces:

   ```text
   NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
   deployment.apps/vaultwarden   2/2     2            2           4d3h
   ```

   (Note the number of current pods: 1).

1. Scale down the application by scaling down to 0 app replicas:

   ```bash
   kubectl scale -n vaultwarden deployment vaultwarden --replicas=0
   ```

   Then check until the number of app pods is 0.

1. Get the name of the DB cluster:

   ```bash
   kubectl get clusters.postgresql.cnpg.io -n vaultwarden
   ```

   output:

   ```text
   NAME             AGE    INSTANCES   READY   STATUS                     PRIMARY
   vaultwarden-db   4d4h   3           3       Cluster in healthy state   vaultwarden-db-2
   ```

   -> The name is `vaultwarden-db`

1. Put the DB in `hibernation` mode:

   ```bash
   kubectl annotate clusters.postgresql.cnpg.io vaultwarden-db -n vaultwarden cnpg.io/hibernation=on
   ```

   You will see that the DB pods will be shut down, while PVCs (and PVs) will be left intact.
   You can also see that the volumes show up as 'detached' in the Longhorn UI.

1. From the Longhorn UI, manually upgrade the Longhorn Engine for the volumes, as explained in [previous section](#migrating-volumes-to-upgraded-longhorn-engine).
1. Unset `hibernation` mode on the DB Cluster:

   ```bash
   kubectl annotate clusters.postgresql.cnpg.io vaultwarden-db -n vaultwarden cnpg.io/hibernation-
   ```

   You can also check that the data is still there by:
   - Opening a shell into a pod: `kubectl exec -n vaultwarden -it vaultwarden-db-2 -c postgres -- /bin/bash`
   - Connecting to the app DB: `psql vaultwarden` (works since DB and user have the same name)
   - Checking that tables are still there: `\dt` (the previous step is not enough as the DB is created by CNPG)

1. Scale app back up:

   ```bash
   kubectl scale -n vaultwarden deployment vaultwarden --replicas=2
   ```

   (alternatively, if using a Helm chart, redeploy it using the same values as before).

### Shutting down old Longhorn Engine

Once all volumes are migrated, we can delete the old Longhorn engine.
By default, the old engine will be kept around.

You can list available engine versions by running:

```bash
kubectl -n longhorn-system get engineimages.longhorn.io
```

```text
NAME          INCOMPATIBLE   STATE      IMAGE                                          REFCOUNT   BUILDDATE   AGE
ei-75a03ec3   false          deployed   docker.io/longhornio/longhorn-engine:v1.11.1   48         5d7h        20h
ei-ff1cedad   false          deployed   docker.io/longhornio/longhorn-engine:v1.11.0   0          48d         34d
```

You can also find them from the UI by going to "Advanced" > "Engine Image".

If the `REFCOUNT` ("Reference Count" in the UI) is 0, you can delete the engine, either from the CLI (`k delete -n longhorn-system engineimages.longhorn.io ei-ff1cedad`), or from the UI.

**This completes the upgrade**.

---

## Links

- [Christian Lempa's Video](https://youtu.be/-ImtLXcEna8)
  - This also explains how to restore snapshots or from backups
- [Official documentation](https://longhorn.io/docs/1.11.1/)
- [Upgrade guide (1.11.0 -> 1.11.1)](https://longhorn.io/docs/1.11.1/deploy/upgrade/)
