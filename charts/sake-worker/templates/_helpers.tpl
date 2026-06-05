{{- define "sake-worker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-worker.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "sake-worker.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end }}

{{- define "sake-worker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-worker.labels" -}}
helm.sh/chart: {{ include "sake-worker.chart" . }}
{{ include "sake-worker.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "sake-worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sake-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
