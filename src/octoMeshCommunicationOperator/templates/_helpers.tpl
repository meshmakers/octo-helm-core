{{/*
Expand the name of the chart.
*/}}
{{- define "octoMeshCommunicationOperator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "octoMeshCommunicationOperator.fullname" -}}
    {{- if .Values.fullnameOverride }}
        {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
    {{- else }}
        {{- $name := default "communication-operator" .Values.nameOverride  }}
        {{- printf "%s-%s" .Release.Name $name | lower | trunc 63 | trimSuffix "-" | lower }}
    {{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "octoMeshCommunicationOperator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "octoMeshCommunicationOperator.labels" -}}
helm.sh/chart: {{ include "octoMeshCommunicationOperator.chart" . }}
{{ include "octoMeshCommunicationOperator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "octoMeshCommunicationOperator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "octoMeshCommunicationOperator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "octoMeshCommunicationOperator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "octoMeshCommunicationOperator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Check if a mandadory value exists
*/}}
{{- define "checkMandatoryValue" -}}
{{- if not .value -}}
{{- fail (printf "Value %s does not exist. Please define a corresponding value." .name) -}}
{{- end -}}
{{- end -}}