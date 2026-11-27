#!/usr/bin/env bash
# Render tests for the octo-mesh and communication operator charts: image pre-pull and probe timing (AB#6592),
# hub authorization and operator credentials (AB#5930), SECRET missing-key guard (AB#5934),
# /metrics never routed through an ingress (AB#5868), removed identity license keys (AB#6726), user-token tenant gate mode (AB#6834), operator.forceClassicWatch (AB#6901),
# removed files migration settings (AB#7033), identity SecretManagement enforcement and Data Protection key encryption (AB#8093), identity admin role migration (AB#8165), CK method idempotency fingerprint key (AB#8280),
# REST deprecation wave dates (AB#8415), identity password methods switch (AB#8603), tenant-database prefix (AB#8797),
# identity tenant authorization modes (AB#9017), tenant generation check mode (AB#9027), stream-data read gate mode (AB#9295), bot index upgrade schedule (AB#9319),
# adapter pool hub mode (AB#9309), GraphQL mutation scope gate (AB#9310),
# runtime query time limit (AB#8897), operator LLM gateway default (AB#8452).
# Needs only `helm` (no cluster). Run from anywhere: src/octo-mesh/tests/render-tests.sh
set -euo pipefail
CHART="$(cd "$(dirname "$0")/.." && pwd)"
VALUES="$CHART/tests/values-minimal.yaml"
fail=0
render() { helm template t "$CHART" -f "$VALUES" "$@"; }
check() { # check <description> <command...>  (command must succeed)
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   - $d"; else echo "FAIL - $d"; fail=1; fi
}

renders_fail() { # renders_fail <description> <expected error text> <helm args...>  (render must fail with that text)
  local d="$1" msg="$2"; shift 2
  local err; err="$("$@" 2>&1 >/dev/null)" && { echo "FAIL - $d (render succeeded)"; fail=1; return; }
  if grep -qF -- "$msg" <<<"$err"; then echo "ok   - $d"; else echo "FAIL - $d (wrong error: $(head -c 200 <<<"$err"))"; fail=1; fi
}

# 1. Default: no pre-pull DaemonSet at all (off by default for every service)
check "default renders no DaemonSet"            bash -c "! helm template t '$CHART' -f '$VALUES' | grep -q '^kind: DaemonSet'"

# 2. Opt-in for identity only: exactly one DaemonSet, named <fullname>-pre-pull, with the service image
OUT="$(render --set services.identity.prePull.enabled=true --set imageDefaults.privateRegistry=registry.example.test --set appVersion=main-latest)"
check "identity prePull renders one DaemonSet"  test "$(grep -c '^kind: DaemonSet' <<<"$OUT")" = 1
check "DaemonSet is named *-identity-services-pre-pull" grep -q 'name: .*identity-services-pre-pull' <<<"$OUT"
check "pre-pull init image equals the Deployment image (2 occurrences)" test "$(grep -c 'image: "\?registry.example.test/meshmakers/octo-mesh-identity-services:main-latest"\?$' <<<"$OUT")" = 2
check "pre-pull rolls all nodes at once (maxUnavailable 100%)" grep -q 'maxUnavailable: 100%' <<<"$OUT"
check "pre-pull command is /bin/true"           grep -q 'command: \["/bin/true"\]' <<<"$OUT"

# 3. A digest-pinned image tag (test-2 CD) is carried over
OUT="$(render --set services.identity.prePull.enabled=true --set 'services.identity.image.tag=main-latest@sha256:abc')"
check "digest-pinned tag is used by the pre-pull" grep -q 'octo-mesh-identity-services:main-latest@sha256:abc' <<<"$OUT"

# 4. deploy=false suppresses the DaemonSet
OUT="$(render --set services.identity.prePull.enabled=true --set services.identity.deploy=false)"
check "deploy=false renders no DaemonSet"       test "$(grep -c '^kind: DaemonSet' <<<"$OUT")" = 0

# 5. All five Recreate services can opt in independently
OUT="$(render --set services.identity.prePull.enabled=true --set services.assetRepository.prePull.enabled=true \
  --set services.bot.prePull.enabled=true --set services.communication.prePull.enabled=true \
  --set services.platformServices.prePull.enabled=true)"
check "five opt-ins render five DaemonSets"     test "$(grep -c '^kind: DaemonSet' <<<"$OUT")" = 5

# 5a. AB#5114: ALLOWSECRETCLEARING is rendered only on the communication controller and only when enabled
check "default renders no ALLOWSECRETCLEARING"  bash -c "! helm template t '$CHART' -f '$VALUES' | grep -q 'ALLOWSECRETCLEARING'"
OUT="$(render --set services.communication.serviceAccountImpersonation.allowSecretClearing=true)"
check "enabled renders ALLOWSECRETCLEARING=true" test "$(grep -A1 'name: OCTO_SERVICEACCOUNTIMPERSONATION__ALLOWSECRETCLEARING' <<<"$OUT" | grep -c 'value: "true"')" = 1
check "enabled renders it exactly once"         test "$(grep -c 'ALLOWSECRETCLEARING' <<<"$OUT")" = 1

# 5b. Regression (test-2 2026-10-12): pre-pull pods must never match a workload Service selector, otherwise
#     they become Ready endpoints that answer nothing (502). The DaemonSet carries its own
#     app.kubernetes.io/service value, so no value used by a pre-pull doc may be used by another document.
OUT="$(render --set services.identity.prePull.enabled=true --set services.assetRepository.prePull.enabled=true \
  --set services.bot.prePull.enabled=true --set services.communication.prePull.enabled=true \
  --set services.platformServices.prePull.enabled=true)"
DS_VALUES="$(awk 'BEGIN{RS="\n---\n"} /\nkind: DaemonSet/ {n=split($0,l,"\n"); for(i=1;i<=n;i++) if(l[i] ~ /app.kubernetes.io\/service:/) {sub(/.*service: */,"",l[i]); print l[i]}}' <<<"$OUT" | sort -u)"
OTHER_VALUES="$(awk 'BEGIN{RS="\n---\n"} !/\nkind: DaemonSet/ {n=split($0,l,"\n"); for(i=1;i<=n;i++) if(l[i] ~ /app.kubernetes.io\/service:/) {sub(/.*service: */,"",l[i]); print l[i]}}' <<<"$OUT" | sort -u)"
check "pre-pull pods carry their own service label (5 values)" test "$(wc -l <<<"$DS_VALUES" | tr -d ' ')" = 5
check "no pre-pull label value is selected by a Service/Deployment" test -z "$(comm -12 <(echo "$DS_VALUES") <(echo "$OTHER_VALUES"))"

# 6. Recreate strategy is untouched, probe timing (AB#6592)
OUT="$(render)"
check "services keep strategy Recreate (5x)"    test "$(grep -c 'type: Recreate' <<<"$OUT")" = 5
check "startupProbe polls every 2s, 300 tries (600s budget)" test "$(grep -A5 'startupProbe' <<<"$OUT" | grep -c 'failureThreshold: 300')" = 5
check "readinessProbe polls every 3s, tolerates 30s" test "$(grep -A7 'readinessProbe' <<<"$OUT" | grep -c 'periodSeconds: 3')" -ge 5

# 7. AB#5930: hub authorization mode per hub (controller env), default LogOnly, anything else fails the render
mode() { grep -A1 "name: OCTO_$1HUBAUTHORIZATION__MODE" <<<"$OUT" | grep -o 'value: "[A-Za-z]*"'; }
OUT="$(render)"
check "hub mode defaults to LogOnly (adapter)"  test "$(mode ADAPTER)" = 'value: "LogOnly"'
check "hub mode defaults to LogOnly (operator)" test "$(mode OPERATOR)" = 'value: "LogOnly"'
OUT="$(render --set services.communication.hubAuthorization.adapterMode=Enforce)"
check "adapterMode=Enforce renders, operator stays LogOnly" test "$(mode ADAPTER) $(mode OPERATOR)" = 'value: "Enforce" value: "LogOnly"'
OUT="$(render --set services.communication.hubAuthorization.operatorMode=Enforce)"
check "operatorMode=Enforce renders, adapter stays LogOnly" test "$(mode ADAPTER) $(mode OPERATOR)" = 'value: "LogOnly" value: "Enforce"'
renders_fail "invalid adapterMode fails the render"  "adapterMode must be LogOnly or Enforce" render --set services.communication.hubAuthorization.adapterMode=Bogus
renders_fail "invalid operatorMode fails the render" "operatorMode must be LogOnly or Enforce" render --set services.communication.hubAuthorization.operatorMode=enforce

# 8. AB#5930/AB#5934: opt-in SECRET missing-key guard of the octo-mesh chart (secrets.secretEncryptionRequired)
KEY="$(printf '0123456789abcdef0123456789abcdef' | base64)"   # 32 bytes, dummy
check "guard is off by default: no key ring renders" render
check "guard=false without key renders"         render --set secrets.secretEncryptionRequired=false
renders_fail "guard=true without key fails the render" "SECRET key ring is empty" render --set secrets.secretEncryptionRequired=true
renders_fail "guard=true with unresolved Vault macro fails" "base64-encoded 32-byte key" render --set secrets.secretEncryptionRequired=true --set 'secrets.communicationInstanceSecretKey=$(VAULT_instance_secret_key)'
renders_fail "guard=\"yes\" is rejected"        "must be true or false" render --set secrets.secretEncryptionRequired=yes
check "guard=true with a valid key renders"     render --set secrets.secretEncryptionRequired=true --set "secrets.communicationInstanceSecretKey=$KEY"

