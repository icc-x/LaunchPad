#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h}
TMP=$(mktemp -d /tmp/launchpad-release-discovery.XXXXXX)
DEFAULT_ARTIFACT_DIR=
unset LAUNCHPAD_RELEASE_ARTIFACT_DIR

cleanup() {
  rm -rf "$TMP"
  if [[ -n $DEFAULT_ARTIFACT_DIR \
        && $DEFAULT_ARTIFACT_DIR == "$ROOT/.superpowers/sdd/release-gate."* ]]; then
    rm -rf "$DEFAULT_ARTIFACT_DIR"
  fi
}
trap cleanup EXIT

DEFAULT_ARTIFACT_DIR=$(
  "$ROOT/scripts/test-release.sh" --probe-default-artifact-contract
)
[[ -d $DEFAULT_ARTIFACT_DIR ]]
[[ -f "$DEFAULT_ARTIFACT_DIR/result.status" ]]
[[ $(<"$DEFAULT_ARTIFACT_DIR/result.status") == failed ]]

cat > "$TMP/five.raw" <<'EOF'
LaunchPadTests.PerformanceTests/snapshot_1000items_under10ms()
LaunchPadTests.PerformanceTests/gridLayout_dynamicViewports_under1ms()
LaunchPadTests.PerformanceTests/search_1000items_under50ms()
LaunchPadTests.PerformanceTests/iconCache_1000MemoryHits_under300ms()
LaunchPadTests.PerformanceTests/iconCache_1000Requests_noRepeatedDiskWrites()
EOF

cat > "$TMP/five.expected" <<'EOF'
LaunchPadTests.PerformanceTests/gridLayout_dynamicViewports_under1ms()
LaunchPadTests.PerformanceTests/iconCache_1000MemoryHits_under300ms()
LaunchPadTests.PerformanceTests/iconCache_1000Requests_noRepeatedDiskWrites()
LaunchPadTests.PerformanceTests/search_1000items_under50ms()
LaunchPadTests.PerformanceTests/snapshot_1000items_under10ms()
EOF

"$ROOT/scripts/run-with-timeout.sh" 5 -- /usr/bin/env \
  LAUNCHPAD_RELEASE_ARTIFACT_DIR="$TMP/artifacts-five" \
  "$ROOT/scripts/test-release.sh" --probe-discovery-contract \
  "$TMP/five.raw" "$TMP/five.list"
cmp -s "$TMP/five.expected" "$TMP/five.list"

: > "$TMP/empty.raw"
if "$ROOT/scripts/run-with-timeout.sh" 5 -- /usr/bin/env \
  LAUNCHPAD_RELEASE_ARTIFACT_DIR="$TMP/artifacts-empty" \
  "$ROOT/scripts/test-release.sh" --probe-discovery-contract \
  "$TMP/empty.raw" "$TMP/empty.list"; then
  print -u2 -- 'empty discovery unexpectedly passed'
  exit 1
fi
