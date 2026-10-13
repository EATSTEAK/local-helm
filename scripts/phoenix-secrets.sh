#!/usr/bin/env bash
# Create credentials outside Git; existing credentials are validated, never rotated.
set -euo pipefail

context="${KUBE_CONTEXT:-colima}"
kube=(kubectl --context "$context" --namespace default)

ensure_secret() {
    local name="$1"
    shift
    if [[ -n "$("${kube[@]}" get secret "$name" --ignore-not-found -o name)" ]]; then
        "${kube[@]}" get secret "$name" -o json |
            ruby -rjson -rbase64 -e '
                data = JSON.parse(STDIN.read).fetch("data", {})
                ARGV.each do |key|
                    value = Base64.strict_decode64(data.fetch(key, ""))
                    abort "Existing Secret is missing/invalid: #{key}" if value.length < 32
                    if key == "PHOENIX_SECRET"
                        abort "Existing signing secret must contain a lowercase letter and digit" unless
                            value.match?(/[a-z]/) && value.match?(/[0-9]/)
                    end
                    if key == "PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD"
                        abort "Existing admin password does not meet the strong policy" unless
                            value.match?(/[a-z]/) && value.match?(/[A-Z]/) &&
                            value.match?(/[0-9]/) && value.match?(/[^a-zA-Z0-9]/)
                    end
                end
            ' "$@"
        printf 'Reusing default/%s; values were not printed or changed.\n' "$name"
        return
    fi

    ruby -rjson -rbase64 -rsecurerandom -e '
        name = ARGV.shift
        data = ARGV.to_h do |key|
            value = SecureRandom.hex(32) + "aA1!"
            [key, Base64.strict_encode64(value)]
        end
        puts JSON.generate({apiVersion: "v1", kind: "Secret", type: "Opaque",
            metadata: {name: name, namespace: "default"}, data: data})
    ' "$name" "$@" | "${kube[@]}" create -f -
}

printf 'Preparing credentials on context %s (namespace default).\n' "$context"
ensure_secret shared-postgres-auth POSTGRES_PASSWORD
ensure_secret phoenix-secret PHOENIX_SECRET PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD PHOENIX_POSTGRES_PASSWORD
printf 'Credentials ready. Back them up securely before the first deployment.\n'
