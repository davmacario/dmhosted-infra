---
id: README
author: Davide Macario
date: 2026-02-21
aliases: []
tags:
  - k3s
  - homelab
---

# SparkyFitness installation on cluster

> [SparkyFitness - GitHub repo](https://github.com/CodeWithCJ/SparkyFitness)

Goal: "translate" the following Docker Compose file:

```yaml
services:
  sparkyfitness-db:
    image: postgres:15-alpine
    restart: always
    environment:
      POSTGRES_DB: ${SPARKY_FITNESS_DB_NAME:?Variable is required and must be set}
      POSTGRES_USER: ${SPARKY_FITNESS_DB_USER:?Variable is required and must be set}
      POSTGRES_PASSWORD: ${SPARKY_FITNESS_DB_PASSWORD:?Variable is required and must be set}
    volumes:
      - ${DB_PATH:-../postgresql}:/var/lib/postgresql/data
    networks:
      - sparkyfitness-network # Use the new named network

  sparkyfitness-server:
    image: codewithcj/sparkyfitness_server:latest # Use pre-built image
    environment:
      SPARKY_FITNESS_LOG_LEVEL: ${SPARKY_FITNESS_LOG_LEVEL}
      ALLOW_PRIVATE_NETWORK_CORS: ${ALLOW_PRIVATE_NETWORK_CORS:-false}
      SPARKY_FITNESS_EXTRA_TRUSTED_ORIGINS: ${SPARKY_FITNESS_EXTRA_TRUSTED_ORIGINS:-}
      SPARKY_FITNESS_DB_USER: ${SPARKY_FITNESS_DB_USER:-sparky}
      SPARKY_FITNESS_DB_HOST: ${SPARKY_FITNESS_DB_HOST:-sparkyfitness-db} # Use the service name 'sparkyfitness-db' for inter-container communication
      SPARKY_FITNESS_DB_NAME: ${SPARKY_FITNESS_DB_NAME}
      SPARKY_FITNESS_DB_PASSWORD: ${SPARKY_FITNESS_DB_PASSWORD:?Variable is required and must be set}
      SPARKY_FITNESS_APP_DB_USER: ${SPARKY_FITNESS_APP_DB_USER:-sparkyapp}
      SPARKY_FITNESS_APP_DB_PASSWORD: ${SPARKY_FITNESS_APP_DB_PASSWORD:?Variable is required and must be set}
      SPARKY_FITNESS_DB_PORT: ${SPARKY_FITNESS_DB_PORT:-5432}
      SPARKY_FITNESS_API_ENCRYPTION_KEY: ${SPARKY_FITNESS_API_ENCRYPTION_KEY:?Variable is required and must be set}
      # Uncomment the line below and comment the line above to use a file-based secret
      # SPARKY_FITNESS_API_ENCRYPTION_KEY_FILE: /run/secrets/sparkyfitness_api_key

      BETTER_AUTH_SECRET: ${BETTER_AUTH_SECRET:?Variable is required and must be set}
      # Uncomment the line below and comment the line above to use a file-based secret
      # BETTER_AUTH_SECRET_FILE: /run/secrets/sparkyfitness_better_auth_secret
      SPARKY_FITNESS_FRONTEND_URL: ${SPARKY_FITNESS_FRONTEND_URL:-http://0.0.0.0:3004}
      SPARKY_FITNESS_DISABLE_SIGNUP: ${SPARKY_FITNESS_DISABLE_SIGNUP}
      SPARKY_FITNESS_ADMIN_EMAIL: ${SPARKY_FITNESS_ADMIN_EMAIL} #User with this email can access the admin panel
      SPARKY_FITNESS_EMAIL_HOST: ${SPARKY_FITNESS_EMAIL_HOST}
      SPARKY_FITNESS_EMAIL_PORT: ${SPARKY_FITNESS_EMAIL_PORT}
      SPARKY_FITNESS_EMAIL_SECURE: ${SPARKY_FITNESS_EMAIL_SECURE}
      SPARKY_FITNESS_EMAIL_USER: ${SPARKY_FITNESS_EMAIL_USER}
      SPARKY_FITNESS_EMAIL_PASS: ${SPARKY_FITNESS_EMAIL_PASS}
      SPARKY_FITNESS_EMAIL_FROM: ${SPARKY_FITNESS_EMAIL_FROM}
      # GARMIN_MICROSERVICE_URL: http://sparkyfitness-garmin:8000 # Add Garmin microservice URL
    networks:
      - sparkyfitness-network # Use the new named network
    restart: always
    depends_on:
      - sparkyfitness-db # Backend depends on the database being available
    volumes:
      - ${SERVER_BACKUP_PATH:-./backup}:/app/SparkyFitnessServer/backup # Mount volume for backups
      - ${SERVER_UPLOADS_PATH:-./uploads}:/app/SparkyFitnessServer/uploads # Mount volume for Profile pictures and excercise images

  sparkyfitness-frontend:
    image: codewithcj/sparkyfitness:latest # Use pre-built image
    ports:
      - "3004:80" # Map host port 8080 to container port 80 (Nginx)
    environment:
      SPARKY_FITNESS_FRONTEND_URL: ${SPARKY_FITNESS_FRONTEND_URL}
      SPARKY_FITNESS_SERVER_HOST: sparkyfitness-server # Internal Docker service name for the backend
      SPARKY_FITNESS_SERVER_PORT: 3010 # Port the backend server listens on
    networks:
      - sparkyfitness-network # Use the new named network
    restart: always
    depends_on:
      - sparkyfitness-server # Frontend depends on the server
      #- sparkyfitness-garmin # Frontend depends on Garmin microservice. Enable if you are using Garmin Connect features.

  # Garmin integration is still work in progress. Enable once table is ready.
  # sparkyfitness-garmin:
  #   image: codewithcj/sparkyfitness_garmin:latest
  #   container_name: sparkyfitness-garmin
  #   environment:
  #     GARMIN_MICROSERVICE_URL: http://sparkyfitness-garmin:${GARMIN_SERVICE_PORT}
  #     GARMIN_SERVICE_PORT: ${GARMIN_SERVICE_PORT}
  #     GARMIN_SERVICE_IS_CN: ${GARMIN_SERVICE_IS_CN}  # set to true for China region. Everything else should be false. Optional - defaults to false
  #   networks:
  #     - sparkyfitness-network
  #   restart: unless-stopped
  #   depends_on:
  #     - sparkyfitness-db
  #     - sparkyfitness-server

networks:
  sparkyfitness-network:
    driver: bridge
```

## Kubernetes resources

Everything will be deployed in the `sparkyfitness` [namespace](./namespace.yaml).

### PostgreSQL DB

From docker compose file:

```yaml
sparkyfitness-db:
  image: postgres:15-alpine
  restart: always
  environment:
    POSTGRES_DB: ${SPARKY_FITNESS_DB_NAME:?Variable is required and must be set}
    POSTGRES_USER: ${SPARKY_FITNESS_DB_USER:?Variable is required and must be set}
    POSTGRES_PASSWORD: ${SPARKY_FITNESS_DB_PASSWORD:?Variable is required and must be set}
  volumes:
    - ${DB_PATH:-../postgresql}:/var/lib/postgresql/data
  networks:
    - sparkyfitness-network # Use the new named network
```

Considerations:

- Stateful application: need deployment via `StatefulSet`
  - This allows to define a PVC as well
- Need a secret containing the DB password: `./postgres-secret.yaml` (not in version control):

  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: sparkyfitness-db-secret
    namespace: sparkyfitness
  type: Opaque
  data:
    db-password: <secret-password-b64>
  ```

  This will be referenced in the value of `POSTGRES_PASSWORD`

  > [!tip]
  >
  > Since K8s Secrets must be encoded in b64, you can do it by running `echo -n "your-secret-here" | base64`

- Need a **headless** `Service` which will allow to reference the DB via the internal DNS
  - No need for a Cluster IP! We will reference the DB using the Service DNS name.

> [!IMPORTANT]
>
> With a `StatefulSet`, pods have their own identity (they are not interchangeable!).
> Their name will be `<statefulset-name>-<pod-index>`, and,

> [!NOTE]
>
> In `StatefulSet`s, mounting a volume from a PVC defined in `spec:volumeClaimTemplates` can be done by referencing
> the name of `spec:volumeClaimTemplates[i].metadata.name`.

#### Reaching the DB

We created a "headless" Service, defined as:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sparkyfitness-db
  namespace: sparkyfitness
spec:
  clusterIP: None
  ports:
    - port: 5432
  selector:
    app: sparkyfitness-db
```

Running `kubectl describe -n sparkyfitness svc sparkyfitness-db` returns:

```text
Name:                     sparkyfitness-db
Namespace:                sparkyfitness
Labels:                   <none>
Annotations:              <none>
Selector:                 app=sparkyfitness-db
Type:                     ClusterIP
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       None
IPs:                      None
Port:                     <unset>  5432/TCP
TargetPort:               5432/TCP
Endpoints:                10.42.2.178:5432
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

which confirms that there is no cluster IP associated to it.

To reach the DB, we will use the DNS record associated with the Service, which is:

```text
<service-name>.<service-namespace>.svc.cluster.local
```

(_Note_: this assumes you didn't modify the cluster domain when creating your cluster, so the default, `cluster.local` is valid)

In our case: `sparkyfitness-db.sparkyfitness.svc.cluster.local`.

##### TIP: checking DNS in the cluster

Launch an ephemeral container and connect to the shell:

```yaml
kubectl run -i --tty dns-test --image=busybox --restart=Never --rm /bin/sh
```

From there, you can run `nslookup` to check reachability:

```sh
nslookup my-db.default.svc.cluster.local
```

### SparkyFitness Backend

From Docker Compose:

```yaml
sparkyfitness-server:
  image: codewithcj/sparkyfitness_server:latest # Use pre-built image
  environment:
    SPARKY_FITNESS_LOG_LEVEL: ${SPARKY_FITNESS_LOG_LEVEL}
    ALLOW_PRIVATE_NETWORK_CORS: ${ALLOW_PRIVATE_NETWORK_CORS:-false}
    SPARKY_FITNESS_EXTRA_TRUSTED_ORIGINS: ${SPARKY_FITNESS_EXTRA_TRUSTED_ORIGINS:-}
    SPARKY_FITNESS_DB_USER: ${SPARKY_FITNESS_DB_USER:-sparky}
    SPARKY_FITNESS_DB_HOST: ${SPARKY_FITNESS_DB_HOST:-sparkyfitness-db} # Use the service name 'sparkyfitness-db' for inter-container communication
    SPARKY_FITNESS_DB_NAME: ${SPARKY_FITNESS_DB_NAME}
    SPARKY_FITNESS_DB_PASSWORD: ${SPARKY_FITNESS_DB_PASSWORD:?Variable is required and must be set}
    SPARKY_FITNESS_APP_DB_USER: ${SPARKY_FITNESS_APP_DB_USER:-sparkyapp}
    SPARKY_FITNESS_APP_DB_PASSWORD: ${SPARKY_FITNESS_APP_DB_PASSWORD:?Variable is required and must be set}
    SPARKY_FITNESS_DB_PORT: ${SPARKY_FITNESS_DB_PORT:-5432}
    SPARKY_FITNESS_API_ENCRYPTION_KEY: ${SPARKY_FITNESS_API_ENCRYPTION_KEY:?Variable is required and must be set}
    # Uncomment the line below and comment the line above to use a file-based secret
    # SPARKY_FITNESS_API_ENCRYPTION_KEY_FILE: /run/secrets/sparkyfitness_api_key

    BETTER_AUTH_SECRET: ${BETTER_AUTH_SECRET:?Variable is required and must be set}
    # Uncomment the line below and comment the line above to use a file-based secret
    # BETTER_AUTH_SECRET_FILE: /run/secrets/sparkyfitness_better_auth_secret
    SPARKY_FITNESS_FRONTEND_URL: ${SPARKY_FITNESS_FRONTEND_URL:-http://0.0.0.0:3004}
    SPARKY_FITNESS_DISABLE_SIGNUP: ${SPARKY_FITNESS_DISABLE_SIGNUP}
    SPARKY_FITNESS_ADMIN_EMAIL: ${SPARKY_FITNESS_ADMIN_EMAIL} #User with this email can access the admin panel
    SPARKY_FITNESS_EMAIL_HOST: ${SPARKY_FITNESS_EMAIL_HOST}
    SPARKY_FITNESS_EMAIL_PORT: ${SPARKY_FITNESS_EMAIL_PORT}
    SPARKY_FITNESS_EMAIL_SECURE: ${SPARKY_FITNESS_EMAIL_SECURE}
    SPARKY_FITNESS_EMAIL_USER: ${SPARKY_FITNESS_EMAIL_USER}
    SPARKY_FITNESS_EMAIL_PASS: ${SPARKY_FITNESS_EMAIL_PASS}
    SPARKY_FITNESS_EMAIL_FROM: ${SPARKY_FITNESS_EMAIL_FROM}
    # GARMIN_MICROSERVICE_URL: http://sparkyfitness-garmin:8000 # Add Garmin microservice URL
  networks:
    - sparkyfitness-network # Use the new named network
  restart: always
  depends_on:
    - sparkyfitness-db # Backend depends on the database being available
  volumes:
    - ${SERVER_BACKUP_PATH:-./backup}:/app/SparkyFitnessServer/backup # Mount volume for backups
    - ${SERVER_UPLOADS_PATH:-./uploads}:/app/SparkyFitnessServer/uploads # Mount volume for Profile pictures and excercise images
```

What we need:

- Several secrets:
  - `SPARKY_FITNESS_DB_PASSWORD` -> from secret used in DB
  - `SPARKY_FITNESS_APP_DB_PASSWORD`
  - `SPARKY_FITNESS_API_ENCRYPTION_KEY_FILE`: mount K8s Secret as file
  - `BETTER_AUTH_SECRET_FILE`: mount Secret as file
- Since the backend is not actually storing the data (PV only for mounts - `backup` and `uploads`), we will use a `Deployment`
  - We need a PVC
  - Fix rollout strategy to `Recreate` to prevent issues with old pod not releasing PVC
    - **TODO**: try using `ReadWriteMany` PVs, but `backup` makes me think it may not be safe
- Since backend pods are supposed to be interchangeable, we will use a ClusterIP Service, which will allow to have load balancing in case we need to scale out
  - Still reachable via `<service-name>.<service-namespace>.svc.cluster.local`

#### Mounting secrets as files

Very common use case of K8s secrets.

Let's mount the secrets for `SPARKY_FITNESS_API_ENCRYPTION_KEY_FILE` and `BETTER_AUTH_SECRET_FILE` using Secrets.

1. Generate 2 strings using:

   ```bash
   openssl rand -hex 32 | base64
   ```

   **Important**: you must encode them in b64 for this to work, as the value will be decoded when writing the

2. Create a k8s secret with those values:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: sparkyfitness-secrets
     namespace: sparkyfitness
   type: Opaque
   data:
     sparkyfitness_api_key: <your api key>
     sparkyfitness_better_auth_secret: <your betterauth secret>
   ```

   **Note** the secret Keys: `sparkyfitness_api_key`, and `sparkyfitness_better_auth_secret`, as they will become the names of the mounted files!

   And apply it: `k apply -f <secret-file>.yaml`

3. Mount the secret (in the `Deployment`):

   ```yaml
   #...
   spec:
     # ...
     template:
       # ...
       spec:
         containers:
           - name: sparkyfitness-backend
             # ...
             volumeMounts:
               - mountPath: /run/secrets
                 name: secret-files
             env:
               - name: SPARKY_FITNESS_API_ENCRYPTION_KEY_FILE
                 value: /run/secrets/sparkyfitness_api_key # Secret key (1)
               - name: BETTER_AUTH_SECRET_FILE
                 value: /run/secrets/sparkyfitness_better_auth_secret # Secret key (2)
         volumes:
           # ...
           - name: secret-files
             secret:
               secretName: sparkyfitness-secrets # Name of the k8s secret
   ```

### SparkyFitness Frontend

From Docker Compose:

```yaml
  sparkyfitness-frontend:
    image: codewithcj/sparkyfitness:latest # Use pre-built image
    ports:
      - "3004:80" # Map host port 8080 to container port 80 (Nginx)
    environment:
      SPARKY_FITNESS_FRONTEND_URL: ${SPARKY_FITNESS_FRONTEND_URL}
      SPARKY_FITNESS_SERVER_HOST: sparkyfitness-server # Internal Docker service name for the backend
      SPARKY_FITNESS_SERVER_PORT: 3010 # Port the backend server listens on
    networks:
      - sparkyfitness-network # Use the new named network
    restart: always
    depends_on:
      - sparkyfitness-server # Frontend depends on the server
      #- sparkyfitness-garmin # Frontend depends on Garmin microservice. Enable if you are using Garmin Connect features.
```

Need:

- Pin image version to `v0.16.4.4`, as backend
- `Deployment`, as it is a stateless app
  - DNS config to search in namespace
- Service, `ClusterIP`
- `Certificate` for `sparkyfitness.internal.dmhosted.com`
- `IngressRoute`, expose on Tailscale

## Updates

### 2026-03-18 - Fixing number of ReplicaSets

Upgrading Sparkyfitness means, in practice, to bump up the container tag versions of both frontend ([sparkyfitness-frontend.yaml](./sparkyfitness-frontend.yaml)), and backend ([sparkyfitness-backend.yaml](./sparkyfitness-backend.yaml)).

By default, Kubernetes leaves behind old `ReplicaSets`, as they enable rollbacks (see `kubectl rollout undo`).
However, by default, the number of "old" ReplicaSets is 10.

We can reduce it by setting `spec:revisionHistoryLimit: 3` (for example) in all deployments.
Note that changing this setting also retroactively deletes the existing ones.

### 2026-03-28 - Migration to PostgreSQL 18

Supported from version v0.16.5.4 (see [docs](https://codewithcj.github.io/SparkyFitness/install/postgres-upgrade)).

Writeup [here](../../../docs/postgres-major-version-upgrade-cnpg.md).
