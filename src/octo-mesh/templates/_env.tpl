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
# - ${octo.scheme}/${octo.domain}: per-cluster URL composition inputs for
#   ${octo.scheme}://<slug>.${octo.domain} (e.g. ${octo.mcp.publicUrl} in the
#   System.Identity.Bootstrap seed). Explicit serviceDefaults.scheme/.domain win;
#   otherwise both are derived from services.identity.publicUri (scheme verbatim,
#   domain = host minus its first label: https://connect.test-2.mm.cloud →
#   test-2.mm.cloud). Leaving them empty seeds half-composed URLs ("/") into
#   blueprint-managed entities — the AB#4338 invalid_target failure on test-2.
{{- $identityUrl := urlParse (default "" .global.Values.services.identity.publicUri) }}
{{- $derivedDomain := "" }}
{{- if $identityUrl.host }}
{{- $derivedDomain = (splitList "." $identityUrl.host) | rest | join "." }}
{{- end }}
- name: OCTO_BLUEPRINTS__OCTOVERSION
  value: {{ .global.Chart.AppVersion | quote }}
- name: OCTO_BLUEPRINTS__ENVIRONMENT
  value: {{ .global.Values.serviceDefaults.environment | quote }}
- name: OCTO_BLUEPRINTS__SYSTEMTENANTID
  value: {{ .global.Values.serviceDefaults.systemDatabaseName | quote }}
- name: OCTO_BLUEPRINTS__SCHEME
  value: {{ .global.Values.serviceDefaults.scheme | default ($identityUrl.scheme | default "https") | quote }}
- name: OCTO_BLUEPRINTS__DOMAIN
  value: {{ .global.Values.serviceDefaults.domain | default $derivedDomain | quote }}
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
{{ include "octo-mesh.blueprints-env" . }}
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
{{ include "octo-mesh.streamdata-env" (dict "global" .global "name" $name) }}
- name: OCTO_BOT__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_BOT__PUBLICURL
  value: {{ .global.Values.services.bot.publicUri }}
{{- if .global.Values.services.studio.publicUri }}
- name: OCTO_BOT__PUBLICREFINERYSTUDIOURL
  value: {{ .global.Values.services.studio.publicUri }}
{{- end }}
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
{{- if .global.Values.services.studio.publicUri }}
- name: OCTO_COMMUNICATIONCONTROLLER__SERVICEURLS__STUDIO
  value: {{ .global.Values.services.studio.publicUri | quote }}
{{- end }}
{{- else if eq .name "platformServices" -}}
{{- $name := "OCTO_PLATFORMSERVICES" }}
{{- /*
Phase 4 of the platform-services initiative — platform-services now OWNS the
System.UI CK model + the System.UI.* / System.TenantMode service-managed
blueprints (moved from admin-panel). It therefore needs three pieces of env
(it used to need only MongoDB for the Phase-2 observability API):
  - system-env (MongoDB): observability API + blueprint apply.
  - broker-env: it runs the distribution-event-hub tenant-lifecycle host
    (PosCreateTenant / PosUpdateTenant) to seed the blueprints on tenant
    create / attach / restore. Its UniqueServiceAddress is "PlatformServices",
    distinct from admin-panel's, so the exclusive queues never collide while
    both are deployed during the sunset window.
  - blueprints-env: ${octo.environment(Mode)} / ${octo.isSystemTenant} drive
    the cockpit `requires:` gates and the TenantMode seed.
*/}}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
{{ include "octo-mesh.blueprints-env" . }}
- name: OCTO_PLATFORMSERVICES__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
- name: OCTO_PLATFORMSERVICES__CRATEDBADMINURL
  value: {{ .global.Values.externalUris.crateDb }}
- name: OCTO_PLATFORMSERVICES__GRAFANAURL
  value: {{ .global.Values.externalUris.grafana }}
- name: OCTO_PLATFORMSERVICES__MESHADAPTERURL
  value: {{ .global.Values.externalUris.meshAdapter }}
- name: OCTO_PLATFORMSERVICES__AISERVICESURL
  value: {{ .global.Values.services.aiServices.publicUri }}
- name: OCTO_PLATFORMSERVICES__ASSETSERVICEURL
  value: {{ .global.Values.services.assetRepository.publicUri }}
- name: OCTO_PLATFORMSERVICES__BOTSERVICEURL
  value: {{ .global.Values.services.bot.publicUri }}
