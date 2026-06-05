set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

profile := "default"
colima_config := "config/colima/values.yaml"
cloudflare_chart := "charts/cloudflare-kube-tunnel"
cloudflare_chart_values := "infrastructure/colima/controllers/cloudflare-tunnel/values.yaml"
canvas_chart := "charts/canvas"
canvas_chart_values := "apps/colima/canvas/values.yaml"
flamres_chart := "charts/flamres"
flamres_chart_values := "apps/colima/flamres/values.yaml"
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

helm-deps:
    helm dependency update {{cloudflare_chart}}

helm-lint: helm-deps
    helm lint {{cloudflare_chart}}
    helm lint {{cloudflare_chart}} -f {{cloudflare_chart_values}}
    helm lint {{canvas_chart}} -f {{canvas_chart_values}}
    helm lint {{flamres_chart}} -f {{flamres_chart_values}}

cluster-install: helm-deps
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

cluster-inventory:
    kubectl get pods -A
    kubectl get ingress -A
    kubectl get pvc -A
    helm list -A

apps-status:
    kubectl rollout status deploy/canvas -n default
    kubectl rollout status deploy/flamres -n flamres
    kubectl get deploy,svc,ingress,pvc -n default
    kubectl get deploy,svc,cm,pvc -n flamres
