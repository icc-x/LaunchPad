# 发布就绪待处理事项

> 核查日期：2026-07-29
> 范围：对 2026-07-15 发布就绪评审中的 41 项问题逐项复核当前代码、脚本与测试状态。

## 当前结论

- 已修复：35 项
- 部分修复：0 项
- 未修复：6 项
- 待处理：6 项
- 发布结论：**当前不可正式发布**。六项发布阻断中 P0-6、P2-13 已清零，剩余 P1-11、P1-12、P1-13、P2-16 全部验收通过后，才能重新评估发布结论。

状态定义：

- **部分修复**：主要风险已有实质性治理，但仍有可复现缺口或未完成的验收条件。
- **未修复**：核心风险仍存在，或尚无实现及可信验证证据。
- 只有在对应验收命令产生新鲜成功结果，并将代码证据更新到本文后，才可把事项移出本清单。

## 发布阻断

### P0-6 发布测试门禁不可用

- **状态**：已修复（验收通过 2026-08-02）
- **现状**：门禁已改为从实际测试发现结果生成执行集合，三轮运行均要求发现集与执行集完全一致，过时测试名称硬编码已移除。
- **代码证据**：`scripts/test-release.sh:462-467` `extract_discovery` 从 `swift test ... list` 提取发现集，`:469-478` `extract_execution_set` 校验执行集数量、事件版本与发现集 `cmp` 一致，`:480-493` `assert_run_log` 校验汇总行与失败标记；`:817-849` 三轮 `discovery-N`/`tests-N` 均通过 `run_watchdog` 执行并对比轮间稳定性。脚本中已无“恰好 6 项”或“SearchEngine 缓存命中”硬编码。
- **验收结果**：2026-08-02 连续两次执行 `./scripts/test-release.sh` 均退出 0；两次 manifest 共 40 项 `command.*.status`/`check.*.status` 全部为 0；三轮均为 `✔ Test run with 1109 tests in 62 suites passed`，无跳过、超时、残留进程或失败标记。

### P1-11 缺少正式发布签名、公证和权限链

- **状态**：未修复
- **现状**：仓库只有本地 `.app` 组装脚本，没有可执行的正式发布流程。
- **代码证据**：`scripts/build-app.sh:14-23` 仅执行 Release 构建、复制二进制和资源；未调用 `codesign`、`notarytool` 或 `stapler`，也未应用 `Resources/LaunchPad.entitlements`。`scripts/release-app.sh` 不存在。
- **剩余工作**：建立可配置的签名、hardened runtime、公证、stapling 和最终验证流程，密钥与 Apple 凭据只能由安全环境注入。
- **验收标准**：发布产物依次通过 `codesign --verify --deep --strict --verbose=2`、`spctl --assess --type execute --verbose=4` 和 `xcrun stapler validate`；产物包含预期 entitlements，并在干净 macOS 环境通过 Gatekeeper 启动。

### P1-12 覆盖率脚本不传播失败

- **状态**：未修复
- **现状**：覆盖率测量仍可能在构建、测试或报告生成失败后以成功退出，不能作为发布门禁。
- **代码证据**：`scripts/coverage_measure.sh:3`、`scripts/final_measure.sh:3` 使用 `set +e`；二者累计 `FAIL` 但未据此非零退出。`scripts/measure_coverage.py:29-31` 注释掉构建失败退出逻辑。
- **剩余工作**：统一覆盖率入口，逐阶段检查退出码；构建、测试发现、每个套件、profraw 合并及 `llvm-cov` 任一失败都必须终止并返回非零状态。
- **验收标准**：正常运行退出 0；分别注入构建失败、测试失败、缺失 profraw 和无效 `llvm-cov` 路径时均退出非零，且不输出成功覆盖率结论。

### P1-13 覆盖工具错误可能被误判为满覆盖

