{{- define "sake-studio.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-studio.fullname" -}}
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

{{- define "sake-studio.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end }}

{{- define "sake-studio.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-studio.labels" -}}
helm.sh/chart: {{ include "sake-studio.chart" . }}
{{ include "sake-studio.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "sake-studio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sake-studio.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
