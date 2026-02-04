{{/*
Expand the name of the chart.
*/}}
{{- define "istio-sticky-session.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "istio-sticky-session.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "istio-sticky-session.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "istio-sticky-session.labels" -}}
helm.sh/chart: {{ include "istio-sticky-session.chart" . }}
{{ include "istio-sticky-session.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "istio-sticky-session.selectorLabels" -}}
app.kubernetes.io/name: {{ include "istio-sticky-session.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: sticky-session-app
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "istio-sticky-session.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "istio-sticky-session.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

