#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

ROOT_DIR=${0:A:h:h}
WATCHDOG="$ROOT_DIR/scripts/run-with-timeout.sh"
export CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache

cd "$ROOT_DIR"

if [[ -n ${LAUNCHPAD_RELEASE_ARTIFACT_DIR:-} ]]; then
  ARTIFACT_DIR=$LAUNCHPAD_RELEASE_ARTIFACT_DIR
  mkdir -p "${ARTIFACT_DIR:h}"
  if ! mkdir "$ARTIFACT_DIR"; then
    print -u2 "release gate: artifact directory must not exist: $ARTIFACT_DIR"
    exit 1
  fi
else
  ARTIFACT_DIR=$(mktemp -d "$ROOT_DIR/.superpowers/sdd/release-gate.XXXXXX")
fi

MANIFEST="$ARTIFACT_DIR/manifest.txt"
{
  print -r -- "head=$(git rev-parse HEAD)"
  print -r -- "start=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  print -r -- "uname=$(/usr/bin/uname -a)"
  print -r -- "configuration=three debug Swift Testing runs and one release product build"
  print -r -- 'toolchain.begin'
  swift --version
  print -r -- 'toolchain.end'
} > "$MANIFEST"

EVENT_PARSER="$ARTIFACT_DIR/event-parser.swift"
/bin/cat > "$EVENT_PARSER" <<'SWIFT'
import Foundation

enum ParserError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidEvent(Int)
    case invalidTestID(String)
    case duplicateIdentity(String)
    case identityMismatch(String)
    case emptyStream

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: event-parser EVENTS EXECUTED VERSION IDENTITY"
        case .invalidEvent(let line):
            return "invalid event schema at line \(line)"
        case .invalidTestID(let id):
            return "invalid test ID: \(id)"
        case .duplicateIdentity(let identity):
            return "duplicate identity: \(identity)"
        case .identityMismatch(let kind):
            return "event identity mismatch: \(kind)"
        case .emptyStream:
            return "event stream is empty"
        }
    }
}

