#!/bin/bash
# LaunchPad 覆盖率测量 v3 — 逐套件跑 + 跑后立即 mv profraw（防止覆盖）
set +e

PROJECT_DIR="/Users/icc/Documents/LaunchPad/LaunchPad"
cd "$PROJECT_DIR"

CODECOV=".build/arm64-apple-macosx/debug/codecov"
COLLECT_DIR=".build/profraw_all"
LLVM_PROFDATA="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-profdata"
LLVM_COV="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-cov"
BIN=".build/arm64-apple-macosx/debug/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests"
PROF_MERGED=".build/coverage_final.profdata"

# 清理
rm -rf "$COLLECT_DIR"
mkdir -p "$COLLECT_DIR"
find "$CODECOV" -name "*.profraw" -delete 2>/dev/null

# 构建（用第一个套件触发构建 + 覆盖率插桩）
echo ">>> 构建（带覆盖率插桩）..."
swift test --filter "AppInfoTests" --disable-sandbox --enable-code-coverage > /dev/null 2>&1

# 收集第一个套件的 profraw
COUNT=0
for f in "$CODECOV"/*.profraw; do
    [ -f "$f" ] || continue
    mv "$f" "$COLLECT_DIR/AppInfoTests_$(basename "$f")"
    COUNT=$((COUNT + 1))
done
echo "构建完成，收集 $COUNT 个 profraw"

# 获取所有套件名
echo ">>> 获取测试套件..."
SUITES=$(swift test list --disable-sandbox 2>/dev/null \
    | grep 'LaunchPadTests\.' \
    | sed 's/LaunchPadTests\.\([^/]*\).*/\1/' \
    | sort -u | grep -v 'AppInfoTests')
TOTAL=$(echo "$SUITES" | wc -l | tr -d ' ')

# 逐套件运行 + 立即收集
echo ">>> 逐套件运行（共 $TOTAL 个）..."
PASS=0
FAIL=0
i=0
START=$(date +%s)

while IFS= read -r suite; do
    [ -z "$suite" ] && continue
    i=$((i + 1))
    
    printf "[%3d/%3d] %-55s ... " "$i" "$TOTAL" "$suite"
    
    if swift test --filter "$suite" --disable-sandbox --enable-code-coverage > /tmp/ctest_${suite}.log 2>&1; then
        echo -n "PASS"
        PASS=$((PASS + 1))
    else
        echo -n "FAIL"
        FAIL=$((FAIL + 1))
    fi
    
    # 立即收集 profraw（mv 走以免下一个套件覆盖）
    NEW=0
    for f in "$CODECOV"/*.profraw; do
        [ -f "$f" ] || continue
        BASENAME=$(basename "$f")
        # 重命名避免冲突
        mv "$f" "$COLLECT_DIR/${suite}__$(echo $BASENAME | sed 's/8674699558523996800/SEQ/')" 2>/dev/null
        NEW=$((NEW + 1))
    done
    echo " (+${NEW} profraw)"
done <<< "$SUITES"

ELAPSED=$(($(date +%s) - START))
COLLECTED=$(find "$COLLECT_DIR" -name "*.profraw" | wc -l | tr -d ' ')

echo ""
echo "========================================"
echo "  PASS=$PASS FAIL=$FAIL / $((TOTAL + 1)) 套件 ($ELAPSED s)"
echo "  profraw: $COLLECTED 个"
echo "========================================"

[ "$COLLECTED" -eq 0 ] && { echo "❌ 无 profraw！"; exit 1; }

# 合并
echo ""
echo ">>> 合并 $COLLECTED 个 profraw..."
find "$COLLECT_DIR" -name "*.profraw" -print0 | xargs -0 "$LLVM_PROFDATA" merge -sparse -o "$PROF_MERGED" 2>&1

# 报告
echo ""
echo "========================================"
echo "  覆盖率报告"
echo "========================================"
"$LLVM_COV" report "$BIN" -instr-profile="$PROF_MERGED" \
    -ignore-filename-regex="Tests/|DerivedSources|runner.swift" 2>/dev/null | tail -n +3

# 零计数行检查
echo ""
echo "========================================"
echo "  逐文件零计数行检查"
echo "========================================"
ZERO_TOTAL=0
find Sources -name "*.swift" -type f | sort | while IFS= read -r f; do
    ZEROS=$("$LLVM_COV" show -use-color=false "$BIN" \
        -instr-profile="$PROF_MERGED" "$f" 2>/dev/null | grep -c '|      0|' || true)
    ZEROS=$(echo "$ZEROS" | tr -d ' \t')
    [ -z "$ZEROS" ] && ZEROS=0
    FNAME=$(echo "$f" | sed 's|Sources/||')
    if [ "$ZEROS" -eq 0 ]; then
        printf "  ✓ %-60s [0]\n" "$FNAME"
    else
        printf "  ⚠ %-60s [%d]\n" "$FNAME" "$ZEROS"
    fi
done

echo ""
# 最终判定
TOTAL_ZEROS=$(find Sources -name "*.swift" -type f -exec "$LLVM_COV" show -use-color=false "$BIN" -instr-profile="$PROF_MERGED" {} 2>/dev/null \; | grep -c '|      0|' || true)
if [ "$TOTAL_ZEROS" -eq 0 ]; then
    echo "✅ 全部源文件 0 个零计数行 → 100% 真实覆盖率！"
else
    echo "⚠️ 零计数行总数: $TOTAL_ZEROS"
fi

echo ""
echo "合并 profdata: $PROJECT_DIR/$PROF_MERGED"
echo "原始 profraw: $PROJECT_DIR/$COLLECT_DIR"
