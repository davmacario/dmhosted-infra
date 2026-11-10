---
id: longhorn
author: Davide Macario
date: 2026-02-14
tags:
  - homelab
  - k3s
  - storage
  - data
---

# Longhorn Storage Provider

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

To ensure the requirements are installed, run the [install_cluster.yml](../playbooks/install_cluster.yml) playbook.

Additionally, it is possible to install the Longhorn Command Line Tool, following the [documentation](https://longhorn.io/docs/1.10.1/deploy/install/#longhorn-command-line-tool).
Then, run it to check and install dependencies.

> [!NOTE]
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

> [!TIP]
>
> You can edit the value of `spec.rules[0].host` to any value you like.
> We will use local DNS (at this stage) to forward traffic directed at that domain name to the Traefik LB IP (192.168.178.20 in my case).

```bash
kubectl apply -f ./kubernetes/longhorn/longhorn-ingress.yaml
```

> [!NOTE]
>
> Unlike the set up for the Traefik UI, we are not setting up any middleware for auth in this case.
> You can follow the same steps as in [Traefik setup](./traefik-setup.md#setting-up-dashboard-access) to do so.

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

   > [!NOTE]
   >
   > If `concurrentAutomaticEngineUpgradePerNodeLimit: 2`, the engine image
   > will upgrade automatically once the volume is detached.

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

## Migrating Longhorn to ArgoCD

Followed same format as kube-prometheus stack.

One thing needed was to create sealed secret for Longhorn UI.

## Upgrading Longhorn (v1.11.1 -> v1.12.)

See [guide](https://longhorn.io/docs/1.12.0/deploy/upgrade/#upgrading-longhorn).
Specifically, [v1.11 -> v1.12](https://longhorn.io/docs/1.12.0/deploy/upgrade/longhorn-manager/).

### Upgrading Longhorn Manager (automated)

Just update the values (I'm pinning longhorn image versions) and the ArgoCD Application to point to v1.12.1.

### Upgrading Longhorn Engine

Given [values.yaml](../kubernetes/longhorn/values.yaml) contains

```yaml
defaultSettings:
  # ...
  concurrentAutomaticEngineUpgradePerNodeLimit: 2
```

Longhorn volumes will perform an online Engine upgrade, however this will only work for volumes that are not strictly local.

To migrate the rest, we will have to peform the same steps as in
[Migrating strictly-local Longhorn volumes](#migrating-strictly-local-longhorn-volumes).
Luckily, having set `concurrentAutomaticEngineUpgradePerNodeLimit: 2`, we don't need to manually upgrade the engine version from the UI, as this will happen automatically once the volumes are detached.

Service checklist

- [x] forgejo
- [x] immich
- [x] vaultwarden
- [x] firefly-iii
- [x] speedtest-tracker
- [x] sparkyfitness

#### FIX: Missing Longhorn Metrics Collection

**Issue**: the new chart version (v1.12.1) introduces a deny-all policy on traffic coming from
outside the namespace to Longhorn pods, via a `NetworkPolicy` resource.

The solution (besides being able to avoid this via specific entries in values.yaml) is to add
a `NetworkPolicy` to allow traffic from the `monitoring` namespace on port 9500 (used to
expose the Prometheus metrics).

See [allow-monitoring-networkpolicy.yaml](../kubernetes/longhorn/allow-monitoring-networkpolicy.yaml):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: longhorn-manager-allow-monitoring
  namespace: longhorn-system
spec:
  podSelector:
    matchLabels:
      app: longhorn-manager
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - port: 9500
          protocol: TCP
```

## Default backup target (RustFS)

Longhorn ships with a `default` BackupTarget, which every StorageClass references through `backupTargetName: default`, but its URL is empty.
We point it at the RustFS instance on the NAS, so backups can be taken manually from the UI.
No recurring snapshot/backup jobs are defined.

1. On RustFS, create a `longhorn-backups` bucket and an access key restricted to it, with the following policy:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetBucketLocation",
           "s3:ListBucket",
           "s3:ListBucketMultipartUploads"
         ],
         "Resource": ["arn:aws:s3:::longhorn-backups"]
       },
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject",
           "s3:AbortMultipartUpload",
           "s3:ListMultipartUploadParts"
         ],
         "Resource": ["arn:aws:s3:::longhorn-backups/*"]
       }
     ]
   }
   ```

   `s3:DeleteObject` is required: Longhorn creates and removes lock objects during every backup, and deletes blocks when a backup is removed.

   > [!WARNING]
   >
   > Do not set lifecycle/retention rules on the bucket.
   > Longhorn manages the backupstore contents itself, and deleting objects behind its back corrupts backups.

1. Create the credentials secret, `kubernetes/longhorn/backup-target-secret.yaml` (git-ignored):

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: longhorn-backup-target
     namespace: longhorn-system
   type: Opaque
   stringData:
     AWS_ACCESS_KEY_ID: <access key>
     AWS_SECRET_ACCESS_KEY: <secret key>
     AWS_ENDPOINTS: https://rustfs.internal.dmhosted.com
   ```

   The endpoint goes in the secret, not in the backup target URL.
   If the endpoint certificate is not trusted by the Longhorn images, add its CA as `AWS_CERT` (PEM).

1. Seal it (see [Sealed Secrets](./sealed-secrets.md)):

   ```bash
   kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
     -o yaml < kubernetes/longhorn/backup-target-secret.yaml \
     > kubernetes/longhorn/backup-target-secret-sealed.yaml
   ```

1. Set the target in [values.yaml](../kubernetes/longhorn/values.yaml):

   ```yaml
   defaultBackupStore:
     backupTarget: s3://longhorn-backups@eu-west-1/ # trailing slash is required
     backupTargetCredentialSecret: longhorn-backup-target
     pollInterval: 300
   ```

   The chart writes these into the `longhorn-default-resource` ConfigMap, which longhorn-manager reconciles into the `default` BackupTarget.

1. Once ArgoCD syncs, check that the target is available:

   ```bash
   kubectl -n longhorn-system get backuptargets.longhorn.io default -o jsonpath='{.status.available}'
   ```

   It should print `true`.
   To take a backup, go to "Volume" in the UI, select the volume, and choose "Create Backup".
   Backups show up under "Backup and Restore" > "Backups".

## Upgrading Longhorn (v1.12.1 -> v1.13.0)

See [guide](https://longhorn.io/docs/1.13.0/deploy/upgrade/longhorn-manager/) and [important notes](https://longhorn.io/docs/1.13.0/important-notes/).
Only upgrades from v1.12.x are supported, Kubernetes must be v1.34 or later, and **downgrades are not possible**.

What changes with our values:

- New `longhorn-global-manager` Deployment (3 replicas, 1 leader), which takes the cluster-wide Pod/PV controllers out of the `longhorn-manager` DaemonSet.
- New CSI controller ServiceAccount, with cluster-wide `get` on Secrets (`csi.allowControllerSecretAccess: true`, default).
- New CRDs (`instancemanagerupgrades`, `instancemanagerupgradecontrols`, `snapshotgroups`).
- No settings removed or renamed.

### Pre-flight

- No volume is `faulted`/`degraded` (`kubectl -n longhorn-system get volumes.longhorn.io`), and no backing image is failed.
- Recent CNPG backups exist, and non-CNPG volumes have a manual backup (see [Default backup target](#default-backup-target-rustfs)).
- `preUpgradeChecker.upgradeVersionCheck: false` is already set, which disables the pre-upgrade Job (recommended for ArgoCD).

### Upgrading Longhorn Manager (automated)

Bump the ArgoCD Application and the pinned images to v1.13.0 (Renovate does this), then merge.
Check that all pods in `longhorn-system` are running, including `longhorn-global-manager-*`, and that the UI loads.

> [!WARNING]
>
> Sync the `root` app first, and only sync `longhorn` once it shows the new `targetRevision`.
> The chart version comes from [longhorn.yaml](../kubernetes/argocd-apps/longhorn.yaml) (synced by `root`), while the values are read straight from `main`.
> Syncing `longhorn` too early renders the **old chart with the new images**: the v1.13.0 `longhorn-manager` then runs with the v1.12.1 ClusterRole and CRDs, and keeps logging `... is forbidden: ... cannot list resource "instancemanagerupgrades"` (pods stuck at 1/2).
> Fix: terminate the running sync operation, refresh, and sync again.

### Upgrading Longhorn Engine

Same as [v1.12](#upgrading-longhorn-engine): replicated volumes are upgraded online automatically, strictly-local volumes (CNPG) are upgraded once detached, following [Migrating strictly-local Longhorn volumes](#migrating-strictly-local-longhorn-volumes).

> [!IMPORTANT]
>
> All the app Applications have `selfHeal: true`, which immediately scales workloads back up.
> Before scaling anything down, disable auto-sync on `root` (it would otherwise restore the child Applications' sync policy) and on the app:
>
> ```bash
> kubectl -n argocd patch application root --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
> kubectl -n argocd patch application <app> --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
> ```
>
> Once done, re-enable it (app first, `root` last); selfHeal then restores the replica counts:
>
> ```bash
> kubectl -n argocd patch application <app> --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
> ```

For each service: pause the app, scale it to 0, hibernate the DB, wait for the volumes to be `detached` and on the new engine (`kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=PVC:.status.kubernetesStatus.pvcName,STATE:.status.state,IMG:.status.currentImage`), remove hibernation, wait for the DB to be healthy, re-enable auto-sync.

Service checklist

- [x] speedtest-tracker
- [x] sparkyfitness
- [x] firefly-iii
- [x] forgejo
- [x] vaultwarden
  - ArgoCD ignores `/spec/replicas` (HPA-managed), and the HPA does nothing at 0 replicas: scale back to 1 manually
- [x] immich (also detaches the `immich-machine-learning` volume)

Other strictly-local (`longhorn-singlecopy`) volumes, no DB to hibernate:

- [x] notes-rag (`notes-rag-persistent`)
- [x] Loki (`storage-loki-0`): scale the `loki` StatefulSet (app `monitoring-loki`)
- [x] Prometheus: set `spec.replicas: 0` on the `Prometheus` CR (app `monitoring`)

Then [shut down the old engine](#shutting-down-old-longhorn-engine) once its `REFCOUNT` is 0, and check that Longhorn metrics are still collected.

#### Old instance managers left behind

Volumes upgraded online keep their engine process on the **old** instance manager (reserving the old CPU request) until they are detached once.
List the volumes still on them:

```bash
kubectl -n longhorn-system get engines.longhorn.io -o custom-columns=VOL:.spec.volumeName,IM:.status.instanceManagerName
```

A rolling restart is not enough, as the new pod lands on the same node and reuses the attachment: scale the workload to 0 and back (same ArgoCD pause as above).
In this upgrade: karakeep (`web`, `meilisearch`), stirling-pdf, uptime-kuma, grafana, and Alertmanager (`spec.replicas: 0` on the `Alertmanager` CR).
The old instance managers are removed once they have no engines/replicas left.

## Reducing Longhorn CPU usage

Most of Longhorn's CPU goes to the instance managers, which run one engine process per volume and one process per replica.
Changes in [values.yaml](../kubernetes/longhorn/values.yaml):

- `guaranteedInstanceManagerCPU: '{"v1":"5","v2":"12"}'`: each instance manager **requests** a % of the node CPU (default 12%, i.e. 480m on a 4-core node), regardless of actual usage.
  Only applied when instance manager pods are recreated (e.g., after an engine upgrade).
- `engineImagePodLivenessProbePeriod: 30`: the engine image pods are probed every 5s by default.
- `metrics.serviceMonitor.interval: 60s`: each scrape walks all volumes and replicas.

Not set in values, but the biggest lever: reduce the number of replicas of low-value volumes (caches, search indexes, ...) from 3 to 2 (or 1), from the volume's "Update Replicas Count" operation in the UI.

---

## Links

- [Christian Lempa's Video](https://youtu.be/-ImtLXcEna8)
  - This also explains how to restore snapshots or from backups
- [Official documentation](https://longhorn.io/docs/1.11.1/)
- [Upgrade guide (1.11.0 -> 1.11.1)](https://longhorn.io/docs/1.11.1/deploy/upgrade/)
