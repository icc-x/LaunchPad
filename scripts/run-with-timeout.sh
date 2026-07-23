#!/bin/zsh
set -u
unsetopt BG_NICE

SELF=${0:A}

pid_is_gone() {
  local pid=$1
  ! kill -0 "$pid" 2>/dev/null
}

wait_for_pidfiles() {
  local attempt pidfile ready
  for attempt in {1..500}; do
    ready=1
    for pidfile in "$@"; do
      if [[ ! -s $pidfile ]]; then
        ready=0
        break
      fi
    done
    (( ready == 1 )) && return 0
    /bin/sleep 0.01
  done
  return 1
}

stop_wrapper() {
  local wrapper=$1
  kill -TERM "$wrapper" 2>/dev/null || true
  wait "$wrapper" 2>/dev/null || true
}

run_command() {
  local seconds=$1
  shift
  local supervisor_pid=0 supervisor_ready=0 forwarded_status=0 wait_status=0
  local ready_file=$(mktemp /tmp/launchpad-supervisor-ready.XXXXXX)
  if [[ -n ${RUN_TIMEOUT_WRAPPER_PIDFILE:-} ]]; then
    print -r -- $$ > "$RUN_TIMEOUT_WRAPPER_PIDFILE" || return 125
  fi
  trap 'forwarded_status=129; (( supervisor_ready == 1 )) && kill -HUP "$supervisor_pid" 2>/dev/null || true' HUP
  trap 'forwarded_status=130; (( supervisor_ready == 1 )) && kill -INT "$supervisor_pid" 2>/dev/null || true' INT
  trap 'forwarded_status=143; (( supervisor_ready == 1 )) && kill -TERM "$supervisor_pid" 2>/dev/null || true' TERM
  /usr/bin/perl -e '
    use Errno qw(EINTR);
    use POSIX qw(SIGHUP SIGINT SIGTERM setpgid);
    my $seconds = shift @ARGV;
    my $ready_file = shift @ARGV;
    pipe(my $group_ready_reader, my $group_ready_writer)
      or die "pipe failed: $!";
    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ($pid == 0) {
      close $group_ready_reader;
      setpgid(0, 0) or die "setpgid failed: $!";
      my $written = syswrite($group_ready_writer, "1");
      die "group ready write failed: $!"
        unless defined($written) && $written == 1;
      close $group_ready_writer or die "group ready close failed: $!";
      exec { $ARGV[0] } @ARGV or exit 127;
    }
    close $group_ready_writer;
    my ($group_ready_byte, $read_count);
    do {
      $read_count = sysread($group_ready_reader, $group_ready_byte, 1);
    } while (!defined($read_count) && $! == EINTR);
    close $group_ready_reader;
    unless (defined($read_count) && $read_count == 1
        && $group_ready_byte eq "1") {
      waitpid($pid, 0);
      die "child process group setup failed";
    }
    if (my $pidfile = $ENV{RUN_TIMEOUT_SUPERVISOR_PIDFILE}) {
      open my $handle, ">", $pidfile or die "open pidfile failed: $!";
      print {$handle} $$;
      close $handle or die "close pidfile failed: $!";
    }
    if (my $pidfile = $ENV{RUN_TIMEOUT_CHILD_PIDFILE}) {
      open my $handle, ">", $pidfile or die "open pidfile failed: $!";
      print {$handle} $pid;
      close $handle or die "close pidfile failed: $!";
    }
    if (my $pidfile = $ENV{RUN_TIMEOUT_PROCESS_GROUP_PIDFILE}) {
      open my $handle, ">", $pidfile or die "open pidfile failed: $!";
      print {$handle} $pid;
      close $handle or die "close pidfile failed: $!";
    }
    my ($timed_out, $forwarded, $terminating) = (0, 0, 0);
    my $terminate_group = sub {
      my ($number, $name) = @_;
      return if $terminating;
      $terminating = 1;
      $forwarded = $number if $number;
      kill $name, -$pid;
      select undef, undef, undef, 2.0;
      kill "KILL", -$pid;
    };
    local $SIG{ALRM} = sub {
      $timed_out = 1;
      $terminate_group->(0, "TERM");
    };
    local $SIG{HUP} = sub {
      alarm 0;
      $terminate_group->(SIGHUP, "HUP");
    };
    local $SIG{INT} = sub {
      alarm 0;
      $terminate_group->(SIGINT, "INT");
    };
    local $SIG{TERM} = sub {
      alarm 0;
      $terminate_group->(SIGTERM, "TERM");
    };
    open my $ready, ">", $ready_file or die "open ready file failed: $!";
    print {$ready} $$;
    close $ready or die "close ready file failed: $!";
    alarm $seconds;
    my $waited;
    do { $waited = waitpid($pid, 0) }
      while $waited == -1 && $! == EINTR;
    my $status = $?;
    alarm 0;
    $terminate_group->(0, "TERM")
      if !$timed_out && !$forwarded && kill(0, -$pid);
    exit 124 if $timed_out;
    exit 128 + $forwarded if $forwarded;
    exit 128 + ($status & 127) if $status & 127;
    exit($status >> 8);
  ' "$seconds" "$ready_file" "$@" &
  supervisor_pid=$!
  local attempt
  for attempt in {1..500}; do
    [[ -s $ready_file ]] && break
    if ! kill -0 "$supervisor_pid" 2>/dev/null; then
      wait "$supervisor_pid" || wait_status=$?
      rm -f "$ready_file"
      trap - HUP INT TERM
      return "$wait_status"
    fi
    /bin/sleep 0.01
  done
  if [[ ! -s $ready_file ]]; then
    kill -TERM "$supervisor_pid" 2>/dev/null || true
    wait "$supervisor_pid" 2>/dev/null || true
    rm -f "$ready_file"
    trap - HUP INT TERM
    return 125
  fi
  supervisor_ready=1
  case $forwarded_status in
    129) kill -HUP "$supervisor_pid" 2>/dev/null || true ;;
    130) kill -INT "$supervisor_pid" 2>/dev/null || true ;;
    143) kill -TERM "$supervisor_pid" 2>/dev/null || true ;;
  esac
  wait "$supervisor_pid" || wait_status=$?
  if (( forwarded_status != 0 )) \
      && kill -0 "$supervisor_pid" 2>/dev/null; then
    wait "$supervisor_pid" || wait_status=$?
  fi
  rm -f "$ready_file"
  trap - HUP INT TERM
  (( forwarded_status != 0 )) && return "$forwarded_status"
  return "$wait_status"
}