func parseEvents() throws {
    guard CommandLine.arguments.count == 5 else {
        throw ParserError.invalidArguments
    }

    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let executedURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let versionURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let identityURL = URL(fileURLWithPath: CommandLine.arguments[4])
    let data = try Data(contentsOf: inputURL)
    guard let stream = String(data: data, encoding: .utf8) else {
        throw ParserError.invalidEvent(1)
    }

    let lines = stream.split(whereSeparator: \Character.isNewline)
    guard !lines.isEmpty else {
        throw ParserError.emptyStream
    }

    let sourceSuffix = try NSRegularExpression(
        pattern: "/[^/]+\\.swift:[0-9]+:[0-9]+$"
    )
    var functionRecords = Set<String>()
    var functionStarts = Set<String>()
    var functionEnds = Set<String>()
    var caseRecords = Set<String>()
    var caseStarts = Set<String>()
    var caseEnds = Set<String>()

    func insertUnique(_ identity: String, into set: inout Set<String>) throws {
        guard set.insert(identity).inserted else {
            throw ParserError.duplicateIdentity(identity)
        }
    }

    func caseIdentity(testID: String, payload: [String: Any]) throws -> String {
        guard let testCase = payload["_testCase"] as? [String: Any],
              let caseID = testCase["id"] as? String,
              !caseID.isEmpty else {
            throw ParserError.invalidTestID(testID)
        }
        return "\(testID)\t\(caseID)"
    }

    for (index, line) in lines.enumerated() {
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        guard let event = object as? [String: Any],
              let kind = event["kind"] as? String,
              let payload = event["payload"] as? [String: Any],
              let version = event["version"] as? NSNumber,
              version.intValue == 0 else {
            throw ParserError.invalidEvent(index + 1)
        }

        if kind == "test" {
            guard let recordKind = payload["kind"] as? String else {
                throw ParserError.invalidEvent(index + 1)
            }
            guard recordKind == "function" else {
                continue
            }
            guard let testID = payload["id"] as? String, testID.contains("/") else {
                throw ParserError.invalidEvent(index + 1)
            }
            try insertUnique(testID, into: &functionRecords)
            if let testCases = payload["_testCases"] as? [[String: Any]] {
                for testCase in testCases {
                    guard let caseID = testCase["id"] as? String, !caseID.isEmpty else {
                        throw ParserError.invalidEvent(index + 1)
                    }
                    try insertUnique("\(testID)\t\(caseID)", into: &caseRecords)
                }
            }
            continue
        }

        guard kind == "event", let eventKind = payload["kind"] as? String else {
            throw ParserError.invalidEvent(index + 1)
        }
        guard let testID = payload["testID"] as? String else {
            continue
        }
        guard testID.contains("/") else {
            continue
        }

        switch eventKind {
        case "testStarted":
            try insertUnique(testID, into: &functionStarts)
        case "testEnded":
            guard let messages = payload["messages"] as? [[String: Any]],
                  messages.contains(where: { $0["symbol"] as? String == "pass" }) else {
                continue
            }
            try insertUnique(testID, into: &functionEnds)
        case "testCaseStarted":
            try insertUnique(
                try caseIdentity(testID: testID, payload: payload),
                into: &caseStarts
            )
        case "testCaseEnded":
            try insertUnique(
                try caseIdentity(testID: testID, payload: payload),
                into: &caseEnds
            )
        default:
            continue
        }
    }

    guard !functionRecords.isEmpty else {
        throw ParserError.emptyStream
    }
    guard functionRecords == functionStarts else {
        throw ParserError.identityMismatch("function records vs starts")
    }
    guard functionRecords == functionEnds else {
        throw ParserError.identityMismatch("function records vs passed ends")
    }
    guard caseRecords == caseStarts else {
        throw ParserError.identityMismatch("case records vs starts")
    }
    guard caseRecords == caseEnds else {
        throw ParserError.identityMismatch("case records vs ends")
    }

    var executed = Set<String>()
    for testID in functionRecords {
        let range = NSRange(testID.startIndex..<testID.endIndex, in: testID)
        guard let match = sourceSuffix.firstMatch(in: testID, range: range),
              match.range.location + match.range.length == range.length else {
            throw ParserError.invalidTestID(testID)
        }
        let canonicalID = (testID as NSString).replacingCharacters(
            in: match.range,
            with: ""
        )
        guard executed.insert(canonicalID).inserted else {
            throw ParserError.duplicateIdentity(canonicalID)
        }
    }

    let sortedFunctionRecords = functionRecords.sorted()
    let sortedFunctionStarts = functionStarts.sorted()
    let sortedFunctionEnds = functionEnds.sorted()
    let sortedCaseRecords = caseRecords.sorted()
    let sortedCaseStarts = caseStarts.sorted()
    let sortedCaseEnds = caseEnds.sorted()
    let identity: [String: Any] = [
        "version": 0,
        "functionRecords": sortedFunctionRecords,
        "functionStarts": sortedFunctionStarts,
        "functionPassedEnds": sortedFunctionEnds,
        "caseRecords": sortedCaseRecords,
        "caseStarts": sortedCaseStarts,
        "caseEnds": sortedCaseEnds,
    ]
    let identityData = try JSONSerialization.data(
        withJSONObject: identity,
        options: [.prettyPrinted, .sortedKeys]
    )
    try identityData.write(to: identityURL, options: .atomic)

    let executedOutput = executed.sorted().joined(separator: "\n") + "\n"
    try Data(executedOutput.utf8).write(to: executedURL, options: .atomic)
    try Data("0\n".utf8).write(to: versionURL, options: .atomic)
}

do {
    try parseEvents()
} catch {
    FileHandle.standardError.write(Data("event parser: \(error)\n".utf8))
    exit(1)
}
SWIFT

record_status() {
  local label=$1 status=$2
  print -r -- "command.${label}.status=${status}" >> "$MANIFEST"
}

