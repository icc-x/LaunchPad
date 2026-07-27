# LaunchPad Release Readiness Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 关闭 2026-07-27 复审确认的 16 个未闭环 P0/P1/P2 项，并用可重复的测试、无 warning Release 构建、签名公证验证和发布门禁证明项目达到候选发布条件。

**Architecture:** 保持 Swift 6 + AppKit + SQLite3 现有分层，以发布门禁为最终权威入口。扫描、布局读取/写入、图标磁盘访问和编码迁移到非主线程执行边界，AppKit 状态只在 MainActor 更新；Schema 初始化改为完整错误传播；图标磁盘缓存持久化源修改时间；搜索结果缓存死链删除；本地 bundle 构建与凭据化发布分开。所有变更按 RED-GREEN、独立提交和阶段门禁执行。

**Tech Stack:** Swift 6.0、Swift Testing、AppKit、CoreGraphics/ImageIO、SQLite3、Swift Package Manager、zsh、Python 3、Xcode command-line tools、Developer ID Application、Apple notary service。

**Source Review:** `docs/2026-07-15-release-readiness-review.md` 及 2026-07-27 修复质量复审。

## Global Constraints

- 平台保持 `macOS 14.0+`，Swift tools version 保持 `6.0`，不增加第三方依赖。
- 实施范围仅包括 7 个部分修复项和 9 个未修复/修复无效项；其余 20 项是不可回归基线。
- 不改变网格分页、键盘事件、拖放领域事务、文件监听、热键释放和窗口生命周期的既有成功语义。
- P1-7 固定为 `discoveryRoots` 配置顺序优先：相同 bundle ID 保留第一个成功解析的应用。
- P2-1 删除未接入生产的搜索结果缓存；生产继续在后台队列执行无缓存搜索，并保留请求代次守卫。
- 全程 TDD：先运行新增测试并确认因目标缺陷失败，再实施最小修复并确认测试通过。
- 新测试使用 Swift Testing；禁止固定 sleep、RunLoop 轮询、真实用户数据库和真实 Dock/登录项修改。
- 所有 SQLite 初始化错误必须向调用方传播；打开后的数据库在初始化任一步骤失败时必须关闭。
- Schema v1 到 v2 的迁移必须幂等、事务化；旧图标缓存元数据缺失时按 stale 处理，不得猜测有效。
- AppKit 对象只在 MainActor 创建、读取和更新；后台边界只传递 `Sendable` 值或受控服务引用。
- 不用 `@unchecked Sendable`、`nonisolated(unsafe)`、关闭诊断或降低 Swift 严格并发级别来消除新 warning；既有 `@unchecked Sendable` 只能在锁或串行队列契约仍成立时保留。
- 发布脚本不得内置证书名称、Apple ID、Team ID、密码或 keychain profile；全部由环境变量或 Keychain profile 注入。
- `scripts/build-app.sh` 保持无凭据本地构建入口；签名、公证和 Gatekeeper 验证由独立 `scripts/release-app.sh` 承担。
- 所有脚本从自身路径解析仓库根目录，使用 `swift build --show-bin-path` 和 `xcrun --find` 解析工具/产物，不硬编码用户目录、架构 triple 或 Xcode 安装路径。
- 每个任务只修改列出的文件。发现超出本计划的新行为问题时停止该任务并单独评审，不顺手扩展范围。
- 每个任务结束后运行 focused tests；每个阶段结束后运行全量 `swift test`；最终必须运行全新 scratch path 的权威发布门禁。

## Closure Matrix

| 审查项 | 关闭任务 | 验收证据 |
|---|---|---|
| P0-5 首次扫描刷新部分修复 | Task 4 | 扫描后台执行、成功后 MainActor reload、失败不 reload |
| P0-6 发布门禁失败 | Task 1 | 三轮 parser 均接受 suite 事件且 execution set 一致 |
| P1-6 Schema 吞错 | Task 3 | execute/prepare/bind/step/PRAGMA 错误全部抛出且关闭连接 |
| P1-7 bundle ID 优先级未命名 | Task 2 | 根目录顺序 first-wins 契约和反向顺序测试 |
| P1-10 初始化失败不退出 | Task 3 | `appTerminator` 精确调用一次且后续 setup 不执行 |
| P1-11 无签名、公证链 | Task 10 | codesign、notary、staple、spctl 四层验证通过 |
| P1-12 测试失败被覆盖率脚本吞掉 | Task 9 | fake failing test runner 使所有兼容入口非零退出 |
| P1-13 覆盖工具失败误报 100% | Task 9 | fake llvm failure 非零退出且不输出成功结论 |
| P2-1 搜索缓存死链 | Task 5 | 生产与测试均只保留无缓存 `search` |
| P2-5 图标缓存校验无效 | Task 6 | 相同尺寸不同内容且修改时间不同必定刷新 |
| P2-6 主线程扫描/数据库/编码 I/O | Tasks 3、4、7 | I/O worker 断言非主线程，UI 更新断言 MainActor |
| P2-12 PageControl 无障碍断链 | Task 8 | value、increment、decrement、press 边界完整 |
| P2-13 Release warning | Task 11 | 全新 Release build 使用 warnings-as-errors 并通过 |
| P2-14 依赖倒置不完整 | Tasks 5、7 | Controller 依赖窄协议，Grid 不再持有 storage |
| P2-15 弱测试 | Task 11 | 恒真断言替换，测试 target warnings-as-errors 通过 |
| P2-16 脚本不可移植 | Tasks 9、10 | 路径/toolchain/架构均动态发现 |

## File Responsibility Map

### New files

