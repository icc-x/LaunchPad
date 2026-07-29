# 发布就绪待处理事项

> 核查日期：2026-07-29
> 范围：对 2026-07-15 发布就绪评审中的 41 项问题逐项复核当前代码、脚本与测试状态。

## 当前结论

- 已修复：27 项
- 部分修复：7 项
- 未修复：7 项
- 待处理：14 项
- 发布结论：**当前不可正式发布**。六项发布阻断全部验收通过后，才能重新评估发布结论。

状态定义：

- **部分修复**：主要风险已有实质性治理，但仍有可复现缺口或未完成的验收条件。
- **未修复**：核心风险仍存在，或尚无实现及可信验证证据。
- 只有在对应验收命令产生新鲜成功结果，并将代码证据更新到本文后，才可把事项移出本清单。

## 发布阻断

### P0-6 发布测试门禁不可用

- **状态**：部分修复
- **现状**：`swift test` 已可稳定完成；但统一发布门禁仍在测试发现阶段失败，不能作为可信发布判据。
- **代码证据**：`scripts/test-release.sh:463` 硬编码要求 `PerformanceTests` 恰好有 6 项；`Tests/LaunchPadTests/Performance/PerformanceTests.swift` 当前只有 5 个 `@Test`。`scripts/test-release.sh:492-497` 仍要求已经不存在的“SearchEngine 缓存命中”性能测试。
- **剩余工作**：让门禁从实际测试发现结果生成执行集合，移除过时测试名称，并保持超时、残留进程和退出码校验。
- **验收标准**：连续两次执行 `./scripts/test-release.sh` 均退出 0，发现集与执行集完全一致，无跳过、超时、残留进程或失败标记。

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

- **状态**：未修复
- **现状**：普通 Release 构建可完成，但将 warning 视为 error 后仍失败，Swift 6 并发与普通编译告警尚未清零。
- **代码证据**：`Package.swift:1` 使用 Swift tools 6.0；`scripts/test-release.sh:846-850` 的 Release 构建没有启用 warnings-as-errors。2026-07-29 复核命令 `swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors` 至少产生 11 个错误。
- **剩余工作**：逐项消除 actor 隔离、Sendable 捕获和未使用值等告警，再把 warnings-as-errors 加入统一发布门禁。
- **验收标准**：Debug 与 Release 的 `swift build ... -Xswiftc -warnings-as-errors` 均退出 0，随后 `./scripts/test-release.sh` 也以相同严格度通过。

### P2-16 发布与覆盖工具不可移植

- **状态**：未修复
- **现状**：发布辅助脚本缺失，现有覆盖脚本依赖开发机绝对路径、固定架构和固定 Xcode 安装位置。
- **代码证据**：`scripts/coverage_measure.sh:5-10`、`scripts/final_measure.sh:5-12` 和 `scripts/measure_coverage.py:13-19` 硬编码 `/Users/icc/Documents/LaunchPad/LaunchPad`、`arm64-apple-macosx` 与 `/Applications/Xcode.app`。约定入口 `scripts/coverage.sh` 和 `scripts/release-app.sh` 均不存在。
- **剩余工作**：从脚本自身位置解析项目根目录，使用 `swift build --show-bin-path`、`xcrun --find` 和实际 target triple 发现产物与工具，并补齐稳定入口。
- **验收标准**：在不同仓库路径及至少 arm64、x86_64 两种 macOS runner 上，发布与覆盖入口无需修改源码即可运行；脚本中不再出现用户目录、固定 target triple 或固定 Xcode 路径。

## 非阻断治理事项

### P1-9 布局写入仍未全部事务化

- **状态**：部分修复
- **现状**：拖放布局变更已通过领域 intent 和存储层事务执行，但遗留批量保存入口仍逐项写入。
- **代码证据**：`Sources/LaunchPad/Services/LayoutRepository.swift:30-32` 将 `LayoutDropIntent` 交给存储层原子变更；`Sources/LaunchPad/Services/LayoutPersistence.swift:8-13` 明确注明无 batch/事务支持，并在循环中逐项 `updateItem`。
- **剩余工作**：删除无生产调用的遗留保存入口，或为其提供原子 `saveLayoutBatch`；同时确认文件夹重命名与未来批量布局操作都遵守同一事务边界。
- **验收标准**：对每类多步布局操作注入中间写失败，数据库快照与操作前完全一致；生产代码中不存在逐项提交的批量布局写入。

### P2-12 无障碍分页控件仍不完整

- **状态**：部分修复
- **现状**：主网格的分页与 section 映射问题已有重构，但页码控件仍只暴露角色和标签，VoiceOver 无法读取当前值或执行增减页操作。
- **代码证据**：`Sources/LaunchPad/Views/PageControl.swift:86-94` 仅实现 `accessibilityRole()` 和 `accessibilityLabel()`，没有 value、increment 或 decrement action。
- **剩余工作**：为页码控件提供当前页/总页数值、可调节角色及增减动作，并验证焦点、搜索态和文件夹分页状态。
- **验收标准**：自动化测试覆盖 value、increment、decrement 和边界页；VoiceOver 可播报“当前页/总页数”并能切换页面。

### P2-14 视图与拖拽协调仍存在共享状态耦合

