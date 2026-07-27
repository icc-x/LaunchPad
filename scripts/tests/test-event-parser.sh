#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h:h}
PARSER="$ROOT_DIR/scripts/parse-test-events.swift"
TEMP_DIR=$(mktemp -d /tmp/launchpad-test-event-parser.XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT
CLANG_MODULE_CACHE_PATH="$TEMP_DIR/clang-module-cache"
SWIFTPM_MODULECACHE_OVERRIDE="$TEMP_DIR/swiftpm-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
export CLANG_MODULE_CACHE_PATH SWIFTPM_MODULECACHE_OVERRIDE

readonly FUNCTION_ID='LaunchPadTests.EventParserTests/testAcceptsSuiteEvents()/EventParserTests.swift:10:2'
readonly CANONICAL_ID='LaunchPadTests.EventParserTests/testAcceptsSuiteEvents()'

fail() {
  print -u2 -- "test-event-parser: $1"
  exit 1
}

write_stream() {
  local destination=$1
  shift
  print -rl -- "$@" > "$destination"
}

parse() {
  local input=$1 prefix=$2
  /usr/bin/swift "$PARSER" "$input" "$TEMP_DIR/${prefix}.executed" \
    "$TEMP_DIR/${prefix}.version" "$TEMP_DIR/${prefix}.identity"
}

expect_failure() {
  local label=$1 expected_error=$2 input=$3
  local command_status

  set +e
  parse "$input" "$label" 2> "$TEMP_DIR/${label}.stderr"
  command_status=$?
  set -e
  (( command_status != 0 )) || fail "$label unexpectedly succeeded"
  rg -q -F -- "$expected_error" "$TEMP_DIR/${label}.stderr" \
    || fail "$label did not report: $expected_error"
}

valid_stream="$TEMP_DIR/valid.ndjson"
write_stream "$valid_stream" \
  '{"version":0,"kind":"event","payload":{"kind":"testStarted","testID":"LaunchPadTests.EventParserTests"}}' \
  "{\"version\":0,\"kind\":\"test\",\"payload\":{\"kind\":\"function\",\"id\":\"$FUNCTION_ID\",\"_testCases\":[{\"id\":\"case-1\"}]}}" \
  "{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"testStarted\",\"testID\":\"$FUNCTION_ID\"}}" \
  "{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"testCaseStarted\",\"testID\":\"$FUNCTION_ID\",\"_testCase\":{\"id\":\"case-1\"}}}" \
  "{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"testCaseEnded\",\"testID\":\"$FUNCTION_ID\",\"_testCase\":{\"id\":\"case-1\"}}}" \
  "{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"testEnded\",\"testID\":\"$FUNCTION_ID\",\"messages\":[{\"symbol\":\"pass\"}]}}" \
  '{"version":0,"kind":"event","payload":{"kind":"testEnded","testID":"LaunchPadTests.EventParserTests"}}'

parse "$valid_stream" valid
[[ $(<"$TEMP_DIR/valid.executed") == "$CANONICAL_ID" ]] \
  || fail 'suite lifecycle event entered executed identities'
[[ $(<"$TEMP_DIR/valid.version") == 0 ]] || fail 'event version output was not 0'
[[ $(/usr/bin/plutil -extract functionRecords.0 raw -o - "$TEMP_DIR/valid.identity") \
    == "$FUNCTION_ID" ]] || fail 'function record was not preserved'
[[ $(/usr/bin/plutil -extract functionStarts.0 raw -o - "$TEMP_DIR/valid.identity") \
    == "$FUNCTION_ID" ]] || fail 'suite lifecycle event entered function starts'

invalid_version_stream="$TEMP_DIR/invalid-version.ndjson"
write_stream "$invalid_version_stream" \
  '{"version":1,"kind":"test","payload":{"kind":"function","id":"LaunchPadTests.EventParserTests/testAcceptsSuiteEvents()/EventParserTests.swift:10:2"}}'
expect_failure invalid-version 'invalid event schema at line 1' "$invalid_version_stream"

duplicate_function_stream="$TEMP_DIR/duplicate-function.ndjson"
write_stream "$duplicate_function_stream" \
  "{\"version\":0,\"kind\":\"test\",\"payload\":{\"kind\":\"function\",\"id\":\"$FUNCTION_ID\",\"_testCases\":[{\"id\":\"case-1\"}]}}" \
  "{\"version\":0,\"kind\":\"test\",\"payload\":{\"kind\":\"function\",\"id\":\"$FUNCTION_ID\",\"_testCases\":[{\"id\":\"case-1\"}]}}"
expect_failure duplicate-function "duplicate identity: $FUNCTION_ID" "$duplicate_function_stream"

missing_case_id_stream="$TEMP_DIR/missing-case-id.ndjson"
write_stream "$missing_case_id_stream" \
  "{\"version\":0,\"kind\":\"test\",\"payload\":{\"kind\":\"function\",\"id\":\"$FUNCTION_ID\",\"_testCases\":[{\"id\":\"case-1\"}]}}" \
  "{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"testCaseStarted\",\"testID\":\"$FUNCTION_ID\",\"_testCase\":{}}}"
expect_failure missing-case-id "invalid test ID: $FUNCTION_ID" "$missing_case_id_stream"

case_suite_id_stream="$TEMP_DIR/case-suite-id.ndjson"
write_stream "$case_suite_id_stream" \
  '{"version":0,"kind":"event","payload":{"kind":"testCaseStarted","testID":"LaunchPadTests.EventParserTests","_testCase":{"id":"case-1"}}}'
expect_failure case-suite-id 'invalid event schema at line 1' "$case_suite_id_stream"

print -- 'test-event-parser: passed'
