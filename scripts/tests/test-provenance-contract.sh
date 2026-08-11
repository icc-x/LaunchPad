#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h:h}
ARTIFACT_DIR=$(mktemp -d /tmp/launchpad-provenance-contract.XXXXXX)
trap '/bin/rm -rf "$ARTIFACT_DIR"' EXIT

LAUNCHPAD_RELEASE_ARTIFACT_DIR="$ARTIFACT_DIR/gate" \
  zsh "$ROOT_DIR/scripts/test-release.sh" --probe-provenance-mutation

print 'test-provenance-contract: passed'
