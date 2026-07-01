# PNL

Colima GitOps overlay for the PNL service in the `koohyomin` namespace. The app deploys API, web, sync CronJobs, and a TimescaleDB dependency stack.

## Managed resources

- `kustomization.yaml` generates two ConfigMaps:
  - `pnl-values` from `pnl-values.yaml`
  - `pnl-deps-values` from `pnl-deps-values.yaml`
- `helmrelease-pnl-deps.yaml` reconciles `HelmRelease/pnl-deps` from the local chart `./charts/pnl-deps`.
- `helmrelease-pnl.yaml` reconciles `HelmRelease/pnl` from the local chart `./charts/pnl` and depends on `pnl-deps`.

## Runtime configuration

Application images:

- API: `ghcr.io/triflam/pnl-api:main`
- Web: `ghcr.io/triflam/pnl-web:main`
- Sync: `ghcr.io/triflam/pnl-sync:main`

Shared settings:

- Image pull Secret: `koohyomin/ghcr-auth`
- Secret reference: `pnl-runtime-secrets` with `optional: false`
- Database URL: `pnl-runtime-secrets` key `DATABASE_URL`
- Public API URL: `https://pnl.koohyom.in`
- WebSocket URL: `wss://pnl.koohyom.in/ws`
- Base currency: `KRW`
- Secondary currency: `USD`

## Dependencies

`pnl-deps` deploys TimescaleDB:

- Image: `timescale/timescaledb:2.17.2-pg16`
- Database: `pnl`
- User: `pnl`
- Password Secret: `pnl-postgres` key `password`
- Storage: `20Gi` through the StatefulSet volume claim template

The dependency chart also creates `pnl-runtime-secrets` with local default values for:

- `DATABASE_URL`
- `EMAIL_INGEST_HMAC_SECRET`
- `DEBANK_API_KEY`
- `CCXT_EXCHANGE_CREDENTIALS_JSON`

Do not put real exchange, DeBank, or other external credentials in chart-managed defaults.

## Sync schedules

The `pnl` chart renders these CronJobs from `pnl-values.yaml`:

- `pnl-sync-debank`: `*/15 * * * *`
- `pnl-sync-ccxt`: `*/10 * * * *`
- `pnl-sync-prices`: `*/5 * * * *`

## Networking

Ingress is enabled with class `nginx` and host `pnl.koohyom.in`. ExternalDNS publishes the Cloudflare Tunnel target with:

```yaml
external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
external-dns.alpha.kubernetes.io/target: 9b1820c5-3168-4638-a1f0-9fe1585eda94.cfargotunnel.com
```

## Operations

```sh
flux reconcile helmrelease pnl-deps -n koohyomin
flux reconcile helmrelease pnl -n koohyomin
kubectl -n koohyomin get helmrelease pnl-deps pnl
kubectl -n koohyomin get pods,cronjobs,pvc -l app.kubernetes.io/name=pnl
```
