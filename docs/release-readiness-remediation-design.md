# 发布就绪整改设计

> 日期：2026-07-29
> 状态：已确认，等待实施计划

## 目标

按风险优先顺序执行 `docs/release-readiness-todo.md` 中的 14 项待处理事项，在不改变现有产品交互的前提下，建立可信的构建、测试、覆盖率、发布和代码质量门禁。

本轮完成标准不是“代码已编写”，而是每个事项的自动验收条件产生新鲜证据。依赖 Apple 凭据、GitHub 托管 runner 或 VoiceOver 人工操作的验收，不得用模拟结果替代真实结果。

## 已确认决策

1. 采用风险优先的分阶段执行方案，每个 Task 独立测试、审查和提交。
2. 签名与公证采用仓库就绪方案：实现完整脚本、凭据注入和 dry-run，不在本地执行真实 Apple 公证。
3. 允许新增 GitHub Actions，功能门禁与性能趋势工作流分离。
4. 允许收紧 `PageItem` 公共 API；保留结构体和读取属性，改用类型化工厂构造合法状态。
5. 每个 Task 的计划状态、代码证据和验收结果必须实时同步，失败时不得开始下一 Task。
6. 设计和实施计划是执行期间的活动文档；全部整改结束后删除，仅在 Git 历史保留过程，最终未完成事项继续保留在 `docs/release-readiness-todo.md`。

## 执行阶段

### Task 1：严格编译与发布门禁

覆盖 P0-6、P2-13。

- 修复当前 warnings-as-errors 暴露的 Sendable、actor 隔离和未使用返回值问题。
- 保留 `scripts/test-release.sh` 的 watchdog、进程残留和 provenance 机制。
- 删除对固定性能测试数量和过时测试名称的依赖，改为以 Swift Testing 发现集为权威输入。
- 将严格 Debug 和 Release 构建加入发布门禁。

成功条件：严格 Debug/Release 构建退出 0；发布门禁发现集与执行集一致，不依赖固定测试数量。

### Task 2：可信覆盖率工具

覆盖 P1-12、P1-13、P2-16 的覆盖率部分。

- 新建唯一入口 `scripts/coverage.sh`。
- 从脚本位置解析仓库根目录，使用 SwiftPM 和 `xcrun` 发现构建目录、测试二进制与 LLVM 工具。
- 使用一次完整 `swift test --enable-code-coverage` 产生覆盖数据，不保留按套件拼接产物的历史流程。
- 构建、测试、测试发现、profraw 发现、profdata 合并、`llvm-cov report/show` 任一失败都立即返回非零状态。
- 空输出、损坏或不匹配的 profdata、错误二进制和缺失工具必须被识别为失败，禁止输出满覆盖结论。
- 新入口通过故障注入测试后，删除 `coverage_measure.sh`、`final_measure.sh` 和 `measure_coverage.py`。

成功条件：正常路径退出 0；四类故障注入均退出非零且不输出成功结论；脚本不含用户目录、固定架构或固定 Xcode 路径。

### Task 3：发布打包、签名与公证流程

覆盖 P1-11、P2-16 的发布部分。

- 新建 `scripts/release-app.sh`，复用现有构建和 Bundle 组装能力。
- 通过环境变量注入 Developer ID Application 身份、Team ID 和 `notarytool` Keychain Profile 名称。
- 顺序执行 hardened runtime 签名、entitlements 应用、严格签名验证、公证提交、stapling、Gatekeeper 评估和 stapler 验证。
- `--dry-run` 输出经过 shell 转义的命令，不执行签名/网络操作，也不读取或打印密钥内容。
- 缺少必需配置、任一步骤失败或产物结构不完整时立即退出非零。

成功条件：脚本自测和 dry-run 通过；真实签名、公证及干净 macOS Gatekeeper 启动保留为外部凭据环境验收，不在本地提前标记完成。

### Task 4：布局事务与 `PageItem` 不变量

覆盖 P1-9、P3-1、P3-3。

- 删除无生产调用的 `LayoutPersistence.saveLayout` 及仅服务于该入口的测试。
- 保留 `PageItem` 结构体及现有读取属性，新增 `.page(...)`、`.app(...)` 和 `.group(...)` 类型化工厂。
- 将任意 `type/app/group` 组合初始化器改为非公开，所有生产和测试构造点迁移到类型化工厂或受控测试辅助方法。
- 自定义 `Codable` 解码和 SQLite 行解码复用同一个不变量验证器。
- 非法记录以明确错误向上传播，不触发 precondition、强制解包或静默修复。
- 真实布局写入继续只走 `LayoutDropIntent -> LayoutRepository -> StorageManager` 原子事务。

合法状态只有三类：

- page：`type == .page`，`app == nil`，`group == nil`；
- app：`type == .app`，`app != nil`，`group == nil`；
- group：`type == .group`，`app == nil`，`group != nil`。

成功条件：公共 API 无法构造非法组合；Codable 与 SQLite 非法输入均返回错误；布局事务失败后数据库快照不变。

### Task 5：分页无障碍

覆盖 P2-12。

- `PageControlView` 改为 adjustable 无障碍元素。
- 暴露当前页和总页数的 value，并实现 increment/decrement action。
- 动作复用现有 `PageControlViewModel` 边界夹紧逻辑，最终通过 `onDotSelected` 进入现有分页数据流。
- 视觉绘制、鼠标点击和布局尺寸保持不变。