- `scripts/parse-test-events.swift`：Swift Testing event stream 的唯一 parser。
- `scripts/tests/test-event-parser.sh`：suite/function/case/malformed event 契约测试。
- `Sources/LaunchPad/Services/AppBootstrapper.swift`：后台数据库 open/schema/recovery 和 MainActor 结果交付边界。
- `Tests/LaunchPadTests/Services/AppBootstrapperTests.swift`：启动成功、恢复、失败关闭及线程测试。
- `Sources/LaunchPad/Services/AppScanCoordinator.swift`：串行后台扫描与批写入边界。
- `Tests/LaunchPadTests/Services/AppScanCoordinatorTests.swift`：扫描线程、序列化、结果分支测试。
- `Sources/LaunchPadProtocols/Models/PersistedLayoutSnapshot.swift`：跨层只读、`Sendable` 的完整布局快照。
- `Sources/LaunchPad/Services/LayoutRepository.swift`：后台布局读取和写命令边界。
- `Tests/LaunchPadTests/Services/LayoutRepositoryTests.swift`：异步仓储成功、失败和串行顺序测试。
- `Sources/LaunchPadProtocols/Models/CachedImageRecord.swift`：图标数据及源修改时间。
- `Sources/LaunchPad/Services/IconRasterEncoder.swift`：从不可变 raster `Data` 在后台生成 1x/2x PNG，不调用 AppKit。
- `Tests/LaunchPadTests/Services/IconRasterEncoderTests.swift`：尺寸、像素内容、损坏输入和线程契约测试。
- `scripts/coverage.sh`：唯一覆盖率实现。
- `scripts/tests/test-coverage-contract.sh`：覆盖率失败传播和工具发现契约测试。
- `scripts/release-app.sh`：Developer ID 签名、公证、staple、Gatekeeper 发布入口。
- `scripts/tests/test-release-app-contract.sh`：无凭据和各验证步骤失败的脚本契约测试。

### Modified files

- `scripts/test-release.sh`：调用仓库内 parser，增加 warnings-as-errors。
- `Sources/LaunchPad/Services/AppScanner.swift`：明确 first-wins 契约。
- `Tests/LaunchPadTests/Services/AppScannerTests.swift`：正反根顺序和根内顺序测试。
- `Sources/LaunchPad/Storage/Schema.swift`：throwing setup、版本写入检查和 v2 迁移。
- `Sources/LaunchPad/Storage/StorageManager.swift`：检查 PRAGMA/schema、失败关闭、完整布局快照、图标元数据。
- `Sources/LaunchPadProtocols/Protocols.swift`：窄化 `LayoutReading`、`LayoutRepositoryProtocol`、`ImageStoring` 数据契约。
- `Tests/LaunchPadTests/Storage/SchemaTests.swift`、`StorageManagerTests.swift`：初始化失败和迁移测试。
- `Sources/LaunchPad/App/AppDelegate.swift`：后台扫描协调、失败退出和 Sendable runner。
- `Tests/LaunchPadTests/App/AppDelegateTests.swift`：启动、扫描及 MainActor 回填测试。
- `Sources/LaunchPad/Services/SearchEngine.swift`：删除 LRU、generation 和 cached API。
- `Tests/LaunchPadTests/Services/SearchEngineTests.swift`、`SearchDebounceTests.swift`、`Performance/PerformanceTests.swift`：删除缓存语义，保留搜索正确性和性能基线。
- `Sources/LaunchPad/Services/IconCache.swift`：基于持久化修改时间校验，不再比较尺寸/位深。
- `Tests/LaunchPadTests/Services/IconCacheTests.swift`：像素内容、元数据缺失和编码失败测试。
- `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`：异步布局仓储、窄依赖和 stale result 守卫。
- `Sources/LaunchPad/Controllers/FolderController.swift`：删除；其唯一重命名写职责迁入异步 LayoutRepository。
- `Sources/LaunchPad/Views/AppGridCollectionView.swift`：删除 storage 依赖，异步图标稳定 ID 回填。
- `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`、`Views/AppGridCollectionViewTests.swift`：异步读取/写入和 cell reuse 测试。
- `Sources/LaunchPad/Views/PageControl.swift`、`Tests/LaunchPadTests/Views/ViewLayerTests.swift`：完整分页无障碍动作。
- `Sources/LaunchPad/App/LaunchPadWindowController.swift`、`Sources/LaunchPad/Views/EmptyStateView.swift`、`FolderOverlayView.swift`、`PageScrollView.swift`、`SearchBar.swift`：warning 收敛。
- `Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift`：替换恒真断言。
- `scripts/coverage_measure.sh`、`scripts/final_measure.sh`、`scripts/measure_coverage.py`：兼容入口转发到权威覆盖率脚本。
- `scripts/build-app.sh`：稳定 bundle 组装和输出路径参数，不执行凭据操作。
- `Resources/LaunchPad.entitlements`：只读复核现有 Apple Events 权限；本计划不新增权限。

---

## Phase A: Restore The Authoritative Gate

### Task 1: Make the Swift Testing event parser suite-aware

**Issues:** P0-6

**Files:**
- Create: `scripts/parse-test-events.swift`
- Create: `scripts/tests/test-event-parser.sh`
- Modify: `scripts/test-release.sh`

**Interfaces:**
- Consumes: Swift Testing event stream version 0 NDJSON。
- Produces: `executed.list`、`event-version.txt`、`event-identity.txt`；suite lifecycle 事件不进入 function identity 集合。

- [ ] **Step 1: 创建失败契约测试**

测试脚本生成包含以下顺序的最小 event stream：suite `testStarted`、function record、function `testStarted`、function pass `testEnded`、suite `testEnded`。断言当前 parser 对 suite ID 报错，修复后只输出 function ID。再加入 malformed version、重复 function、case 缺少 `_testCase.id` 三个非零退出用例。

```zsh
zsh scripts/tests/test-event-parser.sh
```

Expected before fix: suite lifecycle 用例失败并出现 `invalid event schema`。

- [ ] **Step 2: 抽取唯一 parser 并区分 suite/function/case**

实现规则必须是显式分支，而不是放宽所有 ID：

```swift
func functionTestID(payload: [String: Any], line: Int) throws -> String? {
    guard let testID = payload["testID"] as? String, !testID.isEmpty else {
        throw ParserError.invalidEvent(line)
    }
    guard testID.contains("/") else { return nil }
    return testID
}

case "testStarted":
    if let testID = try functionTestID(payload: payload, line: index + 1) {
        try insertUnique(testID, into: &functionStarts)
    }
case "testEnded":
    guard let testID = try functionTestID(payload: payload, line: index + 1) else {
        continue
    }
    guard let messages = payload["messages"] as? [[String: Any]],
          messages.contains(where: { $0["symbol"] as? String == "pass" }) else {
        continue
    }
    try insertUnique(testID, into: &functionEnds)
```

`testCaseStarted`/`testCaseEnded` 仍必须使用包含 `/` 的 function test ID，不允许把 malformed case 当 suite 忽略。

