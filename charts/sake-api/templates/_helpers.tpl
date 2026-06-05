{{- define "sake-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-api.fullname" -}}
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

{{- define "sake-api.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end }}

{{- define "sake-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-api.labels" -}}
helm.sh/chart: {{ include "sake-api.chart" . }}
{{ include "sake-api.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "sake-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sake-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
