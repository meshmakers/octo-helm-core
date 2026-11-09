# Changelog

## Unreleased

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
  First wave: `IdentityUsers1` (identity role and merge endpoints). Set per cluster at rollout in
  `octo-mesh-deployment/clusters/<c>/values-octo-mesh.yaml` (since = release delivery day; sunset = one week after the
  release runs on prod-1 and prod-2).

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
