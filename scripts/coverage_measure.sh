#!/bin/bash
# LaunchPad 覆盖率测量 v2 — 构建一次 + 逐套件跑（不重建）+ 重命名收集 profraw
set +e

PROJECT_DIR="/Users/icc/Documents/LaunchPad/LaunchPad"
CODECOV_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/debug/codecov"
COLLECT_DIR="$PROJECT_DIR/.build/profraw_collection"
LLVM_PROFDATA="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-profdata"
LLVM_COV="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-cov"
BIN="$PROJECT_DIR/.build/arm64-apple-macosx/debug/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests"
PROF_MERGED="$PROJECT_DIR/.build/coverage_merged.profdata"

cd "$PROJECT_DIR"

# Step 1: 一次性构建（带覆盖率）
echo ">>> Step 1: 一次性构建（带代码覆盖率）..."
rm -rf "$COLLECT_DIR"
find "$CODECOV_DIR" -name "*.profraw" -delete 2>/dev/null
rm -f "$PROF_MERGED"
swift test --disable-sandbox --enable-code-coverage --filter "WindowLifecycleTests" 2>/dev/null
echo "构建完成"

# Step 2: 获取套件列表
echo ""
echo ">>> Step 2: 获取测试套件列表..."
SUITES=$(swift test list --disable-sandbox 2>/dev/null \
    | grep 'LaunchPadTests\.' \
    | sed 's/LaunchPadTests\.\([^/]*\).*/\1/' \
    | sort -u)
TOTAL=$(echo "$SUITES" | wc -l | tr -d ' ')
echo "找到 $TOTAL 个测试套件"

# Step 3: 创建收集目录并标记基准时间
mkdir -p "$COLLECT_DIR"

# Step 4: 逐套件运行（跳过构建）+ 每次运行完收集 profraw
echo ""
echo ">>> Step 3: 逐套件运行（--skip-build）+ 收集 profraw..."
PASS=0
FAIL=0
i=0

while IFS= read -r suite; do
    [ -z "$suite" ] && continue
    i=$((i + 1))
    
    printf "[%3d/%3d] %-55s ... " "$i" "$TOTAL" "$suite"
    
    # 先记录已存在的 profraw 文件名
    BEFORE=$(find "$CODECOV_DIR" -name "*.profraw" -maxdepth 1 2>/dev/null | sort)
    
    if swift test --filter "$suite" --disable-sandbox --enable-code-coverage --skip-build \
       > /tmp/coverage_${suite}.log 2>&1; then
        echo -n "PASS"
        PASS=$((PASS + 1))
    else
        echo -n "FAIL"
        FAIL=$((FAIL + 1))
    fi
    
    # 找出新出现的 profraw 文件并重命名移动到收集目录
    AFTER=$(find "$CODECOV_DIR" -name "*.profraw" -maxdepth 1 2>/dev/null | sort)
    NEW_FILES=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") 2>/dev/null)
    COUNT=0
    for nf in $NEW_FILES; do
        [ -f "$nf" ] || continue
        BASENAME=$(basename "$nf")
        mv "$nf" "$COLLECT_DIR/${suite}_${BASENAME}" 2>/dev/null
        COUNT=$((COUNT + 1))
    done
    
    # 如果上面的方式没找到新文件，尝试另一种方式：复制然后清空 codecov
    # （因为 swift test 可能覆盖而非新建 profraw）
    if [ "$COUNT" -eq 0 ]; then
        for pf in "$CODECOV_DIR"/*.profraw; do
            [ -f "$pf" ] || continue
            BASENAME=$(basename "$pf")
            cp "$pf" "$COLLECT_DIR/${suite}_${BASENAME}" 2>/dev/null
            COUNT=$((COUNT + 1))
        done
    fi
    
    echo " (+${COUNT} profraw)"
done <<< "$SUITES"

COLLECTED=$(find "$COLLECT_DIR" -name "*.profraw" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "========================================"
echo "  测试: PASS=$PASS FAIL=$FAIL / $TOTAL"
echo "  profraw 收集: $COLLECTED 个"
echo "========================================"

if [ "$COLLECTED" -gt 0 ]; then
    echo ""
    echo ">>> 合并 profraw..."
    find "$COLLECT_DIR" -name "*.profraw" -print0 | xargs -0 "$LLVM_PROFDATA" merge -sparse -o "$PROF_MERGED" 2>&1
    
    echo ""
    echo "========================================"
    echo "  覆盖率报告（来源: $COLLECTED 个 profraw）"
    echo "========================================"
    "$LLVM_COV" report "$BIN" -instr-profile="$PROF_MERGED" \
        -ignore-filename-regex="Tests/|DerivedSources|runner.swift" 2>/dev/null | tail -n +3
    
    echo ""
    echo ">>> 逐文件零计数行检查..."
    find Sources -name "*.swift" -type f | sort | while IFS= read -r f; do
        ZEROS=$("$LLVM_COV" show -use-color=false "$BIN" \
            -instr-profile="$PROF_MERGED" "$f" 2>/dev/null \
            | grep -c '|      0|' || true)
        ZEROS=$(echo "$ZEROS" | tr -d ' \t')
        [ -z "$ZEROS" ] && ZEROS=0
        FNAME=$(echo "$f" | sed 's|Sources/||')
        if [ "$ZEROS" -eq 0 ]; then
            printf "  [0]  %-60s ✓\n" "$FNAME"
        else
            printf "  [%3d] %-60s ⚠️\n" "$ZEROS" "$FNAME"
        fi
    done
fi
