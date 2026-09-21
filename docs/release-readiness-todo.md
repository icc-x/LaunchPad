# 发布就绪待处理事项

> 核查日期：2026-07-29
> 范围：对 2026-07-15 发布就绪评审中的 41 项问题逐项复核当前代码、脚本与测试状态。
> 最近更新：2026-09-21（发布门禁连续两次通过、CI 迁移 macOS 26 后回写）

## 当前结论

- 已修复：40 项（含 2026-08-11 完成的 13 项本地整改）
- 部分修复：2 项（P2-12、P2-15）
- 未修复：1 项（P1-11）
- 外部验收进展（2026-09-21）：发布门禁连续两次运行已通过；quality 工作流 `macos-26` job 全绿（1173 tests / 65 suites，与本地一致），`macos-26-xlarge` job 与 performance 工作流被 GitHub 账户计费问题阻塞
- 发布结论：**本地可执行门禁全部通过且已连续两次验证**。剩余阻断：真实 Apple 签名/公证/stapling（待凭据环境）、干净 macOS Gatekeeper 启动、GitHub 托管 runner 全矩阵结果（待账户计费修复 + performance 手动触发 ×2）、VoiceOver 实际播报。全部完成后才能重新评估正式发布结论。

状态定义：

- **部分修复**：主要风险已有实质性治理，但仍有可复现缺口或未完成的验收条件。
- **未修复**：核心风险仍存在，或尚无实现及可信验证证据。
- 只有在对应验收命令产生新鲜成功结果，并将代码证据更新到本文后，才可把事项移出本清单。

## 发布阻断

### P1-11 缺少正式发布签名、公证和权限链 — 外部凭据环境验收待处理

- **状态**：未修复（本地流程已实现；真实凭据验收未执行）
- **现状（2026-08-11）**：仓库就绪的发布流程 `scripts/release-app.sh` 已实现并自测通过：hardened runtime 签名、entitlements 应用、严格验证、公证提交、stapling、Gatekeeper 评估、stapler 验证顺序执行；`--dry-run` 输出 shell 转义命令且无副作用；Team ID 写入非密钥 manifest；缺少必需配置或产物结构不完整时非零退出。`scripts/tests/test-release-app.sh` 覆盖 help/未知选项/缺配置/dry-run/构建失败传播/fake-tool 成功顺序。
- **代码证据**：`scripts/release-app.sh`（8 步真实顺序）；`scripts/tests/test-release-app.sh`；`scripts/build-app.sh` 支持 `LAUNCHPAD_BUILD_OUTPUT_DIR` 注入。
- **剩余工作（外部）**：在具备 Developer ID 凭据的安全环境注入 `LAUNCHPAD_CODESIGN_IDENTITY` / `LAUNCHPAD_TEAM_ID` / `LAUNCHPAD_NOTARY_PROFILE` 执行真实签名与公证；在干净 macOS 环境验证 Gatekeeper 启动。（2026-09-21 本机复查：钥匙串无 Developer ID 证书，唯一签名身份为 127.0.0.1 的 SSL 证书，且 `xcrun notarytool` 无已存储的公证 profile，本机不具备验收前置条件；完整命令清单见 `docs/release-readiness-external-acceptance.md` 验收 2。）
- **验收标准**：发布产物依次通过 `codesign --verify --deep --strict --verbose=2`、`spctl --assess --type execute --verbose=4` 和 `xcrun stapler validate`；产物包含预期 entitlements，并在干净 macOS 环境通过 Gatekeeper 启动。

## 非阻断治理事项

### P2-12 无障碍分页控件仍不完整 — VoiceOver 人工验收待处理

- **状态**：部分修复（本地自动化完成；VoiceOver 未执行）
- **现状（2026-08-11）**：`PageControlView` 已改为 `.slider` 角色，暴露当前页/总页数 value（"Page N of M"）、min/max，并实现 `accessibilityPerformIncrement/Decrement`（复用鼠标选择顺序 selectDot → onDotSelected → update()，边界与零页拒绝）。六类分支测试（零页/单页/中间/首页 decrement/末页 increment/成功动作）全部通过。
- **代码证据**：`Sources/LaunchPad/Views/PageControl.swift`（无障碍 API）；`Tests/LaunchPadTests/Views/ViewLayerTests.swift`（PageControlViewTests 22 项）。
- **剩余工作（外部）**：VoiceOver 实际播报"当前页/总页数"并验证键盘调整体验；焦点、搜索态与文件夹分页状态的真实 UI 验收。
- **验收标准**：自动化测试覆盖 value、increment、decrement 和边界页（已完成）；VoiceOver 可播报"当前页/总页数"并能切换页面（待外部执行）。

### P2-15 测试有效性治理未完成 — GitHub 托管 runner 结果待处理

