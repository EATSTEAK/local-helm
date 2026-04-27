# local-helm

Public Helm chart repository for local Kubernetes utilities.

This repository currently publishes `cloudflare-kube-tunnel`, an umbrella chart that exposes a local Colima Kubernetes cluster through Cloudflare Tunnel.

## Repository Usage

After this repo is published with GitHub Pages enabled from the default branch root, add it as a Helm repository:

```sh
helm repo add local-helm https://koohyomin.github.io/local-helm
helm repo update
helm search repo local-helm
```

Install the chart:

```sh
kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -
kubectl -n cloudflare-tunnel create secret generic cloudflare-tunnel-credentials \
  --from-file=credentials.json="$HOME/.cloudflared/9b1820c5-3168-4638-a1f0-9fe1585eda94.json" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-dns create secret generic cloudflare-api-token \
  --from-literal=api-token='<cloudflare-api-token>' \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install cloudflare-kube-tunnel local-helm/cloudflare-kube-tunnel \
  --namespace default
```

For local development before GitHub Pages is enabled:

```sh
helm dependency update charts/cloudflare-kube-tunnel
helm upgrade --install cloudflare-kube-tunnel ./charts/cloudflare-kube-tunnel
```

## Published Packages

- `packages/cloudflare-kube-tunnel-0.1.0.tgz`
- `index.yaml`

Regenerate packages and index:

```sh
./scripts/package.sh
```

## Secret Handling

No Cloudflare API tokens or tunnel credential JSON files are committed.

The chart expects these Kubernetes Secrets to exist by default:

- `cloudflare-tunnel/cloudflare-tunnel-credentials`, key `credentials.json`
- `external-dns/cloudflare-api-token`, key `api-token`

Alternatively, set the chart values that create those secrets at install time, but do not commit those values.
