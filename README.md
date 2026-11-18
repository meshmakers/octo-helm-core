# OctoMesh Helm Charts

This repository contains the helm charts for OctoMesh. The charts are hosted on GitHub pages and can be accessed using the following URL:

```bash
https://meshmakers.github.io/charts
```
# About OctoMesh

OctoMesh is at the forefront of data infrastructure innovation, enabling organizations to build decentralized data architectures that are both scalable and resilient. With OctoMesh, you can connect disparate data sources with unprecedented ease, ensuring that your data is accessible, secure, and compliant across the board.

# Getting started

There are several helm charts available in this repository:
1) octo-mesh: The core services of OctoMesh. This is typically installed centrally and supports multiple tenants.
2) octo-mesh-crds: This chart contains all custom resource definitions (CRDs) required by OctoMesh Communication Operator
3) octo-mesh-communication-operator: This chart contains the OctoMesh Communication Operator, which is responsible for managing adapters on edge clusters.
4) octo-mesh-demo-app: This chart contains the OctoMesh demo app.

Adapter charts now live in their respective adapter repositories and are published from there:
- `octo-mesh-adapter` — published by [`octo-mesh-adapter`](https://github.com/meshmakers/octo-mesh-adapter)
- `octo-eda-adapter` — published by [`octo-adapter-eda`](https://github.com/meshmakers/octo-adapter-eda)

To use the charts, add the repository to your helm configuration:

```bash
helm repo add meshmakers https://meshmakers.github.io/charts
helm repo update
```

## Setup octo-mesh core services

OctoMesh needs a running MongoDB and RabbitMQ instance, for stream data CrateDB is required. Ingress NGINX is recommended for routing. Cert Manager or valid public certificates are required for HTTPS.

Summarized, the following prerequisites are required to install OctoMesh:
1) Ingress NGINX
2) Cert Manager
3) MongoDB
4) RabbitMQ
5) CrateDB

For support to set up the prerequisites, please contact us at [support@meshmakers.io](mailto:support@meshmakers.io)

If you have the prerequisites ready, you can install the core services using the following steps:

### Generate a new key pair for the Identity Server