- [ ] **Step 3: 让发布门禁直接调用仓库 parser**

删除 `test-release.sh` 内生成 `$ARTIFACT_DIR/event-parser.swift` 的 heredoc，改为：

```zsh
readonly EVENT_PARSER="$ROOT_DIR/scripts/parse-test-events.swift"
[[ -f "$EVENT_PARSER" ]] || {
  print -u2 "release gate: missing event parser: $EVENT_PARSER"
  exit 1
}
```

- [ ] **Step 4: 验证 parser 和正式门禁**

```zsh
zsh scripts/tests/test-event-parser.sh
LAUNCHPAD_RELEASE_ARTIFACT_DIR=/tmp/launchpad-gate-task1 zsh scripts/test-release.sh
```

Expected: parser 契约全部通过；正式门禁完成三轮测试和 Release build，`result.status` 为 `passed`。若后续任务前仍因 warning policy 失败，event parser 和三轮 execution artifacts 必须已完成且一致。

- [ ] **Step 5: Commit**

```bash
git add scripts/parse-test-events.swift scripts/tests/test-event-parser.sh scripts/test-release.sh
git commit -m "fix: accept suite lifecycle events in release gate"
```

### Task 2: Formalize duplicate bundle precedence

**Issues:** P1-7

**Files:**
- Modify: `Sources/LaunchPad/Services/AppScanner.swift`
- Modify: `Tests/LaunchPadTests/Services/AppScannerTests.swift`

**Interfaces:**
- Consumes: 有序 `[AppDiscoveryRoot]` 和每个 root 的稳定枚举结果。
- Produces: bundle ID 唯一、保持首次出现顺序的 `[ScannedApp]`。

- [ ] **Step 1: 增加反向根顺序 RED 测试**

同一 bundle ID 分别映射到 `/Applications/A.app` 与 `~/Applications/A.app`；传入 `[systemRoot, userRoot]` 时保留 system，反向传入时保留 user。另测同一根内第一次枚举结果获胜。

```bash
swift test --filter AppScannerTests
```

Expected: 若测试要求尚未被明确编码，至少一条契约断言失败。

- [ ] **Step 2: 用命名方法表达已确认规则**

```swift
/// Deduplicates by bundle ID. Earlier discovery roots and earlier entries
/// within a root have higher precedence.
private func deduplicatedInDiscoveryOrder(_ apps: [ScannedApp]) -> [ScannedApp] {
    var seenBundleIDs = Set<String>()
    return apps.filter { seenBundleIDs.insert($0.bundleId).inserted }
}
```

调用点只替换方法名，不排序 roots、不按路径重排。

- [ ] **Step 3: 验证并提交**

```bash
swift test --filter AppScannerTests
git add Sources/LaunchPad/Services/AppScanner.swift Tests/LaunchPadTests/Services/AppScannerTests.swift
git commit -m "test: define app discovery duplicate precedence"
```

## Phase B: Make Startup And Storage Fail Closed

### Task 3: Propagate schema failures and terminate failed startup

**Issues:** P1-6、P1-10、P2-6 的数据库初始化分支

**Files:**
- Create: `Sources/LaunchPad/Services/AppBootstrapper.swift`
- Create: `Tests/LaunchPadTests/Services/AppBootstrapperTests.swift`
- Modify: `Sources/LaunchPad/Storage/Schema.swift`
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift`
- Modify: `Tests/LaunchPadTests/Storage/SchemaTests.swift`
- Modify: `Tests/LaunchPadTests/Storage/StorageManagerTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Modify: schema setup call sites returned by `rg -n 'Schema.setupSchema|schemaSetup:' Sources Tests`

**Interfaces:**
- Produces: `Schema.setupSchema(db:) throws`；`schemaSetup: (OpaquePointer) throws -> Void`；`StorageError.schemaSetupFailed`；`AppBootstrapper.bootstrap(databasePath:completion:)`。

- [ ] **Step 1: 为所有失败分支写 RED 测试**

覆盖 `sqlite3_exec`、version check prepare、count step、insert prepare、bind 和 insert step。StorageManager 注入 throwing setup 后必须抛出 `.schemaSetupFailed`。AppBootstrapper 测试成功、删除后恢复成功、恢复失败三个分支，并断言 factory/remover 均不在主线程执行、completion 在 MainActor。AppDelegate 最终失败时 `appTerminator` 精确调用一次，且 controller/menu/hotkey/watcher setup 均不执行。

```bash
swift test --filter SchemaTests
swift test --filter StorageManagerTests
swift test --filter AppBootstrapperTests
swift test --filter AppDelegateTests
```

- [ ] **Step 2: 将 schema 初始化改成 fail-fast**

```swift
enum SchemaError: Error, Equatable {
    case executeFailed(index: Int, code: Int32)
    case versionCheckPrepareFailed(Int32)
    case versionCheckStepFailed(Int32)
    case versionInsertPrepareFailed(Int32)
    case versionBindFailed(Int32)
    case versionInsertStepFailed(Int32)
}

public static func setupSchema(db: OpaquePointer) throws {
    try setupSchema(db: db, statements: defaultStatements)
}
```

每个 SQLite 返回码在原调用点立即检查并抛出；错误日志由最外层启动边界记录一次，Schema 层不再“记录后继续”。

- [ ] **Step 3: 让 StorageManager 初始化具备单一清理路径**

```swift
internal init(
    dbPath: String,
    schemaSetup: (OpaquePointer) throws -> Void,
    faultInjector: SQLiteDriver.FaultInjector? = nil
) throws
```

检查 `journal_mode`、`foreign_keys` 和 `schemaSetup`。任一步失败时执行 `sqlite3_close_v2`、清空 `self.db` 并抛出具体 `StorageError`；不得返回可用对象。

- [ ] **Step 4: 数据库不可用时退出进程**

将数据库 path、factory、corruption handler 和 remover 交给后台 bootstrapper；成功后回到 MainActor 执行 `installStorage`、创建 IconCache/AppScanner/HotkeyManager，再依次 setup controllers/menu/hotkey/scan/watcher。失败 completion 使用：

```swift
case .failure:
    NSLog("[AppDelegate] Fatal: could not initialize database, aborting launch")
    appTerminator()
}
```

