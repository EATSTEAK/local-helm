# Insights Write

Colima GitOps overlay for the `insights-write` app, exposed at `https://write.koohyom.in`.

## Managed resources

- `kustomization.yaml` generates the `insights-write-values` ConfigMap from `values.yaml`.
- `helmrelease.yaml` reconciles `HelmRelease/insights-write` in the `koohyomin` namespace from the local chart `./charts/insights-write` using `GitRepository/flux-system`.
- The chart creates the app Deployment, Service, Ingress, ConfigMap, and PVC from `values.yaml`.

## Runtime configuration

- Image: `ghcr.io/eatsteak/insights-write:latest`
- Image pull Secret: `koohyomin/ghcr-auth`
- Secret reference: `insights-write-secrets` with `optional: false`
- Container port: `4321`
- Key config values:
  - `NODE_ENV=production`
  - `HOST=0.0.0.0`
  - `PORT=4321`
  - `LLM_SERVERS_FILE=/app/data/llm-servers.json`
  - `R2_BUCKET_NAME=insights-content`
  - `MLX_OMNI_BASE_URL=http://host.docker.internal:10240/v1`
  - `CF_TARGET_BRANCH=main`

## Networking

Ingress is enabled with class `nginx` and host `write.koohyom.in`. ExternalDNS publishes the Cloudflare Tunnel target with:

```yaml
external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
external-dns.alpha.kubernetes.io/target: 9b1820c5-3168-4638-a1f0-9fe1585eda94.cfargotunnel.com
```

## Storage

The chart creates `insights-write-data`, a `ReadWriteOnce` `local-path` PVC with `1Gi` capacity, mounted at `/app/data`. `LLM_SERVERS_FILE` points into this volume.

## Secrets

Create `koohyomin/ghcr-auth` for GHCR pulls and `koohyomin/insights-write-secrets` for runtime credentials outside GitOps. Do not commit Cloudflare, R2, LLM, or other external credentials.

## Operations

```sh
flux reconcile helmrelease insights-write -n koohyomin
kubectl -n koohyomin get helmrelease insights-write
kubectl -n koohyomin get pods,pvc -l app.kubernetes.io/name=insights-write
```
