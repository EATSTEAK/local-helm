#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
task_dir="$(mktemp -d "${TMPDIR:-/tmp}/phoenix-validate.XXXXXX")"
# Only this script's mktemp output (never a workspace or home directory) is removed.
trap 'ruby -rfileutils -e '\''p = ARGV.fetch(0); abort unless File.basename(p).match?(/\Aphoenix-validate\.[A-Za-z0-9]+\z/); FileUtils.remove_entry_secure(p)'\'' "$task_dir"' EXIT

if [[ -z "${PHOENIX_CHART_PATH:-}" ]]; then
    digest="$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).dig("spec", "ref", "digest")' infrastructure/colima/sources/phoenix.yaml)"
    helm pull "oci://registry-1.docker.io/arizephoenix/phoenix-helm@${digest}" \
        --untar --untardir "$task_dir"
    export PHOENIX_CHART_PATH="$task_dir/phoenix-helm"
fi

helm lint charts/shared-postgres -f apps/colima/shared-postgres/values.yaml
helm lint "$PHOENIX_CHART_PATH" -f apps/colima/phoenix/values.yaml
bash -n scripts/phoenix-secrets.sh
ruby tests/phoenix_test.rb
