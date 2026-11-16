{{- define "octo-mesh.system-env" -}}
- name: OCTO_SYSTEM__SYSTEMDATABASENAME
  value: {{ .global.Values.serviceDefaults.systemDatabaseName }}
- name: OCTO_SYSTEM__DATABASEHOST
  value: {{ .global.Values.clusterDependencies.mongodbHost }}
{{- if .global.Values.clusterDependencies.mongodbReplicaSet }}
- name: OCTO_SYSTEM__REPLICASETNAME
  value: {{ .global.Values.clusterDependencies.mongodbReplicaSet }}
{{- end }}
{{- if .global.Values.clusterDependencies.tenantDatabasePrefix }}
# MongoDB tenant-database prefix (AB#8797, Epic AB#4944): a second OctoMesh instance on the
# same MongoDB names new tenant databases <prefix><tenantId> and refuses explicit names
# without the prefix. Emitted only when set - existing instances keep their names.
- name: OCTO_SYSTEM__TENANTDATABASEPREFIX
  value: {{ .global.Values.clusterDependencies.tenantDatabasePrefix | quote }}
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
{{- /*
SECRET attribute key ring (AB#5536). Part of system-env so EVERY engine host in
this chart gets it — the engine binds SecretEncryption:* in AddRuntimeEngine().
Values live in the backend Secret; see "octo-mesh.secretEncryption" in
_helpers.tpl for how the ring is derived from the instance secret.
*/}}
{{- $fullname := include "octo-mesh.fullname" .global }}
{{- $ring := fromJson (include "octo-mesh.secretEncryption" .global) }}
{{- range $kid, $_ := $ring.keys }}
- name: OCTO_SECRETENCRYPTION__KEYS__{{ $kid }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" $fullname }}
      key: {{ printf "secretEncryptionKey-%s" $kid }}
{{- end }}
{{- if $ring.keys }}
- name: OCTO_SECRETENCRYPTION__ACTIVEKEYID
  value: {{ $ring.activeKeyId | quote }}
{{- end }}
{{- if $ring.legacyV1Key }}
- name: OCTO_SECRETENCRYPTION__LEGACYV1KEY
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" $fullname }}
      key: communicationInstanceSecretKey
{{- end }}
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
{{- if .global.Values.clusterDependencies.streamDataSchemaInstancePrefix }}
# CrateDB schema instance prefix (AB#4946, Epic AB#4944): a second OctoMesh instance sharing
# the cluster's CrateDB names its tenant schemas {prefix}_{tenantId}. Same root "StreamData"
# section as the kill switch above, so the env-var name is fixed across services. Emitted only
# when set — existing instances keep their un-prefixed schemas.
- name: OCTO_STREAMDATA__SCHEMAINSTANCEPREFIX
  value: {{ .global.Values.clusterDependencies.streamDataSchemaInstancePrefix | quote }}
{{- end }}
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
{{- /* AB#5868: optional internal-only Prometheus listener, see values observability.prometheusPort */}}
{{- $promPort := int (.global.Values.observability.prometheusPort | default 0) }}
- name: ASPNETCORE_URLS
  value: {{ if gt $promPort 0 }}"http://+:80;http://+:{{ $promPort }}"{{ else }}"http://+:80"{{ end }}
{{- if gt $promPort 0 }}
- name: Observability__PrometheusPort
  value: {{ $promPort | quote }}
{{- end }}
# Distinct OpenTelemetry service.name per workload. Without this the Dash0
# auto-instrumentation derives service.name from the app.kubernetes.io/name
# label, which is identical ("octo-mesh") for every service in this release —
# so all services collapse into a single node in the Dash0 service map. The
# injector honours an explicit OTEL_SERVICE_NAME over that label default
# (verified on test-2). Value matches the app.kubernetes.io/service label.
- name: OTEL_SERVICE_NAME
  value: {{ include "octo-mesh.service-fullname" (dict "global" .global "name" .name "svc" .svc) | quote }}
# Our own ActivitySources, declared to the injected .NET auto-instrumentation.
# The services also subscribe to these in Meshmakers.Octo.Services.Observability,
# which is what makes the Activities exist at all — but that in-process
# TracerProvider deliberately has no exporter in the cluster (a second exporter
# would duplicate every HTTP span the injector already sends). Naming the
# sources here is what gets the spans OUT, through the injector's provider.
# Harmless on a service that never emits on them: an unknown source name costs
# one idle listener.
#
# MongoDB.Driver (3.x native tracing, one CLIENT span per command) is added
# when tracing.mongoDb is on, so a slow request shows its database calls
# instead of a childless server span (AB#6307). Switchable per cluster because
# it multiplies the span volume of database-heavy services.
- name: OTEL_DOTNET_AUTO_TRACES_ADDITIONAL_SOURCES
  value: "Meshmakers.Octo.StreamData,Meshmakers.Octo.StreamData.Crate{{ if .global.Values.tracing.mongoDb }},MongoDB.Driver{{ end }}"
{{- /*
  AB#5478 section 2.3: nlog.config takes the log level from the environment
  instead of having it pinned in the repository. Both are omitted unless set, and
  nlog.config then falls back to Info. See values.yaml for why a one-off
  investigation is better served by DiagnosticsService than by these.
*/}}
{{- if .global.Values.logLevel }}
- name: OCTO_LOG_LEVEL
  value: {{ .global.Values.logLevel | quote }}
{{- end }}
{{- if .global.Values.logLevelRoot }}
- name: OCTO_LOG_LEVEL_ROOT
  value: {{ .global.Values.logLevelRoot | quote }}
{{- end }}
{{- /*
  AB#8415: dates of the REST deprecation waves ([OctoRestDeprecated(Wave = …)], octo-common-services
  docs/rest-deprecation.md). Rendered for every service: a service only reads the waves its endpoints name.
  An unset date renders nothing (the service then sends no Deprecation / Sunset header for that wave).
*/}}
{{- $restDeprecation := .global.Values.restDeprecation | default dict }}
{{- range $wave, $dates := ($restDeprecation.waves | default dict) }}
{{- if not (regexMatch "^[A-Za-z][A-Za-z0-9]*$" $wave) }}
{{- fail (printf "restDeprecation.waves: wave name '%s' must consist of letters and digits and start with a letter" $wave) }}
{{- end }}
{{- range $key, $name := (dict "since" "Since" "sunset" "Sunset") }}
{{- $value := toString (index ($dates | default dict) $key | default "") }}
{{- if $value }}
{{- if not (regexMatch "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" $value) }}
{{- fail (printf "restDeprecation.waves.%s.%s must be a date yyyy-MM-dd, got '%s'" $wave $key $value) }}
{{- end }}
- name: {{ printf "OCTO_RestDeprecation__Waves__%s__%s" $wave $name }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- include "octo-mesh.tenant-generation-enforcement-env" . }}
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
{{- /* AB#5859 role check on the tenant REST API; Warn is the emergency exit. */}}
{{- $roleEnforcement := .global.Values.services.identity.apiRoleEnforcement | default "Enforce" }}
{{- if not (has $roleEnforcement (list "Enforce" "Warn")) }}
{{- fail (printf "services.identity.apiRoleEnforcement must be Enforce or Warn, got '%s'" $roleEnforcement) }}
{{- end }}
- name: OCTO_IDENTITYAPIAUTHORIZATION__ROLEENFORCEMENT
  value: {{ $roleEnforcement | quote }}
{{- /* AB#5861 staged SecretManagement role on the API secret writes. Rendered only when set:
unset keeps the service default (Warn). Any other value fails the render. */}}
{{- $secretMgmt := .global.Values.services.identity.secretManagementRoleEnforcement }}
{{- if not (or (kindIs "invalid" $secretMgmt) (and (kindIs "string" $secretMgmt) (eq $secretMgmt ""))) }}
{{- if not (and (kindIs "string" $secretMgmt) (has $secretMgmt (list "Warn" "Enforce"))) }}
{{- fail (printf "services.identity.secretManagementRoleEnforcement must be Warn or Enforce, got '%v'" $secretMgmt) }}
{{- end }}
- name: OCTO_IDENTITYAPIAUTHORIZATION__SECRETMANAGEMENTROLEENFORCEMENT
  value: {{ $secretMgmt | quote }}
{{- end }}
{{- /* AB#8165 migration of existing tenant admins from direct roles to TenantOwners membership.
Rendered only when set: unset keeps the service default (Off). Any other value fails the render. */}}
{{- $adminMigration := .global.Values.services.identity.adminRoleMigration }}
{{- if not (or (kindIs "invalid" $adminMigration) (and (kindIs "string" $adminMigration) (eq $adminMigration ""))) }}
{{- if not (and (kindIs "string" $adminMigration) (has $adminMigration (list "Off" "DryRun" "Apply"))) }}
{{- fail (printf "services.identity.adminRoleMigration must be Off, DryRun or Apply, got '%v'" $adminMigration) }}
{{- end }}
- name: OCTO_IDENTITYAPIAUTHORIZATION__ADMINROLEMIGRATION
  value: {{ $adminMigration | quote }}
{{- end }}
{{- /* AB#8305 cleanup of rights-less xt_ shadow users. Rendered only when set: unset keeps the service
default (Off). Any other value fails the render. */}}
{{- $shadowCleanup := .global.Values.services.identity.shadowUserCleanup }}
{{- if not (or (kindIs "invalid" $shadowCleanup) (and (kindIs "string" $shadowCleanup) (eq $shadowCleanup ""))) }}
{{- if not (and (kindIs "string" $shadowCleanup) (has $shadowCleanup (list "Off" "DryRun" "Apply"))) }}
{{- fail (printf "services.identity.shadowUserCleanup must be Off, DryRun or Apply, got '%v'" $shadowCleanup) }}
{{- end }}
- name: OCTO_IDENTITYAPIAUTHORIZATION__SHADOWUSERCLEANUP
  value: {{ $shadowCleanup | quote }}
{{- end }}
{{- /* AB#8339 cross-tenant ancestry from the tenant registry. Rendered only when set: unset keeps the
service default (Warn). Any other value fails the render. */}}
{{- $ancestry := .global.Values.services.identity.crossTenantAncestry }}
{{- if not (or (kindIs "invalid" $ancestry) (and (kindIs "string" $ancestry) (eq $ancestry ""))) }}
{{- if not (and (kindIs "string" $ancestry) (has $ancestry (list "Warn" "Enforce"))) }}
{{- fail (printf "services.identity.crossTenantAncestry must be Warn or Enforce, got '%v'" $ancestry) }}
{{- end }}
- name: OCTO_IDENTITYAPIAUTHORIZATION__CROSSTENANTANCESTRY
  value: {{ $ancestry | quote }}
{{- end }}
{{- /* AB#9017 (AB#9000): identity's own API runs the tenant check of TenantAuthorizationMiddleware on bearer tokens
from octo-identity-services #305 on. Both modes are rendered explicitly (chart default LogOnly) so the mode in effect is
visible on the deployment; the service's code default would be Enforce. */}}
{{ include "octo-mesh.user-token-enforcement-env" (dict "key" "services.identity.userTokenEnforcement" "mode" .global.Values.services.identity.userTokenEnforcement) }}
{{ include "octo-mesh.service-token-enforcement-env" (dict "key" "services.identity.serviceTokenEnforcement" "mode" .global.Values.services.identity.serviceTokenEnforcement) }}
{{- /* AB#5530 encryption at rest of the Data Protection key ring. Rendered only when set (true or
false): unset keeps the service default (false). A non-boolean value fails the render. */}}
{{- $dataProtection := .global.Values.services.identity.dataProtection | default dict }}
{{- if and (hasKey $dataProtection "encryptExistingKeys") (not (kindIs "invalid" $dataProtection.encryptExistingKeys)) }}
{{- if not (kindIs "bool" $dataProtection.encryptExistingKeys) }}
{{- fail (printf "services.identity.dataProtection.encryptExistingKeys must be true or false, got '%v'" $dataProtection.encryptExistingKeys) }}
{{- end }}
- name: OCTO_IDENTITY__DATAPROTECTION__ENCRYPTEXISTINGKEYS
  value: {{ $dataProtection.encryptExistingKeys | quote }}
{{- end }}
{{- /* AB#8603 identity password methods on the bus. Rendered only when set (true or false): unset keeps
the service default (false). A non-boolean value fails the render. */}}
{{- $identityMethods := .global.Values.services.identity.methods | default dict }}
{{- if and (hasKey $identityMethods "enablePasswordMethods") (not (kindIs "invalid" $identityMethods.enablePasswordMethods)) }}
{{- if not (kindIs "bool" $identityMethods.enablePasswordMethods) }}
{{- fail (printf "services.identity.methods.enablePasswordMethods must be true or false, got '%v'" $identityMethods.enablePasswordMethods) }}
{{- end }}
- name: OCTO_Methods__Identity__EnablePasswordMethods
  value: {{ $identityMethods.enablePasswordMethods | quote }}
{{- end }}
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
{{ include "octo-mesh.user-token-enforcement-env" (dict "key" "services.assetRepository.userTokenEnforcement" "mode" .global.Values.services.assetRepository.userTokenEnforcement) }}
{{ include "octo-mesh.stream-data-read-enforcement-env" (dict "mode" .global.Values.services.assetRepository.streamDataReadEnforcement) }}
{{ include "octo-mesh.mutation-scope-env" (dict "enforce" .global.Values.services.assetRepository.enforceMutationScope) }}
- name: OCTO_ASSETREPOSITORY__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
{{- /* AB#8280 CK method idempotency fingerprint key. Id (plain) and secret (secretKeyRef) are rendered
together or not at all; the pairing and format checks run in "octo-mesh.methodsFingerprint". */}}
{{- if (include "octo-mesh.methodsFingerprint" .global) }}
- name: OCTO_METHODS__IDEMPOTENCY__FINGERPRINT__CURRENT__ID
  value: {{ include "octo-mesh.methodsFingerprint" .global | quote }}
