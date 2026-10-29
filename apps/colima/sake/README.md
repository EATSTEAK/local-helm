# Sake

Colima GitOps overlay for Sake in the `sake` namespace. Dependencies, API, worker, and Mastra Studio are separate Helm releases.

## Managed resources

- `namespace.yaml` creates the `sake` namespace.
- `kustomization.yaml` generates four ConfigMaps:
  - `sake-deps-values` from `deps-values.yaml`
  - `sake-api-values` from `api-values.yaml`
  - `sake-worker-values` from `worker-values.yaml`
  - `sake-studio-values` from `studio-values.yaml`
- `helmrelease-deps.yaml` reconciles `HelmRelease/sake-deps` from the local chart `./charts/sake-deps`.
- `helmrelease-api.yaml` reconciles `HelmRelease/sake-api` from `./charts/sake-api` and depends on `sake-deps`.
- `helmrelease-worker.yaml` reconciles `HelmRelease/sake-worker` from `./charts/sake-worker` and depends on both `sake-deps` and `sake-api`.
- `helmrelease-studio.yaml` reconciles `HelmRelease/sake-studio` from `./charts/sake-studio` and depends on both `sake-deps` and `sake-api`, so Studio waits for the API migration hooks to succeed.

## Runtime configuration

- API image: `ghcr.io/triflam/sake-api`
- Worker image: `ghcr.io/triflam/sake-worker`
- Studio image: `ghcr.io/triflam/sake-studio`
- Image pull Secret: `sake/ghcr-auth`
- LLM endpoint: `http://host.docker.internal:8317/v1`
- LLM model: `gpt-6-luna`
- Embedding endpoint: `https://generativelanguage.googleapis.com/v1beta/openai`
- API embedding model: `gemini-embedding-2-preview`
- Worker embedding model: `gemini-embedding-2`
- Embedding dimensions: `1536`

The API chart runs Prisma migration and master account seed jobs as Helm hooks. The worker and Studio are configured for Tavily-backed research search and Crawl4AI crawling; the worker also enables LangSmith tracing.

## Dependencies

`sake-deps` deploys local development dependencies:

- PostgreSQL with pgvector: `pgvector/pgvector:pg16`, PVC `sake-postgres-data`, `8Gi`
- Redis: `redis:7-alpine`, PVC `sake-redis-data`, `2Gi`, AOF with `appendfsync everysec`
- Silo (MinIO-compatible):
  `pgsty/silo:RELEASE.2026-09-16T00-00-00Z`, bucket `sake-dev`, PVC
  `sake-minio-data`, `10Gi`
- Crawl4AI: `unclecode/crawl4ai:0.9.5` pinned by digest
- Secret: `sake-dev-secrets` with local-only Postgres and MinIO defaults

Do not put real external API keys in chart-managed Secrets.

PDF requests to `/crawl` must explicitly select `PDFContentScrapingStrategy`
in `crawler_config.params.scraping_strategy`. The image includes PDF parsing
dependencies, but does not auto-detect PDFs. Scanned PDFs still require separate
OCR.

## Networking

The API Ingress is enabled with class `nginx` and host `sake.koohyom.in`. The Studio Ingress uses `studio-sake.koohyom.in` and requires ingress-nginx basic authentication. The API also trusts both `https://sake.triflam.team` and `https://sake.koohyom.in` through `BETTER_AUTH_TRUSTED_ORIGINS`.

## Secrets

Create or refresh the GHCR pull Secret outside GitOps:

```sh
kubectl -n sake create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username='<github-username>' \
  --docker-password='<github-token-with-read-packages>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Create the Studio basic-auth Secret outside GitOps. `htpasswd` prompts for the password instead of placing it in shell history:

```sh
htpasswd -c /tmp/sake-studio-auth '<username>'
kubectl -n sake create secret generic sake-studio-basic-auth \
  --from-file=auth=/tmp/sake-studio-auth \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/sake-studio-auth
