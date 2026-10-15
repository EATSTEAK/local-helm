# Phoenix

Phoenix runs in `default` at `https://rise.koohyom.in`. UI, REST API and
OTLP/HTTP share `phoenix-svc:6006`. The existing Cloudflare Tunnel terminates
external TLS and forwards through ingress-nginx. No public PostgreSQL endpoint
or gRPC/metrics Service port is created.

## Layout and resource budget

```text
rise.koohyom.in:443 → Cloudflare Tunnel → ingress-nginx
  → default/phoenix-svc:6006 → default/shared-postgres:5432
                                  database=phoenix, role=phoenix
```

| Workload | CPU request / limit | RAM request / limit | Persistence |
| --- | --- | --- | --- |
| Phoenix, 1 replica | 500m / 1 CPU | 1Gi / 2Gi | External PostgreSQL; no SQLite PVC |
| Shared PostgreSQL, 1 replica | 100m / 1 CPU | 256Mi / 1Gi | Separate 8Gi local-path PVC |
| DB bootstrap, transient | 25m / 100m | 32Mi / 128Mi | None |

The Colima profile is 4 CPU / 12GiB RAM / 100GiB disk. This is VM-wide memory,
not Phoenix's limit. Existing Sake PostgreSQL and Grimmory MariaDB are unchanged;
this rollout does not migrate their databases. PostgreSQL is single-node,
without replicas, PgBouncer or an operator.

The official OCI chart is fixed to `12.0.17` by artifact digest, with Phoenix
`20.19.0-nonroot` fixed to its linux/arm64 image digest. Upstream Service and
container-port lists are post-rendered to HTTP only. Phoenix may still start an
internal gRPC listener; removing a `containerPort` is not a listener-disable
switch. The Pod's NetworkPolicy allows incoming TCP 6006 only from ingress-nginx,
and outgoing PostgreSQL/DNS only. No gRPC ingestion endpoint is supported.

Authentication, secure cookies and the strong password policy are enabled.
The authenticated MCP server is enabled at `https://rise.koohyom.in/mcp`.
MCP code mode, telemetry, Prometheus, external fonts, OAuth2 authorization-server
endpoints, model-provider and sandbox-provider access remain disabled.
The DB role is not a superuser and has a connection limit of 20.

## Pre-merge rollout checklist

Flux follows `main`, not the PR branch. The following are explicit local operations,
not GitHub Actions or automatic effects of committing these files.

1. Validate: `just phoenix-validate` (needs Helm, kubectl, Ruby and registry access).
   `ruby tests/postgres_bootstrap_test.rb` additionally tests real SQL against an
   isolated Docker DB with tmpfs data, no published port and no existing PVC.
2. Record current Colima profile and cluster health; back up the existing app DBs
   and runtime Secrets securely, outside Git. Check host and VM free space.
3. During a maintenance window, run `just colima-restart` from this branch to apply
   the 12GiB profile. This interrupts **all cluster services** for several minutes.
   Confirm the node is Ready, 4 CPU/12GiB is effective, and existing apps recover.
   Do not proceed if the host develops sustained memory pressure/swap growth.
4. Run `just phoenix-secrets`. It targets context `colima` unless `KUBE_CONTEXT` is
   explicitly set. It creates the two Secrets below with random credentials,
   validates/reuses existing Secrets, and never prints values or rotates them.
   Back up the new credentials securely before deploying the DB.
5. Merge the PR, then `just flux-reconcile`. `shared-postgres` must become Ready,
   including its post-install DB/role bootstrap hook, before Phoenix is installed.
6. Confirm HelmRelease readiness, then verify the public login page and log in as
   `admin@localhost` with the initial password from your secure credential store.
   The bootstrap script stores that password only in the Kubernetes Secret; use a
   deliberate local Secret retrieval if needed, never CI logs/chat/Git.
7. Create a **system API key** in Settings → API Keys for producers. Do not use the
   database admin password or signing secret as ingestion credentials.
8. In Settings → Data Retention, verify Default is 7 days and change its cleanup
   schedule from the upstream weekly default to daily. Check scheduler timezone
   and choose a time corresponding to 03:00 Asia/Seoul. Verify all projects use
   this policy before enabling normal ingestion.
9. Send a small authenticated OTLP/HTTP protobuf span; check it in the UI. Verify
   an unauthenticated request is rejected, and the Pod restart preserves traces,
   users and API keys. Confirm Sake and Grimmory still work.

