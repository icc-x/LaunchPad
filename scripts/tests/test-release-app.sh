#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h}
TMP=$(mktemp -d /tmp/launchpad-release-app.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

fail() {
  print -u2 -- "test-release-app: $1"
  exit 1
}

SHIM="$TMP/shim"
OUT="$TMP/out"
CALLS_LOG="$TMP/calls.log"
mkdir -p "$SHIM"

cat > "$SHIM/swift" <<'EOF'
#!/bin/zsh
if [[ ${FAKE_BUILD_MODE:-ok} == fail ]]; then
  exit 1
fi
if [[ $1 == build ]]; then
  exit 0
fi
exit 1
EOF
chmod +x "$SHIM/swift"

mkfake() {
  local name=$1 create_last=${2:-0}
  cat > "$SHIM/$name" <<EOF
#!/bin/zsh
print -r -- "\$(basename "\$0") \$*" >> "\$LAUNCHPAD_TEST_CALLS_LOG"
if [[ $create_last == 1 ]]; then
  : > "\${@[-1]}"
fi
exit 0
EOF
  chmod +x "$SHIM/$name"
}
mkfake codesign
mkfake ditto 1
mkfake xcrun
mkfake spctl

RELEASE_ENV=(
  "LAUNCHPAD_CODESIGN_IDENTITY=Developer ID Application: Example"
  "LAUNCHPAD_TEAM_ID=EXAMPLETEAM"
  "LAUNCHPAD_NOTARY_PROFILE=example-profile"
  "LAUNCHPAD_CODESIGN_BIN=$SHIM/codesign"
  "LAUNCHPAD_DITTO_BIN=$SHIM/ditto"
  "LAUNCHPAD_XCRUN_BIN=$SHIM/xcrun"
  "LAUNCHPAD_SPCTL_BIN=$SHIM/spctl"
  "LAUNCHPAD_BUILD_OUTPUT_DIR=$OUT"
  "LAUNCHPAD_TEST_CALLS_LOG=$CALLS_LOG"
  "PATH=$SHIM:$PATH"
)

"$ROOT/scripts/release-app.sh" --help > "$TMP/help.log" 2>&1
rg -q 'Usage' "$TMP/help.log" || fail '--help did not print usage'

if "$ROOT/scripts/release-app.sh" --bogus > "$TMP/bogus.log" 2>&1; then
  fail 'unknown option unexpectedly succeeded'
fi

if /usr/bin/env -u LAUNCHPAD_CODESIGN_IDENTITY \
  LAUNCHPAD_TEAM_ID=EXAMPLETEAM \
  LAUNCHPAD_NOTARY_PROFILE=example-profile \
  "$ROOT/scripts/release-app.sh" --dry-run > /dev/null 2>&1; then
  fail 'missing LAUNCHPAD_CODESIGN_IDENTITY unexpectedly succeeded'
fi

if /usr/bin/env -u LAUNCHPAD_NOTARY_PROFILE \
  "LAUNCHPAD_CODESIGN_IDENTITY=Developer ID Application: Example" \
  "LAUNCHPAD_TEAM_ID=EXAMPLETEAM" \
  "$ROOT/scripts/release-app.sh" --dry-run > /dev/null 2>&1; then
  fail 'missing LAUNCHPAD_NOTARY_PROFILE unexpectedly succeeded'
fi

if /usr/bin/env \
  "LAUNCHPAD_CODESIGN_IDENTITY=Developer ID Application: Example" \
  "LAUNCHPAD_TEAM_ID=BADID" \
  "LAUNCHPAD_NOTARY_PROFILE=example-profile" \
  "$ROOT/scripts/release-app.sh" --dry-run > /dev/null 2>&1; then
  fail 'invalid LAUNCHPAD_TEAM_ID unexpectedly succeeded'
fi

rm -rf "$OUT"
/usr/bin/env "$RELEASE_ENV[@]" \
  LAUNCHPAD_LEAK_PROBE='SECRET_LEAK_PROBE' \
  "$ROOT/scripts/release-app.sh" --dry-run > "$TMP/dry.log" 2>&1
if [[ -e $OUT ]]; then
  fail 'dry-run created artifacts under output directory'
fi
if rg -q 'SECRET_LEAK_PROBE' "$TMP/dry.log"; then
  fail 'dry-run leaked environment values'
fi
rg -q 'codesign' "$TMP/dry.log" || fail 'dry-run did not print commands'

rm -rf "$OUT"
mkdir -p "$OUT/release"
: > "$OUT/release/LaunchPadApp"
chmod +x "$OUT/release/LaunchPadApp"
set +e
/usr/bin/env "$RELEASE_ENV[@]" \
  FAKE_BUILD_MODE=fail \
  "$ROOT/scripts/release-app.sh" > "$TMP/build-fail.log" 2>&1
command_status=$?
set -e
if (( command_status == 0 )); then
  fail 'build failure unexpectedly succeeded'
fi

rm -rf "$OUT"
mkdir -p "$OUT/release"
: > "$OUT/release/LaunchPadApp"
chmod +x "$OUT/release/LaunchPadApp"
: > "$CALLS_LOG"
/usr/bin/env "$RELEASE_ENV[@]" \
  "$ROOT/scripts/release-app.sh" > "$TMP/success.log" 2>&1

[[ -d "$OUT/LaunchPad.app/Contents/MacOS" ]] || fail 'app bundle missing Contents/MacOS'
[[ -f "$OUT/LaunchPad.app/Contents/MacOS/LaunchPadApp" ]] || fail 'app bundle missing executable'
[[ -f "$OUT/LaunchPad.app/Contents/Info.plist" ]] || fail 'app bundle missing Info.plist'
[[ -f "$OUT/LaunchPad.zip" ]] || fail 'archive zip missing'
rg -q 'team_id=EXAMPLETEAM' "$OUT/release-manifest.txt" || fail 'manifest missing team_id'

expected_order='codesign
codesign
ditto
xcrun
xcrun
spctl
xcrun'
actual_order=$(rg -o '^(codesign|ditto|xcrun|spctl)' "$CALLS_LOG")
if [[ $actual_order != $expected_order ]]; then
  fail "unexpected tool order: $actual_order"
fi

print -- 'test-release-app: passed'