- **状态**：未修复
- **现状**：`llvm-cov` 的 stderr 和失败状态仍被吞掉，空输出可被统计为零个未覆盖行。
- **代码证据**：`scripts/final_measure.sh:105-121` 将 `llvm-cov show` stderr 重定向到 `/dev/null`，再用 `grep -c ... || true` 计算零计数行；`scripts/measure_coverage.py` 调用 `llvm-cov show` 后未对每个返回码建立完整失败门禁。
- **剩余工作**：先验证二进制、profdata 和工具版本匹配，再解析结构化或明确校验过的报告；禁止将空输出解释为 100%。
- **验收标准**：使用不匹配 profdata、损坏 profdata、错误二进制或缺失工具运行时均退出非零；只有有效报告明确返回零个未覆盖行时才允许声明满覆盖。

### P2-13 Release 严格告警门禁未通过

- **状态**：已修复（验收通过 2026-08-02）
- **现状**：actor 隔离、Sendable 捕获与未使用值等告警已清零，warnings-as-errors 已纳入统一发布门禁的 Debug 构建、测试发现、测试执行与 Release 构建全部环节。
- **代码证据**：`scripts/test-release.sh:802-806` debug-build、`:819-823` discovery、`:830-834` tests、`:851-856` release-build 均带 `-Xswiftc -warnings-as-errors`；修复提交 `88f6e25 fix: enforce deterministic release builds`（2026-07-29）清理了 App/Views/Controllers 与测试中的告警来源。
- **验收结果**：2026-08-02 复核 `swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors` 与 Debug 同参数构建均退出 0；随后 `./scripts/test-release.sh` 以相同严格度连续两次退出 0（见 P0-6 验收结果）。

### P2-16 发布与覆盖工具不可移植

- **状态**：未修复
- **现状**：发布辅助脚本缺失，现有覆盖脚本依赖开发机绝对路径、固定架构和固定 Xcode 安装位置。
- **代码证据**：`scripts/coverage_measure.sh:5-10`、`scripts/final_measure.sh:5-12` 和 `scripts/measure_coverage.py:13-19` 硬编码 `/Users/icc/Documents/LaunchPad/LaunchPad`、`arm64-apple-macosx` 与 `/Applications/Xcode.app`。约定入口 `scripts/coverage.sh` 和 `scripts/release-app.sh` 均不存在。
- **剩余工作**：从脚本自身位置解析项目根目录，使用 `swift build --show-bin-path`、`xcrun --find` 和实际 target triple 发现产物与工具，并补齐稳定入口。
- **验收标准**：在不同仓库路径及至少 arm64、x86_64 两种 macOS runner 上，发布与覆盖入口无需修改源码即可运行；脚本中不再出现用户目录、固定 target triple 或固定 Xcode 路径。

## 非阻断治理事项

### P1-9 布局写入仍未全部事务化

- **状态**：已修复（验收通过 2026-08-02）
- **现状**：无生产调用的遗留逐项写入入口已删除，生产布局写入只走 `LayoutDropIntent -> LayoutRepository -> StorageManager` 原子事务；文件夹重命名经 `updateItem` 单条事务并保留错误传播。
- **代码证据**：`Sources/LaunchPad/Services/LayoutPersistence.swift` 已删除（含 `saveLayout` 与 `loadLayout`，均无生产调用）；`Sources/LaunchPad/Services/LayoutRepository.swift:30-32` 布局变更走存储层原子事务，`:34-46` `renameFolder` 单条事务写入。`Tests/LaunchPadTests/Storage/StorageManagerLayoutMutationTests.swift` 逐故障注入回滚测试与 `Tests/LaunchPadTests/Integration/IntegrationTests.swift` 回滚重开测试保持全绿。`scripts/test-release.sh` 静态策略新增 `dead-layout-entrypoint`（拒绝 `LayoutPersistence\.|saveLayout\()` 于 Sources/Tests）。
- **验收结果**：2026-08-02 删除后 `rg 'LayoutPersistence\.|saveLayout\(' Sources Tests` 无命中；逐故障注入（BEGIN/read/item/page/insert/delete/COMMIT）回滚后 `persistedLayoutSnapshot() == before` 全部通过；全量 `swift test` 1104 tests / 61 suites 通过。

### P2-12 无障碍分页控件仍不完整

