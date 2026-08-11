---
id: db-migration-sparkyfitness
author: Davide Macario
date: 2026-03-09
tags:
  - homelab
  - k3s
  - database
---

# Database Migration for Sparkyfitness

**Goal**: migrate Sparkyfitness' database (PostgreSQL) from a `StatefulSet` to a CloudNativePG `Cluster` (without losing data).

## Plan

- [x] Set up custom `StorageClass` using Longhorn, with:
  1. Data locality (`dataLocality: strict-local`)
  2. No replication (`numberOfReplicas: "1"`)
- [x] Create manifest for `Cluster`
  - [x] Configure secrets, if needed. (We can likely reuse existing ones).
- [x] Back up old DB
  - **Important**: scale down backend (& frontend?) before
- [x] Launch new DB
- [x] Restore DB from backup
- [x] Update Deployment of backend to point to new instance & apply
- [x] Check new DB is used correctly (maybe scale down old DB)

## Setting up custom `StorageClass`

See [extra Longhorn StorageClasses](../kubernetes/longhorn/extra-storageclasses.yaml), `longhorn-singlecopy`.

The requirements are:

1. Data locality: ensures the Pod and PV are always located on the same node.
2. No replicas: replication is handled by the CNPG Operator

In any case, we will run 3 replicas of the DB on 3 nodes, so all nodes will have a replica.

## Creating `Cluster` manifest