- name: OCTO_METHODS__IDEMPOTENCY__FINGERPRINT__CURRENT__SECRET
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: methodsFingerprintCurrentSecret
{{- end }}
{{- /*
AB#5139 lane-scoped catalogs. The private CK catalog
(PrivateOctoGitHub) and the private blueprint catalog
(PrivateOctoGitHubBlueprints) both default in the engine to the shared
main-lane repositories (construction-kit-libraries-build /
blueprint-libraries-build, branch main). A pre-release instance that runs
next to a main-lane instance therefore installs main-lane content. The
repository coordinates below let ONE installation redirect its private
catalogs at a lane-private repository.

Every coordinate is emitted ONLY when the value is non-empty: an empty
value is "keep the engine default", and an emitted-but-empty variable
would OVERRIDE that default with nothing (a catalog pointed at owner ""/
repo "" fails to refresh). So guard with `with` on each individual value
— never with `default`, which would materialise a value.

AB#6112: the GitHub blueprint catalogs have an IsEnabled switch since
engine AB#6112 (GitHubBlueprintCatalogOptions.IsEnabled, engine default
true). blueprintCatalog.privateGitHubEnabled is tri-state: empty keeps the
engine default (no env var), true/false is emitted explicitly. A plain
`with` cannot be used here because it skips `false`. Production sets it to
false so only released (public) blueprints are offered. Older engines
ignore the variable (it binds to nothing).
*/}}
{{- with .global.Values.services.assetRepository.ckCatalog }}
- name: OCTO_LocalFileSystemCatalog__IsEnabled
  value: "{{ .localFileSystemEnabled }}"
