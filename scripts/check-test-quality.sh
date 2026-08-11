#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
SCAN_ROOT=${1:-$ROOT/Tests}

# 静态测试质量审计：拒绝弱断言与真实 sleep，输出 filename:line。
# 默认扫描 Tests；传入单文件或目录可缩小范围。
FAILED=0
for pattern in '#expect\(true\)' 'Thread\.sleep' 'RunLoop\.current\.run'; do
  if rg -n "$pattern" "$SCAN_ROOT" --glob '*.swift'; then
    FAILED=1
  fi
done
exit $FAILED