- **状态**：部分修复（本地完成；真实 runner 未执行）
- **现状（2026-08-11）**：弱断言审计脚本 `scripts/check-test-quality.sh` 已落地（拒绝 `#expect(true)` / `Thread.sleep` / `RunLoop.current.run`），`scripts/tests/test-test-quality.sh` fixture 自测通过；性能测试已有预热后 11 次采样 median/p95；`.github/workflows/quality.yml` 在 push/PR 的 `macos-26` 与 `macos-26-xlarge` 上运行脚本自测、质量扫描、完整测试与严格 Debug/Release 构建；`.github/workflows/performance.yml` 仅手动/每周在固定 runner（`macos-26-xlarge`）运行性能基准并上传日志 artifact 保留趋势。（2026-09-21：macos-14 镜像已被 GitHub 弃用，矩阵与固定 runner 迁移至 macOS 26，与本地门禁工具链同代。）
- **代码证据**：`scripts/check-test-quality.sh`；`scripts/tests/test-test-quality.sh`；`.github/workflows/quality.yml`；`.github/workflows/performance.yml`。
- **剩余工作（外部）**：在真实 GitHub 托管 runner 上确认 quality 工作流全绿、性能工作流在固定 runner 连续运行无偶发失败并保留趋势记录。
- **验收标准**：静态审计规则进入 CI（已完成）；关键失败、回滚与边界分支具备行为断言（已完成）；性能基准在固定 runner 连续运行无偶发失败并保留趋势记录（待外部执行）。

### 发布门禁连续两次运行（`scripts/test-release.sh` ×2）

- **状态**：已通过（2026-09-21，外部验收）
- **现状（2026-09-21）**：在 commit 9428ebe 上连续两次完整运行 `./scripts/test-release.sh`，两次均退出 0。产物 `.superpowers/sdd/release-gate.xKDRTL` 与 `.superpowers/sdd/release-gate.RpsCCX` 的 `result.status` 均为 `passed`，provenance start/end 检查均通过，每轮各含三次发现集/执行集一致性校验（`✔ Test run with 1173 tests in 65 suites passed`），无跳过、超时或残留进程。发现集与执行集完全一致，实际规模 1173 项/65 suites（此前记录 1126/65，已按实际输出更新）。
- **过程记录**：首轮被 host-boundary 扫描拒绝（测试直接写 `UserDefaults.standard`）→ 引入 `AppDelegate.hotkeyPermissionDefaults` 注入点并以 suite 隔离 defaults 替代（commit 9428ebe）；门禁须在代理命令沙箱外执行（沙箱阻断 SwiftPM index store 写入，触发 EBADF rename 错误）。2026-08-11 记录的 `/bin/ps` 受限问题在本轮沙箱外执行时未复现，watchdog 正常工作。
- **验收标准**：连续两次执行 `./scripts/test-release.sh` 均退出 0，发现集与执行集完全一致 —— 已满足（2026-09-21）。

## 2026-08-11 已完成并移出本清单的事项

以下 13 项本地验收全部完成，代码证据与验收命令结果已写回实施计划（`docs/release-readiness-plan.md`，Task 1–7）：

| 事项 | 覆盖 Task | 验收要点 |
|---|---|---|
| P0-6 发布测试门禁不可用 | Task 1 | 发现集数据驱动（Swift Testing 实测 1109/62→1126/65）；warnings-as-errors 入 Debug/Release |
| P2-13 Release 严格告警门禁未通过 | Task 1 | 严格 Debug/Release 构建退出 0 |
| P1-12 覆盖率脚本不传播失败 | Task 2 | `coverage.sh` 六类故障注入均非零且无成功结论 |
| P1-13 覆盖工具错误被误判满覆盖 | Task 2 | 空/损坏 profdata、错误二进制、缺失工具均被识别为失败 |
| P2-16 发布与覆盖工具不可移植 | Task 2/3 | 脚本无用户目录/固定架构/固定 Xcode 路径；`coverage.sh`、`release-app.sh` 就绪 |
| P1-9 布局写入未全部事务化 | Task 4 | 删除无事务 `LayoutPersistence.saveLayout`；布局写入只走原子事务 |
| P3-1 PageItem 可表达非法状态 | Task 4 | 类型化工厂 + 验证器；非法组合无法通过公开 API 构造 |
| P3-3 遗留无生产调用入口未收敛 | Task 4 | `LayoutPersistence` 全仓库无残留 |
| P3-4 键码魔法数字散落 | Task 6 | `KeyboardKeyCode` 具名常量；生产代码字面量扫描零命中 |
| P3-5 IUO 与强制解包生命周期风险 | Task 7 | 生产代码 IUO/强制解包清零；AppDelegate 服务 optional + 消费者 guard |
| P2-14 视图与拖拽协调共享状态耦合 | Task 6 | 三个窄协议按消费者声明；DragController 保持唯一状态所有者 |
| P2-12 分页无障碍（本地自动化部分） | Task 5 | slider 角色/value/增减动作 + 六分支测试通过 |
| P2-15 测试有效性（本地部分） | Task 7 | 质量审计脚本 + CI 工作流落地 |

## 更新规则

1. 修复提交必须同时更新对应事项的代码证据和验收结果。
2. "部分修复"或"未修复"只有在全部验收标准满足后才能移出本文。
3. 六项发布阻断清零后，重新运行完整测试、严格 Debug/Release 构建、发布门禁、签名与公证验证，再更新总体发布结论。
4. 真实 Apple 签名/公证、Gatekeeper 启动、GitHub 托管 runner 结果与 VoiceOver 播报不得用 dry-run、mock 或静态检查替代；发布门禁必须在可执行 `/bin/ps` 的完整环境运行。
5. 逐项执行外部验收的完整命令与记录模板见 `docs/release-readiness-external-acceptance.md`；验收完成后按该文档"完成后回写"一节更新本文件。