AppBootstrapper 的完成类型只携带成功创建的 `StorageManager` 或稳定错误类别，不跨线程传递 SQLite handle。测试同时断言 application callback 本身立即返回、退出后 `setupControllers`、`setupMenuBar`、`setupHotkey` 和 `setupFileWatcher` 的可观察副作用均为零。

- [ ] **Step 5: 验证并提交**

```bash
swift test --filter SchemaTests
swift test --filter StorageManagerTests
swift test --filter AppBootstrapperTests
swift test --filter AppDelegateTests
git add Sources/LaunchPad/Storage/Schema.swift Sources/LaunchPad/Storage/StorageManager.swift Sources/LaunchPad/Services/AppBootstrapper.swift Sources/LaunchPad/App/AppDelegate.swift Tests/LaunchPadTests
git commit -m "fix: fail startup on schema initialization errors"
```

### Task 4: Move scanning behind a serialized Sendable worker

**Issues:** P0-5、P2-6、P2-13 的 actor warning

**Files:**
- Create: `Sources/LaunchPad/Services/AppScanCoordinator.swift`
- Create: `Tests/LaunchPadTests/Services/AppScanCoordinatorTests.swift`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`

**Interfaces:**
- Consumes: `any AppScanning`、`any ScanBatchWriting`、roots、预先在 MainActor 计算的 page capacity。
- Produces: `@MainActor @Sendable (ScanOutcome) -> Void`；扫描请求在单一串行 queue 上执行。

- [ ] **Step 1: 写扫描的五分支 RED 测试**

覆盖 complete success、incomplete discovery、writer throw、unsuccessful result、连续两次请求。记录 scanner/writer 是否在主线程以及 completion 是否在主线程；只允许 success 触发 reload。

```bash
swift test --filter AppScanCoordinatorTests
swift test --filter AppDelegateTests
```

- [ ] **Step 2: 创建不持有 AppDelegate 的协调器**

```swift
enum ScanOutcome: Sendable, Equatable {
    case success
    case discoveryIncomplete
    case writeFailed
}

final class AppScanCoordinator: Sendable {
    private let queue = DispatchQueue(label: "com.launchpad.scan", qos: .userInitiated)
    private let scanner: any AppScanning
    private let writer: any ScanBatchWriting

    func scan(
        roots: [AppDiscoveryRoot],
        pageCapacity: Int,
        completion: @escaping @MainActor @Sendable (ScanOutcome) -> Void
    )
}
```

该类型只持有不可变的 `DispatchQueue` 和两个 `Sendable` 协议依赖，让编译器验证 `Sendable`；不得新增 `@unchecked Sendable`。串行 queue 只负责请求顺序，不承担 actor 隔离绕过。

- [ ] **Step 3: AppDelegate 只负责 MainActor 输入和结果回填**

在 MainActor 读取 `targetWindowContentSizeProvider()` 并计算 capacity，然后调用 coordinator。删除 `DispatchQueue.global` 直接捕获 `self`、`scanLock` 和 actor 隔离的 `performScan()`。成功 completion 调用 `reloadLoadedViewControllerAfterScan()`；失败只记录现有稳定错误类别。

- [ ] **Step 4: 验证异步行为和回归**

```bash
swift test --filter AppScanCoordinatorTests
swift test --filter AppDelegateTests
swift build -c release --product LaunchPadApp
```

Expected: 首次和增量扫描均不阻塞 MainActor；构建日志不再包含 `performInitialScan` 的 `ActorIsolatedCall`；其余 warning 由 Task 11 统一收敛，原 P0-5 成功刷新测试继续通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchPad/Services/AppScanCoordinator.swift Sources/LaunchPad/App/AppDelegate.swift Tests/LaunchPadTests/Services/AppScanCoordinatorTests.swift Tests/LaunchPadTests/App/AppDelegateTests.swift
git commit -m "fix: isolate app scanning from the main actor"
```

## Phase C: Remove Stale State And Main-Thread I/O

### Task 5: Remove the unused search result cache

**Issues:** P2-1、P2-14 的具体 SearchEngine 依赖

**Files:**
- Modify: `Sources/LaunchPad/Services/SearchEngine.swift`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`
- Modify: `Tests/LaunchPadTests/Services/SearchEngineTests.swift`
- Modify: `Tests/LaunchPadTests/Services/SearchDebounceTests.swift`
- Modify: `Tests/LaunchPadTests/Performance/PerformanceTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`

**Interfaces:**
- Produces: 无状态 `SearchEngine.search(items:query:)`；Controller 通过既有 `SearchRunner` 注入生产和测试搜索。

- [ ] **Step 1: 固定当前生产语义**

增加测试证明两次相同 query、不同数据集返回各自结果，并证明旧请求 completion 仍被 `searchRequestGeneration` 拒绝。

```bash
swift test --filter SearchEngineTests
swift test --filter LaunchPadViewControllerTests
```

- [ ] **Step 2: 删除死缓存接口**

从 `SearchEngine.swift` 删除 `LRUCache`、`MatchCounter`、`cache`、`generation`、`invalidateCache()` 和 `cachedSearch()`。将测试辅助方法改成：

```swift
func executeSearch(items: [PageItem], query: String) -> [PageItem] {
    SearchEngine().search(items: items, query: query)
}
```

随后移除 Controller 的 `private let searchEngine`，让生产搜索只由 `SearchRunner` 承担；默认 runner 内创建无状态 `SearchEngine`。

- [ ] **Step 3: 将性能测试改为真实生产路径**

性能基线测量 `search(items:query:)`，不得继续测已经删除的缓存命中。保留固定数据量和既有墙钟阈值，不放宽阈值。

- [ ] **Step 4: 验证并提交**

```bash
swift test --filter SearchEngineTests
swift test --filter SearchDebounceTests
swift test --filter PerformanceTests
swift test --filter LaunchPadViewControllerTests
git add Sources/LaunchPad/Services/SearchEngine.swift Sources/LaunchPad/Controllers/LaunchPadViewController.swift Tests/LaunchPadTests
git commit -m "refactor: remove unused search result cache"
```

### Task 6: Persist icon source metadata and validate disk cache correctly

**Issues:** P2-5、P1-6 的迁移可靠性

**Files:**
- Create: `Sources/LaunchPadProtocols/Models/CachedImageRecord.swift`
- Modify: `Sources/LaunchPadProtocols/Protocols.swift`
- Modify: `Sources/LaunchPad/Storage/Schema.swift`
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift`
- Modify: `Sources/LaunchPad/Services/IconCache.swift`
- Modify: `Tests/LaunchPadTests/Storage/SchemaTests.swift`
- Modify: `Tests/LaunchPadTests/Storage/StorageManagerTests.swift`
- Modify: `Tests/LaunchPadTests/Services/IconCacheTests.swift`
- Modify: image store mocks returned by `rg -l 'ImageStoring|MockImageStore' Tests`

