#!/usr/bin/env bash
# Render tests for the octo-mesh chart (AB#6592): image pre-pull DaemonSets and probe timing.
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

exit $fail
