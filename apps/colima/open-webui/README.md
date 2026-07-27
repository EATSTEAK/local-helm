# Open WebUI

Open WebUI is deployed to the local Colima cluster with the upstream `open-webui` Helm chart.

| Field | Value |
| --- | --- |
| Namespace | `open-webui` |
| Release | `open-webui` |
| Public host | `chat.koohyom.in` |
| Chart | `open-webui` from `https://helm.openwebui.com` |
| Data | chart-managed `local-path` PVC `open-webui` |

## Runtime Secret

The bootstrap Secret is managed outside Git and must exist before the first Open WebUI pod starts. It prevents the public first-admin registration race.

Required Secret:

- Namespace: `open-webui`
- Name: `open-webui-bootstrap`
- Keys:
  - `WEBUI_ADMIN_EMAIL`
  - `WEBUI_ADMIN_PASSWORD`
  - `WEBUI_ADMIN_NAME`
  - `WEBUI_SECRET_KEY`

Create or refresh it with generated credentials:

```sh
kubectl create namespace open-webui --dry-run=client -o yaml | kubectl apply -f -

ADMIN_EMAIL='admin@koohyom.in'
ADMIN_NAME='Admin'
ADMIN_PASSWORD="$(python3 - <<'PY'
import secrets,string
alphabet=string.ascii_letters+string.digits+'-_'
print(''.join(secrets.choice(alphabet) for _ in range(28)))
PY
)"
WEBUI_SECRET_KEY="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)"

kubectl create secret generic open-webui-bootstrap \
  --namespace open-webui \
  --from-literal=WEBUI_ADMIN_EMAIL="$ADMIN_EMAIL" \
  --from-literal=WEBUI_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  --from-literal=WEBUI_ADMIN_NAME="$ADMIN_NAME" \
  --from-literal=WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

printf '%s' "$ADMIN_PASSWORD" | pbcopy
```

The final command copies the generated admin password to the macOS clipboard without printing it.

## Verification

```sh
kubectl get helmrelease -n open-webui open-webui
kubectl get pods,svc,pvc,ingress -n open-webui
curl -I https://chat.koohyom.in/
```

The app is intentionally deployed without in-cluster Ollama or Pipelines. Configure model providers later from the Open WebUI admin UI or by adding Secret-backed values.
