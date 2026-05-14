# local-helm

Public Helm chart and Flux GitOps repository for local Kubernetes utilities.

This repository publishes `cloudflare-kube-tunnel`, an umbrella chart that exposes a local Colima Kubernetes cluster through Cloudflare Tunnel. It also contains Flux-managed manifests for the local Colima cluster.

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

## GitOps Operations

Flux syncs the Colima cluster from `clusters/colima` on the `main` branch:

```text
clusters/colima/           # Flux root for the local cluster
infrastructure/colima/     # HelmRepository and HelmRelease resources
apps/colima/               # Application manifests
```

Check Flux status:

```sh
just flux-status
```

Force Flux to fetch the latest Git revision and reconcile both layers:

```sh
just flux-reconcile
```

Inspect the current cluster inventory:

```sh
just cluster-inventory
```

Check application rollouts:

```sh
just apps-status
```

Flux `Kustomization` resources currently use `prune: false` while the cluster is being migrated. Enable pruning only after each managed layer is verified to contain every resource that should remain in the cluster.

If a layer needs to be paused during troubleshooting:

```sh
flux suspend kustomization apps -n flux-system
flux resume kustomization apps -n flux-system
```

For Helm-managed infrastructure:

```sh
flux suspend helmrelease ingress-nginx -n ingress-nginx
flux resume helmrelease ingress-nginx -n ingress-nginx
```

## Published Packages

- `packages/cloudflare-kube-tunnel-0.1.0.tgz`
- `index.yaml`

Regenerate packages and index:

```sh
./scripts/package.sh
```

## Secret Handling

No Cloudflare API tokens, tunnel credential JSON files, Slack tokens, or app credentials are committed.

These Kubernetes Secrets are maintained manually and referenced by GitOps manifests only by name:

- `cloudflare-tunnel/cloudflare-tunnel-credentials`, key `credentials.json`
- `external-dns/cloudflare-api-token`, key `api-token`
- `triflam-bot/triflam-bot-secrets`

Create or refresh the Cloudflare Secrets manually:

```sh
kubectl -n cloudflare-tunnel create secret generic cloudflare-tunnel-credentials \
  --from-file=credentials.json="$HOME/.cloudflared/9b1820c5-3168-4638-a1f0-9fe1585eda94.json" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n external-dns create secret generic cloudflare-api-token \
  --from-literal=api-token='<cloudflare-api-token>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Do not enable chart values that create Secrets with inline credentials unless those values remain outside Git.
