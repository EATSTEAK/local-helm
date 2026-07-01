# Canvas

Colima GitOps overlay for the Canvas app, exposed at `https://canvas.koohyom.in`.

## Managed resources

- `kustomization.yaml` generates the `canvas-values` ConfigMap from `values.yaml` and applies the app resources.
- `helmrelease.yaml` reconciles `HelmRelease/canvas` in the `koohyomin` namespace from the local chart `./charts/canvas` using `GitRepository/flux-system`.
- `pvc.yaml` creates `PersistentVolumeClaim/canvas-data` because this overlay sets `persistence.create: false` in Helm values.

## Runtime configuration

- Image: `ghcr.io/eatsteak/canvas.koohyom.in:main`
- Image pull Secret: `koohyomin/ghcr-auth`
- Runtime env:
  - `PUBLIC_BASE_URL=https://canvas.koohyom.in`
  - `DATA_DIR=/data`
  - `MAX_BODY_BYTES=5242880`
- Health checks and Ingress paths use `/healthz`, `/view`, and `/content`.

## Networking

Ingress is enabled with class `nginx` and host `canvas.koohyom.in`. ExternalDNS publishes the Cloudflare Tunnel target with:

```yaml
external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
external-dns.alpha.kubernetes.io/target: 9b1820c5-3168-4638-a1f0-9fe1585eda94.cfargotunnel.com
```

## Storage

`canvas-data` is a `ReadWriteOnce` `local-path` PVC with `1Gi` capacity and is mounted at `/data`.

## Operations

```sh
flux reconcile helmrelease canvas -n koohyomin
kubectl -n koohyomin get helmrelease canvas
kubectl -n koohyomin get pods,pvc -l app.kubernetes.io/name=canvas
```
