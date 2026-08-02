#!/bin/bash
# LaunchPad 测试质量静态审计
# 拒绝弱断言与固定等待，确保测试具备行为断言且不依赖机器负载时序。
# 用法: ./scripts/check-test-quality.sh [scan-root]
# 默认扫描 Tests/；退出 0 表示干净，非零表示发现违规。
set -uo pipefail

SCAN_ROOT="${1:-Tests}"

status=0

check_pattern() {
  local label=$1 pattern=$2
  local matches
  if matches=$(rg -n --glob '*.swift' "$pattern" "$SCAN_ROOT" 2>/dev/null); then
    echo "check-test-quality: $label detected:" >&2
    echo "$matches" >&2
    status=1
  fi
}

# 字面常量断言：`#expect(true)` 不验证任何行为
check_pattern 'constant-expect' '#expect[[:space:]]*\([[:space:]]*true[[:space:]]*\)'

# 固定等待：真实 sleep 与 RunLoop 轮询使测试对机器负载敏感
check_pattern 'fixed-wait' 'Thread\.sleep|RunLoop\.(main|current)\.run'

if [[ $status -eq 0 ]]; then
  echo "check-test-quality: clean ($SCAN_ROOT)"
fi
exit "$status"
