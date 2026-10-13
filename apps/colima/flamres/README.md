# Flamres

Colima GitOps overlay for the Flamres bot in the `flamres` namespace. The app is configured for Slack, Linear, Notion, MemKraft, Canvas publishing, and the Pi agent runtime. OpenCode settings remain during the cutover and rollback window.

## Managed resources

- `namespace.yaml` creates the `flamres` namespace.
- `kustomization.yaml` generates the `flamres-values` ConfigMap from `values.yaml`.
- `helmrelease.yaml` reconciles `HelmRelease/flamres` from the local chart `./charts/flamres` using `GitRepository/flux-system`.
- `pvc.yaml` creates the PVCs used by this overlay because `values.yaml` sets both persistence entries to `create: false`.

`deployment.yaml` is not listed in `kustomization.yaml`; the Flux-managed app path uses the HelmRelease.

## Runtime configuration

- Image: `ghcr.io/triflam/flamres-bot`, pinned by `image.tag` in `values.yaml`
- Image pull Secret: `flamres/ghcr-auth`
- ConfigMap: `flamres-config`
- Secret: `flamres-secrets`
- Container port: `3000`

Important config entries in `values.yaml` include:

- Canvas publishing: `CANVAS_PUBLISH_URL`
- MemKraft MCP: `MCP_MEMKRAFT_ENABLED`, `MEMKRAFT_DIR`, `MEMKRAFT_PYTHON`
- Slack MCP: `MCP_SLACK_ENABLED`, `SLACK_MCP_ENABLED_TOOLS`
- Notion calendar sync: `NOTION_CALENDAR_SYNC_*`
- Pi: `PI_MODEL`, `PI_PROVIDER_BASE_URL`, `PI_PROMPT_TIMEOUT_MS`, `PI_WORKDIR`, `PI_BUNDLED_RESOURCES_DIR`
- Pi state: `PI_AGENT_DIR`, `PI_SESSION_DIR`, `PI_THREAD_SESSION_STORE_PATH`
- OpenCode rollback compatibility: `OPENCODE_*`
- Existing state paths: `SCHEDULE_STORE_PATH`, `THREAD_SESSION_STORE_PATH`, `NOTION_CALENDAR_SYNC_STORE_PATH`, `SLACK_BLOCKS_DIR`

Linear uses the `linear` CLI and `LINEAR_API_KEY` from the runtime Secret, not Linear MCP/OAuth.

## Networking

This overlay does not define an Ingress. The chart still creates an internal ClusterIP service on port `3000`.

Startup and readiness probes use `/health/ready`; liveness uses `/health/live` on the named `http` port. Provider readiness failures must not drive the liveness probe. The current pre-Pi image also supports these endpoints.

## Storage

- `flamres-opencode-data`: `ReadWriteOnce`, `local-path`, `1Gi`, mounted at `/home/node/.local`
- `flamres-workdir`: `ReadWriteOnce`, `local-path`, `2Gi`, mounted at `/workspace`

The deployment uses one replica and `Recreate`: upgrades briefly interrupt service but avoid overlapping Slack/scheduler instances and concurrent writers to file-backed state. Keep `replicaCount: 1`; `Recreate` does not make multi-replica operation safe.

Keep these PVC claim names and mount paths unchanged, including the legacy `opencode` name. Existing mappings, schedules, calendar sync data and Slack Blocks stay under `/home/node/.local/share/triflam-bot`; Pi uses new `pi-agent`, `pi-sessions` and `pi-thread-sessions.json` paths in that same directory. Do not move existing files to the application's default `flamres-bot` directory.

## Secrets

Create or refresh the registry pull Secret and runtime Secret outside GitOps. Do not commit real Slack, Linear, Notion, MemKraft, Pi/OpenCode, or other external credentials.

`flamres-secrets` must contain `PI_API_KEY` before the Pi image is activated. For the unchanged provider endpoint, copy the existing `OPENCODE_API_KEY` to `PI_API_KEY` without printing or writing its value to a file. Do not overwrite an existing different Pi credential. Keep `OPENCODE_API_KEY` and all other credentials intact for the running OpenCode image and rollback; adding a Secret key does not require restarting that image.

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

## Pi cutover and rollback

1. Prepare `PI_API_KEY` in `flamres/flamres-secrets` first; retain `OPENCODE_API_KEY`.
2. Merge the Helm preparation changes **before** [flamres-bot PR #2](https://github.com/triflam/flamres-bot/pull/2). The preparation keeps the current image tag and both runtime configurations, so it remains compatible with OpenCode. Flux will roll the pod to add health probes when the chart is reconciled.
3. After the Helm release is Ready, merge the bot PR. Its `main` workflow publishes the Pi image and dispatches the image-tag update above; Flux then deploys it. Do not activate the Pi image before the Helm settings and Secret are prepared.
4. Check startup/readiness, actual Slack mention/DM/follow-up and question-modal flows, Linear CLI authentication, and Pi session reuse after a pod restart. These live checks are not covered by template tests.
5. Keep the previous image tag/digest and matching ConfigMap/Secret snapshot until validation is complete. Roll back image and runtime settings together, without replacing either PVC. Remove compatibility settings and the old credential only after the rollback window closes.

OpenCode mappings remain readable and are not overwritten, but OpenCode conversation history is **not** converted to Pi JSONL. The first Pi request in an existing thread starts a new Pi conversation.

## Validation

These checks only render manifests; they do not deploy, read Secrets or call Slack:

```sh
helm lint --strict charts/flamres -f apps/colima/flamres/values.yaml
ruby tests/flamres_test.rb
```

The `Validate Flamres deployment` PR workflow runs the same checks for changes to this overlay, its chart or tests.

## Operations

```sh
flux reconcile helmrelease flamres -n flamres
kubectl -n flamres get helmrelease flamres
kubectl -n flamres get pods,pvc
```