- name: OCTO_PrivateOctoGitHub__IsEnabled
  value: "{{ .privateGitHubEnabled }}"
{{- with .privateGitHub }}
{{- with .repositoryOwner }}
- name: OCTO_PrivateOctoGitHub__GitHubRepositoryOwner
  value: {{ . | quote }}
{{- end }}
{{- with .repositoryName }}
- name: OCTO_PrivateOctoGitHub__GitHubRepositoryName
  value: {{ . | quote }}
{{- end }}
{{- with .repositoryBranch }}
- name: OCTO_PrivateOctoGitHub__GitHubRepositoryBranch
  value: {{ . | quote }}
{{- end }}
{{- with .pagesUri }}
- name: OCTO_PrivateOctoGitHub__GitHubPagesUri
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- with .global.Values.services.assetRepository.blueprintCatalog }}
{{- if ne (toString .privateGitHubEnabled) "" }}
- name: OCTO_PrivateOctoGitHubBlueprints__IsEnabled
  value: "{{ .privateGitHubEnabled }}"
{{- end }}
{{- with .privateGitHub }}
{{- with .repositoryOwner }}
- name: OCTO_PrivateOctoGitHubBlueprints__GitHubRepositoryOwner
  value: {{ . | quote }}
{{- end }}
{{- with .repositoryName }}
- name: OCTO_PrivateOctoGitHubBlueprints__GitHubRepositoryName
  value: {{ . | quote }}
{{- end }}
{{- with .repositoryBranch }}
- name: OCTO_PrivateOctoGitHubBlueprints__GitHubRepositoryBranch
  value: {{ . | quote }}
{{- end }}
{{- with .pagesUri }}
- name: OCTO_PrivateOctoGitHubBlueprints__GitHubPagesUri
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- /*
AB#6174 file API limits (section "Files"). Numbers go through int64 so large
byte counts never render in float notation (1.048576e+08).
*/}}
{{- with .global.Values.services.assetRepository.files }}
- name: OCTO_Files__MaxUploadBytes
  value: {{ .maxUploadBytes | int64 | quote }}
