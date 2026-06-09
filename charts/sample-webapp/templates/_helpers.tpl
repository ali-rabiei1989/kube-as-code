{{- define "sample-webapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sample-webapp.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "sample-webapp.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sample-webapp.labels" -}}
app.kubernetes.io/name: {{ include "sample-webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "sample-webapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sample-webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
