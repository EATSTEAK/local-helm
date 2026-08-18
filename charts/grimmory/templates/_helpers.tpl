{{- define "grimmory.labels" -}}
app.kubernetes.io/name: grimmory
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
