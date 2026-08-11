#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h}
TMP=$(mktemp -d /tmp/launchpad-test-quality.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

fail() {
  print -u2 -- "test-test-quality: $1"
  exit 1
}

cat > "$TMP/bad.swift" <<'EOF'
import Testing
@Test func weakAssertion() {
    #expect(true)
    Thread.sleep(forTimeInterval: 0.1)
    RunLoop.current.run(until: Date())
}
EOF

cat > "$TMP/good.swift" <<'EOF'
import Testing
@Test func behaviorAssertion() {
    let value = 1 + 1
    #expect(value == 2)
}
EOF

if "$ROOT/scripts/check-test-quality.sh" "$TMP/bad.swift" > /dev/null 2>&1; then
  fail 'bad fixture unexpectedly passed'
fi

if ! "$ROOT/scripts/check-test-quality.sh" "$TMP/good.swift" > /dev/null 2>&1; then
  fail 'good fixture unexpectedly failed'
fi

print -- 'test-test-quality: passed'