- **状态**：已修复（验收通过 2026-08-02；VoiceOver 真实播报留待外部验收）
- **现状**：页码控件已改为可调节 slider 无障碍元素，暴露当前页/总页数值与增减页动作，动作复用现有 `selectDot → onDotSelected → update` 数据流并在越界时拒绝。
- **代码证据**：`Sources/LaunchPad/Views/PageControl.swift:86-141` 实现 `accessibilityRole() == .slider`、`accessibilityValue()`（1 基当前页）、min/max、`accessibilityValueDescription()`（`Page N of M` / `No pages`）、`accessibilityIncrement`/`accessibilityDecrement`（`stepPage(by:)` 边界拒绝）。
- **验收结果**：2026-08-02 新增 11 个测试（`PageControlAccessibilityTests`）覆盖零页、单页、中间页 increment/decrement、首页递减、末页递增及 value/min/max/描述/回调序列，全部通过；旧 `.group` 角色断言更新为 `.slider`。

### P2-14 视图与拖拽协调仍存在共享状态耦合

- **状态**：已修复（验收通过 2026-08-02）
- **现状**：消费者只依赖各自所需的窄拖拽协议，具体 `DragController` 仅由 AppDelegate 构造，View 层不再出现控制器实现标识符。
- **代码证据**：`Sources/LaunchPad/Controllers/LaunchPadViewController.swift:6-18` 定义 `LaunchPadDragControlling`，`Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift:9-21` 定义 `GridDragControlling`，`Sources/LaunchPad/Views/FolderOverlayView.swift:51-60` 定义 `FolderDragControlling`；`Sources/LaunchPad/Controllers/DragController.swift:257-268` 通过 extension 遵守三个协议（状态机 38 分支未改动）。`scripts/test-release.sh` 静态策略新增 `drag-controller-leak`（Views 目录不得出现 `DragController` 标识符）。
- **验收结果**：2026-08-02 新增 8 个协议 fake 测试（begin/hover/结束/取消/预览回调注入）全部通过；`rg 'DragController' Sources/LaunchPad/Views` 无命中；拖拽全量测试（`DragController|AppGridInteractionCoordinator|FolderOverlayView` 等 295 项）通过。

### P2-15 测试有效性治理未完成

- **状态**：已修复（验收通过 2026-08-02；GitHub 托管 runner 结果留待外部验收）
- **现状**：弱断言与固定等待已有静态审计入口并进入 CI，功能门禁与性能趋势工作流分离；关键失败/回滚/边界分支的行为断言已由既有测试维持。
- **代码证据**：`scripts/check-test-quality.sh` 拒绝 `#expect(true)`/`Thread.sleep`/`RunLoop.current.run`（默认扫描 Tests）；`scripts/tests/test-test-quality.sh` 自测验证坏 fixture 被拒、好 fixture 通过（TDD 先写自测后实现）。`.github/workflows/quality.yml` 在 push/PR 于 `macos-14` 与 `macos-14-xlarge` 双 runner 跑脚本自测、质量扫描、全量测试与严格 Debug/Release 构建；`.github/workflows/performance.yml` 仅手动/每周在固定 runner 采集 `--filter PerformanceTests --no-parallel` 日志并以 artifact 归档趋势。
- **验收结果**：2026-08-02 `zsh scripts/tests/test-test-quality.sh` 通过；`./scripts/check-test-quality.sh` 对 Tests 扫描 clean；性能测试（预热后 11 次采样 median/p95）在门禁三轮运行中全部通过。

### P3-1 `PageItem` 仍可表达非法状态

- **状态**：未修复
- **现状**：公共模型仍允许 item 类型与 app/group 元数据任意组合。
- **代码证据**：`Sources/LaunchPadProtocols/Models/PageItem.swift:5-29` 将 `type`、`app`、`group` 作为彼此独立的公开初始化参数，因此仍可创建 `.app` 且 `app == nil`、`.group` 且 `group == nil`，或 `.page` 同时携带元数据。
- **剩余工作**：采用带关联值的领域枚举，或在公共构造器和 repository 边界集中校验不变量，并制定数据库与测试工厂迁移方案。
- **验收标准**：非法组合无法通过公开 API 构造；对旧数据库非法记录有明确拒绝或修复策略；合法 page/app/group 编解码和迁移测试全部通过。