**Interfaces:**
- Produces:

```swift
public struct CachedImageRecord: Sendable, Equatable {
    public let icon1x: Data
    public let icon2x: Data
    public let sourceModificationDate: Date
}

public protocol ImageStoring: Sendable {
    func saveImage(itemId: Int64, record: CachedImageRecord) throws
    func fetchImage(itemId: Int64) throws -> CachedImageRecord?
}
```

- [ ] **Step 1: 写同尺寸不同内容 RED 测试**

构造红色和蓝色两个 128x128、8-bit 图标。磁盘存红色及旧修改时间，provider 返回蓝色及新修改时间；断言结果像素为蓝色、磁盘记录被更新。另测相同修改时间命中、旧 v1 行元数据为 NULL 时刷新、provider 无修改时间时不持久化。

```bash
swift test --filter IconCacheTests
```

- [ ] **Step 2: 实施 schema v2 迁移**

将 `Schema.currentVersion` 提升为 2，在事务中执行：

```sql
ALTER TABLE image_cache ADD COLUMN source_modified_at REAL;
UPDATE schema_version SET version = 2;
```

只有 v1 执行 ALTER；v2 重复 setup 不重复迁移；未知更高版本必须抛错。ALTER 或版本更新失败必须 rollback，测试重新打开后仍为 v1 且旧表可读。

- [ ] **Step 3: 删除尺寸/位深启发式**

磁盘记录仅在 `record.sourceModificationDate == currentModificationDate` 时有效。当前修改时间缺失、记录元数据缺失、解码失败、读取失败均进入实时提取；保存失败仍返回实时图标，但记录稳定错误类别，不影响 UI。

- [ ] **Step 4: 验证迁移和缓存**

```bash
swift test --filter SchemaTests
swift test --filter StorageManagerTests
swift test --filter IconCacheTests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchPadProtocols Sources/LaunchPad/Storage Sources/LaunchPad/Services/IconCache.swift Tests/LaunchPadTests
git commit -m "fix: validate disk icons with persisted source metadata"
```

### Task 7: Move layout and icon disk work off MainActor

**Issues:** P2-6、P2-14

**Files:**
- Create: `Sources/LaunchPadProtocols/Models/PersistedLayoutSnapshot.swift`
- Create: `Sources/LaunchPad/Services/LayoutRepository.swift`
- Create: `Tests/LaunchPadTests/Services/LayoutRepositoryTests.swift`
- Create: `Sources/LaunchPad/Services/IconRasterEncoder.swift`
- Create: `Tests/LaunchPadTests/Services/IconRasterEncoderTests.swift`
- Modify: `Sources/LaunchPadProtocols/Protocols.swift`
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift`
- Modify: `Sources/LaunchPad/Services/LayoutPersistence.swift`
- Modify: `Sources/LaunchPad/Services/IconCache.swift`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`
- Delete: `Sources/LaunchPad/Controllers/FolderController.swift`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift`
- Modify: `Sources/LaunchPad/Views/AppIconCell.swift`
- Modify: `Sources/LaunchPad/Views/FolderCell.swift`
- Modify: focused controller/grid/icon/storage tests
- Delete: `Tests/LaunchPadTests/Controllers/FolderControllerTests.swift`

**Interfaces:**
- Produces:

```swift
public protocol LayoutReading: Sendable {
    func persistedLayoutSnapshot() throws -> PersistedLayoutSnapshot
}