record_check() {
  local label=$1
  shift

  set +e
  "$@"
  local status=$?
  set -e
  record_status "$label" "$status"
  return "$status"
}

assert_watchdog() {
  [[ -x "$WATCHDOG" ]]
}

assert_static_policy() {
  local legacy_pattern='import XCTest|XCTestCase|XCTAssert[A-Za-z]*|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:'
  local bypass_pattern='XCTSkip|\.disabled\(|\.enabled\(if:|Task\.sleep|RunLoop\.main\.run'
  local grid_legacy_pattern='delegate[[:space:]]*=[[:space:]]*self|NSCollectionViewDelegate|onItemSelected|onSelectionChanged|dragController|pasteboardUUIDReader'
  local host_legacy_pattern='interactionBounds|pageItem\(uuid:|moveSnapshotItem\(|itemsByUUID|snapshotMoves'
  local environment_pattern='ProcessInfo\.processInfo\.'environment
  local performance_skip_pattern='--ski''p[^[:space:]]*PerformanceTests'
  local performance_switch_pattern='retr''y|threshold[ _-]*multiplier'
  local own_supervisor_pattern='run_with_timeou''t\(\)|se''tpgrp|se''tpgid|(^|[[:space:];])tr''ap[[:space:]]+|/usr/bin/pe''rl'

  if rg -n --glob '*.swift' "$legacy_pattern" Tests; then
    print -u2 'release gate: legacy test framework residue detected'
    return 1
  fi
  if rg -n --glob '*.swift' "$bypass_pattern" Tests; then
    print -u2 'release gate: skip or fixed-wait API detected'
    return 1
  fi
  if rg -n "$grid_legacy_pattern" \
      Sources/LaunchPad/Views/AppGridCollectionView.swift; then
    print -u2 'release gate: obsolete main-grid delegate API detected'
    return 1
  fi
  if rg -n --glob 'AppGrid*.swift' '[Pp]roxy' \
      Sources/LaunchPad/Views; then
    print -u2 'release gate: main-grid proxy detected'
    return 1
  fi
  if rg -n "$host_legacy_pattern" \
      Sources/LaunchPad/Views/AppGridCollectionView.swift \
      Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
      Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
      Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift; then
    print -u2 'release gate: obsolete grid-host surface detected'
    return 1
  fi
  if rg -n 'setCurrentVisualPageIndex' \
      Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift; then
    print -u2 'release gate: grid-host page mutation detected'
    return 1
  fi
  if rg -n -U --pcre2 \
      '\b([A-Za-z_][A-Za-z0-9_]*)\.collectionView\(\s*\1\s*,' \
      Tests --glob '*.swift'; then
    print -u2 'release gate: direct main-grid delegate bypass detected'
    return 1
  fi
  if rg -n 'GridLayoutCalculator\.calculate\(screenWidth:' \
      Tests/LaunchPadTests/Performance/PerformanceTests.swift; then
    print -u2 'release gate: performance grid legacy API detected'
    return 1
  fi
  if rg -n "$environment_pattern|$performance_skip_pattern|$performance_switch_pattern" \
      Tests/LaunchPadTests/Performance/PerformanceTests.swift \
      scripts/test-release.sh; then
    print -u2 'release gate: performance bypass detected'
    return 1
  fi
  if rg -n "$own_supervisor_pattern" scripts/test-release.sh; then
    print -u2 'release gate: second timeout supervisor detected'
    return 1
  fi
}

append_process_matches() {
  local destination=$1
  shift

  pgrep "$@" >> "$destination" && return 0
  local status=$?
  (( status == 1 ))
}

capture_related_pids() {
  local destination=$1
  local raw_destination="${destination}.raw"

  : > "$raw_destination"
  append_process_matches "$raw_destination" -x swift-test || return 1
  append_process_matches "$raw_destination" -x swiftpm-testing-helper || return 1
  append_process_matches "$raw_destination" -x LaunchPadPackageTests || return 1
  append_process_matches "$raw_destination" -f \
    '(^|/)swiftpm-testing-helper([[:space:]]|$)' || return 1
  append_process_matches "$raw_destination" -f \
    '/LaunchPadPackageTests\.xctest/Contents/MacOS/LaunchPadPackageTests' || return 1
  LC_ALL=C sort -un "$raw_destination" > "$destination"
}

