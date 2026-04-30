# local-helm

Public Helm chart repository for local Kubernetes utilities.

This repository currently publishes `cloudflare-kube-tunnel`, an umbrella chart that exposes a local Colima Kubernetes cluster through Cloudflare Tunnel.

## Repository Usage

Add the local directory as a Helm repository:

```sh
helm repo add local-helm file:///Users/koohyomin/Projects/local-helm
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

## Local Cluster Management

This repository includes a Colima profile config in `config/colima/default.yaml`.
The local cluster is configured for Kubernetes with `6GiB` memory.

If you have `just` installed, common workflows are available through `justfile`:

```sh
just colima-start
just colima-restart
just colima-status
just colima-apply-config
just cluster-install
just cluster-uninstall
```

The same Colima settings can also be applied directly:

```sh
colima start --profile default --cpus 2 --memory 6 --disk 100 \
  --runtime docker --kubernetes --kubernetes-version v1.33.4+k3s1 \
  --k3s-arg='--disable=traefik'
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