protocol LayoutRepositoryProtocol: Sendable {
    func load() async throws -> PersistedLayoutSnapshot
    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) async throws
    func renameFolder(_ item: PageItem, newTitle: String) async throws
}
```

`PersistedLayoutSnapshot` 暴露只读 `pages`、`pageChildren`、`folderChildren`；StorageManager 用一次 JOIN 查询产生完整快照。

- [ ] **Step 1: 写后台 I/O 和 stale-result RED 测试**

记录 layout read/write、image fetch/save/png encode 的 `Thread.isMainThread`；期望均为 false。连续两次 load，后发请求先完成时只应用最新 generation。cell 被 reuse 后旧图标 completion 不得覆盖新 item。

```bash
swift test --filter LayoutRepositoryTests
swift test --filter LaunchPadViewControllerTests
swift test --filter AppGridCollectionViewTests
swift test --filter IconCacheTests
```

- [ ] **Step 2: 用 actor 串行布局仓储操作**

```swift
actor LayoutRepository: LayoutRepositoryProtocol {
    private let reader: any LayoutReading
    private let mutator: any LayoutMutating
    private let writer: any ItemWriting

    func load() async throws -> PersistedLayoutSnapshot {
        try reader.persistedLayoutSnapshot()
    }

    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) async throws {
        try mutator.apply(intent, pageCapacity: pageCapacity)
    }

    func renameFolder(_ item: PageItem, newTitle: String) async throws {
        var group = item.group ?? GroupInfo(id: item.id, title: newTitle)
        group.title = newTitle
        try writer.updateItem(PageItem(
            id: item.id,
            uuid: item.uuid,
            type: item.type,
            ordering: item.ordering,
            parentId: item.parentId,
            app: item.app,
            group: group
        ))
    }
}
```

Controller 用 `Task` await 仓储，并只在 MainActor 应用 snapshot。拖放、删除和重命名执行期间关闭重复提交；成功或失败后都读取权威 snapshot，保持 P0-4 的“不乐观更新”契约。`FolderController` 的唯一同步写职责迁入 repository 后删除该类及其独立测试，重命名行为测试迁入 `LayoutRepositoryTests`。

- [ ] **Step 3: 删除 Grid 的 storage 与 N+1 查询**

`AppGridCollectionView.configure` 只接收 `IconCaching`；folder preview 数据由完整 snapshot 的 `folderChildren` 投影后随 reload 输入。`configureFolderCell` 只读取内存中的 preview descriptors，不调用 `fetchAllItems`。`openFolder` 和 folder drop 完成后的 overlay reload 同样读取 Controller 持有的最新 snapshot，不再同步查询 storage。

- [ ] **Step 4: 异步加载图标并防止 cell reuse 覆盖**

磁盘 fetch 和 PNG encode/save 在后台执行；`NSImage` 解码、provider 的 AppKit 提取、`tiffRepresentation` 快照和 cell 配置留在 MainActor。MainActor 只把不可变 TIFF `Data` 交给 `IconRasterEncoder`；encoder 使用 CoreGraphics/ImageIO 解码、缩放和生成 128x128/256x256 PNG，不调用 `NSImage`、`lockFocus` 或其他 AppKit API。`IconCaching` 改为 MainActor 请求接口：

```swift
@MainActor
public protocol IconCaching: AnyObject {
    @discardableResult
    func loadIcon(
        forItemId itemId: Int64,
        path: String,
        completion: @escaping @MainActor @Sendable (Int64, NSImage) -> Void
    ) -> Task<Void, Never>
}
```

每个请求携带 item ID，completion 前验证 cell 当前 represented item ID。`prepareForReuse()` 取消旧 task；任务取消后不得配置 cell 或写入磁盘。

- [ ] **Step 5: 窄化 Controller 依赖**

Controller init 改为接收 `any LayoutRepositoryProtocol` 和 `any IconCaching`；AppDelegate 作为 composition root 创建具体实现。`DragController` 和 `KeyboardNavigator` 属于纯 UI 行为状态对象，维持具体类型，不为了测试制造无行为 mock 协议；`FolderController` 因同步存储职责已被 repository 取代而删除。

- [ ] **Step 6: 验证并提交**

```bash
swift test --filter LayoutRepositoryTests
swift test --filter LaunchPadViewControllerTests
swift test --filter AppGridCollectionViewTests
swift test --filter IconCacheTests
swift test --filter IconRasterEncoderTests
swift test --filter IntegrationTests
git add Sources/LaunchPadProtocols Sources/LaunchPad/Services Sources/LaunchPad/Storage/StorageManager.swift Sources/LaunchPad/Controllers/LaunchPadViewController.swift Sources/LaunchPad/Views Tests/LaunchPadTests
git commit -m "refactor: move layout and icon io off the main actor"
```

### Task 8: Complete PageControl accessibility

**Issues:** P2-12

**Files:**
- Modify: `Sources/LaunchPad/Views/PageControl.swift`
- Modify: `Tests/LaunchPadTests/Views/ViewLayerTests.swift`

**Interfaces:**
- Produces: 1-based accessibility value、`.incrementor` role、increment/decrement/press actions；视觉和鼠标回调继续使用 0-based index。

- [ ] **Step 1: 写边界 RED 测试**

测试 `Page 2 of 4`、increment 到 3、decrement 到 1、第一页不能再减、末页不能再增、0/1 page 时动作返回 false、press 触发当前选择且回调一次。

```bash
swift test --filter ViewLayerTests
```

- [ ] **Step 2: 实施可访问动作**

```swift
override public func accessibilityRole() -> NSAccessibility.Role? { .incrementor }

override public func accessibilityValue() -> Any? {
    "Page \(viewModel.currentPage + 1) of \(viewModel.totalPages)"
}

override public func accessibilityPerformIncrement() -> Bool {
    selectAccessiblePage(viewModel.currentPage + 1)
}

