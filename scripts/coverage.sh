#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
SWIFT_BIN=${LAUNCHPAD_SWIFT_BIN:-$(command -v swift)}
XCRUN_BIN=${LAUNCHPAD_XCRUN_BIN:-$(command -v xcrun)}
OUTPUT_DIR=${LAUNCHPAD_COVERAGE_OUTPUT_DIR:-$ROOT/.build/coverage}

cd "$ROOT"
mkdir -p "$OUTPUT_DIR"

"$SWIFT_BIN" test --disable-sandbox --no-parallel --enable-code-coverage

BIN_PATH=$("$SWIFT_BIN" build --show-bin-path)
TEST_BINARY=$(find "$BIN_PATH" -type f \
  -path '*/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests' \
  -print -quit)
if [[ -z $TEST_BINARY || ! -x $TEST_BINARY ]]; then
  print -u2 "coverage: test binary not found under $BIN_PATH"
  exit 1
fi

PROFRAW_FILES=("$BIN_PATH"/codecov/*.profraw(N))
if [[ ${#PROFRAW_FILES[@]} -eq 0 ]]; then
  print -u2 "coverage: no profraw files under $BIN_PATH/codecov"
  exit 1
fi

LLVM_PROFDATA=$("$XCRUN_BIN" --find llvm-profdata)
LLVM_COV=$("$XCRUN_BIN" --find llvm-cov)
if [[ ! -x $LLVM_PROFDATA ]]; then
  print -u2 "coverage: llvm-profdata not found"
  exit 1
fi
if [[ ! -x $LLVM_COV ]]; then
  print -u2 "coverage: llvm-cov not found"
  exit 1
fi

"$LLVM_PROFDATA" merge -sparse -o "$OUTPUT_DIR/coverage.profdata" "${PROFRAW_FILES[@]}"
if [[ ! -s "$OUTPUT_DIR/coverage.profdata" ]]; then
  print -u2 "coverage: merged profdata is empty"
  exit 1
fi

"$LLVM_COV" report "$TEST_BINARY" \
  -instr-profile="$OUTPUT_DIR/coverage.profdata" \
  -ignore-filename-regex='Tests/|DerivedSources|runner.swift' \
  > "$OUTPUT_DIR/coverage-summary.txt"
if [[ ! -s "$OUTPUT_DIR/coverage-summary.txt" ]]; then
  print -u2 "coverage: report produced empty summary"
  exit 1
fi

"$LLVM_COV" show -use-color=false "$TEST_BINARY" \
  -instr-profile="$OUTPUT_DIR/coverage.profdata" \
  -ignore-filename-regex='Tests/|DerivedSources|runner.swift' \
  > "$OUTPUT_DIR/coverage-show.txt"
if [[ ! -s "$OUTPUT_DIR/coverage-show.txt" ]]; then
  print -u2 "coverage: show produced empty output"
  exit 1
fi

print -r -- 'coverage_status=passed'
print -r -- "profdata=$OUTPUT_DIR/coverage.profdata"
print -r -- "summary=$OUTPUT_DIR/coverage-summary.txt"
print -r -- "show=$OUTPUT_DIR/coverage-show.txt"