- name: OCTO_Files__ZipMaxFiles
  value: {{ .zipMaxFiles | int64 | quote }}
- name: OCTO_Files__ZipMaxBytes
  value: {{ .zipMaxBytes | int64 | quote }}
- name: OCTO_Files__PreviewMaxBytes
  value: {{ .previewMaxBytes | int64 | quote }}
{{- end }}
{{- /*
AB#8897 server-side time limit of runtime-entity queries (section "RuntimeQuery"). A whole number of
milliseconds from 0 (off) to 2147483647; anything else fails the render. Unset or null renders nothing: the service
default (120000) applies.
*/}}
{{- with .global.Values.services.assetRepository.runtimeQuery }}
{{- $maxTimeMs := .maxTimeMs }}
{{- /* Helm 3.18.0 loads chart values as json.Number (a string kind); convert it, text still fails below. */}}
{{- if eq (typeOf $maxTimeMs) "json.Number" }}
{{- $maxTimeMs = float64 $maxTimeMs }}
{{- end }}
{{- if not (kindIs "invalid" $maxTimeMs) }}
{{- if not (or (kindIs "float64" $maxTimeMs) (kindIs "int64" $maxTimeMs) (kindIs "int" $maxTimeMs)) }}
{{- fail (printf "services.assetRepository.runtimeQuery.maxTimeMs must be a whole number of milliseconds from 0 (off) to 2147483647, got '%v'" $maxTimeMs) }}
{{- end }}
{{- if or (lt (float64 $maxTimeMs) 0.0) (gt (float64 $maxTimeMs) 2147483647.0) (ne (float64 (int64 $maxTimeMs)) (float64 $maxTimeMs)) }}
{{- fail (printf "services.assetRepository.runtimeQuery.maxTimeMs must be a whole number of milliseconds from 0 (off) to 2147483647, got '%v'" $maxTimeMs) }}
{{- end }}
- name: OCTO_RuntimeQuery__MaxTimeMs
  value: {{ $maxTimeMs | int64 | quote }}
{{- end }}
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
{{- /* AB#5560 PVC / artifact store; renders nothing with the defaults. */}}
{{- include "octo-mesh.bot-storage-env" . }}
{{- /* AB#9319 index upgrade schedule; renders nothing with the defaults. */}}
{{- include "octo-mesh.bot-index-upgrade-env" . }}

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
AB#4923 HTTP activator. Only half of the wiring lives here: what actually routes
traffic is the adapter Ingress annotation
nginx.ingress.kubernetes.io/default-backend, which the communication operator
projects onto every workload (OPERATOR__INGRESS__ANNOTATIONS__n__*) and which
must name this service. Enabling the flag without that annotation is inert.
*/}}
{{- if .global.Values.services.communication.activatorEnabled }}
- name: OCTO_COMMUNICATIONCONTROLLER__ACTIVATORENABLED
  value: "true"
{{- end }}
{{- /*
AB#5063 / AB#5059 (AB#5528 phase 3): staged authorization of the two SignalR hubs.
Rendered always, so the mode in effect is visible on the deployment. Section names
are the controller's AdapterHubAuthorizationOptions.SectionName /
OperatorHubAuthorizationOptions.SectionName; the OCTO_ prefix is stripped by the
controller's AddEnvironmentVariables("OCTO_"). LogOnly changes no outcome; Enforce
refuses unauthenticated / wrongly scoped (adapter hub: wrong-tenant) connections.
Any other value fails the render - a typo must not silently fall back to LogOnly.
*/}}
{{- $hubAuthz := .global.Values.services.communication.hubAuthorization | default dict }}
{{- $adapterHubMode := $hubAuthz.adapterMode | default "LogOnly" }}
{{- if not (has $adapterHubMode (list "LogOnly" "Enforce")) }}
{{- fail (printf "services.communication.hubAuthorization.adapterMode must be LogOnly or Enforce, got '%v'" $adapterHubMode) }}
{{- end }}
{{- $operatorHubMode := $hubAuthz.operatorMode | default "LogOnly" }}
{{- if not (has $operatorHubMode (list "LogOnly" "Enforce")) }}
{{- fail (printf "services.communication.hubAuthorization.operatorMode must be LogOnly or Enforce, got '%v'" $operatorHubMode) }}
{{- end }}
{{ include "octo-mesh.user-token-enforcement-env" (dict "key" "services.communication.userTokenEnforcement" "mode" .global.Values.services.communication.userTokenEnforcement) }}
- name: OCTO_ADAPTERHUBAUTHORIZATION__MODE
  value: {{ $adapterHubMode | quote }}
