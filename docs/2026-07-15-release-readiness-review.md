# LaunchPad 全面工程审查与发布就绪评估

> 审查日期：2026-07-15  
> 审查范围：`Sources/`、`Tests/`、`Package.swift`、`Resources/`、`scripts/`、`README.md` 及现有工程文档  
> 审查目标：按极致工程学与正式上线标准，评估代码质量、抽象设计、架构、测试、性能与安全  
> 结论：**当前版本不满足上线发布标准**

---

## 1. 执行摘要

本轮共审阅：

- 40 个生产 Swift 文件；
- 35 个测试 Swift 文件及 2 个测试辅助文件；
- 883 个测试、57 个测试 suite；
- 4 个构建/覆盖率脚本；
- 应用 Info.plist、entitlements、Package manifest 和发布说明。

审查覆盖了 UI 生命周期、窗口 5 种状态、键盘 3 种模式、拖拽主状态与 hover 子状态、搜索空/非空/过期结果、SQLite CRUD/事务/NULL/错误路径、文件监控、无障碍设置、动画 normal/reduced 分支和发布脚本的所有显式控制流。

核心结论如下：

1. 主网格布局、键盘输入、拖放持久化和首次启动数据展示存在确定性功能断链。
2. SQLite 绑定、事务提交和 Schema 初始化存在数据损坏或“假成功”风险。
3. 搜索防抖和拖拽调度违反 MainActor/主线程约束。
4. 增量扫描无法获得现有 app，卸载、改名和路径变化同步实际不可用。
5. 当前测试并非全绿，现有覆盖率产物过期，覆盖率脚本还会将失败误报为成功。
6. 打包脚本没有签名、公证、hardened runtime 或 entitlement 应用流程，无法作为正式发布产物。

### 1.1 严重度定义

| 级别 | 定义 | 发布策略 |
|---|---|---|
| P0 | 核心功能不可用、发布门禁失效或直接阻断发布 | 必须在任何发布前修复 |
| P1 | 高概率导致数据错误、崩溃、功能失效或发布产物不可用 | 必须在正式上线前修复 |
| P2 | 重要可靠性、性能、架构或可维护性风险 | 应纳入当前发布周期 |
| P3 | 低风险代码质量或长期演进问题 | 可进入后续工程治理 |

---

## 2. 新鲜验证结果

以下结果来自 2026-07-15 的实际命令执行，不引用 README 或历史覆盖率报告中的旧状态。

| 验证项 | 结果 | 证据/说明 |
|---|---|---|
| Debug/全量测试 | 失败 | `swift test` 以 exit 1 / signal 5 结束，并出现固定断言失败 |
| 并行测试 | 失败 | `swift test --parallel` 出现 AppDelegate、性能测试失败及 signal 5 |
| 固定失败复跑 | 失败 | `AppGridCollectionViewTests/testAcceptDrop_onGroupTarget_returnsTrue` 隔离运行仍失败 |
| 性能用例隔离复跑 | 通过 | IconCache 1000 次访问隔离运行约 0.210s；并行时曾为 0.331s，说明墙钟阈值脆弱 |
| Fresh release build | 成功但有 warning | 全新 `/tmp` build path 构建成功，产生至少 13 项生产代码 warning |
| 当前覆盖率 | 无可信数字 | `.profdata` 创建于 7 月 11 日，测试二进制更新于 7 月 15 日，LLVM 报 profile 过期/无覆盖数据 |
| 打包脚本直接执行 | 失败 | `scripts/build-app.sh` 没有执行权限，README 中的直接执行方式会 permission denied |
| 审查基线 | 干净 | 审查过程未修改生产代码或测试代码；本报告是审查后的唯一新增文件 |

这与以下历史声明冲突：