```

Create or refresh `sake-runtime-secrets` before deploying dependencies, API, worker, and Studio. `ADMIN_EMAIL` and `ADMIN_PASSWORD` seed the master login account; the remaining keys back local LLM, embedding, Tavily, LangSmith, and Crawl4AI integrations. Studio reads provider credentials from this Secret so its registered research tools match the worker.

Crawl4AI 0.9.5 intentionally binds only to loopback when no API token is
configured, so a Kubernetes `ClusterIP` alone cannot bypass authentication.
The same random
token must be mounted into Crawl4AI, the Sake worker, and Studio. The dependency
chart limits Crawl4AI ingress to worker and Studio pods and egress to public
HTTP/HTTPS plus cluster DNS; this requires the cluster CNI to enforce
`NetworkPolicy`:

```sh
kubectl -n sake create secret generic sake-runtime-secrets \
  --from-literal=ADMIN_EMAIL='<master-admin-email>' \
  --from-literal=ADMIN_PASSWORD='<master-admin-password>' \
  --from-literal=LLM_API_KEY='<local-llm-api-key-or-placeholder>' \
  --from-literal=EMBEDDING_API_KEY='<gemini-api-key>' \
  --from-literal=TAVILY_API_KEY='<tavily-api-key>' \
  --from-literal=LANGSMITH_API_KEY='<langsmith-api-key>' \
  --from-literal=CRAWL4AI_API_TOKEN="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

For an existing install, copy the current `SAKE_ADMIN_EMAIL` and `SAKE_ADMIN_PASSWORD` values into `ADMIN_EMAIL` and `ADMIN_PASSWORD` without rotating credentials. Add only the canonical keys with a merge patch, retain the legacy keys during the transition, and preserve every other Secret field. After the Secret and chart update are available, reset/reconcile a stalled API release:

```sh
flux reconcile helmrelease sake-api -n sake --reset
```

If only Secret data changes, restart running pods so `envFrom` picks up the new values:

```sh
kubectl -n sake rollout restart deployment/sake-crawl4ai deployment/sake-api deployment/sake-worker deployment/sake-studio
```

## Image tag updates

After the release workflow publishes new Sake images, update the pinned tags with the **Update image tag** GitHub Actions workflow:

```text
app: sake
tag: main-<sha>
targets: [{"file":"apps/colima/sake/api-values.yaml","path":"image.tag"},{"file":"apps/colima/sake/worker-values.yaml","path":"image.tag"},{"file":"apps/colima/sake/studio-values.yaml","path":"image.tag"}]
```

## Redis persistence cutover

An existing ephemeral Redis must be migrated **before** deploying the persistence
change. Starting Redis with `appendonly yes` against only an RDB backup can start
an empty dataset; prepare AOF files first.

1. Suspend the four Sake Helm releases. Record their state, application replica
   counts, Redis deployment, and the queues that are not already paused.
2. Pause queue intake, wait for active jobs to finish, then scale API, worker and
   Studio to zero. Do not terminate active analysis to force the migration.
3. Run Redis `SAVE` and keep a protected copy of `dump.rdb` outside the pod.
   Record key/value fingerprints after writers stop.
4. Create `sake-redis-data` with the chart's Helm ownership metadata and mount it
   in a temporary pod using the same Redis image. Copy the RDB into `/data` and
   start isolated Redis with AOF disabled. Enable AOF with `CONFIG SET appendonly
   yes`; wait for the rewrite to finish successfully. Check the data against the
   source, shut down the isolated server cleanly, and remove the temporary pod.
5. Deploy the reviewed chart and resume the dependency release. Confirm the new
   Redis mounts the PVC, AOF is enabled, and key/value fingerprints match before
   resuming the recorded queues and restoring application replica counts.
6. Verify application readiness, then resume the other Helm releases. Keep the
   backup until recovery is confirmed. The PVC uses Helm's `keep` policy.

Before application writes resume, a failed cutover can return to the saved Redis
spec using the protected RDB with AOF disabled. Keep the releases suspended while
recovering. After writes resume, take a fresh backup from the PVC before any
rollback; the old RDB no longer contains the latest queue state. Do not delete the
PVC or enable ephemeral mode as a rollback shortcut.

AOF `everysec` can lose roughly one second of writes on a host failure. The
`local-path` PVC survives pod replacement, not loss of the Colima disk.

## Operations

```sh
flux reconcile helmrelease sake-deps -n sake
flux reconcile helmrelease sake-api -n sake
flux reconcile helmrelease sake-worker -n sake
flux reconcile helmrelease sake-studio -n sake
kubectl -n sake get helmrelease sake-deps sake-api sake-worker sake-studio
kubectl -n sake get pods,pvc
```
