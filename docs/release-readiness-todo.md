# 质量状态与待处理事项

> 核查日期：2026-07-29
> 范围：对 2026-07-15 发布就绪评审中的 41 项问题逐项复核当前代码、脚本与测试状态。
> 最近更新：2026-09-21（项目定位调整为个人本机项目，移除 GitHub CI/CD 与对外发布设施）

## 项目定位（2026-09-21 起）

- 个人项目，仅在本机构建与运行，不对外分发。
- 原对外发布验收不再作为条件：Developer ID 签名/公证/stapling、干净环境 Gatekeeper 启动、GitHub 托管 runner 结果、VoiceOver 外部人工验收。
- 随定位调整移除的设施：`.github/workflows/`（quality、performance）、`scripts/release-app.sh` 及其自测 `scripts/tests/test-release-app.sh`、外部验收清单 `docs/release-readiness-external-acceptance.md`；均可在 git 历史中恢复。

## 当前结论

- 本地质量门禁全部通过：发布门禁 `./scripts/test-release.sh` 连续两次通过（1173 tests / 65 suites，commit 9428ebe），严格 Debug/Release 构建（warnings-as-errors）随之通过；脚本自测、测试质量审计与覆盖率工具链可用。
- 原评审问题处置：40 项已修复（含 2026-08-11 完成的 13 项本地整改）；P1-11、P2-12、P2-15 按个人项目定位处置完毕，见"已关闭事项"。
- 质量结论：**本机日常使用条件已具备**。后续变更以发布门禁与脚本自测为质量门禁，见"更新规则"。

状态定义：

- **已关闭（范围变更）**：事项随项目定位调整不再适用；保留历史记录与代码证据备查。
- 只有在对应验收命令产生新鲜成功结果，并将代码证据更新到本文后，才可把事项移出或关闭。

## 已关闭事项

### P1-11 缺少正式发布签名、公证和权限链 — 已关闭（范围变更）

- **状态**：已关闭（2026-09-21；个人项目不对外分发，签名/公证链不再需要）
- **历史记录（2026-08-11）**：`scripts/release-app.sh` 曾实现完整发布链（hardened runtime 签名、entitlements 应用、严格验证、公证提交、stapling、Gatekeeper 评估、stapler 验证）并通过 `scripts/tests/test-release-app.sh` 自测；2026-09-21 本机复查确认钥匙串无 Developer ID 证书（唯一签名身份为 127.0.0.1 的 SSL 证书）、无 notarytool 公证 profile。
- **处置**：脚本与自测随定位调整移除（git 历史可恢复）；本机使用经 `./scripts/build-app.sh` 打包为 `.build/LaunchPad.app` 直接运行，无需签名。

### P2-12 无障碍分页控件仍不完整 — 已关闭（本地自动化完成）

- **状态**：已关闭（自动化验收完成；VoiceOver 人工验证转为日常个人可选项）
- **现状（2026-08-11）**：`PageControlView` 已改为 `.slider` 角色，暴露当前页/总页数 value（"Page N of M"）、min/max，并实现 `accessibilityPerformIncrement/Decrement`（复用鼠标选择顺序 selectDot → onDotSelected → update()，边界与零页拒绝）。六类分支测试（零页/单页/中间/首页 decrement/末页 increment/成功动作）全部通过。
- **代码证据**：`Sources/LaunchPad/Views/PageControl.swift`（无障碍 API）；`Tests/LaunchPadTests/Views/ViewLayerTests.swift`（PageControlViewTests 22 项）。
- **备注**：本机开启 VoiceOver（Command+F5）时，页码控件应播报"Page N of M"并支持 Control+Option+Command+↑/↓ 调整；如体验异常按普通缺陷处理，不再单列验收项。

### P2-15 测试有效性治理未完成 — 已关闭（本地完成）

- **状态**：已关闭（本地治理完成；CI 工作流随定位调整移除）
- **现状（2026-08-11）**：弱断言审计脚本 `scripts/check-test-quality.sh` 已落地（拒绝 `#expect(true)` / `Thread.sleep` / `RunLoop.current.run`），`scripts/tests/test-test-quality.sh` fixture 自测通过；性能测试已有预热后 11 次采样 median/p95。
- **补充（2026-09-21）**：原 `.github/workflows/quality.yml`（macos-26 / macos-26-xlarge 矩阵）与 `performance.yml` 随定位调整移除；移除前 macos-26 job 曾全绿（1173 tests / 65 suites，与本地门禁一致），xlarge job 因 GitHub 账户计费问题始终未运行——该阻塞随 CI 移除自然消除。
- **代码证据**：`scripts/check-test-quality.sh`；`scripts/tests/test-test-quality.sh`。

### 发布门禁连续两次运行（`scripts/test-release.sh` ×2）

- **状态**：已通过（2026-09-21）
- **现状（2026-09-21）**：在 commit 9428ebe 上连续两次完整运行 `./scripts/test-release.sh`，两次均退出 0。产物 `.superpowers/sdd/release-gate.xKDRTL` 与 `.superpowers/sdd/release-gate.RpsCCX` 的 `result.status` 均为 `passed`，provenance start/end 检查均通过，每轮各含三次发现集/执行集一致性校验（`✔ Test run with 1173 tests in 65 suites passed`），无跳过、超时或残留进程。
- **过程记录**：首轮被 host-boundary 扫描拒绝（测试直接写 `UserDefaults.standard`）→ 引入 `AppDelegate.hotkeyPermissionDefaults` 注入点并以 suite 隔离 defaults 替代（commit 9428ebe）；门禁须在代理命令沙箱外执行（沙箱阻断 SwiftPM index store 写入，触发 EBADF rename 错误）。2026-08-11 记录的 `/bin/ps` 受限问题在本轮沙箱外执行时未复现，watchdog 正常工作。
- **后续**：门禁继续作为本地变更质量门禁；受控文件变更后在干净提交态复跑（见"更新规则"）。
- **复跑记录（2026-09-21，定位调整后）**：在 commit 68b2a66 上复跑 `./scripts/test-release.sh` 通过（退出 0，`✔ Test run with 1173 tests in 65 suites passed`，严格 Debug/Release 构建通过，产物 `.superpowers/sdd/release-gate.lwMABG`）；五个脚本自测全部通过。附注：`/usr/bin/swift` 脚本模式在代理命令沙箱内会把 swift-frontend 的完整 argv 暴露给脚本的 `CommandLine.arguments`（实测 argc=39），导致 `test-event-parser.sh` 在沙箱内误报 usage 错误——脚本自测须与门禁一样在沙箱外执行。

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
2. 事项只有在全部验收标准满足、或随项目定位调整关闭后，才可移出或关闭。
3. 受控文件（Sources / Tests / scripts / Package.swift / Resources）发生变更的提交，须在干净提交态复跑发布门禁 `./scripts/test-release.sh`（门禁自身要求提交态）与脚本自测 `for t in scripts/tests/test-*.sh; do zsh "$t"; done`，确认通过。
4. 发布门禁与脚本自测必须在可执行 `/bin/ps` 的完整环境、代理命令沙箱外运行（沙箱会阻断 SwiftPM index store 写入，并干扰 `/usr/bin/swift` 脚本模式的参数传递）。
5. 如未来恢复对外发布，从 git 历史恢复 `scripts/release-app.sh`、其自测与外部验收清单，重新建立 CI 与签名/公证链后再评估发布结论。
