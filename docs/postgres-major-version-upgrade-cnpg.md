# PostgreSQL Major Version Upgrade - CNPG

**Goal**: upgrade PostgreSQL version from 15 to 18 for the [SparkyFitness database](../kubernetes/apps/sparkyfitness/database.yaml).

## Approach description

We will perform what is known as "_offline upgrade_", i.e., an upgrade during which the application(s) using
the DB will have to be turned off to prevent inconsistency in the DB data during migration.

CNPG provides a native way to achieve this by means of the `initdb` bootstrap method.
We will have to fill out the `bootstrap:initdb:import` section of the CNPG `Cluster` resource.

## Execution

First, scale down the replicas of frontend + backend (or any app that's using the DB).

```bash
kubectl scale -n sparkyfitness deployment sparkyfitness-backend --replicas=0
kubectl scale -n sparkyfitness deployment sparkyfitness-frontend --replicas=0
```

Secondly, let's take a backup of our DB.
Log into any instance of the existing cluster:

```bash
kubectl exec -n sparkyfitness -it sparkyfitness-cnpg-1 -c postgres -- /bin/bash
```

From there, verify the DB name (you can log into it with `psql -U <user-name> -d <db-name>`).

Since the container FS is read-only, we need to run the `pg_dump` command so that it does not try to write to a file inside the pod.

```bash
kubectl exec -n sparkyfitness -it sparkyfitness-cnpg-1 -c postgres -- /usr/bin/pg_dump -U postgres -d sparkyfitness --format=plain > ./postgres_backup.sql
```

We will have the backup in the `./postgres_backup.sql` file, on the local host.

Then, define the new `Cluster` resource, so that it bootstraps from the existing DB:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: sparkyfitness-db
  namespace: sparkyfitness
  labels:
    app: sparkyfitness-cnpg
spec:
  description: "Database for SparkyFitness"
  inheritedMetadata:
    labels:
      app: sparkyfitness-cnpg
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
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
      import: # NEW:
        type: microservice
        databases:
          - sparkyfitness
        source:
          externalCluster: postgres-15-db
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
  externalClusters:
    - name: postgres-15-db
      connectionParameters:
        host: sparkyfitness-cnpg-ro # Read-only instance
        user: sparky # Needs to be superuser
        dbname: sparkyfitness
      password:
        name: sparkyfitness-cnpg-secret
        key: password
```

Then, apply the new manifest.

This will launch a job in a pod that will execute `pg_dump` and get all the data off the old DB (in a pod named something like `sparkyfitness-db-1-import-<...>`.
Then, new DB replicas will be started.

A quick login into the a new instance shows that the DB was successfully migrated (all tables are there).

Then, modify the `sparkyfitness` deployments to point to the new DB, and increase the number of replicas.

As a last step before decommissioning the old DB, set it in 'hibernation' mode:

```bash
annotate clusters.postgresql.cnpg.io sparkyfitness-cnpg -n sparkyfitness cnpg.io/hibernation=on
```

This will effectively shut it down without losing any data.
If the application works, you can proceed and delete the old `Cluster` resource.

---

## Links

- [CNPG major version upgrade guide](https://cloudnative-pg.io/docs/devel/postgres_upgrades/#major-version-upgrades)
