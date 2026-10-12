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

# 6. Recreate strategy is untouched, probe timing (AB#6592)
OUT="$(render)"
check "services keep strategy Recreate (5x)"    test "$(grep -c 'type: Recreate' <<<"$OUT")" = 5
check "startupProbe polls every 2s, 300 tries (600s budget)" test "$(grep -A5 'startupProbe' <<<"$OUT" | grep -c 'failureThreshold: 300')" = 5
check "readinessProbe polls every 3s, tolerates 30s" test "$(grep -A7 'readinessProbe' <<<"$OUT" | grep -c 'periodSeconds: 3')" -ge 5

exit $fail
