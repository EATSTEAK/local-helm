set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

profile := "default"
colima_config := "config/colima/default.yaml"
chart := "charts/cloudflare-kube-tunnel"
release := "cloudflare-kube-tunnel"
namespace := "default"

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
    helm dependency update {{chart}}

helm-lint: helm-deps
    helm lint {{chart}}

cluster-install: helm-deps
    helm upgrade --install {{release}} ./{{chart}} --namespace {{namespace}}

cluster-uninstall:
    helm uninstall {{release}} --namespace {{namespace}} --ignore-not-found

package:
    ./scripts/package.sh

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
    kubectl rollout status deploy/whoami -n default
    kubectl rollout status deploy/canvas -n default
    kubectl rollout status deploy/triflam-bot -n triflam-bot
    kubectl get deploy,svc,ingress,pvc -n default
    kubectl get deploy,svc,cm,pvc -n triflam-bot
