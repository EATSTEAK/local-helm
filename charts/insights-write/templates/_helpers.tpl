{{- define "insights-write.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "insights-write.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}
{{- end }}

{{- define "insights-write.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end }}

{{- define "insights-write.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "insights-write.labels" -}}
helm.sh/chart: {{ include "insights-write.chart" . }}
{{ include "insights-write.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "insights-write.selectorLabels" -}}
app.kubernetes.io/name: {{ include "insights-write.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
