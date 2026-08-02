#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h}
TMP=$(mktemp -d /tmp/launchpad-test-quality.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bad" "$TMP/good"

# 坏 fixture：字面常量断言（弱断言）
cat > "$TMP/bad/ConstantExpect.swift" <<'EOF'
@Test func test() {
    #expect(true)
}
EOF

# 坏 fixture：固定等待（机器负载敏感）
cat > "$TMP/bad/FixedWait.swift" <<'EOF'
@Test func test() {
    Thread.sleep(forTimeInterval: 1)
    RunLoop.current.run(until: Date())
}
EOF

# 好 fixture：真实行为断言
cat > "$TMP/good/Behavior.swift" <<'EOF'
@Test func test() {
    let value = compute()
    #expect(value == 42)
}
EOF

# 1. 坏 fixture 必须被拒绝
if "$ROOT/scripts/check-test-quality.sh" "$TMP/bad" > /dev/null 2>&1; then
  print -u2 -- 'bad fixture unexpectedly passed'
  exit 1
fi

# 2. 好 fixture 必须通过
"$ROOT/scripts/check-test-quality.sh" "$TMP/good" > /dev/null 2>&1

print 'test-test-quality: OK'
