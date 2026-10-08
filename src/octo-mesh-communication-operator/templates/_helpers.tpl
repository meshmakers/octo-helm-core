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
{{/*
SECRET attribute key ring for operator-deployed workloads (AB#5536, concept
AB#5528 §3.5). Same derivation as the octo-mesh chart's
"octo-mesh.secretEncryption" helper — keep the two in step:

  default:  { k1: clusterSecrets.instanceSecretKey }, active k1
  override: a non-empty clusterSecrets.secretEncryptionKeys REPLACES the ring
            (rotation), clusterSecrets.secretEncryptionActiveKeyId picks the
            active key (default k1)
  legacy:   LegacyV1Key is always clusterSecrets.instanceSecretKey

instanceSecretKey must be the same value as the core chart's
secrets.communicationInstanceSecretKey (Vault `instance_secret_key`).
Returns JSON: { "keys": {...}, "activeKeyId": "...", "legacyV1Key": "..." }.
*/}}
{{- define "octoMeshCommunicationOperator.secretEncryption" -}}
{{- $cs := .Values.operator.clusterSecrets -}}
{{- $instanceKey := $cs.instanceSecretKey | default "" -}}
{{- $keys := dict -}}
{{- $override := $cs.secretEncryptionKeys | default dict -}}
{{- if $override -}}
{{- range $kid, $value := $override -}}
{{- if not (regexMatch "^[a-z0-9]{1,32}$" $kid) -}}
{{- fail (printf "operator.clusterSecrets.secretEncryptionKeys: key id '%s' must be 1-32 lowercase letters or digits" $kid) -}}
{{- end -}}
{{- if not $value -}}
{{- fail (printf "operator.clusterSecrets.secretEncryptionKeys.%s is empty; remove the entry instead" $kid) -}}
{{- end -}}
{{- if ne (len (b64dec $value)) 32 -}}
{{- fail (printf "operator.clusterSecrets.secretEncryptionKeys.%s must be a base64-encoded 32-byte key (openssl rand -base64 32)" $kid) -}}
{{- end -}}
{{- $_ := set $keys $kid $value -}}
{{- end -}}
{{- else if $instanceKey -}}
{{- $_ := set $keys "k1" $instanceKey -}}
{{- end -}}
{{- $active := "" -}}
{{- if $keys -}}
{{- $active = $cs.secretEncryptionActiveKeyId | default "k1" -}}
{{- if not (hasKey $keys $active) -}}
{{- fail (printf "operator.clusterSecrets.secretEncryptionActiveKeyId '%s' is not a key id of the SECRET key ring (%s)" $active (keys $keys | sortAlpha | join ", ")) -}}
{{- end -}}
{{- end -}}
{{- toJson (dict "keys" $keys "activeKeyId" $active "legacyV1Key" $instanceKey) -}}
{{- end -}}

{{/*
AB#5528 phase 3 / AB#5062 — operator client-credentials configuration.
Returns JSON: {"enabled": bool, "chartOwned": bool, "secretName", "clientIdKey",
"clientSecretKey", "issuerUri", "tenantId"}. Validates the combination and fails the
render on a half-configured or ambiguous setup, because a silently dropped credential
degrades to an anonymous hub connection that looks healthy until Enforce is armed.
*/}}
{{- define "octoMeshCommunicationOperator.authentication" -}}
{{- $a := .Values.operator.authentication | default dict -}}
{{- $clientId := $a.clientId | default "" | trim -}}
{{- $clientSecret := $a.clientSecret | default "" -}}
{{- $existing := $a.existingSecret | default "" | trim -}}
{{- $result := dict "enabled" false "chartOwned" false -}}
{{- if and $existing (or $clientId $clientSecret) -}}
{{- fail "operator.authentication: set either existingSecret or clientId/clientSecret, not both" -}}
{{- end -}}
{{- if and $clientSecret (not $clientId) -}}
{{- fail "operator.authentication.clientSecret is set but clientId is empty" -}}
{{- end -}}
{{- if and $clientId (not $clientSecret) -}}
{{- fail "operator.authentication.clientId is set but clientSecret is empty (the operator client is confidential; use existingSecret to supply both from a Secret)" -}}
{{- end -}}
{{- if or $clientId $existing -}}
{{- $issuer := $a.issuerUri | default .Values.operator.authUri | default "" -}}
{{- if not $issuer -}}
{{- fail "operator.authentication is configured but neither operator.authentication.issuerUri nor operator.authUri is set" -}}
{{- end -}}
{{- if not ($a.tenantId | default "" | trim) -}}
{{- fail "operator.authentication.tenantId is required when operator credentials are configured (normally the system tenant, e.g. octosystem)" -}}
{{- end -}}
{{- $_ := set $result "enabled" true -}}
{{- $_ := set $result "issuerUri" $issuer -}}
{{- $_ := set $result "tenantId" $a.tenantId -}}
{{- if $existing -}}
{{- $_ := set $result "secretName" $existing -}}
{{- $_ := set $result "clientIdKey" ($a.existingSecretClientIdKey | default "clientId") -}}
{{- $_ := set $result "clientSecretKey" ($a.existingSecretClientSecretKey | default "clientSecret") -}}
{{- else -}}
{{- $_ := set $result "chartOwned" true -}}
{{- $_ := set $result "secretName" (printf "%s-operator-auth" (include "octoMeshCommunicationOperator.fullname" .)) -}}
{{- $_ := set $result "clientIdKey" "client-id" -}}
{{- $_ := set $result "clientSecretKey" "client-secret" -}}
{{- end -}}
{{- end -}}
{{- toJson $result -}}
{{- end -}}
