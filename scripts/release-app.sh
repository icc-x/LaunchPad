#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}

usage() {
  cat <<'EOF'
Usage: release-app.sh [--dry-run] [--help]

Builds the release app bundle and runs the signing/notarization chain:
  build → codesign (hardened runtime) → verify → archive → notary submit
  → staple → Gatekeeper assess → stapler validate

Environment:
  LAUNCHPAD_CODESIGN_IDENTITY  Developer ID Application identity for codesign
  LAUNCHPAD_TEAM_ID            Team ID written to the release manifest
  LAUNCHPAD_NOTARY_PROFILE     Keychain profile name for notarytool
  LAUNCHPAD_BUILD_OUTPUT_DIR   Output root (default: <repo>/.build)
  LAUNCHPAD_CODESIGN_BIN       codesign path override (default: command -v codesign)
  LAUNCHPAD_DITTO_BIN          ditto path override
  LAUNCHPAD_XCRUN_BIN          xcrun path override
  LAUNCHPAD_SPCTL_BIN          spctl path override

Options:
  --dry-run  Print the exact shell-escaped commands without executing them
  --help     Show this help and exit
EOF
}

DRY_RUN=0
for arg in "$@"; do
  case $arg in
    --help|-h)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --*)
      print -u2 -- "release-app: unknown option: $arg"
      usage >&2
      exit 2
      ;;
    *)
      print -u2 -- "release-app: unexpected argument: $arg"
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n ${LAUNCHPAD_CODESIGN_IDENTITY:-} ]] || {
  print -u2 -- 'release-app: LAUNCHPAD_CODESIGN_IDENTITY is required'
  exit 1
}
[[ -n ${LAUNCHPAD_TEAM_ID:-} ]] || {
  print -u2 -- 'release-app: LAUNCHPAD_TEAM_ID is required'
  exit 1
}
[[ -n ${LAUNCHPAD_NOTARY_PROFILE:-} ]] || {
  print -u2 -- 'release-app: LAUNCHPAD_NOTARY_PROFILE is required'
  exit 1
}
if [[ ! $LAUNCHPAD_TEAM_ID =~ ^[A-Za-z0-9]{8,12}$ ]]; then
  print -u2 -- "release-app: invalid LAUNCHPAD_TEAM_ID: $LAUNCHPAD_TEAM_ID"
  exit 1
fi

OUTPUT_DIR=${LAUNCHPAD_BUILD_OUTPUT_DIR:-$ROOT/.build}
APP="$OUTPUT_DIR/LaunchPad.app"
ARCHIVE="$OUTPUT_DIR/LaunchPad.zip"
ENTITLEMENTS="$ROOT/Resources/LaunchPad.entitlements"

CODESIGN_BIN=${LAUNCHPAD_CODESIGN_BIN:-$(command -v codesign)}
DITTO_BIN=${LAUNCHPAD_DITTO_BIN:-$(command -v ditto)}
XCRUN_BIN=${LAUNCHPAD_XCRUN_BIN:-$(command -v xcrun)}
SPCTL_BIN=${LAUNCHPAD_SPCTL_BIN:-$(command -v spctl)}

[[ -f "$ENTITLEMENTS" ]] || {
  print -u2 -- "release-app: entitlements file missing: $ENTITLEMENTS"
  exit 1
}

shell_quote() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
}

run() {
  local label=$1
  shift
  if (( DRY_RUN )); then
    print -r -- "release-app: [dry-run] $label: $(shell_quote "$@")"
  else
    print -r -- "release-app: $label"
    "$@"
  fi
}

if (( ! DRY_RUN )); then
  mkdir -p "$OUTPUT_DIR"
  print -r -- "team_id=$LAUNCHPAD_TEAM_ID" > "$OUTPUT_DIR/release-manifest.txt"
  print -r -- "timestamp=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUTPUT_DIR/release-manifest.txt"
fi

run build "$ROOT/scripts/build-app.sh"

if (( ! DRY_RUN )); then
  if [[ ! -x "$APP/Contents/MacOS/LaunchPadApp" || ! -f "$APP/Contents/Info.plist" ]]; then
    print -u2 -- "release-app: app bundle incomplete: $APP"
    exit 1
  fi
fi

run codesign "$CODESIGN_BIN" --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$LAUNCHPAD_CODESIGN_IDENTITY" "$APP"

run verify "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$APP"

run archive "$DITTO_BIN" -c -k --keepParent "$APP" "$ARCHIVE"

run notary-submit "$XCRUN_BIN" notarytool submit "$ARCHIVE" \
  --keychain-profile "$LAUNCHPAD_NOTARY_PROFILE" --wait

run staple "$XCRUN_BIN" stapler staple "$APP"

run gatekeeper-assess "$SPCTL_BIN" --assess --type execute --verbose=4 "$APP"

run stapler-validate "$XCRUN_BIN" stapler validate "$APP"

print -r -- "release-app: done; signed artifact: $APP"
