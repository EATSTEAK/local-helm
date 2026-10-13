{{- define "shared-postgres.labels" -}}
app.kubernetes.io/name: shared-postgres
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "shared-postgres.image" -}}
{{ printf "%s@%s" .Values.image.repository (required "image.digest is required" .Values.image.digest) }}
{{- end -}}