| Secret in `default` | Required keys | Used by |
| --- | --- | --- |
| `shared-postgres-auth` | `POSTGRES_PASSWORD` | DB server and bootstrap Job only |
| `phoenix-secret` | `PHOENIX_SECRET`, `PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD`, `PHOENIX_POSTGRES_PASSWORD` | Phoenix; bootstrap Job reads only the DB password |

Keep `PHOENIX_SECRET` stable: changing it invalidates authentication and can break
encrypted data. The initial admin password is read only when the admin account is
created; changing the Secret later is not a password reset. Existing DB data/PVC
must retain the matching PostgreSQL administrator password. The Docker image reads
that password only on first initialization, not on every restart.

## Ingestion

Configure producers with a dedicated system API key stored in their own Secret:

```text
OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://rise.koohyom.in/v1/traces
OTEL_EXPORTER_OTLP_TRACES_HEADERS=authorization=Bearer <SYSTEM_API_KEY>
```

The Ingress limits requests to 8MiB and read/send timeouts to 60 seconds. Keep
exporter batches below that limit. There is no OTLP/gRPC endpoint in this setup.
Direct in-cluster access from ordinary producer Pods is intentionally blocked;
use the public HTTP route, or explicitly review a NetworkPolicy change first.

## MCP access

Connect a Streamable HTTP MCP client to `https://rise.koohyom.in/mcp` with
`Authorization: Bearer <PHOENIX_API_KEY>`. Store the API key in the client's
secret store or environment, never in Git. Browser OAuth login is not enabled.
The endpoint uses the existing HTTPS ingress and requires no additional port
or NetworkPolicy allowance. Unauthenticated requests must be rejected.

Code mode is disabled, so operations are exposed as individual tools rather
than through the Python `execute` tool. MCP is not read-only: tools can mutate
Phoenix data within the API key's permissions. Use a dedicated, least-privilege
key for each client and approve write operations deliberately.

## Capacity and retention

The 7-day default trace policy is configured in values. **Daily cleanup is a
post-deployment UI step**, not a Helm value in this chart. Before that change,
weekly cleanup can leave roughly two weeks of traces. Prompt/dataset/experiment
data is not covered by the trace policy.

`database.allocatedStorageGiB: 3` is a displayed operating budget, not a DB quota.
`local-path` also does not enforce the PVC's 8Gi capacity as a disk usage ceiling.
Observe data, indexes, WAL, backups and both host/VM free space independently.
On 2026-10-13 the host had about 15GiB free and the VM about 28GiB; recheck before
deployment. The disk is a tighter constraint than RAM after the 12GiB increase.

- At Phoenix DB 2Gi, review retention, span attribute sizes and ingestion rate.
- At 3Gi, pause additional ingestion and reassess capacity; this is a manual
  operating threshold, not an implemented automatic quota.
- If either host or VM has less than 10GiB free, stop new bulk ingestion.
- Use the first 24 hours' growth/span count to estimate approximately 8 days of
  data after daily cleanup is configured. Vacuum normally makes deleted space
  reusable; it does not immediately shrink the files.

Observe memory, restarts, connection count, ingestion failures and existing app
latency for 24–72 hours. If more applications adopt the shared DB, reassess its
256Mi request/1Gi limit and 50 total connections rather than assuming this budget
scales indefinitely.

## Rollback and recovery

Suspend `default/phoenix` and stop producers first. Remove/revert the Phoenix
overlay/Ingress only when ready to remove its release. Do not remove the shared
DB overlay as a casual application rollback. Its PVC has
`helm.sh/resource-policy: keep`, but that is not a backup or permission to prune
the PV manually. Keep DB/roles/Secrets for investigation and restore Phoenix at
the **database** level; never restore Sake's unrelated PGDATA over this instance.

If 12GiB causes sustained host pressure, revise the profile to 8GiB and perform a
separate maintenance-window restart. No volume pruning, existing DB migration,
ingress-controller replacement or automatic database deletion is part of this PR.

## References

- [Official Helm deployment](https://arize.com/docs/phoenix/self-hosting/deployment-options/kubernetes-helm)
- [Authentication](https://arize.com/docs/phoenix/self-hosting/features/authentication)
- [Retention policies](https://arize.com/docs/phoenix/settings/data-retention)
- [Shared PostgreSQL operations](../shared-postgres/README.md)
