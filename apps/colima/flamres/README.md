# Flamres

Colima GitOps overlay for the Flamres bot in the `flamres` namespace. The app is configured for Slack, Linear, Notion, MemKraft, Canvas publishing, and OpenCode-related workflows.

## Managed resources

- `namespace.yaml` creates the `flamres` namespace.
- `kustomization.yaml` generates the `flamres-values` ConfigMap from `values.yaml`.
- `helmrelease.yaml` reconciles `HelmRelease/flamres` from the local chart `./charts/flamres` using `GitRepository/flux-system`.
- `pvc.yaml` creates the PVCs used by this overlay because `values.yaml` sets both persistence entries to `create: false`.

`deployment.yaml` is not listed in `kustomization.yaml`; the Flux-managed app path uses the HelmRelease.

## Runtime configuration

- Image: `ghcr.io/triflam/flamres-bot:main-0fcdc35`
- Image pull Secret: `flamres/ghcr-auth`
- ConfigMap: `flamres-config`
- Secret: `flamres-secrets`
- Container port: `3000`

Important config entries in `values.yaml` include:

- Canvas publishing: `CANVAS_PUBLISH_URL`
- Linear MCP: `MCP_LINEAR_ENABLED`, `MCP_LINEAR_URL`
- MemKraft MCP: `MCP_MEMKRAFT_ENABLED`, `MEMKRAFT_DIR`, `MEMKRAFT_PYTHON`
- Slack MCP: `MCP_SLACK_ENABLED`, `SLACK_MCP_ENABLED_TOOLS`
- Notion calendar sync: `NOTION_CALENDAR_SYNC_*`
- OpenCode: `OPENCODE_*`
- Local state paths: `SCHEDULE_STORE_PATH`, `THREAD_SESSION_STORE_PATH`, `SLACK_BLOCKS_DIR`

## Networking

This overlay does not define an Ingress. The chart still creates an internal ClusterIP service on port `3000`.

## Storage

- `flamres-opencode-data`: `ReadWriteOnce`, `local-path`, `1Gi`, mounted at `/home/node/.local`
- `flamres-workdir`: `ReadWriteOnce`, `local-path`, `2Gi`, mounted at `/workspace`

## Secrets

Create or refresh the registry pull Secret and runtime Secret outside GitOps. Do not commit real Slack, Linear, Notion, MemKraft, OpenCode, or other external credentials.

```sh
kubectl -n flamres create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username='<github-username>' \
  --docker-password='<github-token-with-read-packages>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Image tag updates

After a new `ghcr.io/triflam/flamres-bot:main-<sha>` image is published, update `apps/colima/flamres/values.yaml` with the **Update image tag** GitHub Actions workflow:

```text
app: flamres
tag: main-<sha>
targets: [{"file":"apps/colima/flamres/values.yaml","path":"image.tag"}]
```

## Operations

```sh
flux reconcile helmrelease flamres -n flamres
kubectl -n flamres get helmrelease flamres
kubectl -n flamres get pods,pvc
```