- [`README.md`](../README.md#L38) 的 debug/release “0 warnings”；
- [`README.md`](../README.md#L40) 的“520+ tests，0 失败”；
- [`docs/coverage-progress.md`](coverage-progress.md#L1) 的历史 100% 覆盖结论。

历史报告可作为当时状态记录保留，但不能继续作为当前提交的发布证据。

---

## 3. P0：阻断发布问题

### P0-1 主网格多行项目会重叠

**代码证据**

- [`AppGridFlowLayout.swift:55`](../Sources/LaunchPad/Views/AppGridFlowLayout.swift#L55) 获取所有 layout attributes；
- 61-64 行把每一个 attribute 的 `frame.origin.y` 改为同一个中心值。

**触发路径**

网格中出现超过一行的应用。横向 flow layout 原本通过不同 y 坐标形成多行，统一改写 y 后，同一列中的多项会重叠。

**影响**

- 五行网格可能退化为重叠项目；
- supplementary/其他 attributes 也会被无差别改写；
- 主界面属于核心功能，不能发布。

**测试问题**

[`ViewLayerTests.swift:696`](../Tests/LaunchPadTests/Views/ViewLayerTests.swift#L696) 在 727-730 行反而要求所有 attribute 使用同一个 y，固化了错误行为。

**建议**

保留每个 item 的相对 y，仅按内容整体高度计算统一偏移；新增至少 2 行、3 行和 5 行的真实 layout attributes 断言。

### P0-2 键盘搜索丢失首字符及后续字符

**代码证据**

- [`KeyboardNavigator.swift:70`](../Sources/LaunchPad/Controllers/KeyboardNavigator.swift#L70) 在 idle 收到字符时只返回 `.enterSearchMode(char)`，没有把 `mode` 改为 `.search`；
- [`LaunchPadViewController.swift:572`](../Sources/LaunchPad/Controllers/LaunchPadViewController.swift#L572) 处理 `.enterSearchMode` 时只显示搜索框，没有写入关联的首字符，也没有调度搜索；
- [`AppDelegate.swift:280`](../Sources/LaunchPad/App/AppDelegate.swift#L280) 调用 VC 后无条件返回 suppress，原始事件不会继续传给 NSSearchField。

**触发路径**

窗口可见时直接输入任意字符。

**影响**

首字符被吞掉，navigator 仍处于 idle；后续字符继续重复 `.enterSearchMode`，搜索模式无法建立。

**测试问题**

[`LaunchPadViewControllerTests.swift:344`](../Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift#L344) 将“连续字符始终返回 enterSearchMode”作为正确结果，但没有验证搜索框文本和真实搜索结果。

**建议**

在一个原子入口中完成模式切换、首字符写入、焦点设置和搜索调度，并增加“输入 safari 后快照只含 Safari”的入口级测试。

### P0-3 ESC、方向键和 Enter 的生产事件链不可达

**代码证据**

[`HotkeyManager.swift:168`](../Sources/LaunchPad/App/HotkeyManager.swift#L168) 在 172-174 行对 ESC、四个方向键和 Enter 直接返回原事件，没有调用 `onKeyDown`。

**影响**

[`AppDelegate.swift:268`](../Sources/LaunchPad/App/AppDelegate.swift#L268) 中的 ESC、翻页、选择和启动映射在真实 local monitor 入口不可达。

**测试问题**

[`HotkeyManagerTests.swift:437`](../Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift#L437) 明确记录 `onKeyDown should not fire for special keys`，测试方向与产品需求相反；AppDelegate 测试直接调用闭包，绕过了真实事件入口。

**建议**

所有可处理键统一交给 `onKeyDown`，以回调返回值决定吞掉或放行；用 local monitor 入口做端到端按键测试。

### P0-4 拖放仅修改视觉快照，不写入业务数据

**代码证据**

- [`AppGridCollectionView.swift:360`](../Sources/LaunchPad/Views/AppGridCollectionView.swift#L360) 拖到文件夹时只调用 `dragController.handleDrop()`；
- 普通重排只修改 diffable snapshot，然后调用 `handleDrop()`；
- 全仓生产调用搜索显示 `beginEditing`、`simulateReorder` 和 `FolderController.addToFolder` 均只有定义，没有生产调用；
- [`DragController.swift:171`](../Sources/LaunchPad/Controllers/DragController.swift#L171) 只能提交 `currentOrder`，但 UI 拖放从未更新该数组；
- 边缘移动在 [`DragController.swift:197`](../Sources/LaunchPad/Controllers/DragController.swift#L197) 仍写入 `itemId: 0`、`toPage: 0` 占位值，且没有消费者。

**影响**

- 同页重排刷新后恢复；
- 拖入文件夹无效；
- 跨页移动未完成；
- README 所述 6 种拖拽能力不具备真实持久化闭环。

**建议**

让拖放上下文显式携带 dragged ID、source parent、target parent 和目标 index；数据库事务成功后再提交 UI snapshot。该方案会改变现有拖拽流程，实施前需确认交互语义。

### P0-5 首次启动扫描完成后 UI 仍保持空数据

**证据链**

1. [`AppDelegate.swift:103`](../Sources/LaunchPad/App/AppDelegate.swift#L103) 先执行 `setupControllers()`；
2. [`LaunchPadWindowController.swift:59`](../Sources/LaunchPad/App/LaunchPadWindowController.swift#L59) 访问 `viewController.view`，触发 `viewDidLoad()`；
3. [`LaunchPadViewController.swift:181`](../Sources/LaunchPad/Controllers/LaunchPadViewController.swift#L181) 在 `viewDidLoad` 中立即 `loadData()`；
4. 此时首次扫描尚未发生，数据库为空；
5. [`AppDelegate.swift:106`](../Sources/LaunchPad/App/AppDelegate.swift#L106) 随后才执行 `performInitialScan()`；
6. 首次扫描成功路径没有调用 `viewController.loadData()`。

**影响**

首次打开窗口可能显示空网格，直到后续文件事件或一次关闭/重开间接触发重新加载。

**建议**

明确启动数据流：先加载已有布局并展示，再后台扫描，扫描成功后主线程刷新；首次空库和已有数据库都应有集成测试。

### P0-6 当前测试门禁失败且不具备确定性

**实测证据**

- 全量 `swift test` 失败并出现 signal 5；
- `swift test --parallel` 出现并行状态污染和性能阈值失败；
- [`AppGridCollectionViewTests.swift:425`](../Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift#L425) 隔离运行稳定失败；
- FolderOverlay、FileWatcher 还存在单套件失败/超时；
- HotkeyManager suite 存在构建完成后进程不退出的情况。

**建议**

正式发布门禁必须使用单一、可重复、带总超时且退出码可信的测试命令。所有 AppKit process-global 状态、事件 monitor、FSEvent stream 和 status item 必须在 teardown 中释放。

---

## 4. P1：高风险问题

### P1-1 增量扫描无法获得任何已存 app

[`AppDelegate.swift:310`](../Sources/LaunchPad/App/AppDelegate.swift#L310) 只调用 `fetchAllItems(parentId: nil)`；[`StorageManager.swift:184`](../Sources/LaunchPad/Storage/StorageManager.swift#L184) 对 nil 生成 `i.parent_id IS NULL`，只返回顶层 page。首次分页生成的 app 全部挂在 page 下，因此 [`AppScanner.swift:123`](../Sources/LaunchPad/Services/AppScanner.swift#L123) 得到的 `existingApps` 恒为空。

**后果**

- 卸载 app 不会删除；
- app 改名/路径变化不会更新；
- 已存在 app 被重复当成新 app 插入并触发唯一约束错误；
- 新 app 的 ordering 从错误基线开始。

**建议**

增加专用 `fetchAllApps()` 或批量读取完整层级，禁止调用方把“顶层 items”误当“全部 items”。

### P1-2 搜索防抖在后台队列伪装成 MainActor

- [`SearchDebouncer.swift:57`](../Sources/LaunchPad/Services/SearchDebouncer.swift#L57) 把闭包交给 Scheduler；
- 60 行使用 `MainActor.assumeIsolated`；
- 生产 Scheduler 在 [`DragController.swift:230`](../Sources/LaunchPad/Controllers/DragController.swift#L230) 创建私有后台队列，并在 242 行直接执行 work item。

输入任意正常增长的非空查询，100ms 后可能触发执行器断言或后台线程 UI 访问。

**建议**

移除 `nonisolated(unsafe)` 和 `assumeIsolated`；使用真正的 `Task { @MainActor in ... }` hop，或把 UI 调度器定义为 MainActor 专用协议。

### P1-3 拖拽 hover 回调从后台线程进入 UI

[`DragController.swift:193`](../Sources/LaunchPad/Controllers/DragController.swift#L193) 和 206 行使用同一个后台 Scheduler，并直接修改 DragController 状态、调用绑定到 [`LaunchPadViewController.swift:220`](../Sources/LaunchPad/Controllers/LaunchPadViewController.swift#L220) 的 UI 回调。

**建议**

将 DragController 整体限定为 `@MainActor`，或把纯计算状态与 UI 回调拆开并显式切换执行器。

### P1-4 SQLite 文本/BLOB 绑定违反缓冲区生命周期契约

**代码证据**

- [`StorageManager.swift:54`](../Sources/LaunchPad/Storage/StorageManager.swift#L54) 等所有 `sqlite3_bind_text` 将 destructor 传 `nil`；
- [`StorageManager.swift:276`](../Sources/LaunchPad/Storage/StorageManager.swift#L276) 的 BLOB 在 `withUnsafeBytes` 闭包结束后才执行 `sqlite3_step`，destructor 同样为 nil。

nil 表示 `SQLITE_STATIC`，SQLite 假设指针持续有效；Swift 临时 NSString/Data 缓冲区不提供该保证。

**影响**

Release 优化或内存复用下可能写入损坏文本、路径或图标数据。

**建议**

统一封装 SQLite bind helper，所有文本/BLOB 使用 `SQLITE_TRANSIENT`，同时检查每个 bind 返回码。

### P1-5 BEGIN/COMMIT 失败会被报告为成功

[`StorageManager.swift:39`](../Sources/LaunchPad/Storage/StorageManager.swift#L39)、90、236 行忽略 BEGIN 结果；82-83、153-154、257-258 行先设置 `committed = true`，再忽略 COMMIT 结果。

磁盘满、I/O 错误、锁冲突或延迟约束失败时，调用方仍收到成功，并且 defer 不再回滚。

**建议**

建立唯一事务 helper：检查 BEGIN，执行 body，检查 COMMIT，仅成功后更新状态；失败时检查并记录 ROLLBACK 结果。

### P1-6 Schema 错误被吞掉，数据库恢复链不可达

[`Schema.swift:65`](../Sources/LaunchPad/Storage/Schema.swift#L65) 对建表错误只日志后继续，版本插入结果也被忽略；[`StorageManager.swift:27`](../Sources/LaunchPad/Storage/StorageManager.swift#L27) 因此不会抛错。AppDelegate 只在 storageFactory 抛错后才执行损坏恢复。

**建议**

Schema 初始化改为 throwing 的原子事务，并在初始化末尾验证必要表、版本和完整性。

### P1-7 scannedApps 出现重复 bundle ID 会触发运行时陷阱

[`AppScanner.swift:131`](../Sources/LaunchPad/Services/AppScanner.swift#L131) 使用要求 key 唯一的 `Dictionary(uniqueKeysWithValues:)`。

用户目录、`/Applications` 和 `/System/Applications` 存在相同 bundle ID 副本时会 precondition failure。

**建议**

改用 `uniquingKeysWith:`，并明确用户应用、系统应用和全局应用之间的覆盖优先级。优先级属于产品行为，实施前需确认。

### P1-8 应用扫描不递归，遗漏 Utilities 等应用

[`AppScanner.swift:49`](../Sources/LaunchPad/Services/AppScanner.swift#L49) 每个目录只调用一次 `contentsOfDirectory`，只识别第一层 `.app`。`/Applications/Utilities`、`/System/Applications/Utilities` 等目录内应用不会进入结果。

**建议**

使用受控递归枚举，并明确是否跳过 package descendants、符号链接和隐藏目录。

### P1-9 首次分页和文件夹操作缺少领域事务

- [`AppScanner.swift:88`](../Sources/LaunchPad/Services/AppScanner.swift#L88) 吞掉 page 插入失败；111 行完全忽略 app 插入失败；
- [`FolderController.swift:16`](../Sources/LaunchPad/Controllers/FolderController.swift#L16) 创建文件夹需要 1 次 insert 和 2 次 update；
- 解散、移出文件夹同样是多步写入；
- [`LayoutPersistence.swift:10`](../Sources/LaunchPad/Services/LayoutPersistence.swift#L10) 逐条保存布局。

任意中间步骤失败都会留下半完成状态。

**建议**

不要向业务层暴露通用裸事务闭包；在 repository 层提供 `createFolder`、`moveItems`、`saveLayoutBatch` 等原子领域操作。

### P1-10 数据库初始化失败会留下不可操作后台进程

[`AppDelegate.swift:95`](../Sources/LaunchPad/App/AppDelegate.swift#L95) 先切换为 accessory；99-102 行数据库失败只 return，没有调用已有 `appTerminator`，菜单、热键和窗口也未创建。

**建议**

失败时终止应用，或先构建最小恢复菜单提供重试/重建/退出。该行为会改变启动失败流程，需确认产品方案。

### P1-11 正式发布没有签名、公证和可信权限链

[`scripts/build-app.sh:14`](../scripts/build-app.sh#L14) 到 23 行只有构建和复制：

- 没有 codesign；
- 没有 hardened runtime；
- 没有应用 [`LaunchPad.entitlements`](../Resources/LaunchPad.entitlements#L1)；
- 没有 notarization/stapling；
- 没有最终 `codesign --verify --deep --strict`；
- 脚本文件模式为 `100644`，README 的直接执行命令不可用。

无稳定签名还会影响 Gatekeeper、SMAppService 和辅助功能授权持久性。

### P1-12 覆盖率脚本会把测试失败报告为成功

- [`coverage_measure.sh:3`](../scripts/coverage_measure.sh#L3) 和 [`final_measure.sh:3`](../scripts/final_measure.sh#L3) 使用 `set +e`；
- 两者只累计 FAIL，不按 FAIL 非零退出；
- [`measure_coverage.py:29`](../scripts/measure_coverage.py#L29) 注释掉构建失败退出逻辑；
- 三个脚本都可能在测试失败后自然 exit 0。

**建议**

构建、测试发现、每个 suite、profraw 合并、llvm-cov show/report 任一失败都必须传播非零退出码。

### P1-13 覆盖工具错误会被误判为 100%

[`final_measure.sh:105`](../scripts/final_measure.sh#L105) 吞掉 `llvm-cov` stderr，空输出被统计为 0 个未覆盖行；[`measure_coverage.py:125`](../scripts/measure_coverage.py#L125) 同样没有检查每次 `llvm-cov show` 的 return code。

当前 `.profdata` 与二进制不匹配，已经证明历史产物不能作为当前覆盖率证据。

### P1-14 测试会修改用户真实 Dock 和登录项状态

- [`AppScannerTests.swift:145`](../Tests/LaunchPadTests/Services/AppScannerTests.swift#L145) 直接操作 `~/Library/Application Support/Dock/LaunchPadLayout.plist`；
- 153-161 行使用 `try?` 备份、删除、恢复，进程中断或备份冲突可能丢失用户数据；
- 179 行写入测试 plist；
- [`AppDelegateTests.swift:538`](../Tests/LaunchPadTests/App/AppDelegateTests.swift#L538) 直接调用真实 SMAppService unregister/register。

**建议**

路径、文件读取和登录项服务必须注入；测试只能访问临时目录和 mock，不得改宿主机状态。

---

## 5. P2：重要质量、性能和架构问题

### P2-1 搜索缓存返回过期对象

[`SearchEngine.swift:169`](../Sources/LaunchPad/Services/SearchEngine.swift#L169) 的缓存 key 只有 `query.lowercased()`，不包含 items 版本。安装、卸载、改名后再次搜索相同 query 会返回旧 PageItem。

建议引入 layout/data generation，或在 loadData 后显式失效缓存。

### P2-2 SearchEngine 声明 Sendable，但 LRU 无任何同步

[`SearchEngine.swift:98`](../Sources/LaunchPad/Services/SearchEngine.swift#L98) 使用 `@unchecked Sendable`；内部 LRU 的 get 也会修改双向链表。并发使用同一 engine 或 struct 副本可能破坏字典/链表。

建议使用 actor、锁保护完整 LRU 操作，或移除 Sendable 并限定执行器。

### P2-3 单个 SQLite connection 被两个独立队列使用

[`StorageManager.swift:9`](../Sources/LaunchPad/Storage/StorageManager.swift#L9) 只有一个 db handle，却使用独立 read/write queue。读可能在同一连接的写事务中间进入并看到随后回滚的中间状态。

建议让单一 actor/串行 executor 拥有 connection；确需并行读时使用独立只读 connection。

### P2-4 查询中途错误被当成正常 EOF

[`StorageManager.swift:202`](../Sources/LaunchPad/Storage/StorageManager.swift#L202) 只循环 SQLITE_ROW，任何 SQLITE_IOERR/CORRUPT/BUSY 都会退出循环并返回部分数组；`StorageError.queryFailed` 从未使用。

建议最终 step 只有 SQLITE_DONE 才能成功返回，否则抛 queryFailed 并保留 SQLite 扩展错误信息。

### P2-5 图标磁盘缓存跨进程基本失效

[`IconCache.swift:135`](../Sources/LaunchPad/Services/IconCache.swift#L135) 把磁盘中的 PNG 与 live icon 的 TIFF 原始字节比较，编码和尺寸不同；2x 数据只写不读。

建议在缓存表持久化 app modification date 或内容版本，按 backing scale 选择 1x/2x representation。

### P2-6 主线程承担扫描、数据库和图标编码 I/O

AppDelegate 是 MainActor，但 [`AppDelegate.swift:333`](../Sources/LaunchPad/App/AppDelegate.swift#L333) 同步扫描三个目录并读写 SQLite；[`AppGridCollectionView.swift:209`](../Sources/LaunchPad/Views/AppGridCollectionView.swift#L209) 配置 cell 时同步读图标缓存、提取系统图标并可能进行 PNG 编码。

文件夹 cell 还在 228 行逐个查询子项，形成 UI 层 N+1。

建议后台构建不可变 view model/icon payload，再一次性在主线程应用；禁止 AppKit data source 回调执行磁盘写入。

### P2-7 FileWatcher 自保留和重复 start 泄漏资源

[`FileWatcher.swift:43`](../Sources/LaunchPad/Services/FileWatcher.swift#L43) `passRetained(self)`，唯一释放点是显式 stop；deinit 因自保留可能永远不可达。连续 start 会覆盖旧 stream 和 pointer。

建议使用 FSEvent context 的 retain/release 回调或明确外部所有权，并使 start 幂等。

### P2-8 HotkeyManager 的 opaque retain 未平衡

[`HotkeyManager.swift:84`](../Sources/LaunchPad/App/HotkeyManager.swift#L84) `passRetained(self)`，105 行静态属性又强持有；注销只清理静态引用，没有 release opaque retain。

建议保存 refcon 并在 unregister 精确 release 一次；增加 weak 引用释放测试。

### P2-9 文件夹滚动 observer 重复注册且不移除

[`FolderOverlayView.swift:151`](../Sources/LaunchPad/Views/FolderOverlayView.swift#L151) 每次 open 都调用 observe；[`FolderOverlayView.swift:303`](../Sources/LaunchPad/Views/FolderOverlayView.swift#L303) 没有保存 block observer token。

反复打开文件夹会累积 observer 和重复回调。应保存单一 token，并在重注册/deinit 移除。

### P2-10 主分页计算和页码同步错误

- [`AppGridFlowLayout.swift:41`](../Sources/LaunchPad/Views/AppGridFlowLayout.swift#L41) 定义 `pageWidth = bounds.width`；
- 46 行再次计算 `bounds.width / pageWidth`，非零时恒为 1；
- [`PageScrollView.swift:78`](../Sources/LaunchPad/Views/PageScrollView.swift#L78) 滑动结束后没有向 PageControl 发出当前页变化；
- 圆点只在程序化导航路径更新。

建议由单一 PagingCoordinator 管理 viewport、section count、current page 和 page control。

### P2-11 应用启动状态机与生产入口断开

[`LaunchPadViewController.swift:386`](../Sources/LaunchPad/Controllers/LaunchPadViewController.swift#L386) 直接走自己的 cell 动画和 NSWorkspace；[`WindowLifecycle.swift:54`](../Sources/LaunchPad/Controllers/WindowLifecycle.swift#L54) 的 `handleAppClick` 没有生产调用者。

`.launching` 和窗口淡出只在测试中可达，生产依赖窗口失焦副作用关闭。

建议 VC 只发出 launch intent，统一交给 lifecycle/window controller。

### P2-12 无障碍支持存在断链

- [`AppGridCollectionView.swift:259`](../Sources/LaunchPad/Views/AppGridCollectionView.swift#L259) 扁平化所有 section 后始终用 section 0 解析 cell，第二页 VoiceOver 行错误；
- [`PageControl.swift:88`](../Sources/LaunchPad/Views/PageControl.swift#L88) 只有 group role 和 label，没有可调节 value/action；
- [`AccessibilityObservers.swift:19`](../Sources/LaunchPad/Utilities/AccessibilityObservers.swift#L19) 从 app UserDefaults 读取高对比度，而不是 NSWorkspace 系统 API。

### P2-13 生产 warning 与 Swift 6 严格并发目标不一致

Fresh release build 出现：

- MainActor 隔离方法从非隔离上下文调用；
- non-Sendable closure 跨 DispatchQueue；
- completion 被 Sendable closure 捕获；
- 未使用捕获、未使用返回值。

代表位置：[`LaunchPadViewController.swift:333`](../Sources/LaunchPad/Controllers/LaunchPadViewController.swift#L333)、[`AppDelegate.swift:61`](../Sources/LaunchPad/App/AppDelegate.swift#L61)、[`AppGridCollectionView.swift:146`](../Sources/LaunchPad/Views/AppGridCollectionView.swift#L146)。

建议将 release 的 warnings-as-errors 作为门禁，但必须先修复现有 warning，不能直接开启后让构建永久失败。

### P2-14 分层存在逻辑循环和依赖倒置不完整

Package target 依赖方向没有循环：

```text
LaunchPadProtocols <- LaunchPad <- LaunchPadApp
```

但模块内部存在逻辑循环：

```text
LaunchPadViewController -> AppGridCollectionView
AppGridCollectionView   -> DragController
LaunchPadViewController -> DragController
```

证据见 [`LaunchPadViewController.swift:25`](../Sources/LaunchPad/Controllers/LaunchPadViewController.swift#L25) 和 [`AppGridCollectionView.swift:23`](../Sources/LaunchPad/Views/AppGridCollectionView.swift#L23)。

此外：

- VC 依赖具体 IconCache/SearchEngine/Controller，而不是最小协议；
- DataStoring 同时包含读、写、重排和图标数据，接口过宽；
- AppScanning/HotkeyManaging 协议没有覆盖生产调用所需能力，因此 AppDelegate 仍依赖具体类。

建议以用户动作/事件协议解耦 View 和 Controller，并按消费者定义窄接口。

### P2-15 测试数量大，但有效验证密度不足

静态统计：

| 类型 | 数量 |
|---|---:|
| 无任何断言 | 100 |
| 仅检查非空/类型存在 | 57 |
| 唯一断言为恒真或自反比较 | 25 |
| 合计弱验证测试 | 182 |
| 依赖真实 sleep/RunLoop/timeout | 16 |
| 单次 Date 墙钟阈值性能测试 | 5 |

典型问题：

- [`AppDelegateTests.swift:373`](../Tests/LaunchPadTests/App/AppDelegateTests.swift#L373) 多个扫描测试最终只 `#expect(true)`；
- [`FileWatcherTests.swift:118`](../Tests/LaunchPadTests/Services/FileWatcherTests.swift#L118) 声称覆盖 callback guard，实际未触发 callback；
- [`PerformanceTests.swift:29`](../Tests/LaunchPadTests/Performance/PerformanceTests.swift#L29) 用单次墙钟时间断言 1ms/10ms/50ms，容易受机器负载影响。

建议按行为价值重写测试，不以“执行到某一行”作为测试目标。

### P2-16 发布和覆盖脚本不可移植

三个覆盖脚本硬编码：

- `/Users/icc/Documents/LaunchPad/LaunchPad`；
- `arm64-apple-macosx`；
- `/Applications/Xcode.app/...`。

代表位置：[`coverage_measure.sh:5`](../scripts/coverage_measure.sh#L5)、[`final_measure.sh:5`](../scripts/final_measure.sh#L5)、[`measure_coverage.py:13`](../scripts/measure_coverage.py#L13)。

建议从脚本路径计算根目录，用 `swift build --show-bin-path` 和 `xcrun --find` 发现产物和工具。

---

## 6. P3：代码质量与长期演进问题

### P3-1 PageItem 可表达非法状态

[`PageItem.swift:5`](../Sources/LaunchPadProtocols/Models/PageItem.swift#L5) 允许：

- `.app` 但 `app == nil`；
- `.group` 但 `group == nil`；
- `.page` 同时带 app/group。

[`StorageManager.swift:69`](../Sources/LaunchPad/Storage/StorageManager.swift#L69) 还会把非法 app/group 写成缺少子表记录的孤立 item。

建议使用带关联值的领域枚举，或至少在 repository 边界验证 invariant。该调整会影响公共模型和测试工厂，需先确认迁移方案。

### P3-2 Schema 版本表没有迁移能力

[`Schema.swift:86`](../Sources/LaunchPad/Storage/Schema.swift#L86) 只在版本表为空时写 currentVersion，从不读取、比较或迁移已有版本。

当前 version 仍为 1，暂未触发，但下一次 Schema 变更会被阻塞。

### P3-3 明确死代码和未闭合设计

包括但不限于：

- `StorageError.queryFailed` 定义但未使用；
- `AppGridFlowLayout.gridParams` 只赋值不读取；
- `LayoutPersistence.saveLayout` 没有生产调用者；
- `FolderController.addToFolder` 没有生产调用者；
- `WindowLifecycle.handleAppClick` 没有生产调用者；
- 多个 ErrorRecovery strategy 仅测试调用；
- `pendingCrossPageMove` 写入占位数据后无人消费。

建议先恢复真实调用链，再删除确认无需求的覆盖率驱动代码。

### P3-4 魔法数字仍分散

尽管已有 AnimationConstants，仍散落：

- 键码 53/36/126/125/123/124/48/51；
- hotkey keyCode 49；
- 屏幕回退宽度 1440；
- 动画 0.1、0.8、2.0；
- 拖拽边缘宽度 40。

建议键码集中为具名映射，动画值统一引用 AnimationConstants；布局回退值进入 GridLayout 配置。

### P3-5 强制解包与 IUO 增加生命周期脆弱性

代表位置：

- [`PageScrollView.swift:68`](../Sources/LaunchPad/Views/PageScrollView.swift#L68) `documentView!`；
- [`LaunchPadWindowController.swift:50`](../Sources/LaunchPad/App/LaunchPadWindowController.swift#L50) `contentView!`；
- AppDelegate/VC 多个 service/view IUO；
- [`LaunchPadViewController.swift:627`](../Sources/LaunchPad/Controllers/LaunchPadViewController.swift#L627) `selectedIndex!`。

部分解包受当前生命周期保护，但在重构、失败初始化或 headless 环境下风险会放大。建议使用明确初始化状态和 guard，而非扩大 IUO 范围。

---

## 7. 按审查维度归纳

### 7.1 代码质量

主要问题：

- 13+ 生产 warning；
- 恒真/空断言测试；
- try? 吞错过多；
- SQLite 错误缺少原始 code/message；
- 死代码、魔法数字、IUO/force unwrap；
- 注释多次声明“主线程”“真实覆盖”，但代码与实测不符。

改进原则：

1. 先消除确定性行为错误，再处理风格问题；
2. 错误必须沿边界传播或转化为明确结果，不能只日志；
3. 注释解释 invariant 和线程/事务保证，不描述已经被代码否定的假设；
4. release warning 必须归零并纳入门禁。

### 7.2 抽象与设计

优点：

- Package target 依赖单向；
- ItemReading/ItemWriting/ImageStoring 已体现接口隔离意图；
- Grid/Search 等纯函数较易测试。

问题：

- 部分协议只为局部测试存在，生产仍依赖具体类；
- DataStoring 过宽；
- ItemWriting 太底层，无法表达领域事务；
- Scheduler 没有声明执行器语义；
- `@unchecked Sendable` 被用来绕过隔离，而不是证明线程安全；
- View 与 Controller 互相依赖。

推荐设计：

- `@MainActor` 负责 UI、键盘、窗口、拖拽交互状态；
- Storage actor 独占 SQLite connection；
- Repository 提供原子领域操作；
- Scanner 返回明确 diff/result，不直接逐条吞错写库；
- 缓存携带数据版本并有明确失效策略。

### 7.3 架构合理性

当前主数据流意图清晰：

```text
File system -> AppScanner -> StorageManager -> LayoutPersistence
                                      |
                                      v
Keyboard -> ViewController -> DiffableDataSource -> CollectionView
```

但真实执行中存在四处断链：

1. 首次 scan 后没有回流 UI；
2. 增量 scan 只拿到 page，拿不到 app；
3. drag snapshot 没有回流 storage；
4. app click 没有进入 WindowLifecycle。

因此当前问题不是“再加一层抽象”，而是先让已有数据流闭环。

### 7.4 测试质量

局部单元测试数量多、分支覆盖意图强，但存在：

- 182 个弱验证测试；
- 生产调用链未覆盖；
- 真实系统状态被修改；
- AppKit 全局资源未隔离；
- 性能测试使用单次墙钟阈值；
- 覆盖率脚本不传播失败；
- 当前没有可信 fresh coverage 数字。

发布标准应从“执行行数量”升级为：

- 核心用户流程端到端通过；
- 错误路径验证最终状态；
- 事务测试验证失败后状态不变；
- 并发测试验证 actor/线程；
- 覆盖报告与当前二进制可追溯匹配。

### 7.5 性能与安全

性能风险：

- 主线程全目录扫描和 plist I/O；
- cell 配置期间 SQLite、图标提取和 PNG 编码；
- LayoutPersistence/文件夹缩略图 N+1；
- 磁盘图标缓存跨进程失效；
- observer/stream 泄漏；
- 搜索缓存无数据版本。

安全与发布风险：

- SQLite 悬空指针契约违规；
- 测试修改真实 Dock plist 和登录项；
- 未签名、未公证、未启用 hardened runtime；
- entitlements 包含未见生产使用的 Apple Events 权限，应遵循最小权限；
- 无 CI、签名验证、notary 验证和发布 provenance。

未发现网络通信、硬编码密钥或外部依赖供应链面；SQL 值大多使用 bind，不存在明显字符串拼接注入，但 bind 生命周期和返回码处理仍必须修复。

---

## 8. 分支审阅覆盖记录

统计口径为显式 `if / guard / switch / catch / for / while`，并补充 optional binding、`try?`、`??`、可选链和编译条件。以下为人工逐分支审阅的范围摘要。

### 8.1 UI、Controller 与 App

```text
AppDelegate                if 12 / guard 6  / switch 1 / catch 4 / loop 0
HotkeyManager              if 9  / guard 4  / switch 1 / catch 0 / loop 0
LaunchPadWindowController  if 1  / guard 5  / switch 2 / catch 0 / loop 0
DragController             if 4  / guard 11 / switch 2 / catch 1 / loop 0
FolderController           if 1  / guard 0  / switch 0 / catch 0 / loop 1
KeyboardNavigator          if 1  / guard 0  / switch 5 / catch 0 / loop 0
LaunchPadViewController    if 17 / guard 17 / switch 5 / catch 5 / loop 2
WindowLifecycle            if 0  / guard 5  / switch 2 / catch 0 / loop 0
AppGridCollectionView      if 12 / guard 9  / switch 1 / catch 0 / loop 2
FolderOverlayView          if 3  / guard 8  / switch 0 / catch 0 / loop 0
PageScrollView             if 9  / guard 6  / switch 0 / catch 0 / loop 0
其余 View 文件均已逐分支阅读
```

覆盖的状态集合：

- WindowLifecycle：hidden/opening/visible/closing/launching；
- KeyboardNavigator：idle/search/edit 与所有 key case；
- DragController：idle/jiggling/dragging，none/overEdge/overIcon；
- 搜索：空查询、正常查询、回退、过期结果；
- Item：page/app/group；
- 动画：normal/reduce motion/reduce transparency/increase contrast。

### 8.2 Services、Storage、Utilities 与 Models

```text
AppScanner          if 7  / guard 9  / switch 0 / catch 4 / loop 9
FileWatcher         if 3  / guard 4  / switch 0 / catch 0 / loop 0
IconCache           if 9  / guard 4  / switch 0 / catch 0 / loop 0
LayoutPersistence   if 0  / guard 0  / switch 0 / catch 0 / loop 2
SearchDebouncer     if 2  / guard 0  / switch 0 / catch 0 / loop 0
SearchEngine        if 15 / guard 6  / switch 0 / catch 0 / loop 0
Schema              if 3  / guard 2  / switch 0 / catch 0 / loop 1
StorageManager      if 18 / guard 24 / switch 1 / catch 0 / loop 2
GridLayoutCalculator if 2 / guard 0  / switch 0 / catch 0 / loop 0
AnimationRunner     if 2  / guard 0  / switch 1 / catch 0 / loop 0
Accessibility       if 4  / guard 1  / switch 0 / catch 0 / loop 0
ErrorRecovery       if 1  / guard 3  / switch 0 / catch 0 / loop 0
Protocols/Models    无运行时控制分支，已完整阅读
```

---

## 9. 建议整改顺序

### 阶段 A：恢复核心可用性，禁止发布

1. 修复网格 y 布局和分页计算；
2. 修复真实键盘入口、搜索首字符和 navigator 状态；
3. 打通 drag -> domain operation -> storage -> snapshot；
4. 修复首次扫描后刷新和增量扫描完整数据读取；
5. 隔离所有会修改宿主机状态的测试；
6. 建立单一可重复的全量测试命令。

验收标准：核心用户流程端到端通过，全量测试稳定 exit 0，无 signal/超时/跳过核心断言。

### 阶段 B：数据与并发可靠性

1. SQLite bind 使用 SQLITE_TRANSIENT；
2. 建立事务 helper 和领域原子操作；
3. Schema 初始化改为 throwing + migration 基础；
4. Storage actor 独占 connection；
5. UI/Drag/Search 调度统一 MainActor；
6. 修复缓存版本和资源生命周期。

验收标准：失败注入后数据库状态不变，Thread Sanitizer/并发测试无竞争，release warning 为 0。

### 阶段 C：重建发布门禁

1. 覆盖脚本传播所有失败；
2. 从 fresh build 生成可追溯 coverage；
3. 增加 CI、warnings-as-errors、静态检查；
4. 建立 Developer ID 签名、hardened runtime、公证和 stapling；
5. 验证最终 app 的 bundle、entitlements、登录项和 TCC 权限；
6. 执行 README 中尚未完成的手工功能验证矩阵。

验收标准：CI 全绿、覆盖报告与 commit/二进制匹配、最终 `.app` 通过 codesign/Gatekeeper/notary 验证。

---

## 10. 结论

项目已经具备较清晰的目录分层、较多局部单元测试和一定的依赖注入基础，但当前“高覆盖率”主要证明大量代码行被执行，尚未证明核心用户流程真实闭环。

最优先事项不是继续扩充测试数量或增加抽象层，而是：

1. 修复已经由代码证据确认的 P0/P1 调用链；
2. 将 SQLite、调度器和领域操作建立在可证明的线程/事务契约上；
3. 用不会修改宿主机、退出码可信、产物可追溯的测试与发布流水线重新证明质量。

在上述 P0/P1 问题关闭并完成重新验证前，不建议生成或分发正式版本。
