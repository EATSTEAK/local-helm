#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${ROOT_DIR}/charts/cloudflare-kube-tunnel"
PACKAGE_DIR="${ROOT_DIR}/packages"

helm dependency update "${CHART_DIR}"
helm lint "${CHART_DIR}"
helm package "${CHART_DIR}" --destination "${PACKAGE_DIR}"
helm repo index "${ROOT_DIR}" --url "file://${ROOT_DIR}"
