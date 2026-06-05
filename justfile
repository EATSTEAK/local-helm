set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

profile := "default"
colima_config := "config/colima/values.yaml"
cloudflare_chart := "charts/cloudflare-kube-tunnel"
cloudflare_chart_values := "infrastructure/colima/controllers/cloudflare-tunnel/values.yaml"
release := "cloudflare-tunnel"
namespace := "cloudflare-tunnel"

default:
    @just --list

colima-apply-config:
    install -d "$HOME/.colima/{{profile}}"
    cp {{colima_config}} "$HOME/.colima/{{profile}}/colima.yaml"

colima-start: colima-apply-config
    colima start --profile {{profile}}

colima-stop:
    colima stop --profile {{profile}}

colima-restart: colima-apply-config
    colima stop --profile {{profile}}
    colima start --profile {{profile}}

colima-status:
    colima status --profile {{profile}}
    colima list

cluster-install:
    helm dependency update {{cloudflare_chart}}
    helm upgrade --install {{release}} ./{{cloudflare_chart}} --namespace {{namespace}} --create-namespace -f {{cloudflare_chart_values}}

cluster-uninstall:
    helm uninstall {{release}} --namespace {{namespace}} --ignore-not-found

flux-status:
    flux get sources git -A
    flux get sources helm -A
    flux get kustomizations -A
    flux get helmreleases -A

flux-reconcile:
    flux reconcile source git flux-system -n flux-system
    flux reconcile kustomization infrastructure -n flux-system
    flux reconcile kustomization apps -n flux-system