- name: OCTO_OPERATORHUBAUTHORIZATION__MODE
  value: {{ $operatorHubMode | quote }}
{{ include "octo-mesh.adapter-pool-hub-mode-env" (dict "mode" $hubAuthz.adapterPoolMode) }}
{{- /*
AB#5114 (SECRET phase 3): the impersonation switch may clear the stored secret of eligible
standalone service accounts only when this is explicitly enabled; the controller refuses
apply=true with 409 otherwise. Rendered only when true so the default stays visible as "absent".
*/}}
{{- $impersonation := .global.Values.services.communication.serviceAccountImpersonation | default dict }}
{{- if $impersonation.allowSecretClearing }}
- name: OCTO_SERVICEACCOUNTIMPERSONATION__ALLOWSECRETCLEARING
  value: "true"
{{- end }}
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
Reporting ships in helm-pro (octo-mesh-reporting chart), so the core value
tree has no services.reporting block — the public URL is announced via
externalUris.reporting, like the other separately-deployed endpoints above.
Emitted unconditionally: an empty value makes platform-services serve an
empty `reportingServices` _configuration field, which consumers read as
"service not part of this installation" (AB#4884). The Tenant Features panel
in Refinery Studio keys its Reporting row on this.
*/}}
- name: OCTO_PLATFORMSERVICES__REPORTINGSERVICEURL
  value: {{ .global.Values.externalUris.reporting | quote }}
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

{{- define "octo-mesh.user-token-enforcement-env" -}}
{{- /*
AB#6834 (AB#6728): mode of the user-token tenant gate (TenantAuthorizationMiddleware) of one
service, section TenantAuthorization of the service configuration. Rendered explicitly so the
mode in effect is visible on the deployment. LogOnly (default) denies nothing and logs "would be
denied"; Enforce answers 403 for a user token of a foreign tenant. Any other value fails the
render - a typo must not silently fall back to LogOnly. Included by identity (AB#9017),
assetRepository and communication; every other service keeps its code default.
*/ -}}
{{ include "octo-mesh.tenant-authorization-mode-env" (dict "key" .key "mode" .mode "env" "OCTO_TENANTAUTHORIZATION__USERTOKENENFORCEMENT" "allowed" (list "LogOnly" "Enforce")) }}
{{- end }}

{{- define "octo-mesh.stream-data-read-enforcement-env" -}}
{{- /*
AB#9295 (AB#9199): mode of the stream-data read role requirement of the asset repository (AB#8559,
StreamDataReadAuthorization:RoleEnforcement, StreamDataReadRoleEnforcementMode). Rendered explicitly (chart
default Warn = the service's code default) so the mode in effect is visible on the deployment. Off skips the
role check, Warn logs a read without a stream-data role ("would be denied"), Enforce refuses it. Any other value
fails the render. Included only by assetRepository; it is validated once per render, independent of deploy, by
"octo-mesh.stream-data-read-enforcement-validate".
*/ -}}
{{ include "octo-mesh.tenant-authorization-mode-env" (dict "key" "services.assetRepository.streamDataReadEnforcement" "mode" .mode "env" "OCTO_STREAMDATAREADAUTHORIZATION__ROLEENFORCEMENT" "allowed" (list "Off" "Warn" "Enforce") "default" "Warn") }}
{{- end }}

