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

{{/*
Webhook TLS material — resolves the CA + service certificate pair once per
Helm render and caches it on the root scope ($._webhookCerts) so that
secret.yaml, mutators.yaml and validators.yaml all reference the SAME
material in a single render.

Resolution order:
  1. Use values.serviceHooks.{caKey,caCrt,svcKey,svcCrt} if ALL four are
     provided. Lets operators override with externally-issued certs.
  2. Otherwise `lookup` the existing -webhook-ca and -webhook-cert Secrets.
     Reusing them on upgrade keeps the CA stable so the kube-apiserver's
     cached webhook-CA bundle stays valid across releases.
  3. As a last resort (fresh install), `genCA` + `genSignedCert` produce
     a self-signed pair valid for 10 years.

Returns nothing directly — callers read `index $ "_webhookCerts"` after
the include.
*/}}
{{- define "octoMeshCommunicationOperator.webhookCerts" -}}
{{- if not (hasKey $ "_webhookCerts") -}}
  {{- $caKey  := .Values.serviceHooks.caKey  -}}
  {{- $caCrt  := .Values.serviceHooks.caCrt  -}}
  {{- $svcKey := .Values.serviceHooks.svcKey -}}
  {{- $svcCrt := .Values.serviceHooks.svcCrt -}}
  {{- if not (and $caKey $caCrt $svcKey $svcCrt) -}}
    {{- $svcName := include "octoMeshCommunicationOperator.fullname" . -}}
    {{- $ns      := .Release.Namespace -}}
    {{- $caSecret   := (lookup "v1" "Secret" $ns (printf "%s-webhook-ca"   $svcName)) -}}
    {{- $certSecret := (lookup "v1" "Secret" $ns (printf "%s-webhook-cert" $svcName)) -}}
    {{- if and $caSecret $certSecret -}}
      {{- $caKey  = index $caSecret.data   "ca-key.pem"  | b64dec -}}
      {{- $caCrt  = index $caSecret.data   "ca.pem"      | b64dec -}}
      {{- $svcKey = index $certSecret.data "svc-key.pem" | b64dec -}}
      {{- $svcCrt = index $certSecret.data "svc.pem"     | b64dec -}}
    {{- else -}}
      {{- $altNames := list
            $svcName
            (printf "%s.%s"                  $svcName $ns)
            (printf "%s.%s.svc"              $svcName $ns)
            (printf "%s.%s.svc.cluster.local" $svcName $ns) -}}
      {{- $ca   := genCA (printf "%s-ca" $svcName) 3650 -}}
      {{- $cert := genSignedCert $svcName nil $altNames 3650 $ca -}}
      {{- $caKey  = $ca.Key -}}
      {{- $caCrt  = $ca.Cert -}}
      {{- $svcKey = $cert.Key -}}
      {{- $svcCrt = $cert.Cert -}}
    {{- end -}}
  {{- end -}}
  {{- $_ := set $ "_webhookCerts" (dict "caKey" $caKey "caCrt" $caCrt "svcKey" $svcKey "svcCrt" $svcCrt) -}}
{{- end -}}
{{- end -}}