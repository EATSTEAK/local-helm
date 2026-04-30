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
