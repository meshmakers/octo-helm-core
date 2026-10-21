# Changelog

## Unreleased

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