assert_invocation_gone() {
  local supervisor_file=$1 child_file=$2 baseline_file=$3 after_file=$4 delta_file=$5
  local pid_file pid

  for pid_file in "$supervisor_file" "$child_file"; do
    [[ -s "$pid_file" ]] || return 1
    pid=$(<"$pid_file")
    [[ "$pid" == <-> ]] || return 1
    if kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
  done

  capture_related_pids "$after_file"
  comm -13 "$baseline_file" "$after_file" > "$delta_file"
  [[ ! -s "$delta_file" ]]
}

run_watchdog() {
  local label=$1 timeout=$2
  shift 2

  local supervisor_file="$ARTIFACT_DIR/${label}.supervisor.pid"
  local child_file="$ARTIFACT_DIR/${label}.child.pid"
  local baseline_file="$ARTIFACT_DIR/${label}.baseline-pids"
  local after_file="$ARTIFACT_DIR/${label}.after-pids"
  local delta_file="$ARTIFACT_DIR/${label}.residue-pids"
  local status=0 residue_status=0

  if ! capture_related_pids "$baseline_file"; then
    record_status "$label" 1
    print -r -- "command.${label}.baseline_status=1" >> "$MANIFEST"
    return 1
  fi
  set +e
  RUN_TIMEOUT_SUPERVISOR_PIDFILE="$supervisor_file" \
    RUN_TIMEOUT_CHILD_PIDFILE="$child_file" \
    "$WATCHDOG" "$timeout" -- "$@"
  status=$?
  set -e

  assert_invocation_gone "$supervisor_file" "$child_file" \
    "$baseline_file" "$after_file" "$delta_file" || residue_status=$?
  record_status "$label" "$status"
  print -r -- "command.${label}.residue_status=${residue_status}" >> "$MANIFEST"

  (( status == 0 )) || return "$status"
  (( residue_status == 0 ))
}

run_watchdog_self_test() {
  local label=$1 flag=$2 status=0

  set +e
  "$WATCHDOG" "$flag"
  status=$?
  set -e
  record_status "$label" "$status"
  return "$status"
}

extract_discovery() {
  local raw=$1 list=$2

  LC_ALL=C rg '^LaunchPadTests\.' "$raw" | LC_ALL=C sort > "$list" || return 1
  [[ -s "$list" ]] || return 1
  if rg -n -v '^LaunchPadTests\.' "$list"; then
    return 1
  fi
  [[ $(rg -c '^LaunchPadTests\.PerformanceTests/' "$list") -eq 6 ]]
}

extract_execution_set() {
  local expected_count=$1 discovery=$2 executed=$3 version_file=$4 identity_file=$5

  [[ -s "$executed" ]] || return 1
  [[ -s "$identity_file" ]] || return 1
  [[ $(wc -l < "$executed" | tr -d ' ') -eq $expected_count ]] || return 1
  [[ $(wc -l < "$version_file" | tr -d ' ') -eq 1 ]] || return 1
  [[ $(<"$version_file") == 0 ]] || return 1
  cmp -s "$discovery" "$executed"
}