override public func accessibilityPerformDecrement() -> Bool {
    selectAccessiblePage(viewModel.currentPage - 1)
}
```

`selectAccessiblePage` 必须复用 `viewModel.selectDot`、调用 `onDotSelected`、`update()` 和 `NSAccessibility.post(element: self, notification: .valueChanged)`，越界时不改变状态且返回 false。另实现 `accessibilityPerformPress()`：有页面时对当前页调用同一选择路径，无页面时返回 false。

- [ ] **Step 3: 验证并提交**

```bash
swift test --filter ViewLayerTests
git add Sources/LaunchPad/Views/PageControl.swift Tests/LaunchPadTests/Views/ViewLayerTests.swift
git commit -m "fix: expose page control accessibility actions"
```

## Phase D: Make Delivery Evidence Trustworthy

### Task 9: Consolidate portable fail-fast coverage tooling

**Issues:** P1-12、P1-13、P2-16

**Files:**
- Create: `scripts/coverage.sh`
- Create: `scripts/tests/test-coverage-contract.sh`
- Modify: `scripts/coverage_measure.sh`
- Modify: `scripts/final_measure.sh`
- Modify: `scripts/measure_coverage.py`

**Interfaces:**
- Consumes: optional `LAUNCHPAD_COVERAGE_ARTIFACT_DIR`；测试可注入 `SWIFT_BIN`、`LLVM_PROFDATA_BIN`、`LLVM_COV_BIN`。
- Produces: 测试、profile merge、report 任一步失败即非零；仅全部成功后输出覆盖率结论。

- [ ] **Step 1: 用 fake tools 写失败传播 RED 测试**

依次让 fake swift test、test list、profdata merge、llvm-cov report/show 返回 1，断言脚本退出非零且输出中没有 `100%`。成功 fixture 断言只调用动态注入的工具路径。

```zsh
zsh scripts/tests/test-coverage-contract.sh
```

- [ ] **Step 2: 建立唯一实现并动态发现环境**

```zsh
#!/bin/zsh
set -euo pipefail
ROOT_DIR=${0:A:h:h}
SWIFT_BIN=${SWIFT_BIN:-$(command -v swift)}
LLVM_PROFDATA_BIN=${LLVM_PROFDATA_BIN:-$(xcrun --find llvm-profdata)}
LLVM_COV_BIN=${LLVM_COV_BIN:-$(xcrun --find llvm-cov)}
BIN_DIR=$($SWIFT_BIN build -c debug --show-bin-path)
TEST_BIN="$BIN_DIR/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests"
```

每个外部命令直接检查退出码；需要汇总 suite 失败时保存 `failed=1`，循环结束立即 `exit 1`，不得继续生成覆盖率成功结论。检查 profraw 数量、merged profile 非空和 report 输出包含 `TOTAL`。

- [ ] **Step 3: 保留旧入口兼容性**

两个 shell 文件仅 `exec "$SCRIPT_DIR/coverage.sh" "$@"`；Python 文件使用 `os.execv` 转发并透传退出码。禁止保留第二份测试发现、profile merge 或 zero-count 逻辑。

- [ ] **Step 4: 验证契约和真实覆盖率**

```zsh
zsh scripts/tests/test-coverage-contract.sh
LAUNCHPAD_COVERAGE_ARTIFACT_DIR=/tmp/launchpad-coverage-task9 zsh scripts/coverage.sh
```

Expected: 真实测试全绿才生成报告；工具或测试失败时退出非零。

- [ ] **Step 5: Commit**

```bash
git add scripts/coverage.sh scripts/coverage_measure.sh scripts/final_measure.sh scripts/measure_coverage.py scripts/tests/test-coverage-contract.sh
git commit -m "fix: make coverage reporting portable and fail-fast"
```

### Task 10: Add a credentialed Developer ID release pipeline

**Issues:** P1-11、P2-16

**Files:**
- Create: `scripts/release-app.sh`
- Create: `scripts/tests/test-release-app-contract.sh`
- Modify: `scripts/build-app.sh`
- Verify without modifying: `Resources/LaunchPad.entitlements`

**Interfaces:**
- Requires: `LAUNCHPAD_CODESIGN_IDENTITY`、`LAUNCHPAD_NOTARY_PROFILE`。
- Optional: `LAUNCHPAD_RELEASE_OUTPUT_DIR`；默认输出到仓库 `.build/release-artifacts`。
- Produces: 已签名、notarized、stapled 且通过 Gatekeeper 的 `LaunchPad.app` 和命令日志。

- [ ] **Step 1: 写无凭据和步骤失败 RED 测试**

fake `codesign`、`xcrun notarytool`、`xcrun stapler`、`spctl`，分别模拟每一步失败；断言脚本立即非零且不执行后续步骤。缺少两个必需变量时必须在构建前退出，并且不得打印变量值。

```zsh
zsh scripts/tests/test-release-app-contract.sh
```

- [ ] **Step 2: 保持本地组装与正式发布分离**

`build-app.sh` 只负责 `swift build -c release --product LaunchPadApp` 和 bundle 组装，使用自身路径解析 root，并接受显式输出目录。为脚本添加执行权限。不得在该入口隐式使用开发者证书。

- [ ] **Step 3: 实施严格发布顺序**

```zsh
codesign --force --strict --timestamp --options runtime \
  --sign "$LAUNCHPAD_CODESIGN_IDENTITY" \
  "$APP_BUNDLE/Contents/MacOS/LaunchPadApp"
codesign --force --strict --timestamp --options runtime \
  --entitlements "$ROOT_DIR/Resources/LaunchPad.entitlements" \
  --sign "$LAUNCHPAD_CODESIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
xcrun notarytool submit "$ARCHIVE" \
  --keychain-profile "$LAUNCHPAD_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
```

notary 只提交从已签名 app 生成的 zip；任何验证失败均保留 artifact/log 并退出非零。不要使用 `--no-strict`、ad-hoc identity 或跳过 Gatekeeper。

- [ ] **Step 4: 验证脚本契约与真实凭据链**

```zsh
zsh scripts/tests/test-release-app-contract.sh
: ${LAUNCHPAD_CODESIGN_IDENTITY:?configure Developer ID identity first}
: ${LAUNCHPAD_NOTARY_PROFILE:?configure notarytool Keychain profile first}
LAUNCHPAD_RELEASE_OUTPUT_DIR=/tmp/launchpad-release-task10 zsh scripts/release-app.sh
```

Expected: 第一条无凭据测试不访问 Keychain；第二条凭据化命令最终 `spctl` 输出 accepted。真实身份字符串和 profile 由发布负责人提供，不写入仓库。

- [ ] **Step 5: Commit**

```bash
git add scripts/build-app.sh scripts/release-app.sh scripts/tests/test-release-app-contract.sh
git commit -m "build: add signed and notarized release pipeline"
```

### Task 11: Eliminate production/test warnings and replace weak assertions

**Issues:** P2-13、P2-15

**Files:**
- Modify: `Sources/LaunchPad/App/AppDelegate.swift`
- Modify: `Sources/LaunchPad/App/LaunchPadWindowController.swift`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift`
- Modify: `Sources/LaunchPad/Views/EmptyStateView.swift`
- Modify: `Sources/LaunchPad/Views/FolderOverlayView.swift`
- Modify: `Sources/LaunchPad/Views/PageScrollView.swift`
- Modify: `Sources/LaunchPad/Views/SearchBar.swift`
- Modify: `Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift`
- Modify: `scripts/test-release.sh`

**Interfaces:**
- Produces: 所有跨 queue/动画 completion 明确为 `@MainActor @Sendable`；忽略返回值使用 `_ =`；生产和测试编译均 warnings-as-errors。

- [ ] **Step 1: 固定当前 12 条 Release warning 清单**

将以下位置作为基线：AppDelegate 78/194/354、LaunchPadWindowController 21/25、LaunchPadViewController 102、AppGridCollectionView 177/199、EmptyStateView 41、FolderOverlayView 267、PageScrollView 44、SearchBar 44。Task 4 已负责 194；本任务逐一消除其余项。

```bash
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
```

Expected before fix: 非零并输出当前 warning。

- [ ] **Step 2: 修正 closure 隔离和返回值**

统一 runner 类型，例如：

```swift
typealias MainActorAction = @MainActor @Sendable () -> Void
var mainAsyncRunner: (@escaping MainActorAction) -> Void = { action in
    DispatchQueue.main.async(execute: action)
}
```

动画 completion 和 scheduler 同样使用 `@MainActor @Sendable`。`alertRunner` 与 `processScrollPhase` 的有意忽略返回值分别写成 `_ = self.alertRunner(alert)` 和 `_ = processScrollPhase(event.phase, deltaX: event.scrollingDeltaX, event: event)`。不得用 warning suppression attribute。

- [ ] **Step 3: 替换两个已知恒真断言**

