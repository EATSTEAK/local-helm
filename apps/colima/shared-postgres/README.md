# Shared PostgreSQL

`default/shared-postgres` is a new PostgreSQL 16.14 instance, independent of
`sake/sake-postgres` and `default/grimmory-mariadb`. Internal connection address:
`shared-postgres.default.svc.cluster.local:5432`. There is no Ingress, NodePort or
external DB exposure. The pinned pgvector image is already used/cached by Sake;
the extension is available but is not enabled in Phoenix automatically.

The local chart runs one non-root StatefulSet Pod with 100m/256Mi requests,
1 CPU/1Gi limits and a separate `shared-postgres-data` 8Gi local-path PVC.
It uses `shared_buffers=128MB`, `work_mem=4MB`, `maintenance_work_mem=64MB`,
`autovacuum_work_mem=32MB`, `max_connections=50`, `max_wal_size=512MB` and SCRAM
host authentication. `max_wal_size` is a checkpoint target, not a hard disk cap.
TLS is not enabled inside the local cluster; NetworkPolicy limits access to
explicitly opted-in client Pods in `default`. It does not make DB contents immune
to cluster administrators or a node compromise.

## Credentials and application isolation

Create credentials with `just phoenix-secrets` before merging the app overlays.
The admin password is mounted from `default/shared-postgres-auth`; it is never a
chart value. Only DB bootstrap/operations use this superuser account. Each app
gets an independent database and LOGIN role, with no superuser/createdb/createrole/
replication/bypassrls privileges or inherited role membership.

`databases` in the overlay values declares the initial `phoenix` database/owner.
The post-install/post-upgrade Job is idempotent: it refuses an existing privileged
role or a database owned by another role, preserves data, and reconciles the role's
password with the explicitly supplied Secret. It revokes PUBLIC access to each
application database and schema, as well as PUBLIC connections to administrative
`postgres`/`template1` databases. No roles/databases are dropped when removed from
this list; deletion always requires a separate deliberate operation.

Helm waits for the hook to complete before the DB HelmRelease becomes Ready.
Phoenix depends on that readiness. A failed Job is retained for inspection; fix
the cause and explicitly retry the release rather than uninstalling the database.

## Adding an application later

1. Create its own password Secret outside Git; do not reuse the admin credentials.
2. Add a `databases` entry (`name`, `owner`, positive `connectionLimit`,
   `existingSecret`, `passwordKey`) in overlay values and review the change.
3. Label its Pod template `shared-postgres-client: "true"`. The DB ingress policy
   accepts that label only within `default`; another namespace needs an explicit
   namespace-and-Pod policy change.
4. If the app has its own egress policy, allow TCP 5432 to the DB Pod and DNS.
5. Make its HelmRelease depend on `default/shared-postgres`, and verify that it
   cannot connect to other application databases or access their tables.
6. Review total connections/memory/storage and secure backup coverage.

## Inspection and backups

These inspection commands do not print passwords:

```sh
kubectl -n default get helmrelease shared-postgres
kubectl -n default get statefulset,pod,service,pvc -l app.kubernetes.io/name=shared-postgres
kubectl -n default top pod shared-postgres-0
kubectl -n default exec shared-postgres-0 -- psql -U postgres -d postgres -c '\l'
kubectl -n default exec shared-postgres-0 -- du -sh /var/lib/postgresql/data/pgdata
```

For a database-level backup, create a private output file under ignored `secrets/`
or another secure location. Use `umask 077` before redirecting the binary output:

```sh
umask 077
mkdir -p secrets
kubectl -n default exec shared-postgres-0 -- pg_dump -U postgres -d phoenix -Fc > secrets/phoenix.dump
kubectl -n default exec shared-postgres-0 -- pg_dumpall -U postgres --roles-only > secrets/shared-postgres-roles.sql
```

Role backups contain password hashes; never commit or paste them. Keep encrypted
copies of DB backups and both runtime Secrets off this host. A backup only on the
same Mac/VM is not disk-failure protection. Restore the selected app DB with
`pg_restore`, not the entire data directory of a different PostgreSQL instance.

The PVC is marked `helm.sh/resource-policy: keep` to survive Helm uninstall.
Removing the release still stops **all its consumers**; retention is not HA.
The local-path PV has a Delete reclaim policy, so manually deleting its PVC/PV can
destroy data. Major-version image changes require a proper PostgreSQL migration,
not a tag edit against an existing data directory. None of the old app DBs are
moved as part of this deployment.