{{- define "octo-mesh.stream-data-read-enforcement-validate" -}}
{{- /*
AB#9295: validates services.assetRepository.streamDataReadEnforcement once per render, also when the asset
repository is not deployed (deploy: false), and refuses the value on any other service, where it would be
ignored silently. A misspelled key under services.assetRepository (any key whose lower-cased name contains
"streamdataread" but is not exactly streamDataReadEnforcement) also fails the render, so a cluster meant for
Enforce never stays on Warn unnoticed. Called from deployment.yaml with the chart root; renders nothing.
*/ -}}
{{- range $name, $svc := .Values.services }}
{{- $v := dig "streamDataReadEnforcement" nil ($svc | default dict) }}
{{- if eq $name "assetRepository" }}
{{- range $k, $_ := ($svc | default dict) }}
{{- if and (contains "streamdataread" (lower $k)) (ne $k "streamDataReadEnforcement") }}
{{- fail (printf "services.assetRepository.%s is not a known value: did you mean services.assetRepository.streamDataReadEnforcement (Off, Warn or Enforce)?" $k) }}
{{- end }}
{{- end }}
{{- $_ := include "octo-mesh.tenant-authorization-mode-env" (dict "key" "services.assetRepository.streamDataReadEnforcement" "mode" $v "env" "-" "allowed" (list "Off" "Warn" "Enforce") "default" "Warn") }}
{{- else if not (or (kindIs "invalid" $v) (and (kindIs "string" $v) (eq $v ""))) }}
{{- fail (printf "services.%s.streamDataReadEnforcement is not supported: only services.assetRepository runs the stream-data read gate" $name) }}
{{- end }}
{{- end }}
{{- end }}

{{- define "octo-mesh.adapter-pool-hub-mode-env" -}}
{{- /*
AB#9309 (AB#9199): mode of the communication controller's /adapterPoolHub gate
(AdapterPoolHubAuthorizationOptions, section AdapterPoolHubAuthorization, AdapterPoolHubAuthorizationMode
LogOnly | Enforce). Rendered explicitly (chart default LogOnly = the controller's code default) so the mode in
effect is visible on the deployment. LogOnly lets a pool member without a token or with a foreign pool tenant
through and logs/counts it (would_refuse), Enforce refuses it. Any other value fails the render. Included only
by communication; validated once per render, independent of deploy, by "octo-mesh.adapter-pool-hub-mode-validate".
*/ -}}
{{ include "octo-mesh.tenant-authorization-mode-env" (dict "key" "services.communication.hubAuthorization.adapterPoolMode" "mode" .mode "env" "OCTO_ADAPTERPOOLHUBAUTHORIZATION__MODE" "allowed" (list "LogOnly" "Enforce")) }}
{{- end }}

{{- define "octo-mesh.adapter-pool-hub-mode-validate" -}}
{{- /*
AB#9309: validates services.communication.hubAuthorization once per render, also when the communication
controller is not deployed (deploy: false). Fails closed on everything that would otherwise leave a hub on
LogOnly unnoticed:
- adapterPoolMode not LogOnly or Enforce (also a YAML boolean or a lower-case mode);
- an unknown key under services.communication.hubAuthorization (known: adapterMode, operatorMode,
  adapterPoolMode), e.g. a misspelled adapterPoolMod or AdapterPoolMode;
- hubAuthorization set to anything but a map (also false, 0 or "");
- a misplaced or misspelled pool hub key anywhere in the values (see "octo-mesh.gate-key-scan").
Called from deployment.yaml with the chart root; renders nothing.
*/ -}}
{{- $comm := .Values.services.communication | default dict }}
{{- $hub := $comm.hubAuthorization }}
{{- if kindIs "invalid" $hub }}
{{- $hub = dict }}
{{- end }}
{{- if not (kindIs "map" $hub) }}
{{- fail (printf "services.communication.hubAuthorization must be a map, got '%v'" $hub) }}
{{- end }}
{{- range $k, $_ := $hub }}
{{- if not (has $k (list "adapterMode" "operatorMode" "adapterPoolMode")) }}
{{- fail (printf "services.communication.hubAuthorization.%s is not a known value: known are adapterMode, operatorMode and adapterPoolMode" $k) }}
{{- end }}
{{- end }}
{{- $_ := include "octo-mesh.tenant-authorization-mode-env" (dict "key" "services.communication.hubAuthorization.adapterPoolMode" "mode" $hub.adapterPoolMode "env" "-" "allowed" (list "LogOnly" "Enforce")) }}
{{- end }}

