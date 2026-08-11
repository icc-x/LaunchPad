# 发布就绪待处理事项

> 核查日期：2026-07-29
> 范围：对 2026-07-15 发布就绪评审中的 41 项问题逐项复核当前代码、脚本与测试状态。
> 最近更新：2026-08-11（发布就绪整改 Task 1–7 本地验收完成后回写）

## 当前结论

- 已修复：40 项（含 2026-08-11 完成的 13 项本地整改）
- 部分修复：0 项
- 未修复：1 项
- 待处理（外部环境验收）：3 项（P1-11、P2-12、P2-15）+ 发布门禁连续两次运行（受受限环境阻塞）
- 发布结论：**本地可执行门禁全部通过**。真实 Apple 签名/公证/stapling、干净 macOS Gatekeeper 启动、GitHub 托管 Intel 与 Apple Silicon runner 结果、VoiceOver 实际播报，以及 `scripts/test-release.sh` 连续两次运行完成后，才能重新评估正式发布结论。

状态定义：

- **部分修复**：主要风险已有实质性治理，但仍有可复现缺口或未完成的验收条件。
- **未修复**：核心风险仍存在，或尚无实现及可信验证证据。
- 只有在对应验收命令产生新鲜成功结果，并将代码证据更新到本文后，才可把事项移出本清单。

## 发布阻断

### P1-11 缺少正式发布签名、公证和权限链 — 外部凭据环境验收待处理

- **状态**：未修复（本地流程已实现；真实凭据验收未执行）
- **现状（2026-08-11）**：仓库就绪的发布流程 `scripts/release-app.sh` 已实现并自测通过：hardened runtime 签名、entitlements 应用、严格验证、公证提交、stapling、Gatekeeper 评估、stapler 验证顺序执行；`--dry-run` 输出 shell 转义命令且无副作用；Team ID 写入非密钥 manifest；缺少必需配置或产物结构不完整时非零退出。`scripts/tests/test-release-app.sh` 覆盖 help/未知选项/缺配置/dry-run/构建失败传播/fake-tool 成功顺序。
- **代码证据**：`scripts/release-app.sh`（8 步真实顺序）；`scripts/tests/test-release-app.sh`；`scripts/build-app.sh` 支持 `LAUNCHPAD_BUILD_OUTPUT_DIR` 注入。
- **剩余工作（外部）**：在具备 Developer ID 凭据的安全环境注入 `LAUNCHPAD_CODESIGN_IDENTITY` / `LAUNCHPAD_TEAM_ID` / `LAUNCHPAD_NOTARY_PROFILE` 执行真实签名与公证；在干净 macOS 环境验证 Gatekeeper 启动。
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
- **现状（2026-08-11）**：弱断言审计脚本 `scripts/check-test-quality.sh` 已落地（拒绝 `#expect(true)` / `Thread.sleep` / `RunLoop.current.run`），`scripts/tests/test-test-quality.sh` fixture 自测通过；性能测试已有预热后 11 次采样 median/p95；`.github/workflows/quality.yml` 在 push/PR 的 `macos-14` 与 `macos-14-xlarge` 上运行脚本自测、质量扫描、完整测试与严格 Debug/Release 构建；`.github/workflows/performance.yml` 仅手动/每周在固定 runner 运行性能基准并上传日志 artifact 保留趋势。
- **代码证据**：`scripts/check-test-quality.sh`；`scripts/tests/test-test-quality.sh`；`.github/workflows/quality.yml`；`.github/workflows/performance.yml`。
- **剩余工作（外部）**：在真实 GitHub 托管 runner 上确认 quality 工作流全绿、性能工作流在固定 runner 连续运行无偶发失败并保留趋势记录。
- **验收标准**：静态审计规则进入 CI（已完成）；关键失败、回滚与边界分支具备行为断言（已完成）；性能基准在固定 runner 连续运行无偶发失败并保留趋势记录（待外部执行）。

### 发布门禁连续两次运行（`scripts/test-release.sh` ×2）

- **状态**：待处理（受限环境阻塞）
- **现状（2026-08-11）**：`test-release.sh` 的 watchdog 依赖 `/bin/ps eww -axo pid=,command=` 捕获测试进程 token；本宿主环境系统级禁止 `/bin/ps`（`operation not permitted`，关闭命令沙箱后仍被拒），门禁在进入 SwiftPM 前即退出 1。已尝试前台/后台/非沙箱三种方式均无法运行。
- **剩余工作（外部）**：在可执行 `/bin/ps` 的完整 macOS 环境连续运行两次门禁，确认发现集与执行集一致、无跳过/超时/残留进程。
- **验收标准**：连续两次执行 `./scripts/test-release.sh` 均退出 0，发现集与执行集完全一致（此前 Task 1 记录为 1109 项/62 suites，当前测试集为 1126 项/65 suites，需以实际输出为准）。

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