需要覆盖的六类分支：零页、单页、多页中间位置、第一页 decrement、末页 increment、动作导致页面变化。

成功条件：自动化测试覆盖角色、值、两个动作和边界；VoiceOver 播报与人工切页保留为真实 UI 验收。

### Task 6：拖拽状态所有权与输入常量

覆盖 P2-14、P3-4。

- `DragController` 继续作为拖拽会话和预览状态的唯一可变状态所有者，不复制状态机。
- 按消费者定义读取协议和命令协议；`LaunchPadViewController`、`AppGridInteractionCoordinator`、`FolderOverlayView` 只依赖各自需要的窄接口。
- 所有开始、更新 hover、跨页、完成、取消和 native ended 分支仍汇聚到同一个状态所有者。
- 新增具名平台键码定义，统一 AppDelegate 和 HotkeyManager 的生产使用点。
- 不改变 Option+Space、导航键、Delete、Tab 和未知按键的现有行为。

成功条件：View 不直接依赖上层控制器实现；拖拽各终止路径只清理一次；生产代码不存在无说明的键码字面量。

### Task 7：生命周期安全、CI 与最终发布验收

覆盖 P2-15、P3-5 和总体发布结论。

- 将生产 IUO 按生命周期分为必需依赖和延迟状态：必需依赖使用构造注入或完整初始化，延迟状态使用普通可选值和 `guard`。
- 移除未经证明的生产强制解包；失败初始化、view 未加载和 headless 环境返回可测试错误或安全 no-op。
- 新增 GitHub Actions 功能工作流，在 push/PR 运行脚本自测、静态测试质量审计、完整测试和严格 Debug/Release 构建。
- 新增独立性能工作流，仅手动或定时运行固定性能 runner，不阻塞普通功能提交。
- CI 配置包含 Intel 与 Apple Silicon macOS runner；runner 不可用时必须保留真实失败，不降级为单架构成功。
- 最终连续两次运行 `scripts/test-release.sh`，并重新运行完整测试、严格构建和脚本故障注入。

成功条件：本地可执行门禁全部通过；GitHub 托管 runner、真实公证和 VoiceOver 的外部结果按实际状态写回待办。

## 错误处理原则

- Shell 脚本使用严格模式，所有外部命令的失败状态必须显式传播。
- 只在需要检查预期失败的局部区段暂时关闭立即退出，并立即恢复。
- 错误日志包含阶段、稳定错误类别和产物路径，不输出签名或公证敏感信息。
- Swift 模型与存储错误使用可抛出错误传播，不用崩溃或静默修复非法输入。
- UI 延迟状态缺失时使用 `guard` 保持现有流程安全退出，不创建替代业务状态。
- CI 和本地脚本执行同一入口，禁止为 CI 增加跳过性能测试、放宽阈值或忽略失败的旁路。

## 测试策略

每个 Task 采用以下顺序：

1. 写入能证明原问题存在的失败测试或脚本探针。
2. 运行目标测试并确认失败原因与事项一致。
3. 实现满足测试的最小修改。
4. 运行目标测试、受影响套件和完整 `swift test`。
5. 运行严格 Debug/Release 构建与 `git diff --check`。
6. 把命令、退出码和结果写回实施计划，再把 Task 标记为已完成。

脚本故障注入至少覆盖：构建失败、测试失败、空 profraw、损坏 profdata、错误二进制、缺失 LLVM 工具、缺少签名配置和 dry-run 无副作用。

模型测试至少覆盖三类合法状态、所有非法 metadata 组合、Codable round-trip、非法 JSON、非法 SQLite 行和事务回滚。

拖拽测试必须覆盖开始、hover 不变、hover 变化、跨页、进入文件夹、接受、拒绝、取消、native ended、重复终止和过期定时器回调。

## 计划与代码实时同步

实施计划保存为 `docs/release-readiness-plan.md`，Task 状态只有四种：

- `待处理`：尚未开始；
- `进行中`：已开始修改工作树，且当前唯一活动 Task；
- `已完成`：代码和全部本地验收证据已写入同一提交；
- `阻塞`：验收失败或缺少外部条件，计划中记录失败命令、退出码和解除条件。

执行规则：

1. 开始 Task 前先把该 Task 标为进行中，再修改实现。
2. 不并行执行多个 Task，不批量补写状态。
3. Task 完成时把代码、测试、证据和计划状态放在同一提交。
4. Task 阻塞时立即更新计划，不开始后续 Task。
5. 每个提交后检查工作树，防止把无关修改带入 Task。
6. 全部整改结束后删除设计和实施计划文档；最终仍未满足的事项保留在发布待办，完整执行过程由 Git 历史保存。

## 不在本地伪造的验收

以下结果只有真实环境执行后才能完成：

- Apple Developer ID 签名、公证和 stapling；
- 干净 macOS 环境的 Gatekeeper 启动；
- GitHub 托管 Intel 与 Apple Silicon runner 结果；
- VoiceOver 实际播报和键盘调整体验。

本地实现和自动化测试完成后，这些事项仍按实际状态标记为外部验收待处理，不据 dry-run、mock 或静态检查宣称完成。