删除 `overlay != nil`，改为断言初始化后的 `isHidden`、page count 和 observer token 状态。对越界 data-source 用例，不再断言非 optional `cell != nil`，改为断言返回 fallback item 的 `representedObject == nil`，且 icon/storage/provider 调用计数为零。

- [ ] **Step 4: 把 warnings-as-errors 纳入门禁**

正式 Release build 增加 `-Xswiftc -warnings-as-errors`；测试编译至少执行一次 `swift test -Xswiftc -warnings-as-errors --no-parallel`。日志仍保留到 artifact 目录。

- [ ] **Step 5: 验证并提交**

```bash
swift test -Xswiftc -warnings-as-errors --no-parallel
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
git add Sources/LaunchPad Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift scripts/test-release.sh
git commit -m "fix: enforce warning-free production and test builds"
```

## Phase E: Final Regression And Release Evidence

### Task 12: Run complete regression and produce release evidence

**Issues:** 全部 16 项及 20 项不可回归基线

**Files:**
- Modify only when evidence is current and generated from commands: `docs/coverage-progress.md`
- Do not modify: `docs/2026-07-15-release-readiness-review.md`

**Interfaces:**
- Consumes: Tasks 1-11 的代码与脚本。
- Produces: 三个显式 artifact 目录，分别保存门禁、覆盖率和签名分发证据；每个目录都必须记录当前 commit SHA。

- [ ] **Step 1: 静态边界检查**

```bash
rg -n '/Users/|arm64-apple-macosx|/Applications/Xcode.app' scripts/*.sh scripts/*.py
rg -n 'set \+e' scripts/*.sh
rg -n 'cachedSearch|invalidateCache|scanLock' Sources Tests
rg -n 'try\? imageStore|try\? storage' Sources/LaunchPad/Services/IconCache.swift Sources/LaunchPad/Views/AppGridCollectionView.swift
rg -n 'private var storage: DataStoring' Sources/LaunchPad/Views/AppGridCollectionView.swift
```

Expected: 五条命令均无命中；契约测试 fixture 可以包含被禁止字符串，生产脚本和生产源码不允许命中。

- [ ] **Step 2: 全量测试和 warning gate**

```bash
swift test -Xswiftc -warnings-as-errors --no-parallel
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
```

Expected: 1092 个既有测试加本计划新增测试全部通过；实际数量以命令输出为准，零 failure、零 issue、零 warning。

- [ ] **Step 3: 全新目录运行权威发布门禁**

```zsh
LAUNCHPAD_RELEASE_ARTIFACT_DIR=/tmp/launchpad-release-readiness-final \
zsh scripts/test-release.sh
```

Expected: `result.status` 为 `passed`；三轮 discovered/executed identities 完全一致；Release build 成功且 log 无 warning。

- [ ] **Step 4: 运行覆盖率和凭据化发布链**

```zsh
LAUNCHPAD_COVERAGE_ARTIFACT_DIR=/tmp/launchpad-coverage-final \
zsh scripts/coverage.sh
```

```zsh
: ${LAUNCHPAD_CODESIGN_IDENTITY:?configure Developer ID identity first}
: ${LAUNCHPAD_NOTARY_PROFILE:?configure notarytool Keychain profile first}
LAUNCHPAD_RELEASE_OUTPUT_DIR=/tmp/launchpad-signed-final zsh scripts/release-app.sh
```

Expected: coverage 命令退出 0 且报告非空；发布链依次通过 codesign verify、notary accepted、stapler validate、spctl accepted。缺少真实凭据时本任务不能标记完成，也不能宣称 release-ready。

- [ ] **Step 5: 审阅 20 项不可回归基线**

逐项复核 P0-1～P0-4、P1-1～P1-5、P1-8、P1-9、P1-14、P2-2～P2-4、P2-7～P2-11 的生产入口和对应测试。不能只以总测试数代替行为检查。

- [ ] **Step 6: 更新证据文档并提交**

只写入实际命令产生的测试数、warning 数、artifact 路径、coverage 数值和签名验证结果，不预填成功值。

```bash
git add docs/coverage-progress.md
git commit -m "docs: record release readiness verification evidence"
```

## Execution Order And Stop Conditions

1. Task 1 必须先通过，否则后续完整门禁证据不可信。
2. Tasks 2-4 关闭发现、启动和存储基础可靠性；Phase B 全量测试失败时不得进入 schema v2。
3. Task 6 依赖 Task 3 的 throwing schema；Task 7 依赖 Task 6 的图标记录接口。
4. Task 5 与 Task 8 可在 Phase B 后独立实施，但合并前都必须重放 Controller/View tests。
5. Task 9、Task 10 不得共享实现：覆盖率不需要发布凭据，本地 build 不得隐式签名。
6. Task 11 必须在所有生产接口调整完成后执行，避免 warning 基线反复变化。
7. Task 12 的真实 notarization 需要发布负责人预先配置 Keychain profile；没有凭据属于未完成，不属于可跳过检查。
8. 任一 SQLite migration rollback、主线程 I/O、cell reuse stale icon、三轮 execution set 不一致或宿主状态副作用出现时，停止当前阶段，按 systematic-debugging 定位后重新从该阶段首个测试执行。

## Definition Of Done

- 16 个未闭环项均能映射到通过的行为测试或发布证据。
- 普通全量测试与 warnings-as-errors 全量测试均为零失败。
- 全新 scratch path 下 `scripts/test-release.sh` 三轮通过，parser 不再拒绝 suite lifecycle event。
- Release product 和 test target 均为零 warning。
- Schema 初始化任一失败都会关闭数据库并终止应用启动；v1 到 v2 迁移可回滚。
- 扫描、SQLite 读取/写入、图标磁盘访问及 PNG 编码不在 MainActor 执行。
- 搜索无死缓存，异步结果仍受 query + generation 守卫。
- PageControl 可由 VoiceOver 读取当前页并执行增减页动作。
- 覆盖率任一测试或工具失败均返回非零且不会输出虚假成功。
- 正式 app 通过 Developer ID、hardened runtime、notary、staple、codesign 和 Gatekeeper 验证。
- 脚本不包含用户绝对路径、固定架构 triple、固定 Xcode 路径或凭据。
- 20 个已修复项的生产入口与测试语义均未回归。
