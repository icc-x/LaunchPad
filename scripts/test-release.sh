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

RESULT_STATUS="$ARTIFACT_DIR/result.status"
RESULT_STATUS_TEMP="$ARTIFACT_DIR/result.status.passed"
print -r -- 'failed' > "$RESULT_STATUS"

MANIFEST="$ARTIFACT_DIR/manifest.txt"
HEAD_AT_START=$(git rev-parse HEAD)
{
  print -r -- "head=$HEAD_AT_START"
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
import CoreFoundation

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

    func requiredTestID(payload: [String: Any], line: Int) throws -> String {
        guard let testID = payload["testID"] as? String,
              !testID.isEmpty,
              testID.contains("/") else {
            throw ParserError.invalidEvent(line)
        }
        return testID
    }

    for (index, line) in lines.enumerated() {
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        guard let event = object as? [String: Any],
              let kind = event["kind"] as? String,
              let payload = event["payload"] as? [String: Any],
              let versionValue = event["version"],
              CFGetTypeID(versionValue as CFTypeRef) == CFNumberGetTypeID(),
              let version = versionValue as? NSNumber,
              !CFNumberIsFloatType(version),
              version.int64Value == 0 else {
            throw ParserError.invalidEvent(index + 1)
        }

        if kind == "test" {
            guard let recordKind = payload["kind"] as? String else {
                throw ParserError.invalidEvent(index + 1)
            }
            guard recordKind == "function" else {
                continue
            }
            guard let testID = payload["id"] as? String,
                  !testID.isEmpty,
                  testID.contains("/") else {
                throw ParserError.invalidEvent(index + 1)
            }
            try insertUnique(testID, into: &functionRecords)
            if payload.keys.contains("_testCases") {
                guard let testCases = payload["_testCases"] as? [[String: Any]] else {
                    throw ParserError.invalidEvent(index + 1)
                }
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

        switch eventKind {
        case "testStarted":
            let testID = try requiredTestID(payload: payload, line: index + 1)
            try insertUnique(testID, into: &functionStarts)
        case "testEnded":
            let testID = try requiredTestID(payload: payload, line: index + 1)
            guard let messages = payload["messages"] as? [[String: Any]],
                  messages.contains(where: { $0["symbol"] as? String == "pass" }) else {
                continue
            }
            try insertUnique(testID, into: &functionEnds)
        case "testCaseStarted":
            let testID = try requiredTestID(payload: payload, line: index + 1)
            try insertUnique(
                try caseIdentity(testID: testID, payload: payload),
                into: &caseStarts
            )
        case "testCaseEnded":
            let testID = try requiredTestID(payload: payload, line: index + 1)
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
    guard !caseRecords.isEmpty else {
        throw ParserError.identityMismatch("parameter case records are empty")
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
  local label=$1 command_status=$2
  print -r -- "command.${label}.status=${command_status}" >> "$MANIFEST"
}

record_check() {
  local label=$1
  shift

  set +e
  "$@"
  local command_status=$?
  set -e
  record_status "$label" "$command_status"
  return "$command_status"
}

assert_watchdog() {
  [[ -x "$WATCHDOG" ]]
}

capture_provenance() {
  local prefix=$1
  local branch_file="$ARTIFACT_DIR/${prefix}-git-branch.txt"
  local head_file="$ARTIFACT_DIR/${prefix}-git-head.txt"
  local status_file="$ARTIFACT_DIR/${prefix}-git-status.txt"
  local controlled_status_file="$ARTIFACT_DIR/${prefix}-controlled-status.txt"
  local controlled_files_file="$ARTIFACT_DIR/${prefix}-controlled-files.list"
  local controlled_hashes_file="$ARTIFACT_DIR/${prefix}-controlled-files.sha256"
  local controlled_hash_file="$ARTIFACT_DIR/${prefix}-controlled-tree.sha256"
  local controlled_path

  git branch --show-current > "$branch_file" || return 1
  git rev-parse HEAD > "$head_file" || return 1
  git status --porcelain=v1 --branch --untracked-files=all > "$status_file" || return 1
  git status --porcelain=v1 --untracked-files=all -- \
    Sources Tests scripts Package.swift Resources > "$controlled_status_file" || return 1
  git ls-files -- Sources Tests scripts Package.swift Resources \
    > "$controlled_files_file" || return 1
  [[ -s "$controlled_files_file" ]] || return 1

  : > "$controlled_hashes_file"
  while IFS= read -r controlled_path; do
    [[ -f "$controlled_path" ]] || return 1
    /usr/bin/shasum -a 256 "$controlled_path" \
      >> "$controlled_hashes_file" || return 1
  done < "$controlled_files_file"
  /usr/bin/shasum -a 256 "$controlled_hashes_file" > "$controlled_hash_file" || return 1
}

assert_start_provenance() {
  capture_provenance start || return $?
  [[ $(<"$ARTIFACT_DIR/start-git-branch.txt") == release-readiness ]] || return 1
  [[ $(<"$ARTIFACT_DIR/start-git-head.txt") == "$HEAD_AT_START" ]] || return 1
  [[ ! -s "$ARTIFACT_DIR/start-controlled-status.txt" ]] || return 1
  [[ $(wc -l < "$ARTIFACT_DIR/start-controlled-files.list" | tr -d ' ') \
      -eq $(wc -l < "$ARTIFACT_DIR/start-controlled-files.sha256" | tr -d ' ') ]]
}

capture_and_compare_end_provenance() {
  local name
  capture_provenance end || return $?
  for name in git-branch.txt git-head.txt git-status.txt \
      controlled-status.txt controlled-files.list \
      controlled-files.sha256 controlled-tree.sha256; do
    cmp -s "$ARTIFACT_DIR/start-${name}" "$ARTIFACT_DIR/end-${name}" \
      || return 1
  done
}

assert_no_matches() {
  local label=$1 message=$2
  shift 2
  local output="$ARTIFACT_DIR/static-${label}.log"
  local scan_status

  rg "$@" > "$output" 2>&1 && scan_status=0 || scan_status=$?
  print -r -- "command.static-${label}.scan_status=${scan_status}" >> "$MANIFEST"
  case $scan_status in
    0)
      /bin/cat "$output" >&2
      print -u2 "release gate: $message"
      return 1
      ;;
    1)
      return 0
      ;;
    *)
      /bin/cat "$output" >&2
      print -u2 "release gate: static scan failed (${label}, status ${scan_status})"
      return "$scan_status"
      ;;
  esac
}

assert_static_policy() {
  local legacy_pattern='import XCTest|XCTestCase|XCTAssert[A-Za-z]*|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:'
  local trait_pattern='XCTSkip|\.disabled\(|\.enabled\(if:'
  local constant_expect_pattern='#expect[[:space:]]*\([[:space:]]*true[[:space:]]*\)'
  local fixed_wait_pattern='Task\.sleep|Thread\.sleep|RunLoop\.(main|current)\.run|(?<![A-Za-z0-9_.])(sleep|usleep)\s*\('
  local system_boundary_pattern='UserDefaults\.standard\.(set|removeObject)\s*\(|SMAppService\.mainApp\.(register|unregister)\s*\(|NSWorkspace\.shared\.(open|openApplication)\s*\(|NSRunningApplication.*\.activate\s*\(|NSEvent\.addLocalMonitor|CGEvent\.tapCreate|CFRunLoopAddSource|NSStatusBar\.system'
  local user_database_pattern='FileManager\.default\.urls\(\s*for:\s*\.applicationSupportDirectory|NSSearchPathForDirectoriesInDomains\(\s*\.applicationSupportDirectory|[/~]Library/Application Support'
  local grid_legacy_pattern='delegate[[:space:]]*=[[:space:]]*self|NSCollectionViewDelegate|onItemSelected|onSelectionChanged|dragController|pasteboardUUIDReader'
  local host_legacy_pattern='interactionBounds|pageItem\(uuid:|moveSnapshotItem\(|itemsByUUID|snapshotMoves'
  local environment_pattern='ProcessInfo\.processInfo\.'environment
  local performance_skip_pattern='--ski''p(=|[[:space:]]+)[^[:space:]]*PerformanceTests'
  local performance_switch_pattern='retr''y|threshold[ _-]*multiplier'
  local own_supervisor_pattern='run_with_timeou''t\(\)|se''tpgrp|se''tpgid|(^|[[:space:];])tr''ap[[:space:]]+|/usr/bin/pe''rl'

  assert_no_matches legacy-xctest 'legacy test framework residue detected' \
    -n --glob '*.swift' "$legacy_pattern" Tests || return $?
  assert_no_matches test-trait 'skip test trait detected' \
    -n --glob '*.swift' "$trait_pattern" Tests || return $?
  assert_no_matches constant-expect 'literal constant expectation detected' \
    -n --glob '*.swift' "$constant_expect_pattern" Tests || return $?
  assert_no_matches fixed-wait 'fixed-wait API detected' \
    -n --pcre2 --glob '*.swift' "$fixed_wait_pattern" Tests || return $?
  assert_no_matches host-boundary 'real host mutation or acquisition detected' \
    -n --pcre2 --glob '*.swift' "$system_boundary_pattern" Tests || return $?
  assert_no_matches user-database 'user Application Support database path detected' \
    -n -U --pcre2 --glob '*.swift' "$user_database_pattern" Tests || return $?
  assert_no_matches grid-delegate 'obsolete main-grid delegate API detected' \
    -n "$grid_legacy_pattern" Sources/LaunchPad/Views/AppGridCollectionView.swift \
    || return $?
  assert_no_matches grid-proxy 'main-grid proxy detected' \
    -n --glob 'AppGrid*.swift' '[Pp]roxy' Sources/LaunchPad/Views || return $?
  assert_no_matches grid-host 'obsolete grid-host surface detected' \
    -n "$host_legacy_pattern" \
    Sources/LaunchPad/Views/AppGridCollectionView.swift \
    Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
    Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
    Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift || return $?
  assert_no_matches grid-page-mutation 'grid-host page mutation detected' \
    -n 'setCurrentVisualPageIndex' \
    Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift || return $?
  assert_no_matches grid-delegate-bypass 'direct main-grid delegate bypass detected' \
    -n -U --pcre2 '\b([A-Za-z_][A-Za-z0-9_]*)\.collectionView\(\s*\1\s*,' \
    Tests --glob '*.swift' || return $?
  assert_no_matches performance-grid 'performance grid legacy API detected' \
    -n 'GridLayoutCalculator\.calculate\(screenWidth:' \
    Tests/LaunchPadTests/Performance/PerformanceTests.swift || return $?
  assert_no_matches performance-bypass 'performance bypass detected' \
    -n "$environment_pattern|$performance_skip_pattern|$performance_switch_pattern" \
    Tests/LaunchPadTests/Performance/PerformanceTests.swift scripts/test-release.sh \
    || return $?
  assert_no_matches second-supervisor 'second timeout supervisor detected' \
    -n --pcre2 "$own_supervisor_pattern" scripts/test-release.sh || return $?
}

append_process_matches() {
  local destination=$1
  shift

  pgrep "$@" >> "$destination" && return 0
  local command_status=$?
  (( command_status == 1 )) && return 0
  return "$command_status"
}

capture_related_pids() {
  local destination=$1
  local raw_destination="${destination}.raw"

  : > "$raw_destination"
  append_process_matches "$raw_destination" -x swift-test || return $?
  append_process_matches "$raw_destination" -x swiftpm-testing-helper || return $?
  append_process_matches "$raw_destination" -x LaunchPadPackageTests || return $?
  append_process_matches "$raw_destination" -f \
    '(^|/)swiftpm-testing-helper([[:space:]]|$)' || return $?
  append_process_matches "$raw_destination" -f \
    '/LaunchPadPackageTests\.xctest/Contents/MacOS/LaunchPadPackageTests' || return $?
  LC_ALL=C sort -u "$raw_destination" > "$destination" || return $?
}

capture_token_pids() {
  local destination=$1 token=$2
  local snapshot="${destination}.ps"
  LC_ALL=C /bin/ps eww -axo pid=,command= > "$snapshot" || return 1
  /usr/bin/awk \
    -v marker="LAUNCHPAD_RELEASE_INVOCATION_TOKEN=${token}" \
    'index($0, marker) { print $1 }' "$snapshot" \
    | LC_ALL=C sort -u > "$destination"
}

assert_invocation_gone() {
  local label=$1 token=$2 wrapper_file=$3 supervisor_file=$4 child_file=$5
  local process_group_file=$6 token_after_file=$7 related_after_file=$8
  local conflict_file=$9
  local pid_file pid process_group child exact_pid_status=0 process_group_status=0
  local token_enumeration_status=0 token_residue_status=0
  local environment_enumeration_status=0 environment_conflict_status=0

  for pid_file in "$wrapper_file" "$supervisor_file" "$child_file"; do
    if [[ ! -s "$pid_file" ]]; then
      exact_pid_status=1
      break
    fi
    pid=$(<"$pid_file")
    if [[ "$pid" != <-> ]] || kill -0 "$pid" 2>/dev/null; then
      exact_pid_status=1
      break
    fi
  done
  print -r -- "command.${label}.exact_pid_status=${exact_pid_status}" >> "$MANIFEST"

  if [[ ! -s "$process_group_file" || ! -s "$child_file" ]]; then
    process_group_status=1
  else
    process_group=$(<"$process_group_file")
    child=$(<"$child_file")
    if [[ "$process_group" != <-> || "$process_group" != "$child" ]] \
        || kill -0 -- "-$process_group" 2>/dev/null; then
      process_group_status=1
    fi
  fi
  print -r -- "command.${label}.process_group_status=${process_group_status}" \
    >> "$MANIFEST"

  capture_token_pids "$token_after_file" "$token" \
    || token_enumeration_status=$?
  if (( token_enumeration_status == 0 )) && [[ -s "$token_after_file" ]]; then
    token_residue_status=1
  fi
  print -r -- \
    "command.${label}.token_enumeration_status=${token_enumeration_status}" \
    >> "$MANIFEST"
  print -r -- "command.${label}.token_residue_status=${token_residue_status}" \
    >> "$MANIFEST"

  capture_related_pids "$related_after_file" \
    || environment_enumeration_status=$?
  if (( environment_enumeration_status == 0 )); then
    LC_ALL=C comm -23 "$related_after_file" "$token_after_file" \
      > "$conflict_file" || environment_enumeration_status=$?
  fi
  if (( environment_enumeration_status == 0 )) && [[ -s "$conflict_file" ]]; then
    environment_conflict_status=1
  fi
  print -r -- \
    "command.${label}.environment_after_enumeration_status=${environment_enumeration_status}" \
    >> "$MANIFEST"
  print -r -- \
    "command.${label}.environment_conflict_status=${environment_conflict_status}" \
    >> "$MANIFEST"

  (( exact_pid_status == 0 \
      && process_group_status == 0 \
      && token_enumeration_status == 0 \
      && token_residue_status == 0 \
      && environment_enumeration_status == 0 \
      && environment_conflict_status == 0 ))
}

run_watchdog() {
  local label=$1 timeout=$2
  shift 2

  local wrapper_file="$ARTIFACT_DIR/${label}.wrapper.pid"
  local supervisor_file="$ARTIFACT_DIR/${label}.supervisor.pid"
  local child_file="$ARTIFACT_DIR/${label}.child.pid"
  local process_group_file="$ARTIFACT_DIR/${label}.process-group.pid"
  local environment_before_file="$ARTIFACT_DIR/${label}.environment-before.pids"
  local environment_after_file="$ARTIFACT_DIR/${label}.environment-after.pids"
  local environment_conflict_file="$ARTIFACT_DIR/${label}.environment-conflict.pids"
  local token_after_file="$ARTIFACT_DIR/${label}.token-residue.pids"
  local token="${label}-$(/usr/bin/uuidgen)"
  local command_status=0 residue_status=0 environment_enumeration_status=0
  local environment_conflict_status=0

  capture_related_pids "$environment_before_file" \
    || environment_enumeration_status=$?
  if (( environment_enumeration_status == 0 )) \
      && [[ -s "$environment_before_file" ]]; then
    environment_conflict_status=1
  fi
  print -r -- \
    "command.${label}.environment_before_enumeration_status=${environment_enumeration_status}" \
    >> "$MANIFEST"
  print -r -- \
    "command.${label}.environment_conflict_status=${environment_conflict_status}" \
    >> "$MANIFEST"
  if (( environment_enumeration_status != 0 \
      || environment_conflict_status != 0 )); then
    record_status "$label" 'not-run'
    print -r -- "command.${label}.residue_status=not-run" >> "$MANIFEST"
    return 1
  fi
  print -r -- "command.${label}.invocation_token=${token}" >> "$MANIFEST"
  set +e
  LAUNCHPAD_RELEASE_INVOCATION_TOKEN="$token" \
    RUN_TIMEOUT_WRAPPER_PIDFILE="$wrapper_file" \
    RUN_TIMEOUT_SUPERVISOR_PIDFILE="$supervisor_file" \
    RUN_TIMEOUT_CHILD_PIDFILE="$child_file" \
    RUN_TIMEOUT_PROCESS_GROUP_PIDFILE="$process_group_file" \
    "$WATCHDOG" "$timeout" -- /usr/bin/env \
      -u RUN_TIMEOUT_WRAPPER_PIDFILE \
      -u RUN_TIMEOUT_SUPERVISOR_PIDFILE \
      -u RUN_TIMEOUT_CHILD_PIDFILE \
      -u RUN_TIMEOUT_PROCESS_GROUP_PIDFILE \
      "$@"
  command_status=$?
  set -e

  assert_invocation_gone "$label" "$token" "$wrapper_file" \
    "$supervisor_file" "$child_file" "$process_group_file" \
    "$token_after_file" "$environment_after_file" \
    "$environment_conflict_file" || residue_status=$?
  record_status "$label" "$command_status"
  print -r -- "command.${label}.residue_status=${residue_status}" >> "$MANIFEST"

  (( command_status == 0 )) || return "$command_status"
  (( residue_status == 0 ))
}

extract_discovery() {
  local raw=$1 list=$2

  LC_ALL=C rg '^LaunchPadTests\.' "$raw" | LC_ALL=C sort > "$list" || return 1
  [[ -s "$list" ]] || return 1
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
  local label=$1 log=$2 expected_count=$3 summary_file=$4 normalized_summary=$5
  local failure_pattern='↷|[Ss]kipped|✘|failed after|unexpected signal|signal [0-9]+|Fatal error|Abort tr''ap|Trace/BPT tr''ap|Segmentation fault|timed out'

  rg '^✔ Test run with ' "$log" > "$summary_file" || return 1
  [[ $(wc -l < "$summary_file" | tr -d ' ') -eq 1 ]] || return 1
  rg -q "^✔ Test run with ${expected_count} tests in [0-9]+ suites? passed after [0-9.]+ seconds\.$" \
    "$summary_file" || return 1
  sed -E 's/ passed after [0-9.]+ seconds\.$/ passed/' \
    "$summary_file" > "$normalized_summary" || return 1
  assert_no_matches "${label}-failure-markers" 'test failure marker detected' \
    -n "$failure_pattern" "$log" || return $?

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

probe_provenance_mutation() {
  local original_directory=$PWD
  local repository=$(mktemp -d /tmp/launchpad-provenance-probe.XXXXXX)
  local probe_status=0 comparison_status=0

  mkdir -p "$repository/Sources" "$repository/Tests" \
    "$repository/scripts" "$repository/Resources" || probe_status=$?
  if (( probe_status == 0 )); then
    print -r -- 'let value = 1' > "$repository/Sources/probe.swift" \
      || probe_status=$?
    print -r -- '// test' > "$repository/Tests/probe.swift" \
      || probe_status=$?
    print -r -- '#!/bin/zsh' > "$repository/scripts/probe.sh" \
      || probe_status=$?
    print -r -- '// package' > "$repository/Package.swift" \
      || probe_status=$?
    print -r -- 'resource' > "$repository/Resources/probe.txt" \
      || probe_status=$?
  fi
  if (( probe_status == 0 )); then
    cd "$repository" || probe_status=$?
    git init -q -b release-readiness || probe_status=$?
    git config user.name 'LaunchPad Probe' || probe_status=$?
    git config user.email 'launchpad-probe@example.invalid' || probe_status=$?
    git add Sources Tests scripts Package.swift Resources || probe_status=$?
    git commit -q -m baseline || probe_status=$?
    HEAD_AT_START=$(git rev-parse HEAD) || probe_status=$?
    assert_start_provenance || probe_status=$?
  fi
  if (( probe_status == 0 )); then
    print -r -- 'let mutation = 2' >> Sources/probe.swift || probe_status=$?
    set +e
    capture_and_compare_end_provenance
    comparison_status=$?
    set -e
    [[ $comparison_status -ne 0 ]] || probe_status=1
    cmp -s "$ARTIFACT_DIR/start-git-branch.txt" \
      "$ARTIFACT_DIR/end-git-branch.txt" || probe_status=1
    cmp -s "$ARTIFACT_DIR/start-git-head.txt" \
      "$ARTIFACT_DIR/end-git-head.txt" || probe_status=1
    if cmp -s "$ARTIFACT_DIR/start-git-status.txt" \
        "$ARTIFACT_DIR/end-git-status.txt"; then
      probe_status=1
    fi
    if cmp -s "$ARTIFACT_DIR/start-controlled-files.sha256" \
        "$ARTIFACT_DIR/end-controlled-files.sha256"; then
      probe_status=1
    fi
  fi
  cd "$original_directory" || return 1
  rm -rf "$repository"
  return "$probe_status"
}

probe_invocation_ownership() {
  local probe_exit_code=0 unrelated_pid=0

  run_watchdog probe-token-normal 10 /bin/zsh -c \
    '[[ -n ${LAUNCHPAD_RELEASE_INVOCATION_TOKEN:-} ]]' || return $?

  if run_watchdog probe-token-nonzero 10 /bin/zsh -c 'exit 17'; then
    probe_exit_code=0
  else
    probe_exit_code=$?
  fi
  [[ $probe_exit_code -eq 17 ]] || return 1
  rg -q '^command\.probe-token-nonzero\.residue_status=0$' "$MANIFEST" \
    || return 1

  if run_watchdog probe-token-timeout 1 /bin/sleep 30; then
    probe_exit_code=0
  else
    probe_exit_code=$?
  fi
  [[ $probe_exit_code -eq 124 ]] || return 1
  rg -q '^command\.probe-token-timeout\.residue_status=0$' "$MANIFEST" \
    || return 1

  ARGV0=swiftpm-testing-helper /bin/sleep 30 &
  unrelated_pid=$!
  if run_watchdog probe-environment-conflict 10 /usr/bin/true; then
    probe_exit_code=0
  else
    probe_exit_code=$?
  fi
  kill "$unrelated_pid" 2>/dev/null || true
  wait "$unrelated_pid" 2>/dev/null || true
  [[ $probe_exit_code -ne 0 ]] || return 1
  rg -q \
    '^command\.probe-environment-conflict\.environment_conflict_status=1$' \
    "$MANIFEST" || return 1
  rg -q '^command\.probe-environment-conflict\.residue_status=not-run$' \
    "$MANIFEST" || return 1
}

case ${1:-} in
  --probe-provenance-mutation)
    probe_provenance_mutation
    exit $?
    ;;
  --probe-invocation-ownership)
    probe_invocation_ownership
    exit $?
    ;;
esac

record_check watchdog-executable assert_watchdog
record_check syntax zsh -n "$WATCHDOG" "$0"
record_check provenance-start assert_start_provenance
record_check static-policy assert_static_policy
run_watchdog self-test-normal 60 "$WATCHDOG" --self-test-normal
run_watchdog self-test-timeout 60 "$WATCHDOG" --self-test-timeout
run_watchdog self-test-signal 60 "$WATCHDOG" --self-test-signal
run_watchdog self-test-nonzero 60 "$WATCHDOG" --self-test-nonzero

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
  normalized_summary="$ARTIFACT_DIR/tests-${run}.normalized-summary"

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
    "tests-${run}" "$log" "$expected_count" "$summary_file" "$normalized_summary"
  run_watchdog "tests-${run}-event-parser" 180 /usr/bin/swift \
    "$EVENT_PARSER" "$events" "$executed" "$event_version" "$event_identity"
  record_check "tests-${run}-execution-contract" extract_execution_set \
    "$expected_count" "$list" "$executed" "$event_version" "$event_identity"
  if (( run > 1 )); then
    record_check "tests-${run}-execution-stable" compare_artifacts \
      "$ARTIFACT_DIR/executed-1.list" "$executed"
    record_check "tests-${run}-event-version-stable" compare_artifacts \
      "$ARTIFACT_DIR/events-1.version" "$event_version"
    record_check "tests-${run}-identity-stable" compare_artifacts \
      "$ARTIFACT_DIR/events-1.identity.json" "$event_identity"
    record_check "tests-${run}-summary-stable" compare_artifacts \
      "$ARTIFACT_DIR/tests-1.normalized-summary" "$normalized_summary"
  fi
  print -r -- "summary.run${run}=$(<"$summary_file")" >> "$MANIFEST"
  print -r -- "event_version.run${run}=$(<"$event_version")" >> "$MANIFEST"
done

print 'release gate: release build'
run_watchdog release-build 900 /bin/zsh -o pipefail -c \
  'swift build -c release --product LaunchPadApp 2>&1 | tee "$1"' \
  _ "$ARTIFACT_DIR/release-build.log"
record_check provenance-end capture_and_compare_end_provenance
print -r -- 'result=passed' >> "$MANIFEST"
print -r -- 'passed' > "$RESULT_STATUS_TEMP"
/bin/mv -f "$RESULT_STATUS_TEMP" "$RESULT_STATUS"
print "release gate: artifacts $ARTIFACT_DIR"
