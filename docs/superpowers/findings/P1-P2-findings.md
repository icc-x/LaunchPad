# P1 / P2 发现记录

> 最后更新：2026-07-24
> 来源：P0 Readiness Gate review (`docs/superpowers/plans/2026-07-21-p0-release-blockers.md`)

## 当前状态

P0 readiness gate review 产生 **4 项发现**（1 项已完成，3 项待处理），详见下表。

## 背景

- 24 个 P0 task 已全部实现并提交，1086 tests 全绿，零 XCTest 残留
- 覆盖率于 2026-07-24 重新测量
- `test-release.sh` 于 2026-07-24 执行诊断：3/4 门禁阶段通过，因 sandbox 阻断 `/bin/ps` 未完成全部

## 发现清单

| # | 发现 | 级别 | 状态 | 说明 |
|---|------|------|:--:|------|
| 1 | 覆盖率从 100% 下降 | P1 | ✅ 已完成 | 2026-07-24 重新测量：行 97.91%、区域 94.11%、函数 93.62%，42 个源文件中 23 个 100%。下降来自新增 8 个源文件 |
| 2 | `test-release.sh` 未通过 | P0 | ⏳ 待提权终端 | 2026-07-24 已执行诊断：28 项检查通过，sandbox 阻断 `/bin/ps` 导致 token 枚举失败，详见下方 |
| 3 | 代码签名 / 公证 / Developer ID | P1 | ⏳ | 正式分发前必须完成。见下方 checklist |
| 4 | CI 集成 | P2 | ⏳ | 正式分发前配置。当前无 `.github/workflows/` |

---

## 发现 #2 详细诊断：test-release.sh 执行记录

**执行：** `LAUNCHPAD_RELEASE_ARTIFACT_DIR=.workbuddy/artifacts/release-gate-2026-07-24 zsh scripts/test-release.sh`

**结果：** ❌ 未通过（`result.status = failed`）。3/4 门禁阶段通过，在自检最后一步因 sandbox 权限不足退出。

### 通过的检查（28 项）

| 阶段 | 检查项 | 结果 |
|------|--------|:--:|
| 基础设施 | watchdog 可执行 | ✅ |
| 基础设施 | zsh 语法检查 | ✅ |
| 起始证明 | Git 分支 `release-readiness`、HEAD `018a438` | ✅ |
| 静态策略 | 16 项源码扫描（XCTest 残留 / skip trait / 常量断言 / 固定等待 / 系统边界 / 用户数据库 / grid delegate/proxy/host / 性能绕过 / 第二 supervisor） | ✅ 全部 0 违规 |
| 自检 | 进程生命周期（wrapper/supervisor/child）| ✅ 全部 gone |
| 自检 | 进程组验证 | ✅ |
| 自检 | PID 精确匹配 | ✅ |

### 阻断点

```
capture_token_pids → /bin/ps eww -axo pid=,command= → exit 127 (operation not permitted)
→ token_enumeration_status=1 → assert_invocation_gone 返回 1
→ residue_status=1 → set -e 退出
```

**根因：** 脚本在自检阶段调用 `/bin/ps` 枚举所有进程，验证 watchdog 调用后无残留进程（token residue check）。WorkBuddy sandbox 在 macOS 内核级（seatbelt）禁止 `ps` 执行，`dangerouslyDisableSandbox` 也无法绕过。

**已完成：** 基础设施 ✅ + 静态策略 ✅ + 进程生命周期 ✅（3/4 阶段）
**未执行：** 测试发现 + 三轮全量测试 + release build（第 4 阶段）

**下一步：** 在无 sandbox 的真实 macOS 终端中执行完整门禁，保留 artifact 证据。

---

## 发现 #3 详细 checklist：代码签名与公证

**前置条件：** Apple Developer Program 账号（$99/年）。

**步骤：**

1. 创建 Developer ID Application 证书（Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority → developer.apple.com 签发）
2. 补齐 `LaunchPad.entitlements`（当前仅含 `com.apple.security.automation.apple-events`）：
   ```xml
   <key>com.apple.security.cs.allow-unsigned-executable-memory</key><false/>
   <key>com.apple.security.cs.disable-library-validation</key><false/>
   <key>com.apple.security.cs.allow-dyld-environment-variables</key><false/>
   <key>com.apple.security.cs.debugger</key><false/>
   ```
3. Release build + 签名：
   ```bash
   swift build -c release --product LaunchPadApp
   codesign --deep --force --verify --verbose \
     --sign "Developer ID Application: <Team Name> (<Team ID>)" \
     --options runtime \
     .build/release/LaunchPadApp
   ```
4. 打包 `.app`、zip：
   ```bash
   ditto -c -k --keepParent .build/release/LaunchPadApp LaunchPad.zip
   ```
5. 公证：
   ```bash
   xcrun notarytool submit LaunchPad.zip \
     --apple-id "<Apple ID>" --team-id "<Team ID>" \
     --password "<app-specific-password>" --wait
   ```
6. Stapling：
   ```bash
   xcrun stapler staple .build/release/LaunchPad.app
   ```
7. 验证：
   ```bash
   spctl --assess --verbose=4 .build/release/LaunchPad.app
   codesign --verify --deep --strict --verbose=4 .build/release/LaunchPad.app
   ```

---

## 约定

如果后续 review 产生新的 P1/P2 发现，请在此文件中新增条目，保持此节"当前状态"更新。
