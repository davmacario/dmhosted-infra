# Migrating Firefly-III

From: Docker container(s) running on single host, and using MySQL.

To: K8s, using PostgreSQL (CNPG).

No loss of data, and (optionally) extra features.

## Backing up old DB

Log into DB container, and run `mariadb-dump` of the `firefly` database.

> [!tip]
>
> I mounted a new path onto the container so that I could put the backup .sql there

```bash
mariadb-dump -u firefly -p<password> firefly > /db_backup/firefly-dump.sql
```

We will re-apply this dump to the postgres DB once we launch it on K8s.

## Migration

Followed [discussion](https://github.com/orgs/firefly-iii/discussions/7698#discussioncomment-6546883) _very closely_.

In a nutshell:

1. Created "new" copy of app on RPi + PostgreSQL container. `env` is the same as the "original" instance.
1. Let the new copy initialize DB (wait for it to be ready to accept connections)
1. Launch PGAdmin, pointing to the new PostgreSQL DB
1. Take backup of **schema only** of DB
1. Restore backup (achieves deletion of records, not schema)
1. Launch PGLoader (from local laptop, or any host that can connect to both the MariaDB and Postgres DBs):

   ```text
   LOAD DATABASE
       FROM mysql://firefly:<old-db-pass>@<rpi-IP>:3306/firefly
       INTO postgresql://firefly:<new-db-pass>@<rpi-IP>:5432/firefly
       WITH data only, quote identifiers
       ALTER SCHEMA 'firefly' RENAME TO 'public'
   ;
   ```

   This copies the contents across DBs
1. Log into the "new" Firefly container, and run `php artisan firefly-iii:correct-database` to fix any issues with the data
1. Restart new firefly container
1. Log into PostgreSQL container, and execute `pg_dump -U firefly -d firefly > /pg_backup/pg_backup.sql`, where the destination location is a bind mount (this way the data can "get out" of the container)
1. SCP `pg_backup.sql` on local laptop
1. Launch CNPG Cluster on K8s
1. Run:

   ```bash
   kubectl exec -n firefly-iii <cnpg-primary-instance> -i -c postgres -- psql -U firefly -d firefly < ./path/to/pg_backup.sql
   ```

   This will effectively migrate the DB data to the CNPG cluster.
1. You can now deploy Firefly on k8s pointing at the DB.
