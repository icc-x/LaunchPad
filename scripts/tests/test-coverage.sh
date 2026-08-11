#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h}
TMP=$(mktemp -d /tmp/launchpad-coverage.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

fail() {
  print -u2 -- "test-coverage: $1"
  exit 1
}

SHIM="$TMP/shim"
FAKE_BIN_DIR="$TMP/fake-bin"
FAKE_TEST_BINARY="$FAKE_BIN_DIR/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests"
mkdir -p "$SHIM" "$FAKE_BIN_DIR/codecov" "${FAKE_TEST_BINARY:h}"
: > "$FAKE_TEST_BINARY"
chmod +x "$FAKE_TEST_BINARY"

cat > "$SHIM/swift" <<EOF
#!/bin/zsh
if [[ \${FAKE_SWIFT_MODE:-ok} == fail ]]; then
  exit 1
fi
if [[ \$1 == test ]]; then
  exit 0
fi
if [[ \$1 == build && \$2 == --show-bin-path ]]; then
  print -r -- "$FAKE_BIN_DIR"
  exit 0
fi
exit 1
EOF
chmod +x "$SHIM/swift"

cat > "$SHIM/xcrun" <<EOF
#!/bin/zsh
if [[ \${FAKE_XCRUN_MODE:-ok} == fail ]]; then
  exit 1
fi
if [[ \$1 == --find ]]; then
  case \$2 in
    llvm-profdata) print -r -- "$SHIM/llvm-profdata" ;;
    llvm-cov) print -r -- "$SHIM/llvm-cov" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
exit 1
EOF
chmod +x "$SHIM/xcrun"

cat > "$SHIM/llvm-profdata" <<EOF
#!/bin/zsh
if [[ \${FAKE_MERGE_MODE:-ok} == fail ]]; then
  exit 1
fi
while [[ \$# -gt 0 ]]; do
  if [[ \$1 == -o ]]; then
    shift
    print -r -- "fake merged profdata" > "\$1"
  fi
  shift
done
exit 0
EOF
chmod +x "$SHIM/llvm-profdata"

cat > "$SHIM/llvm-cov" <<EOF
#!/bin/zsh
if [[ \${FAKE_REPORT_MODE:-ok} == fail ]]; then
  exit 1
fi
case \$1 in
  report)
    print -r -- "fake coverage report"
    exit 0
    ;;
  show)
    if [[ \${FAKE_SHOW_MODE:-ok} == empty ]]; then
      exit 0
    fi
    print -r -- "fake coverage show"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$SHIM/llvm-cov"

OUT_DIR="$TMP/out"

run_expect_fail() {
  local label=$1
  shift
  local command_status
  set +e
  /usr/bin/env \
    LAUNCHPAD_SWIFT_BIN="$SHIM/swift" \
    LAUNCHPAD_XCRUN_BIN="$SHIM/xcrun" \
    LAUNCHPAD_COVERAGE_OUTPUT_DIR="$OUT_DIR" \
    "$@" \
    "$ROOT/scripts/coverage.sh" > "$TMP/$label.log" 2>&1
  command_status=$?
  set -e
  if (( command_status == 0 )); then
    fail "$label unexpectedly succeeded"
  fi
  if rg -q 'coverage_status=passed' "$TMP/$label.log"; then
    fail "$label printed coverage_status=passed"
  fi
}

run_expect_fail swift-test-failure FAKE_SWIFT_MODE=fail

run_expect_fail empty-profraw

: > "$FAKE_BIN_DIR/codecov/sample.profraw"

run_expect_fail merge-failure FAKE_MERGE_MODE=fail

run_expect_fail report-failure FAKE_REPORT_MODE=fail

run_expect_fail empty-show-output FAKE_SHOW_MODE=empty

run_expect_fail missing-llvm-tools FAKE_XCRUN_MODE=fail

if rg -n '/Users/|arm64-apple-macosx|/Applications/Xcode\.app' "$ROOT/scripts/coverage.sh"; then
  fail 'coverage.sh contains hardcoded developer paths'
fi

rm -rf "$OUT_DIR"
set +e
/usr/bin/env \
  LAUNCHPAD_SWIFT_BIN="$SHIM/swift" \
  LAUNCHPAD_XCRUN_BIN="$SHIM/xcrun" \
  LAUNCHPAD_COVERAGE_OUTPUT_DIR="$OUT_DIR" \
  "$ROOT/scripts/coverage.sh" > "$TMP/success.log" 2>&1
command_status=$?
set -e
if (( command_status != 0 )); then
  cat "$TMP/success.log" >&2
  fail "success path exited $command_status"
fi
rg -q 'coverage_status=passed' "$TMP/success.log" \
  || fail 'success path did not print coverage_status=passed'
[[ -s "$OUT_DIR/coverage.profdata" ]] || fail 'coverage.profdata missing or empty'
[[ -s "$OUT_DIR/coverage-summary.txt" ]] || fail 'coverage-summary.txt missing or empty'
[[ -s "$OUT_DIR/coverage-show.txt" ]] || fail 'coverage-show.txt missing or empty'

print -- 'test-coverage: passed'
