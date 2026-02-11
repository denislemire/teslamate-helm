{{/*
Expand the name of the chart.
*/}}
{{- define "teslamate.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "teslamate.fullname" -}}
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
Common labels
*/}}
{{- define "teslamate.labels" -}}
helm.sh/chart: {{ include "teslamate.chart" . }}
{{ include "teslamate.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "teslamate.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "teslamate.selectorLabels" -}}
app.kubernetes.io/name: {{ include "teslamate.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Database (postgres) component labels and selector
*/}}
{{- define "teslamate.database.labels" -}}
app.kubernetes.io/component: database
{{ include "teslamate.labels" . }}
{{- end }}

{{- define "teslamate.database.selectorLabels" -}}
app: teslamate-db
{{ include "teslamate.selectorLabels" . }}
{{- end }}

{{/*
TeslaMate app component labels
*/}}
{{- define "teslamate.app.labels" -}}
app.kubernetes.io/component: teslamate
{{ include "teslamate.labels" . }}
{{- end }}

{{- define "teslamate.app.selectorLabels" -}}
app: teslamate
{{ include "teslamate.selectorLabels" . }}
{{- end }}

{{/*
Grafana component labels
*/}}
{{- define "teslamate.grafana.labels" -}}
app.kubernetes.io/component: grafana
{{ include "teslamate.labels" . }}
{{- end }}

{{- define "teslamate.grafana.selectorLabels" -}}
app: teslamate-grafana
{{ include "teslamate.selectorLabels" . }}
{{- end }}

{{/*
Mosquitto component labels
*/}}
{{- define "teslamate.mosquitto.labels" -}}
app.kubernetes.io/component: mosquitto
{{ include "teslamate.labels" . }}
{{- end }}

{{- define "teslamate.mosquitto.selectorLabels" -}}
app: mosquitto
{{ include "teslamate.selectorLabels" . }}
{{- end }}

{{/*
TeslaMate API component labels
*/}}
{{- define "teslamate.api.labels" -}}
app.kubernetes.io/component: teslamateapi
{{ include "teslamate.labels" . }}
{{- end }}

{{- define "teslamate.api.selectorLabels" -}}
app: teslamateapi
{{ include "teslamate.selectorLabels" . }}
{{- end }}

{{/*
Postgres service host (for use in env vars)
*/}}
{{- define "teslamate.databaseHost" -}}
{{- printf "postgres.%s.svc.cluster.local" .Release.Namespace }}
{{- end }}

{{/*
Mosquitto service host
*/}}
{{- define "teslamate.mosquittoHost" -}}
{{- printf "mosquitto.%s.svc.cluster.local" .Release.Namespace }}
{{- end }}

{{/*
TeslaMate service host (for API config)
*/}}
{{- define "teslamate.teslamateHost" -}}
{{- printf "teslamate.%s.svc.cluster.local" .Release.Namespace }}
{{- end }}
