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

If you have `just` installed, only cluster and Flux setup workflows are kept in `justfile`:

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
- `sake/ghcr-auth`, Docker registry credentials for `ghcr.io`
- `sake/sake-runtime-secrets`, runtime credentials such as `SAKE_ADMIN_EMAIL`, `SAKE_ADMIN_PASSWORD`, `LLM_API_KEY`, `EMBEDDING_API_KEY`, `TAVILY_API_KEY`, and `LANGSMITH_API_KEY`

The Sake chart creates `sake/sake-dev-secrets` with local-only Postgres and MinIO defaults. Do not put real external API keys in that chart-managed Secret.

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

kubectl -n sake create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username='<github-username>' \
  --docker-password='<github-token-with-read-packages>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Create or refresh Sake runtime credentials before deploying the Sake API and worker. `SAKE_ADMIN_EMAIL` and `SAKE_ADMIN_PASSWORD` seed the master login account after migrations. The Colima Sake overlay currently uses the local OpenAI-compatible chat completions endpoint on `host.docker.internal:8317`, Gemini for embeddings, Tavily for agentic lead research search, and LangSmith tracing for worker research traces:

```sh
kubectl -n sake create secret generic sake-runtime-secrets \
  --from-literal=SAKE_ADMIN_EMAIL='<master-admin-email>' \
  --from-literal=SAKE_ADMIN_PASSWORD='<master-admin-password>' \
  --from-literal=LLM_API_KEY='<local-llm-api-key-or-placeholder>' \
  --from-literal=EMBEDDING_API_KEY='<gemini-api-key>' \
  --from-literal=TAVILY_API_KEY='<tavily-api-key>' \
  --from-literal=LANGSMITH_API_KEY='<langsmith-api-key>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

If you refresh `sake-runtime-secrets` without changing the Helm values or image tag, restart the running pods so `envFrom` picks up the new Secret data:

```sh
kubectl -n sake rollout restart deployment/sake-api deployment/sake-worker
```

Sake GHCR packages should remain private. After the `Release images` workflow pushes `ghcr.io/triflam/sake-api:main-<sha>` and `ghcr.io/triflam/sake-worker:main-<sha>`, update the pinned tags with the **Update image tag** GitHub Actions workflow.

Before using the workflow, create a GitHub Environment named `image-tag-update` and configure Required reviewers. The workflow targets this environment, so the commit job waits for deployment review before it updates files and pushes back to the selected ref.

For Sake, run the workflow with:

```text
app: sake
tag: main-<sha>
targets: [{"file":"apps/colima/sake/api-values.yaml","path":"image.tag"},{"file":"apps/colima/sake/worker-values.yaml","path":"image.tag"}]
```

For Flamres, run the workflow with:

```text
app: flamres
tag: main-<sha>
targets: [{"file":"apps/colima/flamres/values.yaml","path":"image.tag"}]
```

To dispatch the same workflow from another GitHub Actions workflow, use the composite action. It always dispatches `eatsteak/local-helm`.

Same-repository callers can use `${{ github.token }}` with `actions: write` permission. Callers from other repositories must pass a PAT or GitHub App installation token with Actions write access to `eatsteak/local-helm`.

```yaml
permissions:
  actions: write

steps:
  - name: Dispatch Sake image tag update
    uses: eatsteak/local-helm/.github/actions/dispatch-update-image-tag@main
    with:
      github-token: ${{ github.token }}
      app: sake
      tag: main-<sha>
      targets: >-
        [{"file":"apps/colima/sake/api-values.yaml","path":"image.tag"},{"file":"apps/colima/sake/worker-values.yaml","path":"image.tag"}]
```

For Flamres, use:

```yaml
steps:
  - name: Dispatch Flamres image tag update
    uses: eatsteak/local-helm/.github/actions/dispatch-update-image-tag@main
    with:
      github-token: ${{ secrets.LOCAL_HELM_ACTIONS_TOKEN }}
      app: flamres
      tag: main-<sha>
      targets: >-
        [{"file":"apps/colima/flamres/values.yaml","path":"image.tag"}]
```

Do not commit rendered Secrets, Cloudflare API tokens, tunnel credential JSON files, registry credentials, or real external API keys.