process_group_is_gone() {
  local process_group=$1
  ! kill -0 -- "-$process_group" 2>/dev/null
}

assert_tree_gone() {
  local wrapper=$1 wrapper_file=$2 supervisor_file=$3 child_file=$4
  local process_group_file=$5 descendant_file=${6:-}
  local recorded_wrapper=$(<"$wrapper_file")
  local supervisor=$(<"$supervisor_file")
  local child=$(<"$child_file")
  local process_group=$(<"$process_group_file")
  [[ $recorded_wrapper == $wrapper ]] \
    && pid_is_gone "$wrapper" \
    && pid_is_gone "$supervisor" \
    && pid_is_gone "$child" \
    && process_group_is_gone "$process_group" \
    && { [[ -z $descendant_file ]] || pid_is_gone "$(<"$descendant_file")"; }
}

start_tree() {
  local seconds=$1 wrapper_file=$2 supervisor_file=$3 child_file=$4
  local process_group_file=$5 descendant_file=$6
  RUN_TIMEOUT_WRAPPER_PIDFILE=$wrapper_file \
  RUN_TIMEOUT_SUPERVISOR_PIDFILE=$supervisor_file \
    RUN_TIMEOUT_CHILD_PIDFILE=$child_file \
    RUN_TIMEOUT_PROCESS_GROUP_PIDFILE=$process_group_file \
    "$SELF" "$seconds" -- /bin/zsh -c '
      /bin/sleep 30 &
      print -r -- $! > "$1"
      wait
    ' _ "$descendant_file" &
  REPLY=$!
}

self_test_normal() {
  local directory=$(mktemp -d /tmp/launchpad-normal.XXXXXX)
  trap "rm -rf ${(q)directory}" EXIT
  RUN_TIMEOUT_WRAPPER_PIDFILE="$directory/wrapper" \
    RUN_TIMEOUT_SUPERVISOR_PIDFILE="$directory/supervisor" \
    RUN_TIMEOUT_CHILD_PIDFILE="$directory/child" \
    RUN_TIMEOUT_PROCESS_GROUP_PIDFILE="$directory/process-group" \
    "$SELF" 5 -- /usr/bin/true &
  local wrapper=$! exit_code=0
  wait "$wrapper" || exit_code=$?
  [[ $exit_code -eq 0 ]] || return 1
  wait_for_pidfiles "$directory/wrapper" "$directory/supervisor" \
    "$directory/child" "$directory/process-group" || return 1
  assert_tree_gone "$wrapper" "$directory/wrapper" \
    "$directory/supervisor" "$directory/child" \
    "$directory/process-group"
}

self_test_timeout() {
  local directory=$(mktemp -d /tmp/launchpad-timeout.XXXXXX)
  trap "rm -rf ${(q)directory}" EXIT
  start_tree 1 "$directory/wrapper" "$directory/supervisor" \
    "$directory/child" "$directory/process-group" "$directory/descendant"
  local wrapper=$REPLY exit_code=0
  if ! wait_for_pidfiles "$directory/wrapper" "$directory/supervisor" \
      "$directory/child" "$directory/process-group" "$directory/descendant"; then
    stop_wrapper "$wrapper"
    return 1
  fi
  wait "$wrapper" || exit_code=$?
  [[ $exit_code -eq 124 ]] || return 1
  assert_tree_gone "$wrapper" "$directory/wrapper" \
    "$directory/supervisor" "$directory/child" \
    "$directory/process-group" "$directory/descendant"
}

