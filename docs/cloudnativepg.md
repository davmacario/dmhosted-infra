---
id: cloudnativepg
author: Davide Macario
date: 2026-03-02
tags:
  - homelab
  - k3s
  - databases
---

# CloudNativePG - Databases on Kubernetes

**Goal**: run resilient and persistent databases on Kubernetes using [CloudNativePG](https://cloudnative-pg.io/).

## What is CloudNativePG

It is a Kubernetes Controller for PostgreSQL databases.
It allows to create highly available and replicated PostgreSQL DBs, taking care of replication, hot standby replicas across the cluster, etc.

This is achieved through CRDs for the most common DB functionalities.

### K8s - stateless vs. stateful

In general, people don't recommend running stateful workloads on K8s.
This is because, by definition, pods are ephemeral (_cattle_, not _pets_).

It is possible, however, to still treat pods as _cattle_, but introduce "external" (to pods) mechanisms that ensure data persistence, replication, and resilience.
The basic example is using Storage Classes, such as Longhorn, which ensure data is replicated and (optionally) backed up externally, but also, as in CNPG, using custom resources (see CNPG Operator), that perform replication.

## Target setup - integration with existing cluster

> TODO
>
> Elaborate on:
>
> - Longhorn compatibility (to be avoided, prefer local disk and let CNPG handle resilience and replication)

## Installation

Using the manifest.

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.28/releases/cnpg-1.28.1.yaml
```

### Installing the `cnpg` `kubectl` plugin

This plugin is very handy to quickly inspect CNPG databases.

Install it via the script:

```bash
curl -sSfL \
  https://github.com/cloudnative-pg/cloudnative-pg/raw/main/hack/install-cnpg-plugin.sh | \
  sudo sh -s -- -b /usr/local/bin
```

## Upgrading

See [upgrade guide](https://cloudnative-pg.io/docs/1.28/installation_upgrade#upgrades).

> [!IMPORTANT]
>
> Always read the release notes for possible extra steps.

_In general_, the process is:

1. Apply the latest manifest (same as in [previous section](#installation)) - this updates the **controller** instance(s).
2. Making sure the update of the **instance manager** is initiated automagically after the 1st step.

## Testing CNPG

Verify installation by deploying the following manifest:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: database-test
  labels:
    name: database-test
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: demo-cluster
  namespace: database-test
spec:
  instances: 3
  storage:
    storageClass: local-path # Not using Longhorn
    size: 1Gi
```

This will take some time, as it is required to:

1. Pull the image
2. Run a helper (initdb) to set up DB
3. Create DB pod
4. ...and repeat for each of the replicas

> [!TIP]
>
> For the full API definition for Cluster resources, see [docs](https://cloudnative-pg.io/docs/1.28/cloudnative-pg.v1/#cluster)

### Using the `cnpg` kubectl plugin

After launching our demo cluster, we can use the `cnpg` plugin for `kubectl`.

Get the status:

```bash
kubectl cnpg status <cluster-name>
# In our case:
#       kubectl cnpg status demo-cluster
```

Sample output:

```text
$ k cnpg status demo-cluster -n database-test
Cluster Summary
Name                     database-test/demo-cluster
System ID:               7615311156470738965
PostgreSQL Image:        ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
Primary instance:        demo-cluster-1
Primary promotion time:  2026-03-09 17:36:44 +0000 UTC (5m58s)
Status:                  Cluster in healthy state
Instances:               3
Ready instances:         3
Size:                    128M
Current Write LSN:       0/6059E18 (Timeline: 1 - WAL File: 000000010000000000000006)

Continuous Backup not configured

Streaming Replication status
Replication Slots Enabled
Name            Sent LSN   Write LSN  Flush LSN  Replay LSN  Write Lag  Flush Lag  Replay Lag  State      Sync State  Sync Priority  Replication Slot
----            --------   ---------  ---------  ----------  ---------  ---------  ----------  -----      ----------  -------------  ----------------
demo-cluster-2  0/6059E18  0/6059E18  0/6059E18  0/6059E18   00:00:00   00:00:00   00:00:00    streaming  async       0              active
demo-cluster-3  0/6059E18  0/6059E18  0/6059E18  0/6059E18   00:00:00   00:00:00   00:00:00    streaming  async       0              active

Instances status
Name            Current LSN  Replication role  Status  QoS         Manager Version  Node
----            -----------  ----------------  ------  ---         ---------------  ----
demo-cluster-1  0/6059E18    Primary           OK      BestEffort  1.28.1           gouda
demo-cluster-2  0/6059E18    Standby (async)   OK      BestEffort  1.28.1           heiloo
demo-cluster-3  0/6059E18    Standby (async)   OK      BestEffort  1.28.1           overvecht
```

### Testing DB usability

To open a shell inside one of the DB containers, run:

```bash
kubectl exec -n database-test -it demo-cluster-1 -c postgres -- bash
```

You can then run `psql` to log into the DB (no auth needed, since on localhost).

Run `\l` to list the available databases.

Sample SQL script:

```sql
-- Create table
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100)
);

-- Insert records
INSERT INTO users (name, email) VALUES
  ('Alice', 'alice@example.com'),
  ('Bob', 'bob@example.com');
```

Running `\dt`, you can see the `users` table was created successfully.

Then, you can disconnect from the pod, and log into a different one of the same cluster (e.g., `demo-cluster-2`).
Running `\dt` in `psql` will show that the same table we created before is also available in this pod!

### Connecting to the DB

CNPG also takes care of creating secrets for the cluster.

You can list them using:

```bash
kubectl get secrets -n database-test
```

Resulting in:

```text
NAME                       TYPE                       DATA   AGE
demo-cluster-app           kubernetes.io/basic-auth   11     21m
demo-cluster-ca            Opaque                     2      21m
demo-cluster-replication   kubernetes.io/tls          2      21m
demo-cluster-server        kubernetes.io/tls          2      21m
```

The `demo-cluster-app` secret (`*-app`) is the one containing the DB credentials (alongside the connection information).

We can then run

```bash
k get -n database-test secrets/demo-cluster-app -o yaml
```

to get the contents of the secret (b64-encoded):

```yaml
# Note: the following was cleaned up
apiVersion: v1
kind: Secret
metadata:
  name: demo-cluster-app
  namespace: database-test
data:
  dbname: YXBw
  fqdn-jdbc-uri: amRiYzpwb3N0Z3Jlc3FsOi8vZGVtby1jbHVzdGVyLXJ3LmRhdGFiYXNlLXRlc3Quc3ZjLmNsdXN0ZXIubG9jYWw6NTQzMi9hcHA/cGFzc3dvcmQ9Sng5dHVjZEpxTlN6SXZHMFNxOUlBZEdZaTNXQnVEZUZ5YmcxbEtwS3k3SDBvNnpqYTRTVWFnaFNybUhaOW9ldSZ1c2VyPWFwcA==
  fqdn-uri: cG9zdGdyZXNxbDovL2FwcDpKeDl0dWNkSnFOU3pJdkcwU3E5SUFkR1lpM1dCdURlRnliZzFsS3BLeTdIMG82emphNFNVYWdoU3JtSFo5b2V1QGRlbW8tY2x1c3Rlci1ydy5kYXRhYmFzZS10ZXN0LnN2Yy5jbHVzdGVyLmxvY2FsOjU0MzIvYXBw
  host: ZGVtby1jbHVzdGVyLXJ3
  jdbc-uri: amRiYzpwb3N0Z3Jlc3FsOi8vZGVtby1jbHVzdGVyLXJ3LmRhdGFiYXNlLXRlc3Q6NTQzMi9hcHA/cGFzc3dvcmQ9Sng5dHVjZEpxTlN6SXZHMFNxOUlBZEdZaTNXQnVEZUZ5YmcxbEtwS3k3SDBvNnpqYTRTVWFnaFNybUhaOW9ldSZ1c2VyPWFwcA==
  password: Sng5dHVjZEpxTlN6SXZHMFNxOUlBZEdZaTNXQnVEZUZ5YmcxbEtwS3k3SDBvNnpqYTRTVWFnaFNybUhaOW9ldQ==
  pgpass: ZGVtby1jbHVzdGVyLXJ3OjU0MzI6YXBwOmFwcDpKeDl0dWNkSnFOU3pJdkcwU3E5SUFkR1lpM1dCdURlRnliZzFsS3BLeTdIMG82emphNFNVYWdoU3JtSFo5b2V1Cg==
  port: NTQzMg==
  uri: cG9zdGdyZXNxbDovL2FwcDpKeDl0dWNkSnFOU3pJdkcwU3E5SUFkR1lpM1dCdURlRnliZzFsS3BLeTdIMG82emphNFNVYWdoU3JtSFo5b2V1QGRlbW8tY2x1c3Rlci1ydy5kYXRhYmFzZS10ZXN0OjU0MzIvYXBw
  user: YXBw
  username: YXBw
```

> [!TIP]
>
> Using `k9s`, it is possible to easily decode secrets (press `x` when selecting a secret).

Decoding the values:

```yaml
dbname: app
fqdn-jdbc-uri: jdbc:postgresql://demo-cluster-rw.database-test.svc.cluster.local:5432/app?password=Jx9tucdJqNSzIvG0Sq9IAdGYi3WBuDeFybg1lKpKy7H0o6zja4SUaghSrmHZ9oeu&user=app
fqdn-uri: postgresql://app:Jx9tucdJqNSzIvG0Sq9IAdGYi3WBuDeFybg1lKpKy7H0o6zja4SUaghSrmHZ9oeu@demo-cluster-rw.database-test.svc.cluster.local:5432/app
host: demo-cluster-rw
jdbc-uri: jdbc:postgresql://demo-cluster-rw.database-test:5432/app?password=Jx9tucdJqNSzIvG0Sq9IAdGYi3WBuDeFybg1lKpKy7H0o6zja4SUaghSrmHZ9oeu&user=app
password: Jx9tucdJqNSzIvG0Sq9IAdGYi3WBuDeFybg1lKpKy7H0o6zja4SUaghSrmHZ9oeu
pgpass: |
  demo-cluster-rw:5432:app:app:Jx9tucdJqNSzIvG0Sq9IAdGYi3WBuDeFybg1lKpKy7H0o6zja4SUaghSrmHZ9oeu
port: "5432"
uri: postgresql://app:Jx9tucdJqNSzIvG0Sq9IAdGYi3WBuDeFybg1lKpKy7H0o6zja4SUaghSrmHZ9oeu@demo-cluster-rw.database-test:5432/app
user: app
username: app
```

The values can be passed to the application (**by referencing the secret itself!**).

As for how to set up networking, the CNPG operator also creates Service resources for our DB.
Running `k get svc -n database-test` returns:

```text
NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
demo-cluster-r    ClusterIP   10.43.192.11    <none>        5432/TCP   25m
demo-cluster-ro   ClusterIP   10.43.239.139   <none>        5432/TCP   25m
demo-cluster-rw   ClusterIP   10.43.252.192   <none>        5432/TCP   25m
```

**Note** that there are different services depending on the type of access needed (rw, ro)!

This means that, if we want to connect to a DB from a Pod in k8s, we can just grab the DNS name of the service and pass it as the `DB_HOST` for our application.

## Operator configuration

> TODO

[Docs](https://cloudnative-pg.io/docs/1.28/operator_conf#available-options)

## Backing up CNPG Clusters

> [!NOTE]
>
> This section will use RustFS (S3 compatible storage) running on the NAS.
> See [NAS setup guide](./setting-up-truenas.md)

### Installing Barman Cloud plugin

As of the latest version of CNPG, the built-in Barman capabilities are deprecated in favor of the [Barman Cloud CNPG-I plugin](https://cloudnative-pg.io/plugin-barman-cloud/).
This plugin separates the responsibilities between DB cluster administration and backups.

[Installation steps](https://cloudnative-pg.io/plugin-barman-cloud/docs/installation/).
Resources will be created in the `cnpg-system` namespace.

Summed up:

```bash
# Create CRDs + set up required resources
kubectl apply -f \
        https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.12.0/manifest.yaml

# Check that deployment is running
kubectl rollout status deployment \
  -n cnpg-system barman-cloud
# Returns:
#   deployment "barman-cloud" successfully rolled out
```

### Setting up backups

CNPG provides `Backup` and `ScheduleBackup` resources that allow to back up WAL files to S3-compatible storage using Barman.

We will assume `http://192.168.178.254:30292` is the RustFS data endpoint, and we will set up automated backups of the [Sparkyfitness CNPG Cluster](../kubernetes/apps/sparkyfitness/database.yaml).

First, from RustFS, we need to create a bucket to store the backups.
The bucket name is `cnpg-backups`.

Then, we need a key ID + secret key pair.
We will place them inside a Secret (`sparkyfitness-cnpg-rustfs-secret`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sparkyfitness-cnpg-rustfs-secret
  namespace: sparkyfitness
type: Opaque
stringData:
  ACCESS_KEY_ID: "<your-access-key-id>"
  ACCESS_SECRET_KEY: "<your-access-secret-key>"
```

Then, after installing the [Barman Cloud plugin](#installing-barman-cloud-plugin), we can define an `ObjectStore` resource identifying the specific target location for our backup.

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: rustfs-store
  namespace: sparkyfitness
  labels:
    app: sparkyfitness-cnpg
spec:
  configuration:
    destinationPath: s3://cnpg-backups/sparkyfitness/
    endpointURL: http://192.168.178.254:30292
    s3Credentials:
      accessKeyId:
        name: sparkyfitness-cnpg-rustfs-secret
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: sparkyfitness-cnpg-rustfs-secret
        key: ACCESS_SECRET_KEY
    wal:
      compression: gzip
  retentionPolicy: 30d
```

This configures backups to end up in the `cnpg-backups` bucket, at the `sparkyfitness/` directory.
Retention policy is 30 days.

Then, we modify the `Cluster` definition to use the `ObjectStore` we just defined by adding the following section to `spec`:

```yaml
spec:
  # ...
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: rustfs-store
```

This will **recreate the DB pods** (this is normal!!), as it will add sidecar containers running Barman.

Then, just define `Backup` and `ScheduledBackup` resources to execute backups using the `ObjectStore`.

Declarative backup:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: test-backup
spec:
  cluster:
    name: sparkyfitness-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

Alternatively, run a backup imperatively using the `cnpg` kubectl plugin:

```bash
kubectl cnpg backup -n <namespace> <cluster-name> \
  --method=plugin \
  --plugin-name=barman-cloud.cloudnative-pg.io
```

> [!NOTE]
>
> You can safely delete a `backups.postgres.cnpg.io` resource without it deleting the data on the bucket.
> Note that the retention policy defined in the `ObjectStore` will still be applied.

Scheduled backup definition (weekly backup):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: sparkyfitness-rustfs-backup
  namespace: sparkyfitness
spec:
  cluster:
    name: sparkyfitness-db
  schedule: "0 0 0 * * 0" # Every sunday at 00:00
  backupOwnerReference: self
  immediate: true # Trigger backup when creating resource
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

#### Restoring backups

See [docs](https://cloudnative-pg.io/plugin-barman-cloud/docs/usage/#restoring-a-cluster).

---

## Links

- [Video - Mischa Van Den Burg](https://youtu.be/g59ki9z2SO8?si=eYjnJsvVTPfIQN2K)
- [CNPG Cluster API definition](https://cloudnative-pg.io/docs/1.28/cloudnative-pg.v1/#cluster)
- [CNPG in the Homelab with Longhorn](https://medium.com/@camphul/cloudnative-pg-in-the-homelab-with-longhorn-b08c40b85384)