assert_run_log() {
  local log=$1 expected_count=$2 summary_file=$3
  local failure_pattern='↷|[Ss]kipped|✘|failed after|unexpected signal|signal [0-9]+|Fatal error|Abort tr''ap|Trace/BPT tr''ap|Segmentation fault|timed out'

  rg '^✔ Test run with ' "$log" > "$summary_file" || return 1
  [[ $(wc -l < "$summary_file" | tr -d ' ') -eq 1 ]] || return 1
  rg -q "^✔ Test run with ${expected_count} tests in [0-9]+ suites? passed after [0-9.]+ seconds\.$" \
    "$summary_file" || return 1
  if rg -n "$failure_pattern" "$log"; then
    return 1
  fi

  local name
  for name in \
    'SearchEngine 1000 项无缓存 median/p95 < 50ms' \
    'SearchEngine 缓存命中 median/p95 < 1ms' \
    'Diffable snapshot 1002 项 median/p95 < 10ms' \
    '动态 GridMetrics 三种 viewport median/p95 < 1ms' \
    'IconCache 1000 次内存命中 median/p95 < 300ms' \
    'IconCache 1000 次访问后无磁盘重复写入'
  do
    rg -q -F "Test \"$name\" passed" "$log" || return 1
  done
}

compare_artifacts() {
  cmp -s "$1" "$2"
}

record_check watchdog-executable assert_watchdog
record_check syntax zsh -n "$WATCHDOG" "$0"
record_check static-policy assert_static_policy
run_watchdog_self_test self-test-timeout --self-test-timeout
run_watchdog_self_test self-test-signal --self-test-signal
run_watchdog_self_test self-test-nonzero --self-test-nonzero

for run in 1 2 3; do
  print "release gate: test run ${run}/3"
  raw_list="$ARTIFACT_DIR/tests-${run}.raw"
  list="$ARTIFACT_DIR/tests-${run}.list"
  log="$ARTIFACT_DIR/tests-${run}.log"
  events="$ARTIFACT_DIR/tests-${run}.events"
  executed="$ARTIFACT_DIR/executed-${run}.list"
  event_version="$ARTIFACT_DIR/events-${run}.version"
  event_identity="$ARTIFACT_DIR/events-${run}.identity.json"
  summary_file="$ARTIFACT_DIR/tests-${run}.summary"

  run_watchdog "discovery-${run}" 180 /bin/zsh -o pipefail -c \
    'swift test --disable-sandbox --disable-xctest --enable-swift-testing list 2>&1 | tee "$1"' \
    _ "$raw_list"
  record_check "discovery-${run}-contract" extract_discovery "$raw_list" "$list"
  if (( run > 1 )); then
    record_check "discovery-${run}-stable" compare_artifacts \
      "$ARTIFACT_DIR/tests-1.list" "$list"
  fi
  expected_count=$(wc -l < "$list" | tr -d ' ')

  run_watchdog "tests-${run}" 900 /bin/zsh -o pipefail -c \
    'swift test --disable-sandbox --disable-xctest --enable-swift-testing --no-parallel --event-stream-output-path "$2" --event-stream-version 0 2>&1 | tee "$1"' \
    _ "$log" "$events"
  record_check "tests-${run}-log-contract" assert_run_log \
    "$log" "$expected_count" "$summary_file"
  run_watchdog "tests-${run}-event-parser" 180 /usr/bin/swift \
    "$EVENT_PARSER" "$events" "$executed" "$event_version" "$event_identity"
  record_check "tests-${run}-execution-contract" extract_execution_set \
    "$expected_count" "$list" "$executed" "$event_version" "$event_identity"
  if (( run > 1 )); then
    record_check "tests-${run}-execution-stable" compare_artifacts \
      "$ARTIFACT_DIR/executed-1.list" "$executed"
    record_check "tests-${run}-event-version-stable" compare_artifacts \
      "$ARTIFACT_DIR/events-1.version" "$event_version"
  fi
  print -r -- "summary.run${run}=$(<"$summary_file")" >> "$MANIFEST"
  print -r -- "event_version.run${run}=$(<"$event_version")" >> "$MANIFEST"
done

print 'release gate: release build'
run_watchdog release-build 900 /bin/zsh -o pipefail -c \
  'swift build -c release --product LaunchPadApp 2>&1 | tee "$1"' \
  _ "$ARTIFACT_DIR/release-build.log"
print -r -- 'result=passed' >> "$MANIFEST"
print "release gate: artifacts $ARTIFACT_DIR"
