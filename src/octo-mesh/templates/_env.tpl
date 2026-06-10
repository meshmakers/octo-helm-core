{{- define "octo-mesh.system-env" -}}
- name: OCTO_SYSTEM__SYSTEMDATABASENAME
  value: {{ .global.Values.serviceDefaults.systemDatabaseName }}
- name: OCTO_SYSTEM__DATABASEHOST
  value: {{ .global.Values.clusterDependencies.mongodbHost }}
{{- if .global.Values.clusterDependencies.mongodbReplicaSet }}
- name: OCTO_SYSTEM__REPLICASETNAME
  value: {{ .global.Values.clusterDependencies.mongodbReplicaSet }}
{{- end }}
- name: OCTO_SYSTEM__DATABASEUSERPASSWORD
  valueFrom:
    secretKeyRef:
        name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
        key: databaseUser
- name: OCTO_SYSTEM__ADMINUSERPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: databaseAdmin          
{{- end }}

{{- define "octo-mesh.broker-env" -}}
- name: {{ printf "%s__BROKERHOST" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.rabbitMqHost }}
- name: {{ printf "%s__BROKERUSER" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.rabbitMqUser }}
- name: {{ printf "%s__BROKERPASSWORD" (upper .name) }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: rabbitmq     
{{- end }}

{{- define "octo-mesh.blueprints-env" -}}
# Variables surfaced to the blueprint runner via IBlueprintVariableProvider.
# - ${octo.version}: chart appVersion → blueprints can pin Mesh-Adapter ChartVersion
#                    etc. to the current release without manual bumps.
# - ${octo.environment}: dev/test/staging/production gate for `requires:` blocks.
# - ${octo.systemTenantId}: kept in sync with serviceDefaults.systemDatabaseName so
#                          ${octo.isSystemTenant} matches the runtime's system tenant.
- name: OCTO_BLUEPRINTS__OCTOVERSION
  value: {{ .global.Chart.AppVersion | quote }}
- name: OCTO_BLUEPRINTS__ENVIRONMENT
  value: {{ .global.Values.serviceDefaults.environment | quote }}
- name: OCTO_BLUEPRINTS__SYSTEMTENANTID
  value: {{ .global.Values.serviceDefaults.systemDatabaseName | quote }}
{{- end }}

{{- define "octo-mesh.streamdata-env" -}}
# Instance-level kill switch for StreamData. Read by
# StreamDataInstanceConfiguration (root "StreamData" config section, hence
# the fixed env-var name without a service prefix). Defaults to false so
# the feature is opt-in per cluster.
- name: OCTO_STREAMDATA__ENABLED
  value: {{ .global.Values.clusterDependencies.streamDataEnabled | quote }}
- name: {{ printf "%s__STREAMDATAHOST" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.streamDataHost }}
- name: {{ printf "%s__STREAMDATAUSER" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.streamDataUser }}
- name: {{ printf "%s__STREAMDATAPASSWORD" (upper .name) }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: streamDataPassword
{{- end }}


{{- define "octo-mesh.env" -}}
- name: ASPNETCORE_URLS
  value: "http://+:80"
{{- if eq .name "identity" -}}
{{- $name := "OCTO_IDENTITY" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
- name: OCTO_IDENTITY__KeyFilePath
  value: "/etc/octo-identity/IdentityServer4Auth.pfx"
- name: OCTO_IDENTITY__KEYFILEPASSWORD
  valueFrom:
    secretKeyRef:
        name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
        key: identityKeyFile
- name: OCTO_IDENTITY__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_IDENTITY__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
- name: OCTO_IDENTITY__IdentityServerLicenseKey
  value: {{ .global.Values.services.identity.identityServerLicenseKey }}
- name: OCTO_IDENTITY__AutoMapperLicenseKey
  value: {{ .global.Values.services.identity.autoMapperLicenseKey }}
{{- if .global.Values.services.studio.publicUri }}
- name: OCTO_IDENTITY__RefineryStudioUrl
  value: {{ .global.Values.services.studio.publicUri }}
{{- end }}
{{- else if eq .name "assetRepository" -}}
{{- $name := "OCTO_ASSETREPOSITORY" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
{{ include "octo-mesh.streamdata-env" (dict "global" .global "name" $name) }}
{{ include "octo-mesh.blueprints-env" . }}
- name: OCTO_ASSETREPOSITORY__AUTHORITY
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_ASSETREPOSITORY__PUBLICURL
  value: {{ .global.Values.services.assetRepository.publicUri }}
- name: OCTO_ASSETREPOSITORY__PUBLICADMINPANELURL
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: OCTO_ASSETREPOSITORY__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
{{- with .global.Values.services.assetRepository.ckCatalog }}
- name: OCTO_LocalFileSystemCatalog__IsEnabled
  value: "{{ .localFileSystemEnabled }}"
- name: OCTO_PrivateOctoGitHub__IsEnabled
  value: "{{ .privateGitHubEnabled }}"
{{- end }}

{{- else if eq .name "bot" -}}
{{- $name := "OCTO_BOT" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}  
- name: OCTO_BOT__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_BOT__PUBLICURL
  value: {{ .global.Values.services.bot.publicUri }}
- name: OCTO_BOT__PUBLICADMINPANELURL
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: OCTO_BOT__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}

{{- else if eq .name "communication" -}}
{{- $name := "OCTO_COMMUNICATIONCONTROLLER" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
{{ include "octo-mesh.blueprints-env" . }}
- name: OCTO_COMMUNICATIONCONTROLLER__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_COMMUNICATIONCONTROLLER__PUBLICURL
  value: {{ .global.Values.services.communication.publicUri }}
- name: OCTO_COMMUNICATIONCONTROLLER__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
{{- /*
AES-256-GCM master key for IWorkloadEncryptionService. Emitted only when
secrets.communicationInstanceSecretKey is set so unconfigured clusters
keep starting (CommunicationControllerOptions doc: empty is tolerated at
startup, every encrypt/decrypt call then throws a clear config error).
Provisioned per cluster via Vault — see octo-mesh-deployment/docs/VAULT-SETUP.md.
*/}}
{{- if .global.Values.secrets.communicationInstanceSecretKey }}
- name: OCTO_COMMUNICATIONCONTROLLER__INSTANCESECRETKEY
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: communicationInstanceSecretKey
{{- end }}
{{- /*
Named public base domains. Each entry in services.communication.domains is
projected as OCTO_COMMUNICATIONCONTROLLER__DOMAINS__<KEY>; .NET configuration
binding turns it back into a Dictionary<string,string> on
CommunicationControllerOptions.Domains. KEY is uppercased so the rendered env
var matches the .NET binding convention; the resolver itself is
case-insensitive on lookup so blueprint authors can still write
{{domain.default}} in lowercase.
*/}}
{{- range $key, $value := .global.Values.services.communication.domains }}
- name: OCTO_COMMUNICATIONCONTROLLER__DOMAINS__{{ upper $key }}
  value: {{ $value | quote }}
{{- end }}
{{- /*
Named public service URIs surfaced as {{service.NAME}} placeholders in
workload Hostname / ValueOverride.Value / ValuesYaml. The semantic key
"authority" maps to the Identity Service publicUri; other keys mirror the
helm-section name. .NET configuration binding turns OCTO_…__SERVICEURLS__<KEY>
back into a Dictionary<string,string> on CommunicationControllerOptions.ServiceUrls.
Lookup is case-insensitive so blueprint authors can write {{service.authority}}
in lowercase regardless of env-var casing.
*/}}
- name: OCTO_COMMUNICATIONCONTROLLER__SERVICEURLS__AUTHORITY
  value: {{ .global.Values.services.identity.publicUri | quote }}
- name: OCTO_COMMUNICATIONCONTROLLER__SERVICEURLS__ASSETREPOSITORY
  value: {{ .global.Values.services.assetRepository.publicUri | quote }}
- name: OCTO_COMMUNICATIONCONTROLLER__SERVICEURLS__BOT
  value: {{ .global.Values.services.bot.publicUri | quote }}
- name: OCTO_COMMUNICATIONCONTROLLER__SERVICEURLS__COMMUNICATION
  value: {{ .global.Values.services.communication.publicUri | quote }}
- name: OCTO_COMMUNICATIONCONTROLLER__SERVICEURLS__ADMINPANEL
  value: {{ .global.Values.services.adminPanel.publicUri | quote }}
{{- if .global.Values.services.studio.publicUri }}
- name: OCTO_COMMUNICATIONCONTROLLER__SERVICEURLS__STUDIO
  value: {{ .global.Values.services.studio.publicUri | quote }}
{{- end }}
{{- else if eq .name "adminPanel" -}}
{{- $name := "OCTO_ADMINPANEL" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
{{ include "octo-mesh.blueprints-env" . }}
- name: OCTO_ADMINPANEL__CRATEDBADMINURL
  value: {{ .global.Values.externalUris.crateDb }}
- name: OCTO_ADMINPANEL__GRAFANAURL
  value: {{ .global.Values.externalUris.grafana }}
- name: OCTO_ADMINPANEL__MESHADAPTERURL
  value: {{ .global.Values.externalUris.meshAdapter }}
- name: OCTO_ADMINPANEL__AISERVICESURL
  value: {{ .global.Values.services.aiServices.publicUri }}
- name: OCTO_ADMINPANEL__ASSETSERVICEURL
  value: {{ .global.Values.services.assetRepository.publicUri }}
- name: OCTO_ADMINPANEL__BOTSERVICEURL
  value: {{ .global.Values.services.bot.publicUri }}
- name: OCTO_ADMINPANEL__COMMUNICATIONSERVICEURL
  value: {{ .global.Values.services.communication.publicUri }}      
- name: OCTO_ADMINPANEL__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_ADMINPANEL__PUBLICURL
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: OCTO_ADMINPANEL__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
{{- else if eq .name "studio" -}}
{{- $name := "OCTO_REFINERY_STUDIO" }}
- name: ADMIN_PANEL_URI
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: APP_URI
  value: {{ .global.Values.services.studio.publicUri }}
{{- else if eq .name "aiServices" -}}
{{- $name := "OCTO_AISERVICES" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
{{ include "octo-mesh.blueprints-env" . }}
- name: OCTO_AISERVICES__AUTHORITY
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_AISERVICES__PUBLICURL
  value: {{ .global.Values.services.aiServices.publicUri }}
{{- else }}
{{- fail (printf "Service %s is not configured for the octo-mesh helm chart." .name) -}}
{{- end }}
{{- end }}