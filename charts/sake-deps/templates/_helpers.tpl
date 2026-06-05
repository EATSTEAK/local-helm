{{- define "sake-deps.appName" -}}
{{- default "sake" .Values.appName | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-deps.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end }}

{{- define "sake-deps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-deps.labels" -}}
helm.sh/chart: {{ include "sake-deps.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "sake-deps.postgresName" -}}
{{- printf "%s-postgres" (include "sake-deps.appName" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-deps.redisName" -}}
{{- printf "%s-redis" (include "sake-deps.appName" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-deps.minioName" -}}
{{- printf "%s-minio" (include "sake-deps.appName" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "sake-deps.crawl4aiName" -}}
{{- printf "%s-crawl4ai" (include "sake-deps.appName" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