# 9. AB#5930/AB#5934: communication operator chart (operator.authentication, clusterSecrets.secretEncryptionRequired).
#    The chart depends on file://../octo-mesh-crds, so it is rendered from a temp copy with the dependency built.
OPSRC="$CHART/../octo-mesh-communication-operator"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -R "$OPSRC" "$CHART/../octo-mesh-crds" "$TMP/"
helm dependency build "$TMP/octo-mesh-communication-operator" >/dev/null
op() { helm template o "$TMP/octo-mesh-communication-operator" --set operator.authUri=https://connect.example.test "$@"; }
AUTH=(--set operator.authentication.tenantId=octosystem --set operator.authentication.clientId=cid-render-test)

check "operator renders without authentication" op
check "no authentication => no OPERATOR__AUTHENTICATION env" bash -c "! helm template o '$TMP/octo-mesh-communication-operator' --set operator.authUri=https://connect.example.test | grep -q 'OPERATOR__AUTHENTICATION'"
OUT="$(op "${AUTH[@]}" --set operator.authentication.clientSecret=secret-render-A)"
check "client id/secret are referenced via secretKeyRef (2x)" test "$(grep -A4 -E 'name: OPERATOR__AUTHENTICATION__CLIENT(ID|SECRET)$' <<<"$OUT" | grep -c 'secretKeyRef:')" = 2
check "no literal value for the client id/secret env" test "$(grep -A1 -E 'name: OPERATOR__AUTHENTICATION__CLIENT(ID|SECRET)$' <<<"$OUT" | grep -c 'value:')" = 0
check "credential never appears in clear text"  bash -c '! grep -q -- "$1" <<<"$0"' "$OUT" secret-render-A
SUM_A="$(grep 'checksum/operator-authentication' <<<"$OUT")"
SUM_B="$(op "${AUTH[@]}" --set operator.authentication.clientSecret=secret-render-B | grep 'checksum/operator-authentication')"
check "checksum annotation is rendered"         test -n "$SUM_A"
check "checksum changes when the credential changes" test "$SUM_A" != "$SUM_B"
check "checksum is stable for the same credential" test "$SUM_A" = "$(op "${AUTH[@]}" --set operator.authentication.clientSecret=secret-render-A | grep 'checksum/operator-authentication')"
OUT="$(op --set operator.authentication.tenantId=octosystem --set operator.authentication.existingSecret=my-operator-auth)"
check "existingSecret is referenced by name"    grep -q 'name: "my-operator-auth"' <<<"$OUT"
check "existingSecret renders no chart-owned Secret" bash -c '! grep -q -- "-operator-auth$" <<<"$0"' "$OUT"
renders_fail "clientId without clientSecret fails"  "clientSecret is empty" op "${AUTH[@]}"
renders_fail "clientSecret without clientId fails"  "clientId is empty" op --set operator.authentication.clientSecret=x
renders_fail "existingSecret together with clientId fails" "not both" op "${AUTH[@]}" --set operator.authentication.existingSecret=s
renders_fail "credentials without tenantId fail"    "tenantId is required" op --set operator.authentication.clientId=c --set operator.authentication.clientSecret=s

check "operator guard off by default: no key ring renders" op
renders_fail "operator guard=true without key fails" "SECRET key ring is empty" op --set operator.clusterSecrets.secretEncryptionRequired=true
renders_fail "operator guard=true with unresolved Vault macro fails" "base64-encoded 32-byte key" op --set operator.clusterSecrets.secretEncryptionRequired=true --set 'operator.clusterSecrets.instanceSecretKey=$(VAULT_instance_secret_key)'
check "operator guard=true with a valid key renders" op --set operator.clusterSecrets.secretEncryptionRequired=true --set "operator.clusterSecrets.instanceSecretKey=$KEY"

# 9a. AB#6901: operator.forceClassicWatch -> OPERATOR__FORCECLASSICWATCH (operator AB#6898). Off by default.
check "forceClassicWatch default: no env rendered" bash -c "! helm template o '$TMP/octo-mesh-communication-operator' --set operator.authUri=https://connect.example.test | grep -q 'FORCECLASSICWATCH'"
check "forceClassicWatch=false: no env rendered"   bash -c "! helm template o '$TMP/octo-mesh-communication-operator' --set operator.authUri=https://connect.example.test --set operator.forceClassicWatch=false | grep -q 'FORCECLASSICWATCH'"
OUT="$(op --set operator.forceClassicWatch=true)"
check "forceClassicWatch=true renders OPERATOR__FORCECLASSICWATCH=true once" test "$(grep -A1 'name: OPERATOR__FORCECLASSICWATCH$' <<<"$OUT" | grep -c 'value: "true"')" = 1
check "forceClassicWatch=true renders the env exactly once" test "$(grep -c 'FORCECLASSICWATCH' <<<"$OUT")" = 1
check "forceClassicWatch string \"false\" stays off (not truthy)" bash -c "! helm template o '$TMP/octo-mesh-communication-operator' --set operator.authUri=https://connect.example.test --set-string operator.forceClassicWatch=false | grep -q 'FORCECLASSICWATCH'"
renders_fail "forceClassicWatch garbage value fails" "must be true or false" op --set operator.forceClassicWatch=yes

# 9b. AB#8452: operator.llmGatewayUrl -> OPERATOR__LLMGATEWAYURL (cluster default of the LLM gateway). Empty by default.
check "llmGatewayUrl default: no env rendered" bash -c "! helm template o '$TMP/octo-mesh-communication-operator' --set operator.authUri=https://connect.example.test | grep -q 'LLMGATEWAYURL'"
OUT="$(op --set operator.llmGatewayUrl=https://ai.test-2.mm.cloud)"
check "llmGatewayUrl renders OPERATOR__LLMGATEWAYURL with the value once" test "$(grep -A1 'name: OPERATOR__LLMGATEWAYURL$' <<<"$OUT" | grep -c 'value: "https://ai.test-2.mm.cloud"')" = 1
check "llmGatewayUrl with port and path renders" op --set operator.llmGatewayUrl=http://octo-ai.octo.svc.cluster.local:5019/base
renders_fail "llmGatewayUrl without scheme fails" "must be an absolute http(s) URL" op --set operator.llmGatewayUrl=ai.test-2.mm.cloud
renders_fail "llmGatewayUrl with another scheme fails" "must be an absolute http(s) URL" op --set operator.llmGatewayUrl=ftp://ai.test-2.mm.cloud

# 10. AB#5868: /metrics must not be reachable through the public ingress.
#     Layer 1 (services): /metrics only on a dedicated listener that no Service port and no Ingress backend names.
#     Layer 2 (ingress): nginx answers 404 for /metrics even if a service served it on the routed port.
ing()  { awk 'BEGIN{RS="\n---\n"} /\nkind: Ingress\n/' <<<"$OUT"; }
svc()  { awk 'BEGIN{RS="\n---\n"} /\nkind: Service\n/' <<<"$OUT"; }
OUT="$(render)"
check "ingress answers 404 for /metrics"        grep -qF 'if ($uri ~* "^/+metrics(/.*)?$") { return 404; }' <<<"$(ing)"
# AB#7265: the ingress must never reflect the Origin nor allow credentials
check "default ingress: no \$http_origin reflection"      bash -c '! grep -q "Access-Control-Allow-Origin: .*http_origin" <<<"$0"' "$(ing)"
check "default ingress: no Access-Control-Allow-Credentials" bash -c '! grep -qi "Access-Control-Allow-Credentials" <<<"$0"' "$(ing)"
check "default ingress: no Access-Control-Allow-Origin at all" bash -c '! grep -q "Access-Control-Allow-Origin" <<<"$0"' "$(ing)"
check "no ingress rule names a /metrics path"   bash -c '! grep -qi "path: /*metrics" <<<"$0"' "$(ing)"
check "every ingress backend uses the service port (80)" test "$(grep -c 'number: 80$' <<<"$(ing)")" = "$(grep -c 'number: ' <<<"$(ing)")"
check "default: no Prometheus env or listener"  bash -c '! grep -qE "Observability__PrometheusPort|http://\+:80;|name: metrics$" <<<"$0"' "$OUT"
check "default: ASPNETCORE_URLS is port 80 only (5x)" test "$(grep -A1 'name: ASPNETCORE_URLS' <<<"$OUT" | grep -c 'value: "http://+:80"')" = 5

# 10a. A cluster overlay that replaces the configuration-snippet cannot drop the guard
OUT="$(render --set-string 'ingress.annotations.nginx\.ingress\.kubernetes\.io/configuration-snippet=more_set_headers "X-Test: 1";')"
check "overridden snippet is kept"              grep -qF 'more_set_headers "X-Test: 1";' <<<"$(ing)"
check "overridden snippet still gets the guard" grep -qF 'return 404; }' <<<"$(ing)"
# ... and an overlay that sets no snippet at all (annotations without it) gets the guard as well
OUT="$(render --set ingress.annotations=null)"
check "no snippet in values: guard still rendered" grep -qF 'return 404; }' <<<"$(ing)"

# 10c. AB#7265: optional exact-match origin allowlist; never reflection, never credentials
OUT="$(render --set 'ingress.cors.allowedOrigins={https://studio.example.test,https://admin.example.test:8443}')"
check "allowlist: exact-match if for studio"    grep -qF 'if ($http_origin = "https://studio.example.test") {' <<<"$(ing)"
check "allowlist: ACAO is the literal origin"   grep -qF 'more_set_headers "Access-Control-Allow-Origin: https://studio.example.test" always;' <<<"$(ing)"
check "allowlist: second origin with port"      grep -qF 'more_set_headers "Access-Control-Allow-Origin: https://admin.example.test:8443" always;' <<<"$(ing)"
check "allowlist: Vary: Origin set via more_set_headers" test "$(grep -c 'more_set_headers "Vary: Origin" always;' <<<"$(ing)")" = 2
check "allowlist: no add_header (keeps inherited headers)" bash -c '! grep -q "add_header" <<<"$0"' "$(ing)"
check "allowlist: still no reflection"          bash -c '! grep -q "Access-Control-Allow-Origin: .*http_origin" <<<"$0"' "$(ing)"
check "allowlist: still no credentials"         bash -c '! grep -qi "Access-Control-Allow-Credentials" <<<"$0"' "$(ing)"
check "allowlist: metrics guard kept"           grep -qF 'return 404; }' <<<"$(ing)"
for bad in '*' 'https://*.example.test' 'https://a.example.test/path' 'http://x";}' 'studio.example.test'; do
  renders_fail "allowlist rejects '$bad'" "must be an exact origin" render --set-string "ingress.cors.allowedOrigins[0]=$bad"
done

# 10b. Opt-in internal listener: container port + env only, never a Service port or an ingress backend
OUT="$(render --set observability.prometheusPort=9464)"
check "prometheusPort adds the internal listener to ASPNETCORE_URLS (5x)" test "$(grep -c 'value: "http://+:80;http://+:9464"' <<<"$OUT")" = 5
check "prometheusPort sets Observability__PrometheusPort (5x)" test "$(grep -A1 'name: Observability__PrometheusPort' <<<"$OUT" | grep -c 'value: "9464"')" = 5
check "prometheusPort renders a metrics container port (5x)" test "$(grep -c 'containerPort: 9464' <<<"$OUT")" = 5
check "no Service exposes the metrics port"     bash -c '! grep -q 9464 <<<"$0"' "$(svc)"
check "no ingress backend uses the metrics port" bash -c '! grep -q 9464 <<<"$0"' "$(ing)"
check "ingress guard is still rendered with the listener on" grep -qF 'return 404; }' <<<"$(ing)"

# 11. AB#6726: the identity service no longer reads IdentityServerLicenseKey / AutoMapperLicenseKey
OUT="$(render)"
check "identity renders no license key env vars" bash -c '! grep -qiE "IdentityServerLicenseKey|AutoMapperLicenseKey" <<<"$0"' "$OUT"
check "identity env block is still rendered (INSTANCEPREFIX)" grep -q 'name: OCTO_IDENTITY__INSTANCEPREFIX' <<<"$OUT"
# A pipeline that still passes the removed values must not break the render, and must not bring the env vars back
OUT="$(render --set services.identity.identityServerLicenseKey=x --set services.identity.autoMapperLicenseKey=y)"
check "old --set license values render without error" test -n "$OUT"
check "old --set license values are ignored"     bash -c '! grep -qiE "LicenseKey" <<<"$0"' "$OUT"

# 12. AB#6834: user-token tenant gate mode on assetRepository and communication (identity: section 12a), default LogOnly
V=OCTO_TENANTAUTHORIZATION__USERTOKENENFORCEMENT
dep() { awk -v n="$1" 'BEGIN{RS="\n---\n"} /\nkind: Deployment\n/ && $0 ~ ("name: [^\n]*" n "\n")' <<<"$OUT"; }
gate() { grep -A1 "name: $V" <<<"$(dep "$1")" | grep -o 'value: "[A-Za-z]*"' | tr '\n' ' '; }
OUT="$(render)"
check "gate mode defaults to LogOnly (asset repository)" test "$(gate asset-rep-services)" = 'value: "LogOnly" '
check "gate mode defaults to LogOnly (communication)"    test "$(gate communication-controller-services)" = 'value: "LogOnly" '
check "default renders the variable three times (with identity)" test "$(grep -c "name: $V" <<<"$OUT")" = 3
OUT="$(render --set services.assetRepository.userTokenEnforcement=Enforce)"
check "assetRepository=Enforce renders, communication stays LogOnly" test "$(gate asset-rep-services)$(gate communication-controller-services)" = 'value: "Enforce" value: "LogOnly" '
OUT="$(render --set services.communication.userTokenEnforcement=Enforce)"
check "communication=Enforce renders, asset repository stays LogOnly" test "$(gate asset-rep-services)$(gate communication-controller-services)" = 'value: "LogOnly" value: "Enforce" '
OUT="$(render --set services.assetRepository.userTokenEnforcement=LogOnly --set services.communication.userTokenEnforcement=LogOnly)"
check "explicit LogOnly: asset, communication and identity default LogOnly" test "$(grep -A1 "name: $V" <<<"$OUT" | grep -c 'value: "LogOnly"')" = 3
OUT="$(render --set services.assetRepository.userTokenEnforcement=Enforce --set services.communication.userTokenEnforcement=Enforce)"
check "asset+communication Enforce render Enforce, identity stays LogOnly" test "$(grep -A1 "name: $V" <<<"$OUT" | grep -c 'value: "Enforce"')$(gate identity)" = '2value: "LogOnly" '
for svc in bot platform; do
  check "$svc deployment carries no gate variable" bash -c '! grep -q "$1" <<<"$0"' "$(dep "$svc")" "$V"
done
check "identity deployment was found (test is not vacuous)" test -n "$(dep identity)"
check "variable only inside the three deployments"       test "$(grep -c "name: $V" <<<"$(dep asset-rep-services)$(dep communication-controller-services)$(dep identity)")" = 3
renders_fail "invalid asset repository value fails the render" "services.assetRepository.userTokenEnforcement must be LogOnly or Enforce" render --set services.assetRepository.userTokenEnforcement=Bogus
renders_fail "invalid communication value fails the render"    "services.communication.userTokenEnforcement must be LogOnly or Enforce" render --set services.communication.userTokenEnforcement=enforce

# 12a. AB#9017 (AB#9000): identity renders both tenant authorization modes, chart default LogOnly
S=OCTO_TENANTAUTHORIZATION__SERVICETOKENENFORCEMENT
mode() { grep -A1 "name: $1" <<<"$(dep identity)" | grep -o 'value: "[A-Za-z]*"' | tr '\n' ' '; }
OUT="$(render)"
check "identity user-token mode defaults to LogOnly"     test "$(mode $V)" = 'value: "LogOnly" '
check "identity service-token mode defaults to LogOnly"  test "$(mode $S)" = 'value: "LogOnly" '
check "service-token mode is rendered only on identity"  test "$(grep -c "name: $S" <<<"$OUT")" = 1
OUT="$(render --set services.identity.userTokenEnforcement=Enforce --set services.identity.serviceTokenEnforcement=Enforce)"
check "identity Enforce/Enforce renders both"            test "$(mode $V)$(mode $S)" = 'value: "Enforce" value: "Enforce" '
check "identity Enforce leaves asset repository LogOnly" test "$(gate asset-rep-services)" = 'value: "LogOnly" '
OUT="$(render --set services.identity.userTokenEnforcement=LogOnly --set services.identity.serviceTokenEnforcement=LogOnly)"
check "identity explicit LogOnly/LogOnly renders both"   test "$(mode $V)$(mode $S)" = 'value: "LogOnly" value: "LogOnly" '
OUT="$(render --set services.identity.serviceTokenEnforcement=Disabled)"
check "identity service-token Disabled renders"          test "$(mode $S)" = 'value: "Disabled" '
renders_fail "invalid identity user-token value fails the render"    "services.identity.userTokenEnforcement must be LogOnly or Enforce" render --set services.identity.userTokenEnforcement=Disabled
renders_fail "invalid identity service-token value fails the render" "services.identity.serviceTokenEnforcement must be LogOnly, Enforce or Disabled" render --set services.identity.serviceTokenEnforcement=enforce
# A YAML boolean or number must fail instead of silently becoming LogOnly; "" or null keep the chart default
renders_fail "identity user-token false fails the render"     "services.identity.userTokenEnforcement must be LogOnly or Enforce, got 'false'" render --set services.identity.userTokenEnforcement=false
renders_fail "identity service-token 0 fails the render"      "services.identity.serviceTokenEnforcement must be LogOnly, Enforce or Disabled, got '0'" render --set services.identity.serviceTokenEnforcement=0
renders_fail "asset repository user-token false fails the render" "services.assetRepository.userTokenEnforcement must be LogOnly or Enforce, got 'false'" render --set services.assetRepository.userTokenEnforcement=false
OUT="$(render --set services.identity.userTokenEnforcement= --set services.identity.serviceTokenEnforcement=null)"
check "identity empty/null values fall back to LogOnly"  test "$(mode $V)$(mode $S)" = 'value: "LogOnly" value: "LogOnly" '

# 13. Bot artifact store S3: the CrateDB-side endpoint is rendered only when set
S3="--set services.bot.artifactStorage.provider=S3 --set services.bot.artifactStorage.s3.bucket=b --set services.bot.artifactStorage.s3.serviceUrl=http://store.example.test:8333"
OUT="$(render $S3)"
check "S3 without crateDbServiceUrl renders the service URL"  grep -q 'name: OCTO_ARTIFACTSTORAGE__S3__SERVICEURL' <<<"$OUT"
check "S3 without crateDbServiceUrl renders no CRATEDBSERVICEURL" bash -c '! grep -q "OCTO_ARTIFACTSTORAGE__S3__CRATEDBSERVICEURL" <<<"$0"' "$OUT"
OUT="$(render $S3 --set services.bot.artifactStorage.s3.crateDbServiceUrl=http://store.crate.test:8333)"
check "S3 with crateDbServiceUrl renders CRATEDBSERVICEURL once" test "$(grep -c 'name: OCTO_ARTIFACTSTORAGE__S3__CRATEDBSERVICEURL' <<<"$OUT")" = 1
check "CRATEDBSERVICEURL carries the value"                   test "$(grep -A1 'name: OCTO_ARTIFACTSTORAGE__S3__CRATEDBSERVICEURL' <<<"$OUT" | grep -c 'value: "http://store.crate.test:8333"')" = 1
check "the bot's own SERVICEURL is unchanged"                 grep -q 'value: "http://store.example.test:8333"' <<<"$OUT"
OUT="$(render --set services.bot.artifactStorage.provider=FileSystem --set services.bot.artifactStorage.fileSystem.rootPath=/data/a --set services.bot.artifactStorage.s3.crateDbServiceUrl=http://store.crate.test:8333)"
check "FileSystem provider ignores crateDbServiceUrl"          bash -c '! grep -q "OCTO_ARTIFACTSTORAGE__S3__CRATEDBSERVICEURL" <<<"$0"' "$OUT"

# 14. Removed files migration (AB#7033): a cluster value left over from the rollout renders nothing
OUT="$(render --set services.assetRepository.filesMigration.sweepEnabled=true --set 'services.assetRepository.filesMigration.sweepTenants[0]=t1')"
check "asset repository deployment was found (test is not vacuous)" grep -q 'asset-rep-services' <<<"$OUT"
check "leftover filesMigration value renders no OCTO_FilesMigration variable" bash -c '! grep -qi "OCTO_FilesMigration" <<<"$0"' "$OUT"

# 15. AB#8093: identity SecretManagement enforcement (AB#5861) and Data Protection key encryption (AB#5530),
#     rendered on the identity deployment only when set
SM=OCTO_IDENTITYAPIAUTHORIZATION__SECRETMANAGEMENTROLEENFORCEMENT
DPK=OCTO_IDENTITY__DATAPROTECTION__ENCRYPTEXISTINGKEYS
idval() { grep -A1 "name: $1" <<<"$(dep identity)" | grep -o 'value: "[A-Za-z]*"' | tr '\n' ' '; }
OUT="$(render)"
check "identity deployment was found (AB#8093 test is not vacuous)" test -n "$(dep identity)"
check "unset secretManagementRoleEnforcement renders no variable" bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$SM"
check "unset encryptExistingKeys renders no variable"             bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$DPK"
OUT="$(render --set services.identity.secretManagementRoleEnforcement=Enforce)"
check "secretManagementRoleEnforcement=Enforce renders Enforce on identity" test "$(idval $SM)" = 'value: "Enforce" '
check "secretManagementRoleEnforcement renders exactly once"      test "$(grep -c "name: $SM" <<<"$OUT")" = 1
OUT="$(render --set services.identity.secretManagementRoleEnforcement=Warn)"
check "secretManagementRoleEnforcement=Warn renders Warn"         test "$(idval $SM)" = 'value: "Warn" '
OUT="$(render --set services.identity.dataProtection.encryptExistingKeys=true)"
check "encryptExistingKeys=true renders true on identity"         test "$(idval $DPK)" = 'value: "true" '
check "encryptExistingKeys renders exactly once"                  test "$(grep -c "name: $DPK" <<<"$OUT")" = 1
OUT="$(render --set services.identity.dataProtection.encryptExistingKeys=false)"
check "encryptExistingKeys=false renders false (explicit value)"  test "$(idval $DPK)" = 'value: "false" '
renders_fail "invalid secretManagementRoleEnforcement fails the render" "services.identity.secretManagementRoleEnforcement must be Warn or Enforce" render --set services.identity.secretManagementRoleEnforcement=enforce
renders_fail "secretManagementRoleEnforcement=false fails the render" "services.identity.secretManagementRoleEnforcement must be Warn or Enforce" render --set services.identity.secretManagementRoleEnforcement=false
renders_fail "secretManagementRoleEnforcement=0 fails the render"     "services.identity.secretManagementRoleEnforcement must be Warn or Enforce" render --set services.identity.secretManagementRoleEnforcement=0
OUT="$(render --set-string services.identity.secretManagementRoleEnforcement=)"
check "explicit empty secretManagementRoleEnforcement renders no variable" bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$SM"
renders_fail "non-boolean encryptExistingKeys fails the render"  "services.identity.dataProtection.encryptExistingKeys must be true or false" render --set-string services.identity.dataProtection.encryptExistingKeys=yes

# 16. AB#8165: identity admin role migration mode, rendered on the identity deployment only when set
AM=OCTO_IDENTITYAPIAUTHORIZATION__ADMINROLEMIGRATION
OUT="$(render)"
check "unset adminRoleMigration renders no variable"              bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$AM"
for MODE in Off DryRun Apply; do
  OUT="$(render --set services.identity.adminRoleMigration=$MODE)"
  check "adminRoleMigration=$MODE renders $MODE on identity"      test "$(idval $AM)" = "value: \"$MODE\" "
  check "adminRoleMigration=$MODE renders exactly once"           test "$(grep -c "name: $AM" <<<"$OUT")" = 1
done
renders_fail "invalid adminRoleMigration fails the render"  "services.identity.adminRoleMigration must be Off, DryRun or Apply" render --set services.identity.adminRoleMigration=apply
renders_fail "adminRoleMigration=false fails the render"    "services.identity.adminRoleMigration must be Off, DryRun or Apply" render --set services.identity.adminRoleMigration=false
OUT="$(render --set-string services.identity.adminRoleMigration=)"
check "explicit empty adminRoleMigration renders no variable"     bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$AM"
# YAML 1.1 reads an unquoted Off as boolean false: a values file must quote it
AMFILE="$(mktemp)"
printf 'services:\n  identity:\n    adminRoleMigration: "Off"\n' > "$AMFILE"
OUT="$(render -f "$AMFILE")"
check "values file with adminRoleMigration: \"Off\" renders Off"  test "$(idval $AM)" = 'value: "Off" '
printf 'services:\n  identity:\n    adminRoleMigration: Off\n' > "$AMFILE"
renders_fail "unquoted Off in a values file (YAML boolean) fails the render" "services.identity.adminRoleMigration must be Off, DryRun or Apply" render -f "$AMFILE"
rm -f "$AMFILE"

# 17. AB#8305: identity shadow user cleanup mode, rendered on the identity deployment only when set
SU=OCTO_IDENTITYAPIAUTHORIZATION__SHADOWUSERCLEANUP
OUT="$(render)"
check "unset shadowUserCleanup renders no variable"               bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$SU"
for MODE in Off DryRun Apply; do
  OUT="$(render --set services.identity.shadowUserCleanup=$MODE)"
  check "shadowUserCleanup=$MODE renders $MODE on identity"       test "$(idval $SU)" = "value: \"$MODE\" "
  check "shadowUserCleanup=$MODE renders exactly once"            test "$(grep -c "name: $SU" <<<"$OUT")" = 1
done
renders_fail "invalid shadowUserCleanup fails the render"   "services.identity.shadowUserCleanup must be Off, DryRun or Apply" render --set services.identity.shadowUserCleanup=apply
renders_fail "shadowUserCleanup=false fails the render"     "services.identity.shadowUserCleanup must be Off, DryRun or Apply" render --set services.identity.shadowUserCleanup=false
OUT="$(render --set-string services.identity.shadowUserCleanup=)"
check "explicit empty shadowUserCleanup renders no variable"      bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$SU"
SUFILE="$(mktemp)"
printf 'services:\n  identity:\n    shadowUserCleanup: "Off"\n' > "$SUFILE"
OUT="$(render -f "$SUFILE")"
check "values file with shadowUserCleanup: \"Off\" renders Off"   test "$(idval $SU)" = 'value: "Off" '
printf 'services:\n  identity:\n    shadowUserCleanup: Off\n' > "$SUFILE"
renders_fail "unquoted shadowUserCleanup Off (YAML boolean) fails the render" "services.identity.shadowUserCleanup must be Off, DryRun or Apply" render -f "$SUFILE"
rm -f "$SUFILE"

# 13. AB#8280: CK method idempotency fingerprint key, asset repository only, id + secret together or not at all
FPID=services.assetRepository.methods.idempotency.fingerprint.currentId
FPS=secrets.methodsFingerprintCurrentSecret
FPKEY="$(printf '0123456789abcdef0123456789abcdef' | base64)"   # 32 bytes, dummy
OUT="$(render)"
check "default renders no fingerprint variable"  bash -c '! grep -q "METHODS__IDEMPOTENCY" <<<"$0"' "$OUT"
check "default renders no fingerprint secret key" bash -c '! grep -q "methodsFingerprintCurrentSecret" <<<"$0"' "$OUT"
renders_fail "id without secret fails the render"  "currentId is set but secrets.methodsFingerprintCurrentSecret is empty" render --set "$FPID=t2-2026-11"
renders_fail "secret without id fails the render"  "methodsFingerprintCurrentSecret is set but" render --set "$FPS=$FPKEY"
renders_fail "malformed id fails the render"       "must be 1-64 characters of A-Za-z0-9._-" render --set "$FPID=bad id!" --set "$FPS=$FPKEY"
renders_fail "unresolved Vault macro fails the render" "must be base64 of at least 32 random bytes" render --set "$FPID=t2-2026-11" --set "$FPS"='$(VAULT_methods_fingerprint_current_secret)'
renders_fail "secret shorter than 32 bytes fails the render" "must be base64 of at least 32 random bytes" render --set "$FPID=t2-2026-11" --set "$FPS=$(printf 'short' | base64)"
renders_fail "malformed base64 'a' fails the render" "must be base64 of at least 32 random bytes" render --set "$FPID=t2-2026-11" --set "$FPS=a"
renders_fail "non-canonical base64 (long, bad padding) fails the render" "must be base64 of at least 32 random bytes" render --set "$FPID=t2-2026-11" --set "$FPS=$(printf 'A%.0s' {1..45})"
OUT="$(render --set "$FPID=t2-2026-11" --set "$FPS=$FPKEY")"
check "id and secret render the id variable once (asset repository only)" test "$(grep -c 'name: OCTO_METHODS__IDEMPOTENCY__FINGERPRINT__CURRENT__ID' <<<"$OUT")" = 1
check "id variable carries the key id"           bash -c 'grep -A1 "name: OCTO_METHODS__IDEMPOTENCY__FINGERPRINT__CURRENT__ID" <<<"$0" | grep -q "value: \"t2-2026-11\""' "$OUT"
check "secret variable comes from secretKeyRef"  bash -c 'grep -A4 "name: OCTO_METHODS__IDEMPOTENCY__FINGERPRINT__CURRENT__SECRET" <<<"$0" | grep -q "key: methodsFingerprintCurrentSecret"' "$OUT"
check "backend Secret carries the secret key"    grep -q '^  methodsFingerprintCurrentSecret: ' <<<"$OUT"
check "the secret value never appears in clear"  bash -c '! grep -qF "$1" <<<"$0"' "$OUT" "$FPKEY"
FPDEP="$(awk 'BEGIN{RS="\n---\n"} /\nkind: Deployment\n/ && $0 ~ /name: [^\n]*asset-rep-services\n/' <<<"$OUT")"
check "the variable is on the asset repository deployment" grep -q 'METHODS__IDEMPOTENCY__FINGERPRINT__CURRENT__ID' <<<"$FPDEP"
OUT="$(render --set "$FPID=t2-2026-11" --set "$FPS=$FPKEY" --set services.assetRepository.replicaCount=2)"
check "replicaCount 2 renders 2 replicas on the asset repository" bash -c 'awk "BEGIN{RS=\"\\n---\\n\"} /asset-rep-services/ && /kind: Deployment/" <<<"$0" | grep -q "replicas: 2"' "$OUT"

# 18. AB#8339: identity cross-tenant ancestry mode, rendered on the identity deployment only when set
CA=OCTO_IDENTITYAPIAUTHORIZATION__CROSSTENANTANCESTRY
OUT="$(render)"
check "unset crossTenantAncestry renders no variable"              bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$CA"
for MODE in Warn Enforce; do
  OUT="$(render --set services.identity.crossTenantAncestry=$MODE)"
  check "crossTenantAncestry=$MODE renders $MODE on identity"      test "$(idval $CA)" = "value: \"$MODE\" "
  check "crossTenantAncestry=$MODE renders exactly once"           test "$(grep -c "name: $CA" <<<"$OUT")" = 1
done
renders_fail "invalid crossTenantAncestry fails the render"  "services.identity.crossTenantAncestry must be Warn or Enforce" render --set services.identity.crossTenantAncestry=enforce
renders_fail "crossTenantAncestry=true fails the render"     "services.identity.crossTenantAncestry must be Warn or Enforce" render --set services.identity.crossTenantAncestry=true
OUT="$(render --set-string services.identity.crossTenantAncestry=)"
check "explicit empty crossTenantAncestry renders no variable"     bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$CA"

# 19. AB#8415: REST deprecation wave dates, rendered on every service only when set
RD=OCTO_RestDeprecation__Waves__IdentityUsers1
OUT="$(render)"
check "no wave dates render no RestDeprecation variable"           bash -c '! grep -q "OCTO_RestDeprecation__" <<<"$0"' "$OUT"
OUT="$(render --set-string restDeprecation.waves.IdentityUsers1.since=2026-12-01)"
check "since only renders Since on every deployment"               test "$(grep -c "name: ${RD}__Since" <<<"$OUT")" = "$(grep -c '^kind: Deployment' <<<"$OUT")"
check "since only renders no Sunset"                               bash -c '! grep -q "$1__Sunset" <<<"$0"' "$OUT" "$RD"
check "Since carries the date"                                     bash -c 'grep -A1 "name: $1__Since" <<<"$0" | grep -q "value: \"2026-12-01\""' "$OUT" "$RD"
OUT="$(render --set-string restDeprecation.waves.IdentityUsers1.since=2026-12-01 --set-string restDeprecation.waves.IdentityUsers1.sunset=2027-01-15)"
check "sunset renders Sunset with the date"                        bash -c 'grep -A1 "name: $1__Sunset" <<<"$0" | grep -q "value: \"2027-01-15\""' "$OUT" "$RD"
OUT="$(render --set-string restDeprecation.waves.IdentityUsers1.since=)"
check "explicit empty date renders no variable"                    bash -c '! grep -q "OCTO_RestDeprecation__" <<<"$0"' "$OUT"
renders_fail "wave name with a dash fails the render"  "wave name 'identity-users-1' must consist of letters and digits" render --set-string restDeprecation.waves.identity-users-1.since=2026-12-01
renders_fail "malformed date fails the render"         "restDeprecation.waves.IdentityUsers1.sunset must be a date yyyy-MM-dd, got '15.01.2027'" render --set-string restDeprecation.waves.IdentityUsers1.sunset=15.01.2027

# 20. AB#8603: identity password methods on the bus, rendered on the identity deployment only when set
PM=OCTO_Methods__Identity__EnablePasswordMethods
OUT="$(render)"
check "identity deployment was found (AB#8603 test is not vacuous)" test -n "$(dep identity)"
check "unset enablePasswordMethods renders no variable"            bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$PM"
OUT="$(render --set services.identity.methods.enablePasswordMethods=true)"
check "enablePasswordMethods=true renders true on identity"        test "$(idval $PM)" = 'value: "true" '
check "enablePasswordMethods renders exactly once"                 test "$(grep -c "name: $PM" <<<"$OUT")" = 1
OUT="$(render --set services.identity.methods.enablePasswordMethods=false)"
check "enablePasswordMethods=false renders false (explicit value)" test "$(idval $PM)" = 'value: "false" '
renders_fail "non-boolean enablePasswordMethods fails the render"  "services.identity.methods.enablePasswordMethods must be true or false" render --set-string services.identity.methods.enablePasswordMethods=yes
renders_fail "enablePasswordMethods=1 fails the render"            "services.identity.methods.enablePasswordMethods must be true or false" render --set services.identity.methods.enablePasswordMethods=1
PMFILE="$(mktemp)"
printf 'services:\n  identity:\n    methods:\n      enablePasswordMethods: true\n' > "$PMFILE"
OUT="$(render -f "$PMFILE")"
check "values file with enablePasswordMethods: true renders true"  test "$(idval $PM)" = 'value: "true" '
printf 'services:\n  identity:\n    methods:\n      enablePasswordMethods: "true"\n' > "$PMFILE"
renders_fail "quoted \"true\" in a values file fails the render"     "services.identity.methods.enablePasswordMethods must be true or false" render -f "$PMFILE"
rm -f "$PMFILE"

# 21. AB#8797: MongoDB tenant-database prefix on every core service and on the operator, only when set
TP=OCTO_SYSTEM__TENANTDATABASEPREFIX
OUT="$(render)"
check "asset repository deployment was found (AB#8797 test is not vacuous)" test -n "$(dep asset-rep-services)"
check "unset tenantDatabasePrefix renders no variable"             bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$TP"
OUT="$(render --set clusterDependencies.tenantDatabasePrefix=dev_)"
check "tenantDatabasePrefix renders on the asset repository"       bash -c 'grep -A1 "name: $1" <<<"$0" | grep -q "value: \"dev_\""' "$(dep asset-rep-services)" "$TP"
check "tenantDatabasePrefix renders on identity"                    bash -c 'grep -A1 "name: $1" <<<"$0" | grep -q "value: \"dev_\""' "$(dep identity)" "$TP"
check "tenantDatabasePrefix renders on every system-env service"    test "$(grep -c "name: $TP" <<<"$OUT")" = "$(grep -c 'name: OCTO_SYSTEM__SYSTEMDATABASENAME' <<<"$OUT")"
OP_TP=OPERATOR__CLUSTERDEPENDENCIES__TENANTDATABASEPREFIX
check "operator: unset tenantDatabasePrefix renders no variable"   bash -c '! grep -q "$1" <<<"$0"' "$(op)" "$OP_TP"
check "operator: tenantDatabasePrefix renders the variable"         bash -c 'grep -A1 "name: $1" <<<"$0" | grep -q "value: \"dev_\""' "$(op --set operator.clusterDependencies.tenantDatabasePrefix=dev_)" "$OP_TP"

# 22. AB#9027 (AB#9000 switch S2): tenant generation check mode on every service that runs the check
G=OCTO_TENANTAUTHORIZATION__TENANTGENERATIONENFORCEMENT
AI=(--set services.aiServices.deploy=true --set services.aiServices.publicUri=https://ai.example.test)
gen() { grep -A1 "name: $G" <<<"$(dep "$1")" | grep -o 'value: "[A-Za-z]*"' | tr '\n' ' '; }
gens() { echo "$(gen identity)$(gen asset-rep-services)$(gen bot-services)$(gen communication-controller-services)$(gen ai-services)"; }
all() { local i; for i in 1 2 3 4 5; do printf 'value: "%s" ' "$1"; done; }
OUT="$(render "${AI[@]}")"
check "AB#9027 deployments were found (test is not vacuous)"     test -n "$(dep identity)" -a -n "$(dep ai-services)" -a -n "$(dep bot-services)"
check "default renders LogOnly on the five services"           test "$(gens)" = "$(all LogOnly)"
check "rendered exactly five times (not on platform/studio)"   test "$(grep -c "name: $G" <<<"$OUT")" = 5
check "platform services renders no generation mode"           test -z "$(gen platform-services)"
OUT="$(render "${AI[@]}" --set tenantAuthorization.tenantGenerationEnforcement=Enforce)"
check "global Enforce renders Enforce on the five services"    test "$(gens)" = "$(all Enforce)"
OUT="$(render "${AI[@]}" --set tenantAuthorization.tenantGenerationEnforcement=LogOnly)"
check "global explicit LogOnly renders LogOnly"                test "$(gens)" = "$(all LogOnly)"
OUT="$(render "${AI[@]}" --set tenantAuthorization.tenantGenerationEnforcement=Disabled)"
check "global Disabled renders Disabled"                       test "$(gens)" = "$(all Disabled)"
OUT="$(render "${AI[@]}" --set 'tenantAuthorization.tenantGenerationEnforcement=')"
check "global empty renders LogOnly"                           test "$(gens)" = "$(all LogOnly)"
OUT="$(render "${AI[@]}" --set tenantAuthorization.tenantGenerationEnforcement=Enforce --set services.bot.tenantGenerationEnforcement=LogOnly)"
check "per-service override wins (bot LogOnly, rest Enforce)"  test "$(gens)" = 'value: "Enforce" value: "Enforce" value: "LogOnly" value: "Enforce" value: "Enforce" '
OUT="$(render "${AI[@]}" --set services.identity.tenantGenerationEnforcement=Enforce)"
check "identity override Enforce, rest default LogOnly"        test "$(gens)" = 'value: "Enforce" value: "LogOnly" value: "LogOnly" value: "LogOnly" value: "LogOnly" '
OUT="$(render "${AI[@]}" --set tenantAuthorization.tenantGenerationEnforcement=Enforce --set 'services.communication.tenantGenerationEnforcement=')"
check "empty override takes the global value"                  test "$(gen communication-controller-services)" = 'value: "Enforce" '
renders_fail "invalid global value fails the render"           "tenantAuthorization.tenantGenerationEnforcement must be LogOnly, Enforce or Disabled, got 'enforce'" render --set tenantAuthorization.tenantGenerationEnforcement=enforce
renders_fail "global boolean fails the render"                 "tenantAuthorization.tenantGenerationEnforcement must be LogOnly, Enforce or Disabled, got 'false'" render --set tenantAuthorization.tenantGenerationEnforcement=false
renders_fail "invalid override fails the render"               "services.assetRepository.tenantGenerationEnforcement must be LogOnly, Enforce or Disabled, got 'On'" render --set services.assetRepository.tenantGenerationEnforcement=On
renders_fail "invalid global fails even when overridden"       "tenantAuthorization.tenantGenerationEnforcement must be LogOnly, Enforce or Disabled, got 'Yes'" render --set tenantAuthorization.tenantGenerationEnforcement=Yes --set services.identity.tenantGenerationEnforcement=Enforce
renders_fail "override on platform services fails the render"  "services.platformServices.tenantGenerationEnforcement is not supported" render --set services.platformServices.tenantGenerationEnforcement=Enforce
renders_fail "override on studio fails the render"            "services.studio.tenantGenerationEnforcement is not supported" render --set services.studio.tenantGenerationEnforcement=Enforce
renders_fail "invalid override on a service not deployed fails" "services.aiServices.tenantGenerationEnforcement must be LogOnly, Enforce or Disabled, got 'bogus'" render --set services.aiServices.tenantGenerationEnforcement=bogus
renders_fail "invalid global fails with every check service off" "tenantAuthorization.tenantGenerationEnforcement must be LogOnly, Enforce or Disabled, got 'nope'" render --set tenantAuthorization.tenantGenerationEnforcement=nope --set services.identity.deploy=false --set services.assetRepository.deploy=false --set services.bot.deploy=false --set services.communication.deploy=false

# 23. AB#9295 (AB#9199): stream-data read gate mode, asset repository only, chart default Warn (= code default)
R=OCTO_STREAMDATAREADAUTHORIZATION__ROLEENFORCEMENT
rmode() { grep -A1 "name: $R" <<<"$(dep asset-rep-services)" | grep -o 'value: "[A-Za-z]*"' | tr '\n' ' '; }
OUT="$(render)"
check "AB#9295 asset repository deployment was found (test is not vacuous)" test -n "$(dep asset-rep-services)"
check "read gate mode defaults to Warn"                         test "$(rmode)" = 'value: "Warn" '
check "read gate mode rendered exactly once in the whole chart" test "$(grep -c "name: $R" <<<"$OUT")" = 1
for svc in identity bot-services communication-controller-services platform-services; do
  check "$svc deployment was found (test is not vacuous)" test -n "$(dep "$svc")"
  check "$svc deployment carries no read gate variable" bash -c '! grep -q "$1" <<<"$0"' "$(dep "$svc")" "$R"
done
for m in Off Warn Enforce; do
  OUT="$(render --set services.assetRepository.streamDataReadEnforcement=$m)"
  check "read gate mode $m renders $m on the asset repository only" test "$(rmode)$(grep -c "name: $R" <<<"$OUT")" = "value: \"$m\" 1"
done
OUT="$(render --set services.assetRepository.streamDataReadEnforcement= )"
check "empty read gate mode falls back to Warn"                 test "$(rmode)" = 'value: "Warn" '
OUT="$(render --set services.assetRepository.streamDataReadEnforcement=null)"
check "null read gate mode falls back to Warn"                  test "$(rmode)" = 'value: "Warn" '
renders_fail "invalid read gate mode fails the render"          "services.assetRepository.streamDataReadEnforcement must be Off, Warn or Enforce, got 'Bogus'" render --set services.assetRepository.streamDataReadEnforcement=Bogus
renders_fail "lower-case read gate mode fails the render"       "services.assetRepository.streamDataReadEnforcement must be Off, Warn or Enforce, got 'enforce'" render --set services.assetRepository.streamDataReadEnforcement=enforce
renders_fail "boolean read gate mode fails the render"          "services.assetRepository.streamDataReadEnforcement must be Off, Warn or Enforce, got 'false'" render --set services.assetRepository.streamDataReadEnforcement=false
renders_fail "invalid read gate mode fails with deploy false"   "services.assetRepository.streamDataReadEnforcement must be Off, Warn or Enforce, got 'LogOnly'" render --set services.assetRepository.streamDataReadEnforcement=LogOnly --set services.assetRepository.deploy=false
# YAML 1.1 reads an unquoted Off as boolean false: a values file must quote it
RFILE="$(mktemp)"
printf 'services:\n  assetRepository:\n    streamDataReadEnforcement: "Off"\n' > "$RFILE"
OUT="$(render -f "$RFILE")"
check "values file with streamDataReadEnforcement: \"Off\" renders Off" test "$(rmode)" = 'value: "Off" '
printf 'services:\n  assetRepository:\n    streamDataReadEnforcement: Off\n' > "$RFILE"
renders_fail "unquoted Off in a values file (YAML boolean) fails the render" "services.assetRepository.streamDataReadEnforcement must be Off, Warn or Enforce, got 'false'" render -f "$RFILE"
rm -f "$RFILE"
renders_fail "misspelled read gate key fails the render"        "services.assetRepository.streamDataReadEnforcment is not a known value" render --set services.assetRepository.streamDataReadEnforcment=Enforce
renders_fail "wrongly cased read gate key fails the render"     "services.assetRepository.StreamDataReadEnforcement is not a known value" render --set services.assetRepository.StreamDataReadEnforcement=Enforce
renders_fail "read gate mode on another service fails the render" "services.communication.streamDataReadEnforcement is not supported" render --set services.communication.streamDataReadEnforcement=Enforce

# 24. AB#9319: bot index upgrade schedule (services.bot.indexUpgrade.*, OCTO_INDEXUPGRADE__*), bot container only
iu() { tr -d '\r' <<<"$OUT" | grep -A1 "name: OCTO_INDEXUPGRADE__$1\$" | grep -o 'value: .*'; }
BASE="$(render)"
check "unset renders no OCTO_INDEXUPGRADE variable" bash -c "! grep -q OCTO_INDEXUPGRADE <<<\"\$1\"" _ "$BASE"
OUT="$(render --set services.bot.indexUpgrade.schedule=Immediate)"
check "schedule=Immediate renders exactly OCTO_INDEXUPGRADE__SCHEDULE" test "$(grep -c 'OCTO_INDEXUPGRADE' <<<"$OUT") $(iu SCHEDULE)" = '1 value: "Immediate"'
# Without the variable (its name line and the value line after it) the render is byte-identical to the unset one.
# (Carriage returns are dropped on both sides: helm on Windows ends lines with CRLF.)
check "schedule adds only its two lines to the rendered chart" test "$(tr -d '\r' <<<"$OUT" | awk '/name: OCTO_INDEXUPGRADE__SCHEDULE$/ {skip=1; next} skip {skip=0; next} {print}')" = "$(tr -d '\r' <<<"$BASE")"
check "schedule is rendered in the bot Deployment only" test "$(tr -d '\r' <<<"$OUT" | awk 'BEGIN{RS="\n---\n"} /OCTO_INDEXUPGRADE__SCHEDULE/' | grep -E '^kind:|^  name:' | tr '\n' ' ')" = 'kind: Deployment   name: t-bot-services '
OUT="$(render --set services.bot.indexUpgrade.schedule=Window)"
check "schedule=Window renders" test "$(iu SCHEDULE)" = 'value: "Window"'
OUT="$(render --set services.bot.indexUpgrade.window.enabled=true)"
check "window.enabled=true renders exactly __WINDOW__ENABLED \"true\"" test "$(grep -c 'OCTO_INDEXUPGRADE' <<<"$OUT") $(iu WINDOW__ENABLED)" = '1 value: "true"'
OUT="$(render --set services.bot.indexUpgrade.window.enabled=false)"
check "window.enabled=false renders \"false\"" test "$(iu WINDOW__ENABLED)" = 'value: "false"'
OUT="$(render --set-string 'services.bot.indexUpgrade.window.cron=0 2 * * *')"
check "window.cron renders exactly __WINDOW__CRON, quoted" test "$(grep -c 'OCTO_INDEXUPGRADE' <<<"$OUT") $(iu WINDOW__CRON)" = '1 value: "0 2 * * *"'
OUT="$(render --set-string services.bot.indexUpgrade.window.maxDuration=04:00:00)"
check "window.maxDuration renders exactly __WINDOW__MAXDURATION, quoted" test "$(grep -c 'OCTO_INDEXUPGRADE' <<<"$OUT") $(iu WINDOW__MAXDURATION)" = '1 value: "04:00:00"'
OUT="$(render --set-string services.bot.indexUpgrade.window.maxDuration=1.12:30:00.5)"
check "window.maxDuration with days and fraction renders" test "$(iu WINDOW__MAXDURATION)" = 'value: "1.12:30:00.5"'
renders_fail "invalid schedule fails the render"          "services.bot.indexUpgrade.schedule must be Immediate or Window, got 'Bogus'" render --set services.bot.indexUpgrade.schedule=Bogus
renders_fail "lower-case schedule fails the render"       "services.bot.indexUpgrade.schedule must be Immediate or Window, got 'immediate'" render --set services.bot.indexUpgrade.schedule=immediate
renders_fail "empty schedule fails the render"            "services.bot.indexUpgrade.schedule must be Immediate or Window, got ''" render --set-string services.bot.indexUpgrade.schedule=
renders_fail "string window.enabled fails the render"     "services.bot.indexUpgrade.window.enabled must be true or false, got 'yes'" render --set-string services.bot.indexUpgrade.window.enabled=yes
renders_fail "quoted \"true\" window.enabled fails"       "services.bot.indexUpgrade.window.enabled must be true or false, got 'true'" render --set-string services.bot.indexUpgrade.window.enabled=true
renders_fail "invalid window.maxDuration fails the render" "services.bot.indexUpgrade.window.maxDuration must be a .NET TimeSpan" render --set-string services.bot.indexUpgrade.window.maxDuration=4h
renders_fail "window.maxDuration 25:00:00 fails the render" "services.bot.indexUpgrade.window.maxDuration must be a .NET TimeSpan" render --set-string services.bot.indexUpgrade.window.maxDuration=25:00:00
OUT="$(render --set-string services.bot.indexUpgrade.window.maxDuration=9999999.00:00:00)"
check "window.maxDuration with 7 day digits renders" test "$(iu WINDOW__MAXDURATION)" = 'value: "9999999.00:00:00"'
renders_fail "window.maxDuration above the TimeSpan maximum fails" "services.bot.indexUpgrade.window.maxDuration must be a .NET TimeSpan longer than zero with at most 7 day digits" render --set-string services.bot.indexUpgrade.window.maxDuration=99999999.00:00:00
renders_fail "empty window.cron fails the render"         "services.bot.indexUpgrade.window.cron must be a non-empty cron expression" render --set-string services.bot.indexUpgrade.window.cron=
renders_fail "blank window.cron fails the render"         "services.bot.indexUpgrade.window.cron must be a non-empty cron expression" render --set-string 'services.bot.indexUpgrade.window.cron=  '
renders_fail "zero window.maxDuration fails the render"   "services.bot.indexUpgrade.window.maxDuration must be a .NET TimeSpan longer than zero" render --set-string services.bot.indexUpgrade.window.maxDuration=00:00
# Validated once per render, also when bot is not deployed; misspelled, unknown and misplaced keys fail.
renders_fail "invalid value fails also with bot deploy=false" "services.bot.indexUpgrade.schedule must be Immediate or Window, got 'Bogus'" render --set services.bot.deploy=false --set services.bot.indexUpgrade.schedule=Bogus
renders_fail "miscased indexupgrade key fails the render" "services.bot.indexupgrade is not a known value: did you mean services.bot.indexUpgrade?" render --set services.bot.indexupgrade.schedule=Immediate
renders_fail "unknown key under indexUpgrade fails"       "services.bot.indexUpgrade.scedule is not a known value (schedule, window)" render --set services.bot.indexUpgrade.scedule=Immediate
renders_fail "unknown key under window fails"             "services.bot.indexUpgrade.window.enable is not a known value (enabled, cron, maxDuration)" render --set services.bot.indexUpgrade.window.enable=true
renders_fail "indexUpgrade on another service fails"      "services.identity.indexUpgrade is not supported: only services.bot runs the index upgrade" render --set services.identity.indexUpgrade.schedule=Immediate
renders_fail "non-map indexUpgrade fails the render"      "services.bot.indexUpgrade must be a map (schedule, window), got 'Immediate'" render --set services.bot.indexUpgrade=Immediate
renders_fail "non-map window fails the render"            "services.bot.indexUpgrade.window must be a map (enabled, cron, maxDuration), got 'true'" render --set services.bot.indexUpgrade.window=true
# 25. AB#9309 (AB#9199): /adapterPoolHub gate mode, communication controller only, chart default LogOnly (= code default)
P=OCTO_ADAPTERPOOLHUBAUTHORIZATION__MODE
pmode() { grep -A1 "name: $P" <<<"$(dep communication-controller-services)" | grep -o 'value: "[A-Za-z]*"' | tr '\n' ' '; }
hmode() { grep -A1 "name: OCTO_$1HUBAUTHORIZATION__MODE" <<<"$(dep communication-controller-services)" | grep -o 'value: "[A-Za-z]*"'; }
OUT="$(render)"
check "AB#9309 communication controller deployment was found (test is not vacuous)" test -n "$(dep communication-controller-services)"
check "pool hub mode defaults to LogOnly"                        test "$(pmode)" = 'value: "LogOnly" '
check "pool hub mode rendered exactly once in the whole chart"   test "$(grep -c "name: $P" <<<"$OUT")" = 1
for svc in identity asset-rep-services bot-services platform-services; do
  check "$svc deployment was found (test is not vacuous)" test -n "$(dep "$svc")"
  check "$svc deployment carries no pool hub variable" bash -c '! grep -q "$1" <<<"$0"' "$(dep "$svc")" "$P"
done
for m in LogOnly Enforce; do
  OUT="$(render --set services.communication.hubAuthorization.adapterPoolMode=$m)"
  check "pool hub mode $m renders $m on the communication controller only" test "$(pmode)$(grep -c "name: $P" <<<"$OUT")" = "value: \"$m\" 1"
  check "pool hub mode $m leaves adapter and operator hub on LogOnly" test "$(hmode ADAPTER) $(hmode OPERATOR)" = 'value: "LogOnly" value: "LogOnly"'
done
OUT="$(render --set services.communication.hubAuthorization.adapterMode=Enforce --set services.communication.hubAuthorization.operatorMode=Enforce)"
check "adapter and operator hub on Enforce leave the pool hub on LogOnly" test "$(pmode)" = 'value: "LogOnly" '
OUT="$(render --set services.communication.hubAuthorization.adapterPoolMode= )"
check "empty pool hub mode falls back to LogOnly"                test "$(pmode)" = 'value: "LogOnly" '
OUT="$(render --set services.communication.hubAuthorization.adapterPoolMode=null)"
check "null pool hub mode falls back to LogOnly"                 test "$(pmode)" = 'value: "LogOnly" '
renders_fail "invalid pool hub mode fails the render"            "services.communication.hubAuthorization.adapterPoolMode must be LogOnly or Enforce, got 'Bogus'" render --set services.communication.hubAuthorization.adapterPoolMode=Bogus
renders_fail "lower-case pool hub mode fails the render"         "services.communication.hubAuthorization.adapterPoolMode must be LogOnly or Enforce, got 'enforce'" render --set services.communication.hubAuthorization.adapterPoolMode=enforce
renders_fail "boolean pool hub mode fails the render"            "services.communication.hubAuthorization.adapterPoolMode must be LogOnly or Enforce, got 'true'" render --set services.communication.hubAuthorization.adapterPoolMode=true
renders_fail "invalid pool hub mode fails with deploy false"     "services.communication.hubAuthorization.adapterPoolMode must be LogOnly or Enforce, got 'Warn'" render --set services.communication.hubAuthorization.adapterPoolMode=Warn --set services.communication.deploy=false
PFILE="$(mktemp)"
printf 'services:\n  communication:\n    hubAuthorization:\n      adapterPoolMode: Enforce\n' > "$PFILE"
OUT="$(render -f "$PFILE")"
check "values file with adapterPoolMode: Enforce renders Enforce" test "$(pmode)" = 'value: "Enforce" '
# YAML 1.1 reads an unquoted On/Off/yes/no as a boolean: it must fail, never fall back to LogOnly
printf 'services:\n  communication:\n    hubAuthorization:\n      adapterPoolMode: On\n' > "$PFILE"
renders_fail "unquoted On in a values file (YAML boolean) fails the render" "services.communication.hubAuthorization.adapterPoolMode must be LogOnly or Enforce, got 'true'" render -f "$PFILE"
printf 'services:\n  communication:\n    hubAuthorization:\n      adapterPoolMode: Off\n' > "$PFILE"
renders_fail "unquoted Off in a values file (YAML boolean) fails the render" "services.communication.hubAuthorization.adapterPoolMode must be LogOnly or Enforce, got 'false'" render -f "$PFILE"
rm -f "$PFILE"
renders_fail "misspelled pool hub key fails the render"          "services.communication.hubAuthorization.adapterPoolMod is not a known value" render --set services.communication.hubAuthorization.adapterPoolMod=Enforce
renders_fail "wrongly cased pool hub key fails the render"       "services.communication.hubAuthorization.AdapterPoolMode is not a known value" render --set services.communication.hubAuthorization.AdapterPoolMode=Enforce
renders_fail "misspelled adapter hub key fails the render"       "services.communication.hubAuthorization.adapterHubMode is not a known value" render --set services.communication.hubAuthorization.adapterHubMode=Enforce
renders_fail "pool hub mode outside hubAuthorization fails"      "services.communication.adapterPoolMode is not a known value" render --set services.communication.adapterPoolMode=Enforce
renders_fail "misspelled hubAuthorization block fails"           "services.communication.hubAuthorisation is not a known value" render --set services.communication.hubAuthorisation.adapterPoolMode=Enforce
renders_fail "pool hub mode on another service fails the render" "services.assetRepository.hubAuthorization is not a known value" render --set services.assetRepository.hubAuthorization.adapterPoolMode=Enforce
renders_fail "pool hub key on another service with deploy false fails" "services.identity.adapterPoolMode is not a known value" render --set services.identity.adapterPoolMode=Enforce --set services.identity.deploy=false
renders_fail "pool hub key with separators fails the render"     "services.communication.adapter_pool_mode is not a known value" render --set services.communication.adapter_pool_mode=Enforce
renders_fail "pool hub key nested below another block fails"     "services.communication.signalr.adapterPoolMode is not a known value" render --set services.communication.signalr.adapterPoolMode=Enforce
renders_fail "pool hub key in the root tenantAuthorization section fails" "): tenantAuthorization.adapterPoolMode is not a known value" render --set tenantAuthorization.adapterPoolMode=Enforce
renders_fail "hubAuthorization block at the root fails"          "): hubAuthorization is not a known value" render --set hubAuthorization.adapterPoolMode=Enforce
renders_fail "pool hub key on a misspelled service fails"        "services.comunication.hubAuthorization is not a known value" render --set services.comunication.hubAuthorization.adapterPoolMode=Enforce
renders_fail "pool hub key inside a list fails"                  "services.identity.extra[0].adapterPoolMode is not a known value" render --set 'services.identity.extra[0].adapterPoolMode=Enforce'
for bad in false 0; do
  renders_fail "hubAuthorization: $bad (not a map) fails the render" "services.communication.hubAuthorization must be a map, got '$bad'" render --set services.communication.hubAuthorization=$bad
done
renders_fail "hubAuthorization: \"\" (not a map) fails the render" "services.communication.hubAuthorization must be a map, got ''" render --set-string services.communication.hubAuthorization=

# 26. AB#9310 (AB#9199): GraphQL mutation scope gate, asset repository only, chart default false (= service default)
M=OCTO_GRAPHQL__ENFORCEMUTATIONSCOPE
mscope() { grep -A1 "name: $M" <<<"$(dep asset-rep-services)" | grep -o 'value: "[a-z]*"' | tr '\n' ' '; }
OUT="$(render)"
check "AB#9310 asset repository deployment was found (test is not vacuous)" test -n "$(dep asset-rep-services)"
check "mutation scope defaults to false"                         test "$(mscope)" = 'value: "false" '
check "mutation scope rendered exactly once in the whole chart"  test "$(grep -c "name: $M" <<<"$OUT")" = 1
for svc in identity bot-services communication-controller-services platform-services; do
  check "$svc deployment was found (test is not vacuous)" test -n "$(dep "$svc")"
  check "$svc deployment carries no mutation scope variable" bash -c '! grep -q "$1" <<<"$0"' "$(dep "$svc")" "$M"
done
for b in true false; do
  OUT="$(render --set services.assetRepository.enforceMutationScope=$b)"
  check "mutation scope $b renders $b on the asset repository only" test "$(mscope)$(grep -c "name: $M" <<<"$OUT")" = "value: \"$b\" 1"
done
OUT="$(render --set services.assetRepository.enforceMutationScope= )"
check "empty mutation scope falls back to false"                 test "$(mscope)" = 'value: "false" '
OUT="$(render --set services.assetRepository.enforceMutationScope=null)"
check "null mutation scope falls back to false"                  test "$(mscope)" = 'value: "false" '
renders_fail "non-boolean mutation scope fails the render"       "services.assetRepository.enforceMutationScope must be true or false (a YAML boolean), got 'Enforce'" render --set services.assetRepository.enforceMutationScope=Enforce
renders_fail "string \"true\" mutation scope fails the render"   "services.assetRepository.enforceMutationScope must be true or false (a YAML boolean), got 'true'" render --set-string services.assetRepository.enforceMutationScope=true
renders_fail "number mutation scope fails the render"            "services.assetRepository.enforceMutationScope must be true or false (a YAML boolean), got '1'" render --set services.assetRepository.enforceMutationScope=1
renders_fail "non-boolean mutation scope fails with deploy false" "services.assetRepository.enforceMutationScope must be true or false (a YAML boolean), got 'yes please'" render --set "services.assetRepository.enforceMutationScope=yes please" --set services.assetRepository.deploy=false
MFILE="$(mktemp)"
printf 'services:\n  assetRepository:\n    enforceMutationScope: true\n' > "$MFILE"
OUT="$(render -f "$MFILE")"
check "values file with enforceMutationScope: true renders true" test "$(mscope)" = 'value: "true" '
printf 'services:\n  assetRepository:\n    enforceMutationScope: "true"\n' > "$MFILE"
renders_fail "quoted \"true\" in a values file fails the render" "services.assetRepository.enforceMutationScope must be true or false (a YAML boolean), got 'true'" render -f "$MFILE"
rm -f "$MFILE"
renders_fail "misspelled mutation scope key fails the render"    "services.assetRepository.enforceMutationScop is not a known value" render --set services.assetRepository.enforceMutationScop=true
renders_fail "wrongly cased mutation scope key fails the render" "services.assetRepository.EnforceMutationScope is not a known value" render --set services.assetRepository.EnforceMutationScope=true
renders_fail "mutation scope on another service fails the render" "services.communication.enforceMutationScope is not a known value" render --set services.communication.enforceMutationScope=true
renders_fail "mutation scope on a service not deployed fails"    "services.bot.enforceMutationScope is not a known value" render --set services.bot.enforceMutationScope=true --set services.bot.deploy=false
renders_fail "mutation scope at the config key path (graphQl block) fails" "services.assetRepository.graphQl.enforceMutationScope is not a known value" render --set services.assetRepository.graphQl.enforceMutationScope=true
renders_fail "plural mutation scope key fails the render"        "services.assetRepository.enforceMutationsScope is not a known value" render --set services.assetRepository.enforceMutationsScope=true
renders_fail "mutation scope key with separators fails the render" "services.assetRepository.enforce_mutation_scope is not a known value" render --set services.assetRepository.enforce_mutation_scope=true
renders_fail "mutation scope in serviceDefaults fails the render" "): serviceDefaults.enforceMutationScope is not a known value" render --set serviceDefaults.enforceMutationScope=true
MFILE="$(mktemp)"
printf 'assetRepository:\n  enforceMutationScope: true\n' > "$MFILE"
renders_fail "assetRepository block at the root (indentation slip) fails" "): assetRepository.enforceMutationScope is not a known value" render -f "$MFILE"
# a single key containing dots must never pass as the legal nested path
printf 'services.assetRepository.enforceMutationScope: true\n' > "$MFILE"
renders_fail "dotted root key services.assetRepository.enforceMutationScope fails" '): ["services.assetRepository.enforceMutationScope"] is not a known value' render -f "$MFILE"
printf 'services.communication.hubAuthorization.adapterPoolMode: Enforce\n' > "$MFILE"
renders_fail "dotted root key services.communication.hubAuthorization.adapterPoolMode fails" '): ["services.communication.hubAuthorization.adapterPoolMode"] is not a known value' render -f "$MFILE"
printf 'services:\n  communication.hubAuthorization:\n    adapterPoolMode: Enforce\n' > "$MFILE"
renders_fail "dotted service key communication.hubAuthorization fails" '): services.["communication.hubAuthorization"] is not a known value' render -f "$MFILE"
rm -f "$MFILE"
# an escaped dot in --set makes a scalar entry in services, which serviceaccount.yaml already refuses before the scan runs:
# only the failure matters here (never a render with the default)
renders_fail "escaped dot in --set (services.assetRepository\\.enforceMutationScope) fails" "Error:" render --set 'services.assetRepository\.enforceMutationScope=true'

# 27. AB#8897: runtime query time limit on the asset repository only (OCTO_RuntimeQuery__MaxTimeMs)
RQ=OCTO_RuntimeQuery__MaxTimeMs
rq() { grep -A1 "name: $RQ" <<<"$(dep asset-rep-services)" | grep -o 'value: "[0-9]*"'; }
OUT="$(render)"
check "default renders 120000 on the asset repository"         test "$(rq)" = 'value: "120000"'
check "rendered on the asset repository only"                  test "$(grep -c "name: $RQ" <<<"$OUT")" = 1
OUT="$(render --set services.assetRepository.runtimeQuery.maxTimeMs=300000)"
check "a cluster value is rendered"                            test "$(rq)" = 'value: "300000"'
OUT="$(render --set services.assetRepository.runtimeQuery.maxTimeMs=0)"
check "0 (off) is rendered"                                    test "$(rq)" = 'value: "0"'
RQ_FILE="$(mktemp)"; printf 'services:
  assetRepository:
    runtimeQuery:
      maxTimeMs: 1800000
' >"$RQ_FILE"
OUT="$(render -f "$RQ_FILE")"; rm -f "$RQ_FILE"
check "a values-file number renders without float notation"    test "$(rq)" = 'value: "1800000"'
OUT="$(render --set services.assetRepository.runtimeQuery.maxTimeMs=null)"
check "null renders no variable (service default applies)"     test -z "$(rq)"
renders_fail "negative value fails the render"                 "services.assetRepository.runtimeQuery.maxTimeMs must be a whole number of milliseconds from 0 (off) to 2147483647, got '-1'" render --set services.assetRepository.runtimeQuery.maxTimeMs=-1
# --set reads 1.5 as text (strvals parses only integers); the whole-number check needs a values-file float.
renders_fail "fraction via --set (text) fails the render"      "got '1.5'" render --set services.assetRepository.runtimeQuery.maxTimeMs=1.5
RQ_FILE="$(mktemp)"; printf 'services:\n  assetRepository:\n    runtimeQuery:\n      maxTimeMs: 1.5\n' >"$RQ_FILE"
renders_fail "values-file fraction fails the whole-number check" "got '1.5'" render -f "$RQ_FILE"
rm -f "$RQ_FILE"
renders_fail "MongoDB spelling maxTimeMS fails the render"     "services.assetRepository.runtimeQuery.maxTimeMS is not a known value: did you mean services.assetRepository.runtimeQuery.maxTimeMs?" render --set services.assetRepository.runtimeQuery.maxTimeMS=0
renders_fail "unknown key under runtimeQuery fails with deploy false" "services.assetRepository.runtimeQuery.limit is not a known value" render --set services.assetRepository.runtimeQuery.limit=5 --set services.assetRepository.deploy=false
renders_fail "runtimeQuery false fails the render"             "services.assetRepository.runtimeQuery must be a map with the key maxTimeMs, got 'false'" render --set services.assetRepository.runtimeQuery=false
renders_fail "runtimeQuery 0 fails the render"                 "services.assetRepository.runtimeQuery must be a map with the key maxTimeMs, got '0'" render --set services.assetRepository.runtimeQuery=0
renders_fail "runtimeQuery empty string fails the render"      "services.assetRepository.runtimeQuery must be a map with the key maxTimeMs, got ''" render --set-string services.assetRepository.runtimeQuery=
renders_fail "runtimeQuery text fails the render"              "services.assetRepository.runtimeQuery must be a map with the key maxTimeMs, got 'foo'" render --set services.assetRepository.runtimeQuery=foo
RQ_FILE="$(mktemp)"; printf 'services:\n  assetRepository:\n    runtimeQuery: false\n' >"$RQ_FILE"
renders_fail "values-file runtimeQuery false fails also with deploy false" "got 'false'" render -f "$RQ_FILE" --set services.assetRepository.deploy=false
rm -f "$RQ_FILE"
renders_fail "text fails the render"                           "got '2m'" render --set-string services.assetRepository.runtimeQuery.maxTimeMs=2m
renders_fail "value above int32 fails the render"              "got '3000000000'" render --set services.assetRepository.runtimeQuery.maxTimeMs=3000000000
renders_fail "invalid value fails also with deploy false"      "got '-5'" render --set services.assetRepository.runtimeQuery.maxTimeMs=-5 --set services.assetRepository.deploy=false
OUT="$(render --set services.assetRepository.deploy=false)"
check "deploy false renders no runtime query variable"         bash -c '! grep -q "$1" <<<"$0"' "$OUT" "$RQ"

exit $fail
