{{- define "cloudflare-kube-tunnel.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "cloudflare-kube-tunnel.sampleLabels" -}}
app.kubernetes.io/name: {{ .Values.sample.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
