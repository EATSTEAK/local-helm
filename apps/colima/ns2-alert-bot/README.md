# NS2 Alert Bot

Colima GitOps overlay for the NS2 alert worker in the `koohyomin` namespace.

## Managed resources

- `kustomization.yaml` generates the `ns2-alert-bot-values` ConfigMap from `values.yaml`.
- `helmrelease.yaml` reconciles `HelmRelease/ns2-alert-bot` from the local chart `./charts/ns2-alert-bot` using `GitRepository/flux-system`.
- The chart renders a worker Deployment, ConfigMap, and PVC. It does not define an Ingress.

## Runtime configuration

- Image: `ghcr.io/eatsteak/ns2-alert-bot:main-07e83f6273f314b1bd07fd9a901fbd31b1efbdd2`
- Image pull Secret: `koohyomin/ghcr-auth`
- Command: `ns2-alert-bot --config /app/config/targets.yaml run`
- Key config values:
  - `POLL_INTERVAL_SECONDS=60`
  - `STATE_DB_PATH=/data/ns2-alert-bot.sqlite3`
  - `HTTP_TIMEOUT_SECONDS=15`

## Storage

The chart default enables persistence with claim name `ns2-alert-bot-data`, mounted at `/data`. This stores the SQLite state database referenced by `STATE_DB_PATH`.

## Secrets

The chart default references `ns2-alert-bot-runtime-secrets` with `optional: false`. Create the runtime Secret outside GitOps before deployment:

```sh
kubectl create namespace koohyomin --dry-run=client -o yaml | kubectl apply -f -

kubectl -n koohyomin create secret generic ns2-alert-bot-runtime-secrets \
  --from-literal=TELEGRAM_BOT_TOKEN='<telegram-bot-token>' \
  --from-literal=TELEGRAM_CHAT_ID='<telegram-chat-id-or-channel>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

`TELEGRAM_THREAD_ID` can also be added when the bot should post into a specific Telegram topic/thread.

Create or refresh the GHCR pull Secret separately:

```sh
kubectl -n koohyomin create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username='<github-username>' \
  --docker-password='<github-token-with-read-packages>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Image tag updates

After a new `ghcr.io/eatsteak/ns2-alert-bot:main-<sha>` image is published, update `apps/colima/ns2-alert-bot/values.yaml` with the **Update image tag** GitHub Actions workflow:

```text
app: ns2-alert-bot
tag: main-<sha>
targets: [{"file":"apps/colima/ns2-alert-bot/values.yaml","path":"image.tag"}]
```

## Operations

```sh
flux reconcile helmrelease ns2-alert-bot -n koohyomin
kubectl -n koohyomin get helmrelease ns2-alert-bot
kubectl -n koohyomin get pods,pvc -l app.kubernetes.io/name=ns2-alert-bot
```