{{- define "octo-mesh.gate-key-scan" -}}
{{- /*
AB#9309 / AB#9310: walks the whole values tree (maps and lists, every depth, also outside services) and fails
the render on every key that looks like the adapter pool hub mode or the GraphQL mutation scope flag but is not
at its one legal path. A key is suspicious when its name, lower-cased and with every character other than a-z
and 0-9 removed, matches adapterpool, hubauthori or mutations?scop - so wrong casing, separators (_ - .),
plural forms, nesting (services.assetRepository.graphQl.enforceMutationScope), another service, a misspelled
service name and root-level sections (tenantAuthorization.adapterPoolMode) all fail instead of leaving the
gate on its permissive default. Legal paths: services.communication.hubAuthorization,
services.communication.hubAuthorization.adapterPoolMode and services.assetRepository.enforceMutationScope.
Called with (dict "node" .Values "path" ""); renders nothing.
*/ -}}
{{- $legal := list "services.communication.hubAuthorization" "services.communication.hubAuthorization.adapterPoolMode" "services.assetRepository.enforceMutationScope" }}
{{- $path := .path }}
{{- if kindIs "map" .node }}
{{- range $k, $v := .node }}
{{- /* a key that itself contains a dot (a pasted --set path, `services.x.y: v` in a values file) is written as
["<key>"], so its path can never equal a legal path and a suspicious key in or below it fails */ -}}
{{- $seg := ternary (printf "[%q]" $k) $k (contains "." $k) }}
{{- $full := ternary $seg (printf "%s.%s" $path $seg) (eq $path "") }}
{{- $norm := regexReplaceAll "[^a-z0-9]" (lower $k) "" }}
{{- if and (regexMatch "adapterpool|hubauthori|mutations?scop" $norm) (not (has $full $legal)) }}
{{- if regexMatch "mutations?scop" $norm }}
{{- fail (printf "%s is not a known value: the GraphQL mutation scope gate is set only by services.assetRepository.enforceMutationScope (true or false)" $full) }}
{{- else }}
{{- fail (printf "%s is not a known value: the adapter pool hub mode is set only by services.communication.hubAuthorization.adapterPoolMode (LogOnly or Enforce)" $full) }}
{{- end }}
{{- end }}
{{- include "octo-mesh.gate-key-scan" (dict "node" $v "path" $full) }}
{{- end }}
{{- else if kindIs "slice" .node }}
{{- range $i, $e := .node }}
{{- include "octo-mesh.gate-key-scan" (dict "node" $e "path" (printf "%s[%d]" $path $i)) }}
{{- end }}
{{- end }}
{{- end }}

{{- define "octo-mesh.mutation-scope-env" -}}
{{- /*
AB#9310 (AB#9199): the asset repository's GraphQL mutation scope gate (AB#4973, configuration key
GraphQl:EnforceMutationScope, read with bool.TryParse; the OCTO_ prefix is stripped by the service's
AddEnvironmentVariables("OCTO_"), configuration keys are case-insensitive). Rendered explicitly (chart default
false = the service's default, log-first) so the setting in effect is visible on the deployment. false lets a
generic mutation by a token without scope octo_api through and logs it; true refuses it. Only a YAML boolean is
accepted; unset, null or "" renders false; anything else (also the string "true") fails the render. Included
only by assetRepository; validated once per render, independent of deploy, by "octo-mesh.mutation-scope-validate".
*/ -}}
{{- $v := .enforce }}
{{- if or (kindIs "invalid" $v) (and (kindIs "string" $v) (eq $v "")) }}
{{- $v = false }}
{{- end }}
{{- if not (kindIs "bool" $v) }}
{{- fail (printf "services.assetRepository.enforceMutationScope must be true or false (a YAML boolean), got '%v'" $v) }}
{{- end }}
- name: OCTO_GRAPHQL__ENFORCEMUTATIONSCOPE
  value: {{ ternary "true" "false" $v | quote }}
{{- end }}

{{- define "octo-mesh.mutation-scope-validate" -}}
{{- /*
AB#9310: validates services.assetRepository.enforceMutationScope once per render, also when the asset
repository is not deployed (deploy: false). Misplaced or misspelled keys anywhere in the values are caught by
"octo-mesh.gate-key-scan", so a cluster meant to enforce never stays log-first unnoticed. Called from
deployment.yaml with the chart root; renders nothing.
*/ -}}
{{- $asset := .Values.services.assetRepository | default dict }}
{{- $_ := include "octo-mesh.mutation-scope-env" (dict "enforce" $asset.enforceMutationScope) }}
{{- end }}

{{- define "octo-mesh.service-token-enforcement-env" -}}
{{- /*
AB#9017 (AB#9000): mode of the service-token (client-credentials, no sub claim) tenant check of
TenantAuthorizationMiddleware of one service, section TenantAuthorization of the service configuration
(octo-common-services ServiceTokenTenantEnforcementMode). Rendered explicitly so the mode in effect is
visible on the deployment. LogOnly (default) denies nothing and logs a service token that addresses a
foreign tenant; Enforce answers 403; Disabled skips the check without logging (emergency exit only,
it hides the inventory). Any other value fails the render. Included only by identity; every other
service keeps its code default (Enforce).
*/ -}}
{{ include "octo-mesh.tenant-authorization-mode-env" (dict "key" .key "mode" .mode "env" "OCTO_TENANTAUTHORIZATION__SERVICETOKENENFORCEMENT" "allowed" (list "LogOnly" "Enforce" "Disabled")) }}
{{- end }}

