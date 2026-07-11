#!/usr/bin/env python3
"""
LaunchPad 覆盖率测量 — Python 脚本版
直接运行 xctest 二进制，用 LLVM_PROFILE_FILE 控制 profraw 输出路径。
绕过 swift test 的沙箱和 profraw 复用问题。
"""
import subprocess
import os
import glob
import sys
from pathlib import Path

PROJECT_DIR = "/Users/icc/Documents/LaunchPad/LaunchPad"
BUILD_DIR = f"{PROJECT_DIR}/.build/arm64-apple-macosx/debug"
TEST_BIN = f"{BUILD_DIR}/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests"
PROFRAW_DIR = f"{BUILD_DIR}/profraws"
PROF_MERGED = f"{BUILD_DIR}/coverage_merged.profdata"
LLVM_PROFDATA = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-profdata"
LLVM_COV = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-cov"

os.chdir(PROJECT_DIR)

# Step 1: Build
print(">>> Step 1: 构建测试（带覆盖率插桩）...")
result = subprocess.run(
    ["swift", "test", "--disable-sandbox", "--enable-code-coverage", "--filter", "AppInfoTests"],
    capture_output=True, text=True, cwd=PROJECT_DIR, timeout=120
)
#if result.returncode != 0:
#    print(f"构建失败: {result.stderr[-500:]}")
#    sys.exit(1)
print("构建完成")

# Step 2: Get test list
print("\n>>> Step 2: 获取测试列表...")
result = subprocess.run(
    ["swift", "test", "list", "--disable-sandbox"],
    capture_output=True, text=True, cwd=PROJECT_DIR, timeout=60
)
# Get suite names
suites = set()
for line in result.stdout.split("\n"):
    if "LaunchPadTests." in line:
        # Extract suite name: LaunchPadTests.SuiteName/testName
        parts = line.strip().split("/")[0].replace("LaunchPadTests.", "")
        suites.add(parts)

suites = sorted(suites)
print(f"找到 {len(suites)} 个测试套件")

# Step 3: Run each suite and collect profraw
print(f"\n>>> Step 3: 逐套件运行并收集 profraw...")
os.makedirs(PROFRAW_DIR, exist_ok=True)

# Clean old profraws
for f in glob.glob(f"{PROFRAW_DIR}/*.profraw"):
    os.remove(f)

total = len(suites)
passed = 0
failed = 0

for i, suite in enumerate(suites):
    profraw_path = f"{PROFRAW_DIR}/{suite}_%p.profraw"
    
    print(f"[{i+1:3d}/{total:3d}] {suite:55s} ... ", end="", flush=True)
    
    env = os.environ.copy()
    env["LLVM_PROFILE_FILE"] = profraw_path
    
    try:
        result = subprocess.run(
            [TEST_BIN, "--testing-library", "swift-testing", "--filter", f"LaunchPadTests.{suite}"],
            capture_output=True, text=True, cwd=PROJECT_DIR, env=env, timeout=30
        )
        if result.returncode == 0:
            print("PASS")
            passed += 1
        else:
            print("FAIL")
            failed += 1
    except subprocess.TimeoutExpired:
        print("TIMEOUT")
        failed += 1

profraw_count = len(glob.glob(f"{PROFRAW_DIR}/*.profraw"))
print(f"\n{'='*60}")
print(f"  PASS={passed} FAIL={failed} / {total}")
print(f"  profraw: {profraw_count} 个")
print(f"{'='*60}")

if profraw_count == 0:
    print("\n⚠️ 未收集到 profraw 文件")
    sys.exit(1)

# Step 4: Merge profraw
print("\n>>> Step 4: 合并 profraw...")
profraw_files = sorted(glob.glob(f"{PROFRAW_DIR}/*.profraw"))
result = subprocess.run(
    [LLVM_PROFDATA, "merge", "-sparse", "-o", PROF_MERGED] + profraw_files,
    capture_output=True, text=True, timeout=30
)
if result.returncode != 0:
    print(f"合并失败: {result.stderr}")
    sys.exit(1)
print("合并完成")

# Step 5: Coverage report
print(f"\n>>> Step 5: 覆盖率报告...")
result = subprocess.run(
    [LLVM_COV, "report", TEST_BIN, "-instr-profile", PROF_MERGED,
     "-ignore-filename-regex", "Tests/|DerivedSources|runner.swift"],
    capture_output=True, text=True, timeout=30
)
print(result.stdout)

# Step 6: Zero-count check
print(">>> Step 6: 零计数行检查...")
source_files = sorted(glob.glob(f"{PROJECT_DIR}/Sources/**/*.swift", recursive=True))
zero_total = 0
zero_files = []

for sf in source_files:
    rel = os.path.relpath(sf, PROJECT_DIR)
    result = subprocess.run(
        [LLVM_COV, "show", "-use-color=false", TEST_BIN, "-instr-profile", PROF_MERGED, sf],
        capture_output=True, text=True, timeout=10
    )
    zeros = result.stdout.count("|      0|")
    if zeros > 0:
        zero_total += zeros
        short = rel.replace("Sources/", "")
        zero_files.append((short, zeros))

if zero_total == 0:
    print("\n✅ 全部源文件 0 个零计数行 → 100% 真实覆盖率！")
else:
    print(f"\n⚠️ 零计数行总数: {zero_total}")
    print("含零计数行的文件:")
    for fname, count in zero_files:
        print(f"  [{count:3d}] {fname}")

print(f"\n合并 profdata: {PROF_MERGED}")
