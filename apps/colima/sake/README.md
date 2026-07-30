# Sake

Colima GitOps overlay for Sake in the `sake` namespace. The deployment is split into dependency, API, and worker Helm releases.

## Managed resources

- `namespace.yaml` creates the `sake` namespace.
- `kustomization.yaml` generates three ConfigMaps:
  - `sake-deps-values` from `deps-values.yaml`
  - `sake-api-values` from `api-values.yaml`
  - `sake-worker-values` from `worker-values.yaml`
- `helmrelease-deps.yaml` reconciles `HelmRelease/sake-deps` from the local chart `./charts/sake-deps`.
- `helmrelease-api.yaml` reconciles `HelmRelease/sake-api` from `./charts/sake-api` and depends on `sake-deps`.
- `helmrelease-worker.yaml` reconciles `HelmRelease/sake-worker` from `./charts/sake-worker` and depends on both `sake-deps` and `sake-api`.

## Runtime configuration

- API image: `ghcr.io/triflam/sake-app:main-255ae25`
- Worker image: `ghcr.io/triflam/sake-app:main-255ae25`
- Image pull Secret: `sake/ghcr-auth`
- LLM endpoint: `http://host.docker.internal:8317/v1`
- LLM model: `gpt-5.5`
- Embedding endpoint: `https://generativelanguage.googleapis.com/v1beta/openai`
- API embedding model: `gemini-embedding-2-preview`
- Worker embedding model: `gemini-embedding-2`
- Embedding dimensions: `1536`

The API chart runs Prisma migration and master account seed jobs as Helm hooks. The worker is configured for Tavily-backed research search, Crawl4AI crawling, and LangSmith tracing in the local overlay.

## Dependencies

`sake-deps` deploys local development dependencies:

- PostgreSQL with pgvector: `pgvector/pgvector:pg16`, PVC `sake-postgres-data`, `8Gi`
- Redis: `redis:7-alpine`
- MinIO: `minio/minio:RELEASE.2025-09-07T16-13-09Z`, bucket `sake-dev`, PVC `sake-minio-data`, `10Gi`
- Crawl4AI: `unclecode/crawl4ai:0.9.2` pinned by digest
- Secret: `sake-dev-secrets` with local-only Postgres and MinIO defaults

Do not put real external API keys in chart-managed Secrets.

## Networking

The API Ingress is enabled with class `nginx` and host `sake.koohyom.in`. The API also trusts both `https://sake.triflam.team` and `https://sake.koohyom.in` through `BETTER_AUTH_TRUSTED_ORIGINS`.

## Secrets

Create or refresh the GHCR pull Secret outside GitOps:

```sh
kubectl -n sake create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username='<github-username>' \
  --docker-password='<github-token-with-read-packages>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Create or refresh `sake-runtime-secrets` before deploying dependencies, API, and worker. `SAKE_ADMIN_EMAIL` and `SAKE_ADMIN_PASSWORD` seed the master login account; the remaining keys back local LLM, embedding, Tavily, LangSmith, and Crawl4AI integrations.

Crawl4AI 0.9.2 intentionally binds only to loopback when no API token is configured, so a Kubernetes `ClusterIP` alone cannot bypass authentication. The same random token must be mounted into Crawl4AI and the Sake worker. The dependency chart also limits Crawl4AI ingress to worker pods and egress to public HTTP/HTTPS plus cluster DNS; this requires the cluster CNI to enforce `NetworkPolicy`:

```sh
kubectl -n sake create secret generic sake-runtime-secrets \
  --from-literal=SAKE_ADMIN_EMAIL='<master-admin-email>' \
  --from-literal=SAKE_ADMIN_PASSWORD='<master-admin-password>' \
  --from-literal=LLM_API_KEY='<local-llm-api-key-or-placeholder>' \
  --from-literal=EMBEDDING_API_KEY='<gemini-api-key>' \
  --from-literal=TAVILY_API_KEY='<tavily-api-key>' \
  --from-literal=LANGSMITH_API_KEY='<langsmith-api-key>' \
  --from-literal=CRAWL4AI_API_TOKEN="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

If only Secret data changes, restart running pods so `envFrom` picks up the new values:

```sh
kubectl -n sake rollout restart deployment/sake-crawl4ai deployment/sake-api deployment/sake-worker
```

## Image tag updates

After the release workflow publishes a new `ghcr.io/triflam/sake-app:main-<sha>` image, update both pinned tags with the **Update image tag** GitHub Actions workflow:

```text
app: sake
tag: main-<sha>
targets: [{"file":"apps/colima/sake/api-values.yaml","path":"image.tag"},{"file":"apps/colima/sake/worker-values.yaml","path":"image.tag"}]
```

## Operations

```sh
flux reconcile helmrelease sake-deps -n sake
flux reconcile helmrelease sake-api -n sake
flux reconcile helmrelease sake-worker -n sake
kubectl -n sake get helmrelease sake-deps sake-api sake-worker
kubectl -n sake get pods,pvc
```