See [API reference](https://cloudnative-pg.io/docs/1.28/cloudnative-pg.v1/#cluster) for all possible configuration values.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: sparkyfitness-cnpg
  namespace: sparkyfitness
  labels:
    app: sparkyfitness-cnpg
spec:
  description: "Database for SparkyFitness"
  inheritedMetadata:
    labels:
      app: sparkyfitness-cnpg
  imageName: ghcr.io/cloudnative-pg/postgresql:15-minimal-trixie
  imagePullPolicy: IfNotPresent
  instances: 3
  storage:
    storageClass: longhorn-singlecopy
    size: 20Gi
  bootstrap:
    initdb:
      database: sparkyfitness
      owner: sparkyapp
      secret:
        name: sparkyfitness-app-cnpg-secret
  managed:
    roles:
      - name: sparky
        ensure: present
        login: true
        superuser: true
        createdb: true
        passwordSecret:
          name: sparkyfitness-cnpg-secret
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 300m
      memory: 512Mi
```

> [!NOTE]
>
> The Cluster `spec` also includes a `bootstrap` configuration, which allows to bootstrap the DB contents from either a
> WAL dump (`recovery`), or an existing cluster/DB (`pg_basebackup`).
> On paper, `pg_basebackup` sounds ideal, however, this is only usable if the existing DB has been configured to accept
> replication connections, and have `wal_level = replica` in its `postgresql.conf`[^1].
> This is not the case, and changing these settings may cause damage to the DB.

[^1]: _this was a suggestion from Claude_

A few notes:

- The Secrets expected by CNPG to create users have to contain the `username` and `password` key (it is not possible to customize them).
  For this reason, I had to also define `sparkyfitness-app-cnpg-secret` and `sparkyfitness-cnpg-secret` (which actually contain the same credentials as the old secrets).
  I just created them as:

  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: sparkyfitness-cnpg-secret
    namespace: sparkyfitness
  type: Opaque
  data:
    username: <b64-encoded-user>  # sparky
    password: <b64-encoded-password>
  ---
  apiVersion: v1
  kind: Secret
  metadata:
    name: sparkyfitness-app-cnpg-secret
    namespace: sparkyfitness
  type: Opaque
  data:
    username: <b64-encoded-user> # sparkyapp
    password: <b64-encoded-password>
  ```

- By default, CNPG Cluster resources will create the `postgres` user as the superuser for the DB. This cannot be changed (you can only tune the password).
  In my previous deployment, I had set `POSTGRES_USER` to `sparky`, which made it so that the superuser was `sparky`.
  To solve this, I defined the `sparky` user (superuser) in the `spec:managed:roles[0]` section, to make sure the user was created with the right permissions.
  It looks like this user is only set up to perform table creation and schema migrations, so for now it is not (probably) used.
- The `sparkyapp` user, and the `sparkyfitness` DB were created using `spec:bootstrap:initdb`.
- I switched to a CNPG image, which, unlike the one I used previously (`postgres:15-alpine`), does not run as root, and has a read-only fs (except for DB data directory)

## Backing up the old DB

> [!TIP]
>
> To prevent some DB transaction from happening between backup and restore, temporarily scale the replicas of the sparkyfitness backend to 0:
> `kubectl scale -n sparkyfitness deployment sparkyfitness-backend --replicas=0`
>
> Remember to set `--replicas=1` once the migration is complete.

Log into the old Pod:

```bash
kubectl exec -n sparkyfitness -it sparkyfitness-db-0 -c postgres -- /bin/bash
```

Then, as a sanity check, I logged into the DB:

```bash
psql sparkyfitness -U sparky
```

and ran:

```sql
-- List databases: displays `sparkyfitness`, among others. Confirms that one is the only useful table
\l

-- List tables in current DB (`sparkyfitness`). Displays a bunch of tables
\dt

-- List users: displays `sparky` (superuser), and `sparkyapp` (app user)
\du
```

Then, back into bash, I backed up the `sparkyfitness` _database_ (and only that one)

```bash
pg_dump -U sparky -d sparkyfitness --format=plain > /root/postgres_backup.sql
```

> [!NOTE]
>
> In case you want to back up all the contents of the DB instance, use `pg_dumpall`.
> This will also export the users and other DBs.

Running `head -n 20` on the file confirms it is a dump of all the SQL commands ran on the DB so far, which can be executed on a separate DB to restore it.

Then, we can copy the backup to our local machine:

```bash
kubectl cp sparkyfitness/sparkyfitness-db-0:/root/postgres_backup.sql ./postgres_backup.sql
```

Once the CNPG `Cluster` is up, you can restore the DB backup as:

```bash
kubectl exec -n sparkyfitness sparkyfitness-cnpg-1 -i -c postgres -- psql -U postgres -d sparkyfitness < ./postgres_backup.sql
```

This is nice, as it prevents having to copy the backup in the running container (which has a read-only fs, except for the DB data directory).
The DB is now restored.

You can check by running `kubectl exec ...` in the container instance, log into `psql`, and check that the same contents of the old DB are there.

## Updating the `sparkyfitness-backend` Deployment

Changes:

- Switch to new Secrets
- Point to CNPG DB rw Service

Resulting manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sparkyfitness-backend
  namespace: sparkyfitness
  labels:
    app: sparkyfitness-backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sparkyfitness-backend
  strategy: # Downtime at rollout, but clean PV release
    type: Recreate
  template:
    metadata:
      labels:
        app: sparkyfitness-backend
    spec:
      automountServiceAccountToken: false
      dnsPolicy: ClusterFirst
      dnsConfig:
        searches:
          - sparkyfitness.svc.cluster.local
      containers:
        - name: sparkyfitness-backend
          image: codewithcj/sparkyfitness_server:v0.16.5.0
          env:
            - name: SPARKY_FITNESS_LOG_LEVEL
              value: WARN
            - name: SPARKY_FITNESS_DB_HOST
              value: sparkyfitness-cnpg-rw # Changed
            - name: SPARKY_FITNESS_DB_PORT
              value: "5432"
            - name: SPARKY_FITNESS_DB_NAME
              value: sparkyfitness
            - name: SPARKY_FITNESS_DB_USER
              value: sparky
            - name: SPARKY_FITNESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: sparkyfitness-cnpg-secret # Changed
                  key: password
            - name: SPARKY_FITNESS_APP_DB_USER
              value: sparkyapp
            - name: SPARKY_FITNESS_APP_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: sparkyfitness-app-cnpg-secret # Changed
                  key: password
            - name: SPARKY_FITNESS_API_ENCRYPTION_KEY_FILE
              value: /run/secrets/sparkyfitness_api_key
            - name: BETTER_AUTH_SECRET_FILE
              value: /run/secrets/sparkyfitness_better_auth_secret
            - name: SPARKY_FITNESS_FRONTEND_URL
              value: https://sparkyfitness.internal.dmhosted.com
            - name: ALLOW_PRIVATE_NETWORK_CORS
              value: "false"
            - name: SPARKY_FITNESS_EXTRA_TRUSTED_ORIGINS
              value: https://sparkyfitness.local.dmhosted.com
            - name: TZ
              value: Europe/Amsterdam
          volumeMounts:
            - mountPath: /app/SparkyFitnessServer/backup
              subPath: backup
              name: sparkyfitness-backend
            - mountPath: /app/SparkyFitnessServer/uploads
              subPath: uploads
              name: sparkyfitness-backend
            - mountPath: /run/secrets
              name: secret-files
              readOnly: true
      volumes:
        - name: sparkyfitness-backend
          persistentVolumeClaim:
            claimName: sparkyfitness-backend
        - name: secret-files
          secret:
            secretName: sparkyfitness-secrets
```

This is all we need.
Applying the manifest will trigger an update, after which our backend will start using the new DB.

Then, make sure your Sparkyfitness instance works as expected (register new foods/query existing contents).

Once this is verified, you can shut down the old DB:

```bash
kubectl scale -n sparkyfitness statefulset sparkyfitness-db --replicas=0
```

---

## Links

- [Life saver guide](https://oneuptime.com/blog/post/2026-01-21-cloudnativepg-user-management/view#declarative-user-management)
