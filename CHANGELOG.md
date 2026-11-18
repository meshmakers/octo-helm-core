# Changelog

## Unreleased

### Added (AB#9319)
- **octo-mesh: values `services.bot.indexUpgrade.schedule` (`Immediate` | `Window`), `.window.enabled`, `.window.cron`
  and `.window.maxDuration`.** Render `OCTO_INDEXUPGRADE__SCHEDULE`, `OCTO_INDEXUPGRADE__WINDOW__ENABLED`,
  `OCTO_INDEXUPGRADE__WINDOW__CRON` and `OCTO_INDEXUPGRADE__WINDOW__MAXDURATION` on the bot deployment, each only when
  set; unset (default) renders nothing and bot-services keeps its code default (Window, window off: no index is built),
  so no installation changes without a value. Invalid values, misspelled or unknown keys and `indexUpgrade` on another
  service fail the render, also with `services.bot.deploy: false`. Needed for the paging index upgrade of
  octo-bot-services AB#9118; production clusters are switched on only after the developer's go per cluster, the cluster
  values follow in `octo-mesh-deployment` (first test-2 with `schedule: Immediate`).
### Added (AB#9309)
- **octo-mesh: value `services.communication.hubAuthorization.adapterPoolMode` (`LogOnly` | `Enforce`).** Renders
  `OCTO_ADAPTERPOOLHUBAUTHORIZATION__MODE` on the communication controller only (`/adapterPoolHub` gate,
  `AdapterPoolHubAuthorization:Mode`); chart default `LogOnly`, identical to the code default, so no installation
  changes its behaviour without a value (the controller deployment gets the new variable and rolls once). Unset or
  empty renders `LogOnly`; any other value (also a YAML boolean) fails the render, also when the controller is not
  deployed. Unknown keys under `services.communication.hubAuthorization`, misplaced or misspelled pool hub keys under
  `services.communication` and such keys on any other service fail the render. Needed for the per-cluster switch to
  `Enforce` (AB#9199); the cluster values follow in `octo-mesh-deployment`.

### Added (AB#9310)
- **octo-mesh: value `services.assetRepository.enforceMutationScope` (`true` | `false`).** Renders
  `OCTO_GRAPHQL__ENFORCEMUTATIONSCOPE` (`GraphQl:EnforceMutationScope`, AB#4973) on the asset repository only; chart
  default `false`, identical to the service default (log-first), so no installation changes its behaviour without a
  value (the asset repository deployment gets the new variable and rolls once). Unset, null or empty renders `false`;
  anything but a YAML boolean fails the render, also when the asset repository is not deployed; a misspelled key under
  `services.assetRepository` and the key on any other service fail the render. Needed for the per-cluster switch
  (AB#9199); the cluster values follow in `octo-mesh-deployment`.

### Added (AB#9295)
- **octo-mesh: value `services.assetRepository.streamDataReadEnforcement` (`Off` | `Warn` | `Enforce`).** Renders
  `OCTO_STREAMDATAREADAUTHORIZATION__ROLEENFORCEMENT` on the asset repository only (stream-data read gate of
  octo-asset-repo-services AB#8559); chart default `Warn`, identical to the code default, so no installation changes
  its behaviour without a value (the asset repository deployment gets the new variable and rolls once). Unset or empty
  renders `Warn`; any other value fails the render, also when the asset repository is not deployed, and the key on any
  other service fails the render. Needed for the per-cluster switch to `Enforce` (AB#9199, switch plan AB#9296); the
  cluster values follow in `octo-mesh-deployment`.

### Added (AB#9027)
- **octo-mesh: value `tenantAuthorization.tenantGenerationEnforcement` (`LogOnly` | `Enforce` | `Disabled`) with the
  per-service override `services.<service>.tenantGenerationEnforcement`.** Renders
  `OCTO_TENANTAUTHORIZATION__TENANTGENERATIONENFORCEMENT` on identity, assetRepository, bot, communication and
  aiServices (the services that run the tenant generation check of octo-common-services AB#8999); chart default
  `LogOnly`, identical to the code default, so no installation changes without a value. Unset or empty renders
  `LogOnly` (override: the global value); any other value fails the render, also an override on a service without the
  check. Needed for switch S2 of the Enforce plan (AB#9000); the cluster values follow in `octo-mesh-deployment`.

### Added (AB#9017)
- **octo-mesh: identity values `services.identity.userTokenEnforcement` (`LogOnly` | `Enforce`) and
  `services.identity.serviceTokenEnforcement` (`LogOnly` | `Enforce` | `Disabled`).** Render
  `OCTO_TENANTAUTHORIZATION__USERTOKENENFORCEMENT` / `OCTO_TENANTAUTHORIZATION__SERVICETOKENENFORCEMENT` on the identity
  deployment; chart default `LogOnly` for both (the service's code default is `Enforce`). Invalid values fail the render.
  Needed before octo-identity-services #305, which turns on the tenant check of identity's own API (before #305 the
  values have no effect). Rollout plan, follow-up in `octo-mesh-deployment`: test-2 sets `Enforce`, staging-1/prod-1/prod-2
  keep `LogOnly` for the first release (AB#9000). An empty value renders `LogOnly`; a boolean or number fails the render
  (also for the existing assetRepository/communication `userTokenEnforcement`).
  `Disabled` (service tokens only) skips the check without logging and is an emergency exit only.

### Added (AB#8797)
- **octo-mesh: value `clusterDependencies.tenantDatabasePrefix`** (MongoDB tenant-database prefix, Epic AB#4944).
  Renders `OCTO_SYSTEM__TENANTDATABASEPREFIX` on every core service only when set; empty (default) renders nothing and
  every tenant database keeps its name. A second instance on the same MongoDB sets e.g. `dev_`: new tenants without an
  explicit database name get `dev_<tenantId>`, explicit names without the prefix are refused. Needs services with
  octo-construction-kit-engine-mongodb AB#8797.
- **octo-mesh-communication-operator: value `operator.clusterDependencies.tenantDatabasePrefix`.** Renders
  `OPERATOR__CLUSTERDEPENDENCIES__TENANTDATABASEPREFIX` only when set; the operator projects it into every workload as
  `clusterDependencies.tenantDatabasePrefix` (octo-communication-operator AB#8797). Mirror the core chart's value.

### Added (AB#8603)
- **octo-mesh: identity value `services.identity.methods.enablePasswordMethods` (`true` | `false`).** Renders
  `OCTO_Methods__Identity__EnablePasswordMethods` on the identity deployment only when set; unset keeps the service
  default (`false`). A non-boolean value fails the render. `true` offers the password/secret CK methods
  (`User.ChangePassword`, `User.SetPassword`, `User.ResetPassword`, `User.CreateUser`, `Client.AddSecret`,
  `Client.RemoveSecret`) on the bus for the GraphQL gateway. Switch per cluster with the cluster owner's go in
  `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml` (test-2 first).

### Added (AB#8415)
- **octo-mesh: REST deprecation wave dates `restDeprecation.waves.<wave>.since|sunset` (`yyyy-MM-dd`).** Renders
  `OCTO_RestDeprecation__Waves__<wave>__Since|Sunset` on every service only when set; the services send the
  `Deprecation` / `Sunset` headers of the REST endpoints marked with that wave (octo-common-services
  `docs/rest-deprecation.md`). Default `{}`: no variable, no date. An invalid wave name or date fails the render.
  First wave: `IdentityUsers1` (identity role and merge endpoints): since `2026-11-08` (first prod delivery of r3.5.68),
  sunset date to be announced (Gerald 2026-11-11: no fixed compatibility window, Gerald decides the date once the
  migration functions are implemented; until then `sunset` stays empty and no `Sunset` header is sent), set for all
  clusters in `octo-mesh-deployment/base/values-octo-mesh.yaml`.

### Added (AB#8305)
- **octo-mesh: identity value `services.identity.shadowUserCleanup` (`Off` | `DryRun` | `Apply`).** Renders
  `OCTO_IDENTITYAPIAUTHORIZATION__SHADOWUSERCLEANUP` on the identity deployment only when set; unset keeps the
  service default (`Off`). Invalid values fail the render. It removes rights-less `xt_` shadow users left over by
  refused token exchanges (see octo-identity-services); switch per cluster, `DryRun` first, in
  `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml`, and back to unset after `Apply`.

### Added (AB#8339)
- **octo-mesh: identity value `services.identity.crossTenantAncestry` (`Warn` | `Enforce`).** Renders
  `OCTO_IDENTITYAPIAUTHORIZATION__CROSSTENANTANCESTRY` on the identity deployment only when set; unset keeps the
  service default (`Warn`). Invalid values fail the render. `Enforce` lets only tenant-registry ancestors act as
  cross-tenant ancestors (see octo-identity-services); switch per cluster in
  `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml`.

### Added (AB#8280)
- **octo-mesh: CK method idempotency fingerprint key for the asset repository.** New values
  `services.assetRepository.methods.idempotency.fingerprint.currentId` (public key id) and
  `secrets.methodsFingerprintCurrentSecret` (base64 of at least 32 random bytes). The secret goes into the
  `<fullname>-backend` Secret and reaches only the asset repository as
  `OCTO_METHODS__IDEMPOTENCY__FINGERPRINT__CURRENT__ID` / `__SECRET` (`secretKeyRef`). Both unset (default) renders
  exactly as before; one without the other, a malformed id or a short/unresolved secret fails the render. All replicas
  share the key. Clusters set the id in `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml`; the secret comes from
  Vault at deploy time.

### Added (AB#8165)
- **octo-mesh: identity value `services.identity.adminRoleMigration` (`Off` | `DryRun` | `Apply`).** Renders
  `OCTO_IDENTITYAPIAUTHORIZATION__ADMINROLEMIGRATION` on the identity deployment only when set; unset keeps the
  service default (`Off`). Invalid values fail the render. It moves existing tenant admins from directly assigned
  roles to `TenantOwners` membership (see octo-identity-services); switch per cluster, `DryRun` first, in
  `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml`.

### Added (AB#8093)
- **octo-mesh: identity values `services.identity.secretManagementRoleEnforcement` (`Warn` | `Enforce`, AB#5861)
  and `services.identity.dataProtection.encryptExistingKeys` (`true` | `false`, AB#5530).** They render
  `OCTO_IDENTITYAPIAUTHORIZATION__SECRETMANAGEMENTROLEENFORCEMENT` and
  `OCTO_IDENTITY__DATAPROTECTION__ENCRYPTEXISTINGKEYS` on the identity deployment only when set; unset keeps the
  service defaults (`Warn`, `false`). Invalid values fail the render. Clusters switch them in
  `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml`.

### Security (AB#7265)
- **octo-mesh: the ingress no longer reflects the request `Origin` and no longer sets
  `Access-Control-Allow-Credentials: true`.** The former default `configuration-snippet` (commit df97f23, "Emit CORS headers on ingress error responses") set `Access-Control-Allow-Origin: $http_origin` + `Access-Control-Allow-Credentials: true` on every
  response of every host of the chart (connect, assets, bots, communication). Because tenant workloads run
  same-site (`<app>-<tenant>.<cluster-domain>`), any such page could read cookie-authenticated responses of
  logged-in users of other tenants. CORS for proxied responses is now solely the application's policy
  (known client origins, no credentials).
- New optional `ingress.cors.allowedOrigins` (default `[]`): exact SPA origins for which nginx adds
  `Access-Control-Allow-Origin: <origin>` (never credentials) and `Vary: Origin`, so the SPA still sees the real
  502/503 during a rollout. Entries are validated (no wildcards, paths or quotes). List only origins you control,
  e.g. `https://studio.<cluster-domain>`.
- Rollout: clusters get the fix with the next octo-mesh chart release; per-cluster values may set
  `ingress.cors.allowedOrigins` to keep readable 502/503 for Studio.
