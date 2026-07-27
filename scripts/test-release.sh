#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

ROOT_DIR=${0:A:h:h}
WATCHDOG="$ROOT_DIR/scripts/run-with-timeout.sh"
unset LAUNCHPAD_PROCESS_PROBE_SYNTHETIC_ERRNO

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
ARTIFACT_DIR=${ARTIFACT_DIR:A}

RESULT_STATUS="$ARTIFACT_DIR/result.status"
RESULT_STATUS_TEMP="$ARTIFACT_DIR/result.status.passed"
print -r -- 'failed' > "$RESULT_STATUS"

SWIFTPM_SCRATCH_DIR="$ARTIFACT_DIR/swiftpm-scratch"
SWIFTPM_CACHE_DIR="$ARTIFACT_DIR/swiftpm-cache"
CLANG_MODULE_CACHE_PATH="$ARTIFACT_DIR/clang-module-cache"
SWIFTPM_MODULECACHE_OVERRIDE="$ARTIFACT_DIR/swiftpm-module-cache"
mkdir -p "$SWIFTPM_SCRATCH_DIR" "$SWIFTPM_CACHE_DIR" \
  "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
export SWIFTPM_SCRATCH_DIR SWIFTPM_CACHE_DIR
export CLANG_MODULE_CACHE_PATH SWIFTPM_MODULECACHE_OVERRIDE

typeset -ar AUTHORITATIVE_SWIFTPM_INVOCATIONS=(
  discovery-1 tests-1
  discovery-2 tests-2
  discovery-3 tests-3
  release-build
)
typeset -a RECORDED_SWIFTPM_INVOCATIONS=()

MANIFEST="$ARTIFACT_DIR/manifest.txt"
HEAD_AT_START=$(git rev-parse HEAD)
{
  print -r -- "head=$HEAD_AT_START"
  print -r -- "start=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  print -r -- "uname=$(/usr/bin/uname -a)"
  print -r -- "configuration=three debug Swift Testing runs and one release product build"
  print -r -- "swiftpm_scratch_path=$SWIFTPM_SCRATCH_DIR"
  print -r -- "swiftpm_cache_path=$SWIFTPM_CACHE_DIR"
  print -r -- "clang_module_cache_path=$CLANG_MODULE_CACHE_PATH"
  print -r -- "swiftpm_module_cache_override=$SWIFTPM_MODULECACHE_OVERRIDE"
  print -r -- 'toolchain.begin'
  swift --version
  print -r -- 'toolchain.end'
} > "$MANIFEST"

readonly EVENT_PARSER="$ROOT_DIR/scripts/parse-test-events.swift"
[[ -f "$EVENT_PARSER" ]] || {
  print -u2 "release gate: missing event parser: $EVENT_PARSER"
  exit 1
}

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
  /usr/bin/shasum -a 256 "$controlled_hashes_file" \
    | /usr/bin/awk '{ print $1 }' > "$controlled_hash_file" || return 1
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
  local own_supervisor_pattern='run_with_timeou''t\(\)|se''tpgrp|se''tpgid|(^|[[:space:];])tr''ap[[:space:]]+'

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
  assert_swiftpm_resource_contract || return $?
}