- name: OCTO_PLATFORMSERVICES__COMMUNICATIONSERVICEURL
  value: {{ .global.Values.services.communication.publicUri }}
{{- /*
McpServiceUrl feeds the `mcpServices` _configuration field (Studio's
Development→Swagger→McpServices link). The MCP service ships in its own
chart, so the core value tree has no services.mcp block — an explicit
externalUris.mcp wins, otherwise the URL is composed as
<scheme>://mcp.<domain> with the same scheme/domain resolution as
blueprints-env, matching ${octo.mcp.publicUrl} and the mcp.<domain> host
convention on all clusters.
*/}}
{{- $mcpIdentityUrl := urlParse (default "" .global.Values.services.identity.publicUri) }}
{{- $mcpDerivedDomain := "" }}
{{- if $mcpIdentityUrl.host }}
{{- $mcpDerivedDomain = (splitList "." $mcpIdentityUrl.host) | rest | join "." }}
{{- end }}
{{- $mcpScheme := .global.Values.serviceDefaults.scheme | default ($mcpIdentityUrl.scheme | default "https") }}
{{- $mcpDomain := .global.Values.serviceDefaults.domain | default $mcpDerivedDomain }}
{{- $mcpUrl := .global.Values.externalUris.mcp | default (ternary (printf "%s://mcp.%s" $mcpScheme $mcpDomain) "" (ne $mcpDomain "")) }}
{{- if $mcpUrl }}
- name: OCTO_PLATFORMSERVICES__MCPSERVICEURL
  value: {{ $mcpUrl | quote }}
{{- end }}
{{- /*
ReportingServiceUrl is intentionally NOT wired here: octo-report-services
lives in helm-pro (octo-mesh-reporting chart) and is not part of the core
chart's value tree. Matches the legacy admin-panel behaviour where the
`reportingServices` DTO field was never overridden from helm either (no
external consumer reads it today). Operators who want a real value can set
OCTO_PLATFORMSERVICES__REPORTINGSERVICEURL via podAnnotations / a
PodExtra-style override; the field stays in the DTO for backwards
compatibility.
*/}}
- name: OCTO_PLATFORMSERVICES__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
{{- /*
ADMINPANELURL is no longer wired: Phase 4 dropped the redirectUri /
postLogoutRedirectUri fields (and the AdminPanelUrl option) from the
_configuration DTO, so platform-services no longer needs the admin-panel URL.
*/}}
{{- /*
SYSTEMTENANTID is intentionally NOT sourced from serviceDefaults.systemDatabaseName
here: the DB name is PascalCase ("OctoSystem") but external consumers
(Refinery Studio, Office, PowerBI) read this field as the lowercase
tenant-id path segment (e.g. /octosystem/_configuration) — the URL is
case-sensitive in the ASP.NET routing on the consumer side. The legacy
admin-panel never overrode this from helm either; both services rely on
the lowercase "octosystem" appsettings default.
*/}}

{{- else if eq .name "studio" -}}
{{- $name := "OCTO_REFINERY_STUDIO" }}
{{- /*
The studio Docker entrypoint templates BOTH `platformUri` (new) and `adminUri`
(legacy) into /assets/config.json from the env vars below. The configuration
loader (AppConfigurationService) prefers `platformUri`; `adminUri` is kept only
so studio builds / Office add-ins / PowerBI connectors baked against the old
field name keep resolving. Both now point at platform-services — admin-panel was
retired in Phase 4, so there is no admin-panel fallback any more.
*/}}
{{- $configEndpointUri := .global.Values.services.platformServices.publicUri }}
- name: PLATFORM_URI
  value: {{ $configEndpointUri }}
- name: ADMIN_PANEL_URI
  value: {{ $configEndpointUri }}
- name: APP_URI
  value: {{ .global.Values.services.studio.publicUri }}
{{- /*
Dash0 OpenTelemetry (browser RUM). Per-environment opt-in: only emitted when an
endpoint is configured, so environments without Dash0 activated get no DASH0_*
vars and the studio's telemetry init stays a no-op. The entrypoint templates
these into /assets/config.json; the auth token is a secret (secretKeyRef), the
endpoint/dataset/environment are non-secret plain values.
*/}}
{{- if .global.Values.services.studio.dash0.endpoint }}
- name: DASH0_ENDPOINT
  value: {{ .global.Values.services.studio.dash0.endpoint | quote }}
- name: DASH0_DATASET
  value: {{ .global.Values.services.studio.dash0.dataset | default "" | quote }}
- name: DASH0_ENVIRONMENT
  value: {{ .global.Values.services.studio.dash0.environment | default "" | quote }}
- name: DASH0_AUTH_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: dash0WebAuthToken
{{- end }}
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