### P3-3 遗留无生产调用入口尚未收敛

- **状态**：已修复（验收通过 2026-08-02）
- **现状**：无生产调用的 `LayoutPersistence` 整个文件（含 `saveLayout` 与 `loadLayout`）已删除，门禁新增死代码扫描防回归。
- **代码证据**：`Sources/LaunchPad/Services/LayoutPersistence.swift` 已删除；`Tests/LaunchPadTests/Views/ViewLayerTests.swift` 中 `LayoutPersistenceTests` 套件（5 个测试）已删除。`scripts/test-release.sh` 静态策略 `dead-layout-entrypoint` 拒绝 `LayoutPersistence\.|saveLayout\(` 于 Sources/Tests。
- **验收结果**：2026-08-02 `rg 'LayoutPersistence\.|saveLayout\(' Sources Tests` 无命中；`MockItemWriter` 仍被 `ProtocolTests` 使用予以保留；全量 `swift test` 1104 tests / 61 suites 通过。

### P3-4 键码魔法数字仍散落

- **状态**：未修复
- **现状**：键盘导航和全局热键仍直接使用平台键码数字，语义与平台约束没有集中管理。
- **代码证据**：`Sources/LaunchPad/App/AppDelegate.swift:364` 使用 `49` 注册 Option+Space，`:408-416` 直接映射 `53/36/126/125/123/124/48/51`；`Sources/LaunchPad/App/HotkeyManager.swift:185-186` 再次比较 `49`。
- **剩余工作**：建立具名键码定义或可注入映射，统一热键与本地导航使用点，并为映射增加测试。
- **验收标准**：生产代码不再出现无说明的键码字面量；所有支持按键、未知按键和热键冲突分支均有测试。

### P3-5 IUO 与强制解包仍有生命周期风险

- **状态**：已修复（验收通过 2026-08-02）
- **现状**：生产代码 IUO 声明与强制解包已清零：必需依赖改为构造注入或 guard 消费，延迟 UI 状态改为惰性存储/计算属性（view 未加载访问安全，loadView 重建时重置为新实例），数据库路径与面板 contentView 提供确定性回退。
- **代码证据**：`Sources/LaunchPad/App/AppDelegate.swift:23-41` 服务与控制器属性全部转可选并在消费点 guard（`setupHotkey`/`statusItemClicked`/本地事件监视器），`:497-507` `databasePath` 使用 `applicationSupportURLProvider`/`databaseDirectoryCreator` 注入点与 home 目录回退；`Sources/LaunchPad/Controllers/LaunchPadViewController.swift:66-140` 子视图改为惰性存储+`makeSubView` 计算属性，`loadView` 开头重置存储；`Sources/LaunchPad/Views/FolderOverlayView.swift` 子视图 lazy 化；`Sources/LaunchPad/Views/AppGridCollectionView.swift` dataSource lazy、cell 转换 `as?` guard；`Sources/LaunchPad/Views/AppGridFlowLayout.swift:88-94` `compactMap`；`Sources/LaunchPad/App/LaunchPadWindowController.swift:86-92` `contentView?.bounds ?? contentRect`。
- **验收结果**：2026-08-02 新增 3 个测试（databasePath 回退/系统 URL 分支、view 未加载访问子视图）；`rg ':\s*[A-Za-z<>\[\](), .]+!\s*$' Sources --glob '*.swift'` 与强制解包扫描均无命中；全量 `swift test` 1126 tests / 64 suites 通过。

## 更新规则

1. 修复提交必须同时更新对应事项的代码证据和验收结果。
2. “部分修复”或“未修复”只有在全部验收标准满足后才能移出本文。
3. 六项发布阻断清零后，重新运行完整测试、严格 Debug/Release 构建、发布门禁、签名与公证验证，再更新总体发布结论。
