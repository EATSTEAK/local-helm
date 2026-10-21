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
| Phoenix | `default` | `rise.koohyom.in` | [`apps/colima/phoenix/README.md`](apps/colima/phoenix/README.md) |
| Sake | `sake` | `sake.koohyom.in`, `studio-sake.koohyom.in` | [`apps/colima/sake/README.md`](apps/colima/sake/README.md) |
| Shared PostgreSQL | `default` | Internal service only | [`apps/colima/shared-postgres/README.md`](apps/colima/shared-postgres/README.md) |

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

The profile now targets 4 CPU / 12GiB RAM / 100GiB disk. A Git merge does not
resize the running VM: run `just colima-restart` during a maintenance window.
Prepare the runtime Secrets before merging the Phoenix/shared PostgreSQL
overlays; see the [Phoenix rollout checklist](apps/colima/phoenix/README.md).

### Automatic local image cleanup

The Colima profile provisions a kubelet drop-in at
`/var/lib/rancher/k3s/agent/etc/kubelet.conf.d/10-image-gc.conf` with
`imageMaximumGCAge: 24h`. This uses K3s >= 1.32's drop-in support and preserves
its other kubelet defaults.

- Kubelet checks for unused images about every five minutes, independently of
  Flux reconciliation. Images unused for 24 hours become eligible for deletion.
- Disk-based GC remains at its defaults: start above 85% usage and try to reduce
  usage to 80%. It can remove unused images sooner; 24 hours is not a minimum
  retention guarantee. Restarting kubelet resets its image-age tracking.
- GC targets local images in this Colima runtime, not GHCR images, Docker build
  cache, volumes or PVCs. It is not restricted to Flux-managed applications.
  In-use images are protected by kubelet/runtime checks; images for scaled-down
  workloads or rollback may need to be pulled again. Keep those images available
  in the registry and ensure pull credentials are valid.
- No pruning command is added to `just flux-reconcile`: reconciling manifests
  does not guarantee every application's rollout has finished.

Apply only during an approved maintenance window (this restarts the local
cluster):

```sh
just colima-restart
```

Merging Git changes or running Flux reconciliation does not apply the Colima
profile. After restarting, check the **effective** kubelet configuration for the
default profile/node, rather than only the drop-in file:

```sh
kubectl --context colima get --raw /api/v1/nodes/colima/proxy/configz \
  | ruby -rjson -e '
      keys = %w[imageMaximumGCAge imageGCHighThresholdPercent imageGCLowThresholdPercent]
      puts JSON.parse(STDIN.read).fetch("kubeletconfig").slice(*keys).to_json
    '
```

Expect `24h0m0s`, `85`, and `80`. Later drop-ins or CLI overrides can change the
effective values. Confirm node/workload health and compare local image usage
before/after a GC window; the test below does not exercise live garbage collection.

To disable age-based cleanup, change `imageMaximumGCAge` to `0s` in
`config/colima/values.yaml` and repeat the maintenance-window restart. Disk-based
GC remains enabled. Simply removing the provisioning block does not remove the
already-written drop-in from the VM; deleted images must be pulled again.

Validate provisioning locally without starting a VM or deleting images:

```sh
ruby tests/colima_gc_test.rb
```

See [Kubernetes image garbage collection](https://kubernetes.io/docs/concepts/architecture/garbage-collection/#containers-images)
and [K3s kubelet configuration](https://docs.k3s.io/installation/configuration#kubelet-configuration-files).

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
