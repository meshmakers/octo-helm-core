{{/*
Expand the name of the chart.
*/}}
{{- define "octo-mesh.name" -}}
{{- default .Chart.Name | trunc 63 | trimSuffix "-" | lower }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "octo-mesh.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create a default fully qualified app name of a service
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "octo-mesh.service-fullname" -}}
    {{- if .svc.fullnameOverride }}
        {{- .svc.fullnameOverride | trunc 63 | trimSuffix "-" }}
    {{- else }}
        {{- $name := default .name .svc.nameOverride  }}
        {{- printf "%s-%s" .global.Release.Name $name | trunc 63 | trimSuffix "-" | lower }}
    {{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "octo-mesh.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "octo-mesh.labels" -}}
helm.sh/chart: {{ include "octo-mesh.chart" . }}
{{ include "octo-mesh.selectorLabels" .  }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "octo-mesh.selectorLabels" -}}
app.kubernetes.io/name: {{ include "octo-mesh.name" . }}
app.kubernetes.io/instance: {{ include "octo-mesh.fullname" . }}
{{- end }}


{{/*
Common labels service related
*/}}
{{- define "octo-mesh.service-labels" -}}
{{ include "octo-mesh.service-selectorLabels" (dict "global" .global "name" .name "svc" .svc)  }}
{{- end }}

{{/*
Selector labels service related
*/}}
{{- define "octo-mesh.service-selectorLabels" -}}
{{ include "octo-mesh.selectorLabels" .global }}
app.kubernetes.io/service: {{ include "octo-mesh.service-fullname" (dict "global" .global "name" .name "svc" .svc)  }}
{{- end }}

{{/*
Check if a file exists in the `files` directory. If not, return an error.
*/}}
{{- define "checkFileExists" -}}
{{- if not (index .global.Files .file) -}}
{{- fail (printf "File %s does not exist. Please add the file to the correspondings directory." .file) -}}
{{- end -}}
{{- end -}}

{{/*
Check if a mandadory value exists
*/}}
{{- define "checkMandatoryValue" -}}
{{- if not .value -}}
{{- fail (printf "Value %s does not exist. Please define a corresponding value." .name) -}}
{{- end -}}
{{- end -}}
{{/*
SECRET attribute key ring (AB#5536, concept AB#5528 §3.5, decision 3).

Returns the effective key ring as JSON — read it with
`fromJson (include "octo-mesh.secretEncryption" <root>)`:
  { "keys": {kid: base64Key}, "activeKeyId": "k1", "legacyV1Key": base64Key }

Default (no override map): the existing instance secret
(secrets.communicationInstanceSecretKey) IS key `k1` and the legacy `enc:v1`
key, and `k1` is active. No new required value — a cluster without an
instance secret gets an empty ring and the chart emits nothing.

Rotation override: a non-empty secrets.secretEncryptionKeys REPLACES the
derived ring, so a rotation lists every key that must still decrypt
(k1 = the instance secret again, plus k2) and sets
secrets.secretEncryptionActiveKeyId. LegacyV1Key always stays the instance
secret, because that is the key every existing `enc:v1:` value was written
with — it is dropped only by removing the instance secret itself, once a
sweep has proven no `enc:v1` value remains.

Key ids are restricted to lowercase letters and digits: the id becomes part
of an environment variable name, a Secret key and the `enc:v2:<kid>:`
envelope header, and the env var keeps its case (OCTO_SECRETENCRYPTION__KEYS__k1)
so the configuration key matches the id the engine writes.
*/}}
{{- define "octo-mesh.secretEncryption" -}}
{{- $s := .Values.secrets -}}
{{- $instanceKey := $s.communicationInstanceSecretKey | default "" -}}
{{- $keys := dict -}}
{{- $override := $s.secretEncryptionKeys | default dict -}}
{{- if $override -}}
{{- range $kid, $value := $override -}}
{{- if not (regexMatch "^[a-z0-9]{1,32}$" $kid) -}}
{{- fail (printf "secrets.secretEncryptionKeys: key id '%s' must be 1-32 lowercase letters or digits" $kid) -}}
{{- end -}}
{{- if not $value -}}
{{- fail (printf "secrets.secretEncryptionKeys.%s is empty; remove the entry instead" $kid) -}}
{{- end -}}
{{- if ne (len (b64dec $value)) 32 -}}
{{- fail (printf "secrets.secretEncryptionKeys.%s must be a base64-encoded 32-byte key (openssl rand -base64 32)" $kid) -}}
{{- end -}}
{{- $_ := set $keys $kid $value -}}
{{- end -}}
{{- else if $instanceKey -}}
{{- $_ := set $keys "k1" $instanceKey -}}
{{- end -}}
{{- $active := "" -}}
{{- if $keys -}}
{{- $active = $s.secretEncryptionActiveKeyId | default "k1" -}}
{{- if not (hasKey $keys $active) -}}
{{- fail (printf "secrets.secretEncryptionActiveKeyId '%s' is not a key id of the SECRET key ring (%s)" $active (keys $keys | sortAlpha | join ", ")) -}}
{{- end -}}
{{- end -}}
{{- toJson (dict "keys" $keys "activeKeyId" $active "legacyV1Key" $instanceKey) -}}
{{- end -}}

{{/*
AB#5560 service account name of a service. Empty when the service neither creates nor names an account,
so the pod spec keeps the namespace default and renders as before.
*/}}
{{- define "octo-mesh.service-serviceAccountName" -}}
{{- $sa := .svc.serviceAccount | default dict }}
{{- if $sa.create }}
{{- $sa.name | default (include "octo-mesh.service-fullname" .) }}
{{- else }}
{{- $sa.name | default "" }}
{{- end }}
{{- end }}

{{/*
AB#5560 name of the claim backing services.<svc>.persistence.
*/}}
{{- define "octo-mesh.service-persistenceClaimName" -}}
{{- .svc.persistence.existingClaim | default (printf "%s-data" (include "octo-mesh.service-fullname" .)) }}
{{- end }}

{{/*
AB#5560 effective artifact-store provider of the bot: the explicit value, otherwise FileSystem when the
bot has a PVC, otherwise "" (no OCTO_ARTIFACTSTORAGE__* at all, the bot keeps its built-in defaults).
*/}}
{{- define "octo-mesh.bot-artifactProvider" -}}
{{- $store := .svc.artifactStorage | default dict }}
{{- $persistence := .svc.persistence | default dict }}
{{- if $store.provider }}
{{- $store.provider }}
{{- else if $persistence.enabled }}
{{- "FileSystem" }}
{{- end }}
{{- end }}

{{/*
AB#5560 bot storage env: pre-sweep backup path on the PVC and OCTO_ARTIFACTSTORAGE__* (config section
ArtifactStorage, octo-common-services AB#5561). Credentials only as secretKeyRef into an existing Secret.
Renders nothing with the defaults.
*/}}
{{- define "octo-mesh.bot-storage-env" -}}
{{- $svc := .svc }}
{{- $persistence := $svc.persistence | default dict }}
{{- $store := $svc.artifactStorage | default dict }}
{{- $provider := include "octo-mesh.bot-artifactProvider" . }}
{{- if $persistence.enabled }}
- name: OCTO_BOT__SECRETSWEEP__BACKUPSTORAGEPATH
  value: {{ printf "%s/secret-backups" (trimSuffix "/" $persistence.mountPath) | quote }}
{{- end }}
{{- if $provider }}
- name: OCTO_ARTIFACTSTORAGE__PROVIDER
  value: {{ $provider | quote }}
- name: OCTO_ARTIFACTSTORAGE__INSTANCEPREFIX
  value: {{ $store.instancePrefix | default .global.Release.Name | quote }}
{{- if eq $provider "FileSystem" }}
{{- $fs := $store.fileSystem | default dict }}
{{- if and (not $fs.rootPath) (not $persistence.enabled) }}
{{- fail "services.bot.artifactStorage.provider=FileSystem needs services.bot.persistence.enabled=true or services.bot.artifactStorage.fileSystem.rootPath (on a volume you mount via pod.volumes)." }}
{{- end }}
- name: OCTO_ARTIFACTSTORAGE__FILESYSTEM__ROOTPATH
  value: {{ $fs.rootPath | default (printf "%s/artifacts" (trimSuffix "/" $persistence.mountPath)) | quote }}
{{- else if eq $provider "S3" }}
{{- $s3 := $store.s3 | default dict }}
{{- include "checkMandatoryValue" (dict "name" "services.bot.artifactStorage.s3.bucket" "value" $s3.bucket) }}
{{- with $s3.serviceUrl }}
- name: OCTO_ARTIFACTSTORAGE__S3__SERVICEURL
  value: {{ . | quote }}
{{- end }}
{{- with $s3.region }}
- name: OCTO_ARTIFACTSTORAGE__S3__REGION
  value: {{ . | quote }}
{{- end }}
- name: OCTO_ARTIFACTSTORAGE__S3__BUCKET
  value: {{ $s3.bucket | quote }}
- name: OCTO_ARTIFACTSTORAGE__S3__FORCEPATHSTYLE
  value: {{ $s3.forcePathStyle | default false | quote }}
{{- with $s3.serverSideEncryption }}
- name: OCTO_ARTIFACTSTORAGE__S3__SERVERSIDEENCRYPTION
  value: {{ . | quote }}
{{- end }}
{{- if $s3.existingSecret }}
- name: OCTO_ARTIFACTSTORAGE__S3__ACCESSKEYID
  valueFrom:
    secretKeyRef:
      name: {{ $s3.existingSecret | quote }}
      key: {{ $s3.accessKeyIdKey | default "accessKeyId" | quote }}
- name: OCTO_ARTIFACTSTORAGE__S3__SECRETACCESSKEY
  valueFrom:
    secretKeyRef:
      name: {{ $s3.existingSecret | quote }}
      key: {{ $s3.secretAccessKeyKey | default "secretAccessKey" | quote }}
{{- end }}
{{- else if eq $provider "AzureBlob" }}
{{- $az := $store.azureBlob | default dict }}
{{- include "checkMandatoryValue" (dict "name" "services.bot.artifactStorage.azureBlob.container" "value" $az.container) }}
{{- if and $az.connectionStringKey $az.accountKeyKey }}
{{- fail "services.bot.artifactStorage.azureBlob: set either connectionStringKey or accountKeyKey, not both." }}
{{- end }}
{{- if and (or $az.connectionStringKey $az.accountKeyKey) (not $az.existingSecret) }}
{{- fail "services.bot.artifactStorage.azureBlob.connectionStringKey/accountKeyKey need azureBlob.existingSecret." }}
{{- end }}
{{- if and $az.existingSecret (not (or $az.connectionStringKey $az.accountKeyKey)) }}
{{- fail "services.bot.artifactStorage.azureBlob.existingSecret needs connectionStringKey or accountKeyKey." }}
{{- end }}
{{- if not (or $az.useManagedIdentity $az.existingSecret) }}
{{- fail "services.bot.artifactStorage.azureBlob needs useManagedIdentity=true or existingSecret with connectionStringKey/accountKeyKey." }}
{{- end }}
{{- if and (or $az.useManagedIdentity $az.accountKeyKey) (not $az.accountUrl) }}
{{- fail "services.bot.artifactStorage.azureBlob.accountUrl is required with useManagedIdentity or accountKeyKey." }}
{{- end }}
{{- if and $az.useManagedIdentity (not (include "octo-mesh.service-serviceAccountName" .)) }}
{{- fail "services.bot.artifactStorage.azureBlob.useManagedIdentity needs services.bot.serviceAccount.create=true or serviceAccount.name (federated with the workload identity)." }}
{{- end }}
{{- with $az.accountUrl }}
- name: OCTO_ARTIFACTSTORAGE__AZUREBLOB__ACCOUNTURL
  value: {{ . | quote }}
{{- end }}
- name: OCTO_ARTIFACTSTORAGE__AZUREBLOB__CONTAINER
  value: {{ $az.container | quote }}
- name: OCTO_ARTIFACTSTORAGE__AZUREBLOB__USEMANAGEDIDENTITY
  value: {{ $az.useManagedIdentity | default false | quote }}
{{- if $az.connectionStringKey }}
- name: OCTO_ARTIFACTSTORAGE__AZUREBLOB__CONNECTIONSTRING
  valueFrom:
    secretKeyRef:
      name: {{ $az.existingSecret | quote }}
      key: {{ $az.connectionStringKey | quote }}
{{- else if $az.accountKeyKey }}
- name: OCTO_ARTIFACTSTORAGE__AZUREBLOB__ACCOUNTKEY
  valueFrom:
    secretKeyRef:
      name: {{ $az.existingSecret | quote }}
      key: {{ $az.accountKeyKey | quote }}
{{- end }}
{{- else }}
{{- fail (printf "services.bot.artifactStorage.provider must be FileSystem, S3 or AzureBlob (got %q)." $provider) }}
{{- end }}
{{- end }}
{{- end }}