self_test_signal() {
  local pair signal expected race_directory race_wrapper directory wrapper exit_code
  for pair in HUP:129 INT:130 TERM:143; do
    signal=${pair%%:*}
    expected=${pair##*:}
    race_directory=$(mktemp -d /tmp/launchpad-signal-ready.XXXXXX)
    trap "rm -rf ${(q)race_directory}" EXIT
    RUN_TIMEOUT_WRAPPER_PIDFILE="$race_directory/wrapper" \
      RUN_TIMEOUT_SUPERVISOR_PIDFILE="$race_directory/supervisor" \
      RUN_TIMEOUT_CHILD_PIDFILE="$race_directory/child" \
      RUN_TIMEOUT_PROCESS_GROUP_PIDFILE="$race_directory/process-group" \
      "$SELF" 30 -- /bin/sleep 30 &
    race_wrapper=$!
    if ! wait_for_pidfiles "$race_directory/wrapper" \
        "$race_directory/supervisor" "$race_directory/child" \
        "$race_directory/process-group"; then
      stop_wrapper "$race_wrapper"
      return 1
    fi
    kill -"$signal" "$race_wrapper" || return 1
    exit_code=0
    wait "$race_wrapper" || exit_code=$?
    [[ $exit_code -eq $expected ]] || return 1
    assert_tree_gone "$race_wrapper" "$race_directory/wrapper" \
      "$race_directory/supervisor" "$race_directory/child" \
      "$race_directory/process-group" || return 1
    rm -rf "$race_directory"

    directory=$(mktemp -d /tmp/launchpad-signal.XXXXXX)
    trap "rm -rf ${(q)directory}" EXIT
    start_tree 30 "$directory/wrapper" "$directory/supervisor" \
      "$directory/child" "$directory/process-group" "$directory/descendant"
    wrapper=$REPLY
    if ! wait_for_pidfiles "$directory/wrapper" "$directory/supervisor" \
        "$directory/child" "$directory/process-group" "$directory/descendant"; then
      stop_wrapper "$wrapper"
      return 1
    fi
    kill -"$signal" "$wrapper" || return 1
    exit_code=0
    wait "$wrapper" || exit_code=$?
    [[ $exit_code -eq $expected ]] || return 1
    assert_tree_gone "$wrapper" "$directory/wrapper" \
      "$directory/supervisor" "$directory/child" \
      "$directory/process-group" "$directory/descendant" || return 1
    rm -rf "$directory"
  done
}

self_test_nonzero() {
  local directory=$(mktemp -d /tmp/launchpad-nonzero.XXXXXX)
  trap "rm -rf ${(q)directory}" EXIT
  local supervisor_file="$directory/supervisor"
  local child_file="$directory/child"
  local wrapper_file="$directory/wrapper"
  local process_group_file="$directory/process-group"
  local descendant_file="$directory/descendant"
  RUN_TIMEOUT_WRAPPER_PIDFILE=$wrapper_file \
    RUN_TIMEOUT_SUPERVISOR_PIDFILE=$supervisor_file \
    RUN_TIMEOUT_CHILD_PIDFILE=$child_file \
    RUN_TIMEOUT_PROCESS_GROUP_PIDFILE=$process_group_file \
    "$SELF" 30 -- /bin/zsh -c '
      /bin/sleep 30 &
      print -r -- $! > "$1"
      exit 17
    ' _ "$descendant_file" &
  local wrapper=$! exit_code=0
  wait "$wrapper" || exit_code=$?
  [[ $exit_code -eq 17 ]] || return 1
  assert_tree_gone "$wrapper" "$wrapper_file" "$supervisor_file" \
    "$child_file" "$process_group_file" "$descendant_file" || return 1
  exit_code=0
  "$SELF" 5 -- /definitely/missing/launchpad-command || exit_code=$?
  [[ $exit_code -eq 127 ]] || return 1
}

case ${1:-} in
  --self-test-normal) self_test_normal; exit $? ;;
  --self-test-timeout) self_test_timeout; exit $? ;;
  --self-test-signal) self_test_signal; exit $? ;;
  --self-test-nonzero) self_test_nonzero; exit $? ;;
esac

if (( $# < 3 )) || [[ $1 != <-> ]] || (( $1 <= 0 )) || [[ $2 != -- ]]; then
  print -u2 'usage: run-with-timeout.sh SECONDS -- COMMAND [ARG...]'
  exit 2
fi
seconds=$1
shift 2
run_command "$seconds" "$@"
exit $?