Create Private/Public Key

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -keyout IdentityServer4Auth.key -out IdentityServer4Auth.crt -subj "/CN=<identity URI>" -days 10950 -passout pass:"<password>"
```

Create PFX

```bash
openssl pkcs12 -export -out IdentityServer4Auth.pfx -inkey IdentityServer4Auth.key -in IdentityServer4Auth.crt -passin pass:"<password>" -passout pass:"<password>"
```

### Create a values-file to configure OctoMesh
See the [values.yaml](src/octo-mesh/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Install OctoMesh core services

Execute the following command to install OctoMesh

```bash
helm upgrade --install --namespace octo --create-namespace --values ./src/examples/aks-cert-manager-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx <releaseName> meshmakers/octo-mesh
```

Custom root certificates can be added to the secrets using the `--set-file secrets.rootCa=<rootCa.crt>` flag.

```bash
helm upgrade --install --namespace octo --create-namespace --values local-cluster-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=rootca.crt octo-mesh meshmakers/octo-mesh
```

It is also possible to set the image tag for the services using the `--set services.<service>.image.tag=<tag>` flag.

```bash
helm upgrade --install --namespace octo --create-namespace --values rke2-local-values.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=root-ca-collection.crt --set services.identity.image.tag="0.0.2406.3001" octo-mesh meshmakers/octo-mesh
```

### SECRET attribute key ring (AB#5536)

Every engine-hosting service of the `octo-mesh` chart (identity, asset repository, bot, communication controller, platform services, AI services) receives the key ring for the `SECRET` attribute value type through the shared `octo-mesh.system-env` block:

| Environment variable | Configuration key | Source |
|---|---|---|
| `OCTO_SECRETENCRYPTION__KEYS__<kid>` (one per key, e.g. `..._KEYS__k1`) | `SecretEncryption:Keys:<kid>` | backend Secret, key `secretEncryptionKey-<kid>` |
| `OCTO_SECRETENCRYPTION__ACTIVEKEYID` | `SecretEncryption:ActiveKeyId` | plain value |
| `OCTO_SECRETENCRYPTION__LEGACYV1KEY` | `SecretEncryption:LegacyV1Key` | backend Secret, key `communicationInstanceSecretKey` |

No new value is required: by default the existing `secrets.communicationInstanceSecretKey` is key `k1` (active) and the legacy `enc:v1` key. For a key rotation set `secrets.secretEncryptionKeys` (replaces the derived ring — list `k1` too while it is still needed) and `secrets.secretEncryptionActiveKeyId`; the procedure is in `octo-mesh-deployment/docs/VAULT-SETUP.md`. The key id keeps its case in the variable name, so it matches the `enc:v2:<kid>:` header the engine writes.

Workloads deployed by the communication operator receive the same ring when their Adapter has `ReceivesClusterSecrets=true`; set `operator.clusterSecrets.instanceSecretKey` on the operator chart to the same value (optional override: `operator.clusterSecrets.secretEncryptionKeys` / `secretEncryptionActiveKeyId`).

**Missing-key guard (opt-in).** `secrets.secretEncryptionRequired: true` (octo-mesh) and `operator.clusterSecrets.secretEncryptionRequired: true` (operator) make `helm template`/`upgrade` fail when the key ring is empty or the instance secret is not a base64-encoded 32-byte key — including an unresolved Azure DevOps macro such as `$(VAULT_instance_secret_key)`. The default `false` keeps the previous behaviour (empty ring renders nothing, services start, only SECRET access fails), so clusters without an instance secret and edge operators that run without a key ring by design keep deploying. Enable it per cluster once Vault `instance_secret_key` is verified and backed up.

### Bot persistence and artifact storage (AB#5560)

The bot keeps pre-sweep secret dumps, tenant dumps and restore uploads. Without configuration they live in the container's temp directory and are lost on every restart. Three optional blocks under `services.bot` change that; all are off by default and the chart then renders exactly as before.

| Value | Effect |
|---|---|
| `persistence.enabled` (+ `storageClass`, `accessMode` = `ReadWriteOnce`, `size` = `10Gi`, `existingClaim`, `mountPath` = `/data/octo-bot`) | PVC `<release>-bot-services-data` (or the existing claim) mounted at `mountPath`; sets `OCTO_BOT__SECRETSWEEP__BACKUPSTORAGEPATH=<mountPath>/secret-backups` and, unless an object store is configured, `OCTO_ARTIFACTSTORAGE__PROVIDER=FileSystem` with `OCTO_ARTIFACTSTORAGE__FILESYSTEM__ROOTPATH=<mountPath>/artifacts`. `ReadWriteOnce` requires `replicaCount: 1` and `recreateStrategy: true` (render fails otherwise). |
| `scratch.enabled` (+ `mountPath` = `/tmp`, `sizeLimit` = `20Gi`, `medium`, `ephemeralVolume.{enabled,storageClass,size}`) | `emptyDir` with `sizeLimit` (or a generic ephemeral volume) for mongodump output, tus uploads and downloads, so large files do not fill the node disk. |
| `artifactStorage.provider` = `FileSystem` \| `S3` \| `AzureBlob` | `OCTO_ARTIFACTSTORAGE__*` for the platform artifact store (AB#5561): `INSTANCEPREFIX` (default: release name), `S3__{SERVICEURL,CRATEDBSERVICEURL,REGION,BUCKET,FORCEPATHSTYLE,SERVERSIDEENCRYPTION}` (`artifactStorage.s3.crateDbServiceUrl`: the endpoint under which the CrateDB nodes reach the same store for the archive `COPY TO` / `COPY FROM`, set it when that endpoint differs from `serviceUrl`; rendered whenever it is set), `AZUREBLOB__{ACCOUNTURL,CONTAINER,USEMANAGEDIDENTITY}`. |

Credentials are only referenced from an existing Secret, never put into values: `s3.existingSecret` with `accessKeyIdKey` / `secretAccessKeyKey` (defaults `accessKeyId` / `secretAccessKey`; without a Secret the AWS SDK default chain applies), `azureBlob.existingSecret` with exactly one of `connectionStringKey` / `accountKeyKey`. For AKS workload identity set `azureBlob.useManagedIdentity: true`, `azureBlob.workloadIdentityClientId` and `services.bot.serviceAccount.create: true` (or `serviceAccount.name` of an existing, federated account); the pod gets the label `azure.workload.identity/use: "true"` and the created ServiceAccount the `azure.workload.identity/client-id` annotation.

Retention stays in the application (`Bot:SecretSweep:BackupRetentionDays` = 7, `Bot:FileRetentionHours`); bucket/container lifecycle rules are the backstop and belong to the infrastructure. Keep the PVC out of volume snapshots and DR backups. Concept: `octo-construction-kit-engine/docs/secret-sweep-dump-storage.md`.

### Identity REST API role check (AB#5859)

The identity service requires tenant roles on its tenant REST API: `UserManagement` for users, roles and groups; `TenantManagement` or `UserManagement` for clients, identity providers and the other tenant administration endpoints.

| Value | Default | Environment variable |
|---|---|---|
| `services.identity.apiRoleEnforcement` = `Enforce` \| `Warn` | `Enforce` | `OCTO_IDENTITYAPIAUTHORIZATION__ROLEENFORCEMENT` |

`Enforce` rejects callers without the required role (403). `Warn` is the emergency exit / transition switch: such callers are let through and the service logs `would be denied with RoleEnforcement=Enforce (AB#5859)`. Use it only until the missing role assignments are fixed, then switch back to `Enforce`. Any other value fails the render.

### Identity secret management and Data Protection key encryption (AB#5861, AB#5530)

Both values are rendered on the identity deployment **only when set**; unset keeps the service default, so no installation changes without a value.

| Value | Default (unset) | Environment variable |
|---|---|---|
| `services.identity.secretManagementRoleEnforcement` = `Warn` \| `Enforce` | not rendered (service default `Warn`) | `OCTO_IDENTITYAPIAUTHORIZATION__SECRETMANAGEMENTROLEENFORCEMENT` |
| `services.identity.dataProtection.encryptExistingKeys` = `true` \| `false` | not rendered (service default `false`) | `OCTO_IDENTITY__DATAPROTECTION__ENCRYPTEXISTINGKEYS` |

`secretManagementRoleEnforcement`: `Warn` still lets `TenantManagement`/`UserManagement` callers write API secrets and logs `would be denied with SecretManagementRoleEnforcement=Enforce (AB#5861)`; `Enforce` accepts only the `SecretManagement` role. `apiRoleEnforcement: Warn` also relaxes it. Any other value fails the render. Switch per cluster after the precheck in `octo-identity-services/docs/rollout-identity-rest-role-enforcement.md`.

`dataProtection.encryptExistingKeys`: `true` encrypts new Data Protection keys with the platform key ring and rewrites every stored plain key encrypted at startup; identity refuses to start without a `SecretEncryption` key. Switch on per cluster only after every identity pod runs an image with the decryptor (`octo-identity-services/docs/rollout-identity-dataprotection-encryption.md`). Setting it back to `false` does not decrypt stored keys. A non-boolean value fails the render.

### Identity admin role migration (AB#8165)

| Value | Default (unset) | Environment variable |
|---|---|---|
| `services.identity.adminRoleMigration` = `Off` \| `DryRun` \| `Apply` | not rendered (service default `Off`) | `OCTO_IDENTITYAPIAUTHORIZATION__ADMINROLEMIGRATION` |

Moves existing tenant admins from directly assigned roles to `TenantOwners` membership. `DryRun` only logs, per tenant, the subject ids that would join the group and the direct roles that would be removed. `Apply` makes users, `xt_` users and external tenant user mappings that hold `TenantManagement` and `UserManagement` directly members of `TenantOwners` and removes a direct role only when `TenantOwners` carries it; clients and groups are not migrated, a second run changes nothing. It changes role data: set it per cluster, `DryRun` first, `Apply` only with the go of the cluster owner. Any other value fails the render. In a values file write `adminRoleMigration: "Off"` with quotes: an unquoted `Off` is a YAML boolean and fails the render.

### Identity shadow user cleanup (AB#8305)

| Value | Default (unset) | Environment variable |
|---|---|---|
| `services.identity.shadowUserCleanup` = `Off` \| `DryRun` \| `Apply` | not rendered (service default `Off`) | `OCTO_IDENTITYAPIAUTHORIZATION__SHADOWUSERCLEANUP` |

Removes cross-tenant shadow users (`xt_`) that refused token exchanges left behind and that hold no right: no role, no group, no other association, no external tenant user mapping for them, not the source of a mapping elsewhere, and no password, two-factor, login, token or claim. Identity runs it once per start, two minutes after it. `DryRun` only logs, per tenant, every candidate (rtId, user name, creation date), the skip reasons of the other `xt_` users and a summary. `Apply` deletes the candidates through the identity user store and writes one audit event per deleted user; a second run finds nothing. It deletes identity data: set it per cluster, `DryRun` first, `Apply` only after the DryRun list is reviewed, then remove the value again (runbook in `octo-identity-services/docs/authentication.md`). Any other value fails the render. In a values file write `shadowUserCleanup: "Off"` with quotes: an unquoted `Off` is a YAML boolean and fails the render.

### Identity cross-tenant ancestry (AB#8339)

| Value | Default (unset) | Environment variable |
|---|---|---|
| `services.identity.crossTenantAncestry` = `Warn` \| `Enforce` | not rendered (service default `Warn`) | `OCTO_IDENTITYAPIAUTHORIZATION__CROSSTENANTANCESTRY` |

Decides whether the tenant registry or a tenant's own OctoTenant identity providers say who is an ancestor — for the provisioning source users, the tenant switch / token exchange and the cross-tenant login. `Warn` keeps the behaviour before AB#8339 and logs every ancestor the registry does not confirm (`allowed by CrossTenantAncestry=Warn ... (AB#8339)`, with both tenant ids); `Enforce` accepts only registry ancestors and refuses provisioning writes with a non-ancestor source (403) and OctoTenant providers with a non-ancestor parent (400). Switch per cluster in `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml` after the inventory and the Warn log are reviewed (see `octo-identity-services/docs/authentication.md`, *Registry Decides Cross-Tenant Ancestry*). Any other value fails the render.

### Identity password methods on the bus (AB#8603)

| Value | Default (unset) | Environment variable |
|---|---|---|
| `services.identity.methods.enablePasswordMethods` = `true` \| `false` | not rendered (service default `false`) | `OCTO_Methods__Identity__EnablePasswordMethods` |

`true` offers the identity CK methods that carry a password or secret (`User.ChangePassword`, `User.SetPassword`, `User.ResetPassword`, `User.CreateUser`, `Client.AddSecret`, `Client.RemoveSecret`) on the message bus, so the asset repository GraphQL gateway can call them. `false` or unset: the gateway answers `METHOD_HANDLER_NOT_AVAILABLE`; the REST facades (`POST users`, `POST users/ResetPassword`, account pages) keep working local only in either state. Identity reads the value at start, so the CD rollout restarts it. Switch on per cluster only with the cluster owner's go (test-2 first, then staging-1, prod-1, prod-2); rollback = `false` (or unset) and a CD run. A non-boolean value (also a quoted `"true"`) fails the render. Service side: `octo-identity-services/docs/configuration.md`.

### REST deprecation wave dates (AB#8415)

REST endpoints that a CK method replaces are marked with `[OctoRestDeprecated(Wave = "<wave>")]`. Their `Deprecation`
and `Sunset` headers take the dates from `restDeprecation.waves.<wave>.since|sunset` (`yyyy-MM-dd`, UTC), rendered as
`OCTO_RestDeprecation__Waves__<wave>__Since|Sunset` on every service. Unset = no header. Rule: `since`
is the delivery day of the release that contains the wave on prod; the `sunset` date is to be announced — Gerald decides it
once the migration functions are implemented (2026-11-11, no fixed compatibility window), until then it stays empty and no
`Sunset` header is sent; removal after the sunset only on the `octo.rest.deprecated.calls` evidence. Waves: `IdentityUsers1`
(since `2026-11-08`, sunset to be announced, set for all clusters in `octo-mesh-deployment/base/values-octo-mesh.yaml`). Details: octo-common-services `docs/rest-deprecation.md`.

### SignalR hub authorization mode (AB#5063, AB#5059)

The communication controller gates `/{tenantId}/adapterHub` and `/operatorHub` with a staged check. The chart renders the mode of each hub explicitly on the controller deployment:

| Value | Default | Environment variable |
|---|---|---|
| `services.communication.hubAuthorization.adapterMode` = `LogOnly` \| `Enforce` | `LogOnly` | `OCTO_ADAPTERHUBAUTHORIZATION__MODE` |
| `services.communication.hubAuthorization.operatorMode` = `LogOnly` \| `Enforce` | `LogOnly` | `OCTO_OPERATORHUBAUTHORIZATION__MODE` |
| `services.communication.hubAuthorization.adapterPoolMode` = `LogOnly` \| `Enforce` (AB#9309) | `LogOnly` | `OCTO_ADAPTERPOOLHUBAUTHORIZATION__MODE` |

`LogOnly` changes no connection outcome; every connection an enforcing run would refuse is logged and counted (`octo.communication.hub.authorization.decisions`, `outcome=would_refuse`). `Enforce` refuses those connections. Any other value fails the render. Switch per cluster only after the LogOnly evidence is clean — runbook: `octo-communication-controller-services/docs/runbooks/hub-authorization-enforce-rollout.md`. The operator hub additionally needs every operator to authenticate (`operator.authentication.*` on the operator chart, below).

`adapterPoolMode` (AB#9309) gates `/adapterPoolHub`: under `LogOnly` a pool member may connect without a token or register into another tenant's pool (counted with `octo_hub_name="adapterPoolHub"`); `Enforce` refuses both. The chart default `LogOnly` is the controller's code default, so no installation changes its behaviour without a value (the controller deployment gets the new variable and rolls once). An unset or empty value renders `LogOnly`; any other value, also a lower-case mode or a YAML boolean (an unquoted `On`/`Off`/`yes`/`no` in a values file), fails the render. The value is validated also when the communication controller is not deployed. Fail-closed key checks: `hubAuthorization` must be a map (also `false`, `0` or `""` fail); any key under `services.communication.hubAuthorization` other than `adapterMode`, `operatorMode` and `adapterPoolMode` (e.g. a misspelled `adapterPoolMod` or `AdapterPoolMode`) fails the render; and the whole values tree (every depth, lists included, also outside `services`) is scanned for keys whose name, ignoring casing and every character other than letters and digits, contains `adapterpool` or `hubauthori` — every such key that is not exactly `services.communication.hubAuthorization` or `services.communication.hubAuthorization.adapterPoolMode` fails the render (e.g. `services.communication.adapter_pool_mode`, `services.identity.adapterPoolMode`, `tenantAuthorization.adapterPoolMode`, a root-level `hubAuthorization` block, or a single key with dots such as `services.communication.hubAuthorization.adapterPoolMode: Enforce` at the root of a values file — a key containing a dot never counts as the nested path). Switch per cluster by the plan of AB#9309 (values in `octo-mesh-deployment`). Rollback: set the value back to `LogOnly` and roll the controller deployment.

### User-token tenant gate mode (AB#6834)

Asset repository and communication controller reject (or, in `LogOnly`, only log) a user token issued for tenant A that calls a route of tenant B. The chart renders the mode of each service explicitly on its deployment (identity: next section; every other service keeps its code default, `Enforce`):

| Value | Default | Environment variable |
|---|---|---|
| `services.assetRepository.userTokenEnforcement` = `LogOnly` \| `Enforce` | `LogOnly` | `OCTO_TENANTAUTHORIZATION__USERTOKENENFORCEMENT` |
| `services.communication.userTokenEnforcement` = `LogOnly` \| `Enforce` | `LogOnly` | `OCTO_TENANTAUTHORIZATION__USERTOKENENFORCEMENT` |

`LogOnly` (the default, identical to the services' code default, so no installation changes without a value) denies nothing and logs `would be denied`. `Enforce` answers such calls with 403. Any other value fails the render. The SignalR hubs are not part of this gate; see the hub authorization mode above.

Rollback: set the value of the affected service back to `LogOnly` and roll the deployment; each service is switched independently. Switch per cluster only after the LogOnly warnings are clean - rollout steps and checks: runbook in `octo-communication-controller-services` (AB#6833).

### Identity tenant authorization modes (AB#9017)

From octo-identity-services #305 (AB#9017) on, identity's own API runs the tenant check of `TenantAuthorizationMiddleware` on bearer tokens: a token issued for tenant A that calls an identity route of tenant B. The service's code default is `Enforce` for both token kinds; the chart renders both modes explicitly on the identity deployment with the chart default `LogOnly`, so an installation without a value only logs. On an identity version before #305 the variables are bound but have no effect: the check never runs there, whatever the mode says.

An unset or empty value renders `LogOnly`; a YAML boolean or number fails the render like any other invalid value.

| Value | Default | Environment variable |
|---|---|---|
| `services.identity.userTokenEnforcement` = `LogOnly` \| `Enforce` | `LogOnly` | `OCTO_TENANTAUTHORIZATION__USERTOKENENFORCEMENT` |
| `services.identity.serviceTokenEnforcement` = `LogOnly` \| `Enforce` \| `Disabled` | `LogOnly` | `OCTO_TENANTAUTHORIZATION__SERVICETOKENENFORCEMENT` |

`LogOnly` denies nothing and logs every call an enforcing run would refuse. `Enforce` answers it with 403 (a service token is let through when its client is in `TenantAuthorization:CrossTenantServiceClientIds`). `Disabled` (service tokens only, as in octo-common-services `ServiceTokenTenantEnforcementMode`) skips the check without logging; it is an emergency exit only, because it hides the inventory. Any other value fails the render. The service-token mode is rendered on identity only; asset repository and communication controller keep their code default (`Enforce`) for service tokens.

Rollout plan (AB#9000; values in `octo-mesh-deployment`, a follow-up of this chart change): test-2 sets both to `Enforce`; staging-1, prod-1 and prod-2 stay on `LogOnly` for the first release with #305 and are switched per cluster once the LogOnly warnings are clean. Rollback: set the value back to `LogOnly` and roll the identity deployment.

### Tenant generation check mode (AB#9027)

Access tokens issued by identity since AB#8997 carry `tenant_gen`, the creation time of their tenant; older tokens carry
none. The services compare it with the current generation of the tenant (octo-common-services AB#8999,
`docs/tenant-generation-check.md`). Under `Enforce` a token whose `tenant_gen` is missing or differs is refused (e.g. a
token of a deleted tenant presented to a new tenant with the same id); under `LogOnly` it is only logged and counted.
The chart renders the mode on every service that runs the check: identity (also its token grants), asset repository,
bot, communication controller and AI services. Platform services runs no tenant gate and studio is a frontend; neither
gets the variable.

| Value | Default | Environment variable |
|---|---|---|
| `tenantAuthorization.tenantGenerationEnforcement` = `LogOnly` \| `Enforce` \| `Disabled` | `LogOnly` | `OCTO_TENANTAUTHORIZATION__TENANTGENERATIONENFORCEMENT` |
| `services.<service>.tenantGenerationEnforcement` (`identity`, `assetRepository`, `bot`, `communication`, `aiServices`) | unset = the global value | same variable, on that service only |

`LogOnly` (the default, identical to the code default) refuses nothing; tokens without or with a different `tenant_gen`
are logged (`This would be denied with TenantGenerationEnforcement=Enforce`) and counted
(`octo.tenant_auth.generation_checks`). `Enforce` refuses them (403, `METHOD_FORBIDDEN`, `invalid_grant`) and answers
503 when the generation cannot be read. `Disabled` turns the check off without log or metric; it is an emergency exit
only. An unset or empty value renders `LogOnly` (override: the global value); any other value, also a YAML boolean or
number, fails the render. All values are validated once per render, also for services that are not deployed; the global
value is validated even when every service overrides it, and an override on a service without the check (e.g.
`platformServices`, `studio`) fails the render.

Switch per cluster only by the plan `octo-common-services/docs/tenant-generation-enforce-plan.md` (AB#9000, switch S2):
all services of a cluster in one CD run, together with the same value in the reporting, MCP and AI charts
(`octo-helm-pro`). Rollback: set the value back to `LogOnly` and roll the deployments.

### Stream-data read gate mode (AB#9295)

From octo-asset-repo-services #158 (AB#8559) on, a stream-data read of the asset repository (the transient queries
`simple`, `aggregation`, `groupingAggregation`, `downsampling` and the persisted `streamDataQuery`) needs one of the
tenant roles `StreamDataReader`, `StreamDataWriter` or `StreamDataAdmin`. The chart renders the mode explicitly on the
asset repository deployment, and on no other service:

| Value | Default | Environment variable |
|---|---|---|
| `services.assetRepository.streamDataReadEnforcement` = `Off` \| `Warn` \| `Enforce` | `Warn` | `OCTO_STREAMDATAREADAUTHORIZATION__ROLEENFORCEMENT` |

`Warn` (the default, identical to the service's code default, so no installation changes its behaviour without a value)
lets the read through and logs it as "would be denied" (at most once per caller, tenant and query kind per hour).
`Enforce` refuses a caller without a stream-data role (GraphQL error `StreamDataReadRoleRequired`). `Off` skips the
role check (the behaviour before AB#8559). An unset or empty value renders `Warn`; any other value, also a lower-case
mode or a YAML boolean, fails the render. The value is validated also when the asset repository is not deployed, and
the same key on any other service fails the render, as does a misspelled key under `services.assetRepository` (any key
containing `streamDataRead` in any casing that is not exactly `streamDataReadEnforcement`). On an asset repository
before #158 the variable is bound but has no effect. In a values file write `streamDataReadEnforcement: "Off"` with quotes: an unquoted `Off` is a YAML boolean and fails
the render.

Switch per cluster only after the `Warn` log names no caller that still needs a role, by the switch plan of AB#9296
(values in `octo-mesh-deployment`). Rollback: set the value back to `Warn` and roll the asset repository deployment.

### Bot index upgrade schedule (AB#9319)

From octo-bot-services AB#9118 on, bot-services rebuilds the paging indexes of every tenant in the shape
`{ckTypeId, attr…, _id, rtState}` with one Hangfire job per tenant (octo-bot-services `docs/index-upgrade.md`). When it
builds is set per cluster; the chart renders each variable on the bot deployment only, and only when its value is set:

| Value | Default | Environment variable |
|---|---|---|
| `services.bot.indexUpgrade.schedule` = `Immediate` \| `Window` | unset | `OCTO_INDEXUPGRADE__SCHEDULE` |
| `services.bot.indexUpgrade.window.enabled` = `true` \| `false` (YAML boolean) | unset | `OCTO_INDEXUPGRADE__WINDOW__ENABLED` |
| `services.bot.indexUpgrade.window.cron` (Hangfire cron, UTC, e.g. `"0 1 * * *"`) | unset | `OCTO_INDEXUPGRADE__WINDOW__CRON` |
| `services.bot.indexUpgrade.window.maxDuration` (.NET TimeSpan string, e.g. `"04:00:00"`, `"1.00:00:00"`) | unset | `OCTO_INDEXUPGRADE__WINDOW__MAXDURATION` |

Unset (the default) renders nothing, and the service keeps its code default: `Window` with the window off, so no index
is built. `Immediate` builds after every deploy (after a start delay) and for created or attached tenants; `Window`
builds only inside the window the cron opens, and only with `window.enabled: true`. These set values fail the render
with the key in the message: a schedule other than `Immediate` or `Window` (also lower case or empty), a
`window.enabled` that is no YAML boolean (also the string `"true"`), an empty or blank `window.cron` and a
`window.maxDuration` that is no TimeSpan of the form `[d.]hh:mm[:ss[.fffffff]]` longer than zero (at most 7 day
digits, so it stays below the .NET TimeSpan maximum). For `window.cron` the chart checks only that it is a non-empty
string; bot-services (Hangfire) validates the cron expression at start, and with an invalid one no window opens. The
values are checked once per render, also with `services.bot.deploy: false`; a misspelled or unknown key (for example
`services.bot.indexupgrade` or `window.enable`), an `indexUpgrade` or `window` that is no map, and `indexUpgrade` on any
other service fail the render as well, instead of being ignored.

Switch a production cluster on (`schedule: Window` with `window.enabled: true`) only after the developer's go for that
cluster and after measuring the duration on a copy (rollout procedure in octo-bot-services `docs/index-upgrade.md`). The
cluster values live in `octo-mesh-deployment`.
### GraphQL mutation scope gate (AB#9310)

The asset repository requires the scope `octo_api` on the token of a generic GraphQL mutation once its configuration
key `GraphQl:EnforceMutationScope` is `true` (AB#4973; CK method calls need `octo_api` regardless). The chart renders
the setting explicitly on the asset repository deployment, and on no other service:

| Value | Default | Environment variable |
|---|---|---|
| `services.assetRepository.enforceMutationScope` = `true` \| `false` | `false` | `OCTO_GRAPHQL__ENFORCEMUTATIONSCOPE` |

`false` (the default, identical to the service's default, so no installation changes its behaviour without a value;
the asset repository deployment gets the new variable and rolls once) lets the mutation run and logs a warning ("GraphQL
mutation by subject '…' without the 'octo_api' scope — would be rejected once GraphQl:EnforceMutationScope is
enabled"). `true` refuses it with the forbidden error code. Only a YAML boolean is accepted: an unset, null or empty
value renders `false`; anything else, also the quoted string `"true"` or a number, fails the render. The value is
validated also when the asset repository is not deployed. The whole values tree (every depth, lists included, also
outside `services`) is scanned for keys whose name, ignoring casing and every character other than letters and digits,
contains `mutationscop` or `mutationsscop`: every such key that is not exactly
`services.assetRepository.enforceMutationScope` fails the render, e.g. `enforceMutationScop`, `enforceMutationsScope`,
`enforce_mutation_scope`, `services.assetRepository.graphQl.enforceMutationScope` (the configuration key path), the
key on another service, or an `assetRepository` block that slipped to the root of a values file; a single key containing dots (`services.assetRepository.enforceMutationScope: true` at the root of a values file) never counts as the nested path and fails too.

Switch per cluster only after the 7-day log query names no legitimate client without `octo_api`, by the plan of
AB#9310 (values in `octo-mesh-deployment`). Rollback: set the value back to `false` and roll the asset repository
deployment.

### Render octo-mesh chart template locally and display the output

```bash
helm template --namespace octo --values local-cluster-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=rootca.crt octo-mesh ../octo-mesh
```

## Setup OctoMesh Demo App

OctoMesh Demo App shows the possibilities for the frontend UI provides

### Create a values-file to configure demo app
See the [values.yaml](src/octo-mesh-demo-app/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-demo-app chart template locally and display the output

```bash
helm template --namespace octo --values demo-app-sample.yaml mydemoapp ../octo-mesh-demo-app
```

### Install OctoMesh Excel Add-in

```bash
helm upgrade --install --namespace octo --create-namespace --values office-values.yaml --set image.tag="0.0.2406.3001" mesh-add-in meshmakers/octo-mesh-office
```

## Setup OctoMesh Communication Operator

OctoMesh Communication Operator is responsible for managing adapters on edge clusters. The operator requires octo-mesh-crds to be installed.

### Create a value file to configure OctoMesh Communication Operator
See the [values.yaml](src/octo-mesh-communication-operator/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Generate CA and server certificates

For webhooks to work, the operator requires a CA certificate and key, as well as a server certificate and key. The following command can be used to generate the certificates:

```bash
octo-cli -c GenerateOperatorCertificates -o . -n octo-operator-system -s octo-mesh-op1-communication-operator
```
-n is the namespace where the operator is installed, -s is the name of the operator server, it is the combination of the release name and "communication-operator".

### Install OctoMesh CRDs

```bash
helm install --namespace octo-operator-system octo-mesh-crds ./octo-mesh-crds/
```

### Install the OctoMesh Communication Operator

```bash
helm install --namespace octo-operator-system --values ./examples/operator-sample.yaml --set-file serviceHooks.caKey=examples/ca-key.pem --set-file serviceHooks.caCrt=examples/ca.pem --set-file serviceHooks.svcKey=examples/svc-key.pem --set-file serviceHooks.svcCrt=examples/svc.pem octo-mesh-op1 --set "octo-mesh-crds.enabled=false" ./octo-mesh-communication-operator/
```
The operator requires the CRDs to be installed, but they are installed by default. To disable install the CRDs, set the `octo-mesh-crds.enabled` value to `false`.

```bash
helm install --namespace octo-operator-system --values ./examples/operator-sample.yaml --set image.tag=0.0.2408.23001-main  --set-file serviceHooks.caKey=examples/ca-key.pem --set-file serviceHooks.caCrt=examples/ca.pem --set-file serviceHooks.svcKey=examples/svc-key.pem --set-file serviceHooks.svcCrt=examples/svc.pem octo-mesh-op1 ./octo-mesh-communication-operator/
```

### Operator authentication against the controller (AB#5062)

The operator logs in with client credentials before it connects to `/operatorHub`. Optional: without these values nothing is rendered and the operator connects anonymously, which only works while the controller runs `operatorMode: LogOnly`.

| Value | Environment variable |
|---|---|
| `operator.authentication.issuerUri` (empty = `operator.authUri`) | `OPERATOR__AUTHENTICATION__ISSUERURI` |
| `operator.authentication.tenantId` (required when configured; the system tenant, e.g. `octosystem`) | `OPERATOR__AUTHENTICATION__TENANTID` |
| `operator.authentication.clientId` + `clientSecret` → chart-owned Secret `<fullname>-operator-auth`, **or** `operator.authentication.existingSecret` (keys `existingSecretClientIdKey` = `clientId`, `existingSecretClientSecretKey` = `clientSecret`) | `OPERATOR__AUTHENTICATION__CLIENTID` / `__CLIENTSECRET` (secretKeyRef) |

The client must be a confidential `client_credentials` client with scope `octo_api` in that tenant (`octo-cli -c AddClientCredentialsClient`, without `--autoProvision`). Setting both credential sources, only one half of `clientId`/`clientSecret`, or credentials without a tenant id or issuer fails the render. Use a generated secret (e.g. `openssl rand -hex 32`): the pod carries a salted sha256 of the chart-owned credentials as a checksum annotation, so a change restarts the operator pod. An `existingSecret` must exist in the release namespace, otherwise the pod fails with `CreateContainerConfigError`; after rotating an `existingSecret`, restart the deployment manually.

### Forcing the classic watch mode (AB#6901)

| Value | Default | Environment variable |
|---|---|---|
| `operator.forceClassicWatch` | `false` | `OPERATOR__FORCECLASSICWATCH` (rendered only when `true`) |

The operator asks the API server for a consistent watch start and falls back to classic list+watch (`resourceVersion=0`) on its own when the API server refuses it (AB#6898). Setting `operator.forceClassicWatch: true` starts in classic mode from the first request and logs a WARN at startup. It is an incident lever for a cluster known to refuse the consistent start, not a default: leave it `false` elsewhere. The value must be `true` or `false` (a string `"false"` stays off, anything else fails the render); changing it restarts the operator pod. Enabling it on a cluster is a separate decision per cluster.

### Running multiple operators on one cluster (edge devices)

When deploying multiple operator instances onto the same Kubernetes cluster — typically one per target communication controller on an edge device — each instance must be isolated to its own namespace. Otherwise all operators watch every `DeploymentSite` CR cluster-wide and race on reconciliation.

Two values switch the chart from cluster-wide to namespace-scoped mode:

| Value | Default | Namespace-scoped mode |
|-------|---------|------------------------|
| `rbac.scope` | `cluster` | `namespace` — emits `Role` + `RoleBinding` in `.Release.Namespace` instead of `ClusterRole` + `ClusterRoleBinding` |
| `operator.watchNamespace` | _(empty — watch all)_ | namespace name — sets `OPERATOR__WATCHNAMESPACE`, restricting the CR watcher to that namespace |

Example: install one operator per target cluster, each into its own namespace:

```bash
helm install --namespace octo-mesh-test-2 --create-namespace \
  --set rbac.scope=namespace \
  --set operator.watchNamespace=octo-mesh-test-2 \
  octo-mesh-op-test-2 ./octo-mesh-communication-operator/

helm install --namespace octo-mesh-prod-1 --create-namespace \
  --set rbac.scope=namespace \
  --set operator.watchNamespace=octo-mesh-prod-1 \
  octo-mesh-op-prod-1 ./octo-mesh-communication-operator/
```

The two operators stay completely isolated — their RBAC reaches only their own namespace, and the watcher only sees `DeploymentSite` CRs in that namespace.

### Install Schema Provider

Schema Provider is a small container that provides construction kit schema files as a Web API.

### Create a value file to configure Schema Provider
See the [values.yaml](src/octo-mesh-schema-provider/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-schema-provider chart template locally and display the output

```bash
helm template --namespace octo --values schema-provider-sample.yaml schema-provider ../octo-mesh-schema-provider
```
## Release downtime of the Recreate services (identity, asset repository, bot, communication, platform services)

These services run with `recreateStrategy: true` (`strategy: Recreate`) because their command consumers declare
fixed-name **exclusive** RabbitMQ queues (`AddCommandConsumer`, `Temporary = true`): a second pod cannot declare the
queue while the old one holds it (`RESOURCE_LOCKED 405`), so a RollingUpdate or a second replica deadlocks
(reproduced on test-2, AB#6592). They are therefore down from the moment the old pod stops until the new pod is Ready.
Until the event hub no longer needs exclusive command queues, the chart shortens that window:

- **Image pre-pull** (`services.<key>.prePull.enabled`, default `false`): renders a DaemonSet `<service>-pre-pull`
  that pulls the service image onto every node (init container `/bin/true` + pause container). It only helps when
  it is rolled **before** the Deployment. The CD template `octo-mesh-deployment/pipelines/templates/helm-deploy-octo-mesh.yml`
  does that automatically: it renders `templates/pre-pull-daemonset.yaml`, applies it, waits for the DaemonSet rollout
  and only then runs `helm upgrade`. A cluster opts in through its values file, nothing else changes. Optional per
  service: `prePull.nodeSelector`, `prePull.tolerations`, `prePull.maxUnavailable` (default `100%`).
- **Faster Ready detection**: startup probe every 2 s (300 tries = the former 600 s budget) and readiness probe
  every 3 s with 10 failures (30 s tolerance as before) instead of 5 s / 10 s.

The application start itself is not shortened by the chart: the shared startup initialisation
(`DefaultConfigurationInitializationService` in `octo-common-services`) checks CK model upgrades, migrations and
bootstrap blueprints for every tenant before the host starts listening, so the time grows with the number of tenants.

Render tests (no cluster needed): `src/octo-mesh/tests/render-tests.sh`.