assert_swiftpm_resource_contract() {
  local expected_invocations=(
    discovery-1 tests-1
    discovery-2 tests-2
    discovery-3 tests-3
    release-build
  )
  local source="$ROOT_DIR/scripts/test-release.sh"
  local command_source="$ARTIFACT_DIR/static-swiftpm-commands.sh"
  local test_template_count=0 build_template_count=0 swiftpm_template_count=0
  local record_template_count=0 loop_template_count=0
  local host_capture_count=0 unique_invocation_count=0
  local host_capture_pattern='capture_related_''pids|append_process_''matches|pg''rep'

  [[ ${#AUTHORITATIVE_SWIFTPM_INVOCATIONS[@]} -eq 7 ]] || return 1
  [[ "${(j:|:)AUTHORITATIVE_SWIFTPM_INVOCATIONS}" \
      == "${(j:|:)expected_invocations}" ]] || return 1
  unique_invocation_count=$(print -l -- "${AUTHORITATIVE_SWIFTPM_INVOCATIONS[@]}" \
    | LC_ALL=C sort -u | wc -l | tr -d ' ') || return 1
  [[ $unique_invocation_count -eq 7 ]] || return 1

  [[ "$SWIFTPM_SCRATCH_DIR" == "$ARTIFACT_DIR"/* ]] || return 1
  [[ "$SWIFTPM_CACHE_DIR" == "$ARTIFACT_DIR"/* ]] || return 1
  [[ "$CLANG_MODULE_CACHE_PATH" == "$ARTIFACT_DIR"/* ]] || return 1
  [[ "$SWIFTPM_MODULECACHE_OVERRIDE" == "$ARTIFACT_DIR"/* ]] || return 1
  [[ -d "$SWIFTPM_SCRATCH_DIR" && -d "$SWIFTPM_CACHE_DIR" ]] || return 1
  [[ -d "$CLANG_MODULE_CACHE_PATH" && -d "$SWIFTPM_MODULECACHE_OVERRIDE" ]] \
    || return 1

  /usr/bin/awk '
    /^# AUTHORITATIVE_SWIFTPM_COMMANDS_BEGIN$/ { capture = 1; next }
    /^# AUTHORITATIVE_SWIFTPM_COMMANDS_END$/ { capture = 0; next }
    capture { print }
  ' "$source" > "$command_source" || return 1
  test_template_count=$(rg -c -- \
    'swift test --scratch-path "\$SWIFTPM_SCRATCH_DIR" --cache-path "\$SWIFTPM_CACHE_DIR"' \
    "$command_source") || test_template_count=0
  build_template_count=$(rg -c -- \
    'swift build --scratch-path "\$SWIFTPM_SCRATCH_DIR" --cache-path "\$SWIFTPM_CACHE_DIR"' \
    "$command_source") || build_template_count=0
  swiftpm_template_count=$(rg -c -- 'swift (test|build)' "$command_source") \
    || swiftpm_template_count=0
  record_template_count=$(rg -c -- \
    'record_swiftpm_invocation_resources ' "$command_source") \
    || record_template_count=0
  loop_template_count=$(rg -c -- '^for run in 1 2 3; do$' "$command_source") \
    || loop_template_count=0
  host_capture_count=$(rg -c -- "$host_capture_pattern" "$source") \
    || host_capture_count=0

  [[ $test_template_count -eq 2 ]] || return 1
  [[ $build_template_count -eq 1 ]] || return 1
  [[ $swiftpm_template_count -eq 3 ]] || return 1
  [[ $record_template_count -eq 3 ]] || return 1
  [[ $loop_template_count -eq 1 ]] || return 1
  [[ $(( test_template_count * 3 + build_template_count )) -eq 7 ]] || return 1
  [[ $host_capture_count -eq 0 ]] || return 1
  print -r -- 'command.static-swiftpm-resource.invocation_count=7' >> "$MANIFEST"
}

record_swiftpm_invocation_resources() {
  local label=$1 candidate found=0
  for candidate in "${AUTHORITATIVE_SWIFTPM_INVOCATIONS[@]}"; do
    if [[ "$candidate" == "$label" ]]; then
      found=1
      break
    fi
  done
  (( found == 1 )) || return 1
  for candidate in "${RECORDED_SWIFTPM_INVOCATIONS[@]}"; do
    [[ "$candidate" != "$label" ]] || return 1
  done
  RECORDED_SWIFTPM_INVOCATIONS+=("$label")
  print -r -- "command.${label}.swiftpm_scratch_path=$SWIFTPM_SCRATCH_DIR" \
    >> "$MANIFEST" || return 1
  print -r -- "command.${label}.swiftpm_cache_path=$SWIFTPM_CACHE_DIR" \
    >> "$MANIFEST" || return 1
}

assert_recorded_swiftpm_invocations() {
  [[ ${#RECORDED_SWIFTPM_INVOCATIONS[@]} -eq 7 ]] || return 1
  [[ "${(j:|:)RECORDED_SWIFTPM_INVOCATIONS}" \
      == "${(j:|:)AUTHORITATIVE_SWIFTPM_INVOCATIONS}" ]]
}

capture_token_pids() {
  local destination=$1 token=$2
  local snapshot="${destination}.ps"
  LC_ALL=C /bin/ps eww -axo pid=,command= > "$snapshot" || return 1
  /usr/bin/awk \
    -v marker="LAUNCHPAD_RELEASE_INVOCATION_TOKEN=${token}" \
    'index($0, marker) { print $1 }' "$snapshot" \
    | LC_ALL=C sort -u > "$destination" || return 1
}

process_identity_is_gone() {
  local identity=$1
  local synthetic_errno=${LAUNCHPAD_PROCESS_PROBE_SYNTHETIC_ERRNO:-}
  [[ "$identity" == <-> || "$identity" == -<-> ]] || return 64

  /usr/bin/perl -MPOSIX=:errno_h -e '
    use strict;
    use warnings;
    my ($identity, $synthetic_errno) = @ARGV;
    my $alive;
    if ($synthetic_errno eq "EPERM") {
      $alive = 0;
      $! = EPERM;
    } else {
      $alive = kill 0, $identity;
    }
    if ($alive) {
      print "alive\n";
      exit 1;
    }
    my $error = 0 + $!;
    if ($error == ESRCH) {
      print "gone\n";
      exit 0;
    }
    if ($error == EPERM) {
      print "eperm\n";
      exit 2;
    }
    print "errno=$error\n";
    exit 3;
  ' -- "$identity" "$synthetic_errno"
}

assert_invocation_gone() {
  local label=$1 token=$2 wrapper_file=$3 supervisor_file=$4 child_file=$5
  local process_group_file=$6 token_after_file=$7
  local pid_file role pid process_group child liveness_status
  local exact_pid_status=0 process_group_status=0
  local token_enumeration_status=0 token_residue_status=0

  for role in wrapper supervisor child; do
    case $role in
      wrapper) pid_file=$wrapper_file ;;
      supervisor) pid_file=$supervisor_file ;;
      child) pid_file=$child_file ;;
    esac
    if [[ ! -s "$pid_file" ]]; then
      print -r -- "command.${label}.${role}_liveness_status=missing" >> "$MANIFEST"
      exact_pid_status=1
      continue
    fi
    pid=$(<"$pid_file")
    if [[ "$pid" != <-> ]]; then
      liveness_status=64
    elif process_identity_is_gone "$pid" \
        > "$ARTIFACT_DIR/${label}.${role}.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
    fi
    print -r -- "command.${label}.${role}_liveness_status=${liveness_status}" \
      >> "$MANIFEST"
    if (( liveness_status != 0 )); then
      exact_pid_status=1
    fi
  done
  print -r -- "command.${label}.exact_pid_status=${exact_pid_status}" >> "$MANIFEST"

  liveness_status=missing
  if [[ ! -s "$process_group_file" || ! -s "$child_file" ]]; then
    process_group_status=1
  else
    process_group=$(<"$process_group_file")
    child=$(<"$child_file")
    if [[ "$process_group" != <-> || "$process_group" != "$child" ]]; then
      process_group_status=1
      liveness_status=64
    elif process_identity_is_gone "-$process_group" \
        > "$ARTIFACT_DIR/${label}.process-group.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
      process_group_status=1
    fi
  fi
  print -r -- "command.${label}.process_group_liveness_status=${liveness_status:-missing}" \
    >> "$MANIFEST"
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

  (( exact_pid_status == 0 \
      && process_group_status == 0 \
      && token_enumeration_status == 0 \
      && token_residue_status == 0 ))
}

run_watchdog() {
  local label=$1 timeout=$2
  shift 2

  local wrapper_file="$ARTIFACT_DIR/${label}.wrapper.pid"
  local supervisor_file="$ARTIFACT_DIR/${label}.supervisor.pid"
  local child_file="$ARTIFACT_DIR/${label}.child.pid"
  local process_group_file="$ARTIFACT_DIR/${label}.process-group.pid"
  local token_after_file="$ARTIFACT_DIR/${label}.token-residue.pids"
  local token="${label}-$(/usr/bin/uuidgen)"
  local command_status=0 residue_status=0

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
    "$token_after_file" || residue_status=$?
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
    capture_and_compare_end_provenance || probe_status=$?
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
  local probe_exit_code=0
  local timeout_fifo="$ARTIFACT_DIR/probe-timeout.fifo"

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

  /usr/bin/mkfifo "$timeout_fifo" || return 1
  if run_watchdog probe-token-timeout 1 /bin/cat "$timeout_fifo"; then
    probe_exit_code=0
  else
    probe_exit_code=$?
  fi
  [[ $probe_exit_code -eq 124 ]] || return 1
  rg -q '^command\.probe-token-timeout\.residue_status=0$' "$MANIFEST" \
    || return 1

  [[ $(<"$RESULT_STATUS") == failed ]] || return 1
}

capture_artifact_resource_files() {
  local destination=$1
  /usr/bin/find "$SWIFTPM_SCRATCH_DIR" "$SWIFTPM_CACHE_DIR" \
    "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" \
    -type f -print | LC_ALL=C sort > "$destination" || return 1
}

probe_resource_isolation() {
  local unrelated_root
  unrelated_root=$(mktemp -d /tmp/launchpad-resource-probe.XXXXXX) || return 1
  local short_pid=0 long_pid=0 probe_status=0
  local ready_fifo="$unrelated_root/long-ready.fifo"
  local control_fifo="$unrelated_root/long-control.fifo"
  local before="$ARTIFACT_DIR/probe-resources.before"
  local after="$ARTIFACT_DIR/probe-resources.after"

  assert_swiftpm_resource_contract || probe_status=$?
  capture_artifact_resource_files "$before" || probe_status=$?
  /usr/bin/mkfifo "$ready_fifo" "$control_fifo" || probe_status=$?

  if (( probe_status == 0 )); then
    /usr/bin/env -u LAUNCHPAD_RELEASE_INVOCATION_TOKEN \
      SWIFTPM_SCRATCH_DIR="$unrelated_root/short-scratch" \
      SWIFTPM_CACHE_DIR="$unrelated_root/short-cache" \
      CLANG_MODULE_CACHE_PATH="$unrelated_root/short-clang" \
      SWIFTPM_MODULECACHE_OVERRIDE="$unrelated_root/short-module" \
      /bin/zsh -c '
        mkdir -p "$SWIFTPM_SCRATCH_DIR" "$SWIFTPM_CACHE_DIR" \
          "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" || exit 1
        print short > "$SWIFTPM_SCRATCH_DIR/helper.marker" || exit 1
        print short > "$SWIFTPM_CACHE_DIR/helper.marker" || exit 1
        print short > "$CLANG_MODULE_CACHE_PATH/helper.marker" || exit 1
        print short > "$SWIFTPM_MODULECACHE_OVERRIDE/helper.marker" || exit 1
      ' &
    short_pid=$!
    wait "$short_pid" || probe_status=$?
  fi

  if (( probe_status == 0 )); then
    /usr/bin/env -u LAUNCHPAD_RELEASE_INVOCATION_TOKEN \
      SWIFTPM_SCRATCH_DIR="$unrelated_root/long-scratch" \
      SWIFTPM_CACHE_DIR="$unrelated_root/long-cache" \
      CLANG_MODULE_CACHE_PATH="$unrelated_root/long-clang" \
      SWIFTPM_MODULECACHE_OVERRIDE="$unrelated_root/long-module" \
      /bin/zsh -c '
        mkdir -p "$SWIFTPM_SCRATCH_DIR" "$SWIFTPM_CACHE_DIR" \
          "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" || exit 1
        print long > "$SWIFTPM_SCRATCH_DIR/helper.marker" || exit 1
        print long > "$SWIFTPM_CACHE_DIR/helper.marker" || exit 1
        print long > "$CLANG_MODULE_CACHE_PATH/helper.marker" || exit 1
        print long > "$SWIFTPM_MODULECACHE_OVERRIDE/helper.marker" || exit 1
        print ready > "$1" || exit 1
        exec /bin/cat "$2"
    ' _ "$ready_fifo" "$control_fifo" &
    long_pid=$!
    local ready
    ready=$("$WATCHDOG" 10 -- /bin/cat "$ready_fifo") || probe_status=$?
    [[ "$ready" == ready ]] || probe_status=1
  fi

  if (( probe_status == 0 )); then
    run_watchdog probe-resource-isolation 10 /usr/bin/true || probe_status=$?
  fi

  if (( long_pid > 0 )); then
    kill "$long_pid" 2>/dev/null || probe_status=$?
    wait "$long_pid" 2>/dev/null || true
  fi

  if (( probe_status == 0 )); then
    process_identity_is_gone "$short_pid" \
      > "$ARTIFACT_DIR/probe-short-helper.liveness" 2>&1 || probe_status=$?
    process_identity_is_gone "$long_pid" \
      > "$ARTIFACT_DIR/probe-long-helper.liveness" 2>&1 || probe_status=$?
    capture_artifact_resource_files "$after" || probe_status=$?
    cmp -s "$before" "$after" || probe_status=1
    [[ -f "$unrelated_root/short-scratch/helper.marker" ]] || probe_status=1
    [[ -f "$unrelated_root/long-scratch/helper.marker" ]] || probe_status=1
    [[ ! -e "$SWIFTPM_SCRATCH_DIR/helper.marker" ]] || probe_status=1
    [[ ! -e "$SWIFTPM_CACHE_DIR/helper.marker" ]] || probe_status=1
    rg -q '^command\.probe-resource-isolation\.token_residue_status=0$' \
      "$MANIFEST" || probe_status=1
    [[ $(<"$RESULT_STATUS") == failed ]] || probe_status=1
  fi

  rm -rf "$unrelated_root"
  return "$probe_status"
}

probe_process_liveness() {
  local probe_root
  probe_root=$(mktemp -d /tmp/launchpad-liveness-probe.XXXXXX) || return 1
  local ready_fifo="$probe_root/ready.fifo"
  local control_fifo="$probe_root/control.fifo"
  local helper_pid=0 probe_status=0 liveness_status=0 ready current_pgid

  /usr/bin/mkfifo "$ready_fifo" "$control_fifo" || probe_status=$?
  if (( probe_status == 0 )); then
    /bin/zsh -c '
      print ready > "$1" || exit 1
      exec /bin/cat "$2"
    ' _ "$ready_fifo" "$control_fifo" &
    helper_pid=$!
    ready=$("$WATCHDOG" 10 -- /bin/cat "$ready_fifo") || probe_status=$?
    [[ "$ready" == ready ]] || probe_status=1
    current_pgid=$(/usr/bin/perl -MPOSIX=getpgrp -e \
      'print POSIX::getpgrp(), "\n"') || probe_status=$?
    [[ "$current_pgid" == <-> ]] || probe_status=1
  fi

  if (( probe_status == 0 )); then
    if process_identity_is_gone invalid > "$ARTIFACT_DIR/probe-invalid.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
    fi
    [[ $liveness_status -eq 64 ]] || probe_status=1

    if process_identity_is_gone "$helper_pid" \
        > "$ARTIFACT_DIR/probe-pid-alive.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
    fi
    [[ $liveness_status -eq 1 ]] || probe_status=1

    if process_identity_is_gone "-$current_pgid" \
        > "$ARTIFACT_DIR/probe-pgid-alive.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
    fi
    [[ $liveness_status -eq 1 ]] || probe_status=1

    if process_identity_is_gone 1 > "$ARTIFACT_DIR/probe-pid-host.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
    fi
    [[ $liveness_status -eq 1 || $liveness_status -eq 2 ]] || probe_status=1

    if LAUNCHPAD_PROCESS_PROBE_SYNTHETIC_ERRNO=EPERM \
        process_identity_is_gone "$helper_pid" \
        > "$ARTIFACT_DIR/probe-pid-eperm.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
    fi
    [[ $liveness_status -eq 2 ]] || probe_status=1

    if LAUNCHPAD_PROCESS_PROBE_SYNTHETIC_ERRNO=EPERM \
        process_identity_is_gone "-$helper_pid" \
        > "$ARTIFACT_DIR/probe-pgid-eperm.liveness" 2>&1; then
      liveness_status=0
    else
      liveness_status=$?
    fi
    [[ $liveness_status -eq 2 ]] || probe_status=1
  fi

  if (( helper_pid > 0 )); then
    kill "$helper_pid" 2>/dev/null || probe_status=$?
    wait "$helper_pid" 2>/dev/null || true
  fi

  if (( probe_status == 0 )); then
    process_identity_is_gone "$helper_pid" \
      > "$ARTIFACT_DIR/probe-pid-gone.liveness" 2>&1 || probe_status=$?
    process_identity_is_gone "-$helper_pid" \
      > "$ARTIFACT_DIR/probe-pgid-gone.liveness" 2>&1 || probe_status=$?
    [[ $(<"$RESULT_STATUS") == failed ]] || probe_status=1
  fi

  rm -rf "$probe_root"
  return "$probe_status"
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
  --probe-resource-isolation)
    probe_resource_isolation
    exit $?
    ;;
  --probe-process-liveness)
    probe_process_liveness
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

# AUTHORITATIVE_SWIFTPM_COMMANDS_BEGIN
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

  record_swiftpm_invocation_resources "discovery-${run}"
  run_watchdog "discovery-${run}" 180 /bin/zsh -o pipefail -c \
    'swift test --scratch-path "$SWIFTPM_SCRATCH_DIR" --cache-path "$SWIFTPM_CACHE_DIR" --disable-sandbox --disable-xctest --enable-swift-testing list 2>&1 | tee "$1"' \
    _ "$raw_list"
  record_check "discovery-${run}-contract" extract_discovery "$raw_list" "$list"
  if (( run > 1 )); then
    record_check "discovery-${run}-stable" compare_artifacts \
      "$ARTIFACT_DIR/tests-1.list" "$list"
  fi
  expected_count=$(wc -l < "$list" | tr -d ' ')

  record_swiftpm_invocation_resources "tests-${run}"
  run_watchdog "tests-${run}" 900 /bin/zsh -o pipefail -c \
    'swift test --scratch-path "$SWIFTPM_SCRATCH_DIR" --cache-path "$SWIFTPM_CACHE_DIR" --disable-sandbox --disable-xctest --enable-swift-testing --no-parallel --event-stream-output-path "$2" --event-stream-version 0 2>&1 | tee "$1"' \
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
record_swiftpm_invocation_resources release-build
run_watchdog release-build 900 /bin/zsh -o pipefail -c \
  'swift build --scratch-path "$SWIFTPM_SCRATCH_DIR" --cache-path "$SWIFTPM_CACHE_DIR" -c release --product LaunchPadApp 2>&1 | tee "$1"' \
  _ "$ARTIFACT_DIR/release-build.log"
record_check swiftpm-resource-runtime assert_recorded_swiftpm_invocations
# AUTHORITATIVE_SWIFTPM_COMMANDS_END
record_check provenance-end capture_and_compare_end_provenance
print -r -- 'result=passed' >> "$MANIFEST"
print -r -- 'passed' > "$RESULT_STATUS_TEMP"
/bin/mv -f "$RESULT_STATUS_TEMP" "$RESULT_STATUS"
print "release gate: artifacts $ARTIFACT_DIR"