- **状态**：部分修复
- **现状**：SwiftPM target 依赖方向清晰，主网格委托已收敛到 `AppGridInteractionCoordinator`；但控制器、协调器和文件夹视图仍直接共享 `DragController`。
- **代码证据**：`Package.swift:14-34` 的依赖方向为 `LaunchPadProtocols <- LaunchPad <- LaunchPadApp`；`Sources/LaunchPad/Controllers/LaunchPadViewController.swift:82,255`、`Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift:34,48` 和 `Sources/LaunchPad/Views/FolderOverlayView.swift:72` 都持有或接收 `DragController`。
- **剩余工作**：定义由消费者拥有的窄事件/状态接口，明确编辑模式、拖拽会话和预览状态的唯一所有者，减少跨视图共享可变状态。
- **验收标准**：依赖关系测试证明 View 不直接依赖上层控制器实现；拖拽开始、取消、跨页、入文件夹和结束各分支均只有一个状态写入者。

### P2-15 测试有效性治理未完成

- **状态**：部分修复
- **现状**：明显的 `#expect(true)` 和真实 sleep 已清理，性能测试改为预热后 11 次采样并检查 median/p95；但尚无持续的弱断言审计和稳定基准环境。
- **代码证据**：`Tests/LaunchPadTests/Performance/PerformanceTests.swift:9-35` 定义 11 次采样与预热，`:58-67` 计算 median/p95；仓库搜索 `rg '#expect\(true\)|Thread\.sleep|RunLoop\.current\.run' Tests/LaunchPadTests` 当前无命中。
- **剩余工作**：建立弱断言/仅构造对象测试的审计规则；将对机器负载敏感的绝对耗时阈值放入受控性能环境，并区分功能门禁与趋势监控。
- **验收标准**：静态审计规则进入 CI；关键失败、回滚与边界分支具备行为断言；性能基准在固定 runner 连续运行无偶发失败并保留趋势记录。

### P3-1 `PageItem` 仍可表达非法状态

- **状态**：未修复
- **现状**：公共模型仍允许 item 类型与 app/group 元数据任意组合。
- **代码证据**：`Sources/LaunchPadProtocols/Models/PageItem.swift:5-29` 将 `type`、`app`、`group` 作为彼此独立的公开初始化参数，因此仍可创建 `.app` 且 `app == nil`、`.group` 且 `group == nil`，或 `.page` 同时携带元数据。
- **剩余工作**：采用带关联值的领域枚举，或在公共构造器和 repository 边界集中校验不变量，并制定数据库与测试工厂迁移方案。
- **验收标准**：非法组合无法通过公开 API 构造；对旧数据库非法记录有明确拒绝或修复策略；合法 page/app/group 编解码和迁移测试全部通过。

### P3-3 遗留无生产调用入口尚未收敛

- **状态**：部分修复
- **现状**：旧评审中的多个死代码候选已接入生产链或删除，但 `LayoutPersistence.saveLayout` 仍只有测试调用。
- **代码证据**：`Sources/LaunchPad/Controllers/LaunchPadViewController.swift:813` 已在生产路径调用 `WindowLifecycle.handleAppClick`，`Sources/LaunchPad/Storage/StorageManager.swift` 已实际抛出 `StorageError.queryFailed`；`rg 'LayoutPersistence\.saveLayout'` 仅命中 `Tests/LaunchPadTests/Views/ViewLayerTests.swift:160,168,178`。
- **剩余工作**：逐项记录公共 API 的生产调用者和需求所有者；删除确认无需求的覆盖率驱动入口，或恢复真实调用链并补行为测试。
- **验收标准**：死代码扫描和人工调用链审计无未解释项；保留的公开入口至少有一个生产调用者及对应行为测试。

### P3-4 键码魔法数字仍散落

- **状态**：未修复
- **现状**：键盘导航和全局热键仍直接使用平台键码数字，语义与平台约束没有集中管理。
- **代码证据**：`Sources/LaunchPad/App/AppDelegate.swift:364` 使用 `49` 注册 Option+Space，`:408-416` 直接映射 `53/36/126/125/123/124/48/51`；`Sources/LaunchPad/App/HotkeyManager.swift:185-186` 再次比较 `49`。
- **剩余工作**：建立具名键码定义或可注入映射，统一热键与本地导航使用点，并为映射增加测试。
- **验收标准**：生产代码不再出现无说明的键码字面量；所有支持按键、未知按键和热键冲突分支均有测试。

### P3-5 IUO 与强制解包仍有生命周期风险

- **状态**：部分修复
- **现状**：部分历史强制解包已改为可选访问，但关键 UI 与服务属性仍广泛使用隐式解包可选值，窗口初始化仍存在强制解包。
- **代码证据**：`Sources/LaunchPad/Controllers/LaunchPadViewController.swift:68-74,176`、`Sources/LaunchPad/App/AppDelegate.swift:23-39` 使用多个 IUO；`Sources/LaunchPad/App/LaunchPadWindowController.swift:79` 强制解包 `panel.contentView`。`PageScrollView` 的 `documentView!` 已改为 `documentView?`（`:87`）。
- **剩余工作**：按对象生命周期把必需依赖改为初始化注入，把延迟 UI 状态封装为明确状态或受控可选值，并在失败初始化/headless 测试中覆盖守卫分支。
- **验收标准**：生产代码无未经证明的 IUO/强制解包；初始化失败和 view 未加载场景不崩溃，相关测试通过。

## 更新规则

1. 修复提交必须同时更新对应事项的代码证据和验收结果。
2. “部分修复”或“未修复”只有在全部验收标准满足后才能移出本文。
3. 六项发布阻断清零后，重新运行完整测试、严格 Debug/Release 构建、发布门禁、签名与公证验证，再更新总体发布结论。
