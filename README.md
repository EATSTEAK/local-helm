# local-helm

Source-based Helm chart and Flux GitOps repository for local Kubernetes utilities.

This repository contains `cloudflare-kube-tunnel`, a small Helm wrapper that installs Cloudflare Tunnel for an existing Kubernetes ingress controller. It also contains Flux-managed manifests for the local Colima cluster.

## Chart Usage

`cloudflare-kube-tunnel` does not install `ingress-nginx` or `external-dns` by default. Use it in clusters where an ingress controller already exists and where ExternalDNS is already responsible for publishing DNS records from application Ingress annotations.

Create the Cloudflare Tunnel credentials Secret in the release namespace before installing the chart:

```sh
kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -

kubectl -n cloudflare-tunnel create secret generic cloudflare-tunnel-credentials \
  --from-file=credentials.json="$HOME/.cloudflared/9b1820c5-3168-4638-a1f0-9fe1585eda94.json" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Install from source:

```sh
helm dependency update ./charts/cloudflare-kube-tunnel
helm upgrade --install cloudflare-tunnel ./charts/cloudflare-kube-tunnel \
  --namespace cloudflare-tunnel \
  --create-namespace \
  -f ./charts/cloudflare-kube-tunnel/examples/values-colima.yaml
```

The chart passes values through to the upstream `cloudflare-tunnel` chart. A minimal values file looks like this:

```yaml
cloudflare-tunnel:
  enabled: true
  cloudflare:
    secretName: cloudflare-tunnel-credentials
    tunnelName: colima-k8s-koohyomin
    tunnelId: 9b1820c5-3168-4638-a1f0-9fe1585eda94
    ingress:
      - hostname: "*.koohyom.in"
        service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
```

Application Ingresses publish Cloudflare Tunnel CNAME records through ExternalDNS annotations:

```yaml
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/target: 9b1820c5-3168-4638-a1f0-9fe1585eda94.cfargotunnel.com
    external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
```

## Local Cluster Management

This repository includes a Colima profile config in `config/colima/values.yaml`.
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

For local chart validation:

```sh
just helm-lint
```

## GitOps Operations

Flux syncs the Colima cluster from `clusters/colima` on the `main` branch:

```text
clusters/colima/           # Flux root for the local cluster
infrastructure/colima/     # HelmRepository and HelmRelease resources
apps/colima/               # Application manifests
```

The GitOps infrastructure layer installs `ingress-nginx` and `external-dns` as separate Helm releases. The `cloudflare-tunnel` Helm release uses the local chart at `./charts/cloudflare-kube-tunnel` from the Flux GitRepository source and reconciles on Git revisions.

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

Flux `Kustomization` resources use pruning, so verify each managed layer contains every resource that should remain in the cluster before removing manifests.

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

## Secret Handling

No Cloudflare API tokens, tunnel credential JSON files, Slack tokens, or app credentials are committed.

These Kubernetes Secrets are maintained outside the chart and referenced by GitOps manifests only by name:

- `cloudflare-tunnel/cloudflare-tunnel-credentials`, key `credentials.json`
- `external-dns/cloudflare-api-token`, key `api-token`
- `default/ghcr-auth`, Docker registry credentials for `ghcr.io`
- `flamres/ghcr-auth`, Docker registry credentials for `ghcr.io`
- `flamres/flamres-secrets`

Create or refresh the Cloudflare Secrets manually:

```sh
kubectl -n cloudflare-tunnel create secret generic cloudflare-tunnel-credentials \
  --from-file=credentials.json="$HOME/.cloudflared/9b1820c5-3168-4638-a1f0-9fe1585eda94.json" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n external-dns create secret generic cloudflare-api-token \
  --from-literal=api-token='<cloudflare-api-token>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Create or refresh the GHCR pull Secrets in every namespace that references them:

```sh
kubectl -n default create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username='<github-username>' \
  --docker-password='<github-token>' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n flamres create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username='<github-username>' \
  --docker-password='<github-token>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Do not commit rendered Secrets, Cloudflare API tokens, tunnel credential JSON files, or registry credentials.