{{- define "octo-mesh.tenant-generation-services" -}}
{{- /* AB#9027: the services of this chart that run the tenant generation check (octo-common-services AB#8999).
platformServices runs no tenant gate (AB#5051), studio is a frontend. */ -}}
{{- list "identity" "assetRepository" "bot" "communication" "aiServices" | toJson }}
{{- end }}

{{- define "octo-mesh.tenant-generation-enforcement-validate" -}}
{{- /*
AB#9027: validates tenantAuthorization.tenantGenerationEnforcement and every services.<name>.tenantGenerationEnforcement
once per render, independent of deploy, so a typo on a service that is not deployed (yet) or an override on a service
without the check (platformServices, studio, ...) fails the render instead of being ignored. Called from
deployment.yaml with the chart root; renders nothing.
*/ -}}
{{- $services := include "octo-mesh.tenant-generation-services" . | fromJsonArray }}
{{- $allowed := list "LogOnly" "Enforce" "Disabled" }}
{{- $_ := include "octo-mesh.tenant-authorization-mode-env" (dict "key" "tenantAuthorization.tenantGenerationEnforcement" "mode" (dig "tenantGenerationEnforcement" nil (.Values.tenantAuthorization | default dict)) "env" "-" "allowed" $allowed) }}
{{- range $name, $svc := .Values.services }}
{{- $override := dig "tenantGenerationEnforcement" nil ($svc | default dict) }}
{{- if not (or (kindIs "invalid" $override) (and (kindIs "string" $override) (eq $override ""))) }}
{{- $key := printf "services.%s.tenantGenerationEnforcement" $name }}
{{- if not (has $name $services) }}
{{- fail (printf "%s is not supported: %s runs no tenant generation check (supported: %s)" $key $name (join ", " $services)) }}
{{- end }}
{{- $_ := include "octo-mesh.tenant-authorization-mode-env" (dict "key" $key "mode" $override "env" "-" "allowed" $allowed) }}
{{- end }}
{{- end }}
{{- end }}

{{- define "octo-mesh.tenant-generation-enforcement-env" -}}
{{- /*
AB#9027 (AB#9000 switch S2): mode of the tenant generation check (octo-common-services AB#8999,
TenantAuthorization:TenantGenerationEnforcement, TenantGenerationEnforcementMode). Global value
tenantAuthorization.tenantGenerationEnforcement, per-service override services.<name>.tenantGenerationEnforcement
(unset or "" takes the global value). Rendered explicitly (chart default LogOnly) on every service that runs the
check, nothing on the others. All values are validated by "octo-mesh.tenant-generation-enforcement-validate".
*/ -}}
{{- if has .name (include "octo-mesh.tenant-generation-services" .global | fromJsonArray) }}
{{- $override := dig "tenantGenerationEnforcement" nil (.svc | default dict) }}
{{- if or (kindIs "invalid" $override) (and (kindIs "string" $override) (eq $override "")) }}
{{- include "octo-mesh.tenant-authorization-mode-env" (dict "key" "tenantAuthorization.tenantGenerationEnforcement" "mode" (dig "tenantGenerationEnforcement" nil (.global.Values.tenantAuthorization | default dict)) "env" "OCTO_TENANTAUTHORIZATION__TENANTGENERATIONENFORCEMENT" "allowed" (list "LogOnly" "Enforce" "Disabled")) }}
{{- else }}
{{- include "octo-mesh.tenant-authorization-mode-env" (dict "key" (printf "services.%s.tenantGenerationEnforcement" .name) "mode" $override "env" "OCTO_TENANTAUTHORIZATION__TENANTGENERATIONENFORCEMENT" "allowed" (list "LogOnly" "Enforce" "Disabled")) }}
{{- end }}
{{- end }}
{{- end }}

{{- define "octo-mesh.tenant-authorization-mode-env" -}}
{{- /*
Shared validation of the TenantAuthorization modes (AB#6834, AB#9017) and the stream-data read gate mode
(AB#9295). Only an unset value (null) or "" falls back to .default (LogOnly when not given); every other value
must be one of .allowed as a string. A YAML boolean or number (e.g. an empty-looking false or 0) fails the
render instead of silently becoming the default.
*/ -}}
{{- $mode := .mode }}
{{- if or (kindIs "invalid" $mode) (and (kindIs "string" $mode) (eq $mode "")) }}
{{- $mode = .default | default "LogOnly" }}
{{- end }}
{{- if not (and (kindIs "string" $mode) (has $mode .allowed)) }}
{{- fail (printf "%s must be %s, got '%v'" .key (include "octo-mesh.or-list" .allowed) $mode) }}
{{- end }}
- name: {{ .env }}
  value: {{ $mode | quote }}
{{- end }}

{{- define "octo-mesh.or-list" -}}
{{- $n := len . }}
{{- if eq $n 1 }}{{ index . 0 }}
{{- else }}{{ join ", " (initial .) }} or {{ last . }}
{{- end }}
{{- end }}
