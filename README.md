# local-helm

Source-based Helm chart and Flux GitOps repository for local Kubernetes utilities.

This root README is an index. App-specific deployment details live in each app README under `apps/colima/*/README.md`.

## Repository index

| Path | Purpose |
| --- | --- |
| `clusters/colima/` | Flux root for the local Colima cluster. |
| `infrastructure/colima/` | Cluster infrastructure overlays, including HelmRepository and HelmRelease resources. |
| `apps/colima/` | Flux-managed application overlays for the Colima cluster. |
| `charts/` | Local source Helm charts used by Flux HelmReleases. |
| `config/colima/` | Local Colima profile configuration. |
| `.github/actions/dispatch-update-image-tag/` | Composite action for dispatching image tag update workflows. |
| `.github/workflows/update-image-tag.yaml` | Workflow for updating pinned app image tags in GitOps values files. |

## App README index

| App | Namespace | Public host | README |
| --- | --- | --- | --- |
| Canvas | `koohyomin` | `canvas.koohyom.in` | [`apps/colima/canvas/README.md`](apps/colima/canvas/README.md) |
| Flamres | `flamres` | Internal service only | [`apps/colima/flamres/README.md`](apps/colima/flamres/README.md) |
| Grimmory | `default` | `books.koohyom.in` | [`apps/colima/grimmory/README.md`](apps/colima/grimmory/README.md) |
| Insights Write | `koohyomin` | `write.koohyom.in` | [`apps/colima/insights-write/README.md`](apps/colima/insights-write/README.md) |
| NS2 Alert Bot | `koohyomin` | Worker, no Ingress | [`apps/colima/ns2-alert-bot/README.md`](apps/colima/ns2-alert-bot/README.md) |
| Open WebUI | `open-webui` | `chat.koohyom.in` | [`apps/colima/open-webui/README.md`](apps/colima/open-webui/README.md) |
| Sake | `sake` | `sake.koohyom.in` | [`apps/colima/sake/README.md`](apps/colima/sake/README.md) |

## Local cluster operations

The Colima profile config is kept in `config/colima/values.yaml`. If you have `just` installed, use the repository recipes for local cluster and Flux operations:

```sh
just colima-start
just colima-restart
just colima-status
just colima-apply-config
just cluster-install
just cluster-uninstall
just flux-status
just flux-reconcile
```

Flux syncs the Colima cluster from `clusters/colima` on the `main` branch. The app layer includes every overlay listed in `apps/colima/kustomization.yaml`.

## Cloudflare Tunnel chart

`charts/cloudflare-kube-tunnel` is a local wrapper around the upstream Cloudflare Tunnel chart. It expects the tunnel credential Secret to be created outside the chart and routes application Ingresses through the existing local ingress controller.

The Colima example values are in [`charts/cloudflare-kube-tunnel/examples/values-colima.yaml`](charts/cloudflare-kube-tunnel/examples/values-colima.yaml).

## Secrets and credentials

No Cloudflare API tokens, tunnel credential JSON files, Slack tokens, app credentials, registry credentials, or real external API keys should be committed.

Keep runtime Secrets outside GitOps unless a chart explicitly documents local-only defaults. App-specific Secret names and refresh commands are documented in each app README.

Common externally managed Secrets include:

- Cloudflare Tunnel credentials and ExternalDNS API token
- GHCR pull Secrets per namespace
- Runtime Secrets for apps such as Flamres, Insights Write, NS2 Alert Bot, PNL, and Sake

## Image tag updates

Private or pinned app images are updated through the **Update image tag** GitHub Actions workflow. Each app README includes the target values file and JSON path for that app.

For cross-repository dispatches, use the composite action at `.github/actions/dispatch-update-image-tag` with a token that can dispatch workflows in `eatsteak/local-helm`.

## Safety notes

Flux `Kustomization` resources use pruning. Before removing manifests or entries from an overlay, verify that every resource that should remain in the cluster is still represented elsewhere.

Do not commit rendered Secrets, Cloudflare API tokens, tunnel credential JSON files, registry credentials, or real external API keys.
