# LaunchPad P0 Readiness Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task in the current `release-readiness` branch. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 P0-1 至 P0-6，并按已确认设计交付动态网格、完整原子拖放、真实键盘入口、首次扫描刷新和始终启用墙钟断言的可重复发布门禁。

**Architecture:** 保持 AppKit + Controller + Protocol + SQLite 分层。页面展示由稳定顶层全局顺序投影；`AppGridInteractionCoordinator` 作为主网格唯一 AppKit delegate，独占 selection 与 drag/drop 规则，`AppGridCollectionView` 只负责渲染、布局、cell、snapshot 和窄 host 查询；拖放通过 `LayoutDropIntent` 和单一 `LayoutMutating` 入口在 SQLite `BEGIN IMMEDIATE` 事务中提交；网格由真实 viewport 产生 `GridMetrics`；UI 只在 COMMIT 成功后 reload。测试目标渐进统一为 Swift Testing，系统边界通过窄注入隔离，Task 21 后完整 suite 必须零失败、零跳过、零 signal。

**Tech Stack:** Swift 6.0、Swift Testing、AppKit、SQLite3、Swift Package Manager、zsh。

**Design:** `docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md`、`docs/superpowers/specs/2026-07-21-swift-testing-unification-design.md`、`docs/superpowers/specs/2026-07-22-app-grid-interaction-coordinator-design.md`

## Global Constraints

- 平台保持 `macOS 14.0+`，Swift tools version 保持 `6.0`，不增加第三方依赖，不修改数据库 schema。
- 本计划的成功状态仅为 **P0 readiness gate 通过**，不是正式发布授权；禁止据此打发布 tag、生成分发包或宣称项目已满足上线条件。正式分发前必须另行关闭剩余 P1/P2，并完成 release warning、CI、Developer ID、hardened runtime、notarization、stapling、`codesign` 与 Gatekeeper 独立验证。
- 当前分支必须是 `release-readiness`；不得修改或恢复工作区中与本计划无关的用户变更。
- 全程 TDD：每个行为先增加最小失败测试并实际确认 RED，再写最小生产实现并确认 GREEN。
- 新测试只允许使用 Swift Testing。任何 Task 一旦修改仍含 XCTest 的测试文件，该文件必须在同一 Task 结束前完整迁移；禁止在同一文件中混用 `XCTest + Testing`。
- 纯测试框架迁移提交不得包含生产代码。既有失败修复、纯迁移和新行为 RED-GREEN 分别提交、分别审查，最后再审查 Task 的完整 `base..head`。
- 每个旧 XCTest 方法必须映射到一个明确的 Swift Testing suite/test；迁移不得删除期望、降低精度、把失败改为 skip，或依赖测试数量相等代替断言语义审查。
- AppKit suite 在 suite 级标注 `@MainActor`；外部状态使用测试局部 `defer` 清理；异步 callback 必须真正 await，禁止固定 sleep 和 RunLoop 轮询。
- 所有数据库测试使用 `:memory:` 或 `/tmp` 独立文件；禁止访问用户数据库。
- 禁止测试修改真实 Dock plist、登录项、辅助功能设置、全局热键或系统设置。
- 墙钟性能断言始终启用；禁止 `.enabled(if:)`、环境变量、重试、放宽阈值或 `--skip PerformanceTests`。
- 主网格禁止 `delegate === collectionView`、内部纯转发 proxy 和兼容门面；`onItemSelected`、网格上的 `onSelectionChanged`、`dragController`、`pasteboardUUIDReader` 必须在 Task 4 结束前删除，选择与拖放只由 `AppGridInteractionCoordinator` 拥有。
- `scripts/run-with-timeout.sh` 是唯一进程组 watchdog 实现；Task 22 的 `scripts/test-release.sh` 只能调用它，禁止内联第二份 supervisor 或绕过 watchdog 直接执行权威门禁。
- 拖放只允许一个写入口：`LaunchPadViewController -> LayoutMutating`。`FolderController` 仅保留重命名，不保留旧的多 CRUD 布局写路径。
- 页面空白落点必须转换为稳定 `ItemPlacement.afterItem(itemID:)`；禁止把 `visualPageIndex` 写入领域 intent。
- 文件夹禁止嵌套；新文件夹 children 保持原顶层相对顺序；0/1 child 文件夹按设计删除或解散。
- `StorageManager` 的读取、写入、事务和关闭统一使用单一串行 `databaseQueue`。
- 每个任务只提交任务列出的文件，不顺手清理无关 warning、历史计划或 P1/P2。
- 每个任务结束时整个 package 和 test target 必须可编译；`--filter` 只减少执行用例，不允许把尚未迁移的调用点留到后续任务。
- 每条 focused 命令必须匹配至少一个明确命名的 RED/GREEN 测试；零匹配退出 0 视为门禁失败。
- Task 3R 后全量测试必须完整退出并产生 Swift Testing summary；Task 21 后完整串行 suite 必须全绿、零 skip、零 signal，且 `Tests/**/*.swift` 的 XCTest 静态扫描为零。
- 当前失败台账只能单调减少，只用于执行追踪，不是发布白名单。出现未登记失败、缺失 summary 或新的宿主副作用时立即停止并按系统化调试重新定位根因。
- Task 3R 的已确认执行基线是 6 个既有 XCTest failure、2 个既有
  XCTest skip，以及 4 个既有 Swift Testing issue（来自 3 个测试）；
  允许全量命令因这些已登记项非零退出，但必须完整退出、同时产生
  XCTest 与 Swift Testing 的完整 summary、无 signal、无残留进程，且
  failure/skip/issue 集合只能保持或减少，不得新增。6 个 XCTest
  failure 是
  `AppGridCollectionViewTests.testAcceptDrop_onGroupTarget_returnsTrue`、
  `testAcceptDrop_reorderSamePage_performsReorder`、
  `testExtractDraggedItem_validPasteboard_returnsItem`、
  `FileWatcherTests.testStart_realFileChange_triggersOnChange`、
  `FolderOverlayViewTests.testMouseDown_outsidePanel_closesFolder`、
  `SearchBarTests.testSearchBar_hide_animated_completionHidesView`；2 个 skip 是
  `AppIconCellTests.testDidActivateNotification_showsRunningIndicator` 和
  `testDidDeactivateNotification_hidesRunningIndicator`。4 个 Swift Testing
  issue 是
  `LaunchPadWindowControllerTests.openingTransition_triggersShowWindowAnimated`
  的两个断言、
  `LaunchPadWindowControllerTests.launchAnimation_fadesWindowOut` 和
  `LaunchPadWindowControllerTests.showWindowAnimated_reduceMotion_usesReducedBranch`
  各一个断言。它们分别由 Tasks 3M、4、19、21 修复；Task 21 后不再
  允许任何 failure、skip 或 issue。
- 所有 SwiftPM 命令统一使用：

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel
```

## File Responsibility Map

### New production files

- `Sources/LaunchPadProtocols/Models/LayoutDropIntent.swift`：稳定 ID 拖放命令与 placement。
- `Sources/LaunchPad/Services/LayoutProjection.swift`：稳定全局顺序到视觉 sections 的纯投影。
- `Sources/LaunchPad/Services/ScanBatch.swift`：扫描批事务的窄接口、结果和错误类型。
- `Sources/LaunchPad/Storage/LayoutDomainState.swift`：领域校验、顺序变换和页面重建计划。
- `Sources/LaunchPad/Storage/SQLiteTransaction.swift`：检查 BEGIN/COMMIT/ROLLBACK 的唯一事务骨架。
- `Sources/LaunchPad/Models/DragSession.swift`：不可变拖拽会话。
- `Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift`：主网格 selection 与 drag/drop 的唯一 AppKit delegate、所有权和生命周期边界。
- `Sources/LaunchPad/Views/TransientMessageView.swift`：非阻塞、可访问的固定错误提示。
- `Sources/LaunchPad/Utilities/AccessibilityObservers.swift`：局部通知中心与 settings provider 驱动的可释放观察者。

### Modified production files

- `Sources/LaunchPad/Utilities/GridLayoutCalculator.swift`：真实 viewport、动态行数和完整 metrics。
- `Sources/LaunchPad/Views/AppGridFlowLayout.swift`：显式 row-major、一 section 一屏和真实 snap。
- `Sources/LaunchPad/Views/AppGridCollectionView.swift`：单一 metrics、稳定落点、零乐观写入，以及 coordinator 所需的窄渲染/快照 host；不再 self-delegate。
- `Sources/LaunchPad/Views/AppIconCell.swift`、`FolderCell.swift`：尺寸重配置、folder preview 和安全删除入口。
- `Sources/LaunchPad/Views/PageScrollView.swift`：显式 page width/count 和页码回调。
- `Sources/LaunchPad/Views/FolderOverlayView.swift`：实际 clip 容量分页、文件夹内重排和拖出。
- `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`：投影、唯一领域写入口、错误反馈。
- `Sources/LaunchPad/Controllers/DragController.swift`：纯拖拽状态、方向 timer 和 hover preview。
- `Sources/LaunchPad/Controllers/KeyboardNavigator.swift`：真实 search query 状态。
- `Sources/LaunchPad/Controllers/FolderController.swift`：移除非原子布局 CRUD，只保留 rename。
- `Sources/LaunchPad/App/HotkeyManager.swift`、`AppDelegate.swift`：真实 monitor 链、扫描刷新和安全系统边界。
- `Sources/LaunchPad/Services/AppScanner.swift`：可观察扫描写入结果与只读排除列表注入。
- `Sources/LaunchPad/Services/SearchDebouncer.swift`：scheduler action 显式回到 MainActor，禁止后台 `assumeIsolated`。
- `Sources/LaunchPad/Services/FileWatcher.swift`：显式 FSEvent 生命周期。
- `Sources/LaunchPad/Storage/StorageManager.swift`：单队列、事务和 `LayoutMutating`。
- `Sources/LaunchPadProtocols/Protocols.swift`：新增独立 `LayoutMutating` 协议。
- `scripts/run-with-timeout.sh`：Task 4 创建的唯一进程组 watchdog，可运行任意 argv 命令并完整清理子孙进程。
- `scripts/test-release.sh`：Task 22 创建的唯一对外发布测试入口，只编排并消费共享 watchdog。

### New test files

- `Tests/LaunchPadTests/Services/LayoutProjectionTests.swift`
- `Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift`
- `Tests/LaunchPadTests/Storage/LayoutDomainStateTests.swift`
- `Tests/LaunchPadTests/Storage/StorageManagerLayoutMutationTests.swift`
- `Tests/LaunchPadTests/Storage/StorageManagerScanBatchTests.swift`
- `Tests/LaunchPadTests/Views/TransientMessageViewTests.swift`
- `Tests/LaunchPadTests/Services/FileWatcherLifecycleTests.swift`
- `Tests/LaunchPadTests/Utilities/AccessibilityObserversTests.swift`

### Existing tests synchronized by this plan

- `Tests/LaunchPadTests/Utilities/GridLayoutCalculatorTests.swift`
- `Tests/LaunchPadTests/Utilities/AccessibilitySettingsTests.swift`
- `Tests/LaunchPadTests/Views/ViewLayerTests.swift`
- `Tests/LaunchPadTests/Views/PageScrollViewTests.swift`
- `Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift`
- `Tests/LaunchPadTests/Views/DiffableDataSourceTests.swift`
- `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- `Tests/LaunchPadTests/Views/AppIconCellTests.swift`
- `Tests/LaunchPadTests/Views/FolderCellTests.swift`
- `Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift`
- `Tests/LaunchPadTests/Views/FolderOverlayViewPagingTests.swift`
- `Tests/LaunchPadTests/Views/CollectionViewDragTests.swift`
- `Tests/LaunchPadTests/Services/SearchDebounceTests.swift`
- `Tests/LaunchPadTests/Models/ProtocolTests.swift`
- `Tests/LaunchPadTests/Controllers/KeyboardNavigatorTests.swift`
- `Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift`
- `Tests/LaunchPadTests/Controllers/DragControllerTests.swift`
- `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- `Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift`
- `Tests/LaunchPadTests/Controllers/FolderControllerTests.swift`
- `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- `Tests/LaunchPadTests/Services/AppScannerTests.swift`
- `Tests/LaunchPadTests/Services/FileWatcherTests.swift`
- `Tests/LaunchPadTests/Storage/StorageManagerTests.swift`
- `Tests/LaunchPadTests/Performance/PerformanceTests.swift`
- `Tests/LaunchPadTests/Integration/IntegrationTests.swift`
- `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift`

---

### Task 1: Add Height-aware Grid Metrics

**Files:**
- Modify: `Sources/LaunchPad/Utilities/GridLayoutCalculator.swift:4-55`
- Modify: `Tests/LaunchPadTests/Utilities/GridLayoutCalculatorTests.swift:5-102`

**Interfaces:**
- Consumes: actual clip viewport `CGSize`.
- Produces: `GridMetrics`, `GridInsets`, `calculate(viewportSize:)`.
- Consumed later by: Task 5 for view-only reprojection and Task 20 for first-scan target-display storage capacity.
- Preserves temporarily: existing `GridParameters` and `calculate(screenWidth:)` as an explicit compatibility API through Task 20; Tasks 3-5 must use `GridMetrics` for all grid rendering and resize paths.

- [x] **Step 1: Add RED tests for columns, row breakpoints, clamping and invalid input**

Append these tests while leaving old tests in place:

```swift
@Test("列边界 1440/1728 及 nextUp 精确")
func columnBreakpoints() {
    #expect(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 1440, height: 620)).columns == 7)
    #expect(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: CGFloat(1440).nextUp, height: 620)).columns == 9)
    #expect(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 1728, height: 620)).columns == 9)
    #expect(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: CGFloat(1728).nextUp, height: 620)).columns == 10)
}

@Test("每个最小高度边界精确选择 5 到 1 行")
func rowBreakpoints() {
    let cases: [(CGFloat, Int)] = [
        (620, 5), (496, 4), (372, 3), (248, 2), (124, 1),
    ]
    for (height, expectedRows) in cases {
        #expect(GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1440, height: height)).rows == expectedRows)
        if expectedRows > 1 {
            #expect(GridLayoutCalculator.calculate(
                viewportSize: CGSize(width: 1440, height: height.nextDown)).rows
                == expectedRows - 1)
        }
    }
}

@Test("900 768 600 整屏对应 viewport 得到 5 5 4 行")
func approvedScreenHeights() {
    #expect(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 1440, height: 798)).rows == 5)
    #expect(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 1366, height: 666)).rows == 5)
    #expect(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 1280, height: 498)).rows == 4)
}

@Test("异常 viewport 返回有限非负 metrics")
func invalidViewportIsSanitized() {
    let metrics = GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: .nan, height: .infinity))
    let values = [
        metrics.iconSize, metrics.itemSize.width, metrics.itemSize.height,
        metrics.horizontalSpacing, metrics.verticalSpacing,
        metrics.sectionInsets.top, metrics.sectionInsets.left,
        metrics.sectionInsets.bottom, metrics.sectionInsets.right,
        metrics.pageWidth,
    ]
    #expect(metrics.rows == 1)
    #expect(values.allSatisfy { $0.isFinite && $0 >= 0 })
}

@Test("item 尺寸不重复包含 spacing")
func itemSizeExcludesSpacing() {
    let metrics = GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 1440, height: 620))
    #expect(metrics.itemSize.width == metrics.iconSize)
    #expect(metrics.itemSize.height == metrics.iconSize + 40)
    #expect(metrics.verticalSpacing == 20)
    #expect(metrics.sectionInsets.top >= 10)
    #expect(metrics.sectionInsets.bottom >= 10)
}

@Test("图标尺寸明确夹紧到 64 和 96")
func iconSizeClampsToExactBounds() {
    let minimum = GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 1, height: 124)
    )
    let maximum = GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 2560, height: 1200)
    )

    #expect(minimum.iconSize == 64)
    #expect(maximum.iconSize == 96)
}
```

- [x] **Step 2: Run the new tests and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter GridLayoutCalculatorTests
```

Expected: compile failure because `GridMetrics` and `calculate(viewportSize:)` do not exist.

- [x] **Step 3: Add the exact metrics types and calculator**

Add above the existing compatibility types and method:

```swift
public struct GridInsets: Equatable, Sendable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat
}

public struct GridMetrics: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let itemsPerPage: Int
    public let iconSize: CGFloat
    public let itemSize: CGSize
    public let horizontalSpacing: CGFloat
    public let verticalSpacing: CGFloat
    public let sectionInsets: GridInsets
    public let pageWidth: CGFloat
}
```

Add these constants and overload inside `GridLayoutCalculator`:

```swift
static let minimumIconSize: CGFloat = 64
static let maximumIconSize: CGFloat = 96
static let labelExtent: CGFloat = 40
static let minimumHorizontalInset: CGFloat = 60
static let minimumHorizontalSpacing: CGFloat = 20
static let minimumVerticalInset: CGFloat = 10
static let approvedVerticalSpacing: CGFloat = 20

public static func calculate(viewportSize: CGSize) -> GridMetrics {
    let width = viewportSize.width.isFinite ? max(0, viewportSize.width) : 0
    let height = viewportSize.height.isFinite ? max(0, viewportSize.height) : 0
    let columns = width <= 1440 ? 7 : (width <= 1728 ? 9 : 10)
    let rows = stride(from: 5, through: 1, by: -1).first { candidate in
        let itemHeights = CGFloat(candidate) * (minimumIconSize + labelExtent)
        let gaps = CGFloat(candidate - 1) * approvedVerticalSpacing
        return height >= 2 * minimumVerticalInset + itemHeights + gaps
    } ?? 1

    let widthLimit = (width - 2 * minimumHorizontalInset
        - CGFloat(columns - 1) * minimumHorizontalSpacing) / CGFloat(columns)
    let heightLimit = (height - 2 * minimumVerticalInset
        - CGFloat(rows - 1) * approvedVerticalSpacing) / CGFloat(rows) - labelExtent
    let iconSize = min(
        maximumIconSize,
        max(minimumIconSize, min(widthLimit, heightLimit))
    )
    let itemSize = CGSize(width: iconSize, height: iconSize + labelExtent)
    let horizontalInset = min(
        minimumHorizontalInset,
        max(0, (width - CGFloat(columns) * iconSize) / 2)
    )
    let horizontalSpacing = max(
        0,
        (width - 2 * horizontalInset - CGFloat(columns) * iconSize)
            / CGFloat(max(columns - 1, 1))
    )
    let verticalInset = max(
        0,
        (height - CGFloat(rows) * itemSize.height
            - CGFloat(rows - 1) * approvedVerticalSpacing) / 2
    )

    return GridMetrics(
        columns: columns,
        rows: rows,
        itemsPerPage: columns * rows,
        iconSize: iconSize,
        itemSize: itemSize,
        horizontalSpacing: horizontalSpacing,
        verticalSpacing: approvedVerticalSpacing,
        sectionInsets: GridInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        ),
        pageWidth: width
    )
}
```

- [x] **Step 4: Run calculator tests and confirm GREEN**

Run the Step 2 command.

Expected: all old width tests and new viewport tests pass.

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPad/Utilities/GridLayoutCalculator.swift \
  Tests/LaunchPadTests/Utilities/GridLayoutCalculatorTests.swift
git commit -m "feat: calculate grid metrics from viewport"
```

---

### Task 2: Project Stable Layout Into Visual Pages

**Files:**
- Create: `Sources/LaunchPad/Services/LayoutProjection.swift`
- Create: `Tests/LaunchPadTests/Services/LayoutProjectionTests.swift`

**Interfaces:**
- Consumes: persisted page order, persisted children and Task 1 `GridMetrics`.
- Produces: `LayoutProjection.paginate(items:metrics:)` and `project(...) -> [[PageItem]]` without writes; both ordinary and search grids use the same visual capacity.

- [x] **Step 1: Write projection RED tests**

Create the test file with:

```swift
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("LayoutProjection stable order")
struct LayoutProjectionTests {
    @Test("跨持久化页按稳定顺序重新分段")
    func rechunksAcrossPersistedPages() {
        let firstPage = TestDataFactory.makePageItem(id: 100, type: .page, ordering: 1)
        let secondPage = TestDataFactory.makePageItem(id: 200, type: .page, ordering: 0)
        let itemsByPage: [Int64: [PageItem]] = [
            100: [
                TestDataFactory.makePageItem(id: 3, ordering: 1),
                TestDataFactory.makePageItem(id: 2, ordering: 0),
            ],
            200: [
                TestDataFactory.makePageItem(id: 1, ordering: 0),
            ],
        ]
        let metrics = GridMetrics(
            columns: 2, rows: 1, itemsPerPage: 2, iconSize: 64,
            itemSize: CGSize(width: 64, height: 104), horizontalSpacing: 20,
            verticalSpacing: 20,
            sectionInsets: GridInsets(top: 10, left: 10, bottom: 10, right: 10),
            pageWidth: 200
        )

        let result = LayoutProjection.project(
            pages: [firstPage, secondPage],
            itemsByPage: itemsByPage,
            metrics: metrics
        )

        #expect(result.map { $0.map(\.id) } == [[1, 2], [3]])
    }

    @Test("空布局仍产生一个空视觉页")
    func emptyLayoutReturnsOneEmptyPage() {
        let metrics = GridMetrics(
            columns: 7, rows: 5, itemsPerPage: 35, iconSize: 64,
            itemSize: CGSize(width: 64, height: 104), horizontalSpacing: 20,
            verticalSpacing: 20,
            sectionInsets: GridInsets(top: 10, left: 60, bottom: 10, right: 60),
            pageWidth: 1440
        )
        #expect(LayoutProjection.project(
            pages: [], itemsByPage: [:], metrics: metrics
        ) == [[]])
    }

    @Test("容量变化只改变分段不改变稳定顺序")
    func capacityChangePreservesStableOrder() {
        let page = TestDataFactory.makePageItem(id: 100, type: .page)
        let items = (1...8).map { TestDataFactory.makePageItem(id: Int64($0), ordering: $0) }
        let wide = makeMetrics(columns: 4, rows: 1)
        let narrow = makeMetrics(columns: 3, rows: 1)

        let wideResult = LayoutProjection.project(
            pages: [page], itemsByPage: [100: items], metrics: wide)
        let narrowResult = LayoutProjection.project(
            pages: [page], itemsByPage: [100: items], metrics: narrow)

        #expect(wideResult.flatMap { $0 }.map(\.id) == Array(1...8).map(Int64.init))
        #expect(narrowResult.flatMap { $0 }.map(\.id) == Array(1...8).map(Int64.init))
        #expect(wideResult.map(\.count) == [4, 4])
        #expect(narrowResult.map(\.count) == [3, 3, 2])
    }

    @Test("搜索结果也按视觉容量分页且最后一页不超容量")
    func searchResultsUseVisualPagination() {
        let items = (1...9).map {
            TestDataFactory.makePageItem(id: Int64($0), ordering: $0)
        }
        let metrics = makeMetrics(columns: 4, rows: 1)

        let result = LayoutProjection.paginate(items: items, metrics: metrics)

        #expect(result.map(\.count) == [4, 4, 1])
        #expect(result.flatMap { $0 }.map(\.id) == items.map(\.id))
        #expect(result.allSatisfy { $0.count <= metrics.itemsPerPage })
    }

    private func makeMetrics(columns: Int, rows: Int) -> GridMetrics {
        GridMetrics(
            columns: columns, rows: rows, itemsPerPage: columns * rows,
            iconSize: 64, itemSize: CGSize(width: 64, height: 104),
            horizontalSpacing: 20, verticalSpacing: 20,
            sectionInsets: GridInsets(top: 10, left: 10, bottom: 10, right: 10),
            pageWidth: 400
        )
    }
}
```

- [x] **Step 2: Run and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LayoutProjectionTests
```

Expected: compile failure because `LayoutProjection` does not exist.

- [x] **Step 3: Add the pure projection implementation**

Create:

```swift
import Foundation
import LaunchPadProtocols

public enum LayoutProjection {
    public static func paginate(
        items: [PageItem],
        metrics: GridMetrics
    ) -> [[PageItem]] {
        guard !items.isEmpty else { return [[]] }
        let capacity = max(metrics.itemsPerPage, 1)
        return stride(from: 0, to: items.count, by: capacity).map { start in
            Array(items[start..<min(start + capacity, items.count)])
        }
    }

    public static func project(
        pages: [PageItem],
        itemsByPage: [Int64: [PageItem]],
        metrics: GridMetrics
    ) -> [[PageItem]] {
        let orderedItems = pages
            .sorted { $0.ordering < $1.ordering }
            .flatMap { page in
                (itemsByPage[page.id] ?? []).sorted { $0.ordering < $1.ordering }
            }
        return paginate(items: orderedItems, metrics: metrics)
    }
}
```

- [x] **Step 4: Add missing-child and immutability cases, then run GREEN**

Add these exact tests:

```swift
@Test("持久化页缺少 children key 时仍返回一个空视觉页")
func missingPageChildrenStillReturnsOneEmptyPage() {
    let page = TestDataFactory.makePageItem(id: 100, type: .page, ordering: 0)
    let metrics = makeMetrics(columns: 7, rows: 5)

    #expect(LayoutProjection.project(
        pages: [page], itemsByPage: [:], metrics: metrics
    ) == [[]])
}

@Test("投影不修改 parentId 或 ordering")
func projectionDoesNotMutateParentOrOrdering() {
    let page = TestDataFactory.makePageItem(id: 100, type: .page, ordering: 0)
    let items = [
        TestDataFactory.makePageItem(id: 2, ordering: 1, parentId: 100),
        TestDataFactory.makePageItem(id: 1, ordering: 0, parentId: 100),
    ]
    let originalPage = page
    let originalItems = items

    _ = LayoutProjection.project(
        pages: [page],
        itemsByPage: [100: items],
        metrics: makeMetrics(columns: 1, rows: 1)
    )

    #expect(page == originalPage)
    #expect(items == originalItems)
}
```

Run the Step 2 command.

Expected: all projection tests pass.

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPad/Services/LayoutProjection.swift \
  Tests/LaunchPadTests/Services/LayoutProjectionTests.swift
git commit -m "feat: project stable layout into visual pages"
```

---

### Task 3: Replace Flow Geometry With Explicit Row-major Pages

**Files:**
- Modify: `Sources/LaunchPad/Views/AppGridFlowLayout.swift:5-68`
- Modify: `Sources/LaunchPad/Views/PageScrollView.swift:31-152`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift:47-83`
- Modify: `Tests/LaunchPadTests/Views/ViewLayerTests.swift:366-752`
- Modify: `Tests/LaunchPadTests/Views/PageScrollViewTests.swift:6-382`

**Interfaces:**
- Consumes: Task 1 `GridMetrics`.
- Produces: exact row-major item frames, one section per `pageWidth`, explicit paging count, and a collection document frame that cannot collapse below the layout content width but can shrink when the section count decreases.
- Compatibility: keep `applyGridParameters(_:)` and `scrollToPage(_:pageWidth:)` until Tasks 4-5 migrate current callers; the adapters must delegate to the new geometry and paging state rather than retain FlowLayout behavior. Layout compatibility always derives both axes from the enclosing clip viewport, never the expanded document bounds, and falls back to the legacy parameter dimensions only when the clip dimension is absent, non-finite or non-positive. Before Task 5 explicitly configures paging, the legacy scroll adapter derives page count from `documentView` width so page-control navigation does not regress; an explicit one-page configuration must never be overwritten by that fallback.

- [x] **Step 1: Replace both obsolete FlowLayout suites with real 2/3/5-row and multi-section RED tests**

Delete `AppGridFlowLayoutTests` and `AppGridFlowLayoutTests2`, including assertions on `itemSize`, `scrollDirection`, `sectionInset` and vertical centering. Replace them with one hidden fixture; creating the `NSWindow` is allowed, but do not call `makeKeyAndOrderFront`:

```swift
@MainActor
private final class GridSectionsDataSource: NSObject, NSCollectionViewDataSource {
    var itemCounts: [Int]
    init(itemCounts: [Int]) { self.itemCounts = itemCounts }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        itemCounts.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        itemCounts[section]
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath)
    }
}

@MainActor
private func makeGridFixture(
    itemCounts: [Int],
    viewportSize: CGSize
) -> (
    window: NSWindow,
    scrollView: NSScrollView,
    collectionView: AppGridCollectionView,
    layout: AppGridFlowLayout,
    dataSource: GridSectionsDataSource,
    metrics: GridMetrics
) {
    let metrics = GridLayoutCalculator.calculate(viewportSize: viewportSize)
    let layout = AppGridFlowLayout()
    layout.applyGridMetrics(metrics)
    let collectionView = AppGridCollectionView(frame: NSRect(
        origin: .zero,
        size: NSSize(width: metrics.pageWidth * CGFloat(max(itemCounts.count, 1)),
                     height: viewportSize.height)
    ))
    collectionView.collectionViewLayout = layout
    collectionView.register(AppIconCell.self, forItemWithIdentifier: AppIconCell.identifier)
    let dataSource = GridSectionsDataSource(itemCounts: itemCounts)
    collectionView.dataSource = dataSource
    // This fixture owns its external data source; isolate unrelated production selection callbacks.
    collectionView.delegate = nil
    let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: viewportSize))
    scrollView.documentView = collectionView
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: viewportSize),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = scrollView
    collectionView.reloadData()
    layout.prepare()
    return (window, scrollView, collectionView, layout, dataSource, metrics)
}
```

The central assertion helper must be:

```swift
private func assertRowMajor(
    attributes: [NSCollectionViewLayoutAttributes],
    columns: Int,
    expectedRows: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let sorted = attributes.sorted { $0.indexPath!.item < $1.indexPath!.item }
    let rowOrigins = Set(sorted.map { $0.frame.minY.rounded() })
    XCTAssertEqual(rowOrigins.count, expectedRows, file: file, line: line)
    for (index, attribute) in sorted.enumerated() {
        let expectedRow = index / columns
        let expectedColumn = index % columns
        XCTAssertEqual(attribute.indexPath?.item, index, file: file, line: line)
        if expectedColumn > 0 {
            XCTAssertEqual(
                attribute.frame.minY,
                sorted[expectedRow * columns].frame.minY,
                accuracy: 0.5, file: file, line: line
            )
        }
    }
}

@MainActor
func testRowMajorAttributesUseTwoThreeAndFiveRowsWithoutOverlap() {
    for (height, itemCount, expectedRows) in [(248.0, 14, 2), (372.0, 21, 3), (620.0, 35, 5)] {
        let fixture = makeGridFixture(
            itemCounts: [itemCount],
            viewportSize: CGSize(width: 1440, height: height)
        )
        let attributes = (0..<itemCount).compactMap {
            fixture.layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
        }
        assertRowMajor(
            attributes: attributes,
            columns: fixture.metrics.columns,
            expectedRows: expectedRows
        )
        for left in attributes.indices {
            for right in attributes.indices where right > left {
                XCTAssertFalse(attributes[left].frame.intersects(attributes[right].frame))
            }
        }
    }
}

@MainActor
func testTwoAndThreeSectionOriginsDifferByPageWidth() {
    for count in [2, 3] {
        let fixture = makeGridFixture(
            itemCounts: Array(repeating: 1, count: count),
            viewportSize: CGSize(width: 1440, height: 620)
        )
        let origins = (0..<count).compactMap {
            fixture.layout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: $0)
            )?.frame.minX
        }
        XCTAssertEqual(origins.count, count)
        for section in 1..<count {
            XCTAssertEqual(
                origins[section] - origins[section - 1],
                fixture.metrics.pageWidth,
                accuracy: 0.5
            )
        }
        XCTAssertEqual(
            fixture.layout.collectionViewContentSize.width,
            CGFloat(count) * fixture.metrics.pageWidth,
            accuracy: 0.5
        )
    }
}

@MainActor
func testPartialLastPageStartsAtTopLeftSlot() {
    let fixture = makeGridFixture(
        itemCounts: [35, 3],
        viewportSize: CGSize(width: 1440, height: 620)
    )
    let first = fixture.layout.layoutAttributesForItem(
        at: IndexPath(item: 0, section: 1)
    )!
    XCTAssertEqual(
        first.frame.origin,
        NSPoint(
            x: fixture.metrics.pageWidth + fixture.metrics.sectionInsets.left,
            y: fixture.metrics.sectionInsets.top
        )
    )
}

@MainActor
func testSupplementaryRequestIsNotRepositionedAsAnItem() {
    let fixture = makeGridFixture(
        itemCounts: [1], viewportSize: CGSize(width: 1440, height: 620)
    )
    XCTAssertNil(fixture.layout.layoutAttributesForSupplementaryView(
        ofKind: NSCollectionView.elementKindSectionHeader,
        at: IndexPath(item: 0, section: 0)
    ))
}

@MainActor
func testSnapUsesRealSectionCountAndConfiguredPageWidth() {
    let fixture = makeGridFixture(
        itemCounts: [1, 1, 1], viewportSize: CGSize(width: 300, height: 248)
    )
    fixture.scrollView.contentView.setBoundsOrigin(NSPoint(x: 300, y: 0))
    let target = fixture.layout.targetContentOffset(
        forProposedContentOffset: NSPoint(x: 610, y: 17),
        withScrollingVelocity: .zero
    )
    XCTAssertEqual(target, NSPoint(x: 600, y: 0))
}

@MainActor
func testDocumentFrameTracksPagedContentWidthAndCanShrink() {
    let fixture = makeGridFixture(
        itemCounts: [1, 1, 1], viewportSize: CGSize(width: 300, height: 248)
    )
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(fixture.collectionView.frame.width, 900, accuracy: 0.5)
    XCTAssertEqual(
        fixture.scrollView.contentView.documentRect.width, 900, accuracy: 0.5
    )

    fixture.dataSource.itemCounts = [1, 1]
    fixture.collectionView.reloadData()
    fixture.layout.invalidateLayout()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.collectionView.frame.width, 600, accuracy: 0.5)
    XCTAssertEqual(
        fixture.scrollView.contentView.documentRect.width, 600, accuracy: 0.5
    )
}

@MainActor
func testCompatibilityMetricsStayBoundToClipViewportAcrossPrepares() {
    let viewportSize = CGSize(width: 300, height: 248)
    let fixture = makeGridFixture(
        itemCounts: [1, 1, 1], viewportSize: viewportSize
    )
    fixture.collectionView.setFrameSize(NSSize(width: 900, height: 620))
    let parameters = GridLayoutCalculator.calculate(screenWidth: viewportSize.width)
    let expectedMetrics = GridLayoutCalculator.calculate(viewportSize: viewportSize)
    let expectedContentHeight = expectedMetrics.sectionInsets.top
        + CGFloat(expectedMetrics.rows) * expectedMetrics.itemSize.height
        + CGFloat(max(expectedMetrics.rows - 1, 0)) * expectedMetrics.verticalSpacing
        + expectedMetrics.sectionInsets.bottom

    for _ in 0..<2 {
        fixture.layout.applyGridParameters(parameters)
        fixture.layout.prepare()

        XCTAssertEqual(
            fixture.layout.collectionViewContentSize.width, 900, accuracy: 0.5
        )
        XCTAssertEqual(
            fixture.layout.collectionViewContentSize.height,
            expectedContentHeight,
            accuracy: 0.5
        )
        fixture.window.contentView?.layoutSubtreeIfNeeded()
    }
}
```

- [x] **Step 2: Add PageScrollView RED tests**

Add the following invalid-configuration, ended/cancelled, synchronous resize, clamp and callback tests:

```swift
@Test("configurePaging 后 scrollToPage 同步夹紧并通知")
@MainActor
func configuredPagingClampsAndNotifies() {
    let sut = PageScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    var pages: [Int] = []
    sut.onPageChanged = { pages.append($0) }
    sut.configurePaging(pageWidth: 300, pageCount: 3)

    sut.scrollToPage(9, animated: false)

    #expect(sut.contentView.bounds.origin.x == 600)
    #expect(pages == [2])
}

@Test("无效 pageWidth 被清零且 pageCount 至少为一")
@MainActor
func invalidPagingConfigurationIsSanitized() {
    let sut = PageScrollView()
    sut.configurePaging(pageWidth: .infinity, pageCount: 0)
    #expect(sut.pagingPageWidth == 0)
    #expect(sut.pagingPageCount == 1)
}

@Test("resize 后同步滚到夹紧后的当前页")
@MainActor
func resizePagingPositionsSynchronously() {
    let sut = PageScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    sut.configurePaging(pageWidth: 300, pageCount: 3)
    sut.scrollToPage(2, animated: false)
    sut.configurePaging(pageWidth: 240, pageCount: 2)
    sut.scrollToPage(2, animated: false)
    #expect(sut.contentView.bounds.origin.x == 240)
}

@Test("configured 三页的 ended 与 cancelled 都使用显式 pageCount")
@MainActor
func configuredEndedAndCancelledUseExplicitPageCount() {
    for phase in [NSEvent.Phase.ended, .cancelled] {
        let sut = PageScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        sut.configurePaging(pageWidth: 300, pageCount: 3)
        var pages: [Int] = []
        sut.onPageChanged = { pages.append($0) }
        let event = makeDummyScrollEvent()
        _ = sut.processScrollPhase(.changed, deltaX: 200, event: event)
        _ = sut.processScrollPhase(phase, deltaX: 0, event: event)

        #expect(pages == [1])
    }
}

@Test("兼容 scrollToPage 在未显式配置时按文档宽度推导页数")
@MainActor
func legacyScrollToPageInfersPageCount() {
    let sut = PageScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    sut.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 200))
    var pages: [Int] = []
    sut.onPageChanged = { pages.append($0) }

    sut.scrollToPage(2)

    #expect(sut.pagingPageWidth == 300)
    #expect(sut.pagingPageCount == 3)
    #expect(pages == [2])
}

@Test("显式单页配置不被兼容页数推导覆盖")
@MainActor
func explicitSinglePageDoesNotUseLegacyInference() {
    let sut = PageScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    sut.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 200))
    var pages: [Int] = []
    sut.onPageChanged = { pages.append($0) }
    sut.configurePaging(pageWidth: 300, pageCount: 1)

    sut.scrollToPage(2)

    #expect(sut.pagingPageCount == 1)
    #expect(pages == [0])
}
```

- [x] **Step 3: Run and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridFlowLayoutTests|PageScrollViewTests'
```

Expected: old layout collapses all y values, multi-section width is not page aligned, and PageScrollView lacks configuration APIs.

- [x] **Step 4: Replace `AppGridFlowLayout` with explicit cached item frames**

Keep the class name but derive from `NSCollectionViewLayout`. Implement these exact public methods and cache rules:

```swift
public final class AppGridFlowLayout: NSCollectionViewLayout {
    private var metrics: GridMetrics?
    private var compatibilityParameters: GridLayoutCalculator.GridParameters?
    private var attributesByIndexPath: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var contentSize: NSSize = .zero

    public func applyGridMetrics(_ metrics: GridMetrics) {
        self.metrics = metrics
        compatibilityParameters = nil
        invalidateLayout()
    }

    @available(*, deprecated, message: "Use applyGridMetrics(_:)")
    public func applyGridParameters(
        _ parameters: GridLayoutCalculator.GridParameters
    ) {
        metrics = nil
        compatibilityParameters = parameters
        invalidateLayout()
    }

    public override func prepare() {
        super.prepare()
        attributesByIndexPath.removeAll(keepingCapacity: true)
        guard let collectionView,
              let metrics = resolvedMetrics(for: collectionView) else {
            contentSize = .zero
            return
        }

        let sectionCount = max(collectionView.numberOfSections, 1)
        for section in 0..<collectionView.numberOfSections {
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                let row = item / max(metrics.columns, 1)
                let column = item % max(metrics.columns, 1)
                let origin = NSPoint(
                    x: CGFloat(section) * metrics.pageWidth
                        + metrics.sectionInsets.left
                        + CGFloat(column) * (metrics.itemSize.width + metrics.horizontalSpacing),
                    y: metrics.sectionInsets.top
                        + CGFloat(row) * (metrics.itemSize.height + metrics.verticalSpacing)
                )
                let indexPath = IndexPath(item: item, section: section)
                let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
                attributes.frame = NSRect(origin: origin, size: metrics.itemSize)
                attributesByIndexPath[indexPath] = attributes
            }
        }
        contentSize = NSSize(
            width: CGFloat(sectionCount) * metrics.pageWidth,
            height: metrics.sectionInsets.top
                + CGFloat(metrics.rows) * metrics.itemSize.height
                + CGFloat(max(metrics.rows - 1, 0)) * metrics.verticalSpacing
                + metrics.sectionInsets.bottom
        )
    }

    private func resolvedMetrics(
        for collectionView: NSCollectionView
    ) -> GridMetrics? {
        if let metrics { return metrics }
        guard let parameters = compatibilityParameters else { return nil }
        let fallbackWidth = 2 * parameters.horizontalMargin
            + CGFloat(parameters.columns) * parameters.iconSize
            + CGFloat(max(parameters.columns - 1, 0)) * parameters.spacing
        let fallbackHeight = parameters.topMargin + parameters.bottomMargin
            + CGFloat(parameters.rows) * (parameters.iconSize + 40)
            + CGFloat(max(parameters.rows - 1, 0)) * parameters.spacing
        let clipSize = collectionView.enclosingScrollView?.contentView.bounds.size
        let clipWidth = clipSize?.width ?? 0
        let clipHeight = clipSize?.height ?? 0
        let viewport = CGSize(
            width: clipWidth.isFinite && clipWidth > 0
                ? clipWidth : fallbackWidth,
            height: clipHeight.isFinite && clipHeight > 0
                ? clipHeight : fallbackHeight
        )
        return GridLayoutCalculator.calculate(viewportSize: viewport)
    }

    public override var collectionViewContentSize: NSSize { contentSize }

    public override func layoutAttributesForElements(
        in rect: NSRect
    ) -> [NSCollectionViewLayoutAttributes] {
        attributesByIndexPath.values
            .filter { $0.frame.intersects(rect) }
            .map { $0.copy() as! NSCollectionViewLayoutAttributes }
    }

    public override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        attributesByIndexPath[indexPath]?.copy() as? NSCollectionViewLayoutAttributes
    }

    public override func layoutAttributesForSupplementaryView(
        ofKind elementKind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        nil
    }

    public override func shouldInvalidateLayout(
        forBoundsChange newBounds: NSRect
    ) -> Bool {
        collectionView?.bounds.size != newBounds.size
    }

    public override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: NSPoint,
        withScrollingVelocity velocity: NSPoint
    ) -> NSPoint {
        guard let collectionView,
              let metrics = resolvedMetrics(for: collectionView) else {
            return proposedContentOffset
        }
        let totalPages = max(collectionView.numberOfSections, 1)
        let currentPage = Int(round(collectionView.enclosingScrollView?
            .contentView.bounds.origin.x ?? 0) / max(metrics.pageWidth, 1))
        let target = PageScrollView.targetPage(
            for: proposedContentOffset.x - CGFloat(currentPage) * metrics.pageWidth,
            velocity: velocity.x,
            currentPage: currentPage,
            totalPages: totalPages,
            pageWidth: metrics.pageWidth
        )
        return NSPoint(x: CGFloat(target) * metrics.pageWidth, y: 0)
    }
}
```

In `AppGridCollectionView`, add the document sizing boundary before `setup()`:

```swift
/// Prevents AppKit from collapsing horizontally paged content to the clip width.
override public func setFrameSize(_ newSize: NSSize) {
    var resolvedSize = newSize
    let contentWidth = collectionViewLayout?.collectionViewContentSize.width ?? 0
    if contentWidth.isFinite && contentWidth > 0 {
        resolvedSize.width = max(resolvedSize.width, contentWidth)
    }
    super.setFrameSize(resolvedSize)
}
```

- [x] **Step 5: Add explicit PageScrollView configuration**

Add properties and replace `scrollToPage`:

```swift
var onPageChanged: ((Int) -> Void)?
private(set) var pagingPageWidth: CGFloat = 0
private(set) var pagingPageCount: Int = 1
private var hasExplicitPagingConfiguration = false

func configurePaging(pageWidth: CGFloat, pageCount: Int) {
    hasExplicitPagingConfiguration = true
    updatePagingConfiguration(pageWidth: pageWidth, pageCount: pageCount)
}

private func updatePagingConfiguration(pageWidth: CGFloat, pageCount: Int) {
    pagingPageWidth = pageWidth.isFinite ? max(0, pageWidth) : 0
    pagingPageCount = max(1, pageCount)
}

func scrollToPage(_ page: Int, animated: Bool) {
    guard pagingPageWidth > 0 else { return }
    let clamped = min(max(page, 0), pagingPageCount - 1)
    let target = NSPoint(x: CGFloat(clamped) * pagingPageWidth, y: 0)
    if animated {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AnimationConstants.pageScroll.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentView.animator().bounds.origin = target
        }
    } else {
        contentView.setBoundsOrigin(target)
    }
    onPageChanged?(clamped)
}

@available(*, deprecated, message: "Configure paging, then call scrollToPage(_:animated:)")
func scrollToPage(_ page: Int, pageWidth: CGFloat? = nil) {
    if !hasExplicitPagingConfiguration {
        let resolvedPageWidth = pageWidth ?? bounds.width
        let documentWidth = documentView?.bounds.width ?? 0
        let inferredPageCount = resolvedPageWidth.isFinite && resolvedPageWidth > 0
            ? max(1, Int(ceil(documentWidth / resolvedPageWidth)))
            : 1
        updatePagingConfiguration(
            pageWidth: resolvedPageWidth,
            pageCount: inferredPageCount
        )
    } else if let pageWidth {
        updatePagingConfiguration(
            pageWidth: pageWidth,
            pageCount: pagingPageCount
        )
    }
    scrollToPage(page, animated: true)
}
```

Replace the ended/cancelled branch so every exit clears the accumulator and it uses only configured paging state:

```swift
if phase.contains(.ended) || phase.contains(.cancelled) {
    let accumulatedOffset = scrollAccumulator
    scrollAccumulator = 0
    guard isScrolling else { return false }
    isScrolling = false
    guard pagingPageWidth > 0 else { return false }

    let currentPage = Int(round(
        contentView.bounds.origin.x / pagingPageWidth
    ))
    let target = Self.targetPage(
        for: accumulatedOffset,
        velocity: deltaX * 10,
        currentPage: currentPage,
        totalPages: pagingPageCount,
        pageWidth: pagingPageWidth
    )
    scrollToPage(target, animated: true)
    return false
}
```

- [x] **Step 6: Run layout and paging tests GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridFlowLayoutTests|PageScrollViewTests'
```

Expected: 2/3/5 rows are distinct, two sections are exactly two pages, the document frame expands and shrinks with section count, and paging callbacks/clamps pass without showing a real window.

- [x] **Step 7: Commit**

```bash
git add Sources/LaunchPad/Views/AppGridFlowLayout.swift \
  Sources/LaunchPad/Views/PageScrollView.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Tests/LaunchPadTests/Views/ViewLayerTests.swift \
  Tests/LaunchPadTests/Views/PageScrollViewTests.swift
git commit -m "fix: use explicit row-major paged geometry"
```

---

### Task 3R-A: Bind Scheduler Work to MainActor and Make Debounce Deterministic

**Files:**
- Modify: `Sources/LaunchPadProtocols/Protocols.swift:92-98`
- Modify: `Sources/LaunchPad/Controllers/DragController.swift:6,228-251`
- Modify: `Sources/LaunchPad/Services/SearchDebouncer.swift:9-70`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:67-68,310-339`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift:150-176`
- Modify: `Tests/LaunchPadTests/Models/ProtocolTests.swift:47-50`
- Modify: `Tests/LaunchPadTests/Controllers/DragControllerTests.swift:14`
- Modify: `Tests/LaunchPadTests/Views/CollectionViewDragTests.swift:6`
- Modify: `Tests/LaunchPadTests/Services/SearchDebounceTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift:100-117,711-722`
- Create: `.superpowers/sdd/task-3r-a-review.md`

**Interfaces:**
- Produces: `@MainActor public protocol Scheduler: Sendable` and an exact `@escaping @MainActor @Sendable () -> Void` action contract.
- Produces: one-work-item `DispatchQueueScheduler`; replacement, explicit cancellation and destruction each cancel the exact owned item.
- Produces: `SearchDebouncer` with `@MainActor @Sendable (String) -> Void` handler and VC-local `SearchRunner` for synchronous test completion.
- Consumed later by: Tasks 7, 15 and 21. Those tasks consume this contract and must not redefine it.

- [x] **Step 1: Reproduce the background `assumeIsolated` trap with a named RED test**

Add:

```swift
@Test("真实 scheduler 的延迟 action 在 MainActor 执行")
func dispatchQueueSchedulerRunsActionOnMainActor() async {
    let (stream, continuation) = AsyncStream.makeStream(of: String.self)
    let scheduler = DispatchQueueScheduler()
    scheduler.schedule(after: 0) {
        MainActor.preconditionIsolated()
        continuation.yield("safari")
        continuation.finish()
    }
    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == "safari")
}
```

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter dispatchQueueSchedulerRunsActionOnMainActor
```

Expected: current implementation terminates with signal 5 in `MainActor.assumeIsolated` on `com.launchpad.scheduler`. This is the RED evidence and may not be skipped or recorded as an allowed failure.

- [x] **Step 2: Move the scheduler contract and implementation onto MainActor**

Replace the protocol with:

```swift
@MainActor
public protocol Scheduler: Sendable {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    )
    func cancelPending()
}
```

Mark `DragController` `@MainActor` and replace `DispatchQueueScheduler` with:

```swift
@MainActor
public final class DispatchQueueScheduler: Scheduler {
    private final class PendingWork: @unchecked Sendable {
        private var item: DispatchWorkItem?

        func replace(with newItem: DispatchWorkItem) {
            item?.cancel()
            item = newItem
        }

        func cancel() {
            item?.cancel()
            item = nil
        }

        deinit { item?.cancel() }
    }

    private let pendingWork = PendingWork()
    var workItemObserver: ((DispatchWorkItem) -> Void)?

    public init() {}

    public func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        cancelPending()
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        pendingWork.replace(with: item)
        workItemObserver?(item)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + interval,
            execute: item
        )
    }

    public func cancelPending() {
        pendingWork.cancel()
    }
}
```

`assumeIsolated` is allowed only inside the work item explicitly submitted to `DispatchQueue.main`. Mark `MockScheduler` and both drag suites `@MainActor`; store actions as `@MainActor @Sendable () -> Void`. `fireLatest()` must remove all pending actions before invoking the latest action so a test cannot leave escaped work.

- [x] **Step 3: Remove every unsafe SearchDebouncer bridge and prove exact ownership**

Replace the callback declaration, initializer and delayed branch with:

```swift
private let searchHandler: @MainActor @Sendable (String) -> Void

public init(
    debounceInterval: TimeInterval = 0.1,
    scheduler: Scheduler,
    searchHandler: @escaping @MainActor @Sendable (String) -> Void
) {
    self.debounceInterval = debounceInterval
    self.scheduler = scheduler
    self.searchHandler = searchHandler
}

lastQuery = query
scheduler.cancelPending()
let handler = searchHandler
scheduler.schedule(after: debounceInterval) {
    handler(query)
}
```

Delete both `@preconcurrency`, `nonisolated(unsafe)`, `unsafeHandler` and the background `MainActor.assumeIsolated`. Add:

```swift
@Test("替换、显式取消与释放均取消 exact work item")
func dispatchQueueSchedulerCancelsOwnedWorkItems() {
    var first: DispatchWorkItem?
    var second: DispatchWorkItem?
    var third: DispatchWorkItem?
    weak var weakScheduler: DispatchQueueScheduler?
    do {
        let scheduler = DispatchQueueScheduler()
        weakScheduler = scheduler
        scheduler.workItemObserver = { item in
            if first == nil { first = item }
            else if second == nil { second = item }
            else { third = item }
        }
        scheduler.schedule(after: 60) {}
        scheduler.schedule(after: 60) {}
        #expect(first?.isCancelled == true)
        #expect(second?.isCancelled == false)
        scheduler.cancelPending()
        #expect(second?.isCancelled == true)
        scheduler.schedule(after: 60) {}
        #expect(third?.isCancelled == false)
    }
    #expect(weakScheduler == nil)
    #expect(third?.isCancelled == true)
}
```

Run the two named scheduler tests; expected: 2 tests pass and the helper exits normally.

- [x] **Step 4: Replace the escaping VC search fixture with an injected runner**

Add:

```swift
typealias SearchRunner = @MainActor @Sendable (
    [PageItem],
    String,
    @escaping @MainActor @Sendable ([PageItem]) -> Void
) -> Void

lazy var searchRunner: SearchRunner = {
    [searchQueue, searchEngine] items, query, completion in
    searchQueue.async {
        let results = searchEngine.cachedSearch(items: items, query: query)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion(results) }
        }
    }
}
```

The nonempty branch calls `searchRunner(allItems, capturedQuery)` and applies results only through its MainActor completion with the existing expected-query guard. Replace the no-assertion fixture with `handleSearch_nonEmptyQuery_runsInjectedSearchOnce`: inject `MockScheduler`, one Safari item ID 10 and a synchronous runner; enter `s`, append `a`, advance by `0.099` then `0.001`, and assert exactly `[(ids: [10], query: "sa")]`, label `1 results`, visible results and an empty scheduler.

- [x] **Step 5: Run regression, full serial termination gate and commit**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'SearchDebounceTests|LaunchPadViewControllerTests|DragControllerTests|CollectionViewDragTests|ProtocolTests'

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel
```

Expected: the focused command exits 0. The full command completes with a full
Swift Testing summary, no signal and no escaped helper process; it may exit
nonzero only for the exact registered 6-failure/2-skip Task 3R baseline above.
Compare qualified IDs, not only counts, and stop on any new ID or count
increase. Record RED/GREEN/full-gate logs and review the task range before
committing:

```bash
git add Sources/LaunchPadProtocols/Protocols.swift \
  Sources/LaunchPad/Controllers/DragController.swift \
  Sources/LaunchPad/Services/SearchDebouncer.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift \
  Tests/LaunchPadTests/Models/ProtocolTests.swift \
  Tests/LaunchPadTests/Controllers/DragControllerTests.swift \
  Tests/LaunchPadTests/Views/CollectionViewDragTests.swift \
  Tests/LaunchPadTests/Services/SearchDebounceTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift
git commit -m "fix: bind schedulers and debounce work to main actor"
```

---

### Task 3R-B: Isolate Hotkey and AppDelegate Process Boundaries

**Files:**
- Modify: `Sources/LaunchPadProtocols/Protocols.swift:86-90`
- Modify: `Sources/LaunchPad/App/HotkeyManager.swift:39-58,72-112,161-183`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:31-83,139-141,222-290`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift:134-148`
- Modify: `Tests/LaunchPadTests/Models/ProtocolTests.swift:43-47`
- Modify: `Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Create: `.superpowers/sdd/task-3r-b-review.md`

**Interfaces:**
- Produces: explicit global-tap override semantics; an injected closure returning nil is an authoritative failure and never falls through to the injected `eventTapCreator` system boundary.
- Produces: Task 21's planned `eventTapCreator` boundary ahead of schedule so the no-fallback rule has deterministic RED/GREEN evidence; Task 21 reuses it and does not add a duplicate creator.
- Produces: `@MainActor HotkeyManaging` and `@MainActor HotkeyManager`, removing the unverifiable `@unchecked Sendable` contract; mocks and protocol tests consume the same actor contract.
- Produces: Task 21's planned weak `HotkeyCallbackBox` and exactly-once retained callback-context release ahead of schedule; Task 21 reuses them.
- Produces: idempotent `localMonitorInstaller`/`localMonitorRemover`, plus AppDelegate `hotkeyManagerFactory`, `workspaceURLOpener` and `hotkeyToggleRunner`.
- Consumed later by: Tasks 8-9 and 21; those tasks extend behavior/lifecycle through these names and do not add duplicate boundaries.

- [x] **Step 1: Reproduce tap fallback and real-boundary leaks**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'registerGlobalHotkey_hasConflict_whenTapFails|setupHotkey_conflict'
```

Expected: the current host returns nil from the real `CGEvent.tapCreate`, so the
existing result-only tests pass and cannot prove whether fallback occurred. Add
an injected `eventTapCreator` counter first, without changing the nil-coalescing
selection, and assert that `tapProvider = { nil }` must leave its call count at
zero. The old selection calls it once, producing deterministic RED without
touching the real event-tap boundary. Capture the counter mismatch as RED.

- [x] **Step 2: Make tap selection explicit and local monitor lifecycle injectable**

Move Task 21's planned event-tap creation boundary forward:

```swift
typealias EventTapCreator = (
    CGEventMask,
    CGEventTapCallBack,
    UnsafeMutableRawPointer?
) -> CFMachPort?

var eventTapCreator: EventTapCreator = { mask, callback, context in
    CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: context
    )
}
```

Replace tap selection with:

```swift
let tap: CFMachPort?
if let tapProvider {
    tap = tapProvider()
} else {
    tap = eventTapCreator(mask, HotkeyManager.tapCallback, selfPtr)
}
```

Add:

```swift
var localMonitorHandler: ((NSEvent) -> NSEvent?)?
var localMonitorInstaller: (@escaping (NSEvent) -> NSEvent?) -> Any? = {
    handler in
    NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown, .flagsChanged],
        handler: handler
    )
}
var localMonitorRemover: (Any) -> Void = { NSEvent.removeMonitor($0) }

public init() {
    accessibilityChecker = HotkeyManager.defaultAccessibilityCheck
    localMonitorHandler = { [weak self] event in
        self?.handleLocalMonitorEvent(event) ?? event
    }
}

public func registerLocalMonitor() {
    guard localMonitor == nil, let localMonitorHandler else { return }
    localMonitor = localMonitorInstaller(localMonitorHandler)
}

public func unregisterLocalMonitor() {
    guard let localMonitor else { return }
    localMonitorRemover(localMonitor)
    self.localMonitor = nil
}
```

Make `HotkeyManaging`, `HotkeyManager`, `MockHotkeyManager`, the hotkey suite,
and the affected protocol test MainActor-isolated. Remove
`HotkeyManager: @unchecked Sendable`. Registration is MainActor-isolated and
adds the event-tap source to `CFRunLoopGetCurrent()`, which is therefore the main
run loop. The `nonisolated` C callback has a main-runloop-only contract: require
`Thread.isMainThread`, then synchronously enter `MainActor.assumeIsolated` and
process the event before returning. Do not bridge an off-main callback with
`DispatchQueue.main.sync`; that creates callback-context UAF and cross-thread
deadlock windows. Cover the main-thread `flagsChanged` then `keyDown` ordering
and statically reject an off-main sync bridge.

Move Task 21's weak callback ownership forward. Retain a `HotkeyCallbackBox`
whose manager reference is weak, store the opaque context only after successful
registration, and release it exactly once on every tap/source failure,
re-registration, explicit unregister and deinit. Registration starts by
unregistering prior state and resetting `hasConflict = false`. Add RED/GREEN
coverage for deallocation after successful unregister, repeated registration,
double unregister, and conflict followed by permission failure/success.

Do not change special-key suppression in this task; Task 8 owns that behavior. Convert every hotkey test fixture to an isolated manager with injected accessibility result, opaque local token and fake tap result. Add `nilTapOverrideIsAuthoritative` and `localMonitorLifecycleUsesInjectedBoundary`. The former asserts false/conflict and an exact zero `eventTapCreator` call count; the latter asserts install/remove identity/count after double register/unregister. Also cover the no-override production branch with exactly one injected creator call. Delete tests that directly call `AXIsProcessTrusted` or real `SMAppService.register/unregister`, and delete the real-FSEvents two-second sleep test whose only assertion is `#expect(true)`; Task 21 adds its deterministic backend replacement.

- [x] **Step 3: Isolate AppDelegate construction, URL opening and toggle delivery**

Add:

```swift
var hotkeyManagerFactory: () -> HotkeyManager = { HotkeyManager() }
var workspaceURLOpener: (URL) -> Void = {
    _ = NSWorkspace.shared.open($0)
}
var hotkeyToggleRunner:
    @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = {
    action in
    Task { @MainActor in action() }
}
```

Use the factory in `setupServices`, the URL opener in the permission-settings branch, and bind toggle through:

```swift
let runner = hotkeyToggleRunner
hotkeyManager.onToggle = { @Sendable [weak self] in
    runner { [weak self] in self?.windowController.toggle() }
}
```

The AppDelegate test factory must use `NSStatusItem()` instead of `NSStatusBar.system`, an isolated hotkey manager, `{ _ in }` URL opener and a synchronous toggle runner. Replace sleep-based toggle verification with an immediate lifecycle assertion. Conflict tests assert the exact alert `Option+Space 快捷键已被占用` and no opened URL; permission tests assert only `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`, while the second-button path opens nothing. Add exact factory call-count/identity coverage and a successful hotkey-registration branch that produces zero alert and zero opened URL.

- [x] **Step 4: Run isolated suites, full serial termination gate and commit**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'HotkeyManagerTests|AppDelegateTests'

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel
```

Expected: the focused command exits 0. The full command completes with both
framework summaries, no `Task.sleep`, no real event tap/local monitor/status-bar
insertion or System Settings open, no signal and no escaped helper; it may exit
nonzero only for the remaining subset of the registered Task 3R baseline:
6 XCTest failures, 2 XCTest skips and 4 Swift Testing issues from the 3 named
`LaunchPadWindowControllerTests`. Stop on any new failure/skip/issue ID or count
increase. Review 3R-B separately, then the combined 3R range:

```bash
git add Sources/LaunchPad/App/HotkeyManager.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Sources/LaunchPadProtocols/Protocols.swift \
  Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift \
  Tests/LaunchPadTests/Models/ProtocolTests.swift
git commit -m "fix: isolate hotkey system boundaries in tests"
```

---

### Task 3R-C: Isolate Dock Exclusion Parsing Before Continuing the Full Gate

**Files:**
- Modify: `Sources/LaunchPad/Services/AppScanner.swift:5-40`
- Modify: `Tests/LaunchPadTests/Services/AppScannerTests.swift:6-193`
- Create: `.superpowers/sdd/task-3r-c-review.md`

**Interfaces:**
- Consumes: the existing `excludedBundleIds` override; explicit sets remain
  authoritative and do not invoke the provider.
- Produces: `AppScanner.ExcludedDataProvider`, read-only
  `systemExcludedData()` and pure `parseExcludedBundleIDs(from:)`.
- Preserves: production defaults still read
  `~/Library/Application Support/Dock/LaunchPadLayout.plist` once and parse the
  same hidden string bundle IDs; production never writes that path.
- Test isolation: every AppScanner test that does not target the provider passes
  `excludedBundleIds: []`; the provider/parser tests use only in-memory `Data`.

- [x] **Step 1: Record the stable RED without widening filesystem permissions**

Use the existing main-agent evidence rather than re-running the dangerous test
outside the managed sandbox:

```bash
rg -n "scan_loadsSystemExcludedBundleIds|LaunchPadLayout.plist|try! data.write" \
  Tests/LaunchPadTests/Services/AppScannerTests.swift
rg -n "unexpected signal code 5|AppScannerTests.swift:179|NSCocoaErrorDomain Code=513" \
  /tmp/launchpad-main-3m-full.log
test ! -e "$HOME/Library/Application Support/Dock/LaunchPadLayout.plist"
```

Expected: the old test contains backup/delete/create/write operations against
the real user Dock path; the full log records signal 5 and Cocoa 513/EPERM at
line 179; no plist remains after the denied write. Never request broader
permissions to make this test pass, because that would authorize the forbidden
side effect.

- [x] **Step 2: Replace the host mutation with in-memory RED tests**

Add this helper inside `AppScannerTests`:

```swift
private func makeExcludedData(from root: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(
        fromPropertyList: root,
        format: .xml,
        options: 0
    )
}
```

Delete the backup/remove/create/write test and replace it with these six exact
branches:

```swift
@Test("nil exclusion data returns an empty set")
func parseExcludedBundleIDs_nil_returnsEmpty() {
    #expect(AppScanner.parseExcludedBundleIDs(from: nil).isEmpty)
}

@Test("malformed exclusion data returns an empty set")
func parseExcludedBundleIDs_malformedData_returnsEmpty() {
    #expect(AppScanner.parseExcludedBundleIDs(
        from: Data("not a plist".utf8)
    ).isEmpty)
}

@Test("a plist without pages returns an empty set")
func parseExcludedBundleIDs_missingPages_returnsEmpty() throws {
    let data = try makeExcludedData(from: ["version": 1])
    #expect(AppScanner.parseExcludedBundleIDs(from: data).isEmpty)
}

@Test("malformed item containers and entries are ignored")
func parseExcludedBundleIDs_malformedItems_areIgnored() throws {
    let data = try makeExcludedData(from: [
        "pages": [
            ["items": "not an array"],
            ["items": [
                ["bundleid": 17, "visible": false],
                ["bundleid": "missing.visible"],
                ["visible": false],
            ]],
        ],
    ])
    #expect(AppScanner.parseExcludedBundleIDs(from: data).isEmpty)
}

@Test("only hidden string bundle IDs are returned")
func parseExcludedBundleIDs_mixedVisibility_returnsOnlyHiddenStrings() throws {
    let data = try makeExcludedData(from: [
        "pages": [
            ["items": [
                ["bundleid": "com.test.hidden.one", "visible": false],
                ["bundleid": "com.test.visible", "visible": true],
            ]],
            ["items": [
                ["bundleid": "com.test.hidden.two", "visible": false],
            ]],
        ],
    ])
    #expect(AppScanner.parseExcludedBundleIDs(from: data) == [
        "com.test.hidden.one", "com.test.hidden.two",
    ])
}

@Test("injected exclusion data filters a hidden app")
func scan_loadsInjectedSystemExcludedBundleIds() throws {
    let data = try makeExcludedData(from: [
        "pages": [["items": [[
            "bundleid": "com.test.hidden", "visible": false,
        ]]]],
    ])
    let fs = MockFileSystemService()
    let hiddenURL = appURL("HiddenApp")
    fs.directoryContentsMap[appDir] = [hiddenURL]
    fs.existingFiles = [hiddenURL]
    fs.bundleInfos[hiddenURL] = makePlist(
        name: "HiddenApp",
        bundleId: "com.test.hidden"
    )
    let scanner = AppScanner(
        fileSystemService: fs,
        excludedDataProvider: { data }
    )

    #expect(scanner.scanDirectories([appDir]).isEmpty)
}
```

The file contains 22 `AppScanner(...)` construction points. After this change,
exactly 20 pass `excludedBundleIds: []`, one existing test passes the non-empty
`["com.apple.Installer"]` set, and one test passes the in-memory
`excludedDataProvider`. This makes all non-provider tests independent of the
user's actual Dock contents.

- [x] **Step 3: Run the rewritten suite and confirm interface RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter AppScannerTests
```

Expected: compilation fails because `parseExcludedBundleIDs(from:)` and the
`excludedDataProvider` initializer parameter do not exist. Stop if the new
tests are not discovered after the production interface is added; a zero-match
or a signal from the deleted host-writing path is not valid RED.

- [x] **Step 4: Add the read-only provider and pure parser**

Replace the coupled loader with:

```swift
typealias ExcludedDataProvider = @Sendable () -> Data?

init(
    fileSystemService: FileSystemService,
    excludedBundleIds: Set<String>? = nil,
    excludedDataProvider: @escaping ExcludedDataProvider = AppScanner.systemExcludedData
) {
    self.fileSystemService = fileSystemService
    self.excludedBundleIds = excludedBundleIds
        ?? Self.parseExcludedBundleIDs(from: excludedDataProvider())
}

static func systemExcludedData() -> Data? {
    let path = NSHomeDirectory()
        + "/Library/Application Support/Dock/LaunchPadLayout.plist"
    return FileManager.default.contents(atPath: path)
}

static func parseExcludedBundleIDs(from data: Data?) -> Set<String> {
    guard let data,
          let propertyList = try? PropertyListSerialization.propertyList(
              from: data,
              format: nil
          ),
          let root = propertyList as? [String: Any],
          let pages = root["pages"] as? [[String: Any]] else {
        return []
    }

    var result = Set<String>()
    for page in pages {
        guard let items = page["items"] as? [[String: Any]] else {
            continue
        }
        for item in items {
            guard let id = item["bundleid"] as? String,
                  let visible = item["visible"] as? Bool,
                  visible == false else {
                continue
            }
            result.insert(id)
        }
    }
    return result
}
```

Do not add a writable path injection, a temporary HOME override or filesystem
backup logic. The provider returns data only; the parser owns no filesystem.

- [x] **Step 5: Run focused, static and full termination gates**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter '^LaunchPadTests\.AppScannerTests/'

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter AppScannerTests

! rg -n "backup_test|createDirectory|removeItem|moveItem|data.write|try!" \
  Tests/LaunchPadTests/Services/AppScannerTests.swift
test "$(sed -n '1,/^@Suite("AppScanner 首次启动分页")/p' \
  Tests/LaunchPadTests/Services/AppScannerTests.swift | \
  rg -c '^\s*@Test')" -eq 13
test "$(rg -c 'excludedBundleIds: \[\]' \
  Tests/LaunchPadTests/Services/AppScannerTests.swift)" -eq 20
test "$(rg -c 'excludedBundleIds: \["com.apple.Installer"\]' \
  Tests/LaunchPadTests/Services/AppScannerTests.swift)" -eq 1
test "$(rg -c 'excludedDataProvider:' \
  Tests/LaunchPadTests/Services/AppScannerTests.swift)" -eq 1

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel
```

Expected: the qualified focused filter runs 13 tests in one suite and exits 0.
The unqualified `--filter AppScannerTests` is a substring match in this
toolchain and is retained only as an adjacent regression command; it runs 27
tests in three suites.
The full command completes both summaries with no signal or Dock write: XCTest
`205 tests / 2 skips / 5 registered failures`; Swift Testing
`703 tests / 48 suites / 4 registered issues`. Stop on any new ID, count
increase, missing summary or residual process.

- [x] **Step 6: Review, commit and re-run the focused suite**

Review all parser branches, explicit-list precedence and every AppScanner test
initializer. Review the task range `fe947af..HEAD` separately, then the full
Task 3R-A-through-3R-C/3M aggregate `5b4cf0a..HEAD`. Then commit only:

```bash
git add Sources/LaunchPad/Services/AppScanner.swift \
  Tests/LaunchPadTests/Services/AppScannerTests.swift
git commit -m "fix: isolate launchpad exclusion parsing"
```

After commit, re-run the 13-test focused command and record exact commands,
summaries and commit range in `.superpowers/sdd/task-3r-c-review.md`.

---

### Task 3M: Stabilize Animation Fixtures and Migrate ViewLayer 56/56

**Files:**
- Modify: `Tests/LaunchPadTests/Views/ViewLayerTests.swift:1-791`
- Create: `docs/superpowers/reports/2026-07-21-task-3m-view-layer-migration.md`
- Create: `.superpowers/sdd/task-3m-review.md`

**Interfaces:**
- Produces: six Swift Testing suites, 56 one-to-one tests, zero legacy framework symbols and no production diff.
- Actor rule: `AnimationRunnerTests`, `EmptyStateViewTests`, `SearchBarTests`, `AppGridFlowLayoutTests` and `PageControlViewTests` are suite-level `@MainActor`; `LayoutPersistenceTests` remains a value suite.
- Preserves: all 9 source `accuracy: 0.5` call sites as explicit
  `abs(actual - expected) <= 0.5` assertions. One call site is inside the
  row-major helper and intentionally executes once for every non-leading item;
  migration equivalence is audited by source call site, not dynamic invocation
  count.

- [x] **Step 1: Capture the 56-test baseline and current static residue**

```bash
cat > /tmp/task-3m-id-map.tsv <<'EOF'
AnimationRunnerTests testAnimate_normalMotion_callsNormal animate_normalMotion_callsNormal
AnimationRunnerTests testAnimate_reduceMotion_callsReduced animate_reduceMotion_callsReduced
AnimationRunnerTests testRun_normalMotion_callsBlock run_normalMotion_callsBlock
AnimationRunnerTests testRun_reduceMotion_fadeFallback_callsBlock run_reduceMotion_fadeFallback_callsBlock
AnimationRunnerTests testRun_reduceMotion_scalePulseFallback_callsBlock run_reduceMotion_scalePulseFallback_callsBlock
AnimationRunnerTests testRun_reduceMotion_skipsBlock run_reduceMotion_skipsBlock
LayoutPersistenceTests testLoadLayout_emptyStorage_returnsEmptyLayout loadLayout_emptyStorage_returnsEmptyLayout
LayoutPersistenceTests testLoadLayout_withPages_returnsCorrectStructure loadLayout_withPages_returnsCorrectStructure
LayoutPersistenceTests testSaveLayout_callsUpdateForEachItem saveLayout_callsUpdateForEachItem
LayoutPersistenceTests testSaveLayout_emptyList_doesNotCallUpdate saveLayout_emptyList_doesNotCallUpdate
LayoutPersistenceTests testSaveLayout_propagatesError saveLayout_propagatesError
EmptyStateViewTests testEmptyStateView_hide_animated_completionHidesView emptyStateView_hide_animated_completionHidesView
EmptyStateViewTests testEmptyStateView_hide_animated_doesNotCrash emptyStateView_hide_animated_doesNotCrash
EmptyStateViewTests testEmptyStateView_hide_hides emptyStateView_hide_hides
EmptyStateViewTests testEmptyStateView_init_doesNotCrash emptyStateView_init_doesNotCrash
EmptyStateViewTests testEmptyStateView_initCoder_producesValidInstance emptyStateView_initCoder_producesValidInstance
EmptyStateViewTests testEmptyStateView_show_animated_doesNotCrash emptyStateView_show_animated_doesNotCrash
EmptyStateViewTests testEmptyStateView_show_hide_multipleTimes emptyStateView_show_hide_multipleTimes
EmptyStateViewTests testEmptyStateView_show_unhides emptyStateView_show_unhides
SearchBarTests testSearchBar_clearAndFocus_resetsStringValue searchBar_clearAndFocus_resetsStringValue
SearchBarTests testSearchBar_controlTextDidChange_callsCallback searchBar_controlTextDidChange_callsCallback
SearchBarTests testSearchBar_hide_animated_completionHidesView searchBar_hide_animated_completionHidesView
SearchBarTests testSearchBar_hide_animated_doesNotCrash searchBar_hide_animated_doesNotCrash
SearchBarTests testSearchBar_hide_hides searchBar_hide_hides
SearchBarTests testSearchBar_hide_withoutShow_isNoOp searchBar_hide_withoutShow_isNoOp
SearchBarTests testSearchBar_init_doesNotCrash searchBar_init_doesNotCrash
SearchBarTests testSearchBar_initCoder_producesValidInstance searchBar_initCoder_producesValidInstance
SearchBarTests testSearchBar_onQueryChanged_callback searchBar_onQueryChanged_callback
SearchBarTests testSearchBar_searchFieldDidEndSearching_callsCallback searchBar_searchFieldDidEndSearching_callsCallback
SearchBarTests testSearchBar_searchFieldDidStartSearching_callsCallback searchBar_searchFieldDidStartSearching_callsCallback
SearchBarTests testSearchBar_show_animated_doesNotCrash searchBar_show_animated_doesNotCrash
SearchBarTests testSearchBar_show_calledTwice_secondCallIsNoOp searchBar_show_calledTwice_secondCallIsNoOp
SearchBarTests testSearchBar_show_unhides searchBar_show_unhides
AppGridFlowLayoutTests testCompatibilityMetricsStayBoundToClipViewportAcrossPrepares compatibilityMetricsStayBoundToClipViewportAcrossPrepares
AppGridFlowLayoutTests testDocumentFrameTracksPagedContentWidthAndCanShrink documentFrameTracksPagedContentWidthAndCanShrink
AppGridFlowLayoutTests testPartialLastPageStartsAtTopLeftSlot partialLastPageStartsAtTopLeftSlot
AppGridFlowLayoutTests testRowMajorAttributesUseTwoThreeAndFiveRowsWithoutOverlap rowMajorAttributesUseTwoThreeAndFiveRowsWithoutOverlap
AppGridFlowLayoutTests testSnapUsesRealSectionCountAndConfiguredPageWidth snapUsesRealSectionCountAndConfiguredPageWidth
AppGridFlowLayoutTests testSupplementaryRequestIsNotRepositionedAsAnItem supplementaryRequestIsNotRepositionedAsAnItem
AppGridFlowLayoutTests testTwoAndThreeSectionOriginsDifferByPageWidth twoAndThreeSectionOriginsDifferByPageWidth
PageControlViewTests testPageControlView_accessibilityLabel_isPageIndicator pageControlView_accessibilityLabel_isPageIndicator
PageControlViewTests testPageControlView_accessibilityRole_isGroup pageControlView_accessibilityRole_isGroup
PageControlViewTests testPageControlView_draw_withActiveDot_doesNotCrash pageControlView_draw_withActiveDot_doesNotCrash
PageControlViewTests testPageControlView_draw_withPages_doesNotCrash pageControlView_draw_withPages_doesNotCrash
PageControlViewTests testPageControlView_draw_zeroPages_doesNotCrash pageControlView_draw_zeroPages_doesNotCrash
PageControlViewTests testPageControlView_init_doesNotCrash pageControlView_init_doesNotCrash
PageControlViewTests testPageControlView_initCoder_producesValidInstance pageControlView_initCoder_producesValidInstance
PageControlViewTests testPageControlView_intrinsicContentSize_multiplePages pageControlView_intrinsicContentSize_multiplePages
PageControlViewTests testPageControlView_intrinsicContentSize_singlePage pageControlView_intrinsicContentSize_singlePage
PageControlViewTests testPageControlView_intrinsicContentSize_zeroPages pageControlView_intrinsicContentSize_zeroPages
PageControlViewTests testPageControlView_mouseDown_onDot_selectsPage pageControlView_mouseDown_onDot_selectsPage
PageControlViewTests testPageControlView_mouseDown_outsideDots_doesNotSelect pageControlView_mouseDown_outsideDots_doesNotSelect
PageControlViewTests testPageControlView_mouseDown_zeroPages_doesNotCrash pageControlView_mouseDown_zeroPages_doesNotCrash
PageControlViewTests testPageControlView_onDotSelected_isSettable pageControlView_onDotSelected_isSettable
PageControlViewTests testPageControlView_update_withMultiplePages_isVisible pageControlView_update_withMultiplePages_isVisible
PageControlViewTests testPageControlView_update_withSinglePage_isHidden pageControlView_update_withSinglePage_isHidden
EOF

awk '{ print "LaunchPadTests." $1 "/" $2 }' /tmp/task-3m-id-map.tsv | \
  LC_ALL=C sort > /tmp/task-3m-expected-before.txt
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(AnimationRunnerTests|LayoutPersistenceTests|EmptyStateViewTests|SearchBarTests|AppGridFlowLayoutTests|PageControlViewTests)/' | \
  LC_ALL=C sort > /tmp/task-3m-actual-before.txt
test "$(wc -l < /tmp/task-3m-id-map.tsv)" -eq 56
test "$(wc -l < /tmp/task-3m-actual-before.txt)" -eq 56
diff -u /tmp/task-3m-expected-before.txt /tmp/task-3m-actual-before.txt
test "$(rg -c '^\s+func test' Tests/LaunchPadTests/Views/ViewLayerTests.swift)" -eq 56
rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:' \
  Tests/LaunchPadTests/Views/ViewLayerTests.swift
```

Expected: the canonical map, discovery set and method scan each identify exactly
56 tests; `diff -u` exits 0, proving every qualified XCTest ID matches the
canonical set; the static scan records the legacy symbols that the migration
must remove.

- [x] **Step 2: Fix the SearchBar headless animation fixture before migration**

Replace the wait-based test, still in its existing framework for this isolated fixture commit, with:

```swift
func testSearchBar_hide_animated_completionHidesView() {
    let bar = SearchBar()
    bar.show(animated: false)
    var completionRan = false
    bar.hideCompletionRunner = { completion in
        completionRan = true
        completion()
    }

    bar.hide(animated: true)

    XCTAssertTrue(completionRan)
    XCTAssertTrue(bar.isHidden)
}
```

Run the exact test and commit only the fixture:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter SearchBarTests/testSearchBar_hide_animated_completionHidesView
git add Tests/LaunchPadTests/Views/ViewLayerTests.swift
git commit -m "test: make search bar hide completion deterministic"
```

Expected: one test passes without a fixed wait.

- [x] **Step 3: Perform the full-file pure migration with no production diff**

Use this structure:

```swift
import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor @Suite("AnimationRunner") struct AnimationRunnerTests { /* 6 tests */ }
@Suite("LayoutPersistence") struct LayoutPersistenceTests { /* 5 tests */ }
@MainActor @Suite("EmptyStateView") struct EmptyStateViewTests { /* 8 tests */ }
@MainActor @Suite("SearchBar") struct SearchBarTests { /* 14 tests */ }
@MainActor @Suite("显式 row-major 分页网格") struct AppGridFlowLayoutTests { /* 7 tests */ }
@MainActor @Suite("PageControlView") struct PageControlViewTests { /* 16 tests */ }
#endif
```

The comments above describe counts only; the implementation commit must contain all original bodies. Convert truth/equality/nil assertions to `#expect`, unwraps to `try #require`, typed errors to `#expect(throws: TestError.self)`, and identity assertions to `===`. The row helper becomes:

```swift
private func expectRowMajor(
    attributes: [NSCollectionViewLayoutAttributes],
    columns: Int,
    expectedRows: Int
) throws {
    let indexed = try attributes.map { attribute in
        (
            item: try #require(attribute.indexPath).item,
            attributes: attribute
        )
    }
    let sorted = indexed.sorted { $0.item < $1.item }
    #expect(Set(sorted.map { $0.attributes.frame.minY.rounded() }).count == expectedRows)
    for (index, entry) in sorted.enumerated() {
        let row = index / columns
        let column = index % columns
        #expect(entry.item == index)
        if column > 0 {
            #expect(abs(
                entry.attributes.frame.minY
                    - sorted[row * columns].attributes.frame.minY
            ) <= 0.5)
        }
    }
}
```

Every caller uses `try expectRowMajor(...)`; no migrated test in this file may
force-unwrap `indexPath`.

Both EmptyState and SearchBar animated-hide cases inject `hideCompletionRunner = { $0() }`; tests that verify execution also set a Boolean before invoking completion. Page mouse tests require a real optional event with `try #require`; x=50 in width 100 selects page 1, x=5 in width 200 selects nothing, and the zero-page event leaves callback count zero.

Create the migration report with 56 explicit rows, using
`/tmp/task-3m-id-map.tsv` as the canonical old/new ID set. Each report row
records the exact qualified old and new IDs, assertion equivalence or
strengthening, actor placement, fixture behavior and wait cleanup. The report
must expand every map row; citing the naming rule alone is not sufficient.

- [x] **Step 4: Run migration equivalence, adjacent geometry and static gates**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AnimationRunnerTests|LayoutPersistenceTests|EmptyStateViewTests|SearchBarTests|AppGridFlowLayoutTests|PageControlViewTests|PageScrollViewTests'

awk '{ print "LaunchPadTests." $1 "/" $3 "()" }' /tmp/task-3m-id-map.tsv | \
  LC_ALL=C sort > /tmp/task-3m-expected-after.txt
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(AnimationRunnerTests|LayoutPersistenceTests|EmptyStateViewTests|SearchBarTests|AppGridFlowLayoutTests|PageControlViewTests)/' | \
  LC_ALL=C sort > /tmp/task-3m-actual-after.txt
test "$(wc -l < /tmp/task-3m-actual-after.txt)" -eq 56
diff -u /tmp/task-3m-expected-after.txt /tmp/task-3m-actual-after.txt

! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:' \
  Tests/LaunchPadTests/Views/ViewLayerTests.swift
```

Expected: the six migrated suites discover exactly 56 tests, `diff -u` proves
every qualified Swift Testing ID matches the canonical set, all focused and
adjacent tests pass, and the static scan prints nothing.

- [x] **Step 5: Review migration and commit separately**

The migration reviewer checks all 56 report rows, all 9 tolerance call sites
(including the row-major helper call site), actor placement and a
production-empty diff. Then commit:

```bash
git add Tests/LaunchPadTests/Views/ViewLayerTests.swift \
  docs/superpowers/reports/2026-07-21-task-3m-view-layer-migration.md
git commit -m "test: migrate view layer suites to Swift Testing"
```

Finally review the aggregate range from Task 3R-A base through Task 3M head and record the exact commits and commands in `.superpowers/sdd/task-3m-review.md`.

---

### Task 4: Finish Grid Metrics and Replace the Self-delegate with an Interaction Coordinator

**Files:**
- Modify: `Sources/LaunchPad/Views/AppIconCell.swift:19-20,192-218`
- Modify: `Sources/LaunchPad/Views/FolderCell.swift:24-26,63-152`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift:25-45,99-205,209-282`
- Create: `Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:13-32,117-128,209-225`
- Modify: `Sources/LaunchPad/Views/DiffableDataSourceBuilder.swift:8-49`
- Modify: `Tests/LaunchPadTests/Views/AppIconCellTests.swift`
- Modify: `Tests/LaunchPadTests/Views/FolderCellTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Create: `Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift`
- Modify: `docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md`
- Create: `scripts/run-with-timeout.sh`

**Interfaces:**
- Consumes: Task 1 `GridMetrics`, Task 3 layout API, Task 3M's full-file migration rule, Task 3R-B's isolated process boundaries and the approved `2026-07-22-app-grid-interaction-coordinator-design.md` ownership contract.
- Produces: four fully migrated Swift Testing files (128 one-to-one mappings), deterministic workspace/drag inputs, exact cell reconfiguration, section-aware accessibility, stable-ID programmatic selection, authoritative paged-search snapshots and an externally owned main-grid delegate.
- Produces for Tasks 5, 16, 18 and 19: `AppGridInteractionCoordinator`, `AppGridInteractionHosting`, non-optional `onSelectionChanged: ((PageItem) -> Void)?`, `onItemActivated`, injectable coordinator-owned pasteboard reader and a grid host with no delegate/business callbacks.
- Produces for Tasks 22 and 23: executable `scripts/run-with-timeout.sh SECONDS -- COMMAND [ARG...]`, the only process-group supervisor implementation in the repository.

**Confirmed Task 4 execution rules:**

- The following six commits are the completed, reviewed Task 4 baseline and must
  not be replayed or amended: `29998af`, `47c5902`, `1de5594`, `d7073d4`,
  `f804ef9`, `b169539`. They cover fixture isolation, all four XCTest migrations
  and the cell-metrics slice. The remaining steps start at the Grid RED slice.
- Commit `29998af` temporarily placed `pasteboardUUIDReader` on the grid to make
  the historical drag fixtures deterministic. The remaining coordinator slice
  migrates that dependency and every interaction test to the coordinator, then
  deletes the grid property in the same Task. It is not a downstream API.
- `LaunchPadViewController` strongly owns one coordinator for its current grid;
  AppKit weakly references the coordinator as delegate; the coordinator weakly
  references its host and strongly owns the existing `DragController`.
- `AppGridCollectionView` must not conform to `NSCollectionViewDelegate`, assign
  `delegate = self`, retain a proxy, or expose `onItemSelected`, grid-level
  `onSelectionChanged`, `dragController` or `pasteboardUUIDReader` after GREEN.
- `onSelectionChanged` has non-optional `PageItem` payload and fires before
  `onItemActivated` for a valid mouse selection. Empty/stale selection and every
  programmatic `selectItem(id:)` path emit no coordinator output.
- `selectItem(id:)` clears nil/unknown IDs with
  `deselectItems(at: selectionIndexPaths)`, never `deselectAll`, because AppKit
  documents that the latter notifies the delegate.
- The focused coordinator suite has two independent time gates:
  `ContinuousClock` always asserts each returning hot-loop regression is `< 1s`;
  the shared watchdog runs the focused process with a hard 30-second limit.

- `makeSUT()` does not install default `GridMetrics`. Tests that exercise
  entrance animation or accessibility rows explicitly call
  `applyGridMetrics(_:)`; this preserves the observable `gridMetrics == nil`
  guard branch.
- `AppIconCell` uses these exact narrow boundaries, all defaulted to the
  existing production sources:

```swift
internal var workspaceNotificationCenter: NotificationCenter =
    NSWorkspace.shared.notificationCenter
internal var runningApplicationProvider: () -> [NSRunningApplication] = {
    NSWorkspace.shared.runningApplications
}
internal var notificationBundleIDReader: (Notification) -> String? = {
    notification in
    let application = notification.userInfo?[
        NSWorkspace.applicationUserInfoKey
    ] as? NSRunningApplication
    return application?.bundleIdentifier
}
```

  Registration and removal must use the same injected center. Each test owns a
  local center and calls `prepareForReuse()` from `defer`; tests never post to
  `NSWorkspace.shared.notificationCenter`.
- Migration report IDs use the discovery format exactly. Example row:
  `LaunchPadTests.AppIconCellTests/testInit_loadsView` ->
  `LaunchPadTests.AppIconCellTests/init_loadsView()`.
- The 13 behavior tests execute as three compileable TDD feature slices:
  Cell `2`, Grid `9`, Search `2`. For each slice, add only that slice's tests,
  prove its exact declarations exist once, run the compile/behavior RED, add
  the minimal production implementation, then prove its qualified IDs exist
  once and run the slice plus adjacent suites GREEN before commit. Do not
  create one commit that leaves tests referring to missing interfaces.
- `accessibilityRows()` returns an empty array while `gridMetrics` is nil.
  Section-aware accessibility tests explicitly apply metrics before reload.
- Folder rows retain `bottomAnchor`, so their inward inset uses a negative
  constant. Name the positive distance `bottomInset`, assign
  `constraint.constant = -bottomInset`, and test both the negative sign and the
  exact inset before asserting final bounded, distinct, non-overlapping frames.

- [x] **Step 1: Record the exact 128-test baseline and reproduce all five existing outcomes**

Run the four suites before editing:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppIconCellTests|FolderCellTests|AppGridCollectionViewTests|DiffableDataSourceBuilderTests'

swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(AppIconCellTests|FolderCellTests|AppGridCollectionViewTests|DiffableDataSourceBuilderTests)/'
```

Expected baseline: exactly 128 discovered tests: AppIconCell 26, FolderCell 20, AppGridCollectionView 71 and DiffableDataSourceBuilder 11. The run reports exactly three failures in the AppGrid `acceptDrop` group/reorder/extract paths and exactly two skips in AppIconCell activation/deactivation. Record all five IDs and their current assertion/skip reason in `.superpowers/sdd/task-4-baseline.md`; this ledger is diagnostic evidence, never a whitelist.

- [x] **Step 2: Fix the three false pasteboard fixtures and two workspace skips before migration**

Add the narrow read boundary to `AppGridCollectionView`:

```swift
internal var pasteboardUUIDReader: (NSPasteboard) -> String? = {
    $0.string(forType: .string)
}
```

All source writer serialization tests continue to inspect a real `NSPasteboardItem`. Validation/acceptance extraction calls `pasteboardUUIDReader(draggingInfo.draggingPasteboard)`. The three previously failing tests inject the session UUID; missing/malformed branches inject nil or an invalid value. Strengthen the fixture matrix to prove group source, missing source, reorder target and missing target branches reached the callback or rejection expected by production.

In `AppIconCell`, inject a test-local `NotificationCenter`, `runningApplicationProvider` and notification bundle reader. Each activation/deactivation test owns a local center, uses `defer` for exact observer cleanup, supplies a deterministic running app/bundle ID and replaces both skips with real assertions. No test posts to `NSWorkspace.shared.notificationCenter`.

Run the same focused command. Expected: 128 pass, 0 fail, 0 skip. Commit only this existing-failure repair:

```bash
git add Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppIconCell.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift
git commit -m "fix: isolate cell workspace and drag inputs"
```

- [x] **Step 3: Migrate AppIconCellTests 26/26 with a production-empty diff**

Replace the class and lifecycle with a suite-level `@MainActor @Suite("AppIconCell") struct AppIconCellTests`. Every test constructs its own cell, center and dependency closures; convert assertions to `#expect`/`try #require` and keep exact identity/equality semantics. Create 26 explicit mapping rows in `docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md` using the confirmed discovery-ID format for both old and new IDs, then run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter AppIconCellTests
! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:' \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift
git diff --exit-code HEAD -- Sources
git add Tests/LaunchPadTests/Views/AppIconCellTests.swift \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md
git commit -m "test: migrate app icon cell tests to Swift Testing"
```

Expected: exactly 26 tests pass, no skip, static scan empty and no production diff.

- [x] **Step 4: Migrate FolderCellTests 20/20 with all tolerances preserved**

Use suite-level `@MainActor`. Convert every old method one-to-one, preserve every frame/constraint assertion, and write all 20 rows to the same report. Every former `accuracy:` assertion becomes `#expect(abs(actual - expected) <= originalTolerance)`.

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter FolderCellTests
! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:|accuracy:' \
  Tests/LaunchPadTests/Views/FolderCellTests.swift
git diff --exit-code HEAD -- Sources
git add Tests/LaunchPadTests/Views/FolderCellTests.swift \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md
git commit -m "test: migrate folder cell tests to Swift Testing"
```

Expected: exactly 20 tests pass and the report now has 46 mapping rows.

- [x] **Step 5: Migrate AppGridCollectionViewTests 71/71 without real pasteboard reads**

Use suite-level `@MainActor`; replace shared IUO setup with `makeSUT()` returning a fresh collection view and owned dependencies. Writer tests inspect `NSPasteboardItem`; every validation/acceptance test injects `pasteboardUUIDReader`. Convert the file's four former tolerance assertions to exact `abs` comparisons and add 71 mapping rows.

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter AppGridCollectionViewTests
! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:|accuracy:' \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift
git diff --exit-code HEAD -- Sources
git add Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md
git commit -m "test: migrate app grid tests to Swift Testing"
```

Expected: exactly 71 tests pass; the report has 117 rows.

- [x] **Step 6: Migrate DiffableDataSourceBuilderTests 11/11 and audit 128 mappings**

This is a plain `@Suite` unless an individual test actually creates AppKit UI. Convert all 11 methods, append the 11 rows, and make the report contain columns for old discovery ID, new discovery ID, assertion equivalence/strengthening, actor, fixture and cleanup. The naming rule is removal of leading `test` followed by lowercasing the next character; the report must list every mapping rather than relying on the rule.

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter DiffableDataSourceBuilderTests
! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:|accuracy:' \
  Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift
test "$(rg -c '^\| `LaunchPadTests\.(AppIconCellTests|FolderCellTests|AppGridCollectionViewTests|DiffableDataSourceBuilderTests)/test[^`]+` \|' \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md)" -eq 128
git diff --exit-code HEAD -- Sources
git add Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md
git commit -m "test: migrate diffable builder tests to Swift Testing"
```

Expected: 11 tests pass, all four files are free of legacy symbols, the report has exactly 128 data rows plus header/separator, and all four migration commits have an empty production diff.

- [x] **Step 7: Prepare the remaining Grid, coordinator and Search RED slices**

The declaration inventory below is authoritative, but add and execute it in
the confirmed compileable order rather than as one uncompilable RED commit:

1. Cell slice: the AppIcon and Folder declarations (`2`) is complete in
   `b169539`.
2. Grid slice: the AppGrid declarations (`8`).
3. Coordinator slice: migrate every existing interaction test and add the
   branch/lifecycle/hot-loop matrix from Step 11.
4. Search slice: the DiffableDataSourceBuilder declarations (`2`).

For each slice, add these exact assertions to the already migrated suites;
never reintroduce the old framework. Run the corresponding Step 8 discovery
and RED gate before adding that slice's production interface from Steps 9-10.
The read-only observability properties prevent tests from reaching into private
constraints:

The complete declaration inventory is authoritative; Step 8 must statically
verify every declaration before its RED run, then dynamically discover the
same 13 qualified IDs after their owning slice compiles GREEN:

| Suite | Exact Swift Testing function | Required behavioral proof |
|---|---|---|
| `AppIconCellTests` | `appIconCellReconfiguresBothConstraints` | 96pt reconfiguration updates width and height constraints |
| `FolderCellTests` | `folderCellReconfiguresEntireThumbnailGrid` | all nine 96pt-grid frames are bounded, distinct and non-overlapping |
| `AppGridCollectionViewTests` | `legacyUpdateLayoutUsesBothClipAxes` | compatibility API reads both valid clip-view axes |
| `AppGridCollectionViewTests` | `legacyUpdateLayoutFallsBackOnlyForInvalidClipAxes` | each invalid axis falls back independently |
| `AppGridCollectionViewTests` | `applyGridMetricsReconfiguresVisibleAppAndFolderCells` | app and folder cells receive the same new icon size |
| `AppGridCollectionViewTests` | `reloadReconfigureItemsRefreshesUnchangedVisibleIcon` | unchanged diffable identity reloads its visible content |
| `AppGridCollectionViewTests` | `buildAccessibilityRowsPreservesOneThenTwoItemSections` | section sizes `[1, 2]` remain `[1, 2]`, with view identity preserved |
| `AppGridCollectionViewTests` | `accessibilityRowsUsesRealSnapshotSections` | outer accessibility API uses real snapshot section boundaries |
| `AppGridCollectionViewTests` | `stableIDSelectionUpdatesActualSelectionIndexPaths` | stable ID resolves across sections and mutates AppKit selection state |
| `AppGridCollectionViewTests` | `nilAndUnknownStableIDsClearActualSelection` | nil and unknown IDs both clear AppKit selection state |
| `DiffableDataSourceBuilderTests` | `searchResultPagesAreAuthoritative` | supplied pages and item order override flat search results exactly |
| `DiffableDataSourceBuilderTests` | `nilSearchResultPagesUsesLegacySearchSection` | nil pages preserve the single legacy `.search` section |

```swift
@Test("AppIconCell 重新配置 96pt 时同步两个尺寸约束")
func appIconCellReconfiguresBothConstraints() {
    let cell = AppIconCell()
    _ = cell.view
    cell.configure(
        item: TestDataFactory.makePageItem(id: 1),
        icon: NSImage(size: NSSize(width: 64, height: 64)),
        iconSize: 96
    )
    #expect(cell.configuredIconSize == 96)
    #expect(cell.configuredIconConstraintSize == CGSize(width: 96, height: 96))
}

@Test("FolderCell 重新配置 96pt 时同步九个缩略图及位置")
func folderCellReconfiguresEntireThumbnailGrid() {
    let cell = FolderCell()
    _ = cell.view
    cell.configure(
        item: TestDataFactory.makePageItem(
            id: 2, type: .group,
            group: TestDataFactory.makeGroupInfo(id: 2)
        ),
        childIcons: [],
        iconSize: 96
    )
    #expect(cell.configuredIconSize == 96)
    #expect(cell.configuredThumbnailGridSize == CGSize(width: 96, height: 96))
    cell.view.layoutSubtreeIfNeeded()
    let frames = cell.configuredThumbnailFrames
    let bounds = cell.configuredThumbnailGridBounds
    #expect(frames.count == 9)
    #expect(frames.allSatisfy { bounds.contains($0) })
    for first in frames.indices {
        for second in frames.indices where first < second {
            #expect(!frames[first].intersects(frames[second]))
        }
    }
}
```

Use this exact section-aware input in the accessibility test:

```swift
let indexPaths = [
    [IndexPath(item: 0, section: 0)],
    [IndexPath(item: 0, section: 1), IndexPath(item: 1, section: 1)],
]
let rows = collectionView.buildAccessibilityRows(
    itemIndexPathsBySection: indexPaths,
    columns: 2
)
#expect(rows.map(\.count) == [1, 2])
#expect(requestedIndexPaths == indexPaths.flatMap { $0 })

let noRows = collectionView.buildAccessibilityRows(
    itemIndexPathsBySection: indexPaths,
    columns: 0
)
#expect(noRows.isEmpty)
```

Add stable selection and paged-search tests with exact section assertions:

```swift
@Test("稳定 ID 在重新分段后解析并更新真实 AppKit selection")
@MainActor
func stableIDSelectionUpdatesActualSelectionIndexPaths() throws {
    let collectionView = AppGridCollectionView(frame: NSRect(
        x: 0, y: 0, width: 800, height: 600
    ))
    let items = TestDataFactory.makeAppItems(count: 5)
    collectionView.reload(
        pages: [Array(items.prefix(2)), Array(items.dropFirst(2))],
        searchResults: nil,
        searchQuery: nil,
        animateEntrance: false
    )

    let selected = try #require(collectionView.selectItem(id: items[4].id))
    #expect(selected == IndexPath(item: 2, section: 1))
    #expect(collectionView.selectionIndexPaths == [selected])
}

@Test("paged search contents 是权威输入并保持精确顺序")
func searchResultPagesAreAuthoritative() {
    let items = TestDataFactory.makeAppItems(count: 9)
    let snapshot = DiffableDataSourceBuilder.buildSnapshot(
        pages: [],
        searchResults: items,
        searchQuery: "app",
        searchResultPages: [
            Array(items[0..<4]), Array(items[4..<8]), Array(items[8..<9]),
        ]
    )

    #expect(snapshot.sectionIdentifiers == [
        .searchPage(0), .searchPage(1), .searchPage(2),
    ])
    #expect(snapshot.itemIdentifiers.map(\.id) == items.map(\.id))
}
```

Implement the other eight Grid declarations and two Search declarations in
their owning slice.
Their required-proof column is the minimum assertion contract: each
test must assert the named production state directly, not only callback count,
object existence or lack of a crash. In particular, the nil/unknown selection
test inspects `selectionIndexPaths.isEmpty`, and the legacy-search test compares
both `.search` and the exact item order. Selection callback order moves to the
coordinator suite and compares the exact two-element event array there.

- [x] **Step 8: Confirm each slice RED, then discover its GREEN IDs**

`swift test list` compiles the test target, so a slice whose tests refer to a
missing production interface cannot be dynamically discovered during compile
RED. For each slice, first use `rg` to prove every exact function declaration
exists once, then run only the covering suites and record the expected
interface/behavior failure. After implementing the slice, rerun the focused
suite GREEN, obtain a fresh `swift test list`, and use the qualified-ID loop for
that slice. Use these three exact inventories:

```bash
test "$(rg -n '^\s*func (appIconCellReconfiguresBothConstraints|folderCellReconfiguresEntireThumbnailGrid)\(' \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift \
  Tests/LaunchPadTests/Views/FolderCellTests.swift | wc -l | tr -d ' ')" -eq 2

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppIconCellTests|FolderCellTests'

test "$(rg -c '^\s*func (legacyUpdateLayoutUsesBothClipAxes|legacyUpdateLayoutFallsBackOnlyForInvalidClipAxes|applyGridMetricsReconfiguresVisibleAppAndFolderCells|reloadReconfigureItemsRefreshesUnchangedVisibleIcon|buildAccessibilityRowsPreservesOneThenTwoItemSections|accessibilityRowsUsesRealSnapshotSections|stableIDSelectionUpdatesActualSelectionIndexPaths|nilAndUnknownStableIDsClearActualSelection)\(' \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift)" -eq 8

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridCollectionViewTests|AppGridFlowLayoutTests'

test "$(rg -c '^\s*func (searchResultPagesAreAuthoritative|nilSearchResultPagesUsesLegacySearchSection)\(' \
  Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift)" -eq 2

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DiffableDataSourceBuilderTests|DiffableDataSourceTests'

```

Expected per slice: the completed Cell `2`, then Grid `8`, the Step 11
coordinator inventory, then Search `2` declarations exist once before
the focused command fails only for that slice's missing production interface or
behavior. After implementation, the same qualified IDs appear once and the
focused command is GREEN. Commit the current slice before adding the next
slice's tests. Across the Grid/Search records all 10 remaining IDs must be
present exactly once; coordinator IDs are checked by their own exhaustive list.
Any missing/duplicate declaration or ID, or unrelated migrated-test failure, is
a stop condition rather than valid RED evidence.

- [x] **Step 9: Add exact metrics, constraint storage and reconfiguration APIs**

Execute the AppIcon/Folder portions immediately after the Cell RED gate and
commit that slice before adding Grid tests. Execute the AppGrid metrics portion
immediately after the Grid RED gate. The existing
`animateEntrance_withInjectedProviders_runsLoopBody` fixture must explicitly
call `applyGridMetrics(_:)` before `reload`; do not install metrics in the
default `makeSUT()`.

After implementing the Cell portion, run its GREEN gate and commit immediately:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppIconCellTests|FolderCellTests'
TASK4_GREEN_LIST=$(CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
  swift test --disable-sandbox list)
while IFS= read -r id; do
  test "$(printf '%s\n' "$TASK4_GREEN_LIST" | rg -c -x -F "${id}()")" -eq 1
done <<'TASK4_CELL_GREEN_IDS'
LaunchPadTests.AppIconCellTests/appIconCellReconfiguresBothConstraints
LaunchPadTests.FolderCellTests/folderCellReconfiguresEntireThumbnailGrid
TASK4_CELL_GREEN_IDS
git add Sources/LaunchPad/Views/AppIconCell.swift \
  Sources/LaunchPad/Views/FolderCell.swift \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift \
  Tests/LaunchPadTests/Views/FolderCellTests.swift
git commit -m "fix: synchronize cell metrics"
```

In `AppGridCollectionView` replace `currentIconSize` with:

```swift
private(set) var gridMetrics: GridMetrics?

public func applyGridMetrics(_ metrics: GridMetrics) {
    guard gridMetrics != metrics else { return }
    gridMetrics = metrics
    (collectionViewLayout as? AppGridFlowLayout)?.applyGridMetrics(metrics)
    var snapshot = diffableDataSource.snapshot()
    let items = snapshot.itemIdentifiers
    if !items.isEmpty {
        snapshot.reloadItems(items)
        diffableDataSource.apply(snapshot, animatingDifferences: false)
    }
}

@available(*, deprecated, message: "Use applyGridMetrics(_:)")
public func updateLayout(screenWidth: CGFloat) {
    let clipSize = enclosingScrollView?.contentView.bounds.size ?? .zero
    let width = clipSize.width.isFinite && clipSize.width > 0
        ? clipSize.width : screenWidth
    let height = clipSize.height.isFinite && clipSize.height > 0
        ? clipSize.height : 620
    applyGridMetrics(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: width, height: height)
    ))
}
```

In `AppIconCell`, add and update these members in `configure`:

```swift
private(set) var configuredIconSize: CGFloat = 64
var configuredIconConstraintSize: CGSize {
    CGSize(
        width: iconWidthConstraint?.constant ?? 0,
        height: iconHeightConstraint?.constant ?? 0
    )
}

// At the start of configure(...iconSize:):
configuredIconSize = iconSize
iconWidthConstraint?.constant = iconSize
iconHeightConstraint?.constant = iconSize
```

In `FolderCell`, replace the fixed thumbnail constants with these stored constraints and observability properties:

```swift
private static let gridSize = 3
private static let thumbnailSpacing: CGFloat = 2
private var thumbnailGridWidthConstraint: NSLayoutConstraint?
private var thumbnailGridHeightConstraint: NSLayoutConstraint?
private var thumbnailSizeConstraints: [NSLayoutConstraint] = []
private var thumbnailLeadingConstraints: [(NSLayoutConstraint, column: Int)] = []
private var thumbnailBottomConstraints: [(NSLayoutConstraint, rowFromBottom: Int)] = []
private(set) var configuredIconSize: CGFloat = 64
var configuredThumbnailGridSize: CGSize {
    CGSize(
        width: thumbnailGridWidthConstraint?.constant ?? 0,
        height: thumbnailGridHeightConstraint?.constant ?? 0
    )
}
var configuredThumbnailSizes: [CGFloat] {
    thumbnailSizeConstraints.map(\.constant)
}
var configuredThumbnailBottomConstants: [CGFloat] {
    thumbnailBottomConstraints.map { $0.0.constant }
}
var configuredThumbnailFrames: [CGRect] {
    thumbnailImageViews.map(\.frame)
}
var configuredThumbnailGridBounds: CGRect {
    thumbnailGrid.bounds
}
```

In `loadView`, create and retain the two grid constraints before activating them:

```swift
let gridWidth = thumbnailGrid.widthAnchor.constraint(equalToConstant: 64)
let gridHeight = thumbnailGrid.heightAnchor.constraint(equalToConstant: 64)
thumbnailGridWidthConstraint = gridWidth
thumbnailGridHeightConstraint = gridHeight
NSLayoutConstraint.activate([
    thumbnailGrid.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
    thumbnailGrid.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
    gridWidth,
    gridHeight,
])
```

Replace `setupThumbnailGrid` with the complete retained-constraint implementation:

```swift
private func setupThumbnailGrid() {
    thumbnailImageViews.removeAll()
    thumbnailSizeConstraints.removeAll()
    thumbnailLeadingConstraints.removeAll()
    thumbnailBottomConstraints.removeAll()
    thumbnailGrid.subviews.forEach { $0.removeFromSuperview() }
    let thumbnailSize = (CGFloat(64) - 2 * Self.thumbnailSpacing) / 3

    for row in 0..<Self.gridSize {
        for column in 0..<Self.gridSize {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            thumbnailGrid.addSubview(imageView)
            let rowFromBottom = Self.gridSize - 1 - row
            let leading = imageView.leadingAnchor.constraint(
                equalTo: thumbnailGrid.leadingAnchor,
                constant: CGFloat(column) * (thumbnailSize + Self.thumbnailSpacing)
            )
            let bottom = imageView.bottomAnchor.constraint(
                equalTo: thumbnailGrid.bottomAnchor,
                constant: -CGFloat(rowFromBottom)
                    * (thumbnailSize + Self.thumbnailSpacing)
            )
            let width = imageView.widthAnchor.constraint(equalToConstant: thumbnailSize)
            let height = imageView.heightAnchor.constraint(equalToConstant: thumbnailSize)
            NSLayoutConstraint.activate([leading, bottom, width, height])
            thumbnailImageViews.append(imageView)
            thumbnailSizeConstraints.append(contentsOf: [width, height])
            thumbnailLeadingConstraints.append((leading, column))
            thumbnailBottomConstraints.append((bottom, rowFromBottom))
        }
    }
}
```

Change the signature to `public func configure(item: PageItem, childIcons: [NSImage], iconSize: CGFloat = 64)` and update every retained constraint:

```swift
let thumbnailSpacing: CGFloat = 2
let thumbnailSize = max(0, (iconSize - 2 * thumbnailSpacing) / 3)
configuredIconSize = iconSize
thumbnailGridWidthConstraint?.constant = iconSize
thumbnailGridHeightConstraint?.constant = iconSize
thumbnailSizeConstraints.forEach { $0.constant = thumbnailSize }
thumbnailLeadingConstraints.forEach { constraint, column in
    constraint.constant = CGFloat(column) * (thumbnailSize + thumbnailSpacing)
}
thumbnailBottomConstraints.forEach { constraint, rowFromBottom in
    let bottomInset = CGFloat(rowFromBottom)
        * (thumbnailSize + thumbnailSpacing)
    constraint.constant = -bottomInset
}
```

Pass `gridMetrics?.iconSize ?? 64` in both `.app` and `.group` cell configuration branches.

- [x] **Step 10: Make reload reconfigure existing IDs, paginate search and keep rows section-aware**

Execute the grid reload/accessibility/selection portions after the Grid RED
gate. Execute `.searchPage`, `searchResultPages` and the reload forwarding hunk
only after the Search RED gate, then commit the Search slice. This ordering
keeps every intermediate commit compileable.

After implementing only the Grid portion, run its GREEN gate and commit before
adding either Search test:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridCollectionViewTests|AppGridFlowLayoutTests'
TASK4_GREEN_LIST=$(CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
  swift test --disable-sandbox list)
while IFS= read -r id; do
  test "$(printf '%s\n' "$TASK4_GREEN_LIST" | rg -c -x -F "${id}()")" -eq 1
done <<'TASK4_GRID_GREEN_IDS'
LaunchPadTests.AppGridCollectionViewTests/legacyUpdateLayoutUsesBothClipAxes
LaunchPadTests.AppGridCollectionViewTests/legacyUpdateLayoutFallsBackOnlyForInvalidClipAxes
LaunchPadTests.AppGridCollectionViewTests/applyGridMetricsReconfiguresVisibleAppAndFolderCells
LaunchPadTests.AppGridCollectionViewTests/reloadReconfigureItemsRefreshesUnchangedVisibleIcon
LaunchPadTests.AppGridCollectionViewTests/buildAccessibilityRowsPreservesOneThenTwoItemSections
LaunchPadTests.AppGridCollectionViewTests/accessibilityRowsUsesRealSnapshotSections
LaunchPadTests.AppGridCollectionViewTests/stableIDSelectionUpdatesActualSelectionIndexPaths
LaunchPadTests.AppGridCollectionViewTests/nilAndUnknownStableIDsClearActualSelection
TASK4_GRID_GREEN_IDS
git add Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift
git commit -m "fix: synchronize grid accessibility and selection"
```

Then add the two Search tests, run their Step 8 RED gate, implement only the
Search portion, run GREEN and commit:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DiffableDataSourceBuilderTests|DiffableDataSourceTests|AppGridCollectionViewTests'
TASK4_GREEN_LIST=$(CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
  swift test --disable-sandbox list)
while IFS= read -r id; do
  test "$(printf '%s\n' "$TASK4_GREEN_LIST" | rg -c -x -F "${id}()")" -eq 1
done <<'TASK4_SEARCH_GREEN_IDS'
LaunchPadTests.DiffableDataSourceBuilderTests/searchResultPagesAreAuthoritative
LaunchPadTests.DiffableDataSourceBuilderTests/nilSearchResultPagesUsesLegacySearchSection
TASK4_SEARCH_GREEN_IDS
git add Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/DiffableDataSourceBuilder.swift \
  Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift
git commit -m "fix: paginate authoritative search snapshots"
```

Extend `Section` and `DiffableDataSourceBuilder.buildSnapshot` without removing the old single-search-section compatibility path:

```swift
public enum Section: Hashable {
    case page(Int)
    case search
    case searchPage(Int)
}

public static func buildSnapshot(
    pages: [[PageItem]],
    searchResults: [PageItem]?,
    searchQuery: String?,
    searchResultPages: [[PageItem]]? = nil
) -> NSDiffableDataSourceSnapshot<Section, PageItem> {
    var snapshot = NSDiffableDataSourceSnapshot<Section, PageItem>()
    if let results = searchResults,
       let query = searchQuery,
       !query.isEmpty {
        if let searchResultPages {
            let sections = searchResultPages.indices.map(Section.searchPage)
            snapshot.appendSections(sections)
            for (index, page) in searchResultPages.enumerated() {
                snapshot.appendItems(page, toSection: .searchPage(index))
            }
        } else {
            snapshot.appendSections([.search])
            snapshot.appendItems(results, toSection: .search)
        }
        return snapshot
    }
    let sections = pages.indices.map(Section.page)
    snapshot.appendSections(sections)
    for (index, page) in pages.enumerated() {
        snapshot.appendItems(page, toSection: .page(index))
    }
    return snapshot
}
```

Replace `reload` with:

```swift
public func reload(
    pages: [[PageItem]],
    searchResults: [PageItem]?,
    searchQuery: String?,
    searchResultPages: [[PageItem]]? = nil,
    animatingDifferences: Bool = true,
    reconfigureItems: Bool = false,
    animateEntrance: Bool = true
) {
    var snapshot = DiffableDataSourceBuilder.buildSnapshot(
        pages: pages,
        searchResults: searchResults,
        searchQuery: searchQuery,
        searchResultPages: searchResultPages
    )
    if reconfigureItems {
        let existing = Set(diffableDataSource.snapshot().itemIdentifiers)
        snapshot.reloadItems(snapshot.itemIdentifiers.filter(existing.contains))
    }
    diffableDataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    if animateEntrance { self.animateEntrance() }
}
```

Change `animateEntrance()` to `guard let columns = gridMetrics?.columns else { return }`; remove its `calculate(screenWidth:)` call. Build `accessibilityRows()` from snapshot sections and `diffableDataSource.indexPath(for:)`; when `gridMetrics` is nil, return an empty array. Then implement the row helper exactly:

```swift
func buildAccessibilityRows(
    itemIndexPathsBySection: [[IndexPath]],
    columns: Int
) -> [[Any]] {
    guard columns > 0 else { return [] }
    return itemIndexPathsBySection.flatMap { indexPaths in
        stride(from: 0, to: indexPaths.count, by: columns).compactMap { start in
            let end = min(start + columns, indexPaths.count)
            let views = indexPaths[start..<end].compactMap {
                cellViewProvider?($0) ?? item(at: $0)?.view
            }
            return views.isEmpty ? nil : views
        }
    }
}
```

Do not add a grid selection callback. Remove `onItemSelected`, the existing
grid-level `onSelectionChanged`, `dragController`, `pasteboardUUIDReader`,
`delegate = self` and the entire `NSCollectionViewDelegate` conformance only in
the coordinator GREEN commit from Step 12, so the intermediate Grid commit stays
compileable. Implement stable programmatic selection without business output:

```swift
@discardableResult
func selectItem(id: Int64?) -> IndexPath? {
    guard let id,
          let item = diffableDataSource.snapshot().itemIdentifiers.first(
            where: { $0.id == id }
          ),
          let indexPath = diffableDataSource.indexPath(for: item) else {
        deselectItems(at: selectionIndexPaths)
        return nil
    }
    selectItems(at: [indexPath], scrollPosition: [])
    return indexPath
}
```

- [x] **Step 11: Move the complete interaction matrix to a coordinator RED suite**

Create `@MainActor @Suite("AppGridInteractionCoordinator") struct
AppGridInteractionCoordinatorTests`. Its fixture returns the host, the real
`NSCollectionView`, coordinator and `DragController`; no test may recover a
coordinator from a weak AppKit delegate without also retaining it:

```swift
@MainActor
private final class InteractionHost: AppGridInteractionHosting {
    let collectionViewForDelegateInstallation = NSCollectionView()
    var itemsByPath: [IndexPath: PageItem] = [:]
    var itemsByUUID: [String: PageItem] = [:]
    var resolvedPath: IndexPath?
    var renderedImages: [IndexPath: NSImage] = [:]
    private(set) var snapshotMoves: [(PageItem, PageItem)] = []

    func pageItem(at indexPath: IndexPath) -> PageItem? {
        itemsByPath[indexPath]
    }

    func pageItem(uuid: String) -> PageItem? {
        itemsByUUID[uuid]
    }

    func resolvedIndexPath(at point: NSPoint) -> IndexPath? {
        resolvedPath
    }

    func dragImage(at indexPath: IndexPath) -> NSImage? {
        renderedImages[indexPath]
    }

    func moveSnapshotItem(_ item: PageItem, before target: PageItem) {
        snapshotMoves.append((item, target))
    }
}

@MainActor
private func makeInteractionSUT(
    reader: @escaping (NSPasteboard) -> String? = {
        $0.string(forType: .string)
    }
) -> (
    host: InteractionHost,
    collectionView: NSCollectionView,
    coordinator: AppGridInteractionCoordinator,
    dragController: DragController
) {
    let host = InteractionHost()
    host.collectionViewForDelegateInstallation.frame = NSRect(
        x: 0, y: 0, width: 800, height: 620
    )
    let dragController = DragController(scheduler: MockScheduler())
    let coordinator = AppGridInteractionCoordinator(
        dragController: dragController,
        pasteboardUUIDReader: reader
    )
    coordinator.attach(to: host)
    return (
        host,
        host.collectionViewForDelegateInstallation,
        coordinator,
        dragController
    )
}
```

Migrate the following 23 historical AppGrid interaction tests plus the pending
callback-order behavior rather than copying them. In the migration report, keep
each old discovery ID and change the new suite prefix to
`LaunchPadTests.AppGridInteractionCoordinatorTests/`; rename only where the old
name still says `onItemSelected`. Keep
`makeDragImage_returns64x64Image` in `AppGridCollectionViewTests`, because image
rendering is a host responsibility. The grid suite must no longer contain these
interaction declarations:

```text
onItemSelected_callbackIsSettable
pasteboardWriterForItemAt_appItem_writesUuid
pasteboardWriterForItemAt_groupItem_writesUuid
pasteboardWriterForItemAt_pageItem_returnsNil
validateDrop_screenEdge_returnsGeneric
validateDrop_rightEdge_returnsGeneric
validateDrop_emptyArea_returnsMove
acceptDrop_onGroupTarget_returnsTrue
acceptDrop_invalidPasteboard_returnsFalse
draggingImageForItemsAt_returnsImage
onItemSelected_triggeredViaDidSelect
onItemSelected_emptySelection_doesNotFire
resolveHoverLocation_overIcon_whenGroupAtLocation
resolveHoverLocation_empty_whenAppAtLocation
resolveHoverLocation_empty_whenResolverReturnsNil
acceptDrop_reorderSamePage_performsReorder
acceptDrop_outOfRangeTarget_returnsFalse
extractDraggedItem_validPasteboard_returnsItem
extractDraggedItem_emptyPasteboard_returnsNil
performDrop_onGroupTarget_returnsTrue
performDrop_reorderSamePage_returnsTrue
draggingImageForItemsAt_usesInjectedCellProvider
performDrop_bothItemsNotInSnapshot_noOp
selectionCallbacksPreserveChangedThenActivatedOrder
```

Add missing branch/lifecycle cases under these exact IDs. Every item in the
right column is a required direct assertion, not merely a no-crash check:

| Test ID | Exact proof |
|---|---|
| `selection_emptyAndStaleEmitNothing` | empty and unmapped index paths produce zero outputs |
| `selection_validEmitsChangedThenActivated` | exact `changed:<id>`, `activated:<id>` order |
| `selection_hasNoDeselectOutput` | coordinator implements no `didDeselectItemsAt`; programmatic clear emits nothing |
| `writer_appGroupPageAndMissing` | app/group UUID payloads; page/missing nil |
| `validation_allLocationAndStateBranches` | left/right edge, group, app, page, no path, stale path and non-dragging |
| `validation_edgePreservesDropOperationSentinel` | both edge branches leave a `.before` sentinel unchanged |
| `acceptance_allSourceAndTargetBranches` | nil/malformed/unknown source, missing target, group, ordinary move and both absent |
| `dragImage_emptyMissingAndValid` | empty set/missing image return empty; valid image is identical |
| `attach_isIdempotentAndMovesFromAToB` | repeated attach is stable; A delegate nil, B delegate coordinator |
| `detach_preservesExternalDelegateAndIsIdempotent` | externally replaced delegate survives two detach calls |
| `weakHostAndOwnerGraphReleaseWithoutCycle` | host, grid, coordinator and VC weak probes become nil as applicable |
| `hostReleaseMakesAllFiveEntrypointsSafe` | nil/false/empty/none defaults and zero output after host deallocation |
| `delegateWiringSelectionAndDragAreReal` | one selection and one writer/validation call enter through `collectionView.delegate` |
| `programmaticSelectionNeverEmitsBusinessOutput` | valid, nil and unknown stable IDs leave event list empty |

Use `#expect(collectionView.delegate === coordinator)` and
`#expect(collectionView.delegate !== collectionView)` in every real-wiring
fixture. Delegate integration calls use the retained delegate:

```swift
let delegate = try #require(collectionView.delegate)
delegate.collectionView?(
    collectionView,
    didSelectItemsAt: [IndexPath(item: 0, section: 0)]
)
let writer = delegate.collectionView?(
    collectionView,
    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
)
#expect(writer != nil)
```

The pure branch tests may call coordinator methods directly. They must not call
`grid.collectionView(grid, ...)`; that expression is a permanent static-gate
failure for the main grid.

Run RED after moving tests and adding the exact inventories:

```bash
test "$(rg -c '^\s*@Test\b' \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift)" -ge 38
! rg -n 'pasteboardWriterForItemAt|validateDrop|acceptDrop|draggingImageForItemsAt|resolveHoverLocation|extractDraggedItem|performDrop|selectionCallbacksPreserveChangedThenActivatedOrder' \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|LaunchPadViewControllerTests'
```

Expected: compile RED only because `AppGridInteractionHosting`,
`AppGridInteractionCoordinator` and VC ownership/wiring do not yet exist. A
zero-match filter, missing migrated ID or failure in an already migrated
non-interaction grid test is not valid RED.

- [x] **Step 12: Implement the host and coordinator, then delete the old grid API**

Create `Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift` with this
Task 4 interface and ownership. Task 16 extends the same protocol; it does not
replace or broaden ownership back into the grid:

```swift
import AppKit
import LaunchPadProtocols

@MainActor
protocol AppGridInteractionHosting: AnyObject {
    var collectionViewForDelegateInstallation: NSCollectionView { get }
    func pageItem(at indexPath: IndexPath) -> PageItem?
    func pageItem(uuid: String) -> PageItem?
    func resolvedIndexPath(at point: NSPoint) -> IndexPath?
    func dragImage(at indexPath: IndexPath) -> NSImage?
    func moveSnapshotItem(_ item: PageItem, before target: PageItem)
}

@MainActor
final class AppGridInteractionCoordinator: NSObject, NSCollectionViewDelegate {
    private(set) weak var host: (any AppGridInteractionHosting)?
    private weak var collectionView: NSCollectionView?
    let dragController: DragController

    var onSelectionChanged: ((PageItem) -> Void)?
    var onItemActivated: ((PageItem) -> Void)?
    var pasteboardUUIDReader: (NSPasteboard) -> String?

    init(
        dragController: DragController,
        pasteboardUUIDReader: @escaping (NSPasteboard) -> String?
    ) {
        self.dragController = dragController
        self.pasteboardUUIDReader = pasteboardUUIDReader
    }

    func attach(to host: any AppGridInteractionHosting) {
        detach()
        let collectionView = host.collectionViewForDelegateInstallation
        self.host = host
        self.collectionView = collectionView
        collectionView.delegate = self
    }

    func detach() {
        if collectionView?.delegate === self {
            collectionView?.delegate = nil
        }
        collectionView = nil
        host = nil
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard let indexPath = indexPaths.first,
              let item = host?.pageItem(at: indexPath) else { return }
        onSelectionChanged?(item)
        onItemActivated?(item)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard let item = host?.pageItem(at: indexPath),
              item.type != .page else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.uuid, forType: .string)
        return pasteboardItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard host != nil else { return [] }
        let location = draggingInfo.draggingLocation
        let edgeWidth: CGFloat = 40
        if location.x < edgeWidth
            || location.x > collectionView.bounds.width - edgeWidth {
            dragController.updateDragHover(location: .screenEdge)
            return .generic
        }
        dragController.updateDragHover(location: resolveHoverLocation(at: location))
        dropOperation.pointee = .on
        return .move
    }

    func resolveHoverLocation(at location: NSPoint) -> DragController.HoverLocation {
        guard let indexPath = host?.resolvedIndexPath(at: location),
              let item = host?.pageItem(at: indexPath),
              item.type == .group else { return .empty }
        return .overIcon(targetId: item.id)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let source = extractDraggedItem(from: draggingInfo),
              let target = host?.pageItem(at: indexPath) else { return false }
        return performDrop(draggedItem: source, targetItem: target)
    }

    func extractDraggedItem(from draggingInfo: NSDraggingInfo) -> PageItem? {
        guard let uuid = pasteboardUUIDReader(draggingInfo.draggingPasteboard)
        else { return nil }
        return host?.pageItem(uuid: uuid)
    }

    func performDrop(draggedItem: PageItem, targetItem: PageItem) -> Bool {
        if targetItem.type != .group {
            host?.moveSnapshotItem(draggedItem, before: targetItem)
        }
        dragController.handleDrop()
        return host != nil
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingImageForItemsAt indexPaths: Set<IndexPath>,
        with event: NSEvent,
        offset dragImageOffset: NSPointPointer
    ) -> NSImage {
        guard let indexPath = indexPaths.first else { return NSImage() }
        return host?.dragImage(at: indexPath) ?? NSImage()
    }
}
```

Conform `AppGridCollectionView` through a narrow host extension. Keep
`makeDragImage(from:)` as the rendering primitive and keep the current Task 4
optimistic move exactly until Task 16 removes it:

```swift
@MainActor
extension AppGridCollectionView: AppGridInteractionHosting {
    var collectionViewForDelegateInstallation: NSCollectionView { self }

    func pageItem(at indexPath: IndexPath) -> PageItem? {
        diffableDataSource.itemIdentifier(for: indexPath)
    }

    func pageItem(uuid: String) -> PageItem? {
        diffableDataSource.snapshot().itemIdentifiers.first { $0.uuid == uuid }
    }

    func resolvedIndexPath(at point: NSPoint) -> IndexPath? {
        indexPathResolver?(point) ?? indexPathForItem(at: point)
    }

    func dragImage(at indexPath: IndexPath) -> NSImage? {
        guard let cell = visibleCellProvider?(indexPath) ?? item(at: indexPath)
        else { return nil }
        return makeDragImage(from: cell.view)
    }

    func moveSnapshotItem(_ item: PageItem, before target: PageItem) {
        var snapshot = diffableDataSource.snapshot()
        guard snapshot.sectionIdentifier(containingItem: item) != nil
                || snapshot.sectionIdentifier(containingItem: target) != nil
        else { return }
        snapshot.deleteItems([item])
        snapshot.insertItems([item], beforeItem: target)
        diffableDataSource.apply(snapshot, animatingDifferences: true)
    }
}
```

Delete the old delegate extension and the four obsolete grid properties. Keep
`draggingSession(_:sourceOperationMaskFor:)` as the grid's existing
`NSDraggingSource` override; it is not collection delegate ownership.

- [x] **Step 13: Make the ViewController the sole production owner and prove lifecycle wiring**

Add the strong property and rebuild-safe installation in
`LaunchPadViewController`:

```swift
private(set) var gridInteractionCoordinator: AppGridInteractionCoordinator?

override public func loadView() {
    gridInteractionCoordinator?.detach()
    // Existing root view and subview construction remains unchanged.
    collectionView = AppGridCollectionView(frame: .zero)
    collectionView.configure(iconCache: iconCache, storage: storage)
    let coordinator = AppGridInteractionCoordinator(
        dragController: dragController,
        pasteboardUUIDReader: { $0.string(forType: .string) }
    )
    gridInteractionCoordinator = coordinator
    coordinator.attach(to: collectionView)
    // Continue the existing scroll/document-view setup.
}

private func setupCallbacks() {
    // Existing search callbacks remain unchanged.
    gridInteractionCoordinator?.onItemActivated = { [weak self] item in
        self?.handleItemSelection(item)
    }
    // Existing cell delete, page and DragController callbacks remain unchanged.
}
```

Task 4 binds only activation. Task 5 owns the first introduction of
`selectedItemID` and binds coordinator `onSelectionChanged` there. Replace all
VC tests that invoke `collectionView.onItemSelected` with retained
coordinator output or real delegate selection. Add tests for strong retention,
view rebuild A-to-B detachment and weak release probes. Expected wiring after
every rebuild is exactly:

```swift
let coordinator = try #require(sut.gridInteractionCoordinator)
let grid = try #require(firstGrid(in: sut.view))
#expect(grid.delegate === coordinator)
#expect(grid.delegate !== grid)
```

Run GREEN and commit the coordinator ownership slice separately:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|LaunchPadViewControllerTests'
! rg -n 'delegate\s*=\s*self|NSCollectionViewDelegate|onItemSelected|onSelectionChanged|dragController|pasteboardUUIDReader' \
  Sources/LaunchPad/Views/AppGridCollectionView.swift
! rg -n 'collectionView\.collectionView\(' \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift
git add Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md
git commit -m "fix: externalize app grid interactions"
```

- [x] **Step 14: Add the macOS 26 hot-loop regression and shared process watchdog**

Add a real `NSWindow + NSScrollView + AppGridCollectionView` test to the
coordinator suite. Load one app and one folder, attach the coordinator before
the first reload, then execute initial metrics, reload/display, updated metrics,
real delegate selection, programmatic clear and one second reload/selection
cycle. Always assert the returning path against `ContinuousClock`:

```swift
@Test("macOS 26 reload display metrics selection cycle converges under one second")
func appKitReloadDisplaySelectionCycleConverges() throws {
    let clock = ContinuousClock()
    let start = clock.now
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let scrollView = NSScrollView(frame: window.contentView!.bounds)
    let grid = AppGridCollectionView(frame: scrollView.contentView.bounds)
    let coordinator = AppGridInteractionCoordinator(
        dragController: DragController(scheduler: MockScheduler()),
        pasteboardUUIDReader: { _ in nil }
    )
    coordinator.attach(to: grid)
    scrollView.documentView = grid
    window.contentView = scrollView
    window.orderFront(nil)
    defer {
        coordinator.detach()
        window.orderOut(nil)
    }

    let app = TestDataFactory.makePageItem(id: 1, type: .app)
    let folder = TestDataFactory.makePageItem(
        id: 2,
        type: .group,
        group: TestDataFactory.makeGroupInfo(id: 2)
    )
    grid.applyGridMetrics(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 800, height: 620)
    ))
    grid.reload(
        pages: [[app, folder]], searchResults: nil, searchQuery: nil,
        animatingDifferences: false, animateEntrance: false
    )
    grid.layoutSubtreeIfNeeded()
    let updatedMetrics = GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: 800, height: 496)
    )
    grid.applyGridMetrics(updatedMetrics)
    grid.layoutSubtreeIfNeeded()
    let appCell = try #require(
        grid.item(at: IndexPath(item: 0, section: 0)) as? AppIconCell
    )
    let folderCell = try #require(
        grid.item(at: IndexPath(item: 1, section: 0)) as? FolderCell
    )
    #expect(appCell.configuredIconSize == updatedMetrics.iconSize)
    #expect(folderCell.configuredIconSize == updatedMetrics.iconSize)
    grid.delegate?.collectionView?(
        grid,
        didSelectItemsAt: [IndexPath(item: 0, section: 0)]
    )
    _ = grid.selectItem(id: nil)
    grid.reload(
        pages: [[app, folder]], searchResults: nil, searchQuery: nil,
        animatingDifferences: false, animateEntrance: false
    )
    grid.layoutSubtreeIfNeeded()
    grid.delegate?.collectionView?(
        grid,
        didSelectItemsAt: [IndexPath(item: 1, section: 0)]
    )

    #expect(clock.now - start < .seconds(1))
}
```

Create executable `scripts/run-with-timeout.sh`. Its public contract is exact:

```text
scripts/run-with-timeout.sh SECONDS -- COMMAND [ARG...]
parameter error = 2; timeout = 124; HUP/INT/TERM = 129/130/143;
ordinary nonzero and exec 127 are preserved; argv is exec'd without eval.
```

The implementation creates one process group in a Perl supervisor. A pipe ACK
from the child makes process-group creation happen-before publication of the
wrapper ready file; only then may the wrapper forward signals to the negative
PGID. Cleanup sends TERM, waits a fixed two-second grace, sends KILL, reaps the
direct child, and only then returns. The executable also exposes these exact
internal verification entries:

```bash
scripts/run-with-timeout.sh --self-test-timeout
scripts/run-with-timeout.sh --self-test-signal
scripts/run-with-timeout.sh --self-test-nonzero
```

The timeout, signal and ordinary-nonzero branches each start a fresh wrapper
which starts `/bin/zsh`; that child forks a descendant `sleep`. The complete
script records wrapper, supervisor, direct child and descendant exact PIDs and
asserts all are gone after return. Signal self-test runs HUP, INT and TERM
independently and asserts `129`, `130`, `143`; for each signal it first sends at
the group-ready boundary before running the complete descendant-tree case.
Nonzero self-test asserts `17` with residual descendant cleanup, then separately
proves missing-command `127`. `RUN_TIMEOUT_SUPERVISOR_PIDFILE` and
`RUN_TIMEOUT_CHILD_PIDFILE` are self-test-only hooks published after the group
ACK. Implement the file exactly with this structure; do not use `eval`,
shell-join argv or process-name-only cleanup:

```zsh
#!/bin/zsh
set -u
unsetopt BG_NICE

SELF=${0:A}

pid_is_gone() {
  local pid=$1
  ! kill -0 "$pid" 2>/dev/null
}

wait_for_pidfiles() {
  local first=$1 second=$2 third=$3
  local attempt
  for attempt in {1..500}; do
    [[ -s $first && -s $second && -s $third ]] && return 0
    /bin/sleep 0.01
  done
  return 1
}

wait_for_two_pidfiles() {
  local first=$1 second=$2
  local attempt
  for attempt in {1..500}; do
    [[ -s $first && -s $second ]] && return 0
    /bin/sleep 0.01
  done
  return 1
}

stop_wrapper() {
  local wrapper=$1
  kill -TERM "$wrapper" 2>/dev/null || true
  wait "$wrapper" 2>/dev/null || true
}

run_command() {
  local seconds=$1
  shift
  local supervisor_pid=0 supervisor_ready=0 forwarded_status=0 wait_status=0
  local ready_file=$(mktemp /tmp/launchpad-supervisor-ready.XXXXXX)
  trap 'forwarded_status=129; (( supervisor_ready == 1 )) && kill -HUP "$supervisor_pid" 2>/dev/null || true' HUP
  trap 'forwarded_status=130; (( supervisor_ready == 1 )) && kill -INT "$supervisor_pid" 2>/dev/null || true' INT
  trap 'forwarded_status=143; (( supervisor_ready == 1 )) && kill -TERM "$supervisor_pid" 2>/dev/null || true' TERM
  /usr/bin/perl -e '
    use Errno qw(EINTR);
    use POSIX qw(SIGHUP SIGINT SIGTERM setpgid);
    my $seconds = shift @ARGV;
    my $ready_file = shift @ARGV;
    pipe(my $group_ready_reader, my $group_ready_writer)
      or die "pipe failed: $!";
    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ($pid == 0) {
      close $group_ready_reader;
      setpgid(0, 0) or die "setpgid failed: $!";
      my $written = syswrite($group_ready_writer, "1");
      die "group ready write failed: $!"
        unless defined($written) && $written == 1;
      close $group_ready_writer or die "group ready close failed: $!";
      exec { $ARGV[0] } @ARGV or exit 127;
    }
    close $group_ready_writer;
    my ($group_ready_byte, $read_count);
    do {
      $read_count = sysread($group_ready_reader, $group_ready_byte, 1);
    } while (!defined($read_count) && $! == EINTR);
    close $group_ready_reader;
    unless (defined($read_count) && $read_count == 1
        && $group_ready_byte eq "1") {
      waitpid($pid, 0);
      die "child process group setup failed";
    }
    if (my $pidfile = $ENV{RUN_TIMEOUT_SUPERVISOR_PIDFILE}) {
      open my $handle, ">", $pidfile or die "open pidfile failed: $!";
      print {$handle} $$;
      close $handle or die "close pidfile failed: $!";
    }
    if (my $pidfile = $ENV{RUN_TIMEOUT_CHILD_PIDFILE}) {
      open my $handle, ">", $pidfile or die "open pidfile failed: $!";
      print {$handle} $pid;
      close $handle or die "close pidfile failed: $!";
    }
    my ($timed_out, $forwarded, $terminating) = (0, 0, 0);
    my $terminate_group = sub {
      my ($number, $name) = @_;
      return if $terminating;
      $terminating = 1;
      $forwarded = $number if $number;
      kill $name, -$pid;
      select undef, undef, undef, 2.0;
      kill "KILL", -$pid;
    };
    local $SIG{ALRM} = sub {
      $timed_out = 1;
      $terminate_group->(0, "TERM");
    };
    local $SIG{HUP} = sub {
      alarm 0;
      $terminate_group->(SIGHUP, "HUP");
    };
    local $SIG{INT} = sub {
      alarm 0;
      $terminate_group->(SIGINT, "INT");
    };
    local $SIG{TERM} = sub {
      alarm 0;
      $terminate_group->(SIGTERM, "TERM");
    };
    open my $ready, ">", $ready_file or die "open ready file failed: $!";
    print {$ready} $$;
    close $ready or die "close ready file failed: $!";
    alarm $seconds;
    my $waited;
    do { $waited = waitpid($pid, 0) }
      while $waited == -1 && $! == EINTR;
    my $status = $?;
    alarm 0;
    $terminate_group->(0, "TERM")
      if !$timed_out && !$forwarded && kill(0, -$pid);
    exit 124 if $timed_out;
    exit 128 + $forwarded if $forwarded;
    exit 128 + ($status & 127) if $status & 127;
    exit($status >> 8);
  ' "$seconds" "$ready_file" "$@" &
  supervisor_pid=$!
  local attempt
  for attempt in {1..500}; do
    [[ -s $ready_file ]] && break
    if ! kill -0 "$supervisor_pid" 2>/dev/null; then
      wait "$supervisor_pid" || wait_status=$?
      rm -f "$ready_file"
      trap - HUP INT TERM
      return "$wait_status"
    fi
    /bin/sleep 0.01
  done
  if [[ ! -s $ready_file ]]; then
    kill -TERM "$supervisor_pid" 2>/dev/null || true
    wait "$supervisor_pid" 2>/dev/null || true
    rm -f "$ready_file"
    trap - HUP INT TERM
    return 125
  fi
  supervisor_ready=1
  case $forwarded_status in
    129) kill -HUP "$supervisor_pid" 2>/dev/null || true ;;
    130) kill -INT "$supervisor_pid" 2>/dev/null || true ;;
    143) kill -TERM "$supervisor_pid" 2>/dev/null || true ;;
  esac
  wait "$supervisor_pid" || wait_status=$?
  if (( forwarded_status != 0 )) \
      && kill -0 "$supervisor_pid" 2>/dev/null; then
    wait "$supervisor_pid" || wait_status=$?
  fi
  rm -f "$ready_file"
  trap - HUP INT TERM
  (( forwarded_status != 0 )) && return "$forwarded_status"
  return "$wait_status"
}

assert_tree_gone() {
  local wrapper=$1 supervisor_file=$2 child_file=$3 descendant_file=$4
  local supervisor=$(<"$supervisor_file")
  local child=$(<"$child_file")
  local descendant=$(<"$descendant_file")
  pid_is_gone "$wrapper" \
    && pid_is_gone "$supervisor" \
    && pid_is_gone "$child" \
    && pid_is_gone "$descendant"
}

start_tree() {
  local seconds=$1 supervisor_file=$2 child_file=$3 descendant_file=$4
  RUN_TIMEOUT_SUPERVISOR_PIDFILE=$supervisor_file \
    RUN_TIMEOUT_CHILD_PIDFILE=$child_file \
    "$SELF" "$seconds" -- /bin/zsh -c '
      /bin/sleep 30 &
      print -r -- $! > "$1"
      wait
    ' _ "$descendant_file" &
  REPLY=$!
}

self_test_timeout() {
  local directory=$(mktemp -d /tmp/launchpad-timeout.XXXXXX)
  trap "rm -rf ${(q)directory}" EXIT
  start_tree 1 "$directory/supervisor" "$directory/child" "$directory/descendant"
  local wrapper=$REPLY exit_code=0
  if ! wait_for_pidfiles "$directory/supervisor" "$directory/child" \
      "$directory/descendant"; then
    stop_wrapper "$wrapper"
    return 1
  fi
  wait "$wrapper" || exit_code=$?
  [[ $exit_code -eq 124 ]] || return 1
  assert_tree_gone "$wrapper" "$directory/supervisor" \
    "$directory/child" "$directory/descendant"
}

self_test_signal() {
  local pair signal expected race_directory race_wrapper directory wrapper exit_code
  for pair in HUP:129 INT:130 TERM:143; do
    signal=${pair%%:*}
    expected=${pair##*:}
    race_directory=$(mktemp -d /tmp/launchpad-signal-ready.XXXXXX)
    trap "rm -rf ${(q)race_directory}" EXIT
    RUN_TIMEOUT_SUPERVISOR_PIDFILE="$race_directory/supervisor" \
      RUN_TIMEOUT_CHILD_PIDFILE="$race_directory/child" \
      "$SELF" 30 -- /bin/sleep 30 &
    race_wrapper=$!
    if ! wait_for_two_pidfiles "$race_directory/supervisor" \
        "$race_directory/child"; then
      stop_wrapper "$race_wrapper"
      return 1
    fi
    kill -"$signal" "$race_wrapper" || return 1
    exit_code=0
    wait "$race_wrapper" || exit_code=$?
    [[ $exit_code -eq $expected ]] || return 1
    pid_is_gone "$race_wrapper" \
      && pid_is_gone "$(<"$race_directory/supervisor")" \
      && pid_is_gone "$(<"$race_directory/child")" || return 1
    rm -rf "$race_directory"

    directory=$(mktemp -d /tmp/launchpad-signal.XXXXXX)
    trap "rm -rf ${(q)directory}" EXIT
    start_tree 30 "$directory/supervisor" "$directory/child" \
      "$directory/descendant"
    wrapper=$REPLY
    if ! wait_for_pidfiles "$directory/supervisor" "$directory/child" \
        "$directory/descendant"; then
      stop_wrapper "$wrapper"
      return 1
    fi
    kill -"$signal" "$wrapper" || return 1
    exit_code=0
    wait "$wrapper" || exit_code=$?
    [[ $exit_code -eq $expected ]] || return 1
    assert_tree_gone "$wrapper" "$directory/supervisor" \
      "$directory/child" "$directory/descendant" || return 1
    rm -rf "$directory"
  done
}

self_test_nonzero() {
  local directory=$(mktemp -d /tmp/launchpad-nonzero.XXXXXX)
  trap "rm -rf ${(q)directory}" EXIT
  local supervisor_file="$directory/supervisor"
  local child_file="$directory/child"
  local descendant_file="$directory/descendant"
  RUN_TIMEOUT_SUPERVISOR_PIDFILE=$supervisor_file \
    RUN_TIMEOUT_CHILD_PIDFILE=$child_file \
    "$SELF" 30 -- /bin/zsh -c '
      /bin/sleep 30 &
      print -r -- $! > "$1"
      exit 17
    ' _ "$descendant_file" &
  local wrapper=$! exit_code=0
  wait "$wrapper" || exit_code=$?
  [[ $exit_code -eq 17 ]] || return 1
  assert_tree_gone "$wrapper" "$supervisor_file" \
    "$child_file" "$descendant_file" || return 1
  exit_code=0
  "$SELF" 5 -- /definitely/missing/launchpad-command || exit_code=$?
  [[ $exit_code -eq 127 ]] || return 1
}

case ${1:-} in
  --self-test-timeout) self_test_timeout; exit $? ;;
  --self-test-signal) self_test_signal; exit $? ;;
  --self-test-nonzero) self_test_nonzero; exit $? ;;
esac

if (( $# < 3 )) || [[ $1 != <-> ]] || (( $1 <= 0 )) || [[ $2 != -- ]]; then
  print -u2 'usage: run-with-timeout.sh SECONDS -- COMMAND [ARG...]'
  exit 2
fi
seconds=$1
shift 2
run_command "$seconds" "$@"
exit $?
```

Run the mandatory watchdog gates and commit it with the regression:

```bash
chmod +x scripts/run-with-timeout.sh
zsh -n scripts/run-with-timeout.sh
test -x scripts/run-with-timeout.sh
scripts/run-with-timeout.sh --self-test-timeout
scripts/run-with-timeout.sh --self-test-signal
scripts/run-with-timeout.sh --self-test-nonzero
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
scripts/run-with-timeout.sh 900 -- \
  swift test --disable-sandbox --no-parallel \
  --filter 'AppIconCellTests|FolderCellTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|DiffableDataSourceBuilderTests|DiffableDataSourceTests|AppGridFlowLayoutTests'
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
scripts/run-with-timeout.sh 30 -- \
  swift test --disable-sandbox --no-parallel \
  --filter 'AppGridInteractionCoordinatorTests|AppGridCollectionViewTests'
git add scripts/run-with-timeout.sh \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift
git commit -m "test: guard app grid convergence"
```

Expected: all three self-tests exit 0, the focused suite exits 0 in less than 30
seconds, the hot-loop test's always-enabled `< 1s` assertion passes, and no
recorded wrapper/supervisor/child/descendant PID remains alive.

- [x] **Step 15: Run the expanded cell/grid/coordinator regression GREEN**

```bash
set -euo pipefail
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
scripts/run-with-timeout.sh 900 -- \
  swift test --disable-sandbox --no-parallel \
  --filter 'AppIconCellTests|FolderCellTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|LaunchPadViewControllerTests|DiffableDataSourceBuilderTests|DiffableDataSourceTests|AppGridFlowLayoutTests'

full_status=0
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
scripts/run-with-timeout.sh 900 -- /bin/zsh -o pipefail -c \
  'swift test --disable-sandbox --no-parallel 2>&1 | tee "$1"' \
  _ /tmp/launchpad-task-4-full.log || full_status=$?
[[ $full_status -eq 0 || $full_status -eq 1 ]]
test "$(rg -c "^Test Suite 'All tests' (passed|failed)" \
  /tmp/launchpad-task-4-full.log)" -eq 1
test "$(rg -c '^(✔|✘) Test run with ' \
  /tmp/launchpad-task-4-full.log)" -eq 1
! rg -n "Test Case '-\[LaunchPadTests\..*\]' skipped" \
  /tmp/launchpad-task-4-full.log
! rg -n '^↷ Test ' /tmp/launchpad-task-4-full.log

cat > /tmp/launchpad-task-4-allowed-xctest-failures.txt <<'EOF'
LaunchPadTests.FileWatcherTests.testStart_realFileChange_triggersOnChange
LaunchPadTests.FolderOverlayViewTests.testMouseDown_outsidePanel_closesFolder
EOF
rg "Test Case '-\[LaunchPadTests\..*\]' failed" \
  /tmp/launchpad-task-4-full.log \
  > /tmp/launchpad-task-4-xctest-failure-lines.txt || true
sed -E "s/^.*Test Case '-\[([^ ]+) ([^]]+)\]' failed.*$/\1.\2/" \
  /tmp/launchpad-task-4-xctest-failure-lines.txt | \
  LC_ALL=C sort -u > /tmp/launchpad-task-4-actual-xctest-failures.txt
LC_ALL=C sort -u /tmp/launchpad-task-4-allowed-xctest-failures.txt \
  > /tmp/launchpad-task-4-allowed-xctest-failures.sorted.txt
comm -23 /tmp/launchpad-task-4-actual-xctest-failures.txt \
  /tmp/launchpad-task-4-allowed-xctest-failures.sorted.txt \
  > /tmp/launchpad-task-4-unexpected-xctest-failures.txt
test ! -s /tmp/launchpad-task-4-unexpected-xctest-failures.txt

cat > /tmp/launchpad-task-4-allowed-swift-issues.txt <<'EOF'
LaunchPadTests.LaunchPadWindowControllerTests/openingTransition_triggersShowWindowAnimated()|opening 委托触发 showWindowAnimated（normal 分支）— 动画完成后进入 visible 且窗口可见|LaunchPadWindowControllerTests.swift:154:9
LaunchPadTests.LaunchPadWindowControllerTests/openingTransition_triggersShowWindowAnimated()|opening 委托触发 showWindowAnimated（normal 分支）— 动画完成后进入 visible 且窗口可见|LaunchPadWindowControllerTests.swift:155:9
LaunchPadTests.LaunchPadWindowControllerTests/launchAnimation_fadesWindowOut()|启动动画将窗口淡出至 alphaValue=0 并最终回到 hidden|LaunchPadWindowControllerTests.swift:227:9
LaunchPadTests.LaunchPadWindowControllerTests/showWindowAnimated_reduceMotion_usesReducedBranch()|reduceMotion=true -> showWindowAnimated 用 reduced 分支|LaunchPadWindowControllerTests.swift:296:9
EOF
cut -d'|' -f2 /tmp/launchpad-task-4-allowed-swift-issues.txt | \
  LC_ALL=C sort -u > /tmp/launchpad-task-4-allowed-swift-failures.txt
rg '^✘ Test ".*" failed after' /tmp/launchpad-task-4-full.log \
  > /tmp/launchpad-task-4-swift-failure-lines.txt || true
sed -E 's/^✘ Test "(.*)" failed after.*$/\1/' \
  /tmp/launchpad-task-4-swift-failure-lines.txt | \
  LC_ALL=C sort -u > /tmp/launchpad-task-4-actual-swift-failures.txt
comm -23 /tmp/launchpad-task-4-actual-swift-failures.txt \
  /tmp/launchpad-task-4-allowed-swift-failures.txt \
  > /tmp/launchpad-task-4-unexpected-swift-failures.txt
test ! -s /tmp/launchpad-task-4-unexpected-swift-failures.txt
rg ' recorded an issue at ' /tmp/launchpad-task-4-full.log \
  > /tmp/launchpad-task-4-swift-issue-lines.txt || true
sed -E \
  's/^✘ Test "(.*)" recorded an issue at ([^/ ]+Tests\.swift:[0-9]+:[0-9]+):.*$/\1|\2/' \
  /tmp/launchpad-task-4-swift-issue-lines.txt | \
  LC_ALL=C sort > /tmp/launchpad-task-4-actual-swift-issues.txt
cut -d'|' -f2-3 /tmp/launchpad-task-4-allowed-swift-issues.txt | \
  LC_ALL=C sort > /tmp/launchpad-task-4-allowed-swift-issue-keys.txt
comm -23 /tmp/launchpad-task-4-actual-swift-issues.txt \
  /tmp/launchpad-task-4-allowed-swift-issue-keys.txt \
  > /tmp/launchpad-task-4-unexpected-swift-issues.txt
test ! -s /tmp/launchpad-task-4-unexpected-swift-issues.txt
test "$(wc -l < /tmp/launchpad-task-4-actual-swift-issues.txt \
  | tr -d ' ')" -le 4

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
scripts/run-with-timeout.sh 120 -- swift test --disable-sandbox list \
  > /tmp/launchpad-task-4-discovered-tests.txt
cat > /tmp/launchpad-task-4-expected-xctest-ids.txt <<'EOF'
LaunchPadTests.FileWatcherTests/testStart_realFileChange_triggersOnChange
LaunchPadTests.FolderOverlayViewTests/testMouseDown_outsidePanel_closesFolder
EOF
rg '^LaunchPadTests\.(FileWatcherTests/testStart_realFileChange_triggersOnChange|FolderOverlayViewTests/testMouseDown_outsidePanel_closesFolder)$' \
  /tmp/launchpad-task-4-discovered-tests.txt | \
  LC_ALL=C sort > /tmp/launchpad-task-4-actual-xctest-ids.txt
LC_ALL=C sort /tmp/launchpad-task-4-expected-xctest-ids.txt \
  > /tmp/launchpad-task-4-expected-xctest-ids.sorted.txt
diff -u /tmp/launchpad-task-4-expected-xctest-ids.sorted.txt \
  /tmp/launchpad-task-4-actual-xctest-ids.txt
cut -d'|' -f1 /tmp/launchpad-task-4-allowed-swift-issues.txt | \
  LC_ALL=C sort -u > /tmp/launchpad-task-4-expected-swift-ids.txt
rg '^LaunchPadTests\.LaunchPadWindowControllerTests/(openingTransition_triggersShowWindowAnimated|launchAnimation_fadesWindowOut|showWindowAnimated_reduceMotion_usesReducedBranch)\(\)$' \
  /tmp/launchpad-task-4-discovered-tests.txt | \
  LC_ALL=C sort -u > /tmp/launchpad-task-4-actual-swift-ids.txt
diff -u /tmp/launchpad-task-4-expected-swift-ids.txt \
  /tmp/launchpad-task-4-actual-swift-ids.txt
cut -d'|' -f2 /tmp/launchpad-task-4-allowed-swift-issues.txt | \
  LC_ALL=C sort -u > /tmp/launchpad-task-4-expected-swift-titles.txt
rg -F -f /tmp/launchpad-task-4-expected-swift-titles.txt \
  Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift | \
  sed -E 's/.*@Test\("(.*)"\).*/\1/' | \
  LC_ALL=C sort > /tmp/launchpad-task-4-actual-swift-titles.txt
diff -u /tmp/launchpad-task-4-expected-swift-titles.txt \
  /tmp/launchpad-task-4-actual-swift-titles.txt
if [[ $full_status -eq 0 ]]; then
  test ! -s /tmp/launchpad-task-4-actual-xctest-failures.txt
  test ! -s /tmp/launchpad-task-4-actual-swift-failures.txt
else
  [[ -s /tmp/launchpad-task-4-actual-xctest-failures.txt \
    || -s /tmp/launchpad-task-4-actual-swift-failures.txt ]]
fi
! pgrep -x swift-test
! pgrep -x LaunchPadPackageTests
```

Expected: the original 158-test accounting remains one-to-one after moving 23
historical interactions plus the callback-order behavior to the coordinator;
14 new branch/lifecycle cases and one hot-loop regression bring the exact Task 4
total to 173 tests, all pass with 0 fail and 0 skip. The coordinator suite has
exactly 39 tests. Folder 96pt coverage asserts nine distinct thumbnail frames,
non-overlap, non-positive bottom constants and exact positive inward inset
magnitudes; stable selection asserts real `selectionIndexPaths`; coordinator
selection asserts callback-before-activation; paged search asserts
`.searchPage` is authoritative when supplied. The unfiltered run must complete
and match the monotonically decreasing registered Task 3R baseline: a nonzero
status is allowed only for still-open, explicitly registered later-task
failures/issues. The executable subset comparison above rejects every new
XCTest failure, Swift Testing qualified-ID/display-title/source-location issue,
skip, unexpected exit status, missing framework summary or residual process;
none may be accepted by count alone. Discovery also proves the two still-open
XCTest IDs were not deleted or renamed. The unique `@Test` title and discovery
checks make each logged Swift issue traceable back to its registered qualified
test ID.

- [x] **Step 16: Run static/compile gates and confirm every Task 4 commit boundary**

```bash
! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:' \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift \
  Tests/LaunchPadTests/Views/FolderCellTests.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift
! rg -n 'accuracy:' Tests/LaunchPadTests --glob '*.swift'
! rg -n 'delegate\s*=\s*self|extension AppGridCollectionView:\s*NSCollectionViewDelegate|onItemSelected|onSelectionChanged|dragController|pasteboardUUIDReader' \
  Sources/LaunchPad/Views/AppGridCollectionView.swift
! rg -n --glob 'AppGrid*.swift' '[Pp]roxy' \
  Sources/LaunchPad/Views
! rg -n -U --pcre2 \
  '\b([A-Za-z_][A-Za-z0-9_]*)\.collectionView\(\s*\1\s*,' \
  Tests --glob '*.swift'
test "$(rg -c '^\s*@Test\b' Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift)" -eq 39
zsh -n scripts/run-with-timeout.sh
test -x scripts/run-with-timeout.sh
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
scripts/run-with-timeout.sh 900 -- swift build --disable-sandbox
```

The behavior slices were committed immediately at their GREEN gates. Step 16
must not create or amend a behavior commit. Confirm that no
Task 4 source or test delta remains unstaged or staged:

```bash
git diff --exit-code -- \
  Sources/LaunchPad/Views/AppIconCell.swift \
  Sources/LaunchPad/Views/FolderCell.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/Views/DiffableDataSourceBuilder.swift \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift \
  Tests/LaunchPadTests/Views/FolderCellTests.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md \
  scripts/run-with-timeout.sh
git diff --cached --exit-code -- \
  Sources/LaunchPad/Views/AppIconCell.swift \
  Sources/LaunchPad/Views/FolderCell.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/Views/DiffableDataSourceBuilder.swift \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift \
  Tests/LaunchPadTests/Views/FolderCellTests.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift \
  docs/superpowers/reports/2026-07-21-task-4-cell-grid-migration.md \
  scripts/run-with-timeout.sh
```

- [x] **Step 17: Perform eight review gates and record the aggregate result**

Review A: existing three failures/two skips and their deterministic repair.
Review B: all four production-empty migrations and 128 mappings. Review C: cell
constraints/frames. Review D: grid metrics, accessibility and stable selection.
Review E: coordinator parity, all branches, real delegate wiring and lifecycle.
Review F: macOS 26 hot-loop test, `< 1s` wall-clock assertion and all watchdog
self-tests with exact PID cleanup. Review G: paged search authority. Review H:
Task 4 base..head, exact 173-test accounting, static scans and build. Record
exact commit ranges and commands in `.superpowers/sdd/task-4-review.md`.

---

### Task 5: Reproject the View Controller on Real Viewport Changes

**Files:**
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:15-20,58-67,143-191,285-381,607-651`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Integration/IntegrationTests.swift:113-124`

**Interfaces:**
- Consumes: Tasks 1-4, including the Task 4-owned
  `AppGridInteractionCoordinator` and callback contract
  `onSelectionChanged: ((PageItem) -> Void)?`.
- Consumes later: Task 20 reloads this controller after scan; first-scan storage capacity remains Task 20's responsibility.
- Produces: `gridMetrics`, current-mode `visualPages`, stable selection and synchronized page control/scroll/keyboard/accessibility without storage writes.

- [x] **Step 1: Add viewport resize and active-search RED tests**

Use 60 items across two persisted pages. The six RED methods are `resizeReprojectsWithoutWritesAndPreservesStableOrder`, `resizeClampsPreviousPageAndRestoresSelectionByID`, `resizeKeepsActiveSearchAndPaginatesResults`, `resizeSynchronizesKeyboardAndAccessibilityRows`, `invalidViewportDoesNothing` and `sameMetricsDoesNotReload`; their setup and assertion bodies are given in the blocks below. The no-write test must compare the existing mock's concrete write records; do not invent `totalWriteCallCount`:

```swift
let insertedBefore = storage.insertedItems
let updatedBefore = storage.updatedItems
let deletedBefore = storage.deletedIds
sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
sut.viewDidLayout()
#expect(storage.insertedItems == insertedBefore)
#expect(storage.updatedItems == updatedBefore)
#expect(storage.deletedIds == deletedBefore)
#expect(sut.gridMetrics?.rows == 4)
#expect(sut.visualPages.map(\.count) == [28, 28, 4])
#expect(sut.visualPages.flatMap { $0 }.map(\.id) == Array(1...60).map(Int64.init))
```

Task 5 removes `selectedIndex` as writable state, but preserves source
compatibility with a deprecated read-only projection. Migrate every existing
`LaunchPadViewControllerTests.swift` behavior assertion to `selectedItemID` or
`selectedItemIndexPath`; only the compatibility test below may read
`selectedIndex`. Replace initial/ignored assertions with
`selectedItemID == nil`; replace first Down/Tab assertions with the first
snapshot item's stable ID; replace subsequent Down/Up/Tab integer arithmetic
with expected stable IDs resolved from `gridSnapshot.itemIdentifiers`; replace
the historical coverage-only `?? 0`/`?? -1` tests with behavior tests for nil
Up, first Tab, cross-section Down and end-of-list no-op:

```swift
@Test("selectedIndex 兼容适配器从稳定 ID 投影展平索引")
func selectedIndexCompatibilityAdapterProjectsFlattenedIndex() {
    let (sut, _, storage) = makeSUT()
    let apps = TestDataFactory.makeAppItems(count: 30)
    sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
    loadViewWithData(sut, storage: storage, apps: apps)
    sut.viewDidLayout()

    #expect(sut.selectedIndex == nil)
    _ = sut.selectItem(id: apps[29].id)

    #expect(sut.selectedItemID == apps[29].id)
    #expect(sut.selectedItemIndexPath == IndexPath(item: 1, section: 1))
    #expect(sut.selectedIndex == 29)
}

@Test("未加载视图的分页动作不强制加载视图")
func pageActionsDoNotLoadView() {
    let (sut, _, _) = makeSUT()

    #expect(!sut.isViewLoaded)
    #expect(sut.handleKeyEvent(.leftArrow) == .previousPage)
    #expect(sut.handleKeyEvent(.rightArrow) == .nextPage)
    #expect(!sut.isViewLoaded)
}
```

Before GREEN, this command must print nothing; it rejects reintroducing a
stored assignment while allowing the read-only compatibility getter and its
single test:

```bash
rg --pcre2 -n '\bselectedIndex\s*=(?!=)' \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift
```

Prove page clamp preserves the old page before `configure(totalPages:)` can reset it:

```swift
sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
sut.viewDidLayout()
sut.navigateToPage(2)
_ = sut.selectItem(id: 60)
sut.viewportSizeProvider = { CGSize(width: 1729, height: 496) }
sut.viewDidLayout()

#expect(sut.currentVisualPage == 1)
#expect(sut.pagingPageCount == 2)
#expect(sut.selectedItemID == 60)
#expect(sut.selectedItemIndexPath?.section == 1)
```

For active search, use 30 matching results and resize to capacity 28. Assert the query and mode remain active, `visualPages.map(\.count) == [28, 2]`, the snapshot has two `.searchPage` sections, and every item frame stays within rows `0..<metrics.rows`:

```swift
let matchingItems = TestDataFactory.makeAppItems(
    count: 30,
    titlePrefix: "App"
)
sut.handleSearch(query: "app")
sut.keyboardNavigator.mode = .search(query: "app")
sut.applySearchResults(
    matchingItems,
    query: "app",
    expectedQuery: "app"
)
sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
sut.viewDidLayout()

#expect(sut.currentSearchQuery == "app")
#expect(sut.keyboardNavigator.mode == .search(query: "app"))
#expect(sut.visualPages.map(\.count) == [28, 2])
#expect(sut.gridSnapshot.sectionIdentifiers == [
    .searchPage(0), .searchPage(1),
])
```

Use `projectedLayoutDidReload` as the same-metrics injection point:

```swift
var reloadCount = 0
sut.projectedLayoutDidReload = { reloadCount += 1 }
sut.viewportSizeProvider = { CGSize(width: 1440, height: 620) }
sut.viewDidLayout()
let countAfterFirstLayout = reloadCount
sut.viewDidLayout()
#expect(reloadCount == countAfterFirstLayout)
```

- [x] **Step 2: Run focused VC tests and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LaunchPadViewControllerTests
```

- [x] **Step 3: Add the observable state and viewport entry**

Add the new members below; change the existing `currentSearchQuery` declaration from `private` to `private(set)` instead of declaring it twice:

```swift
var viewportSizeProvider: (() -> CGSize)?
var projectedLayoutDidReload: (() -> Void)?
private(set) var gridMetrics: GridMetrics?
private(set) var visualPages: [[PageItem]] = [[]]
public private(set) var selectedItemID: Int64?
private(set) var currentSearchResults: [PageItem] = []
private(set) var currentSearchQuery: String = ""
var currentVisualPage: Int { pageControlViewModel.currentPage }
var pagingPageCount: Int { scrollView?.pagingPageCount ?? 1 }
var gridSnapshot: AppGridCollectionView.Snapshot {
    collectionView.diffableDataSource.snapshot()
}
var selectedItemIndexPath: IndexPath? {
    guard let selectedItemID,
          let item = gridSnapshot.itemIdentifiers.first(where: {
              $0.id == selectedItemID
          }) else { return nil }
    return collectionView.diffableDataSource.indexPath(for: item)
}

@available(*, deprecated, message: "Use selectedItemID")
public var selectedIndex: Int? {
    guard isViewLoaded, let selectedItemID else { return nil }
    return gridSnapshot.itemIdentifiers.firstIndex {
        $0.id == selectedItemID
    }
}

override public func viewDidLayout() {
    super.viewDidLayout()
    let size = viewportSizeProvider?() ?? scrollView.contentView.bounds.size
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0 else { return }
    let metrics = GridLayoutCalculator.calculate(viewportSize: size)
    guard metrics != gridMetrics else { return }
    gridMetrics = metrics
    collectionView.applyGridMetrics(metrics)
    reloadProjectedLayout(preserving: selectedItemID)
}
```

- [x] **Step 4: Centralize normal/search projection, page clamp and selection restore**

Add:

```swift
private func reloadProjectedLayout(preserving itemID: Int64?) {
    guard let metrics = gridMetrics else { return }
    let isSearchActive = !currentSearchQuery.isEmpty
    visualPages = isSearchActive
        ? LayoutProjection.paginate(items: currentSearchResults, metrics: metrics)
        : LayoutProjection.project(
            pages: allPages,
            itemsByPage: itemsByPage,
            metrics: metrics
        )
    let previousPage = pageControlViewModel.currentPage
    collectionView.reload(
        pages: isSearchActive ? [] : visualPages,
        searchResults: isSearchActive ? currentSearchResults : nil,
        searchQuery: isSearchActive ? currentSearchQuery : nil,
        searchResultPages: isSearchActive ? visualPages : nil,
        animatingDifferences: false,
        reconfigureItems: true,
        animateEntrance: false
    )
    let clampedPage = min(max(previousPage, 0), max(visualPages.count - 1, 0))
    pageControlViewModel.configure(totalPages: visualPages.count)
    pageControlViewModel.currentPage = clampedPage
    pageControlViewModel.isSearchActive = isSearchActive
    pageControl.update()
    scrollView.configurePaging(
        pageWidth: metrics.pageWidth,
        pageCount: visualPages.count
    )
    scrollView.scrollToPage(clampedPage, animated: false)
    _ = selectItem(id: itemID)
    projectedLayoutDidReload?()
}
```

Change `loadData` to update `allPages/itemsByPage` and call this method when metrics exists. In `handleSearch(query:)`, clear `currentSearchResults` before reloading an empty query. In `applySearchResults`, assign `currentSearchResults = results` and call `reloadProjectedLayout(preserving: selectedItemID)` instead of directly creating a one-section search snapshot. This guarantees every normal or search section contains at most `metrics.itemsPerPage`, so the explicit layout cannot crop a sixth row.

Bind collection, scroll and mouse selection state in `setupCallbacks`:

```swift
gridInteractionCoordinator?.onSelectionChanged = { [weak self] item in
    self?.selectedItemID = item.id
}
scrollView.onPageChanged = { [weak self] page in
    guard let self else { return }
    pageControlViewModel.currentPage = page
    pageControl.update()
}
```

- [x] **Step 5: Make navigation and keyboard use visual pages and current columns**

Replace `allPages.count` guards with `visualPages.count`; remove the stored
`selectedIndex` and keep only Step 3's deprecated read-only adapter. Use one
page synchronizer for dot clicks, scroll callbacks and cross-section keyboard
movement:

```swift
private func synchronizePage(to page: Int, animated: Bool) {
    guard isViewLoaded,
          page >= 0,
          page < visualPages.count else { return }
    pageControlViewModel.currentPage = page
    pageControl.update()
    scrollView.scrollToPage(page, animated: animated)
}

func navigateToPage(_ index: Int) {
    synchronizePage(to: index, animated: true)
}

@discardableResult
func selectItem(id: Int64?) -> IndexPath? {
    let indexPath = collectionView.selectItem(id: id)
    selectedItemID = indexPath == nil ? nil : id
    if let indexPath {
        synchronizePage(to: indexPath.section, animated: false)
    }
    return indexPath
}

private func moveSelection(_ direction: SelectionDirection) {
    guard isViewLoaded,
          let columns = gridMetrics?.columns,
          columns > 0 else { return }
    let snapshot = collectionView.diffableDataSource.snapshot()
    let items = snapshot.itemIdentifiers
    guard !items.isEmpty else {
        selectedItemID = nil
        return
    }
    let current = selectedItemID.flatMap { id in
        items.firstIndex(where: { $0.id == id })
    }
    let candidate: Int
    switch direction {
    case .down:
        candidate = current.map { $0 + columns } ?? 0
    case .up:
        guard let current else { return }
        candidate = current - columns
    case .next:
        candidate = (current ?? -1) + 1
    }
    guard items.indices.contains(candidate) else { return }
    _ = selectItem(id: items[candidate].id)
}
```

At the start of `handleItemSelection(_:)`, call `_ = selectItem(id: item.id)`;
this is a programmatic grid selection and therefore emits no coordinator output.
It closes the mouse and folder-overlay path through the same state/page
synchronization used by keyboard selection without callback recursion.
`reloadProjectedLayout` already calls this same helper, so no second manual
selection state exists. Clearing nil/unknown IDs explicitly sets
`selectedItemID = nil`; no nil payload is invented at the coordinator boundary.

Finally, make `accessibilityRows()` use `gridMetrics.columns` and the same snapshot section/index paths from Task 4. The test `resizeSynchronizesKeyboardAndAccessibilityRows` must assert the 4-row metrics, a Down move by exactly 7 flattened items, the resolved selection section, and accessibility row count `visualPages.reduce(0) { $0 + ceilDiv($1.count, 7) }` using integer arithmetic `($1.count + 6) / 7`.

- [x] **Step 6: Update integration expectations and run the grid regression**

Update the fixed 1440-width integration test to pass `CGSize(width: 1440, height: 620)` and assert 7x5. Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'GridLayoutCalculatorTests|LayoutProjectionTests|AppGridFlowLayoutTests|PageScrollViewTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|LaunchPadViewControllerTests|IntegrationTests'
```

Expected: all dynamic grid, page geometry, resize and stable selection tests pass.

- [x] **Step 7: Commit**

```bash
git add Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Integration/IntegrationTests.swift
git commit -m "feat: reproject layout for viewport changes"
```

---
### Task 6: Keep Keyboard Search State Truthful

**Files:**
- Modify: `Sources/LaunchPad/Controllers/KeyboardNavigator.swift:53-79`
- Modify: `Tests/LaunchPadTests/Controllers/KeyboardNavigatorTests.swift:69-146`

**Interfaces:**
- Consumes: idle/search/edit state and abstract keys.
- Produces: existing `Action` API; `Mode.search(query:)` always matches accepted input.

- [x] **Step 1: Add state mutation RED tests**

```swift
@Test("idle 首字符进入搜索态，后续字符追加")
func firstAndFollowingCharactersUpdateMode() {
    let sut = KeyboardNavigator()
    #expect(sut.handleCharacter("s") == .enterSearchMode("s"))
    #expect(sut.mode == .search(query: "s"))
    #expect(sut.handleCharacter("a") == .appendToQuery("a"))
    #expect(sut.mode == .search(query: "sa"))
}

@Test("搜索态 Delete 同步缩短查询")
func deleteUpdatesQuery() {
    let sut = KeyboardNavigator()
    sut.mode = .search(query: "saf")
    #expect(sut.handleKey(.delete) == .deleteLastCharacter)
    #expect(sut.mode == .search(query: "sa"))
}

@Test("空字符串输入被忽略且不改变模式")
func emptyCharacterIsIgnored() {
    let sut = KeyboardNavigator()
    #expect(sut.handleCharacter("") == .ignored)
    #expect(sut.mode == .idle)
}
```

- [x] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter KeyboardNavigatorTests
```

Expected: first character leaves mode idle and Delete does not shorten query.

- [x] **Step 3: Replace both state entry methods**

```swift
public func handleKey(_ key: Key) -> Action {
    switch mode {
    case .idle:
        return handleKeyInIdle(key)
    case .search(let query):
        let action = handleKeyInSearch(key)
        switch action {
        case .clearSearch:
            mode = .idle
        case .deleteLastCharacter:
            mode = .search(query: String(query.dropLast()))
        default:
            break
        }
        return action
    case .edit:
        return handleKeyInEdit(key)
    }
}

public func handleCharacter(_ char: String) -> Action {
    guard !char.isEmpty else { return .ignored }
    switch mode {
    case .idle:
        mode = .search(query: char)
        return .enterSearchMode(char)
    case .search(let query):
        mode = .search(query: query + char)
        return .appendToQuery(char)
    case .edit:
        return .ignored
    }
}
```

- [x] **Step 4: Run the full three-mode suite GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter KeyboardNavigatorTests
```

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPad/Controllers/KeyboardNavigator.swift \
  Tests/LaunchPadTests/Controllers/KeyboardNavigatorTests.swift
git commit -m "fix: keep keyboard search state synchronized"
```

---

### Task 7: Apply the First Search Character Atomically

**Files:**
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:548-585`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`

**Interfaces:**
- Consumes: Task 6 `.enterSearchMode(initialQuery)`.
- Produces: first character, responder focus and one debounced request in one call.

- [x] **Step 1: Replace the reversed repeated-enter test**

```swift
@Test("连续字符建立完整查询并仅保留一个防抖任务")
func charactersBuildCompleteQuery() {
    let scheduler = MockScheduler()
    let (sut, _, _) = makeSUTWithSearchScheduler(searchScheduler: scheduler)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = sut.view

    let actions = "safari".map { sut.handleCharacterInput(String($0)) }

    #expect(actions.first == .enterSearchMode("s"))
    #expect(Array(actions.dropFirst()) == [
        .appendToQuery("a"), .appendToQuery("f"), .appendToQuery("a"),
        .appendToQuery("r"), .appendToQuery("i"),
    ])
    #expect(sut.searchBar.stringValue == "safari")
    #expect(sut.keyboardNavigator.mode == .search(query: "safari"))
    #expect(window.firstResponder === sut.searchBar)
    #expect(scheduler.scheduledActions.count == 1)
}
```

- [x] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter charactersBuildCompleteQuery
```

Expected: the search field omits `s` and the action sequence is wrong.

- [x] **Step 3: Consume the associated initial query**

Replace the action branch:

```swift
case .enterSearchMode(let initialQuery):
    guard isViewLoaded else { return }
    searchBar.show()
    searchBar.stringValue = initialQuery
    searchBar.window?.makeFirstResponder(searchBar)
    searchDebouncer.search(query: initialQuery)
```

Keep the existing append and Delete branches, which now consume Task 6's truthful state.

- [x] **Step 4: Run VC and debounce regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'LaunchPadViewControllerTests|SearchDebounceTests'
```

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift
git commit -m "fix: apply initial search character atomically"
```

---

### Task 8: Preserve Local Monitor Suppression Results

**Files:**
- Modify: `Sources/LaunchPad/App/HotkeyManager.swift:39-58,161-183`
- Modify: `Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift:418-495`

**Interfaces:**
- Consumes: Task 3R-B `localMonitorInstaller`, `localMonitorRemover`, idempotent registration and `onKeyDown: (NSEvent) -> NSEvent?`.
- Produces: callback `nil` is returned to AppKit unchanged for every key type.
- Preserves: Task 3R-B's already-reviewed install/remove lifecycle; this task changes only event routing semantics.

- [x] **Step 1: Replace the special-key bypass test with RED entry tests**

```swift
private final class KeyCodeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UInt16] = []

    func append(_ keyCode: UInt16) {
        lock.lock()
        storage.append(keyCode)
        lock.unlock()
    }

    var values: [UInt16] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Test("local monitor 转发 ESC 方向键 Enter 并保留 nil")
func localMonitorForwardsSpecialKeysAndNil() {
    let manager = HotkeyManager()
    let keyCodes = KeyCodeRecorder()
    manager.onKeyDown = { event in
        keyCodes.append(event.keyCode)
        return nil
    }
    let handler = manager.localMonitorHandler

    for keyCode: UInt16 in [53, 123, 124, 125, 126, 36] {
        #expect(handler?(makeNSKeyEvent(type: .keyDown, keyCode: keyCode)) == nil)
    }
    #expect(keyCodes.values == [53, 123, 124, 125, 126, 36])
}

@Test("local monitor 无 callback 时放行原对象")
func localMonitorWithoutCallbackReturnsOriginal() {
    let manager = HotkeyManager()
    let event = makeNSKeyEvent(type: .keyDown, keyCode: 53)
    #expect(manager.localMonitorHandler?(event) === event)
}

@Test("重复注册 local monitor 只安装一次")
func localMonitorRegistrationIsIdempotent() {
    let manager = HotkeyManager()
    let token = NSObject()
    var installationCount = 0
    manager.localMonitorInstaller = { _ in
        installationCount += 1
        return token
    }
    manager.localMonitorRemover = { _ in }
    defer { manager.unregisterLocalMonitor() }

    manager.registerLocalMonitor()
    manager.registerLocalMonitor()

    #expect(installationCount == 1)
}
```

- [x] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'localMonitorForwardsSpecialKeysAndNil|localMonitorWithoutCallbackReturnsOriginal|localMonitorRegistrationIsIdempotent'
```

- [x] **Step 3: Make the existing injected handler preserve optional results**

```swift
func handleLocalMonitorEvent(_ event: NSEvent) -> NSEvent? {
    guard let onKeyDown else { return event }
    return onKeyDown(event)
}
```

Keep Task 3R-B's initializer/register/unregister implementation byte-for-byte except for the handler's now-optional return type. The focused lifecycle test must still prove one install and one remove after duplicate calls.

- [x] **Step 4: Run the complete HotkeyManager suite and verify process exit**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter HotkeyManagerTests
```

Every test that installs a real local monitor must use `defer { manager.unregisterLocalMonitor() }`.

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPad/App/HotkeyManager.swift \
  Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift
git commit -m "fix: route all local keys through callback"
```

---

### Task 9: Suppress Only App Events That Were Handled

**Files:**
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:39-40,220-290`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`

**Interfaces:**
- Consumes: Task 3R-B `workspaceURLOpener`/isolated manager factory, Task 8 optional monitor result and Tasks 6-7 keyboard APIs.
- Produces: handled keyDown returns `nil`; hidden/unmapped/flagsChanged returns original event.
- Rule: suppression is exactly `Action != .ignored`; mapping a key code is not proof that the current mode handled it.

- [x] **Step 1: Add real monitor-chain RED tests through the already isolated boundaries**

Task 3R-B already added `workspaceURLOpener` and made the common factory non-system. Keep that injection unchanged. Every test below calls `HotkeyManager.localMonitorHandler`, not AppDelegate's closure directly.

Use these exact helpers and test names so the RED command cannot succeed with zero matches:

```swift
private func visibleLifecycle() -> WindowLifecycle {
    let lifecycle = WindowLifecycle()
    lifecycle.handleToggle()
    lifecycle.openAnimationDidFinish()
    return lifecycle
}

private func flagsChangedEvent() -> NSEvent {
    NSEvent.keyEvent(
        with: .flagsChanged, location: .zero, modifierFlags: [.option],
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: 58
    )!
}

private func prepareKeyboardMonitor(
    _ sut: AppDelegate,
    lifecycle: WindowLifecycle,
    viewController: LaunchPadViewController?
) -> HotkeyManager {
    let manager = HotkeyManager()
    manager.localMonitorInstaller = { _ in NSObject() }
    manager.localMonitorRemover = { _ in }
    sut.hotkeyManager = manager
    sut.lifecycle = lifecycle
    sut.viewController = viewController
    sut.setupHotkey()
    return manager
}

@Test("visible idle 的已处理特殊键被吞")
func localMonitorVisibleHandledSpecialKeyReturnsNil() throws {
    let sut = makeDelegate()
    let viewController = try makeViewController()
    _ = viewController.view
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: visibleLifecycle(), viewController: viewController
    )
    defer { manager.unregisterLocalMonitor() }

    #expect(manager.localMonitorHandler?(keyEvent(keyCode: 123)) == nil)
}

@Test("visible search 的 ignored 方向键放行原事件")
func localMonitorVisibleIgnoredSpecialKeyReturnsOriginal() throws {
    let sut = makeDelegate()
    let viewController = try makeViewController()
    _ = viewController.view
    viewController.keyboardNavigator.mode = .search(query: "sa")
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: visibleLifecycle(), viewController: viewController
    )
    defer { manager.unregisterLocalMonitor() }
    let event = keyEvent(keyCode: 123)

    #expect(manager.localMonitorHandler?(event) === event)
}

@Test("visible 连续字符建立查询且两个事件均被吞")
func localMonitorVisibleCharactersBuildSearchAndReturnNil() throws {
    let sut = makeDelegate()
    let viewController = try makeViewController()
    _ = viewController.view
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: visibleLifecycle(), viewController: viewController
    )
    defer { manager.unregisterLocalMonitor() }

    #expect(manager.localMonitorHandler?(keyEvent(keyCode: 1, characters: "s")) == nil)
    #expect(manager.localMonitorHandler?(keyEvent(keyCode: 0, characters: "a")) == nil)
    #expect(viewController.keyboardNavigator.mode == .search(query: "sa"))
}

@Test("flagsChanged 放行原事件")
func localMonitorFlagsChangedReturnsOriginal() throws {
    let sut = makeDelegate()
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: visibleLifecycle(), viewController: try makeViewController()
    )
    defer { manager.unregisterLocalMonitor() }
    let event = flagsChangedEvent()

    #expect(manager.localMonitorHandler?(event) === event)
}

@Test("未知且无字符的 keyDown 放行原事件")
func localMonitorUnknownEmptyCharacterReturnsOriginal() throws {
    let sut = makeDelegate()
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: visibleLifecycle(), viewController: try makeViewController()
    )
    defer { manager.unregisterLocalMonitor() }
    let event = keyEvent(keyCode: 110)

    #expect(manager.localMonitorHandler?(event) === event)
}

@Test("hidden 生命周期放行原事件")
func localMonitorHiddenReturnsOriginal() throws {
    let sut = makeDelegate()
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: WindowLifecycle(), viewController: try makeViewController()
    )
    defer { manager.unregisterLocalMonitor() }
    let event = keyEvent(keyCode: 53)

    #expect(manager.localMonitorHandler?(event) === event)
}

@Test("缺少 view controller 时放行原事件")
func localMonitorMissingViewControllerReturnsOriginal() {
    let sut = makeDelegate()
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: visibleLifecycle(), viewController: nil
    )
    defer { manager.unregisterLocalMonitor() }
    let event = keyEvent(keyCode: 53)

    #expect(manager.localMonitorHandler?(event) === event)
}

@Test("存在但未加载的 view controller 放行且不强制加载")
func localMonitorUnloadedViewControllerReturnsOriginal() throws {
    let sut = makeDelegate()
    let viewController = try makeViewController()
    let manager = prepareKeyboardMonitor(
        sut, lifecycle: visibleLifecycle(), viewController: viewController
    )
    defer { manager.unregisterLocalMonitor() }
    let event = keyEvent(keyCode: 125)

    #expect(viewController.isViewLoaded == false)
    #expect(manager.localMonitorHandler?(event) === event)
    #expect(viewController.isViewLoaded == false)
}
```

The visible unknown/empty-character test must also create a named
`viewController`, evaluate `_ = viewController.view`, and pass that loaded
instance to `prepareKeyboardMonitor`. Otherwise Task 9's unloaded-view guard
would return the original event for the wrong reason and the test would not
exercise the unknown-key branch.

- [x] **Step 2: Run entry tests and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'localMonitorVisibleHandledSpecialKeyReturnsNil|localMonitorVisibleIgnoredSpecialKeyReturnsOriginal|localMonitorVisibleCharactersBuildSearchAndReturnNil|localMonitorFlagsChangedReturnsOriginal|localMonitorUnknownEmptyCharacterReturnsOriginal|localMonitorHiddenReturnsOriginal|localMonitorMissingViewControllerReturnsOriginal|localMonitorUnloadedViewControllerReturnsOriginal'
```

- [x] **Step 3: Replace the callback with handled-only routing**

```swift
hotkeyManager.onKeyDown = { @Sendable [weak self] event in
    guard let self else { return event }
    let keyCode = event.keyCode
    let characters = event.characters
    let eventType = event.type

    let handled = MainActor.assumeIsolated { () -> Bool in
        guard eventType == .keyDown,
              self.lifecycle.state == .visible,
              let viewController = self.viewController,
              viewController.isViewLoaded else {
            return false
        }

        let key: KeyboardNavigator.Key? = switch keyCode {
        case 53: .escape
        case 36: .enter
        case 126: .upArrow
        case 125: .downArrow
        case 123: .leftArrow
        case 124: .rightArrow
        case 48: .tab
        case 51: .delete
        default: nil
        }
        if let key {
            return viewController.handleKeyEvent(key) != .ignored
        }
        guard let characters, !characters.isEmpty else { return false }
        return viewController.handleCharacterInput(characters) != .ignored
    }
    return handled ? nil : event
}
```

The settings branch must continue using Task 3R-B's `workspaceURLOpener(url)`; do not add a second opener or direct `NSWorkspace.shared.open` call.

- [x] **Step 4: Run keyboard entry regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'KeyboardNavigatorTests|LaunchPadViewControllerTests|HotkeyManagerTests|AppDelegateTests'
```

Expected: process exits 0 and does not open System Settings.

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPad/App/AppDelegate.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift
git commit -m "fix: suppress only handled application events"
```

---

### Task 10: Add Stable Layout Mutation Contracts and Test Doubles

**Execution-order gate:** Task numbers, not physical document position, define execution order. Complete Tasks 10-14 before Tasks 15-19; Task 16 imports `ItemPlacement`, Task 18 imports `LayoutMutating`, and Task 19 consumes the completed folder transaction behavior.

**Files:**
- Create: `Sources/LaunchPadProtocols/Models/LayoutDropIntent.swift`
- Modify: `Sources/LaunchPadProtocols/Protocols.swift:13-21`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift:23-61`
- Modify: `Tests/LaunchPadTests/Models/ProtocolTests.swift`

**Interfaces:**
- Produces: `ItemPlacement`, the six-case `LayoutDropIntent`, and independent `LayoutMutating`.
- Constraint: `DataStoring` must not inherit `LayoutMutating`.

- [x] **Step 1: Add RED protocol and mock tests**

```swift
@Test("layout mutator 记录稳定 intent 与容量")
func layoutMutatorRecordsIntentAndCapacity() throws {
    let sut = MockLayoutMutator()
    let intent = LayoutDropIntent.moveTopLevel(
        itemID: 8,
        placement: .beforeItem(itemID: 3)
    )
    try sut.apply(intent, pageCapacity: 35)
    #expect(sut.appliedIntents == [intent])
    #expect(sut.appliedPageCapacities == [35])
}

@Test("item placement 暴露稳定 anchor ID")
func placementAnchorID() {
    #expect(ItemPlacement.beforeItem(itemID: 4).anchorItemID == 4)
    #expect(ItemPlacement.afterItem(itemID: 9).anchorItemID == 9)
}

@Test("layout mutator 错误不记录未提交 intent")
func layoutMutatorFailureDoesNotRecordIntent() {
    let sut = MockLayoutMutator()
    sut.applyError = TestError.generic

    #expect(throws: TestError.self) {
        try sut.apply(
            .deleteFolder(folderID: 7),
            pageCapacity: 35
        )
    }
    #expect(sut.appliedIntents.isEmpty)
    #expect(sut.appliedPageCapacities.isEmpty)
}
```

- [x] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter ProtocolTests
```

- [x] **Step 3: Create the exact domain contracts**

```swift
import Foundation

public enum ItemPlacement: Sendable, Equatable {
    case beforeItem(itemID: Int64)
    case afterItem(itemID: Int64)

    public var anchorItemID: Int64 {
        switch self {
        case .beforeItem(let itemID), .afterItem(let itemID): itemID
        }
    }
}

public enum LayoutDropIntent: Sendable, Equatable {
    case moveTopLevel(itemID: Int64, placement: ItemPlacement)
    case addToFolder(itemID: Int64, folderID: Int64)
    case createFolder(itemID: Int64, targetItemID: Int64, title: String)
    case reorderFolderItem(
        itemID: Int64,
        folderID: Int64,
        placement: ItemPlacement
    )
    case removeFromFolder(
        itemID: Int64,
        folderID: Int64,
        placement: ItemPlacement
    )
    case deleteFolder(folderID: Int64)
}
```

The enum has exactly six cases. Do not add a constant `intents.count == 6` test because it only verifies its own fixture. Task 11's exhaustive `switch` plus one behavior test per intent is the compiler-backed completeness gate; adding a seventh case must break that switch and the domain test target build.

Add to `Protocols.swift` without changing `DataStoring`:

```swift
public protocol LayoutMutating: Sendable {
    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws
}
```

Add to `MockProtocols.swift`:

```swift
final class MockLayoutMutator: LayoutMutating, @unchecked Sendable {
    private(set) var appliedIntents: [LayoutDropIntent] = []
    private(set) var appliedPageCapacities: [Int] = []
    var applyError: Error?

    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws {
        if let applyError { throw applyError }
        appliedIntents.append(intent)
        appliedPageCapacities.append(pageCapacity)
    }
}
```

- [x] **Step 4: Run protocol tests GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter ProtocolTests
```

Expected: `ProtocolTests` exits 0 and the mutator success/failure plus placement assertions pass; Task 11 later supplies exhaustive six-intent behavior coverage.

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPadProtocols/Models/LayoutDropIntent.swift \
  Sources/LaunchPadProtocols/Protocols.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift \
  Tests/LaunchPadTests/Models/ProtocolTests.swift
git commit -m "feat: define stable layout mutation contracts"
```

---

### Task 11: Build the Pure Layout Domain State

**Files:**
- Create: `Sources/LaunchPad/Storage/LayoutDomainState.swift`
- Create: `Tests/LaunchPadTests/Storage/LayoutDomainStateTests.swift`

**Interfaces:**
- Consumes: Task 10 intents and existing item types.
- Produces: `validate(_:)`, `applyValidated(_:createdFolderID:)`, `apply(_:createdFolderID:)`, validated global/folder order, folder effects and dense page rebuild plans.

- [x] **Step 1: Write RED tests for all six intents and page reconstruction**

Create `LayoutDomainStateTests.swift` with the following helpers and tests. These tests intentionally reference the production types before they exist, so the first run must fail to compile.

```swift
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("Pure layout domain state")
struct LayoutDomainStateTests {
    private func node(_ id: Int64, _ type: ItemType = .app) -> LayoutNode {
        LayoutNode(id: id, type: type)
    }

    private func state(
        pages: [Int64] = [100],
        top: [LayoutNode],
        folders: [Int64: [LayoutNode]] = [:]
    ) -> LayoutDomainState {
        LayoutDomainState(
            existingPageIDs: pages,
            topLevelItems: top,
            childrenByFolderID: folders
        )
    }

    @Test("顶层 before/after 使用稳定 anchor")
    func moveTopLevelBeforeAndAfter() throws {
        var before = state(top: [node(1), node(2), node(3), node(4, .group)],
                           folders: [4: [node(40), node(41)]])
        _ = try before.apply(
            .moveTopLevel(itemID: 4, placement: .beforeItem(itemID: 2))
        )
        #expect(before.topLevelItems.map(\.id) == [1, 4, 2, 3])

        var after = state(top: [node(1), node(2), node(3)])
        _ = try after.apply(
            .moveTopLevel(itemID: 1, placement: .afterItem(itemID: 3))
        )
        #expect(after.topLevelItems.map(\.id) == [2, 3, 1])
    }

    @Test("顶层 stale/self drop 零变更")
    func moveTopLevelInvalidInputsDoNotMutate() {
        let intents: [LayoutDropIntent] = [
            .moveTopLevel(itemID: 99, placement: .beforeItem(itemID: 2)),
            .moveTopLevel(itemID: 1, placement: .beforeItem(itemID: 99)),
            .moveTopLevel(itemID: 1, placement: .afterItem(itemID: 1)),
        ]
        for intent in intents {
            var sut = state(top: [node(1), node(2)])
            let original = sut
            #expect(throws: LayoutDomainError.self) {
                _ = try sut.apply(intent)
            }
            #expect(sut == original)
        }
    }

    @Test("新文件夹占 target 位置且 children 保持原全局相对顺序")
    func createFolderPreservesGlobalOrder() throws {
        for (source, target) in [(Int64(3), Int64(1)), (Int64(1), Int64(3))] {
            var sut = state(top: [node(1), node(2), node(3)])
            let effects = try sut.apply(
                .createFolder(itemID: source, targetItemID: target, title: "Work"),
                createdFolderID: 90
            )
            #expect(sut.topLevelItems.map(\.id) == (target == 1 ? [90, 2] : [2, 90]))
            #expect(sut.childrenByFolderID[90]?.map(\.id) == [1, 3])
            #expect(effects.createdFolderTitle == "Work")
        }
    }

    @Test("create folder 拒绝 self/group/stale 且不变更")
    func createFolderRejectsInvalidInputs() {
        let base = state(
            top: [node(1), node(2), node(7, .group)],
            folders: [7: [node(70), node(71)]]
        )
        let intents: [LayoutDropIntent] = [
            .createFolder(itemID: 1, targetItemID: 1, title: "Work"),
            .createFolder(itemID: 7, targetItemID: 1, title: "Work"),
            .createFolder(itemID: 1, targetItemID: 7, title: "Work"),
            .createFolder(itemID: 99, targetItemID: 1, title: "Work"),
            .createFolder(itemID: 1, targetItemID: 99, title: "Work"),
        ]
        for intent in intents {
            var sut = base
            #expect(throws: LayoutDomainError.self) {
                _ = try sut.apply(intent, createdFolderID: 90)
            }
            #expect(sut == base)
        }
    }

    @Test("add folder 只接受顶层 app 和顶层 group")
    func addToFolderAppendsAndRejectsInvalidTypes() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(8, .group)],
            folders: [7: [node(70), node(71)], 8: [node(80), node(81)]]
        )
        _ = try sut.apply(.addToFolder(itemID: 1, folderID: 7))
        #expect(sut.topLevelItems.map(\.id) == [7, 8])
        #expect(sut.childrenByFolderID[7]?.map(\.id) == [70, 71, 1])

        let original = sut
        #expect(throws: LayoutDomainError.self) {
            _ = try sut.apply(.addToFolder(itemID: 8, folderID: 7))
        }
        #expect(sut == original)
    }

    @Test("folder 第 36 项可 before/after 重排，stale anchor 零变更")
    func reorderFolderItemThirtySix() throws {
        let children = (1...36).map { node(Int64($0)) }
        var sut = state(top: [node(7, .group)], folders: [7: children])
        _ = try sut.apply(
            .reorderFolderItem(
                itemID: 36,
                folderID: 7,
                placement: .beforeItem(itemID: 1)
            )
        )
        #expect(sut.childrenByFolderID[7]?.first?.id == 36)

        _ = try sut.apply(
            .reorderFolderItem(
                itemID: 36,
                folderID: 7,
                placement: .afterItem(itemID: 35)
            )
        )
        #expect(sut.childrenByFolderID[7]?.last?.id == 36)

        let original = sut
        #expect(throws: LayoutDomainError.self) {
            _ = try sut.apply(
                .reorderFolderItem(
                    itemID: 36,
                    folderID: 7,
                    placement: .afterItem(itemID: 99)
                )
            )
        }
        #expect(sut == original)
    }

    @Test("移出三项文件夹保留两个连续 child")
    func removeFromThreeItemFolderKeepsFolder() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(2)],
            folders: [7: [node(70), node(71), node(72)]]
        )
        let effects = try sut.apply(
            .removeFromFolder(
                itemID: 72,
                folderID: 7,
                placement: .beforeItem(itemID: 2)
            )
        )
        #expect(sut.topLevelItems.map(\.id) == [1, 7, 72, 2])
        #expect(sut.childrenByFolderID[7]?.map(\.id) == [70, 71])
        #expect(effects.folderIDsToDelete.isEmpty)
    }

    @Test("移出二项文件夹时 sibling 原位替换 folder")
    func removeFromTwoItemFolderAutoDissolves() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(2)],
            folders: [7: [node(70), node(71)]]
        )
        let effects = try sut.apply(
            .removeFromFolder(
                itemID: 71,
                folderID: 7,
                placement: .beforeItem(itemID: 2)
            )
        )
        #expect(sut.topLevelItems.map(\.id) == [1, 70, 71, 2])
        #expect(sut.childrenByFolderID[7] == nil)
        #expect(effects.folderIDsToDelete == [7])
    }

    @Test("folder 自身可作拖出锚点，单 child 移出后删除空 folder")
    func removeOnlyChildAllowsOwningFolderAnchor() throws {
        for placement in [
            ItemPlacement.beforeItem(itemID: 7),
            ItemPlacement.afterItem(itemID: 7),
        ] {
            var sut = state(
                top: [node(1), node(7, .group), node(2)],
                folders: [7: [node(70)]]
            )
            let effects = try sut.apply(
                .removeFromFolder(itemID: 70, folderID: 7, placement: placement)
            )
            #expect(sut.topLevelItems.map(\.id) == [1, 70, 2])
            #expect(effects.folderIDsToDelete == [7])
        }
    }

    @Test("安全删除在 folder 原位展开 children")
    func deleteFolderPreservesChildren() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(2)],
            folders: [7: [node(70), node(71)]]
        )
        let effects = try sut.apply(.deleteFolder(folderID: 7))
        #expect(sut.topLevelItems.map(\.id) == [1, 70, 71, 2])
        #expect(sut.childrenByFolderID[7] == nil)
        #expect(effects.folderIDsToDelete == [7])
    }

    @Test("page plan 复用、创建、删除并保留唯一空页")
    func pagePlanCoversEveryCardinality() throws {
        let overflow = state(
            pages: [100, 101],
            top: (1...5).map { node(Int64($0)) }
        )
        #expect(try overflow.makePageRebuildPlan(pageCapacity: 2) == PageRebuildPlan(
            pages: [
                .init(existingPageID: 100, ordering: 0, itemIDs: [1, 2]),
                .init(existingPageID: 101, ordering: 1, itemIDs: [3, 4]),
                .init(existingPageID: nil, ordering: 2, itemIDs: [5]),
            ],
            obsoletePageIDs: []
        ))

        let empty = state(pages: [100, 101], top: [])
        #expect(try empty.makePageRebuildPlan(pageCapacity: 35) == PageRebuildPlan(
            pages: [.init(existingPageID: 100, ordering: 0, itemIDs: [])],
            obsoletePageIDs: [101]
        ))
    }

    @Test("非法容量、重复 ID、嵌套 group、orphan folder 被拒绝")
    func invariantsRejectCorruptState() {
        let corruptStates = [
            state(pages: [100, 100], top: [node(1)]),
            state(top: [node(1), node(1)]),
            state(top: [node(7, .group)], folders: [7: [node(8, .group)]]),
            state(top: [node(1)], folders: [7: [node(70)]]),
        ]
        for sut in corruptStates {
            #expect(throws: LayoutDomainError.self) {
                _ = try sut.makePageRebuildPlan(pageCapacity: 35)
            }
        }
        let valid = state(top: [node(1)])
        #expect(throws: LayoutDomainError.self) {
            _ = try valid.makePageRebuildPlan(pageCapacity: 0)
        }
    }
}
```

- [x] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LayoutDomainStateTests
```

- [x] **Step 3: Add the complete domain implementation**

```swift
import Foundation
import LaunchPadProtocols

enum LayoutDomainError: Error, Equatable {
    case invalidPageCapacity
    case missingItem(Int64)
    case missingAnchor(Int64)
    case missingCreatedFolderID
    case invalidType(Int64)
    case invalidParent(Int64)
    case selfDrop
    case duplicateItem(Int64)
    case duplicatePage(Int64)
    case orphanFolder(Int64)
    case unsupportedIntent
    case persistedStateMismatch
}

struct LayoutNode: Equatable, Sendable {
    let id: Int64
    let type: ItemType
}

struct LayoutMutationEffects: Equatable {
    var folderIDsToDelete: Set<Int64> = []
    var createdFolderTitle: String?
}

struct PageRebuildPlan: Equatable {
    struct Page: Equatable {
        let existingPageID: Int64?
        let ordering: Int
        let itemIDs: [Int64]
    }
    let pages: [Page]
    let obsoletePageIDs: [Int64]
}

struct LayoutDomainState: Equatable {
    private(set) var existingPageIDs: [Int64]
    private(set) var topLevelItems: [LayoutNode]
    private(set) var childrenByFolderID: [Int64: [LayoutNode]]

    init(
        existingPageIDs: [Int64],
        topLevelItems: [LayoutNode],
        childrenByFolderID: [Int64: [LayoutNode]]
    ) {
        self.existingPageIDs = existingPageIDs
        self.topLevelItems = topLevelItems
        self.childrenByFolderID = childrenByFolderID
    }

    func validateState() throws {
        var seen = Set<Int64>()
        for pageID in existingPageIDs {
            guard seen.insert(pageID).inserted else {
                throw LayoutDomainError.duplicatePage(pageID)
            }
        }
        for node in topLevelItems {
            guard node.type == .app || node.type == .group else {
                throw LayoutDomainError.invalidType(node.id)
            }
            guard seen.insert(node.id).inserted else {
                throw LayoutDomainError.duplicateItem(node.id)
            }
            if node.type == .group, childrenByFolderID[node.id] == nil {
                throw LayoutDomainError.orphanFolder(node.id)
            }
        }
        let topFolderIDs = Set(
            topLevelItems.filter { $0.type == .group }.map(\.id)
        )
        for (folderID, children) in childrenByFolderID {
            guard topFolderIDs.contains(folderID) else {
                throw LayoutDomainError.orphanFolder(folderID)
            }
            for child in children {
                guard child.type == .app else {
                    throw LayoutDomainError.invalidType(child.id)
                }
                guard seen.insert(child.id).inserted else {
                    throw LayoutDomainError.duplicateItem(child.id)
                }
            }
        }
    }

    func validate(_ intent: LayoutDropIntent) throws {
        try validateState()
        switch intent {
        case .moveTopLevel(let itemID, let placement):
            try validateTopLevelNode(itemID)
            guard itemID != placement.anchorItemID else {
                throw LayoutDomainError.selfDrop
            }
            try validateTopLevelNode(placement.anchorItemID)

        case .addToFolder(let itemID, let folderID):
            try validateTopLevelApp(itemID)
            try validateTopLevelFolder(folderID)

        case .createFolder(let itemID, let targetItemID, _):
            guard itemID != targetItemID else {
                throw LayoutDomainError.selfDrop
            }
            try validateTopLevelApp(itemID)
            try validateTopLevelApp(targetItemID)

        case .reorderFolderItem(let itemID, let folderID, let placement):
            try validateTopLevelFolder(folderID)
            let children = try folderChildren(folderID)
            guard itemID != placement.anchorItemID else {
                throw LayoutDomainError.selfDrop
            }
            try validateChild(itemID, in: children, folderID: folderID)
            guard children.contains(where: { $0.id == placement.anchorItemID }) else {
                throw LayoutDomainError.missingAnchor(placement.anchorItemID)
            }

        case .removeFromFolder(let itemID, let folderID, let placement):
            try validateTopLevelFolder(folderID)
            let children = try folderChildren(folderID)
            try validateChild(itemID, in: children, folderID: folderID)
            try validateTopLevelNode(placement.anchorItemID)

        case .deleteFolder(let folderID):
            try validateTopLevelFolder(folderID)
            _ = try folderChildren(folderID)
        }
    }

    mutating func apply(
        _ intent: LayoutDropIntent,
        createdFolderID: Int64? = nil
    ) throws -> LayoutMutationEffects {
        try validate(intent)
        let effects = try applyValidated(
            intent,
            createdFolderID: createdFolderID
        )
        try validateState()
        return effects
    }

    mutating func applyValidated(
        _ intent: LayoutDropIntent,
        createdFolderID: Int64? = nil
    ) throws -> LayoutMutationEffects {
        var effects = LayoutMutationEffects()
        switch intent {
        case .moveTopLevel(let itemID, let placement):
            topLevelItems = try Self.moving(
                topLevelItems,
                itemID: itemID,
                placement: placement
            )

        case .addToFolder(let itemID, let folderID):
            guard let sourceIndex = topLevelItems.firstIndex(where: { $0.id == itemID }) else {
                throw LayoutDomainError.missingItem(itemID)
            }
            let source = topLevelItems.remove(at: sourceIndex)
            childrenByFolderID[folderID, default: []].append(source)

        case .createFolder(let itemID, let targetItemID, let title):
            guard let folderID = createdFolderID else {
                throw LayoutDomainError.missingCreatedFolderID
            }
            let occupiedIDs = Set(existingPageIDs)
                .union(topLevelItems.map(\.id))
                .union(childrenByFolderID.values.flatMap { $0.map(\.id) })
            guard !occupiedIDs.contains(folderID) else {
                throw LayoutDomainError.duplicateItem(folderID)
            }
            guard let sourceIndex = topLevelItems.firstIndex(where: { $0.id == itemID }),
                  let targetIndex = topLevelItems.firstIndex(where: { $0.id == targetItemID }) else {
                throw LayoutDomainError.missingItem(itemID)
            }
            let orderedChildren = [
                (sourceIndex, topLevelItems[sourceIndex]),
                (targetIndex, topLevelItems[targetIndex]),
            ].sorted { $0.0 < $1.0 }.map { $0.1 }
            let insertionIndex = topLevelItems[..<targetIndex]
                .filter { $0.id != itemID && $0.id != targetItemID }
                .count
            topLevelItems.removeAll { $0.id == itemID || $0.id == targetItemID }
            topLevelItems.insert(
                LayoutNode(id: folderID, type: .group),
                at: insertionIndex
            )
            childrenByFolderID[folderID] = orderedChildren
            effects.createdFolderTitle = title

        case .reorderFolderItem(let itemID, let folderID, let placement):
            guard let children = childrenByFolderID[folderID] else {
                throw LayoutDomainError.invalidParent(folderID)
            }
            childrenByFolderID[folderID] = try Self.moving(
                children,
                itemID: itemID,
                placement: placement
            )

        case .removeFromFolder(let itemID, let folderID, let placement):
            guard var children = childrenByFolderID[folderID],
                  let sourceIndex = children.firstIndex(where: { $0.id == itemID }),
                  let folderIndex = topLevelItems.firstIndex(where: { $0.id == folderID }) else {
                throw LayoutDomainError.invalidParent(folderID)
            }
            let source = children.remove(at: sourceIndex)
            let usesOwningFolderAnchor = placement.anchorItemID == folderID

            if children.count >= 2 {
                childrenByFolderID[folderID] = children
                if usesOwningFolderAnchor {
                    let insertionIndex = switch placement {
                    case .beforeItem: folderIndex
                    case .afterItem: folderIndex + 1
                    }
                    topLevelItems.insert(source, at: insertionIndex)
                } else {
                    topLevelItems = try Self.insertingExternal(
                        source,
                        into: topLevelItems,
                        placement: placement
                    )
                }
            } else {
                topLevelItems.remove(at: folderIndex)
                childrenByFolderID.removeValue(forKey: folderID)
                effects.folderIDsToDelete.insert(folderID)
                if let remaining = children.first {
                    topLevelItems.insert(remaining, at: folderIndex)
                }
                if usesOwningFolderAnchor {
                    let insertionIndex = switch placement {
                    case .beforeItem: folderIndex
                    case .afterItem: children.isEmpty ? folderIndex : folderIndex + 1
                    }
                    topLevelItems.insert(source, at: insertionIndex)
                } else {
                    topLevelItems = try Self.insertingExternal(
                        source,
                        into: topLevelItems,
                        placement: placement
                    )
                }
            }

        case .deleteFolder(let folderID):
            guard let folderIndex = topLevelItems.firstIndex(where: { $0.id == folderID }),
                  let children = childrenByFolderID[folderID] else {
                throw LayoutDomainError.invalidParent(folderID)
            }
            topLevelItems.remove(at: folderIndex)
            topLevelItems.insert(contentsOf: children, at: folderIndex)
            childrenByFolderID.removeValue(forKey: folderID)
            effects.folderIDsToDelete.insert(folderID)
        }
        return effects
    }

    private static func moving(
        _ nodes: [LayoutNode],
        itemID: Int64,
        placement: ItemPlacement
    ) throws -> [LayoutNode] {
        guard itemID != placement.anchorItemID else { throw LayoutDomainError.selfDrop }
        guard let source = nodes.first(where: { $0.id == itemID }) else {
            throw LayoutDomainError.missingItem(itemID)
        }
        var result = nodes.filter { $0.id != itemID }
        guard let anchor = result.firstIndex(where: { $0.id == placement.anchorItemID }) else {
            throw LayoutDomainError.missingAnchor(placement.anchorItemID)
        }
        let insertion = switch placement {
        case .beforeItem: anchor
        case .afterItem: anchor + 1
        }
        result.insert(source, at: insertion)
        return result
    }

    private static func insertingExternal(
        _ source: LayoutNode,
        into nodes: [LayoutNode],
        placement: ItemPlacement
    ) throws -> [LayoutNode] {
        guard !nodes.contains(where: { $0.id == source.id }) else {
            throw LayoutDomainError.duplicateItem(source.id)
        }
        guard let anchorIndex = nodes.firstIndex(where: {
            $0.id == placement.anchorItemID
        }) else {
            throw LayoutDomainError.missingAnchor(placement.anchorItemID)
        }
        var result = nodes
        let insertionIndex = switch placement {
        case .beforeItem: anchorIndex
        case .afterItem: anchorIndex + 1
        }
        result.insert(source, at: insertionIndex)
        return result
    }

    private func validateTopLevelNode(_ itemID: Int64) throws {
        guard let node = topLevelItems.first(where: { $0.id == itemID }) else {
            throw LayoutDomainError.missingItem(itemID)
        }
        guard node.type == .app || node.type == .group else {
            throw LayoutDomainError.invalidType(itemID)
        }
    }

    private func validateTopLevelApp(_ itemID: Int64) throws {
        guard let node = topLevelItems.first(where: { $0.id == itemID }) else {
            throw LayoutDomainError.missingItem(itemID)
        }
        guard node.type == .app else {
            throw LayoutDomainError.invalidType(itemID)
        }
    }

    private func validateTopLevelFolder(_ folderID: Int64) throws {
        guard let node = topLevelItems.first(where: { $0.id == folderID }) else {
            throw LayoutDomainError.missingItem(folderID)
        }
        guard node.type == .group else {
            throw LayoutDomainError.invalidType(folderID)
        }
        guard childrenByFolderID[folderID] != nil else {
            throw LayoutDomainError.invalidParent(folderID)
        }
    }

    private func folderChildren(_ folderID: Int64) throws -> [LayoutNode] {
        guard let children = childrenByFolderID[folderID] else {
            throw LayoutDomainError.invalidParent(folderID)
        }
        return children
    }

    private func validateChild(
        _ itemID: Int64,
        in children: [LayoutNode],
        folderID: Int64
    ) throws {
        guard let child = children.first(where: { $0.id == itemID }) else {
            throw LayoutDomainError.invalidParent(folderID)
        }
        guard child.type == .app else {
            throw LayoutDomainError.invalidType(itemID)
        }
    }

    func makePageRebuildPlan(pageCapacity: Int) throws -> PageRebuildPlan {
        guard pageCapacity > 0 else {
            throw LayoutDomainError.invalidPageCapacity
        }
        try validateState()
        let chunks: [[LayoutNode]] = topLevelItems.isEmpty
            ? [[]]
            : stride(from: 0, to: topLevelItems.count, by: pageCapacity).map {
                start in
                Array(topLevelItems[
                    start..<min(start + pageCapacity, topLevelItems.count)
                ])
            }
        let pages = chunks.enumerated().map { ordering, chunk in
            PageRebuildPlan.Page(
                existingPageID: ordering < existingPageIDs.count
                    ? existingPageIDs[ordering]
                    : nil,
                ordering: ordering,
                itemIDs: chunk.map(\.id)
            )
        }
        return PageRebuildPlan(
            pages: pages,
            obsoletePageIDs: Array(existingPageIDs.dropFirst(pages.count))
        )
    }
}
```

- [x] **Step 4: Run all domain tests GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LayoutDomainStateTests
```

Expected: all six intent branches, folder item 36, owning-folder anchor, and all page-plan branches pass.

- [x] **Step 5: Commit**

```bash
git add Sources/LaunchPad/Storage/LayoutDomainState.swift \
  Tests/LaunchPadTests/Storage/LayoutDomainStateTests.swift
git commit -m "feat: model atomic layout mutations"
```

---

### Task 12: Serialize SQLite Access and Check Every Transaction Boundary

**Files:**
- Create: `Sources/LaunchPad/Storage/SQLiteTransaction.swift`
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift:7-361`
- Modify: `Tests/LaunchPadTests/Storage/StorageManagerTests.swift`

**Interfaces:**
- Consumes: one SQLite connection.
- Produces: one `databaseQueue`, `SQLiteDriver`, checked deferred/immediate transactions, one `runTransaction` invalidation boundary, and unusable state after rollback failure.

- [x] **Step 1: Add transaction and serialization RED tests**

Add the following support and tests to `StorageManagerTests.swift`:

```swift
final class SQLiteFaultScript: @unchecked Sendable {
    private struct ScheduledFailure {
        var callsUntilFailure: Int
        let code: Int32
    }

    private let lock = NSLock()
    private var failures: [SQLiteFaultPoint: [ScheduledFailure]] = [:]

    func failNext(_ point: SQLiteFaultPoint, code: Int32) {
        fail(point, onOccurrence: 1, code: code)
    }

    func fail(
        _ point: SQLiteFaultPoint,
        onOccurrence: Int,
        code: Int32
    ) {
        precondition(onOccurrence > 0)
        lock.lock()
        failures[point, default: []].append(
            ScheduledFailure(
                callsUntilFailure: onOccurrence,
                code: code
            )
        )
        lock.unlock()
    }

    func result(for point: SQLiteFaultPoint) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard var scheduled = failures[point], !scheduled.isEmpty else {
            return nil
        }
        scheduled[0].callsUntilFailure -= 1
        if scheduled[0].callsUntilFailure == 0 {
            let code = scheduled.removeFirst().code
            failures[point] = scheduled
            return code
        }
        failures[point] = scheduled
        return nil
    }
}

private final class QueueObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func append(_ value: Bool) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var snapshot: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private func makeFaultableStorage(
    _ script: SQLiteFaultScript
) throws -> StorageManager {
    try StorageManager(
        dbPath: ":memory:",
        schemaSetup: { Schema.setupSchema(db: $0) },
        faultInjector: script.result(for:)
    )
}

@Test("BEGIN 失败不执行事务 body")
func beginFailureDoesNotWrite() throws {
    let script = SQLiteFaultScript()
    let sut = try makeFaultableStorage(script)
    script.failNext(.begin, code: SQLITE_BUSY)

    #expect(throws: StorageError.beginFailed) {
        _ = try sut.insertItem(
            TestDataFactory.makePageItem(
                uuid: "begin-failure",
                type: .page
            )
        )
    }
    #expect(try sut.fetchAllItems(parentId: nil).isEmpty)
}

@Test("COMMIT 失败回滚 insert")
func commitFailureRollsBackInsert() throws {
    let script = SQLiteFaultScript()
    let sut = try makeFaultableStorage(script)
    script.failNext(.commit, code: SQLITE_IOERR)

    #expect(throws: StorageError.commitFailed) {
        _ = try sut.insertItem(
            TestDataFactory.makePageItem(
                uuid: "commit-failure",
                type: .page
            )
        )
    }
    #expect(try sut.fetchAllItems(parentId: nil).isEmpty)
}

@Test("ROLLBACK 失败保留 primary error 并使 storage 不可用")
func rollbackFailureInvalidatesStorage() throws {
    let script = SQLiteFaultScript()
    let sut = try makeFaultableStorage(script)
    _ = try sut.insertItem(
        TestDataFactory.makePageItem(uuid: "duplicate", type: .page)
    )
    script.failNext(.rollback, code: SQLITE_IOERR)

    do {
        _ = try sut.insertItem(
            TestDataFactory.makePageItem(uuid: "duplicate", type: .page)
        )
        Issue.record("expected SQLiteRollbackFailure")
    } catch let error as SQLiteRollbackFailure {
        #expect(error.primaryError is StorageError)
        #expect(error.rollbackCode == SQLITE_IOERR)
    }
    #expect(throws: StorageError.storageUnavailable) {
        _ = try sut.fetchAllItems(parentId: nil)
    }
}

@Test("所有公开读写入口位于同一 databaseQueue")
func everyPublicMethodUsesDatabaseQueue() throws {
    let sut = try StorageManager(dbPath: ":memory:")
    let recorder = QueueObservationRecorder()
    sut.databaseAccessObserver = { recorder.append($0) }

    let pageID = try sut.insertItem(
        TestDataFactory.makePageItem(uuid: "queue-page", type: .page)
    )
    let app = TestDataFactory.makeAppInfo(
        title: "Queue",
        bundleId: "com.test.queue"
    )
    let appID = try sut.insertItem(
        TestDataFactory.makePageItem(
            uuid: "queue-app",
            type: .app,
            parentId: pageID,
            app: app
        )
    )
    _ = try sut.fetchAllItems(parentId: pageID)
    try sut.updateItem(PageItem(
        id: appID,
        uuid: "queue-app",
        type: .app,
        ordering: 0,
        parentId: pageID,
        app: AppInfo(
            id: appID,
            title: "Queue Updated",
            bundleId: "com.test.queue",
            path: app.path,
            storeId: nil,
            category: nil
        ),
        group: nil
    ))
    try sut.reorderItems(parentId: pageID, orderedIds: [appID])
    try sut.saveImage(itemId: appID, icon1x: Data([1]), icon2x: Data([2]))
    _ = try sut.fetchImage(itemId: appID)
    try sut.deleteItem(id: appID)

    #expect(!recorder.snapshot.isEmpty)
    #expect(recorder.snapshot.allSatisfy { $0 })
}
```

- [x] **Step 2: Run StorageManager tests and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter StorageManager
```

Expected: the command matches the file-level transaction tests plus every named `StorageManager*Tests` suite; verify the test runner reports at least the four new tests before accepting RED.

- [x] **Step 3: Create the checked SQLite driver and transaction runner**

```swift
import Foundation
import SQLite3

enum SQLiteStatementKind: Hashable, Sendable {
    case fetchItems
    case fetchAllItems
    case insertItem
    case insertAppMetadata
    case insertGroupMetadata
    case updateItem
    case updateAppMetadata
    case updateGroupMetadata
    case deleteItem
    case reorderItem
    case saveImage
    case fetchImage
    case updateLayoutItem
    case updatePageOrdering
    case insertPage
    case deleteLayoutItem
}

enum SQLiteFaultPoint: Hashable, Sendable {
    case begin
    case prepare(SQLiteStatementKind)
    case bind(SQLiteStatementKind, index: Int32)
    case step(SQLiteStatementKind)
    case changes(SQLiteStatementKind)
    case commit
    case rollback
}

struct SQLiteDriver: @unchecked Sendable {
    typealias FaultInjector = @Sendable (SQLiteFaultPoint) -> Int32?

    let faultInjector: FaultInjector?

    func execute(
        database: OpaquePointer,
        sql: String,
        point: SQLiteFaultPoint
    ) -> Int32 {
        if let code = faultInjector?(point) { return code }
        return sqlite3_exec(database, sql, nil, nil, nil)
    }

    func prepare(
        database: OpaquePointer,
        sql: String,
        statement: inout OpaquePointer?,
        kind: SQLiteStatementKind
    ) -> Int32 {
        if let code = faultInjector?(.prepare(kind)) { return code }
        return sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    }

    func bind(
        _ operation: @autoclosure () -> Int32,
        kind: SQLiteStatementKind,
        index: Int32
    ) -> Int32 {
        if let code = faultInjector?(.bind(kind, index: index)) { return code }
        return operation()
    }

    func step(
        _ statement: OpaquePointer?,
        kind: SQLiteStatementKind
    ) -> Int32 {
        if let code = faultInjector?(.step(kind)) { return code }
        return sqlite3_step(statement)
    }

    func changes(
        database: OpaquePointer,
        kind: SQLiteStatementKind
    ) -> Int32 {
        if let count = faultInjector?(.changes(kind)) { return count }
        return sqlite3_changes(database)
    }
}

enum SQLiteTransactionMode: Sendable, Equatable {
    case deferred
    case immediate
}

struct SQLiteRollbackFailure: Error {
    let primaryError: Error
    let rollbackCode: Int32
}

struct SQLiteTransaction {
    let database: OpaquePointer
    let driver: SQLiteDriver

    func run<T>(
        mode: SQLiteTransactionMode,
        body: () throws -> T
    ) throws -> T {
        let begin = mode == .immediate ? "BEGIN IMMEDIATE" : "BEGIN"
        guard driver.execute(
            database: database,
            sql: begin,
            point: .begin
        ) == SQLITE_OK else {
            throw StorageError.beginFailed
        }
        do {
            let result = try body()
            guard driver.execute(
                database: database,
                sql: "COMMIT",
                point: .commit
            ) == SQLITE_OK else {
                throw StorageError.commitFailed
            }
            return result
        } catch {
            let primary = error
            // SQLITE_IOERR/FULL/NOMEM or RAISE(ROLLBACK) may have already
            // ended the transaction. Never issue a synthetic rollback after
            // SQLite has returned to autocommit mode.
            guard sqlite3_get_autocommit(database) == 0 else {
                throw primary
            }
            let rollbackCode = driver.execute(
                database: database,
                sql: "ROLLBACK",
                point: .rollback
            )
            guard rollbackCode == SQLITE_OK else {
                throw SQLiteRollbackFailure(
                    primaryError: primary,
                    rollbackCode: rollbackCode
                )
            }
            throw primary
        }
    }
}
```

- [x] **Step 4: Replace both queues and initialize the driver**

Replace `db`, `readQueue`, `writeQueue`, both initializers and `deinit` with this structure:

```swift
private var db: OpaquePointer?
private let databaseQueue = DispatchQueue(
    label: "com.launchpad.storage.database",
    qos: .userInitiated
)
private let databaseQueueKey = DispatchSpecificKey<UInt8>()
private let databaseQueueToken: UInt8 = 1
private let sqliteDriver: SQLiteDriver
private var isUsable = true

internal var databaseAccessObserver: (@Sendable (Bool) -> Void)?

public convenience init(dbPath: String) throws {
    try self.init(
        dbPath: dbPath,
        schemaSetup: { Schema.setupSchema(db: $0) },
        faultInjector: nil
    )
}

internal init(
    dbPath: String,
    schemaSetup: (OpaquePointer) -> Void,
    faultInjector: SQLiteDriver.FaultInjector? = nil
) throws {
    sqliteDriver = SQLiteDriver(faultInjector: faultInjector)
    databaseQueue.setSpecific(
        key: databaseQueueKey,
        value: databaseQueueToken
    )
    if sqlite3_open(dbPath, &db) != SQLITE_OK {
        throw StorageError.openFailed
    }
    guard let database = db else { throw StorageError.openFailed }
    _ = sqlite3_exec(database, "PRAGMA journal_mode=WAL", nil, nil, nil)
    _ = sqlite3_exec(database, "PRAGMA foreign_keys=ON", nil, nil, nil)
    schemaSetup(database)
}

deinit {
    databaseQueue.sync {
        if let db {
            _ = sqlite3_close_v2(db)
            self.db = nil
        }
    }
}

private func requireDatabase() throws -> OpaquePointer {
    guard isUsable, let db else { throw StorageError.storageUnavailable }
    return db
}

private func invalidateDatabase() {
    isUsable = false
    if let db {
        _ = sqlite3_close_v2(db)
        self.db = nil
    }
}

private func withDatabase<T>(
    _ body: (OpaquePointer) throws -> T
) throws -> T {
    try databaseQueue.sync {
        databaseAccessObserver?(
            DispatchQueue.getSpecific(key: databaseQueueKey)
                == databaseQueueToken
        )
        return try body(requireDatabase())
    }
}

private func runTransaction<T>(
    database: OpaquePointer,
    mode: SQLiteTransactionMode,
    body: () throws -> T
) throws -> T {
    do {
        return try SQLiteTransaction(
            database: database,
            driver: sqliteDriver
        ).run(mode: mode, body: body)
    } catch let rollbackFailure as SQLiteRollbackFailure {
        invalidateDatabase()
        throw rollbackFailure
    }
}
```

- [x] **Step 5: Route every existing public method through `withDatabase`**

Use these exact wrappers; the private statement functions contain the SQL currently in the corresponding source ranges and accept the nonoptional local pointer:

```swift
@discardableResult
public func insertItem(_ item: PageItem) throws -> Int64 {
    try withDatabase { database in
        try runTransaction(database: database, mode: .deferred) {
            try insertItemStatement(item, database: database)
        }
    }
}

public func updateItem(_ item: PageItem) throws {
    try withDatabase { database in
        try runTransaction(database: database, mode: .deferred) {
            try updateItemStatement(item, database: database)
        }
    }
}

public func deleteItem(id: Int64) throws {
    try withDatabase { database in
        try deleteItemStatement(id: id, database: database)
    }
}

public func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
    try withDatabase { database in
        try fetchItems(parentID: parentId, database: database)
    }
}

public func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {
    try withDatabase { database in
        try runTransaction(database: database, mode: .deferred) {
            try reorderItemsStatement(
                parentID: parentId,
                orderedIDs: orderedIds,
                database: database
            )
        }
    }
}

public func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {
    try withDatabase { database in
        try saveImageStatement(
            itemID: itemId,
            icon1x: icon1x,
            icon2x: icon2x,
            database: database
        )
    }
}

public func fetchImage(itemId: Int64) throws -> (Data, Data)? {
    try withDatabase { database in
        try fetchImageStatement(itemID: itemId, database: database)
    }
}
```

Add the shared transient destructor and checked bind helpers first. Every
statement helper uses the nonoptional local database pointer; no transaction
body calls a public method:

```swift
private static let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

private func bindText(
    _ value: String?,
    statement: OpaquePointer?,
    index: Int32,
    kind: SQLiteStatementKind
) throws {
    let code: Int32
    if let value {
        code = sqliteDriver.bind(
            sqlite3_bind_text(
                statement,
                index,
                (value as NSString).utf8String,
                -1,
                Self.sqliteTransient
            ),
            kind: kind,
            index: index
        )
    } else {
        code = sqliteDriver.bind(
            sqlite3_bind_null(statement, index),
            kind: kind,
            index: index
        )
    }
    guard code == SQLITE_OK else { throw StorageError.bindFailed }
}

private func bindInt64(
    _ value: Int64?,
    statement: OpaquePointer?,
    index: Int32,
    kind: SQLiteStatementKind
) throws {
    let code = value.map {
        sqliteDriver.bind(
            sqlite3_bind_int64(statement, index, $0),
            kind: kind,
            index: index
        )
    } ?? sqliteDriver.bind(
        sqlite3_bind_null(statement, index),
        kind: kind,
        index: index
    )
    guard code == SQLITE_OK else { throw StorageError.bindFailed }
}

private func insertItemStatement(
    _ item: PageItem,
    database: OpaquePointer
) throws -> Int64 {
    let kind = SQLiteStatementKind.insertItem
    let sql = """
        INSERT INTO items (uuid, type, parent_id, ordering)
        VALUES (?, ?, ?, ?)
        """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindText(item.uuid, statement: statement, index: 1, kind: kind)
    guard sqliteDriver.bind(
        sqlite3_bind_int(statement, 2, Int32(item.type.rawValue)),
        kind: kind,
        index: 2
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    try bindInt64(item.parentId, statement: statement, index: 3, kind: kind)
    guard sqliteDriver.bind(
        sqlite3_bind_int(statement, 4, Int32(item.ordering)),
        kind: kind,
        index: 4
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.insertFailed
    }
    let itemID = sqlite3_last_insert_rowid(database)
    switch item.type {
    case .app:
        if let app = item.app {
            try insertAppMetadata(
                itemID: itemID,
                app: app,
                database: database
            )
        }
    case .group:
        if let group = item.group {
            try insertGroupMetadata(
                itemID: itemID,
                group: group,
                database: database
            )
        }
    case .page:
        break
    }
    return itemID
}

private func insertAppMetadata(
    itemID: Int64,
    app: AppInfo,
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.insertAppMetadata
    let sql = """
        INSERT INTO apps
            (item_id, title, bundle_id, store_id, category, path)
        VALUES (?, ?, ?, ?, ?, ?)
        """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindInt64(itemID, statement: statement, index: 1, kind: kind)
    try bindText(app.title, statement: statement, index: 2, kind: kind)
    try bindText(app.bundleId, statement: statement, index: 3, kind: kind)
    try bindText(app.storeId, statement: statement, index: 4, kind: kind)
    try bindText(app.category, statement: statement, index: 5, kind: kind)
    try bindText(app.path, statement: statement, index: 6, kind: kind)
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.insertFailed
    }
}

private func insertGroupMetadata(
    itemID: Int64,
    group: GroupInfo,
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.insertGroupMetadata
    let sql = "INSERT INTO groups (item_id, title) VALUES (?, ?)"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindInt64(itemID, statement: statement, index: 1, kind: kind)
    try bindText(group.title, statement: statement, index: 2, kind: kind)
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.insertFailed
    }
}

private func updateItemStatement(
    _ item: PageItem,
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.updateItem
    let sql = "UPDATE items SET ordering = ?, parent_id = ? WHERE id = ?"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    guard sqliteDriver.bind(
        sqlite3_bind_int(statement, 1, Int32(item.ordering)),
        kind: kind,
        index: 1
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    try bindInt64(item.parentId, statement: statement, index: 2, kind: kind)
    try bindInt64(item.id, statement: statement, index: 3, kind: kind)
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.updateFailed
    }
    if let app = item.app {
        try updateAppMetadata(itemID: item.id, app: app, database: database)
    }
    if let group = item.group {
        try updateGroupMetadata(
            itemID: item.id,
            group: group,
            database: database
        )
    }
}

private func updateAppMetadata(
    itemID: Int64,
    app: AppInfo,
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.updateAppMetadata
    let sql = """
        UPDATE apps
        SET title = ?, path = ?, store_id = ?, category = ?
        WHERE item_id = ?
        """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindText(app.title, statement: statement, index: 1, kind: kind)
    try bindText(app.path, statement: statement, index: 2, kind: kind)
    try bindText(app.storeId, statement: statement, index: 3, kind: kind)
    try bindText(app.category, statement: statement, index: 4, kind: kind)
    try bindInt64(itemID, statement: statement, index: 5, kind: kind)
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.updateFailed
    }
}

private func updateGroupMetadata(
    itemID: Int64,
    group: GroupInfo,
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.updateGroupMetadata
    let sql = "UPDATE groups SET title = ? WHERE item_id = ?"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindText(group.title, statement: statement, index: 1, kind: kind)
    try bindInt64(itemID, statement: statement, index: 2, kind: kind)
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.updateFailed
    }
}

private func deleteItemStatement(
    id: Int64,
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.deleteItem
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: "DELETE FROM items WHERE id = ?",
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindInt64(id, statement: statement, index: 1, kind: kind)
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.deleteFailed
    }
}

private func fetchItems(
    parentID: Int64?,
    database: OpaquePointer
) throws -> [PageItem] {
    let kind = SQLiteStatementKind.fetchItems
    let predicate = parentID == nil
        ? "i.parent_id IS NULL"
        : "i.parent_id = ?"
    let sql = """
        SELECT i.id, i.uuid, i.type, i.ordering, i.parent_id,
               a.title, a.bundle_id, a.path, a.store_id, a.category,
               g.title
        FROM items i
        LEFT JOIN apps a ON i.id = a.item_id
        LEFT JOIN groups g ON i.id = g.item_id
        WHERE \(predicate)
        ORDER BY i.ordering
        """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    if let parentID {
        try bindInt64(parentID, statement: statement, index: 1, kind: kind)
    }
    var items: [PageItem] = []
    var stepCode = sqliteDriver.step(statement, kind: kind)
    while stepCode == SQLITE_ROW {
        items.append(decodePageItem(statement: statement))
        stepCode = sqliteDriver.step(statement, kind: kind)
    }
    guard stepCode == SQLITE_DONE else { throw StorageError.queryFailed }
    return items
}

private func reorderItemsStatement(
    parentID: Int64,
    orderedIDs: [Int64],
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.reorderItem
    let sql = "UPDATE items SET ordering = ?, parent_id = ? WHERE id = ?"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    for (ordering, id) in orderedIDs.enumerated() {
        guard sqlite3_reset(statement) == SQLITE_OK,
              sqlite3_clear_bindings(statement) == SQLITE_OK else {
            throw StorageError.updateFailed
        }
        guard sqliteDriver.bind(
            sqlite3_bind_int(statement, 1, Int32(ordering)),
            kind: kind,
            index: 1
        ) == SQLITE_OK else { throw StorageError.bindFailed }
        try bindInt64(parentID, statement: statement, index: 2, kind: kind)
        try bindInt64(id, statement: statement, index: 3, kind: kind)
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.updateFailed
        }
    }
}

private func saveImageStatement(
    itemID: Int64,
    icon1x: Data,
    icon2x: Data,
    database: OpaquePointer
) throws {
    let kind = SQLiteStatementKind.saveImage
    let sql = """
        INSERT OR REPLACE INTO image_cache (item_id, icon_1x, icon_2x)
        VALUES (?, ?, ?)
        """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindInt64(itemID, statement: statement, index: 1, kind: kind)
    let firstCode = icon1x.withUnsafeBytes { bytes in
        sqliteDriver.bind(
            sqlite3_bind_blob(
                statement, 2, bytes.baseAddress,
                Int32(bytes.count), Self.sqliteTransient
            ),
            kind: kind,
            index: 2
        )
    }
    let secondCode = icon2x.withUnsafeBytes { bytes in
        sqliteDriver.bind(
            sqlite3_bind_blob(
                statement, 3, bytes.baseAddress,
                Int32(bytes.count), Self.sqliteTransient
            ),
            kind: kind,
            index: 3
        )
    }
    guard firstCode == SQLITE_OK, secondCode == SQLITE_OK else {
        throw StorageError.bindFailed
    }
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: kind) == 1 else {
        throw StorageError.insertFailed
    }
}

private func fetchImageStatement(
    itemID: Int64,
    database: OpaquePointer
) throws -> (Data, Data)? {
    let kind = SQLiteStatementKind.fetchImage
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: "SELECT icon_1x, icon_2x FROM image_cache WHERE item_id = ?",
        statement: &statement,
        kind: kind
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    try bindInt64(itemID, statement: statement, index: 1, kind: kind)
    let firstStep = sqliteDriver.step(statement, kind: kind)
    guard firstStep != SQLITE_DONE else { return nil }
    guard firstStep == SQLITE_ROW else { throw StorageError.queryFailed }
    let result: (Data, Data)?
    if let first = sqlite3_column_blob(statement, 0),
       let second = sqlite3_column_blob(statement, 1) {
        result = (
            Data(
                bytes: first,
                count: Int(sqlite3_column_bytes(statement, 0))
            ),
            Data(
                bytes: second,
                count: Int(sqlite3_column_bytes(statement, 1))
            )
        )
    } else {
        result = nil
    }
    guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE else {
        throw StorageError.queryFailed
    }
    return result
}
```

Use this decoder in both `fetchItems` and Task 13's all-items snapshot reader; it is the complete replacement for the current inline column decoding:

```swift
private func decodePageItem(statement: OpaquePointer?) -> PageItem {
    let id = sqlite3_column_int64(statement, 0)
    let uuid = sqlite3_column_text(statement, 1).map {
        String(cString: $0)
    } ?? ""
    let typeRaw = Int(sqlite3_column_int(statement, 2))
    let ordering = Int(sqlite3_column_int(statement, 3))
    let parentID: Int64? = sqlite3_column_type(statement, 4) == SQLITE_NULL
        ? nil
        : sqlite3_column_int64(statement, 4)
    let type = ItemType(rawValue: typeRaw) ?? .app
    var app: AppInfo?
    var group: GroupInfo?
    if type == .app {
        app = AppInfo(
            id: id,
            title: sqlite3_column_text(statement, 5).map {
                String(cString: $0)
            } ?? "",
            bundleId: sqlite3_column_text(statement, 6).map {
                String(cString: $0)
            } ?? "",
            path: sqlite3_column_text(statement, 7).map {
                String(cString: $0)
            } ?? "",
            storeId: sqlite3_column_text(statement, 8).map {
                String(cString: $0)
            },
            category: sqlite3_column_text(statement, 9).map {
                String(cString: $0)
            }
        )
    } else if type == .group {
        group = GroupInfo(
            id: id,
            title: sqlite3_column_text(statement, 10).map {
                String(cString: $0)
            } ?? "New Folder"
        )
    }
    return PageItem(
        id: id,
        uuid: uuid,
        type: type,
        ordering: ordering,
        parentId: parentID,
        app: app,
        group: group
    )
}
```

- [x] **Step 6: Extend stable storage errors**

```swift
public enum StorageError: Error, Equatable {
    case openFailed
    case prepareFailed
    case insertFailed
    case updateFailed
    case deleteFailed
    case bindFailed
    case queryFailed
    case beginFailed
    case commitFailed
    case storageUnavailable
}
```

- [x] **Step 7: Run storage and null-field suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter StorageManager
```

Expected suites include `StorageManagerTests`, `StorageManagerAdvancedTests`, `StorageManagerUpdateTests`, `StorageManagerFetchImageNullBlobTests`, and `StorageManagerFetchAllItemsNullFieldsTests`; command exit 0 is required.

- [x] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Storage/SQLiteTransaction.swift \
  Sources/LaunchPad/Storage/StorageManager.swift \
  Tests/LaunchPadTests/Storage/StorageManagerTests.swift
git commit -m "fix: serialize and verify sqlite transactions"
```

---

### Task 13: Persist Top-level Layout Mutations Atomically

**Files:**
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift`
- Create: `Tests/LaunchPadTests/Storage/StorageManagerLayoutMutationTests.swift`

**Interfaces:**
- Consumes: Tasks 10-12.
- Produces: `PersistedLayoutSnapshot`, transaction-local complete layout reads, `StorageManager: LayoutMutating` for stable top-level before/after, and resolved dense page rebuilds.

- [x] **Step 1: Add top-level persistence RED tests**

Create `StorageManagerLayoutMutationTests.swift` with this seed helper and the complete top-level tests:

```swift
import Foundation
import SQLite3
import Testing
import LaunchPadProtocols
@testable import LaunchPad

@Suite("StorageManager atomic layout mutations")
struct StorageManagerLayoutMutationTests {
    private struct IDs {
        let first: Int64
        let second: Int64
        let third: Int64
        let fourth: Int64
    }

    private func makeTwoPageLayout(
        script: SQLiteFaultScript = SQLiteFaultScript()
    ) throws -> (StorageManager, IDs, SQLiteFaultScript) {
        let storage = try StorageManager(
            dbPath: ":memory:",
            schemaSetup: { Schema.setupSchema(db: $0) },
            faultInjector: script.result(for:)
        )
        let firstPage = try storage.insertItem(
            TestDataFactory.makePageItem(uuid: "page-1", type: .page, ordering: 0)
        )
        let secondPage = try storage.insertItem(
            TestDataFactory.makePageItem(uuid: "page-2", type: .page, ordering: 1)
        )
        func insertApp(_ index: Int, pageID: Int64, ordering: Int) throws -> Int64 {
            try storage.insertItem(
                TestDataFactory.makePageItem(
                    uuid: "layout-app-\(index)",
                    type: .app,
                    ordering: ordering,
                    parentId: pageID,
                    app: TestDataFactory.makeAppInfo(
                        title: "App \(index)",
                        bundleId: "com.test.layout.\(index)"
                    )
                )
            )
        }
        let first = try insertApp(1, pageID: firstPage, ordering: 0)
        let second = try insertApp(2, pageID: firstPage, ordering: 1)
        let third = try insertApp(3, pageID: secondPage, ordering: 0)
        let fourth = try insertApp(4, pageID: secondPage, ordering: 1)
        return (
            storage,
            IDs(first: first, second: second, third: third, fourth: fourth),
            script
        )
    }

    @Test("跨页 before 提交稳定全局顺序和连续 page ordering")
    func moveTopLevelPersistsCrossPageOrder() throws {
        let (sut, ids, _) = try makeTwoPageLayout()
        try sut.apply(
            .moveTopLevel(
                itemID: ids.fourth,
                placement: .beforeItem(itemID: ids.second)
            ),
            pageCapacity: 2
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.pages.map(\.ordering) == [0, 1])
        #expect(snapshot.flattenedTopLevelIDs == [
            ids.first, ids.fourth, ids.second, ids.third,
        ])
        #expect(snapshot.pageChildren.values.allSatisfy { children in
            children.map(\.ordering) == Array(0..<children.count)
        })
    }

    @Test("same-page after 使用 anchor 当前数据库位置")
    func moveTopLevelPersistsSamePageAfter() throws {
        let (sut, ids, _) = try makeTwoPageLayout()
        try sut.apply(
            .moveTopLevel(
                itemID: ids.first,
                placement: .afterItem(itemID: ids.second)
            ),
            pageCapacity: 2
        )
        #expect(try sut.persistedLayoutSnapshot().flattenedTopLevelIDs == [
            ids.second, ids.first, ids.third, ids.fourth,
        ])
    }

    @Test("stale source/anchor、self 和零容量零写入")
    func rejectedTopLevelMutationsLeaveCompleteSnapshotUnchanged() throws {
        for scenario in 0..<4 {
            let (sut, ids, _) = try makeTwoPageLayout()
            let intent: LayoutDropIntent
            let capacity: Int
            switch scenario {
            case 0:
                intent = .moveTopLevel(
                    itemID: 999,
                    placement: .beforeItem(itemID: ids.first)
                )
                capacity = 2
            case 1:
                intent = .moveTopLevel(
                    itemID: ids.first,
                    placement: .beforeItem(itemID: 999)
                )
                capacity = 2
            case 2:
                intent = .moveTopLevel(
                    itemID: ids.first,
                    placement: .afterItem(itemID: ids.first)
                )
                capacity = 2
            default:
                intent = .moveTopLevel(
                    itemID: ids.first,
                    placement: .afterItem(itemID: ids.second)
                )
                capacity = 0
            }
            let before = try sut.persistedLayoutSnapshot()
            #expect(throws: LayoutDomainError.self) {
                try sut.apply(intent, pageCapacity: capacity)
            }
            #expect(try sut.persistedLayoutSnapshot() == before)
        }
    }

    struct InjectedFault: Sendable {
        let point: SQLiteFaultPoint
        let occurrence: Int
        let code: Int32
    }

    @Test(
        "read/prepare/bind/step/changes/COMMIT 失败完整回滚",
        arguments: [
            InjectedFault(point: .prepare(.fetchAllItems), occurrence: 1, code: SQLITE_ERROR),
            InjectedFault(point: .step(.fetchAllItems), occurrence: 1, code: SQLITE_IOERR),
            InjectedFault(point: .prepare(.updateLayoutItem), occurrence: 1, code: SQLITE_ERROR),
            InjectedFault(point: .bind(.updateLayoutItem, index: 1), occurrence: 1, code: SQLITE_RANGE),
            InjectedFault(point: .step(.updateLayoutItem), occurrence: 2, code: SQLITE_CONSTRAINT),
            InjectedFault(point: .changes(.updateLayoutItem), occurrence: 1, code: 0),
            InjectedFault(point: .commit, occurrence: 1, code: SQLITE_IOERR),
        ]
    )
    func injectedTopLevelFailureRollsBack(_ fault: InjectedFault) throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(
            fault.point,
            onOccurrence: fault.occurrence,
            code: fault.code
        )

        #expect(throws: (any Error).self) {
            try sut.apply(
                .moveTopLevel(
                    itemID: ids.fourth,
                    placement: .beforeItem(itemID: ids.first)
                ),
                pageCapacity: 2
            )
        }
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("扩页 insert 和缩页 delete 失败完整回滚")
    func pageInsertAndDeleteFailuresRollBack() throws {
        do {
            let (sut, ids, script) = try makeTwoPageLayout()
            let before = try sut.persistedLayoutSnapshot()
            script.failNext(.step(.insertPage), code: SQLITE_FULL)
            #expect(throws: (any Error).self) {
                try sut.apply(
                    .moveTopLevel(
                        itemID: ids.fourth,
                        placement: .beforeItem(itemID: ids.first)
                    ),
                    pageCapacity: 1
                )
            }
            #expect(try sut.persistedLayoutSnapshot() == before)
        }
        do {
            let (sut, ids, script) = try makeTwoPageLayout()
            let before = try sut.persistedLayoutSnapshot()
            script.failNext(.step(.deleteLayoutItem), code: SQLITE_CONSTRAINT)
            #expect(throws: (any Error).self) {
                try sut.apply(
                    .moveTopLevel(
                        itemID: ids.fourth,
                        placement: .beforeItem(itemID: ids.first)
                    ),
                    pageCapacity: 4
                )
            }
            #expect(try sut.persistedLayoutSnapshot() == before)
        }
    }
}
```

- [x] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter StorageManagerLayoutMutationTests
```

- [x] **Step 3: Add the complete persisted snapshot and transaction-local reader**

Add these types next to `StorageManager`; `allItems` contains every `items` row joined with app/group metadata, so equality covers root rows, page rows, group title, direct page children, folder children and orphan rows:

```swift
struct PersistedLayoutSnapshot: Equatable {
    let allItems: [PageItem]

    var rootItems: [PageItem] {
        allItems.filter { $0.parentId == nil }.sorted(by: Self.layoutOrder)
    }

    var pages: [PageItem] {
        rootItems.filter { $0.type == .page }
    }

    var pageChildren: [Int64: [PageItem]] {
        Dictionary(uniqueKeysWithValues: pages.map { page in
            (page.id, children(of: page.id))
        })
    }

    var folderChildren: [Int64: [PageItem]] {
        let groups = allItems.filter { $0.type == .group }
        return Dictionary(uniqueKeysWithValues: groups.map { group in
            (group.id, children(of: group.id))
        })
    }

    var flattenedTopLevelIDs: [Int64] {
        pages.flatMap { pageChildren[$0.id] ?? [] }.map(\.id)
    }

    func children(of parentID: Int64) -> [PageItem] {
        allItems.filter { $0.parentId == parentID }.sorted(by: Self.layoutOrder)
    }

    private static func layoutOrder(_ lhs: PageItem, _ rhs: PageItem) -> Bool {
        lhs.ordering == rhs.ordering ? lhs.id < rhs.id : lhs.ordering < rhs.ordering
    }
}
```

Add the all-row reader. It uses Task 12's exact decoder and verifies the terminal `SQLITE_DONE` code:

```swift
private func fetchAllPersistedItems(
    database: OpaquePointer
) throws -> [PageItem] {
    let sql = """
        SELECT i.id, i.uuid, i.type, i.ordering, i.parent_id,
               a.title, a.bundle_id, a.path, a.store_id, a.category,
               g.title
        FROM items i
        LEFT JOIN apps a ON i.id = a.item_id
        LEFT JOIN groups g ON i.id = g.item_id
        ORDER BY i.id
        """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: .fetchAllItems
    ) == SQLITE_OK else {
        throw StorageError.prepareFailed
    }
    var items: [PageItem] = []
    var stepCode = sqliteDriver.step(statement, kind: .fetchAllItems)
    while stepCode == SQLITE_ROW {
        items.append(decodePageItem(statement: statement))
        stepCode = sqliteDriver.step(statement, kind: .fetchAllItems)
    }
    guard stepCode == SQLITE_DONE else { throw StorageError.queryFailed }
    return items
}

private func readPersistedLayoutSnapshot(
    database: OpaquePointer
) throws -> PersistedLayoutSnapshot {
    PersistedLayoutSnapshot(
        allItems: try fetchAllPersistedItems(database: database)
    )
}

func persistedLayoutSnapshot() throws -> PersistedLayoutSnapshot {
    try withDatabase { database in
        try readPersistedLayoutSnapshot(database: database)
    }
}

private func readLayoutDomainState(
    snapshot: PersistedLayoutSnapshot
) throws -> LayoutDomainState {
    guard snapshot.rootItems.allSatisfy({ $0.type == .page }) else {
        throw LayoutDomainError.invalidParent(
            snapshot.rootItems.first { $0.type != .page }?.id ?? 0
        )
    }
    var reachable = Set(snapshot.pages.map(\.id))
    var topLevel: [LayoutNode] = []
    var folderChildren: [Int64: [LayoutNode]] = [:]
    for page in snapshot.pages {
        let children = snapshot.pageChildren[page.id] ?? []
        guard children.allSatisfy({ $0.type == .app || $0.type == .group }) else {
            throw LayoutDomainError.invalidType(
                children.first { $0.type == .page }?.id ?? page.id
            )
        }
        for child in children {
            guard reachable.insert(child.id).inserted else {
                throw LayoutDomainError.duplicateItem(child.id)
            }
            topLevel.append(LayoutNode(id: child.id, type: child.type))
            if child.type == .group {
                let nested = snapshot.folderChildren[child.id] ?? []
                guard nested.allSatisfy({ $0.type == .app }) else {
                    throw LayoutDomainError.invalidType(
                        nested.first { $0.type != .app }?.id ?? child.id
                    )
                }
                for item in nested {
                    guard reachable.insert(item.id).inserted else {
                        throw LayoutDomainError.duplicateItem(item.id)
                    }
                }
                folderChildren[child.id] = nested.map {
                    LayoutNode(id: $0.id, type: $0.type)
                }
            }
        }
    }
    let allIDs = Set(snapshot.allItems.map(\.id))
    guard reachable == allIDs else {
        throw LayoutDomainError.invalidParent(
            allIDs.subtracting(reachable).sorted().first ?? 0
        )
    }
    return LayoutDomainState(
        existingPageIDs: snapshot.pages.map(\.id),
        topLevelItems: topLevel,
        childrenByFolderID: folderChildren
    )
}
```

- [x] **Step 4: Add checked page/item writers and resolved page persistence**

Add these exact helpers. Every reused page row is explicitly rewritten to `(parent_id: NULL, ordering: denseIndex)` before item updates:

```swift
private struct ResolvedPage {
    let id: Int64
    let ordering: Int
    let itemIDs: [Int64]
}

private func updateParentAndOrdering(
    itemID: Int64,
    parentID: Int64,
    ordering: Int,
    database: OpaquePointer
) throws {
    let sql = "UPDATE items SET parent_id = ?, ordering = ? WHERE id = ?"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: .updateLayoutItem
    ) == SQLITE_OK else {
        throw StorageError.prepareFailed
    }
    guard sqliteDriver.bind(
        sqlite3_bind_int64(statement, 1, parentID),
        kind: .updateLayoutItem,
        index: 1
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_int(statement, 2, Int32(ordering)),
        kind: .updateLayoutItem,
        index: 2
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_int64(statement, 3, itemID),
        kind: .updateLayoutItem,
        index: 3
    ) == SQLITE_OK else {
        throw StorageError.bindFailed
    }
    guard sqliteDriver.step(statement, kind: .updateLayoutItem) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: .updateLayoutItem) == 1 else {
        throw StorageError.updateFailed
    }
}

private func updatePageOrdering(
    pageID: Int64,
    ordering: Int,
    database: OpaquePointer
) throws {
    let sql = "UPDATE items SET parent_id = NULL, ordering = ? WHERE id = ? AND type = ?"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: .updatePageOrdering
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    guard sqliteDriver.bind(
        sqlite3_bind_int(statement, 1, Int32(ordering)),
        kind: .updatePageOrdering,
        index: 1
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_int64(statement, 2, pageID),
        kind: .updatePageOrdering,
        index: 2
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_int(statement, 3, Int32(ItemType.page.rawValue)),
        kind: .updatePageOrdering,
        index: 3
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    guard sqliteDriver.step(statement, kind: .updatePageOrdering) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: .updatePageOrdering) == 1 else {
        throw StorageError.updateFailed
    }
}

private func insertPage(
    ordering: Int,
    database: OpaquePointer
) throws -> Int64 {
    let sql = "INSERT INTO items (uuid, type, parent_id, ordering) VALUES (?, ?, NULL, ?)"
    let uuid = UUID().uuidString
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: .insertPage
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    guard sqliteDriver.bind(
        sqlite3_bind_text(
            statement,
            1,
            (uuid as NSString).utf8String,
            -1,
            Self.sqliteTransient
        ),
        kind: .insertPage,
        index: 1
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_int(statement, 2, Int32(ItemType.page.rawValue)),
        kind: .insertPage,
        index: 2
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_int(statement, 3, Int32(ordering)),
        kind: .insertPage,
        index: 3
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    guard sqliteDriver.step(statement, kind: .insertPage) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: .insertPage) == 1 else {
        throw StorageError.insertFailed
    }
    return sqlite3_last_insert_rowid(database)
}

private func deleteLayoutItem(
    itemID: Int64,
    database: OpaquePointer
) throws {
    let sql = "DELETE FROM items WHERE id = ?"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: sql,
        statement: &statement,
        kind: .deleteLayoutItem
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    guard sqliteDriver.bind(
        sqlite3_bind_int64(statement, 1, itemID),
        kind: .deleteLayoutItem,
        index: 1
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    guard sqliteDriver.step(statement, kind: .deleteLayoutItem) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: .deleteLayoutItem) == 1 else {
        throw StorageError.deleteFailed
    }
}

private func persistPagePlan(
    _ plan: PageRebuildPlan,
    database: OpaquePointer
) throws -> [ResolvedPage] {
    var resolved: [ResolvedPage] = []
    for page in plan.pages {
        let pageID: Int64
        if let existingPageID = page.existingPageID {
            pageID = existingPageID
        } else {
            pageID = try insertPage(
                ordering: page.ordering,
                database: database
            )
        }
        try updatePageOrdering(
            pageID: pageID,
            ordering: page.ordering,
            database: database
        )
        resolved.append(ResolvedPage(
            id: pageID,
            ordering: page.ordering,
            itemIDs: page.itemIDs
        ))
    }
    for page in resolved {
        for (ordering, itemID) in page.itemIDs.enumerated() {
            try updateParentAndOrdering(
                itemID: itemID,
                parentID: page.id,
                ordering: ordering,
                database: database
            )
        }
    }
    for obsoletePageID in plan.obsoletePageIDs {
        try deleteLayoutItem(itemID: obsoletePageID, database: database)
    }
    return resolved
}
```

Reuse Task 12's single `sqliteTransient` constant; do not declare a second
copy in Task 13.

- [x] **Step 5: Add exact post-write invariant verification**

```swift
private func verifyPersistedLayout(
    state: LayoutDomainState,
    pages: [ResolvedPage],
    createdFolderTitles: [Int64: String] = [:],
    database: OpaquePointer
) throws {
    let snapshot = try readPersistedLayoutSnapshot(database: database)
    guard snapshot.pages.map(\.id) == pages.map(\.id),
          snapshot.pages.map(\.ordering) == Array(0..<pages.count) else {
        throw LayoutDomainError.persistedStateMismatch
    }
    for page in pages {
        let children = snapshot.pageChildren[page.id] ?? []
        guard children.map(\.id) == page.itemIDs,
              children.map(\.ordering) == Array(0..<children.count) else {
            throw LayoutDomainError.persistedStateMismatch
        }
    }
    guard snapshot.flattenedTopLevelIDs == state.topLevelItems.map(\.id) else {
        throw LayoutDomainError.persistedStateMismatch
    }
    for (folderID, expectedChildren) in state.childrenByFolderID {
        let children = snapshot.folderChildren[folderID] ?? []
        guard children.map(\.id) == expectedChildren.map(\.id),
              children.map(\.ordering) == Array(0..<children.count),
              children.allSatisfy({ $0.type == .app }) else {
            throw LayoutDomainError.persistedStateMismatch
        }
    }
    for (folderID, title) in createdFolderTitles {
        guard snapshot.allItems.first(where: { $0.id == folderID })?.group?.title
                == title else {
            throw LayoutDomainError.persistedStateMismatch
        }
    }
    let expectedIDs = Set(pages.map(\.id))
        .union(state.topLevelItems.map(\.id))
        .union(state.childrenByFolderID.values.flatMap { $0.map(\.id) })
    guard Set(snapshot.allItems.map(\.id)) == expectedIDs else {
        throw LayoutDomainError.persistedStateMismatch
    }
}
```

- [x] **Step 6: Implement the atomic top-level entry**

Make the class declaration `StorageManager: DataStoring, LayoutMutating, @unchecked Sendable` and add this method. Task 12's `runTransaction` is the only place that catches rollback failure and invalidates the connection:

```swift
public func apply(
    _ intent: LayoutDropIntent,
    pageCapacity: Int
) throws {
    try withDatabase { database in
        try runTransaction(database: database, mode: .immediate) {
            guard case .moveTopLevel = intent else {
                throw LayoutDomainError.unsupportedIntent
            }
            let before = try readPersistedLayoutSnapshot(database: database)
            var state = try readLayoutDomainState(snapshot: before)
            _ = try state.apply(intent)
            let plan = try state.makePageRebuildPlan(
                pageCapacity: pageCapacity
            )
            let resolvedPages = try persistPagePlan(
                plan,
                database: database
            )
            try verifyPersistedLayout(
                state: state,
                pages: resolvedPages,
                database: database
            )
        }
    }
}
```

- [x] **Step 7: Run layout mutation suite GREEN and storage regression**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainState'
```

Expected: all real `StorageManager*` suites and `LayoutDomainStateTests` execute and exit 0.

- [x] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Storage/StorageManager.swift \
  Tests/LaunchPadTests/Storage/StorageManagerLayoutMutationTests.swift
git commit -m "feat: persist top-level layout mutations atomically"
```

---

### Task 14: Persist Every Folder Mutation and Safe Delete Atomically

**Files:**
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift`
- Modify: `Tests/LaunchPadTests/Storage/StorageManagerLayoutMutationTests.swift`
- Modify: `Tests/LaunchPadTests/Integration/IntegrationTests.swift:201-315`

**Interfaces:**
- Consumes: Task 13 entry and Task 11 folder branches.
- Produces: create/add/reorder/remove/auto-dissolve/zero-child cleanup/safe-delete.

- [x] **Step 1: Add complete folder RED tests**

Append this extension to `StorageManagerLayoutMutationTests.swift`; it uses the complete snapshot from Task 13, not `LayoutPersistence`'s two-level projection:

```swift
extension StorageManagerLayoutMutationTests {
    private struct FolderIDs {
        let before: Int64
        let folder: Int64
        let after: Int64
        let children: [Int64]
    }

    private func makeFolderLayout(
        childCount: Int = 2,
        script: SQLiteFaultScript = SQLiteFaultScript()
    ) throws -> (StorageManager, FolderIDs, SQLiteFaultScript) {
        let storage = try StorageManager(
            dbPath: ":memory:",
            schemaSetup: { Schema.setupSchema(db: $0) },
            faultInjector: script.result(for:)
        )
        let pageID = try storage.insertItem(
            TestDataFactory.makePageItem(uuid: "folder-page", type: .page)
        )
        func app(_ suffix: String, parentID: Int64, ordering: Int) throws -> Int64 {
            try storage.insertItem(
                TestDataFactory.makePageItem(
                    uuid: "folder-app-\(suffix)",
                    type: .app,
                    ordering: ordering,
                    parentId: parentID,
                    app: TestDataFactory.makeAppInfo(
                        title: "Folder App \(suffix)",
                        bundleId: "com.test.folder.\(suffix)"
                    )
                )
            )
        }
        let before = try app("before", parentID: pageID, ordering: 0)
        let folder = try storage.insertItem(
            TestDataFactory.makePageItem(
                uuid: "folder",
                type: .group,
                ordering: 1,
                parentId: pageID,
                group: TestDataFactory.makeGroupInfo(title: "Folder")
            )
        )
        let after = try app("after", parentID: pageID, ordering: 2)
        let children = try (0..<childCount).map { index in
            try app("child-\(index)", parentID: folder, ordering: index)
        }
        return (
            storage,
            FolderIDs(before: before, folder: folder, after: after, children: children),
            script
        )
    }

    @Test("create folder 保持全局相对顺序和 target 位置")
    func createFolderPersistsOrderAndTitle() throws {
        let (sut, ids, _) = try makeTwoPageLayout()
        try sut.apply(
            .createFolder(
                itemID: ids.fourth,
                targetItemID: ids.second,
                title: "Work"
            ),
            pageCapacity: 2
        )
        let snapshot = try sut.persistedLayoutSnapshot()
        let folder = try #require(
            snapshot.allItems.first { $0.group?.title == "Work" }
        )
        #expect(snapshot.flattenedTopLevelIDs == [ids.first, folder.id, ids.third])
        #expect(snapshot.folderChildren[folder.id]?.map(\.id) == [ids.second, ids.fourth])
    }

    @Test("create folder 第二个 child UPDATE 失败回滚 folder row/title/children")
    func createFolderSecondChildFailureRollsBack() throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(
            .step(.updateLayoutItem),
            onOccurrence: 2,
            code: SQLITE_CONSTRAINT
        )
        #expect(throws: (any Error).self) {
            try sut.apply(
                .createFolder(
                    itemID: ids.fourth,
                    targetItemID: ids.second,
                    title: "Rollback"
                ),
                pageCapacity: 2
            )
        }
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("add folder 末尾追加并从顶层移除")
    func addToFolderAppendsDenseChild() throws {
        let (sut, ids, _) = try makeFolderLayout()
        try sut.apply(
            .addToFolder(itemID: ids.before, folderID: ids.folder),
            pageCapacity: 3
        )
        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [ids.folder, ids.after])
        #expect(snapshot.folderChildren[ids.folder]?.map(\.id)
            == ids.children + [ids.before])
        #expect(snapshot.folderChildren[ids.folder]?.map(\.ordering) == [0, 1, 2])
    }

    @Test("folder 内 before/after 重排并拒绝 wrong parent")
    func reorderFolderItemPersistsAndRejectsWrongParent() throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 3)
        try sut.apply(
            .reorderFolderItem(
                itemID: ids.children[2],
                folderID: ids.folder,
                placement: .beforeItem(itemID: ids.children[0])
            ),
            pageCapacity: 3
        )
        #expect(try sut.persistedLayoutSnapshot()
            .folderChildren[ids.folder]?.map(\.id)
            == [ids.children[2], ids.children[0], ids.children[1]])

        let before = try sut.persistedLayoutSnapshot()
        #expect(throws: LayoutDomainError.self) {
            try sut.apply(
                .reorderFolderItem(
                    itemID: ids.after,
                    folderID: ids.folder,
                    placement: .afterItem(itemID: ids.children[0])
                ),
                pageCapacity: 3
            )
        }
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("移出三项文件夹保留两个 dense children")
    func removeFromThreeItemFolderPersists() throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 3)
        try sut.apply(
            .removeFromFolder(
                itemID: ids.children[2],
                folderID: ids.folder,
                placement: .beforeItem(itemID: ids.after)
            ),
            pageCapacity: 4
        )
        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [
            ids.before, ids.folder, ids.children[2], ids.after,
        ])
        #expect(snapshot.folderChildren[ids.folder]?.map(\.id)
            == Array(ids.children.prefix(2)))
    }

    @Test("移出二项文件夹支持 owning-folder anchor 并自动解散")
    func removeFromTwoItemFolderAutoDissolves() throws {
        let (sut, ids, _) = try makeFolderLayout()
        try sut.apply(
            .removeFromFolder(
                itemID: ids.children[1],
                folderID: ids.folder,
                placement: .afterItem(itemID: ids.folder)
            ),
            pageCapacity: 4
        )
        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [
            ids.before, ids.children[0], ids.children[1], ids.after,
        ])
        #expect(snapshot.allItems.contains { $0.id == ids.folder } == false)
    }

    @Test("移出唯一 child 删除空 folder")
    func removeOnlyChildDeletesFolder() throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 1)
        try sut.apply(
            .removeFromFolder(
                itemID: ids.children[0],
                folderID: ids.folder,
                placement: .beforeItem(itemID: ids.folder)
            ),
            pageCapacity: 3
        )
        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [
            ids.before, ids.children[0], ids.after,
        ])
        #expect(snapshot.allItems.contains { $0.id == ids.folder } == false)
    }

    @Test("safe delete 原位展开且 overflow 创建新页")
    func deleteFolderPreservesChildrenAndSpillsPage() throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 3)
        try sut.apply(.deleteFolder(folderID: ids.folder), pageCapacity: 2)
        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [
            ids.before,
            ids.children[0],
            ids.children[1],
            ids.children[2],
            ids.after,
        ])
        #expect(snapshot.pages.count == 3)
        #expect(snapshot.allItems.contains { $0.id == ids.folder } == false)
    }

    @Test("folder stale anchor 和中途 step 失败完整 snapshot 不变")
    func folderFailuresLeaveCompleteSnapshotUnchanged() throws {
        do {
            let (sut, ids, _) = try makeFolderLayout()
            let before = try sut.persistedLayoutSnapshot()
            #expect(throws: LayoutDomainError.self) {
                try sut.apply(
                    .removeFromFolder(
                        itemID: ids.children[0],
                        folderID: ids.folder,
                        placement: .afterItem(itemID: 999)
                    ),
                    pageCapacity: 3
                )
            }
            #expect(try sut.persistedLayoutSnapshot() == before)
        }
        do {
            let (sut, ids, script) = try makeFolderLayout()
            let before = try sut.persistedLayoutSnapshot()
            script.failNext(.step(.updateLayoutItem), code: SQLITE_IOERR)
            #expect(throws: (any Error).self) {
                try sut.apply(
                    .addToFolder(itemID: ids.before, folderID: ids.folder),
                    pageCapacity: 3
                )
            }
            #expect(try sut.persistedLayoutSnapshot() == before)
        }
    }

    @Test(
        "create folder 两张 INSERT 的 prepare/bind/step/changes 失败完整回滚",
        arguments: [
            InjectedFault(
                point: .prepare(.insertItem),
                occurrence: 1,
                code: SQLITE_ERROR
            ),
            InjectedFault(
                point: .bind(.insertItem, index: 1),
                occurrence: 1,
                code: SQLITE_RANGE
            ),
            InjectedFault(
                point: .bind(.insertItem, index: 2),
                occurrence: 1,
                code: SQLITE_RANGE
            ),
            InjectedFault(
                point: .step(.insertItem),
                occurrence: 1,
                code: SQLITE_FULL
            ),
            InjectedFault(
                point: .changes(.insertItem),
                occurrence: 1,
                code: 0
            ),
            InjectedFault(
                point: .prepare(.insertGroupMetadata),
                occurrence: 1,
                code: SQLITE_ERROR
            ),
            InjectedFault(
                point: .bind(.insertGroupMetadata, index: 1),
                occurrence: 1,
                code: SQLITE_RANGE
            ),
            InjectedFault(
                point: .bind(.insertGroupMetadata, index: 2),
                occurrence: 1,
                code: SQLITE_RANGE
            ),
            InjectedFault(
                point: .step(.insertGroupMetadata),
                occurrence: 1,
                code: SQLITE_FULL
            ),
            InjectedFault(
                point: .changes(.insertGroupMetadata),
                occurrence: 1,
                code: 0
            ),
        ]
    )
    func createFolderInsertFailureRollsBack(_ fault: InjectedFault) throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(
            fault.point,
            onOccurrence: fault.occurrence,
            code: fault.code
        )

        #expect(throws: (any Error).self) {
            try sut.apply(
                .createFolder(
                    itemID: ids.fourth,
                    targetItemID: ids.second,
                    title: "Never committed"
                ),
                pageCapacity: 2
            )
        }
        #expect(try sut.persistedLayoutSnapshot() == before)
    }
}
```

- [x] **Step 2: Run and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter StorageManagerLayoutMutationTests
```

Expected: the ten create-folder INSERT fault arguments fail for the expected
missing checked `insertFolder` path; the command must report the parameterized
test rather than succeeding with zero matches.

- [x] **Step 3: Add checked folder insertion inside the transaction**

Add this helper. Both rows are written only after `state.validate(intent)` succeeds:

```swift
private func insertFolder(
    title: String,
    database: OpaquePointer
) throws -> Int64 {
    let itemSQL = "INSERT INTO items (uuid, type, parent_id, ordering) VALUES (?, ?, NULL, 0)"
    let uuid = UUID().uuidString
    var itemStatement: OpaquePointer?
    defer { sqlite3_finalize(itemStatement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: itemSQL,
        statement: &itemStatement,
        kind: .insertItem
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    guard sqliteDriver.bind(
        sqlite3_bind_text(
            itemStatement,
            1,
            (uuid as NSString).utf8String,
            -1,
            Self.sqliteTransient
        ),
        kind: .insertItem,
        index: 1
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_int(itemStatement, 2, Int32(ItemType.group.rawValue)),
        kind: .insertItem,
        index: 2
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    guard sqliteDriver.step(itemStatement, kind: .insertItem) == SQLITE_DONE,
          sqliteDriver.changes(database: database, kind: .insertItem) == 1 else {
        throw StorageError.insertFailed
    }
    let folderID = sqlite3_last_insert_rowid(database)

    let metadataSQL = "INSERT INTO groups (item_id, title) VALUES (?, ?)"
    var metadataStatement: OpaquePointer?
    defer { sqlite3_finalize(metadataStatement) }
    guard sqliteDriver.prepare(
        database: database,
        sql: metadataSQL,
        statement: &metadataStatement,
        kind: .insertGroupMetadata
    ) == SQLITE_OK else { throw StorageError.prepareFailed }
    guard sqliteDriver.bind(
        sqlite3_bind_int64(metadataStatement, 1, folderID),
        kind: .insertGroupMetadata,
        index: 1
    ) == SQLITE_OK,
    sqliteDriver.bind(
        sqlite3_bind_text(
            metadataStatement,
            2,
            (title as NSString).utf8String,
            -1,
            Self.sqliteTransient
        ),
        kind: .insertGroupMetadata,
        index: 2
    ) == SQLITE_OK else { throw StorageError.bindFailed }
    guard sqliteDriver.step(
        metadataStatement,
        kind: .insertGroupMetadata
    ) == SQLITE_DONE,
    sqliteDriver.changes(
        database: database,
        kind: .insertGroupMetadata
    ) == 1 else {
        throw StorageError.insertFailed
    }
    return folderID
}
```

- [x] **Step 4: Add exhaustive folder persistence to `apply`**

Add the child writer and replace Task 13's temporary move-only `apply` with the exhaustive version below:

```swift
private func persistFolderChildren(
    _ childrenByFolderID: [Int64: [LayoutNode]],
    database: OpaquePointer
) throws {
    for folderID in childrenByFolderID.keys.sorted() {
        let children = childrenByFolderID[folderID] ?? []
        for (ordering, child) in children.enumerated() {
            try updateParentAndOrdering(
                itemID: child.id,
                parentID: folderID,
                ordering: ordering,
                database: database
            )
        }
    }
}

public func apply(
    _ intent: LayoutDropIntent,
    pageCapacity: Int
) throws {
    try withDatabase { database in
        try runTransaction(database: database, mode: .immediate) {
            let before = try readPersistedLayoutSnapshot(database: database)
            var state = try readLayoutDomainState(snapshot: before)
            try state.validate(intent)

            let createdFolderID: Int64? = switch intent {
            case .createFolder(_, _, let title):
                try insertFolder(title: title, database: database)
            case .moveTopLevel,
                 .addToFolder,
                 .reorderFolderItem,
                 .removeFromFolder,
                 .deleteFolder:
                nil
            }

            let effects = try state.applyValidated(
                intent,
                createdFolderID: createdFolderID
            )
            try state.validateState()
            let pagePlan = try state.makePageRebuildPlan(
                pageCapacity: pageCapacity
            )

            try persistFolderChildren(
                state.childrenByFolderID,
                database: database
            )
            let resolvedPages = try persistPagePlan(
                pagePlan,
                database: database
            )
            for folderID in effects.folderIDsToDelete.sorted() {
                try deleteLayoutItem(itemID: folderID, database: database)
            }

            let createdTitles: [Int64: String]
            if let createdFolderID,
               let title = effects.createdFolderTitle {
                createdTitles = [createdFolderID: title]
            } else {
                createdTitles = [:]
            }
            try verifyPersistedLayout(
                state: state,
                pages: resolvedPages,
                createdFolderTitles: createdTitles,
                database: database
            )
        }
    }
}
```

The destructive order is encoded by the method: surviving folder children first, page parents second, folder deletes third, verification fourth, COMMIT last.

- [x] **Step 5: Add `/tmp` reopen proofs for commit and rollback failure**

Append these tests to `IntegrationTests.swift`:

```swift
@Test("layout COMMIT 关闭重开后仍持久化")
func layoutCommitSurvivesReopen() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("LaunchPadLayout-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("layout.sqlite").path
    var firstID: Int64 = 0
    var secondID: Int64 = 0
    do {
        let storage = try StorageManager(dbPath: path)
        let pageID = try storage.insertItem(
            TestDataFactory.makePageItem(uuid: "reopen-page", type: .page)
        )
        firstID = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "reopen-first",
            type: .app,
            ordering: 0,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.reopen.first")
        ))
        secondID = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "reopen-second",
            type: .app,
            ordering: 1,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.reopen.second")
        ))
        try storage.apply(
            .moveTopLevel(
                itemID: secondID,
                placement: .beforeItem(itemID: firstID)
            ),
            pageCapacity: 35
        )
    }
    let reopened = try StorageManager(dbPath: path)
    #expect(try reopened.persistedLayoutSnapshot().flattenedTopLevelIDs
        == [secondID, firstID])
}

@Test("真实 ROLLBACK failure 关闭连接后重开无部分事务")
func rollbackFailureInvalidatesAndReopenRestoresCommittedState() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("LaunchPadRollback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("layout.sqlite").path
    let script = SQLiteFaultScript()
    let storage = try StorageManager(
        dbPath: path,
        schemaSetup: { Schema.setupSchema(db: $0) },
        faultInjector: script.result(for:)
    )
    let pageID = try storage.insertItem(
        TestDataFactory.makePageItem(uuid: "rollback-page", type: .page)
    )
    let firstID = try storage.insertItem(TestDataFactory.makePageItem(
        uuid: "rollback-first",
        type: .app,
        ordering: 0,
        parentId: pageID,
        app: TestDataFactory.makeAppInfo(bundleId: "com.test.rollback.first")
    ))
    let secondID = try storage.insertItem(TestDataFactory.makePageItem(
        uuid: "rollback-second",
        type: .app,
        ordering: 1,
        parentId: pageID,
        app: TestDataFactory.makeAppInfo(bundleId: "com.test.rollback.second")
    ))
    let before = try storage.persistedLayoutSnapshot()
    script.failNext(.step(.updateLayoutItem), code: SQLITE_IOERR)
    script.failNext(.rollback, code: SQLITE_IOERR)

    #expect(throws: SQLiteRollbackFailure.self) {
        try storage.apply(
            .moveTopLevel(
                itemID: secondID,
                placement: .beforeItem(itemID: firstID)
            ),
            pageCapacity: 35
        )
    }
    #expect(throws: StorageError.storageUnavailable) {
        _ = try storage.fetchAllItems(parentId: nil)
    }

    let reopened = try StorageManager(dbPath: path)
    #expect(try reopened.persistedLayoutSnapshot() == before)
}
```

- [x] **Step 6: Replace old non-atomic integration expectations**

Keep `storageManager_deleteGroup_cascadeDelete` as the low-level SQLite behavior proof. Delete only the old `folderController_createFolder_itemsInFolder` and `folderController_autoDissolve` tests at `IntegrationTests.swift:258-315`; Task 14 Step 1 and Step 5 replace them with atomic round trips. Do not delete `FolderController.renameFolder` tests because Task 19 retains rename.

- [x] **Step 7: Run folder, storage and integration GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainState|IntegrationTests'
```

Expected: every `StorageManager*` suite, `LayoutDomainStateTests`, and `IntegrationTests` executes and exits 0.

- [x] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Storage/StorageManager.swift \
  Tests/LaunchPadTests/Storage/StorageManagerLayoutMutationTests.swift \
  Tests/LaunchPadTests/Integration/IntegrationTests.swift
git commit -m "feat: make folder layout mutations atomic"
```

---

### Task 15: Replace Reorder Guessing With an Immutable Main-actor Drag Session

> **Execution dependency:** Task 10 must be complete. This task also migrates every current caller of the APIs it removes, so its focused command can compile the complete package and test target before Task 18 exists.

**Files:**
- Create: `Sources/LaunchPad/Models/DragSession.swift`
- Modify: `Sources/LaunchPad/Controllers/DragController.swift:5-251`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:29,195-271,509-526,560-605`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:143-157`
- Modify: `Tests/LaunchPadTests/Controllers/DragControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Views/CollectionViewDragTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Modify: `Tests/LaunchPadTests/Models/ProtocolTests.swift:47-50`

**Interfaces:**
- Consumes: Task 3R-A's MainActor `Scheduler`/`MockScheduler`/single-work-item `DispatchQueueScheduler`, plus Task 10 `ItemPlacement`, `ItemType` and stable IDs.
- Produces: immutable `DragSession`, directional edge timer, preview-only app hover and idempotent cleanup. This task must not redefine scheduler actor or ownership contracts.
- Removes in the same commit: `currentOrder`, `pendingCrossPageMove`, `beginEditing`, `simulateReorder`, `onCreateGroup`, `handleCreateGroup(targetId:)` and the `ItemWriting` constructor dependency.
- Preserves: existing long-press idle/jiggling/dragging transitions; `handleCancel()` remains as a compatibility alias for edit-mode callers and delegates to `cancelDrag()` without writing.

- [x] **Step 1: Replace obsolete reorder tests with RED session and timer tests**

Mark all retained `DragControllerTests` and `CollectionViewDragTests` suites `@MainActor`. Use this deterministic helper instead of guessed ordering:

```swift
private func makeSession(
    itemID: Int64 = 11,
    type: ItemType = .app,
    sourceKind: DragSourceKind = .topLevel,
    parentID: Int64 = 100,
    visualIndex: Int = 3
) -> DragSession {
    DragSession(
        itemID: itemID,
        itemUUID: "00000000-0000-0000-0000-\(String(format: "%012lld", itemID))",
        itemType: type,
        sourceKind: sourceKind,
        sourceParentID: parentID,
        sourceVisualIndex: visualIndex,
        hoverDestination: nil,
        folderCreationPreviewTargetID: nil
    )
}
```

Add these exact RED tests:

```swift
@Test("更新 hover 产生新会话值，不修改原值")
func hoverUpdateKeepsOriginalSessionImmutable() {
    let scheduler = MockScheduler()
    let sut = DragController(scheduler: scheduler)
    let original = makeSession()

    sut.beginDrag(original)
    sut.updateDragHover(.item(itemID: 22, itemType: .app))

    #expect(original.hoverDestination == nil)
    #expect(sut.session?.hoverDestination == .item(itemID: 22, itemType: .app))
}

@Test("左右边缘超时分别请求上一页和下一页")
func edgeHoverUsesActualDirection() {
    let scheduler = MockScheduler()
    let sut = DragController(scheduler: scheduler)
    var directions: [DragPageDirection] = []
    sut.onPageChange = { directions.append($0) }
    sut.beginDrag(makeSession())

    sut.updateDragHover(.edge(.backward))
    scheduler.advance(by: 1.5)
    sut.updateDragHover(.edge(.forward))
    scheduler.advance(by: 1.5)

    #expect(directions == [.backward, .forward])
}

@Test("app-on-app 超时只显示预览，切换和移开会清除")
func appOnAppTimeoutOnlyShowsPreview() {
    let scheduler = MockScheduler()
    let sut = DragController(scheduler: scheduler)
    var previews: [Int64?] = []
    sut.onFolderCreationPreviewChanged = { previews.append($0) }
    sut.beginDrag(makeSession(itemID: 11, type: .app))

    sut.updateDragHover(.item(itemID: 22, itemType: .app))
    scheduler.advance(by: 0.8)
    #expect(sut.session?.folderCreationPreviewTargetID == 22)
    #expect(previews.last == 22)

    sut.updateDragHover(.item(itemID: 33, itemType: .app))
    #expect(previews.last == nil)
    scheduler.advance(by: 0.8)
    #expect(previews.last == 33)

    sut.updateDragHover(.empty)
    #expect(sut.session?.folderCreationPreviewTargetID == nil)
    #expect(previews.last == nil)
}

@Test(arguments: [ItemType.group, ItemType.page])
func nonAppTargetsNeverPreview(_ targetType: ItemType) {
    let scheduler = MockScheduler()
    let sut = DragController(scheduler: scheduler)
    var preview: Int64? = nil
    sut.onFolderCreationPreviewChanged = { preview = $0 }
    sut.beginDrag(makeSession(type: .app))

    sut.updateDragHover(.item(itemID: 22, itemType: targetType))
    scheduler.advance(by: 0.8)

    #expect(preview == nil)
    #expect(sut.session?.folderCreationPreviewTargetID == nil)
}

@Test(arguments: [true, false])
func finishAndCancelClearTimerPreviewAndSession(useFinish: Bool) {
    let scheduler = MockScheduler()
    let sut = DragController(scheduler: scheduler)
    var previews: [Int64?] = []
    sut.onFolderCreationPreviewChanged = { previews.append($0) }
    sut.beginDrag(makeSession())
    sut.updateDragHover(.item(itemID: 22, itemType: .app))
    scheduler.advance(by: 0.8)

    if useFinish { sut.finishDrag() } else { sut.cancelDrag() }
    scheduler.advance(by: 2.0)

    #expect(sut.state == .idle)
    #expect(sut.session == nil)
    #expect(previews.last == nil)
    #expect(scheduler.scheduledActions.isEmpty)
}

```

Retain explicit long-press RED cases for `< 0.5s`, `0.5s/<=10pt`, `>10pt`, release, cancel and repeated state entry. Delete every assertion about `currentOrder`, `reorderItems` and synthetic cross-page IDs. Scheduler replacement/cancel/deinit remains covered only by Task 3R-A.

- [x] **Step 2: Run the new tests and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DragControllerTests|CollectionViewDragTests'
```

Expected: compile RED for missing `DragSession`, `DragPageDirection`, `beginDrag`, `finishDrag` and `cancelDrag`.

- [x] **Step 3: Verify and consume the Task 3R-A scheduler contract**

Before adding drag session code, run the Task 3R-A scheduler ownership and actor tests. Expected: both pass. Keep `DragController` suite-level `@MainActor`, accept `Scheduler` in its initializer and schedule edge/preview actions directly. Do not edit `Scheduler`, `DispatchQueueScheduler`, `MockScheduler`, `SearchDebouncer` or their ownership tests in this task.

- [x] **Step 4: Create immutable drag model types**

```swift
import Foundation
import LaunchPadProtocols

public enum DragSourceKind: Sendable, Equatable {
    case topLevel
    case folderChild
}

public enum DragPageDirection: Sendable, Equatable {
    case forward
    case backward
}

public enum DragHoverDestination: Sendable, Equatable {
    case edge(DragPageDirection)
    case item(itemID: Int64, itemType: ItemType)
    case empty
}

public struct DragSession: Sendable, Equatable {
    public let itemID: Int64
    public let itemUUID: String
    public let itemType: ItemType
    public let sourceKind: DragSourceKind
    public let sourceParentID: Int64
    public let sourceVisualIndex: Int
    public let hoverDestination: DragHoverDestination?
    public let folderCreationPreviewTargetID: Int64?

    public init(
        itemID: Int64,
        itemUUID: String,
        itemType: ItemType,
        sourceKind: DragSourceKind,
        sourceParentID: Int64,
        sourceVisualIndex: Int,
        hoverDestination: DragHoverDestination? = nil,
        folderCreationPreviewTargetID: Int64? = nil
    ) {
        self.itemID = itemID
        self.itemUUID = itemUUID
        self.itemType = itemType
        self.sourceKind = sourceKind
        self.sourceParentID = sourceParentID
        self.sourceVisualIndex = sourceVisualIndex
        self.hoverDestination = hoverDestination
        self.folderCreationPreviewTargetID = folderCreationPreviewTargetID
    }

    public func updating(
        hoverDestination: DragHoverDestination?,
        folderCreationPreviewTargetID: Int64?
    ) -> DragSession {
        DragSession(
            itemID: itemID,
            itemUUID: itemUUID,
            itemType: itemType,
            sourceKind: sourceKind,
            sourceParentID: sourceParentID,
            sourceVisualIndex: sourceVisualIndex,
            hoverDestination: hoverDestination,
            folderCreationPreviewTargetID: folderCreationPreviewTargetID
        )
    }
}
```

- [x] **Step 5: Replace DragController persistence with the complete session state machine**

Mark `DragController` `@MainActor`, remove `@unchecked Sendable` and the old writer/order properties, then implement these exact lifecycle and hover methods:

```swift
public private(set) var session: DragSession?
public var onPageChange: ((DragPageDirection) -> Void)?
public var onFolderCreationPreviewChanged: ((Int64?) -> Void)?

public init(scheduler: Scheduler = DispatchQueueScheduler()) {
    self.scheduler = scheduler
}

public func beginDrag(_ session: DragSession) {
    cancelHoverTimer()
    clearPreview()
    state = .dragging
    self.session = session
}

public func updateDragHover(_ destination: DragHoverDestination) {
    guard state == .dragging,
          let current = session,
          current.hoverDestination != destination else { return }

    cancelHoverTimer()
    if current.folderCreationPreviewTargetID != nil {
        onFolderCreationPreviewChanged?(nil)
    }
    session = current.updating(
        hoverDestination: destination,
        folderCreationPreviewTargetID: nil
    )

    switch destination {
    case .edge(let direction):
        scheduler.schedule(after: Self.edgeHoverDuration) { [weak self] in
            guard let self,
                  self.session?.hoverDestination == .edge(direction) else {
                return
            }
            self.onPageChange?(direction)
            self.session = self.session?.updating(
                hoverDestination: nil,
                folderCreationPreviewTargetID: nil
            )
        }

    case .item(let targetID, let targetType):
        guard current.itemType == .app,
              targetType == .app,
              current.itemID != targetID else { return }
        scheduler.schedule(after: Self.iconHoverDuration) { [weak self] in
            guard let self,
                  self.session?.hoverDestination
                    == .item(itemID: targetID, itemType: .app) else { return }
            self.session = self.session?.updating(
                hoverDestination: self.session?.hoverDestination,
                folderCreationPreviewTargetID: targetID
            )
            self.onFolderCreationPreviewChanged?(targetID)
        }

    case .empty:
        break
    }
}

public func finishDrag() {
    clearPreview()
    session = nil
    resetToIdle()
}

public func cancelDrag() {
    finishDrag()
}

public func handleCancel() {
    guard state != .idle else { return }
    cancelDrag()
}

private func clearPreview() {
    if session?.folderCreationPreviewTargetID != nil {
        onFolderCreationPreviewChanged?(nil)
    }
    session = session?.updating(
        hoverDestination: session?.hoverDestination,
        folderCreationPreviewTargetID: nil
    )
}

private func resetToIdle() {
    scheduler.cancelPending()
    state = .idle
}
```

Retain `handlePressBegan`, `handleDragMoved`, `handlePressEnded`, `handleLongPress` and `handleDragStart`, but make their scheduled closures MainActor-safe and remove every reorder write. A gesture-only `.dragging` state may temporarily have `session == nil`; native pasteboard creation replaces it with a real session before any hover/drop is accepted.

- [x] **Step 6: Migrate every removed API caller in the same task**

Use `DragController()` or `DragController(scheduler:)` in `AppDelegate`, VC/window test factories and AppDelegate tests. In VC:

```swift
// Delete the old onCreateGroup binding and handleCreateGroup(targetId:).

case .ended, .cancelled, .failed:
    if dragController.state == .jiggling {
        updateJiggleState()
    } else if dragController.state == .dragging {
        dragController.finishDrag()
        loadData()
    } else {
        dragController.handlePressEnded()
    }
```

Replace VC tests that used `beginEditing` with `handleLongPress(movementDistance:)` for edit mode or `beginDrag(makeSession())` for active drag. Delete tests for `onCreateGroup/currentOrder`; Task 18 adds real drop-intent tests.

- [x] **Step 7: Run complete compile-adjacent regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DragControllerTests|CollectionViewDragTests|SearchDebounceTests|ProtocolTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests|AppDelegateTests'
```

Expected: PASS with no remaining reference to `itemWriter`, `currentOrder`, `pendingCrossPageMove`, `beginEditing`, `simulateReorder` or `onCreateGroup` in DragController callers.

- [x] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Models/DragSession.swift \
  Sources/LaunchPad/Controllers/DragController.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Tests/LaunchPadTests/Controllers/DragControllerTests.swift \
  Tests/LaunchPadTests/Views/CollectionViewDragTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift \
  Tests/LaunchPadTests/Models/ProtocolTests.swift
git commit -m "refactor: model drag state with immutable sessions"
```

---

### Task 16: Resolve Stable Grid Drop Destinations Without Optimistic Snapshots

> **Execution dependency:** Tasks 10 and 15 must be complete.

**Files:**
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift:22-28,296-420`
- Modify: `Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift`
- Modify: `Sources/LaunchPad/Views/AppIconCell.swift:12-21,31-83,190-218,274-284`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppIconCellTests.swift`

**Interfaces:**
- Consumes: Task 4's migrated suites, coordinator-owned
  `pasteboardUUIDReader`, `AppGridInteractionHosting`, Task 15 `DragSession` and
  Task 10 `ItemPlacement`.
- Produces on `AppGridInteractionCoordinator`: `GridDropDestination`,
  `topLevelPlacement(atLocalPoint:)`, `isDragEnabled`, source/extraction,
  validation/acceptance/drag-ended policy and `onDropRequested`.
- Produces on the grid host: stable empty anchors, synchronized visual-page
  state, snapshot/layout queries and preview drawing only. FolderOverlay remains
  a separate delegate owned by Task 19.
- Constraint: source/validation/acceptance never mutate a diffable snapshot; only a later COMMIT-triggered VC reload may change it.

- [x] **Step 1: Add RED tests for source identity, all destinations and immutable snapshots**

Use valid UUID strings in every accepted source fixture. Extend the Task 4
fixture without dropping its owner: it continues to return
`(host, collectionView, coordinator, dragController)`, and every coordinator
test retains all four for the whole test. This is mandatory because the
coordinator holds `host` weakly; retaining only the collection view does not
retain the fake host. Host-only empty placement/page clamp tests stay in
`AppGridCollectionViewTests`; source, extraction, destination policy,
validate/accept/ended and drop callback tests live in
`AppGridInteractionCoordinatorTests`. When extending `InteractionHost`, delete
the Task 4-only `itemsByUUID`, `snapshotMoves`, `pageItem(uuid:)` and
`moveSnapshotItem(_:before:)` members; the fake must conform to the same
complete Task 16 surface without retaining obsolete conveniences. Add these
helpers and representative tests:

```swift
private func makeApp(
    id: Int64,
    parentID: Int64 = 100,
    ordering: Int = 0
) -> PageItem {
    TestDataFactory.makePageItem(
        id: id,
        uuid: "00000000-0000-0000-0000-\(String(format: "%012lld", id))",
        type: .app,
        ordering: ordering,
        parentId: parentID,
        app: TestDataFactory.makeAppInfo(id: id, title: "A\(id)")
    )
}

@Test("pasteboard writer 使用真实稳定 source identity 建立会话")
func pasteboardWriterStartsSessionWithRealSourceIdentity() throws {
    let source = makeApp(id: 10, parentID: 77, ordering: 2)
    loadSnapshot(pages: [[source]])
    let delegate = try #require(collectionView.delegate)
    let writer = delegate.collectionView?(
        collectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    )

    #expect(writer != nil)
    let session = try #require(dragController.session)
    #expect(session.itemID == 10)
    #expect(session.sourceParentID == 77)
    #expect(session.sourceVisualIndex == 0)
}

@Test("空白落点使用当前视觉页最后一个稳定 ID")
func emptyDropUsesLastVisibleStableID() {
    let items = [makeApp(id: 10), makeApp(id: 20), makeApp(id: 30)]
    loadSnapshot(pages: [items])

    #expect(collectionView.emptyPlacement(inVisualPage: 0)
        == .afterItem(itemID: 30))
}

@Test("drop 转发稳定 anchor 且不乐观修改 snapshot")
func dropForwardsStableAnchorWithoutChangingSnapshot() throws {
    let source = makeApp(id: 1)
    let target = makeApp(id: 9, parentID: 200)
    loadSnapshot(pages: [[source], [target]])
    let before = collectionView.diffableDataSource.snapshot().itemIdentifiers
    var received: GridDropDestination?
    coordinator.onDropRequested = { _, destination in
        received = destination
        return true
    }

    let parentID = try #require(source.parentId)
    #expect(coordinator.performDrop(
        session: DragSession(
            itemID: source.id, itemUUID: source.uuid,
            itemType: source.type, sourceKind: .topLevel,
            sourceParentID: parentID, sourceVisualIndex: 0
        ),
        destination: .placement(.afterItem(itemID: target.id))
    ))

    #expect(received == .placement(.afterItem(itemID: 9)))
    #expect(collectionView.diffableDataSource.snapshot().itemIdentifiers
        == before)
}

@Test("视觉页 setter 夹紧且启用中间页双向 edge")
func visualPageSetterClampsAndEnablesBothEdgeDirections() {
    loadSnapshot(pages: [[makeApp(id: 1)], [makeApp(id: 2)], [makeApp(id: 3)]])

    collectionView.setCurrentVisualPageIndex(1)

    #expect(collectionView.currentVisualPageIndex == 1)
    #expect(coordinator.canHoverEdge(.backward))
    #expect(coordinator.canHoverEdge(.forward))
}

@Test("validate drop 在中间页按可见边缘解析双向 hover")
func validateDropUsesVisibleEdgesOnMiddlePage() throws {
    let source = makeApp(id: 1)
    loadSnapshot(pages: [[source], [makeApp(id: 2)], [makeApp(id: 3)]])
    collectionView.frame = NSRect(x: 0, y: 0, width: 2100, height: 500)
    let scrollView = NSScrollView(
        frame: NSRect(x: 0, y: 0, width: 700, height: 500)
    )
    scrollView.documentView = collectionView
    let window = attachToWindow(
        scrollView,
        origin: NSPoint(x: 120, y: 80)
    )
    _ = window
    scrollView.contentView.scroll(to: NSPoint(x: 700, y: 0))
    collectionView.setCurrentVisualPageIndex(1)

    let session = DragSession(
        itemID: source.id,
        itemUUID: source.uuid,
        itemType: source.type,
        sourceKind: .topLevel,
        sourceParentID: source.parentId!,
        sourceVisualIndex: 0
    )
    dragController.beginDrag(session)
    coordinator.pasteboardUUIDReader = { _ in session.itemUUID }

    func validate(at localPoint: NSPoint) -> NSDragOperation {
        let info = draggingInfo(
            for: session,
            at: collectionView.convert(localPoint, to: nil)
        )
        var proposed = NSIndexPath(forItem: 0, inSection: 1)
        var operation: NSCollectionView.DropOperation = .on
        return withUnsafeMutablePointer(to: &operation) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                collectionView.delegate?.collectionView?(
                    collectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                        proposedPointer
                    ),
                    dropOperation: operationPointer
                ) ?? []
            }
        }
    }

    let visible = collectionView.visibleRect
    #expect(validate(at: NSPoint(x: visible.minX + 1, y: visible.midY))
        == .generic)
    #expect(dragController.session?.hoverDestination == .edge(.backward))
    #expect(validate(at: NSPoint(x: visible.maxX - 1, y: visible.midY))
        == .generic)
    #expect(dragController.session?.hoverDestination == .edge(.forward))
}

private func attachToWindow(
    _ view: NSView,
    origin: NSPoint
) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
        styleMask: [],
        backing: .buffered,
        defer: false
    )
    let host = NSView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = host
    view.frame = NSRect(x: origin.x, y: origin.y, width: 700, height: 500)
    host.addSubview(view)
    return window
}

private func draggingInfo(
    for session: DragSession,
    at windowPoint: NSPoint
) -> MockDraggingInfo {
    let pasteboard = NSPasteboard(
        name: .init("grid-\(UUID().uuidString)")
    )
    return MockDraggingInfo(pasteboard: pasteboard, location: windowPoint)
}

@Test("validate drop 对非零 view origin 只转换一次 window point")
func validateDropConvertsWindowPointForNonZeroViewOrigin() throws {
    let source = makeApp(id: 1)
    let target = makeApp(id: 2, ordering: 1)
    loadSnapshot(pages: [[source, target]])
    let session = DragSession(
        itemID: source.id,
        itemUUID: source.uuid,
        itemType: source.type,
        sourceKind: .topLevel,
        sourceParentID: source.parentId!,
        sourceVisualIndex: 0
    )
    dragController.beginDrag(session)
    coordinator.pasteboardUUIDReader = { _ in session.itemUUID }
    let window = attachToWindow(
        collectionView,
        origin: NSPoint(x: 120, y: 80)
    )
    _ = window
    var resolvedPoint: NSPoint?
    collectionView.indexPathResolver = { point in
        resolvedPoint = point
        return nil
    }
    let localPoint = NSPoint(x: 250, y: 180)
    let info = draggingInfo(
        for: session,
        at: collectionView.convert(localPoint, to: nil)
    )
    var proposed = NSIndexPath(forItem: 1, inSection: 0)
    var operation: NSCollectionView.DropOperation = .on
    _ = withUnsafeMutablePointer(to: &operation) { operationPointer in
        withUnsafeMutablePointer(to: &proposed) { proposedPointer in
            collectionView.delegate?.collectionView?(
                collectionView,
                validateDrop: info,
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                    proposedPointer
                ),
                dropOperation: operationPointer
            )
        }
    }

    let resolved = try #require(resolvedPoint)
    #expect(abs(resolved.x - localPoint.x) <= 0.001)
    #expect(abs(resolved.y - localPoint.y) <= 0.001)
}

@Test("accept drop 对非零 view origin 只转换一次 window point")
func acceptDropConvertsWindowPointForNonZeroViewOrigin() throws {
    let source = makeApp(id: 1)
    let target = makeApp(id: 2, ordering: 1)
    loadSnapshot(pages: [[source, target]])
    let session = DragSession(
        itemID: source.id,
        itemUUID: source.uuid,
        itemType: source.type,
        sourceKind: .topLevel,
        sourceParentID: source.parentId!,
        sourceVisualIndex: 0
    )
    dragController.beginDrag(session)
    coordinator.pasteboardUUIDReader = { _ in session.itemUUID }
    let window = attachToWindow(
        collectionView,
        origin: NSPoint(x: 120, y: 80)
    )
    _ = window
    var resolvedPoint: NSPoint?
    collectionView.indexPathResolver = { point in
        resolvedPoint = point
        return nil
    }
    coordinator.onDropRequested = { _, _ in true }
    let localPoint = NSPoint(x: 250, y: 180)
    let info = draggingInfo(
        for: session,
        at: collectionView.convert(localPoint, to: nil)
    )

    #expect(collectionView.delegate?.collectionView?(
        collectionView,
        acceptDrop: info,
        indexPath: IndexPath(item: 1, section: 0),
        dropOperation: .on
    ) == true)
    let resolved = try #require(resolvedPoint)
    #expect(abs(resolved.x - localPoint.x) <= 0.001)
    #expect(abs(resolved.y - localPoint.y) <= 0.001)
}
```

Change the existing `MockDraggingInfo` declaration from `private final class`
to module-internal `final class`; Task 19 reuses it for folder coordinate tests.

The complete branch matrix uses these Swift Testing IDs (leading `test` removed and next character lowercased):

```text
pasteboardWriter_groupStartsTopLevelSession
pasteboardWriter_pageSearchMissingParentAndMalformedUUIDReturnNil
extractSession_unknownUUIDStaleSourceAndMismatchedActiveSessionReturnNil
validateDrop_leftEdgeFirstPageAndRightEdgeLastPageReject
validateDrop_leftEdgeMiddlePageArmsBackward
validateDrop_rightEdgeMiddlePageArmsForward
resolveDestination_beforeAfterAndEmptyUseStableIDs
resolveDestination_appOnAppAndAppOnGroupAreOnItem
resolveDestination_groupOnAppGroupAndSelfReject
resolveDestination_staleTargetRejects
acceptDrop_callbackFailureKeepsSnapshotUnchanged
draggingSessionEndClearsSessionTimerAndPreview
```

- [x] **Step 2: Run and confirm RED**

```bash
swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|AppIconCellTests)/'

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|AppIconCellTests'
```

Expected: the list command contains each named Task 16 ID in its owning suite;
the run is compile RED for coordinator-owned `GridDropDestination`, policy,
host page/snapshot queries and preview APIs. A zero-match filtered exit is a
gate failure.

- [x] **Step 3: Add exact destination and page synchronization APIs**

```swift
public enum GridDropDestination: Sendable, Equatable {
    case placement(ItemPlacement)
    case onItem(itemID: Int64, itemType: ItemType)
}

// AppGridInteractionCoordinator
public var isDragEnabled = true {
    didSet {
        if !isDragEnabled { dragController.cancelDrag() }
    }
}
public var onDropRequested: ((DragSession, GridDropDestination) -> Bool)?

// AppGridCollectionView host state
public private(set) var currentVisualPageIndex = 0

public func setCurrentVisualPageIndex(_ index: Int) {
    let pageCount = diffableDataSource.snapshot().sectionIdentifiers.reduce(into: 0) {
        if case .page = $1 { $0 += 1 }
    }
    currentVisualPageIndex = max(0, min(index, max(0, pageCount - 1)))
}

// AppGridInteractionCoordinator policy reads host state; it owns no snapshot.
func canHoverEdge(_ direction: DragPageDirection) -> Bool {
    guard let host else { return false }
    switch direction {
    case .backward:
        return host.currentVisualPageIndex > 0
    case .forward:
        return host.currentVisualPageIndex + 1 < host.visualPageCount
    }
}

// AppGridCollectionView stable anchor query
func emptyPlacement(inVisualPage pageIndex: Int) -> ItemPlacement? {
    let snapshot = diffableDataSource.snapshot()
    let section = Section.page(pageIndex)
    guard snapshot.sectionIdentifiers.contains(section),
          let last = snapshot.itemIdentifiers(inSection: section).last else {
        return nil
    }
    return .afterItem(itemID: last.id)
}
```

In the same source file, replace Task 4's host protocol with this complete Task
16 surface. It remains class-bound so coordinator `weak host` is legal:

```swift
@MainActor
protocol AppGridInteractionHosting: AnyObject {
    var collectionViewForDelegateInstallation: NSCollectionView { get }
    var interactionVisibleRect: NSRect { get }
    var visualPageCount: Int { get }
    var currentVisualPageIndex: Int { get }

    func section(at index: Int) -> Section?
    func pageItem(at indexPath: IndexPath) -> PageItem?
    func pageItem(id: Int64) -> PageItem?
    func visualIndex(of item: PageItem) -> Int?
    func indexPath(forItemID itemID: Int64) -> IndexPath?
    func resolvedIndexPath(at point: NSPoint) -> IndexPath?
    func layoutFrame(at indexPath: IndexPath) -> NSRect?
    func emptyPlacement(inVisualPage pageIndex: Int) -> ItemPlacement?
    func dragImage(at indexPath: IndexPath) -> NSImage?
    func setFolderCreationPreview(targetItemID: Int64?)
}
```

Implement every member from the grid's existing diffable snapshot, layout,
`visibleRect` and cell rendering primitives. Delete Task 4's obsolete
`pageItem(uuid:)` query and `moveSnapshotItem(_:before:)`; Task 16 resolves the
active source by session ID and forbids optimistic snapshot mutation. Keep
`setCurrentVisualPageIndex(_:)` as a concrete grid/VC API instead of exposing it
through the coordinator host protocol. After every grid `reload`, call
`setCurrentVisualPageIndex(currentVisualPageIndex)` so a reduced page count
clamps immediately. Task 18 synchronizes this host state with the
VC/page-scroll source of truth.

- [x] **Step 4: Build and validate a real top-level source session**

Replace the coordinator's pasteboard writer with:

```swift
public func collectionView(
    _ collectionView: NSCollectionView,
    pasteboardWriterForItemAt indexPath: IndexPath
) -> NSPasteboardWriting? {
    guard isDragEnabled,
          let host,
          case .page = host.section(at: indexPath.section),
          let item = host.pageItem(at: indexPath),
          item.type != .page,
          let parentID = item.parentId,
          UUID(uuidString: item.uuid) != nil,
          let visualIndex = host.visualIndex(of: item) else { return nil }

    dragController.beginDrag(DragSession(
        itemID: item.id,
        itemUUID: item.uuid,
        itemType: item.type,
        sourceKind: .topLevel,
        sourceParentID: parentID,
        sourceVisualIndex: visualIndex
    ))

    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(item.uuid, forType: .string)
    return pasteboardItem
}

func extractActiveSession(from draggingInfo: NSDraggingInfo) -> DragSession? {
    guard isDragEnabled,
          let value = pasteboardUUIDReader(draggingInfo.draggingPasteboard),
          UUID(uuidString: value) != nil,
          let session = dragController.session,
          session.sourceKind == .topLevel,
          session.itemUUID == value,
          let source = host?.pageItem(id: session.itemID),
          source.uuid == value else { return nil }
    return session
}
```

- [x] **Step 5: Resolve edges, on-item, before/after and empty deterministically**

Every policy and delegate method in this step is implemented on
`AppGridInteractionCoordinator`, never on the grid. Use host queries for all
snapshot, layout and visible-rect data. Use a center rectangle for `.onItem`;
outside it, compare x with the target midpoint. Expose the same placement-only
resolver for folder drag-out:

```swift
func resolveGridDestination(at location: NSPoint) -> GridDropDestination? {
    guard let host else { return nil }
    guard let indexPath = host.resolvedIndexPath(at: location) else {
        return host.emptyPlacement(
            inVisualPage: host.currentVisualPageIndex
        ).map {
            .placement($0)
        }
    }
    guard let item = host.pageItem(at: indexPath),
          let frame = host.layoutFrame(at: indexPath) else { return nil }

    let onFrame = frame.insetBy(
        dx: frame.width * 0.25,
        dy: frame.height * 0.20
    )
    if onFrame.contains(location) {
        return .onItem(itemID: item.id, itemType: item.type)
    }
    return .placement(
        location.x < frame.midX
            ? .beforeItem(itemID: item.id)
            : .afterItem(itemID: item.id)
    )
}

public func topLevelPlacement(atLocalPoint location: NSPoint) -> ItemPlacement? {
    switch resolveGridDestination(at: location) {
    case .placement(let placement):
        return placement
    case .onItem(let itemID, _):
        guard let indexPath = host?.indexPath(forItemID: itemID),
              let frame = host?.layoutFrame(at: indexPath) else {
            return nil
        }
        return location.x < frame.midX
            ? .beforeItem(itemID: itemID)
            : .afterItem(itemID: itemID)
    case nil:
        return nil
    }
}
```

Both AppKit entry points receive `draggingLocation` in window coordinates. Each
entry converts it exactly once with
`collectionView.convert(draggingInfo.draggingLocation, from: nil)` before edge,
item or empty resolution. Use these complete implementations:

```swift
public func collectionView(
    _ collectionView: NSCollectionView,
    validateDrop draggingInfo: NSDraggingInfo,
    proposedIndexPath proposedDropIndexPath:
        AutoreleasingUnsafeMutablePointer<NSIndexPath>,
    dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
) -> NSDragOperation {
    let localPoint = collectionView.convert(
        draggingInfo.draggingLocation,
        from: nil
    )
    guard let session = extractActiveSession(from: draggingInfo) else {
        dragController.updateDragHover(.empty)
        return []
    }

    let edgeWidth: CGFloat = 40
    let visibleBounds = host?.interactionVisibleRect ?? .zero
    if localPoint.x < visibleBounds.minX + edgeWidth {
        guard canHoverEdge(.backward) else {
            dragController.updateDragHover(.empty)
            return []
        }
        dragController.updateDragHover(.edge(.backward))
        return .generic
    }
    if localPoint.x > visibleBounds.maxX - edgeWidth {
        guard canHoverEdge(.forward) else {
            dragController.updateDragHover(.empty)
            return []
        }
        dragController.updateDragHover(.edge(.forward))
        return .generic
    }

    guard let destination = resolveGridDestination(at: localPoint),
          allows(session: session, destination: destination) else {
        dragController.updateDragHover(.empty)
        return []
    }
    switch destination {
    case .placement:
        dragController.updateDragHover(.empty)
    case .onItem(let itemID, let itemType):
        dragController.updateDragHover(
            .item(itemID: itemID, itemType: itemType)
        )
    }
    dropOperation.pointee = .on
    return .move
}

public func collectionView(
    _ collectionView: NSCollectionView,
    acceptDrop draggingInfo: NSDraggingInfo,
    indexPath: IndexPath,
    dropOperation: NSCollectionView.DropOperation
) -> Bool {
    let localPoint = collectionView.convert(
        draggingInfo.draggingLocation,
        from: nil
    )
    guard let session = extractActiveSession(from: draggingInfo),
          let destination = resolveGridDestination(at: localPoint),
          allows(session: session, destination: destination) else {
        dragController.cancelDrag()
        return false
    }
    return performDrop(session: session, destination: destination)
}
```

The allowed-destination helper remains exhaustive:

```swift
private func allows(
    session: DragSession,
    destination: GridDropDestination
) -> Bool {
    switch destination {
    case .placement(let placement):
        return placement.anchorItemID != session.itemID
    case .onItem(let targetID, .app), .onItem(let targetID, .group):
        return session.itemType == .app && targetID != session.itemID
    case .onItem:
        return false
    }
}
```

Arm hover `.item` only for accepted `.onItem`; use `.empty` for placement. In `acceptDrop`, resolve the same active session/destination and call:

```swift
func performDrop(
    session: DragSession,
    destination: GridDropDestination
) -> Bool {
    guard isDragEnabled else {
        dragController.cancelDrag()
        return false
    }
    return onDropRequested?(session, destination) ?? false
}

public func collectionView(
    _ collectionView: NSCollectionView,
    draggingSession session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    dragOperation operation: NSDragOperation
) {
    dragController.finishDrag()
}
```

Delete the old `snapshot.deleteItems/insertItems/apply` block completely.

- [x] **Step 6: Add a visible, reusable folder-creation preview**

In `AppIconCell.loadView`, set `containerView.wantsLayer = true` before configuring its layer. Add:

```swift
public private(set) var isFolderCreationPreviewVisible = false

public func setFolderCreationPreviewVisible(_ visible: Bool) {
    isFolderCreationPreviewVisible = visible
    containerView.layer?.borderWidth = visible ? 2 : 0
    containerView.layer?.borderColor = visible
        ? NSColor.controlAccentColor.cgColor
        : nil
    containerView.layer?.cornerRadius = 8
}
```

Call `setFolderCreationPreviewVisible(false)` from `prepareForReuse`. In AppGrid add:

```swift
private var previewedFolderTargetID: Int64?

func setFolderCreationPreview(targetItemID: Int64?) {
    if let oldID = previewedFolderTargetID,
       let oldItem = diffableDataSource.snapshot().itemIdentifiers.first(where: {
           $0.id == oldID
       }),
       let oldPath = diffableDataSource.indexPath(for: oldItem),
       let oldCell = (visibleCellProvider?(oldPath) ?? item(at: oldPath))
        as? AppIconCell {
        oldCell.setFolderCreationPreviewVisible(false)
    }

    previewedFolderTargetID = targetItemID
    guard let targetItemID,
          let item = diffableDataSource.snapshot().itemIdentifiers.first(where: {
              $0.id == targetItemID && $0.type == .app
          }),
          let path = diffableDataSource.indexPath(for: item),
          let cell = (visibleCellProvider?(path) ?? item(at: path))
            as? AppIconCell else {
        return
    }
    cell.setFolderCreationPreviewVisible(true)
}
```

The grid only draws through this host method. Bind and clear the preview from
coordinator lifecycle, because the coordinator owns the `DragController`:

```swift
// At the end of coordinator.attach(to:)
dragController.onFolderCreationPreviewChanged = { [weak self] targetID in
    self?.host?.setFolderCreationPreview(targetItemID: targetID)
}

// At the start of coordinator.detach(), before clearing host
host?.setFolderCreationPreview(targetItemID: nil)
dragController.onFolderCreationPreviewChanged = nil
```

Grid `reload` also calls `setFolderCreationPreview(targetItemID: nil)` before
applying its new snapshot. Tests cover valid app, stale/missing target, non-app
target, old-target clearing, reload, detach and A-to-B reattach.

- [x] **Step 7: Run grid, icon and drag suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|AppIconCellTests|DragControllerTests|CollectionViewDragTests'
```

Expected: PASS; accepted/rejected drops leave the pre-COMMIT snapshot unchanged, edge direction respects the synchronized page, and preview border visibly toggles.

Before committing, enforce the complete host contraction and real delegate
wiring across production and tests:

```bash
! rg -n 'interactionBounds|pageItem\(uuid:|moveSnapshotItem\(|itemsByUUID|snapshotMoves' \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift
! rg -n 'setCurrentVisualPageIndex' \
  Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift
! rg -n -U --pcre2 \
  '\b([A-Za-z_][A-Za-z0-9_]*)\.collectionView\(\s*\1\s*,' \
  Tests --glob '*.swift'
```

Expected: all three scans print nothing. The concrete grid still exposes
`setCurrentVisualPageIndex(_:)` to the VC, but the host protocol/coordinator
cannot mutate page state and no test can retain Task 4 lookup/move shortcuts.

- [x] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
  Sources/LaunchPad/Views/AppIconCell.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift
git commit -m "feat: resolve stable grid drop destinations"
```

---

### Task 17: Add a Deterministic Accessible Error Message View

**Files:**
- Create: `Sources/LaunchPad/Views/TransientMessageView.swift`
- Create: `Tests/LaunchPadTests/Views/TransientMessageViewTests.swift`

**Interfaces:**
- Produces: `show(message:duration:)`, `hide()`, exact failure text, cancellable auto-hide and injectable accessibility announcement with required priority.

- [x] **Step 1: Write deterministic RED tests without a window or sleep**

```swift
import AppKit
import Testing
@testable import LaunchPad

@MainActor
@Suite("TransientMessageView")
struct TransientMessageViewTests {
    @Test("show 设置文本、显示视图并发布 high priority announcement")
    func showDisplaysExactTextAndPostsAnnouncement() {
        let sut = TransientMessageView(frame: .zero)
        var announcement: (String, Int)?
        var delay: TimeInterval?
        sut.postAnnouncement = {
            announcement = ($0, $1.rawValue)
        }
        sut.scheduleHide = { value, _ in delay = value }

        sut.show(message: "无法更新布局，请重试")

        #expect(sut.message == "无法更新布局，请重试")
        #expect(!sut.isHidden)
        #expect(sut.accessibilityLabel() == "无法更新布局，请重试")
        #expect(announcement?.0 == "无法更新布局，请重试")
        #expect(announcement?.1 == NSAccessibilityPriorityLevel.high.rawValue)
        #expect(delay == 2.5)
    }

    @Test("重复 show 取消旧任务并替换文本")
    func repeatedShowCancelsOldWorkAndReplacesText() throws {
        let sut = TransientMessageView(frame: .zero)
        var workItems: [DispatchWorkItem] = []
        sut.postAnnouncement = { _, _ in }
        sut.scheduleHide = { _, item in workItems.append(item) }

        sut.show(message: "first")
        sut.show(message: "second")

        #expect(try #require(workItems.first).isCancelled)
        #expect(!(try #require(workItems.last)).isCancelled)
        #expect(sut.message == "second")
    }

    @Test("调度任务执行后确定性隐藏")
    func scheduledWorkHidesDeterministically() throws {
        let sut = TransientMessageView(frame: .zero)
        var scheduled: DispatchWorkItem?
        sut.postAnnouncement = { _, _ in }
        sut.scheduleHide = { _, item in scheduled = item }
        sut.show(message: "error")

        try #require(scheduled).perform()

        #expect(sut.message == nil)
        #expect(sut.isHidden)
        #expect(sut.accessibilityLabel() == "")
    }
}
```

- [x] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter TransientMessageViewTests
```

Expected: compile RED because `TransientMessageView` does not exist.

- [x] **Step 3: Add the complete NSView initializer, hierarchy and scheduling implementation**

```swift
import AppKit

@MainActor
public final class TransientMessageView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var pendingHide: DispatchWorkItem?

    var scheduleHide: (TimeInterval, DispatchWorkItem) -> Void = { delay, item in
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }
    var postAnnouncement:
        (String, NSAccessibilityPriorityLevel) -> Void = { message, priority in
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue,
            ]
        )
    }

    public private(set) var message: String?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.92).cgColor
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("")
        isHidden = true
    }

    public func show(message: String, duration: TimeInterval = 2.5) {
        pendingHide?.cancel()
        self.message = message
        label.stringValue = message
        setAccessibilityLabel(message)
        isHidden = false
        postAnnouncement(message, .high)

        let item = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        pendingHide = item
        scheduleHide(duration, item)
    }

    public func hide() {
        pendingHide?.cancel()
        pendingHide = nil
        message = nil
        label.stringValue = ""
        setAccessibilityLabel("")
        isHidden = true
    }
}
```

- [x] **Step 4: Run GREEN and commit**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter TransientMessageViewTests
```

Expected: PASS with no real window, delay or system accessibility mutation.

```bash
git add Sources/LaunchPad/Views/TransientMessageView.swift \
  Tests/LaunchPadTests/Views/TransientMessageViewTests.swift
git commit -m "feat: add deterministic layout error feedback"
```

---

### Task 18: Make the View Controller the Only Top-level Drop Writer

> **Execution dependency:** Tasks 5-7, 10, and 16-17 must be complete. Task 5 supplies `gridMetrics` and visual-page callbacks; Task 6 supplies truthful synchronous keyboard search mode.

**Files:**
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:13-89,98-241,285-382,509-605`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift`
- Modify: `Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift`
- Modify: `Sources/LaunchPad/Views/FolderOverlayView.swift:11-35`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:12-18,111-160`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift`

**Interfaces:**
- Consumes: Task 10 `LayoutMutating`, Task 16 `GridDropDestination`, Task 17 `TransientMessageView`, Task 5 `GridMetrics`/visual paging.
- Produces: one mutation attempt, COMMIT-then-reload, synchronous search triple guard, sanitized structured log and current-page synchronization.
- Constraint: `DataStoring` remains independent from `LayoutMutating`; AppDelegate retains two separately typed references to the same production `StorageManager`.

- [x] **Step 1: Extend the mutator test double with attempt accounting**

Task 10's `appliedIntents` records only successful calls. Add independent attempt state and increment it before throwing:

```swift
final class MockLayoutMutator: LayoutMutating, @unchecked Sendable {
    private(set) var applyAttemptCount = 0
    private(set) var attemptedIntents: [LayoutDropIntent] = []
    private(set) var appliedIntents: [LayoutDropIntent] = []
    private(set) var appliedPageCapacities: [Int] = []
    var applyError: Error?

    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws {
        applyAttemptCount += 1
        attemptedIntents.append(intent)
        if let applyError { throw applyError }
        appliedIntents.append(intent)
        appliedPageCapacities.append(pageCapacity)
    }
}
```

- [x] **Step 2: Add RED mapping, failure, search and page synchronization tests**

```swift
@Test("事务失败只有一次尝试并显示固定提示")
func dropFailureDoesNotRetry() {
    let mutator = MockLayoutMutator()
    mutator.applyError = TestError.generic
    let (sut, _, storage) = makeSUT(layoutMutator: mutator)
    loadViewWithData(sut, storage: storage)
    sut.viewDidLayout()
    let readsBefore = storage.fetchAllItemsCallCount

    #expect(!sut.applyDropIntent(
        .moveTopLevel(itemID: 2, placement: .beforeItem(itemID: 1))
    ))
    #expect(mutator.applyAttemptCount == 1)
    #expect(mutator.appliedIntents.isEmpty)
    #expect(storage.fetchAllItemsCallCount > readsBefore)
    #expect(sut.transientMessageView.message == "无法更新布局，请重试")
    #expect(sut.dragController.session == nil)
}

@Test("同步搜索模式拒绝已在途 drop 并清理会话")
func searchModeRejectsInFlightDropAtControllerBoundary() {
    let mutator = MockLayoutMutator()
    let (sut, _, storage) = makeSUT(layoutMutator: mutator)
    loadViewWithData(sut, storage: storage)
    sut.viewDidLayout()
    sut.dragController.beginDrag(makeSession())
    sut.keyboardNavigator.mode = .search(query: "s")

    #expect(!sut.applyDropIntent(
        .moveTopLevel(itemID: 2, placement: .beforeItem(itemID: 1))
    ))
    #expect(mutator.applyAttemptCount == 0)
    #expect(sut.dragController.session == nil)
}

@Test("页码点击、滚动和边缘翻页同步 collection 当前视觉页")
func everyPageEntrySynchronizesCollectionView() {
    let (sut, _, storage) = makeSUT(layoutMutator: MockLayoutMutator())
    sut.viewportSizeProvider = { CGSize(width: 1440, height: 620) }
    loadViewWithData(
        sut,
        storage: storage,
        apps: TestDataFactory.makeAppItems(count: 80)
    )
    sut.viewDidLayout()
    sut.pageControl.onDotSelected?(1)
    #expect(sut.currentGridVisualPage == 1)
    sut.handleVisiblePageChanged(2)
    #expect(sut.currentGridVisualPage == 2)
    sut.dragController.onPageChange?(.backward)
    #expect(sut.currentGridVisualPage == 1)
}

private func firstGrid(in root: NSView) -> AppGridCollectionView? {
    if let grid = root as? AppGridCollectionView { return grid }
    for child in root.subviews {
        if let grid = firstGrid(in: child) { return grid }
    }
    return nil
}

@Test("0.8 秒 hover 只显示预览，松手只提交一次 createFolder")
func folderHoverPreviewsWithoutWriteAndDropCommitsExactlyOnce() throws {
    let scheduler = MockScheduler()
    let mutator = MockLayoutMutator()
    let (sut, _, storage) = makeSUT(
        layoutMutator: mutator,
        dragScheduler: scheduler
    )
    let apps = (1...2).map { id in
        TestDataFactory.makePageItem(
            id: Int64(id),
            uuid: "00000000-0000-0000-0000-\(String(
                format: "%012lld", Int64(id)
            ))",
            type: .app,
            ordering: id - 1,
            parentId: 1,
            app: TestDataFactory.makeAppInfo(
                id: Int64(id),
                title: "A\(id)"
            )
        )
    }
    loadViewWithData(sut, storage: storage, apps: apps)
    sut.viewportSizeProvider = { CGSize(width: 1440, height: 620) }
    sut.viewDidLayout()
    let grid = try #require(firstGrid(in: sut.view))
    let previewCell = AppIconCell()
    _ = previewCell.view
    grid.visibleCellProvider = { indexPath in
        indexPath == IndexPath(item: 1, section: 0) ? previewCell : nil
    }
    let session = DragSession(
        itemID: apps[0].id,
        itemUUID: apps[0].uuid,
        itemType: .app,
        sourceKind: .topLevel,
        sourceParentID: 1,
        sourceVisualIndex: 0
    )
    sut.dragController.beginDrag(session)

    sut.dragController.updateDragHover(
        .item(itemID: apps[1].id, itemType: .app)
    )
    scheduler.advance(by: 0.8)

    #expect(previewCell.isFolderCreationPreviewVisible)
    #expect(mutator.applyAttemptCount == 0)
    let coordinator = try #require(sut.gridInteractionCoordinator)
    coordinator.pasteboardUUIDReader = { _ in session.itemUUID }
    let delegate = try #require(grid.delegate)
    #expect(delegate === coordinator)
    let targetPath = try #require(
        grid.diffableDataSource.indexPath(for: apps[1])
    )
    grid.layoutSubtreeIfNeeded()
    let targetFrame = try #require(
        grid.collectionViewLayout?
            .layoutAttributesForItem(at: targetPath)?.frame
    )
    grid.indexPathResolver = { _ in targetPath }
    let info = MockDraggingInfo(
        pasteboard: NSPasteboard(
            name: .init("vc-drop-\(UUID().uuidString)")
        ),
        location: grid.convert(
            NSPoint(x: targetFrame.midX, y: targetFrame.midY),
            to: nil
        )
    )

    #expect(delegate.collectionView?(
        grid,
        acceptDrop: info,
        indexPath: targetPath,
        dropOperation: .on
    ) == true)
    #expect(mutator.applyAttemptCount == 1)
    #expect(mutator.attemptedIntents == [
        .createFolder(
            itemID: apps[0].id,
            targetItemID: apps[1].id,
            title: "New Folder"
        ),
    ])
    delegate.collectionView?(
        grid,
        draggingSession: NSDraggingSession(),
        endedAt: .zero,
        dragOperation: .move
    )
    #expect(mutator.applyAttemptCount == 1)
    #expect(sut.dragController.session == nil)
    #expect(scheduler.scheduledActions.isEmpty)
    #expect(!previewCell.isFolderCreationPreviewVisible)
}
```

This test must keep the retained real delegate for both native calls. It proves
the `acceptDrop -> draggingSession ended` sequence cannot introduce a second
writer: mutation attempts remain exactly one after the sixth delegate entry.

Add the mapping matrix as one exhaustive pure-controller test; same-page,
cross-page and empty destinations are all stable placements and therefore must
map identically without page numbers:

```swift
@Test("全部 grid source 与 destination 映射稳定 intent 或明确拒绝")
func gridSourceAndDestinationMappingIsExhaustive() {
    let (sut, _, _) = makeSUT(layoutMutator: MockLayoutMutator())
    let app = makeSession(itemID: 2, type: .app)
    let group = makeSession(itemID: 7, type: .group)
    let folderChild = DragSession(
        itemID: 2,
        itemUUID: "00000000-0000-0000-0000-000000000002",
        itemType: .app,
        sourceKind: .folderChild,
        sourceParentID: 50,
        sourceVisualIndex: 0
    )

    #expect(sut.makeGridIntent(
        session: app,
        destination: .placement(.beforeItem(itemID: 1))
    ) == .moveTopLevel(
        itemID: 2,
        placement: .beforeItem(itemID: 1)
    ))
    #expect(sut.makeGridIntent(
        session: app,
        destination: .placement(.afterItem(itemID: 40))
    ) == .moveTopLevel(
        itemID: 2,
        placement: .afterItem(itemID: 40)
    ))
    #expect(sut.makeGridIntent(
        session: app,
        destination: .onItem(itemID: 3, itemType: .app)
    ) == .createFolder(itemID: 2, targetItemID: 3, title: "New Folder"))
    #expect(sut.makeGridIntent(
        session: app,
        destination: .onItem(itemID: 8, itemType: .group)
    ) == .addToFolder(itemID: 2, folderID: 8))
    #expect(sut.makeGridIntent(
        session: group,
        destination: .placement(.afterItem(itemID: 9))
    ) == .moveTopLevel(
        itemID: 7,
        placement: .afterItem(itemID: 9)
    ))
    #expect(sut.makeGridIntent(
        session: group,
        destination: .onItem(itemID: 3, itemType: .app)
    ) == nil)
    #expect(sut.makeGridIntent(
        session: group,
        destination: .onItem(itemID: 8, itemType: .group)
    ) == nil)
    #expect(sut.makeGridIntent(
        session: app,
        destination: .placement(.beforeItem(itemID: 2))
    ) == nil)
    #expect(sut.makeGridIntent(
        session: app,
        destination: .onItem(itemID: 2, itemType: .app)
    ) == nil)
    #expect(sut.makeGridIntent(
        session: folderChild,
        destination: .placement(.beforeItem(itemID: 1))
    ) == nil)
}

@Test("当前动态容量原样传给 writer；stale anchor 失败不重试")
func dropForwardsCapacityAndStaleAnchorFailsOnce() {
    let mutator = MockLayoutMutator()
    let (sut, _, storage) = makeSUT(layoutMutator: mutator)
    sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
    loadViewWithData(sut, storage: storage)
    sut.viewDidLayout()
    let intent = LayoutDropIntent.moveTopLevel(
        itemID: 2,
        placement: .beforeItem(itemID: 1)
    )
    #expect(sut.applyDropIntent(intent))
    #expect(mutator.appliedPageCapacities == [28])

    mutator.applyError = LayoutDomainError.missingAnchor(999)
    #expect(!sut.applyDropIntent(.moveTopLevel(
        itemID: 2,
        placement: .beforeItem(itemID: 999)
    )))
    #expect(mutator.applyAttemptCount == 2)
    #expect(sut.transientMessageView.message == "无法更新布局，请重试")
}
```

In `AppGridInteractionCoordinatorTests`, set `coordinator.isDragEnabled = false`, assert the
pasteboard writer returns nil, then feed a valid active session to both native
validate/accept entries and assert `[]`/`false`, zero callback invocations and
an unchanged snapshot. Re-enable drag and assert the same source is accepted;
this proves search toggles all three boundaries rather than only the writer.

- [x] **Step 3: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'LaunchPadViewControllerTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|AppDelegateTests|LaunchPadWindowControllerTests'
```

Expected: compile RED for the new VC initializer, message/log members, AppDelegate mutator property and page synchronization.

- [x] **Step 4: Retain separate storage and mutator references in AppDelegate**

Add:

```swift
var storage: (any DataStoring)!
var layoutMutator: (any LayoutMutating)!
```

Use one assignment helper in both first-open and corruption-recovery paths:

```swift
private func installStorage(_ manager: StorageManager) {
    storage = manager
    layoutMutator = manager
}
```

In `setupServices()`, replace each direct assignment with:

```swift
do {
    installStorage(try storageFactory(dbPath))
} catch {
    let strategy = corruptionHandler(dbPath)
    if case .deleteAndRescan = strategy {
        try? FileManager.default.removeItem(atPath: dbPath)
        if let recovered = try? storageFactory(dbPath) {
            installStorage(recovered)
        } else {
            storage = nil
            layoutMutator = nil
        }
    } else {
        storage = nil
        layoutMutator = nil
    }
}
```

`setupControllers()` must guard both references and pass `layoutMutator` separately. AppDelegate tests assert first success, recovered success and both failure paths keep `storage/layoutMutator` synchronized.

- [x] **Step 5: Add the VC dependency, transient view and sanitized log event**

Add production types and properties:

```swift
struct LayoutDropFailureEvent: Sendable, Equatable {
    let kind: String
    let sourceID: Int64
    let relatedIDs: [Int64]
    let category: String

    init(intent: LayoutDropIntent) {
        category = "mutation_failed"
        switch intent {
        case .moveTopLevel(let itemID, let placement):
            kind = "move_top_level"
            sourceID = itemID
            relatedIDs = [placement.anchorItemID]
        case .addToFolder(let itemID, let folderID):
            kind = "add_to_folder"
            sourceID = itemID
            relatedIDs = [folderID]
        case .createFolder(let itemID, let targetItemID, _):
            kind = "create_folder"
            sourceID = itemID
            relatedIDs = [targetItemID]
        case .reorderFolderItem(let itemID, let folderID, let placement):
            kind = "reorder_folder_item"
            sourceID = itemID
            relatedIDs = [folderID, placement.anchorItemID]
        case .removeFromFolder(let itemID, let folderID, let placement):
            kind = "remove_from_folder"
            sourceID = itemID
            relatedIDs = [folderID, placement.anchorItemID]
        case .deleteFolder(let folderID):
            kind = "delete_folder"
            sourceID = folderID
            relatedIDs = []
        }
    }
}

private let layoutMutator: LayoutMutating
private(set) var transientMessageView: TransientMessageView!
/// 当前网格视觉页；测试通过该只读投影验证导航同步，collectionView 保持 private。
var currentGridVisualPage: Int {
    collectionView.currentVisualPageIndex
}
var layoutDropFailureLogger: (LayoutDropFailureEvent) -> Void = { event in
    NSLog(
        "[LaunchPadViewController] layout_drop_failed kind=%@ source=%lld related=%@ category=%@",
        event.kind,
        event.sourceID,
        event.relatedIDs.map(String.init).joined(separator: ","),
        event.category
    )
}
```

Add `layoutMutator: LayoutMutating` to the designated initializer and assign it. In `loadView`, instantiate and constrain the message above the page control:

```swift
transientMessageView = TransientMessageView(frame: .zero)
transientMessageView.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(transientMessageView)
NSLayoutConstraint.activate([
    transientMessageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    transientMessageView.bottomAnchor.constraint(
        equalTo: pageControl.topAnchor,
        constant: -12
    ),
    transientMessageView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
])
```

- [x] **Step 6: Map grid destinations and bind the only writer**

```swift
func makeGridIntent(
    session: DragSession,
    destination: GridDropDestination
) -> LayoutDropIntent? {
    guard session.sourceKind == .topLevel else { return nil }
    switch destination {
    case .placement(let placement):
        guard placement.anchorItemID != session.itemID else { return nil }
        return .moveTopLevel(itemID: session.itemID, placement: placement)
    case .onItem(let targetID, .app):
        guard session.itemType == .app, targetID != session.itemID else {
            return nil
        }
        return .createFolder(
            itemID: session.itemID,
            targetItemID: targetID,
            title: "New Folder"
        )
    case .onItem(let targetID, .group):
        guard session.itemType == .app, targetID != session.itemID else {
            return nil
        }
        return .addToFolder(itemID: session.itemID, folderID: targetID)
    case .onItem:
        return nil
    }
}

private var isSearchActive: Bool {
    if case .search = keyboardNavigator.mode { return true }
    return !currentSearchQuery.isEmpty
}

@discardableResult
func applyDropIntent(_ intent: LayoutDropIntent) -> Bool {
    defer { dragController.finishDrag() }
    guard !isSearchActive,
          let capacity = gridMetrics?.itemsPerPage else { return false }

    do {
        try layoutMutator.apply(intent, pageCapacity: capacity)
        loadData()
        return true
    } catch {
        loadData()
        transientMessageView.show(message: "无法更新布局，请重试")
        layoutDropFailureLogger(LayoutDropFailureEvent(intent: intent))
        return false
    }
}
```

Bind without a second writer or guessed source:

```swift
gridInteractionCoordinator?.onDropRequested = { [weak self] session, destination in
    guard let self,
          let intent = self.makeGridIntent(
              session: session,
              destination: destination
          ) else {
        self?.dragController.cancelDrag()
        return false
    }
    return self.applyDropIntent(intent)
}
```

The logger receives only `LayoutDropFailureEvent`; never pass or interpolate the caught `error`. Tests inject the logger and assert event fields exactly.

- [x] **Step 7: Disable drag synchronously at source, validation and writer boundaries**

Task 19 adds folder delegates, but add `public var isDragEnabled = true` to `FolderOverlayView` now so search code compiles independently. Add:

```swift
private func setDragEnabled(_ enabled: Bool) {
    gridInteractionCoordinator?.isDragEnabled = enabled
    folderOverlay.isDragEnabled = enabled
    if !enabled { dragController.cancelDrag() }
}
```

Call `setDragEnabled(false)` in `.enterSearchMode` and `.appendToQuery` before scheduling search. Call `setDragEnabled(true)` in `.clearSearch` after `keyboardNavigator.mode` returns idle and in `handleSearch(query: "")`. Keep Task 16 pasteboard/validate guards and `applyDropIntent`'s synchronous `keyboardNavigator.mode` guard.

- [x] **Step 8: Synchronize currentVisualPageIndex at every navigation entry**

```swift
private func synchronizeCurrentVisualPage() {
    collectionView.setCurrentVisualPageIndex(
        pageControlViewModel.currentPage
    )
}

func handleVisiblePageChanged(_ page: Int) {
    pageControlViewModel.currentPage = page
    synchronizeCurrentVisualPage()
}
```

Call this method:

1. after `reloadProjectedLayout` clamps `pageControlViewModel.currentPage`;
2. after `navigateToPage` updates the page model;
3. inside Task 5's `scrollView.onPageChanged` callback by calling
   `handleVisiblePageChanged(_:)` before `pageControl.update()`;
4. after edge `handlePageChange` delegates to `navigateToPage`;
5. after clearing search restores projected pages.

The dot callback already calls `navigateToPage`; do not add a second path.

- [x] **Step 9: Update every VC constructor and run regression GREEN**

Pass `MockLayoutMutator` from VC/window test factories and real `layoutMutator` from AppDelegate. Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'LaunchPadViewControllerTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|AppDelegateTests|LaunchPadWindowControllerTests|TransientMessageViewTests'
```

Expected: PASS; failure has one attempt and zero successful apply, search races make zero attempts, all page paths synchronize, and logs contain no underlying error text.

- [x] **Step 10: Commit**

```bash
git add Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
  Sources/LaunchPad/Views/FolderOverlayView.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift
git commit -m "feat: commit top-level drops through one domain writer"
```

---

### Task 19: Add Folder Reorder, Drag-out and Safe Delete UI

> **Execution dependency:** Tasks 10, 14-18 must be complete.

**Files:**
- Modify: `Sources/LaunchPad/Views/FolderOverlayView.swift:11-315`
- Modify: `Sources/LaunchPad/Views/FolderCell.swift:8-183`
- Modify: `Sources/LaunchPad/Views/AppIconCell.swift`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift`
- Modify: `Sources/LaunchPad/Controllers/FolderController.swift:6-102`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`
- Modify: `Sources/LaunchPad/App/LaunchPadWindowController.swift:95-114`
- Modify: `Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/FolderOverlayViewPagingTests.swift`
- Modify: `Tests/LaunchPadTests/Views/FolderCellTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/FolderControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift`

**Interfaces:**
- Consumes: Task 16 coordinator
  `topLevelPlacement(atLocalPoint:)`, Task 18's only writer/error path and Task
  14's atomic folder intents. `FolderOverlayView` deliberately keeps its own
  delegate, `DragController`, pasteboard reader and `onDropRequested`; this Task
  does not route overlay-local AppKit callbacks through the main-grid
  coordinator.
- Consumes: the actual folder clip viewport; both axes use the existing 72x80 item geometry and capacity never exceeds the existing maximum of 35.
- Produces: width/height-derived folder rows, columns and capped capacity, one shared open/reload/resize reprojection path, inner and overlay-exterior drop destinations, stable child placement, drag-out, deterministic folder reload, real edit-mode delete control, confirmed safe delete and all lifecycle cleanup.

- [x] **Step 1: Repair the existing external-click animation fixture as an isolated test commit**

Keep the file in its current framework for this one fixture-only commit. Require the optional `NSEvent`, call `layoutSubtreeIfNeeded()`, recursively locate the panel `NSVisualEffectView`, choose `NSPoint(x: panel.frame.minX - 1, y: panel.frame.midY)` and prove the point is outside the panel. Inject `closeFolderCompletionRunner = { $0() }`; assert synchronously that `isHidden` is true and `onClosed` ran exactly once. Delete the 0.3-second dispatch, expectation and wait.

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter FolderOverlayViewTests/testMouseDown_outsidePanel_closesFolder
git add Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift
git commit -m "test: make folder close completion deterministic"
```

- [x] **Step 2: Migrate FolderOverlayViewTests 39/39 in a production-empty commit**

Use `@MainActor @Suite("FolderOverlayView") struct FolderOverlayViewTests`. Do not migrate `setUp`/`tearDown` or IUO state; each test calls:

```swift
private func makeOverlay() -> FolderOverlayView {
    let overlay = FolderOverlayView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 700)
    )
    overlay.folderViewportSizeProvider = {
        CGSize(width: 800, height: 624)
    }
    overlay.closeFolderCompletionRunner = { $0() }
    return overlay
}
```

Convert all 39 methods one-to-one, preserve every assertion and replace optional event/object unwraps with `try #require`. Remove fixed waits and RunLoop polling; locally injected completion runners are synchronous. Add 39 explicit rows to `docs/superpowers/reports/2026-07-21-task-19-folder-overlay-migration.md`.

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(FolderOverlayViewTests|FolderOverlayViewPagingTests)/' | \
  LC_ALL=C sort > /tmp/task-19-folder-actual-before.txt
test "$(wc -l < /tmp/task-19-folder-actual-before.txt | tr -d ' ')" -eq 47
test "$(LC_ALL=C sort -u /tmp/task-19-folder-actual-before.txt | wc -l | tr -d ' ')" -eq 47
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter FolderOverlayViewTests
! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:|RunLoop\.main\.run' \
  Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift
git diff --exit-code HEAD -- Sources
git add Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift \
  docs/superpowers/reports/2026-07-21-task-19-folder-overlay-migration.md
git commit -m "test: migrate folder overlay tests to Swift Testing"
```

- [x] **Step 3: Migrate FolderOverlayViewPagingTests 8/8 and audit all 47 mappings**

Use `@MainActor @Suite("FolderOverlayView paging")` with a fresh overlay per test. Notification-driven paging posts to a local `NotificationCenter`; because the `.main` observer is synchronous on MainActor, assert immediately without RunLoop polling. Append all 8 mappings to the report. The complete old-name mapping is removal of `test` and lowercasing the next character, but the report must expand all 39+8 qualified IDs with assertion/actor/fixture/cleanup columns.

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'FolderOverlayViewTests|FolderOverlayViewPagingTests'
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(FolderOverlayViewTests|FolderOverlayViewPagingTests)/' | \
  LC_ALL=C sort > /tmp/task-19-folder-actual-after.txt
awk -F'`' \
  '$0 ~ /^\| `LaunchPadTests\.(FolderOverlayViewTests|FolderOverlayViewPagingTests)\// { print $4 }' \
  docs/superpowers/reports/2026-07-21-task-19-folder-overlay-migration.md | \
  LC_ALL=C sort > /tmp/task-19-folder-expected-after.txt
awk -F'`' \
  '$0 ~ /^\| `LaunchPadTests\.(FolderOverlayViewTests|FolderOverlayViewPagingTests)\// { print $2 }' \
  docs/superpowers/reports/2026-07-21-task-19-folder-overlay-migration.md | \
  LC_ALL=C sort > /tmp/task-19-folder-expected-before.txt
test "$(wc -l < /tmp/task-19-folder-expected-before.txt | tr -d ' ')" -eq 47
test "$(wc -l < /tmp/task-19-folder-expected-after.txt | tr -d ' ')" -eq 47
test "$(wc -l < /tmp/task-19-folder-actual-after.txt | tr -d ' ')" -eq 47
diff -u /tmp/task-19-folder-actual-before.txt \
  /tmp/task-19-folder-expected-before.txt
diff -u /tmp/task-19-folder-expected-after.txt \
  /tmp/task-19-folder-actual-after.txt
! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:|RunLoop\.main\.run' \
  Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift \
  Tests/LaunchPadTests/Views/FolderOverlayViewPagingTests.swift
git diff --exit-code HEAD -- Sources
git add Tests/LaunchPadTests/Views/FolderOverlayViewPagingTests.swift \
  docs/superpowers/reports/2026-07-21-task-19-folder-overlay-migration.md
git commit -m "test: migrate folder paging tests to Swift Testing"
```

Expected: the captured old discovery, report old-ID column, report new-ID
column and new discovery each contain exactly 47 qualified IDs. Both canonical
`diff -u` commands are empty, proving old and new IDs are each unique and
one-to-one; all tests pass, the static scan is empty and both migration commits
have no production diff.

- [x] **Step 4: Add RED tests for inner folder and overlay-exterior branches**

Use valid UUID fixtures and add:

```swift
private func makeApp(
    id: Int64,
    parentID: Int64 = 50,
    ordering: Int = 0
) -> PageItem {
    TestDataFactory.makePageItem(
        id: id,
        uuid: "00000000-0000-0000-0000-\(String(format: "%012lld", id))",
        type: .app,
        ordering: ordering,
        parentId: parentID,
        app: TestDataFactory.makeAppInfo(id: id, title: "A\(id)")
    )
}

private func makeFolder(id: Int64 = 50) -> PageItem {
    TestDataFactory.makePageItem(
        id: id,
        uuid: "10000000-0000-0000-0000-\(String(format: "%012lld", id))",
        type: .group,
        ordering: 0,
        parentId: 1,
        group: TestDataFactory.makeGroupInfo(id: id, title: "Folder \(id)")
    )
}

private func makeFolderChildSession(
    itemID: Int64 = 10,
    folderID: Int64 = 50
) -> DragSession {
    DragSession(
        itemID: itemID,
        itemUUID: "00000000-0000-0000-0000-\(String(format: "%012lld", itemID))",
        itemType: .app,
        sourceKind: .folderChild,
        sourceParentID: folderID,
        sourceVisualIndex: 0
    )
}

// In the migrated paging suite, retain paginateItems as a pure helper test.
private func makePagingOverlay() -> FolderOverlayView {
    FolderOverlayView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 700)
    )
}

private func pagingFolder() -> PageItem {
    TestDataFactory.makePageItem(
        id: 50,
        type: .group,
        parentId: 1,
        group: TestDataFactory.makeGroupInfo(id: 50, title: "Folder")
    )
}

private func sectionCounts(_ overlay: FolderOverlayView) -> [Int] {
    (0..<overlay.numberOfSections(in: overlay.folderCollectionView)).map {
        overlay.collectionView(
            overlay.folderCollectionView,
            numberOfItemsInSection: $0
        )
    }
}

@Test("folder metrics 使用实际宽高并封顶 35")
func metricsUseActualWidthHeightAndCapAtThirtyFive() {
    let one = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: 96, height: 96)
    )
    #expect(one.columns == 1)
    #expect(one.rows == 1)
    #expect(one.pageCapacity == 1)
    #expect(one.horizontalInset == 12)

    let medium = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: 496, height: 360)
    )
    #expect(medium.columns == 6)
    #expect(medium.rows == 4)
    #expect(medium.pageCapacity == 24)
    #expect(medium.horizontalInset == 12)
    #expect(
        FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(
                width: CGFloat(496).nextDown,
                height: 360
            )
        ).pageCapacity == 20
    )
    #expect(
        FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(
                width: 496,
                height: CGFloat(360).nextDown
            )
        ).pageCapacity == 18
    )

    let capped = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: 800, height: 624)
    )
    #expect(capped.columns == 5)
    #expect(capped.rows == 7)
    #expect(capped.pageCapacity == 35)
    #expect(capped.horizontalInset == 204)

    let invalid = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: .nan, height: .infinity)
    )
    #expect(invalid.columns == 1)
    #expect(invalid.rows == 1)
    #expect(invalid.pageCapacity == 1)
    #expect(invalid.horizontalInset.isFinite)
}

@Test("open 使用实际 folder viewport 容量")
func openUsesActualFolderViewportCapacity() {
    let pagingOverlay = makePagingOverlay()
    pagingOverlay.folderViewportSizeProvider = {
        CGSize(width: 500, height: 400)
    }
    pagingOverlay.openFolder(
        item: pagingFolder(),
        childItems: TestDataFactory.makeAppItems(count: 41),
        iconCache: nil
    )

    #expect(pagingOverlay.currentPageCapacity == 24)
    #expect(sectionCounts(pagingOverlay) == [24, 17])
    #expect(pagingOverlay.currentVisualPageIndex == 0)
}

@Test("reload 重新分页并夹紧当前页")
func reloadRepaginatesAndClampsCurrentPage() {
    let pagingOverlay = makePagingOverlay()
    pagingOverlay.folderViewportSizeProvider = {
        CGSize(width: 500, height: 400)
    }
    pagingOverlay.openFolder(
        item: pagingFolder(),
        childItems: TestDataFactory.makeAppItems(count: 60),
        iconCache: nil
    )
    pagingOverlay.folderScrollView.frame = NSRect(
        x: 0, y: 0, width: 500, height: 400
    )
    pagingOverlay.folderPageControl.onDotSelected?(2)
    #expect(pagingOverlay.currentVisualPageIndex == 2)

    pagingOverlay.reloadChildren(
        TestDataFactory.makeAppItems(count: 25)
    )

    #expect(pagingOverlay.currentPageCapacity == 24)
    #expect(sectionCounts(pagingOverlay) == [24, 1])
    #expect(pagingOverlay.currentVisualPageIndex == 1)
    #expect(pagingOverlay.emptyPlacement(inVisualPage: 1)
        == .afterItem(itemID: 25))
}

@Test("resize 重新分页并夹紧当前页")
func resizeRepaginatesAndClampsCurrentPage() {
    let pagingOverlay = makePagingOverlay()
    var viewport = CGSize(width: 500, height: 400)
    pagingOverlay.folderViewportSizeProvider = { viewport }
    pagingOverlay.openFolder(
        item: pagingFolder(),
        childItems: TestDataFactory.makeAppItems(count: 60),
        iconCache: nil
    )
    pagingOverlay.folderScrollView.frame = NSRect(
        x: 0, y: 0, width: 500, height: 400
    )
    pagingOverlay.folderPageControl.onDotSelected?(2)
    #expect(pagingOverlay.currentVisualPageIndex == 2)

    viewport = CGSize(width: 500, height: 624)
    pagingOverlay.layout()

    #expect(pagingOverlay.currentPageCapacity == 35)
    #expect(sectionCounts(pagingOverlay) == [35, 25])
    #expect(pagingOverlay.currentVisualPageIndex == 1)
    #expect(pagingOverlay.emptyPlacement(inVisualPage: 1)
        == .afterItem(itemID: 60))
}

// Each FolderOverlayView test calls makeOverlay() from migration Step 2.

@Test("folder source 捕获当前 folder identity")
func folderSourceCapturesCurrentFolderIdentityThroughRealDelegate() throws {
    let overlay = makeOverlay()
    let folder = makeFolder(id: 50)
    let child = makeApp(id: 10, parentID: 50)
    overlay.openFolder(item: folder, childItems: [child], iconCache: nil)
    overlay.dragController = DragController(scheduler: MockScheduler())
    let delegate = try #require(overlay.folderCollectionView.delegate)
    #expect(delegate === overlay)

    let writer = delegate.collectionView?(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    )

    #expect(writer != nil)
    let session = try #require(overlay.dragController?.session)
    #expect(session.sourceKind == .folderChild)
    #expect(session.sourceParentID == 50)
}

@Test("folder 第二视觉页空白使用最后稳定 child ID")
func folderEmptyOnSecondVisualPageUsesLastStableChildID() {
    let overlay = makeOverlay()
    let children = (1...40).map { makeApp(id: Int64($0), parentID: 50) }
    overlay.folderViewportSizeProvider = {
        CGSize(width: 500, height: 400)
    }
    overlay.openFolder(item: makeFolder(id: 50), childItems: children, iconCache: nil)

    #expect(overlay.emptyPlacement(inVisualPage: 1)
        == .afterItem(itemID: 40))
}

@Test("overlay 外部 drop 使用已解析 top-level placement")
func overlayExteriorDropUsesResolvedTopLevelPlacement() {
    let overlay = makeOverlay()
    let session = makeFolderChildSession(itemID: 10, folderID: 50)
    overlay.dragController = DragController(scheduler: MockScheduler())
    overlay.dragController?.beginDrag(session)
    overlay.topLevelPlacementResolver = { _ in .beforeItem(itemID: 99) }
    var received: FolderDropDestination?
    overlay.onDropRequested = { _, destination in
        received = destination
        return true
    }

    #expect(overlay.performExteriorDrop(at: NSPoint(x: 10, y: 10)))
    #expect(received == .outside(.beforeItem(itemID: 99)))
}

@Test("未解析 external drop 拒绝且不回调")
func unresolvedExteriorDropRejectsWithoutCallback() {
    let overlay = makeOverlay()
    overlay.dragController = DragController(scheduler: MockScheduler())
    overlay.dragController?.beginDrag(makeFolderChildSession())
    overlay.topLevelPlacementResolver = { _ in nil }
    var called = false
    overlay.onDropRequested = { _, _ in called = true; return true }

    #expect(!overlay.performExteriorDrop(at: NSPoint(x: 10, y: 10)))
    #expect(!called)
}

@Test("folder stale 与非法 indexPath 拒绝且零回调")
func staleInsideIndexPathsRejectWithoutCallback() throws {
    let overlay = makeOverlay()
    let window = makeWindowHosting(overlay)
    _ = window
    let child = makeApp(id: 10, parentID: 50)
    overlay.openFolder(
        item: makeFolder(id: 50),
        childItems: [child],
        iconCache: nil
    )
    overlay.layoutSubtreeIfNeeded()
    let controller = DragController(scheduler: MockScheduler())
    overlay.dragController = controller
    let session = makeFolderChildSession(itemID: 10, folderID: 50)
    overlay.pasteboardUUIDReader = { _ in session.itemUUID }
    let delegate = try #require(overlay.folderCollectionView.delegate)
    #expect(delegate === overlay)
    var callbackCount = 0
    overlay.onDropRequested = { _, _ in
        callbackCount += 1
        return true
    }
    let stalePaths = [
        IndexPath(item: -1, section: 0),
        IndexPath(item: 0, section: -1),
        IndexPath(item: 0, section: 1),
        IndexPath(item: 1, section: 0),
    ]

    for stalePath in stalePaths {
        controller.beginDrag(session)
        overlay.folderIndexPathResolver = { _ in stalePath }
        let info = makeDraggingInfo(
            session: session,
            windowPoint: overlay.folderCollectionView.convert(
                NSPoint(x: 10, y: 10),
                to: nil
            )
        )
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        var operation: NSCollectionView.DropOperation = .before
        let validation = withUnsafeMutablePointer(
            to: &operation
        ) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                delegate.collectionView?(
                    overlay.folderCollectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                        proposedPointer
                    ),
                    dropOperation: operationPointer
                ) ?? []
            }
        }
        #expect(validation == [])
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            acceptDrop: info,
            indexPath: stalePath,
            dropOperation: .before
        ) == false)
    }

    #expect(callbackCount == 0)
}

@Test("folder native delegate 拒绝全部无效 source/session 分支")
func folderNativeDelegateRejectsInvalidSourceSessions() throws {
    let source = makeApp(id: 10, parentID: 50)
    let target = makeApp(id: 11, parentID: 50, ordering: 1)
    let valid = makeFolderChildSession(itemID: 10, folderID: 50)

    func session(
        itemID: Int64 = 10,
        itemUUID: String =
            "00000000-0000-0000-0000-000000000010",
        itemType: ItemType = .app,
        sourceKind: DragSourceKind = .folderChild,
        parentID: Int64 = 50
    ) -> DragSession {
        DragSession(
            itemID: itemID,
            itemUUID: itemUUID,
            itemType: itemType,
            sourceKind: sourceKind,
            sourceParentID: parentID,
            sourceVisualIndex: 0
        )
    }

    func assertRejected(
        activeSession: DragSession?,
        pasteboardValue: String?,
        isDragEnabled: Bool = true,
        opensFolder: Bool = true,
        children: [PageItem]? = nil,
        resolvedIndexPath: IndexPath? = nil,
        resolvedFrame: NSRect? = nil
    ) throws {
        let overlay = makeOverlay()
        let window = makeWindowHosting(overlay)
        _ = window
        overlay.openFolder(
            item: makeFolder(id: 50),
            childItems: children ?? [source, target],
            iconCache: nil
        )
        if !opensFolder {
            overlay.closeFolder()
            #expect(overlay.currentFolderID == nil)
        }
        overlay.layoutSubtreeIfNeeded()
        let controller = DragController(scheduler: MockScheduler())
        overlay.dragController = controller
        if let activeSession { controller.beginDrag(activeSession) }
        overlay.isDragEnabled = isDragEnabled
        overlay.pasteboardUUIDReader = { _ in pasteboardValue }
        overlay.folderIndexPathResolver = { _ in resolvedIndexPath }
        overlay.folderItemFrameResolver = { _ in resolvedFrame }
        var callbackCount = 0
        overlay.onDropRequested = { _, _ in
            callbackCount += 1
            return true
        }
        let delegate = try #require(overlay.folderCollectionView.delegate)
        #expect(delegate === overlay)
        let info = makeDraggingInfo(
            session: valid,
            windowPoint: overlay.folderCollectionView.convert(
                NSPoint(x: 10, y: 10),
                to: nil
            )
        )
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        var operation: NSCollectionView.DropOperation = .before
        let validation = withUnsafeMutablePointer(
            to: &operation
        ) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                delegate.collectionView?(
                    overlay.folderCollectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                        proposedPointer
                    ),
                    dropOperation: operationPointer
                ) ?? []
            }
        }
        #expect(validation == [])
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            acceptDrop: info,
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        ) == false)
        #expect(callbackCount == 0)
        #expect(controller.session == nil)
    }

    try assertRejected(
        activeSession: valid,
        pasteboardValue: nil
    )
    try assertRejected(
        activeSession: valid,
        pasteboardValue: "malformed"
    )
    try assertRejected(
        activeSession: valid,
        pasteboardValue: "00000000-0000-0000-0000-000000000099"
    )
    try assertRejected(
        activeSession: nil,
        pasteboardValue: valid.itemUUID
    )
    try assertRejected(
        activeSession: valid,
        pasteboardValue: valid.itemUUID,
        isDragEnabled: false
    )
    try assertRejected(
        activeSession: session(itemType: .group),
        pasteboardValue: valid.itemUUID
    )
    try assertRejected(
        activeSession: session(sourceKind: .topLevel),
        pasteboardValue: valid.itemUUID
    )
    try assertRejected(
        activeSession: session(parentID: 99),
        pasteboardValue: valid.itemUUID
    )
    try assertRejected(
        activeSession: session(
            itemID: 99,
            itemUUID: "00000000-0000-0000-0000-000000000099"
        ),
        pasteboardValue: "00000000-0000-0000-0000-000000000099"
    )
    let mismatchedUUIDChild = TestDataFactory.makePageItem(
        id: 10,
        uuid: "00000000-0000-0000-0000-000000000099",
        type: .app,
        parentId: 50,
        app: TestDataFactory.makeAppInfo(id: 10, title: "Mismatch UUID")
    )
    try assertRejected(
        activeSession: valid,
        pasteboardValue: valid.itemUUID,
        children: [mismatchedUUIDChild, target]
    )
    let mismatchedParentChild = makeApp(id: 10, parentID: 99)
    try assertRejected(
        activeSession: valid,
        pasteboardValue: valid.itemUUID,
        children: [mismatchedParentChild, target]
    )
    try assertRejected(
        activeSession: valid,
        pasteboardValue: valid.itemUUID,
        resolvedIndexPath: IndexPath(item: 1, section: 0),
        resolvedFrame: nil
    )
    try assertRejected(
        activeSession: valid,
        pasteboardValue: valid.itemUUID,
        opensFolder: false
    )
}

private func makeWindowHosting(
    _ view: NSView,
    origin: NSPoint = NSPoint(x: 140, y: 90)
) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
        styleMask: [],
        backing: .buffered,
        defer: false
    )
    let host = NSView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = host
    view.frame = NSRect(x: origin.x, y: origin.y, width: 800, height: 600)
    host.addSubview(view)
    return window
}

private func makeDraggingInfo(
    session: DragSession,
    windowPoint: NSPoint
) -> MockDraggingInfo {
    let pasteboard = NSPasteboard(
        name: .init("folder-\(UUID().uuidString)")
    )
    return MockDraggingInfo(pasteboard: pasteboard, location: windowPoint)
}

private func assertSecondVisualPageBlankDrop(
    itemCount: Int,
    expectedAnchorID: Int64
) throws {
    let overlay = makeOverlay()
    let window = makeWindowHosting(overlay)
    _ = window
    overlay.folderViewportSizeProvider = {
        CGSize(width: 500, height: 400)
    }
    let children = (1...itemCount).map {
        makeApp(id: Int64($0), parentID: 50, ordering: $0 - 1)
    }
    overlay.openFolder(
        item: makeFolder(id: 50),
        childItems: children,
        iconCache: nil
    )
    overlay.layoutSubtreeIfNeeded()
    overlay.folderScrollView.frame = NSRect(
        x: 0, y: 0, width: 500, height: 400
    )
    overlay.folderPageControl.onDotSelected?(1)
    #expect(overlay.currentVisualPageIndex == 1)

    let controller = DragController(scheduler: MockScheduler())
    overlay.dragController = controller
    let session = makeFolderChildSession(itemID: 1, folderID: 50)
    controller.beginDrag(session)
    overlay.pasteboardUUIDReader = { _ in session.itemUUID }
    var resolvedPoints: [NSPoint] = []
    overlay.folderIndexPathResolver = { point in
        resolvedPoints.append(point)
        return nil
    }
    var received: FolderDropDestination?
    overlay.onDropRequested = { _, destination in
        received = destination
        return true
    }
    let localPoint = NSPoint(x: 220, y: 140)
    let info = makeDraggingInfo(
        session: session,
        windowPoint: overlay.folderCollectionView.convert(
            localPoint,
            to: nil
        )
    )
    let delegate = try #require(overlay.folderCollectionView.delegate)
    #expect(delegate === overlay)

    var proposed = NSIndexPath(forItem: 0, inSection: 1)
    var operation: NSCollectionView.DropOperation = .before
    let validation = withUnsafeMutablePointer(
        to: &operation
    ) { operationPointer in
        withUnsafeMutablePointer(to: &proposed) { proposedPointer in
            delegate.collectionView?(
                overlay.folderCollectionView,
                validateDrop: info,
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                    proposedPointer
                ),
                dropOperation: operationPointer
            ) ?? []
        }
    }
    #expect(validation == .move)
    #expect(delegate.collectionView?(
        overlay.folderCollectionView,
        acceptDrop: info,
        indexPath: IndexPath(item: 0, section: 1),
        dropOperation: .before
    ) == true)
    #expect(received == .inside(.afterItem(itemID: expectedAnchorID)))
    #expect(resolvedPoints.count == 2)
    for point in resolvedPoints {
        #expect(abs(point.x - localPoint.x) <= 0.001)
        #expect(abs(point.y - localPoint.y) <= 0.001)
    }
}

@Test("第二视觉页 item36 空白 drop 使用 item36")
func secondVisualPageItem36BlankDropUsesItem36() throws {
    try assertSecondVisualPageBlankDrop(
        itemCount: 36,
        expectedAnchorID: 36
    )
}

@Test("第二视觉页 item40 空白 drop 使用 item40")
func secondVisualPageItem40BlankDropUsesItem40() throws {
    try assertSecondVisualPageBlankDrop(
        itemCount: 40,
        expectedAnchorID: 40
    )
}

@Test("scroll 同步当前视觉页和空白 anchor")
func scrollSynchronizesCurrentVisualPageAndBlankAnchor() {
    let overlay = makeOverlay()
    let children = (1...40).map {
        makeApp(id: Int64($0), parentID: 50, ordering: $0 - 1)
    }
    overlay.folderViewportSizeProvider = {
        CGSize(width: 500, height: 400)
    }
    overlay.openFolder(
        item: makeFolder(),
        childItems: children,
        iconCache: nil
    )
    overlay.folderScrollView.frame = NSRect(
        x: 0, y: 0, width: 500, height: 400
    )
    overlay.folderScrollView.contentView.scroll(
        to: NSPoint(x: 500, y: 0)
    )
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: overlay.folderScrollView.contentView
    )

    #expect(overlay.currentVisualPageIndex == 1)
    #expect(overlay.emptyPlacement(
        inVisualPage: overlay.currentVisualPageIndex
    ) == .afterItem(itemID: 40))
}

@Test("外部 drag entries 对非零 origin 只转换一次 window point")
func exteriorDragEntriesConvertWindowPointForNonZeroOrigin() {
    let overlay = makeOverlay()
    let window = makeWindowHosting(overlay)
    _ = window
    let child = makeApp(id: 10, parentID: 50)
    overlay.openFolder(
        item: makeFolder(),
        childItems: [child],
        iconCache: nil
    )
    overlay.layoutSubtreeIfNeeded()
    let controller = DragController(scheduler: MockScheduler())
    overlay.dragController = controller
    let session = makeFolderChildSession(itemID: 10, folderID: 50)
    controller.beginDrag(session)
    overlay.pasteboardUUIDReader = { _ in session.itemUUID }
    var points: [NSPoint] = []
    overlay.topLevelPlacementResolver = { point in
        points.append(point)
        return .beforeItem(itemID: 99)
    }
    overlay.onDropRequested = { _, _ in true }
    let localPoint = NSPoint(x: 5, y: 5)
    let info = makeDraggingInfo(
        session: session,
        windowPoint: overlay.convert(localPoint, to: nil)
    )

    #expect(overlay.draggingEntered(info) == .move)
    #expect(overlay.draggingUpdated(info) == .move)
    #expect(overlay.prepareForDragOperation(info))
    #expect(overlay.performDragOperation(info))
    #expect(points.count == 4)
    for point in points {
        #expect(abs(point.x - localPoint.x) <= 0.001)
        #expect(abs(point.y - localPoint.y) <= 0.001)
    }
}

@Test("folder dragging session end 清理取消会话")
func folderDraggingSessionEndClearsCancelledSessionThroughRealDelegate() throws {
    let overlay = makeOverlay()
    overlay.openFolder(
        item: makeFolder(id: 50),
        childItems: [makeApp(id: 10, parentID: 50)],
        iconCache: nil
    )
    let scheduler = MockScheduler()
    let controller = DragController(scheduler: scheduler)
    overlay.dragController = controller
    controller.beginDrag(makeFolderChildSession())
    controller.updateDragHover(.item(itemID: 11, itemType: .app))
    let delegate = try #require(overlay.folderCollectionView.delegate)
    #expect(delegate === overlay)

    delegate.collectionView?(
        overlay.folderCollectionView,
        draggingSession: NSDraggingSession(),
        endedAt: .zero,
        dragOperation: []
    )

    #expect(controller.state == .idle)
    #expect(controller.session == nil)
    #expect(scheduler.scheduledActions.isEmpty)
}
```

Add the remaining source and intent branches explicitly:

```swift
@Test("folder source 拒绝 group、非法 child 与 stale indexPath")
func folderSourceRejectsGroupInvalidChildAndStaleIndexPaths() throws {
    let overlay = makeOverlay()
    let folder = makeFolder(id: 50)
    let group = makeFolder(id: 60)
    let wrongParent = makeApp(id: 10, parentID: 99)
    overlay.openFolder(
        item: folder,
        childItems: [group, wrongParent],
        iconCache: nil
    )
    overlay.dragController = DragController(scheduler: MockScheduler())
    let delegate = try #require(overlay.folderCollectionView.delegate)
    #expect(delegate === overlay)

    #expect(delegate.collectionView?(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    ) == nil)
    #expect(delegate.collectionView?(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)
    ) == nil)
    for stalePath in [
        IndexPath(item: -1, section: 0),
        IndexPath(item: 0, section: -1),
        IndexPath(item: 0, section: 1),
        IndexPath(item: 2, section: 0),
    ] {
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            pasteboardWriterForItemAt: stalePath
        ) == nil)
    }
    #expect(overlay.dragController?.session == nil)
}

@Test("folder source 拒绝 disabled、closed folder 与 malformed UUID")
func folderSourceRejectsDisabledClosedAndMalformedUUID() throws {
    let overlay = makeOverlay()
    let valid = makeApp(id: 10, parentID: 50)
    let malformed = TestDataFactory.makePageItem(
        id: 11,
        uuid: "malformed",
        type: .app,
        ordering: 1,
        parentId: 50,
        app: TestDataFactory.makeAppInfo(id: 11, title: "Malformed")
    )
    overlay.openFolder(
        item: makeFolder(id: 50),
        childItems: [valid, malformed],
        iconCache: nil
    )
    overlay.dragController = DragController(scheduler: MockScheduler())
    let delegate = try #require(overlay.folderCollectionView.delegate)
    #expect(delegate === overlay)

    overlay.isDragEnabled = false
    #expect(delegate.collectionView?(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    ) == nil)

    overlay.isDragEnabled = true
    #expect(delegate.collectionView?(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)
    ) == nil)

    overlay.closeFolder()
    #expect(overlay.currentFolderID == nil)
    #expect(delegate.collectionView?(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    ) == nil)
    #expect(overlay.dragController?.session == nil)
}

@Test("folder drop 拒绝 self 和 callback failure")
func folderDropRejectsSelfAndCallbackFailure() {
    let overlay = makeOverlay()
    let session = makeFolderChildSession(itemID: 10, folderID: 50)
    overlay.dragController = DragController(scheduler: MockScheduler())
    overlay.dragController?.beginDrag(session)
    var calls = 0
    overlay.onDropRequested = { _, _ in calls += 1; return false }

    #expect(!overlay.performFolderDrop(
        session: session,
        destination: .inside(.beforeItem(itemID: 10))
    ))
    #expect(calls == 0)
    #expect(!overlay.performFolderDrop(
        session: session,
        destination: .inside(.afterItem(itemID: 11))
    ))
    #expect(calls == 1)
}

@Test("folder inside/outside 分别映射 reorder/remove intent")
func folderIntentMappingIsExhaustive() {
    let (sut, _, _) = makeSUT(layoutMutator: MockLayoutMutator())
    let child = makeFolderChildSession(itemID: 10, folderID: 50)
    #expect(sut.makeFolderIntent(
        session: child,
        destination: .inside(.beforeItem(itemID: 11))
    ) == .reorderFolderItem(
        itemID: 10,
        folderID: 50,
        placement: .beforeItem(itemID: 11)
    ))
    #expect(sut.makeFolderIntent(
        session: child,
        destination: .outside(.afterItem(itemID: 99))
    ) == .removeFromFolder(
        itemID: 10,
        folderID: 50,
        placement: .afterItem(itemID: 99)
    ))
    #expect(sut.makeFolderIntent(
        session: child,
        destination: .inside(.beforeItem(itemID: 10))
    ) == nil)
}
```

Controller integration adds three storage-result fixtures: a successful inner
reorder reloads the remaining folder children, a successful drag-out whose
transaction auto-dissolves the folder closes the overlay, and a thrown mutation
reloads the original children, returns false and shows exactly
`无法更新布局，请重试`. Each fixture asserts one mutation attempt and no second
writer path.

- [x] **Step 5: Add RED safe-delete and lifecycle tests**

First remove the window-test fixed-wait fixture completely. Delete
`pumpRunloopBriefly(for:)` and `flushMainQueue(for:)`; replace all 11
`flushMainQueue` call sites and the direct run-loop pump in
`applyAccessibilitySettings_onNotification_updatesMaterial`. Tests that cross
the controller's main-actor dispatch boundary use the following synchronous
boundary fixture, which is RED until Step 13 adds `mainActorDispatcher` and the
application lookup/open seams:

```swift
private func makeSynchronousWindowSUT() -> SUT {
    let sut = makeSUT()
    sut.controller.mainActorDispatcher = { operation in
        MainActor.assumeIsolated { operation() }
    }
    sut.controller.runAnimated = { _, animations, completion in
        animations()
        completion()
    }
    sut.controller.mainAsyncRunner = { $0() }
    sut.controller.applicationURLProvider = { _ in
        URL(fileURLWithPath: "/Applications/LaunchPad-Test.app")
    }
    sut.controller.applicationOpener = { _ in }
    return sut
}
```

Use this fixture in the existing opening, closing, hidden, launch, reduced
motion and short-duration tests and remove `async` from those methods. The
notification test posts on `@MainActor` and asserts immediately; Task 21 later
injects its local notification center/settings source. Replace the existing
Finder lookup test with an exact side-effect-free assertion:

```swift
@Test("launch request 使用注入 URL 并只调用一次 opener")
func launchRequestUsesInjectedApplicationBoundary() {
    let sut = makeSynchronousWindowSUT()
    let expected = URL(fileURLWithPath: "/Applications/Target.app")
    var requestedBundleID: String?
    var openedURLs: [URL] = []
    sut.controller.applicationURLProvider = {
        requestedBundleID = $0
        return expected
    }
    sut.controller.applicationOpener = { openedURLs.append($0) }

    sut.controller.lifecycle(
        sut.lifecycle,
        shouldLaunchApp: "com.test.target"
    )

    #expect(requestedBundleID == "com.test.target")
    #expect(openedURLs == [expected])
}
```

No `LaunchPadWindowControllerTests` method may call a real application URL
lookup/open operation or wait for elapsed wall-clock time.

```swift
@Test("FolderCell edit mode 显示可用删除按钮")
func folderCellEditingShowsWorkingDeleteButton() {
    let cell = FolderCell()
    _ = cell.view
    var deleted = false
    cell.onDelete = { deleted = true }

    cell.setEditing(true)
    #expect(cell.isDeleteControlVisible)
    cell.performDeleteForTesting()
    #expect(deleted)

    cell.setEditing(false)
    #expect(!cell.isDeleteControlVisible)
}

@Test("文件夹删除取消时零 mutation，确认后只提交安全删除 intent")
func folderDeleteRequiresConfirmation() {
    let mutator = MockLayoutMutator()
    let (sut, _, storage) = makeSUT(layoutMutator: mutator)
    loadViewWithData(sut, storage: storage)
    sut.viewDidLayout()
    let folder = makeFolder(id: 50)

    sut.confirmFolderDeletion = { _ in false }
    sut.handleItemDelete(folder)
    #expect(mutator.applyAttemptCount == 0)

    sut.confirmFolderDeletion = { _ in true }
    sut.handleItemDelete(folder)
    #expect(mutator.attemptedIntents == [.deleteFolder(folderID: 50)])
}

@Test("窗口进入 closing 会清理活动拖拽")
func closingWindowClearsDragSession() {
    let sut = makeSynchronousWindowSUT()
    sut.viewController.dragController.beginDrag(makeSession())

    sut.controller.lifecycle(sut.lifecycle, didTransitionTo: .closing)

    #expect(sut.viewController.dragController.session == nil)
}

@Test("重复 open 只保留一个 observer 且 close 移除")
func repeatedOpenKeepsOneObserverAndCloseRemovesIt() {
    let sut = makeOverlay()
    sut.closeFolderCompletionRunner = { $0() }
    var scrollUpdateCount = 0
    sut.scrollPositionDidUpdate = { scrollUpdateCount += 1 }
    let folder = makeFolder()
    let children = (1...40).map {
        makeApp(id: Int64($0), parentID: 50, ordering: $0 - 1)
    }
    sut.openFolder(item: folder, childItems: children, iconCache: nil)
    sut.openFolder(item: folder, childItems: children, iconCache: nil)
    #expect(sut.isObservingScrollPosition)
    let beforePost = scrollUpdateCount
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: sut.folderScrollView.contentView
    )
    #expect(scrollUpdateCount == beforePost + 1)

    sut.closeFolder()
    #expect(!sut.isObservingScrollPosition)
    let afterClose = scrollUpdateCount
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: sut.folderScrollView.contentView
    )
    #expect(scrollUpdateCount == afterClose)
}

@Test("deinit 释放带 scroll observer 的 overlay")
func deinitReleasesOverlayWithInstalledScrollObserver() {
    weak var weakOverlay: FolderOverlayView?
    autoreleasepool {
        var sut: FolderOverlayView? = makeOverlay()
        sut?.openFolder(
            item: makeFolder(),
            childItems: [makeApp(id: 1)],
            iconCache: nil
        )
        #expect(sut?.isObservingScrollPosition == true)
        weakOverlay = sut
        sut = nil
    }
    #expect(weakOverlay == nil)
}
```

- [x] **Step 6: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'FolderOverlayViewTests|FolderOverlayViewPagingTests|FolderCellTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|FolderControllerTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests'
```

Expected: compile RED for folder viewport capacity/reprojection, folder
destination, overlay-exterior destination methods, reload API, delete control
window cleanup, `mainActorDispatcher` and application URL/open boundaries.

- [x] **Step 7: Add complete FolderOverlay source, inner destination and reload APIs**

Add state and callbacks:

```swift
struct FolderGridMetrics: Sendable, Equatable {
    let columns: Int
    let rows: Int
    let pageCapacity: Int
    let horizontalInset: CGFloat
}

nonisolated static let maximumFolderItemsPerPage = 35
nonisolated static let folderItemWidth: CGFloat = 72
nonisolated static let folderItemHeight: CGFloat = 80
nonisolated static let folderItemSpacing: CGFloat = 8
nonisolated static let minimumFolderHorizontalInset: CGFloat = 12
nonisolated static let folderVerticalInset: CGFloat = 8

nonisolated static func folderGridMetrics(
    forViewportSize rawSize: CGSize
) -> FolderGridMetrics {
    let width = rawSize.width.isFinite ? max(0, rawSize.width) : 0
    let height = rawSize.height.isFinite ? max(0, rawSize.height) : 0
    let availableWidth = max(
        0,
        width - 2 * minimumFolderHorizontalInset
    )
    let available = max(0, height - 2 * folderVerticalInset)
    let calculatedColumns = (availableWidth + folderItemSpacing)
        / (folderItemWidth + folderItemSpacing)
    let calculatedRows = (available + folderItemSpacing)
        / (folderItemHeight + folderItemSpacing)
    let fittingColumns = max(1, Int(min(
        CGFloat(maximumFolderItemsPerPage),
        calculatedColumns
    )))
    let fittingRows = max(1, Int(min(
        CGFloat(maximumFolderItemsPerPage),
        calculatedRows
    )))
    let capacity = min(
        maximumFolderItemsPerPage,
        fittingColumns * fittingRows
    )
    let layoutColumns = min(
        fittingColumns,
        max(1, (capacity + fittingRows - 1) / fittingRows)
    )
    let occupiedWidth = CGFloat(layoutColumns) * folderItemWidth
        + CGFloat(layoutColumns - 1) * folderItemSpacing
    return FolderGridMetrics(
        columns: layoutColumns,
        rows: fittingRows,
        pageCapacity: capacity,
        horizontalInset: max(
            minimumFolderHorizontalInset,
            (width - occupiedWidth) / 2
        )
    )
}

public enum FolderDropDestination: Sendable, Equatable {
    case inside(ItemPlacement)
    case outside(ItemPlacement)
}

public var dragController: DragController?
public var onDropRequested: ((DragSession, FolderDropDestination) -> Bool)?
public var topLevelPlacementResolver: ((NSPoint) -> ItemPlacement?)?
public private(set) var currentFolderID: Int64?
private(set) var currentVisualPageIndex = 0
private(set) var currentPageCapacity = 0
private(set) var currentFolderGridMetrics: FolderGridMetrics?
var folderViewportSizeProvider: (() -> CGSize)?
private var projectedFolderViewportSize: CGSize?
private var isReprojectingChildren = false
private var scrollObserverToken: NSObjectProtocol?
var folderCollectionView: NSCollectionView { collectionView }
var folderScrollView: NSScrollView { scrollView }
var folderPageControl: PageControlView { pageControlView }
var isObservingScrollPosition: Bool { scrollObserverToken != nil }
var folderIndexPathResolver: ((NSPoint) -> IndexPath?)?
var folderItemFrameResolver: ((IndexPath) -> NSRect?)?
var scrollPositionDidUpdate: (() -> Void)?

deinit {
    if let scrollObserverToken {
        NotificationCenter.default.removeObserver(scrollObserverToken)
    }
}
```

Task 18 already supplies `isDragEnabled`. In `setup()`, register both receivers:

```swift
collectionView.registerForDraggedTypes([.string])
registerForDraggedTypes([.string])
```

In `openFolder`, sort stable children and reset identity before applying the
existing responsive panel constraints:

```swift
currentFolderID = item.id
currentVisualPageIndex = 0
self.childItems = childItems.sorted {
    $0.ordering == $1.ordering
        ? $0.id < $1.id
        : $0.ordering < $1.ordering
}
```

After updating `backgroundWidthConstraint` and `backgroundHeightConstraint`,
finish the open path in this order so the clip viewport is measured after Auto
Layout and before the first snapshot is visible:

```swift
isHidden = false
layoutSubtreeIfNeeded()
reprojectChildren(resetCurrentPage: true, forceReload: true)
observeScrollPosition()
```

Delete the old fixed `maxItemsPerPage = 35`, initial `paginateItems`, page
control configuration, `reloadData` and the later duplicate
`observeScrollPosition()` calls from `openFolder`.

Use one replaceable block-observer token and clear it on close/deinit:

```swift
private func stopObservingScrollPosition() {
    guard let scrollObserverToken else { return }
    NotificationCenter.default.removeObserver(scrollObserverToken)
    self.scrollObserverToken = nil
}

public func observeScrollPosition() {
    stopObservingScrollPosition()
    scrollView.contentView.postsBoundsChangedNotifications = true
    scrollObserverToken = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: scrollView.contentView,
        queue: .main
    ) { [weak self] _ in
        MainActor.assumeIsolated {
            self?.updatePageFromScrollPosition()
        }
    }
}
```

Delete the old second `observeScrollPosition()` call later in `openFolder`; the
reset block above is the only installation point. Replace `closeFolder` with:

```swift
public func closeFolder() {
    closeFolderCompletionRunner { [weak self] in
        MainActor.assumeIsolated {
            guard let self else { return }
            stopObservingScrollPosition()
            currentVisualPageIndex = 0
            currentPageCapacity = 0
            currentFolderGridMetrics = nil
            projectedFolderViewportSize = nil
            currentFolderID = nil
            isHidden = true
            childItems = []
            pages = []
            onClosed?()
        }
    }
}
```

Add the single folder projection entry. It owns capacity, section insets,
pagination, page clamp, reload and scroll position for open/reload/resize:

```swift
private func reprojectChildren(
    resetCurrentPage: Bool,
    forceReload: Bool = false
) {
    guard !isReprojectingChildren else { return }
    let rawViewport = folderViewportSizeProvider?()
        ?? scrollView.contentView.bounds.size
    let viewport = CGSize(
        width: rawViewport.width.isFinite ? max(0, rawViewport.width) : 0,
        height: rawViewport.height.isFinite ? max(0, rawViewport.height) : 0
    )
    let metrics = Self.folderGridMetrics(forViewportSize: viewport)
    let capacity = metrics.pageCapacity
    guard forceReload
            || capacity != currentPageCapacity
            || viewport != projectedFolderViewportSize else { return }

    isReprojectingChildren = true
    defer { isReprojectingChildren = false }
    currentPageCapacity = capacity
    currentFolderGridMetrics = metrics
    projectedFolderViewportSize = viewport

    if let layout = collectionView.collectionViewLayout
        as? NSCollectionViewFlowLayout {
        layout.itemSize = NSSize(
            width: Self.folderItemWidth,
            height: Self.folderItemHeight
        )
        layout.minimumInteritemSpacing = Self.folderItemSpacing
        layout.minimumLineSpacing = Self.folderItemSpacing
        layout.sectionInset = NSEdgeInsets(
            top: Self.folderVerticalInset,
            left: metrics.horizontalInset,
            bottom: Self.folderVerticalInset,
            right: metrics.horizontalInset
        )
        layout.invalidateLayout()
    }

    pages = Self.paginateItems(childItems, pageSize: capacity)
    let requestedPage = resetCurrentPage ? 0 : currentVisualPageIndex
    currentVisualPageIndex = max(
        0,
        min(requestedPage, max(0, pages.count - 1))
    )
    pageControlViewModel.configure(totalPages: pages.count)
    pageControlViewModel.currentPage = currentVisualPageIndex
    pageControlView.update()
    collectionView.reloadData()
    collectionView.layoutSubtreeIfNeeded()
    if viewport.width > 0 {
        scrollView.contentView.scroll(to: NSPoint(
            x: CGFloat(currentVisualPageIndex) * viewport.width,
            y: 0
        ))
    }
}

override public func layout() {
    super.layout()
    guard !isHidden, currentFolderID != nil else { return }
    reprojectChildren(resetCurrentPage: false)
}
```

Replace page navigation and scroll synchronization with:

```swift
private func navigateToPage(_ pageIndex: Int) {
    guard pageIndex >= 0, pageIndex < pages.count else { return }
    let pageWidth = scrollView.contentView.bounds.width
    guard pageWidth > 0 else { return }
    currentVisualPageIndex = pageIndex
    pageControlViewModel.currentPage = pageIndex
    pageControlView.update()
    NSAnimationContext.runAnimationGroup { context in
        context.duration = AnimationConstants.pageScroll.duration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scrollView.contentView.animator().bounds.origin.x =
            CGFloat(pageIndex) * pageWidth
    }
}

func updatePageFromScrollPosition() {
    scrollPositionDidUpdate?()
    let pageWidth = scrollView.contentView.bounds.width
    guard pageWidth > 0 else { return }
    let page = Int(round(
        scrollView.contentView.bounds.origin.x / pageWidth
    ))
    let clamped = max(0, min(page, max(0, pages.count - 1)))
    currentVisualPageIndex = clamped
    if clamped != pageControlViewModel.currentPage {
        pageControlViewModel.currentPage = clamped
        pageControlView.update()
    }
}
```

Add the reload API:

```swift
public func reloadChildren(_ children: [PageItem]) {
    childItems = children.sorted {
        $0.ordering == $1.ordering
            ? $0.id < $1.id
            : $0.ordering < $1.ordering
    }
    reprojectChildren(resetCurrentPage: false, forceReload: true)
}

func emptyPlacement(inVisualPage pageIndex: Int) -> ItemPlacement? {
    guard pageIndex >= 0, pageIndex < pages.count,
          let last = pages[pageIndex].last else { return nil }
    return .afterItem(itemID: last.id)
}
```

Implement `NSCollectionViewDelegate` source/validation/acceptance with the actual methods:

```swift
public func collectionView(
    _ collectionView: NSCollectionView,
    pasteboardWriterForItemAt indexPath: IndexPath
) -> NSPasteboardWriting? {
    guard isDragEnabled,
          let folderID = currentFolderID,
          pages.indices.contains(indexPath.section),
          pages[indexPath.section].indices.contains(indexPath.item) else {
        return nil
    }
    let item = pages[indexPath.section][indexPath.item]
    guard item.type == .app,
          item.parentId == folderID,
          UUID(uuidString: item.uuid) != nil,
          let visualIndex = childItems.firstIndex(where: { $0.id == item.id }) else {
        return nil
    }

    dragController?.beginDrag(DragSession(
        itemID: item.id,
        itemUUID: item.uuid,
        itemType: item.type,
        sourceKind: .folderChild,
        sourceParentID: folderID,
        sourceVisualIndex: visualIndex
    ))
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(item.uuid, forType: .string)
    return pasteboardItem
}
```

Add the same narrow boundary name used by Task 4, local to the overlay:

```swift
internal var pasteboardUUIDReader: (NSPasteboard) -> String? = {
    $0.string(forType: .string)
}
```

Implement the inner resolver and both AppKit collection-view entries completely.
Each native entry converts the window point once before any local frame lookup:

```swift
private func activeFolderSession(
    from draggingInfo: NSDraggingInfo
) -> DragSession? {
    guard isDragEnabled,
          let folderID = currentFolderID,
          let uuid = pasteboardUUIDReader(draggingInfo.draggingPasteboard),
          UUID(uuidString: uuid) != nil,
          let session = dragController?.session,
          session.itemUUID == uuid,
          session.itemType == .app,
          session.sourceKind == .folderChild,
          session.sourceParentID == folderID,
          childItems.contains(where: {
              $0.id == session.itemID
                && $0.uuid == uuid
                && $0.parentId == folderID
          }) else { return nil }
    return session
}

private func insideDestination(
    at localPoint: NSPoint
) -> FolderDropDestination? {
    let indexPath: IndexPath?
    if let folderIndexPathResolver {
        indexPath = folderIndexPathResolver(localPoint)
    } else {
        indexPath = collectionView.indexPathForItem(at: localPoint)
    }
    guard let indexPath else {
        return emptyPlacement(
            inVisualPage: currentVisualPageIndex
        ).map { .inside($0) }
    }
    guard pages.indices.contains(indexPath.section),
          pages[indexPath.section].indices.contains(indexPath.item) else {
        return nil
    }
    let target = pages[indexPath.section][indexPath.item]
    let frame: NSRect?
    if let folderItemFrameResolver {
        frame = folderItemFrameResolver(indexPath)
    } else {
        frame = collectionView.collectionViewLayout?
            .layoutAttributesForItem(at: indexPath)?.frame
    }
    guard let frame else { return nil }
    return .inside(
        localPoint.x < frame.midX
            ? .beforeItem(itemID: target.id)
            : .afterItem(itemID: target.id)
    )
}

public func collectionView(
    _ collectionView: NSCollectionView,
    validateDrop draggingInfo: NSDraggingInfo,
    proposedIndexPath proposedDropIndexPath:
        AutoreleasingUnsafeMutablePointer<NSIndexPath>,
    dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
) -> NSDragOperation {
    let localPoint = collectionView.convert(
        draggingInfo.draggingLocation,
        from: nil
    )
    guard let session = activeFolderSession(from: draggingInfo),
          let destination = insideDestination(at: localPoint),
          destination.anchorItemID != session.itemID else {
        dragController?.updateDragHover(.empty)
        return []
    }
    dragController?.updateDragHover(.empty)
    dropOperation.pointee = .before
    return .move
}

public func collectionView(
    _ collectionView: NSCollectionView,
    acceptDrop draggingInfo: NSDraggingInfo,
    indexPath: IndexPath,
    dropOperation: NSCollectionView.DropOperation
) -> Bool {
    let localPoint = collectionView.convert(
        draggingInfo.draggingLocation,
        from: nil
    )
    guard let session = activeFolderSession(from: draggingInfo),
          let destination = insideDestination(at: localPoint) else {
        dragController?.cancelDrag()
        return false
    }
    return performFolderDrop(session: session, destination: destination)
}

public func collectionView(
    _ collectionView: NSCollectionView,
    draggingSession session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    dragOperation operation: NSDragOperation
) {
    dragController?.finishDrag()
}
```

Both entries call the same writer-free helper:

```swift
func performFolderDrop(
    session: DragSession,
    destination: FolderDropDestination
) -> Bool {
    guard isDragEnabled,
          session.sourceKind == .folderChild,
          session.sourceParentID == currentFolderID,
          destination.anchorItemID != session.itemID else {
        dragController?.cancelDrag()
        return false
    }
    return onDropRequested?(session, destination) ?? false
}
```

Add an internal computed property because the view controller maps the same
destination type:

```swift
extension FolderDropDestination {
    var anchorItemID: Int64 {
        switch self {
        case .inside(let placement), .outside(let placement):
            return placement.anchorItemID
        }
    }
}
```

- [x] **Step 8: Make FolderOverlay itself receive exterior drops**

`NSDraggingInfo.draggingLocation` is in window coordinates. Every exterior
AppKit entry converts independently; the helper accepts only an overlay-local
point, so a future caller cannot accidentally reuse a window point:

```swift
private func exteriorDestination(
    for draggingInfo: NSDraggingInfo,
    at localPoint: NSPoint
) -> (DragSession, FolderDropDestination)? {
    guard let session = activeFolderSession(from: draggingInfo),
          !backgroundView.frame.contains(localPoint),
          let placement = topLevelPlacementResolver?(localPoint),
          placement.anchorItemID != session.itemID else { return nil }
    return (session, .outside(placement))
}

override public func draggingEntered(
    _ sender: NSDraggingInfo
) -> NSDragOperation {
    let localPoint = convert(sender.draggingLocation, from: nil)
    return exteriorDestination(for: sender, at: localPoint) == nil ? [] : .move
}

override public func draggingUpdated(
    _ sender: NSDraggingInfo
) -> NSDragOperation {
    let localPoint = convert(sender.draggingLocation, from: nil)
    return exteriorDestination(for: sender, at: localPoint) == nil ? [] : .move
}

override public func prepareForDragOperation(
    _ sender: NSDraggingInfo
) -> Bool {
    let localPoint = convert(sender.draggingLocation, from: nil)
    return exteriorDestination(for: sender, at: localPoint) != nil
}

override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let localPoint = convert(sender.draggingLocation, from: nil)
    guard let (session, destination) = exteriorDestination(
        for: sender,
        at: localPoint
    ) else {
        dragController?.cancelDrag()
        return false
    }
    return performFolderDrop(session: session, destination: destination)
}

func performExteriorDrop(at localPoint: NSPoint) -> Bool {
    guard let session = dragController?.session,
          !backgroundView.frame.contains(localPoint),
          let placement = topLevelPlacementResolver?(localPoint) else {
        return false
    }
    return performFolderDrop(
        session: session,
        destination: .outside(placement)
    )
}
```

The final helper is internal and exists only for deterministic tests; production uses the AppKit overrides.

- [x] **Step 9: Bind overlay-local points to main-grid stable placements and reload folder state**

In VC setup:

```swift
folderOverlay.dragController = dragController
folderOverlay.topLevelPlacementResolver = { [weak self] overlayPoint in
    guard let self else { return nil }
    let windowPoint = self.folderOverlay.convert(overlayPoint, to: nil)
    let gridPoint = self.collectionView.convert(windowPoint, from: nil)
    return self.gridInteractionCoordinator?
        .topLevelPlacement(atLocalPoint: gridPoint)
}
folderOverlay.onDropRequested = { [weak self] session, destination in
    self?.handleFolderDrop(session: session, destination: destination) ?? false
}
```

Map and apply through the Task 18 writer:

```swift
func makeFolderIntent(
    session: DragSession,
    destination: FolderDropDestination
) -> LayoutDropIntent? {
    guard session.sourceKind == .folderChild,
          session.itemType == .app,
          destination.anchorItemID != session.itemID else { return nil }
    switch destination {
    case .inside(let placement):
        return .reorderFolderItem(
            itemID: session.itemID,
            folderID: session.sourceParentID,
            placement: placement
        )
    case .outside(let placement):
        return .removeFromFolder(
            itemID: session.itemID,
            folderID: session.sourceParentID,
            placement: placement
        )
    }
}

@discardableResult
func handleFolderDrop(
    session: DragSession,
    destination: FolderDropDestination
) -> Bool {
    guard let intent = makeFolderIntent(
        session: session,
        destination: destination
    ) else {
        dragController.cancelDrag()
        return false
    }

    let succeeded = applyDropIntent(intent)
    if let folder = findItem(byId: session.sourceParentID),
       let children = try? storage.fetchAllItems(parentId: folder.id) {
        folderOverlay.reloadChildren(children)
    } else {
        folderOverlay.closeFolder()
    }
    return succeeded
}
```

Because `applyDropIntent` reloads on both success and failure, failure reloads the original database children and returns false for AppKit snapback; auto-dissolve removes the folder from reloaded top-level state and closes the overlay.

- [x] **Step 10: Remove FolderController's non-atomic layout APIs**

Delete `createFolder`, `addToFolder`, `dissolveFolder`, and `removeFromFolder` plus tests that assert multi-CRUD calls. Keep exactly:

```swift
public final class FolderController {
    private let itemWriter: ItemWriting

    public init(itemWriter: ItemWriting) {
        self.itemWriter = itemWriter
    }

    public func renameFolder(item: PageItem, newTitle: String) throws {
        var group = item.group ?? GroupInfo(id: item.id, title: newTitle)
        group.title = newTitle
        try itemWriter.updateItem(PageItem(
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

All drag and safe-delete writes now go only through `LaunchPadViewController -> LayoutMutating`.

- [x] **Step 11: Add a real FolderCell edit/delete control and wire it**

Add `deleteButton`, `onDelete`, state and methods:

```swift
private let deleteButton = NSButton()
public var onDelete: (() -> Void)?
public private(set) var isEditing = false
var isDeleteControlVisible: Bool { deleteButton.alphaValue > 0 }

private func setupDeleteButton() {
    deleteButton.image = NSImage(
        systemSymbolName: "xmark.circle.fill",
        accessibilityDescription: "Delete folder"
    )
    deleteButton.isBordered = false
    deleteButton.contentTintColor = .systemRed
    deleteButton.target = self
    deleteButton.action = #selector(deleteFolderClicked)
    deleteButton.alphaValue = 0
    deleteButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(deleteButton)
    NSLayoutConstraint.activate([
        deleteButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
        deleteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
        deleteButton.widthAnchor.constraint(equalToConstant: 20),
        deleteButton.heightAnchor.constraint(equalToConstant: 20),
    ])
}

public func setEditing(_ editing: Bool) {
    isEditing = editing
    deleteButton.alphaValue = editing ? 1 : 0
}

@objc private func deleteFolderClicked() {
    onDelete?()
}

func performDeleteForTesting() {
    deleteFolderClicked()
}
```

Call `setupDeleteButton()` from `loadView`, `setEditing(false)` from `prepareForReuse`, and wire `cell.onDelete` to `AppGridCollectionView.onItemDelete`. Extend `updateJiggleState`:

```swift
if let appCell = collectionView.item(at: indexPath) as? AppIconCell {
    if jiggling { appCell.startJiggling() } else { appCell.stopJiggling() }
} else if let folderCell = collectionView.item(at: indexPath) as? FolderCell {
    folderCell.setEditing(jiggling)
}
```

Update existing test injection to provide either cell type, or add a separate `folderJiggleCellProvider` used before the real collection fallback.

- [x] **Step 12: Confirm safe folder delete and retain app deletion**

Add to VC:

```swift
var confirmFolderDeletion: (PageItem) -> Bool = { _ in
    let alert = NSAlert()
    alert.messageText = "删除文件夹？"
    alert.informativeText = "文件夹中的应用会移回主网格。"
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")
    return alert.runModal() == .alertFirstButtonReturn
}
```

Replace `handleItemDelete` with:

```swift
func handleItemDelete(_ item: PageItem) {
    switch item.type {
    case .group:
        guard confirmFolderDeletion(item) else { return }
        _ = applyDropIntent(.deleteFolder(folderID: item.id))
    case .app:
        do {
            try storage.deleteItem(id: item.id)
            dragController.handleCancel()
            updateJiggleState()
            loadData()
        } catch {
            NSLog("[LaunchPadViewController] Failed to delete item")
        }
    case .page:
        return
    }
}
```

The app failure log also avoids interpolating storage details. Tests inject confirmation; no test displays a real alert.

- [x] **Step 13: Clear drag state and make window lifecycle boundaries deterministic**

Add one idempotent VC entry:

```swift
func cancelActiveDrag() {
    dragController.cancelDrag()
}
```

Call it before `onClose?()` in `.closeWindow`, in `.exitEditMode`, and before disabling drag for search. Task 16 already handles native drag-session end. In `LaunchPadWindowController.lifecycle(_:didTransitionTo:)`:

Add narrow boundaries whose production defaults preserve the existing main
queue and `NSWorkspace` behavior:

```swift
internal nonisolated(unsafe) var mainActorDispatcher:
    (@escaping @MainActor @Sendable () -> Void) -> Void = { operation in
    DispatchQueue.main.async(execute: operation)
}

internal var applicationURLProvider: (String) -> URL? = {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
}

internal var applicationOpener: (URL) -> Void = { url in
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(
        at: url,
        configuration: configuration
    )
}
```

Replace the outer `DispatchQueue.main.async` in all three nonisolated delegate
entries (`didTransitionTo`, `shouldLaunchApp`, and
`lifecycleRequestsLaunchAnimation`) with `mainActorDispatcher`. The application
branch resolves through `applicationURLProvider` and calls
`applicationOpener`; it never reaches either system API from a unit test.
Then apply the closing/hidden behavior:

```swift
case .closing:
    self.viewController.cancelActiveDrag()
    self.hideWindowAnimated()
case .hidden:
    self.viewController.cancelActiveDrag()
    self.window?.orderOut(nil)
    self.viewController.loadData()
```

Add tests for accepted drop, rejected drop/session end, explicit cancel, ESC edit exit, normal ESC close, search activation, `.closing` and `.hidden`; all assert timer actions empty, preview cleared and `session == nil`.

- [x] **Step 14: Run all folder/drag suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DragControllerTests|CollectionViewDragTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|AppIconCellTests|FolderOverlayViewTests|FolderOverlayViewPagingTests|FolderCellTests|FolderControllerTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests|TransientMessageViewTests'
! rg -n 'Task\.sleep|RunLoop\.main\.run|flushMainQueue|pumpRunloopBriefly' \
  Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift
! rg -n 'NSWorkspace\.shared\.(urlForApplication|openApplication)' \
  Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift
```

Expected: PASS; folder capacity follows the real clip height, open/reload/resize
repaginate and clamp, child before/after/empty and item 36 use stable IDs,
stale negative/out-of-range child paths reject with zero callback, exterior
drop reaches the grid resolver, safe delete has a real edit control, failure
reloads and returns false, and every lifecycle exit clears session/timer/preview.
The retained overlay delegate handles source, validation, acceptance and
drag-ended wiring; disabled, absent-folder, nil/malformed/mismatched pasteboard,
missing session, wrong type/kind/parent and stale-child inputs all reject with
zero callback. Both window-test scans print nothing: all former fixed waits are
event/boundary driven and application launch is fully injected.

- [x] **Step 15: Commit behavior and run aggregate review**

```bash
git add Sources/LaunchPad/Views/FolderOverlayView.swift \
  Sources/LaunchPad/Views/FolderCell.swift \
  Sources/LaunchPad/Views/AppIconCell.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Controllers/FolderController.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/App/LaunchPadWindowController.swift \
  Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift \
  Tests/LaunchPadTests/Views/FolderOverlayViewPagingTests.swift \
  Tests/LaunchPadTests/Views/FolderCellTests.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Controllers/FolderControllerTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift
git commit -m "feat: support responsive folder drag and safe delete"
```

Review the external-click fixture commit, both production-empty migration commits, each behavior commit and the full Task 19 base..head separately. Record 47 mapping checks, exact focused counts, static output and aggregate command in `.superpowers/sdd/task-19-review.md`.

---

### Task 20: Refresh Loaded UI After Scanning With Target-display Capacity

**Files:**
- Create: `Sources/LaunchPad/Services/ScanBatch.swift`
- Modify: `Sources/LaunchPad/Services/AppScanner.swift:5-182`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:14-83,292-368`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:143-160`
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift`
- Create: `Tests/LaunchPadTests/Storage/StorageManagerScanBatchTests.swift`
- Modify: `Tests/LaunchPadTests/Services/AppScannerTests.swift:220-450`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift:13-107,370-480,554-566`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Integration/IntegrationTests.swift`

**Interfaces:**
- Consumes: Task 1 `GridLayoutCalculator.calculate(viewportSize:)` and Task 5's viewport-derived projection.
- Produces: narrow `ScanBatchWriting`, one `BEGIN IMMEDIATE` scan transaction,
  observable `ScanSyncResult`, target-display clip capacity, and
  reload-only-when-loaded behavior.
- Preserves: display changes after the scan remain view projection only and never repaginate storage.
- Corrects: incremental diff reads `PersistedLayoutSnapshot.allItems` inside the
  transaction; `fetchAllItems(parentId: nil)` returns only root pages and must
  never again be used as the installed-app set.

- [x] **Step 1: Replace constant assertions with scan data-flow RED tests**

Replace scan tests that inspect unrelated `ItemWriting` calls with one narrow
writer double. `DataStoring` does not inherit `ScanBatchWriting`:

```swift
private final class RecordingScanBatchWriter:
    ScanBatchWriting,
    @unchecked Sendable
{
    var result = ScanSyncResult()
    var error: Error?
    var onSynchronize: (@Sendable () -> Void)?
    private(set) var receivedApps: [[ScannedApp]] = []
    private(set) var receivedCapacities: [Int] = []

    func synchronizeInstalledApps(
        _ apps: [ScannedApp],
        initialPageCapacity: Int
    ) throws -> ScanSyncResult {
        receivedApps.append(apps)
        receivedCapacities.append(initialPageCapacity)
        if let error { throw error }
        onSynchronize?()
        return result
    }
}

private func makeFileSystemWithApps(count: Int) -> MockFileSystemService {
    let fileSystem = MockFileSystemService()
    let root = URL(fileURLWithPath: "/Applications")
    let urls = (0..<count).map { root.appendingPathComponent("App\($0).app") }
    fileSystem.directoryContentsMap[root] = urls
    for (index, url) in urls.enumerated() {
        fileSystem.bundleInfos[url] = [
            "CFBundleName": "App \(index)",
            "CFBundleIdentifier": "com.test.app\(index)",
        ]
    }
    return fileSystem
}
```

Delete the private no-op `MockFileSystemService` in `AppDelegateTests` and use
the existing reference mock from `TestHelpers/MockProtocols.swift`. The
capacity test injects the full borderless window content size `1440x598`; the
shared VC geometry removes 102pt and sends the resulting 7x4 capacity:

```swift
@Test("首次扫描使用目标显示器真实容量")
func initialScanUsesTargetViewportCapacity() throws {
    let writer = RecordingScanBatchWriter()
    let fileSystem = makeFileSystemWithApps(count: 29)
    let sut = makeDelegate()
    sut.scanBatchWriter = writer
    sut.appScanner = AppScanner(
        fileSystemService: fileSystem,
        excludedBundleIds: []
    )
    sut.targetWindowContentSizeProvider = {
        CGSize(width: 1440, height: 598)
    }

    sut.performInitialScan()

    #expect(writer.receivedApps.count == 1)
    #expect(writer.receivedApps.first?.count == 29)
    #expect(writer.receivedCapacities == [28])
}
```

Add exact loaded/unloaded and failure tests; they call the real AppDelegate scan
entry rather than the writer directly:

```swift
@Test("成功扫描只刷新已加载 VC 一次")
func successfulScanReloadsOnlyLoadedViewController() throws {
    let sut = makeDelegate()
    let writer = RecordingScanBatchWriter()
    sut.scanBatchWriter = writer
    sut.appScanner = AppScanner(
        fileSystemService: makeFileSystemWithApps(count: 1),
        excludedBundleIds: []
    )
    let viewController = try makeViewController()
    sut.viewController = viewController
    var reloads = 0
    sut.viewControllerReloader = { _ in reloads += 1 }

    sut.performInitialScan()
    #expect(!viewController.isViewLoaded)
    #expect(reloads == 0)

    _ = viewController.view
    sut.performIncrementalScan()
    #expect(reloads == 1)
}

@Test("批事务失败不刷新并只记录固定分类")
func scanBatchFailureKeepsLoadedUIAndLogs() throws {
    let sut = makeDelegate()
    let writer = RecordingScanBatchWriter()
    writer.error = TestError.generic
    sut.scanBatchWriter = writer
    sut.appScanner = AppScanner(
        fileSystemService: makeFileSystemWithApps(count: 1),
        excludedBundleIds: []
    )
    let viewController = try makeViewController()
    _ = viewController.view
    sut.viewController = viewController
    var reloads = 0
    var categories: [String] = []
    sut.viewControllerReloader = { _ in reloads += 1 }
    sut.scanFailureLogger = { categories.append($0) }

    sut.performInitialScan()

    #expect(reloads == 0)
    #expect(categories == ["scan-batch-failed"])
}
```

Duplicate these assertions through `performIncrementalScan` so the FileWatcher
entry has the same success/failure gate. Before Task 21 replaces the real
FSEvents test, update the existing
`setupFileWatcher_triggersIncrementalScan` test to install the new required
writer and assert the callback, rather than leaving the IUO nil or using a
no-op assertion:

```swift
private enum AppDelegateTestTimeout: Error { case elapsed }

private func withAppDelegateTestTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await ContinuousClock().sleep(for: duration)
            throw AppDelegateTestTimeout.elapsed
        }
        guard let result = try await group.next() else {
            throw AppDelegateTestTimeout.elapsed
        }
        group.cancelAll()
        return result
    }
}

@Test("setupFileWatcher：文件变更触发一次批量增量扫描")
func setupFileWatcher_triggersIncrementalScan() async throws {
    let sut = makeDelegate()
    let writer = RecordingScanBatchWriter()
    let events = AsyncStream<Void>.makeStream()
    writer.onSynchronize = { events.continuation.yield() }
    defer { events.continuation.finish() }
    sut.scanBatchWriter = writer
    sut.appScanner = AppScanner(
        fileSystemService: MockFileSystemService(),
        excludedBundleIds: []
    )

    let dir = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("launchpad_fw_\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        atPath: dir,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(atPath: dir) }

    sut.watchedPaths = [dir]
    sut.fileWatcherFactory = { FileWatcher(debounceInterval: 0.1) }
    sut.setupFileWatcher()
    try "x".write(
        toFile: (dir as NSString).appendingPathComponent("probe.txt"),
        atomically: true,
        encoding: .utf8
    )

    let received = try await withAppDelegateTestTimeout(.seconds(10)) {
        for await _ in events.stream { return true }
        return false
    }
    #expect(received)
    #expect(writer.receivedApps.count == 1)
}
```

App scanner branch tests retain every
directory/read branch: directory error continues, non-app URL, missing plist,
missing/empty name, `LSUIElement == true`, missing bundle ID, excluded bundle,
valid bundle, and duplicate bundle IDs across directories preserving the first
stable occurrence without `Dictionary(uniqueKeysWithValues:)`.

Add SQLite-backed tests in `StorageManagerScanBatchTests.swift`; these test the
transaction rather than a mock:

```swift
@Test("首次扫描中途失败继续尝试后页但整个批次回滚")
func initialFailureContinuesAndRollsBackEverything() throws {
    let script = SQLiteFaultScript()
    let sut = try StorageManager(
        dbPath: ":memory:",
        schemaSetup: { Schema.setupSchema(db: $0) },
        faultInjector: script.result(for:)
    )
    script.failNext(
        .step(.insertAppMetadata),
        code: SQLITE_CONSTRAINT
    )
    let apps = [
        ScannedApp(name: "A", bundleId: "com.test.a", path: "/A.app"),
        ScannedApp(name: "B", bundleId: "com.test.b", path: "/B.app"),
    ]

    do {
        _ = try sut.synchronizeInstalledApps(
            apps,
            initialPageCapacity: 1
        )
        Issue.record("expected ScanBatchWriteFailure")
    } catch let failure as ScanBatchWriteFailure {
        #expect(failure.result.attemptedWriteCount == 4)
        #expect(failure.result.successfulWriteCount == 3)
        #expect(failure.result.failedWriteCount == 1)
    }
    #expect(try sut.persistedLayoutSnapshot().allItems.isEmpty)
}

@Test("增量 update 失败后仍尝试 insert/delete 且完整回滚")
func incrementalFailureContinuesAndRollsBackEverything() throws {
    let (sut, script) = try makeSeededScanStorage()
    let before = try sut.persistedLayoutSnapshot()
    script.failNext(.step(.updateAppMetadata), code: SQLITE_IOERR)
    let apps = [
        ScannedApp(
            name: "A changed",
            bundleId: "com.test.a",
            path: "/A2.app"
        ),
        ScannedApp(name: "C", bundleId: "com.test.c", path: "/C.app"),
    ]

    do {
        _ = try sut.synchronizeInstalledApps(
            apps,
            initialPageCapacity: 28
        )
        Issue.record("expected ScanBatchWriteFailure")
    } catch let failure as ScanBatchWriteFailure {
        #expect(failure.result.failedWriteCount == 1)
        #expect(failure.result.successfulWriteCount == 2)
    }
    #expect(try sut.persistedLayoutSnapshot() == before)
}

@Test("零扫描结果仍原子建立唯一空页")
func emptyInitialScanCreatesOnePage() throws {
    let sut = try StorageManager(dbPath: ":memory:")
    let result = try sut.synchronizeInstalledApps(
        [],
        initialPageCapacity: 28
    )
    let snapshot = try sut.persistedLayoutSnapshot()

    #expect(result.isSuccessful)
    #expect(snapshot.pages.count == 1)
    #expect(snapshot.pageChildren[snapshot.pages[0].id] == [])
}

@Test("真实 RAISE(ROLLBACK) 后立即停止且不产生 autocommit 残留")
func automaticSQLiteRollbackStopsFurtherScanWrites() throws {
    let sut = try StorageManager(
        dbPath: ":memory:",
        schemaSetup: { database in
            Schema.setupSchema(db: database)
            let sql = """
                CREATE TRIGGER abort_test_b
                BEFORE INSERT ON apps
                WHEN NEW.bundle_id = 'com.test.b'
                BEGIN
                    SELECT RAISE(ROLLBACK, 'forced automatic rollback');
                END
                """
            #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        }
    )
    let scanned = [
        ScannedApp(name: "A", bundleId: "com.test.a", path: "/A.app"),
        ScannedApp(name: "B", bundleId: "com.test.b", path: "/B.app"),
        ScannedApp(name: "C", bundleId: "com.test.c", path: "/C.app"),
    ]

    do {
        _ = try sut.synchronizeInstalledApps(
            scanned,
            initialPageCapacity: 3
        )
        Issue.record("expected ScanBatchWriteFailure")
    } catch let failure as ScanBatchWriteFailure {
        #expect(failure.result.attemptedWriteCount == 3)
        #expect(failure.result.successfulWriteCount == 2)
        #expect(failure.result.failedWriteCount == 1)
    }
    #expect(try sut.persistedLayoutSnapshot().allItems.isEmpty)

    let retry = try sut.synchronizeInstalledApps(
        [scanned[0], scanned[2]],
        initialPageCapacity: 3
    )
    #expect(retry.isSuccessful)
    let bundleIDs = try sut.persistedLayoutSnapshot().allItems.compactMap {
        $0.app?.bundleId
    }
    #expect(Set(bundleIDs) == ["com.test.a", "com.test.c"])
}

@Test("增量删除重排子项、清理全部空页并始终保留一页")
func incrementalScanRestoresDensePageInvariants() throws {
    let sut = try StorageManager(dbPath: ":memory:")
    let page1 = try sut.insertItem(TestDataFactory.makePageItem(
        type: .page,
        ordering: 0
    ))
    let page2 = try sut.insertItem(TestDataFactory.makePageItem(
        type: .page,
        ordering: 1
    ))
    let page3 = try sut.insertItem(TestDataFactory.makePageItem(
        type: .page,
        ordering: 2
    ))
    func insertApp(
        _ name: String,
        bundleID: String,
        parentID: Int64,
        ordering: Int
    ) throws {
        _ = try sut.insertItem(TestDataFactory.makePageItem(
            type: .app,
            ordering: ordering,
            parentId: parentID,
            app: TestDataFactory.makeAppInfo(
                title: name,
                bundleId: bundleID,
                path: "/\(name).app"
            )
        ))
    }
    try insertApp("A", bundleID: "com.test.a", parentID: page1, ordering: 0)
    try insertApp("B", bundleID: "com.test.b", parentID: page2, ordering: 0)
    try insertApp("C", bundleID: "com.test.c", parentID: page2, ordering: 1)
    try insertApp("D", bundleID: "com.test.d", parentID: page3, ordering: 0)

    _ = try sut.synchronizeInstalledApps(
        [
            ScannedApp(name: "C", bundleId: "com.test.c", path: "/C.app"),
        ],
        initialPageCapacity: 28
    )
    var snapshot = try sut.persistedLayoutSnapshot()
    #expect(snapshot.pages.map(\.ordering) == [0])
    #expect(snapshot.pageChildren[snapshot.pages[0].id]?.map(\.ordering) == [0])
    #expect(snapshot.pageChildren[snapshot.pages[0].id]?.first?.app?.bundleId
        == "com.test.c")

    _ = try sut.synchronizeInstalledApps([], initialPageCapacity: 28)
    snapshot = try sut.persistedLayoutSnapshot()
    #expect(snapshot.pages.count == 1)
    #expect(snapshot.pages[0].ordering == 0)
    #expect(snapshot.pageChildren[snapshot.pages[0].id] == [])
}
```

`makeSeededScanStorage()` creates one page with `A` and `B`, returning a
faultable manager and its script. Add direct BEGIN/read/prepare/bind/step/
changes/COMMIT fault cases, a rollback-failure case that asserts the original
`SQLiteRollbackFailure` plus subsequent `storageUnavailable`, and a file-backed
reopen case proving no partial scan rows survive. Add success cases for invalid
capacity, empty/one/multiple pages, page failure continuing to the next page,
app failure continuing within and across pages, nonempty root without a page,
new/changed/unchanged/removed apps, malformed existing app, duplicate existing
and scanned bundle IDs, and no-op sync. The real `RAISE(ROLLBACK)` test is not
replaced by a fault injector: it proves `sqlite3_get_autocommit` stops further
writes after SQLite itself ends the transaction. Every failure compares the complete
`PersistedLayoutSnapshot`, not only thrown error type.

Update `IntegrationTests.swift` so the old empty-scan assertion expects exactly
one empty root page. Replace all four old `firstLaunchPaginate` calls with
`synchronizeInstalledApps`. Add a real incremental round trip with existing
page + A + B, scanned A-changed + C, and assert A updates, B is deleted, C is
inserted and no duplicate-bundle failure occurs; this prevents the old
root-pages-only diff from returning.

- [x] **Step 2: Run scan suites and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManagerScanBatchTests|AppScannerTests|AppDelegateTests|LaunchPadViewControllerTests|IntegrationTests'
```

Expected: compile RED for `ScanBatchWriting`, storage batch transaction and
shared window-to-grid viewport geometry. Verify all five named suites are
reported; zero-match success is a failure.

- [x] **Step 3: Add the narrow scan batch contract**

Create `ScanBatch.swift`. It is internal to the LaunchPad target; controller and
protocol modules do not receive a general transaction closure:

```swift
import Foundation
import LaunchPadProtocols

struct ScanSyncResult: Sendable, Equatable {
    private(set) var attemptedWriteCount = 0
    private(set) var successfulWriteCount = 0
    private(set) var failedWriteCount = 0

    var isSuccessful: Bool { failedWriteCount == 0 }

    mutating func recordSuccess() {
        attemptedWriteCount += 1
        successfulWriteCount += 1
    }

    mutating func recordFailure() {
        attemptedWriteCount += 1
        failedWriteCount += 1
    }
}

struct ScanBatchWriteFailure: Error {
    let result: ScanSyncResult
    let primaryError: any Error
}

enum ScanBatchError: Error, Equatable {
    case invalidPageCapacity
    case missingPage
}

protocol ScanBatchWriting: Sendable {
    func synchronizeInstalledApps(
        _ apps: [ScannedApp],
        initialPageCapacity: Int
    ) throws -> ScanSyncResult
}
```

Delete `AppScanner.firstLaunchPaginate` and `incrementalSync`; the scanner now
only discovers `ScannedApp` values. Replace its trapping dictionary creation
with a stable first-wins helper used before returning scan results:

```swift
private func deduplicated(_ apps: [ScannedApp]) -> [ScannedApp] {
    var seen = Set<String>()
    return apps.filter { seen.insert($0.bundleId).inserted }
}
```

Call `deduplicated(apps)` at the end of `scanDirectories`. Directory errors
continue to the next directory exactly as before; write continuation moves into
the single repository transaction in Step 4.

- [x] **Step 4: Implement the single-transaction scan repository**

Make `StorageManager` conform to `ScanBatchWriting`. Add complete construction,
deduplication and per-operation accounting helpers:

```swift
private func makeScanPage(ordering: Int) -> PageItem {
    PageItem(
        id: 0,
        uuid: UUID().uuidString,
        type: .page,
        ordering: ordering,
        parentId: nil,
        app: nil,
        group: nil
    )
}

private func makeScanApp(
    _ scanned: ScannedApp,
    parentID: Int64,
    ordering: Int
) -> PageItem {
    PageItem(
        id: 0,
        uuid: UUID().uuidString,
        type: .app,
        ordering: ordering,
        parentId: parentID,
        app: AppInfo(
            id: 0,
            title: scanned.name,
            bundleId: scanned.bundleId,
            path: scanned.path,
            storeId: nil,
            category: nil
        ),
        group: nil
    )
}

private func deduplicateScannedApps(
    _ scanned: [ScannedApp]
) -> [ScannedApp] {
    var seen = Set<String>()
    return scanned.filter { seen.insert($0.bundleId).inserted }
}

private func attemptScanWrite<T>(
    database: OpaquePointer,
    _ result: inout ScanSyncResult,
    firstError: inout (any Error)?,
    _ body: () throws -> T
) throws -> T? {
    do {
        let value = try body()
        result.recordSuccess()
        return value
    } catch {
        result.recordFailure()
        if firstError == nil { firstError = error }
        // Some SQLite failures automatically roll the transaction back. Once
        // autocommit resumes, continuing would turn later writes into partial
        // commits that the outer ROLLBACK cannot undo.
        guard sqlite3_get_autocommit(database) == 0 else {
            throw ScanBatchWriteFailure(
                result: result,
                primaryError: firstError ?? error
            )
        }
        return nil
    }
}
```

Use the complete incremental diff below. It deliberately reads
`snapshot.allItems`, not the root-only result of
`fetchAllItems(parentId: nil)`:

```swift
private func executeIncrementalScan(
    _ scanned: [ScannedApp],
    snapshot: PersistedLayoutSnapshot,
    database: OpaquePointer,
    result: inout ScanSyncResult,
    firstError: inout (any Error)?
) throws {
    guard let lastPage = snapshot.pages.last else {
        throw ScanBatchError.missingPage
    }
    let existingApps = snapshot.allItems.filter { $0.type == .app }
    let existingByBundle = Dictionary(
        existingApps.compactMap { item in
            item.app.map { ($0.bundleId, item) }
        },
        uniquingKeysWith: { first, _ in first }
    )
    let scannedByBundle = Dictionary(
        scanned.map { ($0.bundleId, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    var ordering = snapshot.pageChildren[lastPage.id]?.count ?? 0

    for app in scanned where existingByBundle[app.bundleId] == nil {
        if try attemptScanWrite(
            database: database,
            &result,
            firstError: &firstError,
            {
                try insertItemStatement(
                    makeScanApp(
                        app,
                        parentID: lastPage.id,
                        ordering: ordering
                    ),
                    database: database
                )
            }
        ) != nil {
            ordering += 1
        }
    }

    for item in existingApps {
        guard let old = item.app,
              let fresh = scannedByBundle[old.bundleId],
              old.title != fresh.name || old.path != fresh.path else {
            continue
        }
        let updatedInfo = AppInfo(
            id: old.id,
            title: fresh.name,
            bundleId: old.bundleId,
            path: fresh.path,
            storeId: old.storeId,
            category: old.category
        )
        let updated = PageItem(
            id: item.id,
            uuid: item.uuid,
            type: item.type,
            ordering: item.ordering,
            parentId: item.parentId,
            app: updatedInfo,
            group: item.group
        )
        _ = try attemptScanWrite(
            database: database,
            &result,
            firstError: &firstError
        ) {
            try updateItemStatement(updated, database: database)
        }
    }

    for item in existingApps {
        guard let bundleID = item.app?.bundleId,
              scannedByBundle[bundleID] == nil else { continue }
        _ = try attemptScanWrite(
            database: database,
            &result,
            firstError: &firstError
        ) {
            try deleteItemStatement(id: item.id, database: database)
        }
    }
}

private func normalizeScanLayout(
    database: OpaquePointer,
    result: inout ScanSyncResult,
    firstError: inout (any Error)?
) throws {
    let snapshot = try readPersistedLayoutSnapshot(database: database)
    var pages = snapshot.pages.sorted {
        $0.ordering == $1.ordering
            ? $0.id < $1.id
            : $0.ordering < $1.ordering
    }

    for page in pages {
        let children = (snapshot.pageChildren[page.id] ?? []).sorted {
            $0.ordering == $1.ordering
                ? $0.id < $1.id
                : $0.ordering < $1.ordering
        }
        for (ordering, item) in children.enumerated()
        where item.parentId != page.id || item.ordering != ordering {
            _ = try attemptScanWrite(
                database: database,
                &result,
                firstError: &firstError
            ) {
                try updateParentAndOrdering(
                    itemID: item.id,
                    parentID: page.id,
                    ordering: ordering,
                    database: database
                )
            }
        }
    }

    let hasNonemptyPage = pages.contains {
        !(snapshot.pageChildren[$0.id] ?? []).isEmpty
    }
    let preservedEmptyPageID = hasNonemptyPage ? nil : pages.first?.id
    var deletedPageIDs = Set<Int64>()
    for page in pages
    where (snapshot.pageChildren[page.id] ?? []).isEmpty
        && page.id != preservedEmptyPageID {
        let deleted = try attemptScanWrite(
            database: database,
            &result,
            firstError: &firstError
        ) {
            try deleteLayoutItem(
                itemID: page.id,
                database: database
            )
        }
        if deleted != nil { deletedPageIDs.insert(page.id) }
    }
    pages.removeAll { deletedPageIDs.contains($0.id) }

    for (ordering, page) in pages.enumerated()
    where page.ordering != ordering {
        _ = try attemptScanWrite(
            database: database,
            &result,
            firstError: &firstError
        ) {
            try updatePageOrdering(
                pageID: page.id,
                ordering: ordering,
                database: database
            )
        }
    }
}
```

The internal protocol witness runs every SQL write under one immediate transaction.
An individual failure is counted and later independent operations are still
attempted, but the first error is thrown at the end so `runTransaction` rolls
the whole batch back. Rollback failure is rethrown unchanged so Task 12's
connection invalidation evidence remains valid:

```swift
func synchronizeInstalledApps(
    _ scanned: [ScannedApp],
    initialPageCapacity: Int
) throws -> ScanSyncResult {
    var observed = ScanSyncResult()
    do {
        return try withDatabase { database in
            try runTransaction(database: database, mode: .immediate) {
                let snapshot = try readPersistedLayoutSnapshot(
                    database: database
                )
                var firstError: (any Error)?
                let apps = deduplicateScannedApps(scanned)

                if snapshot.allItems.isEmpty {
                    guard initialPageCapacity > 0 else {
                        throw ScanBatchError.invalidPageCapacity
                    }
                    let sorted = apps.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name)
                            == .orderedAscending
                    }
                    let chunks: [[ScannedApp]] = sorted.isEmpty
                        ? [[]]
                        : stride(
                            from: 0,
                            to: sorted.count,
                            by: initialPageCapacity
                        ).map { start in
                            Array(sorted[start..<min(
                                start + initialPageCapacity,
                                sorted.count
                            )])
                        }

                    for (pageOrdering, chunk) in chunks.enumerated() {
                        guard let pageID = try attemptScanWrite(
                            database: database,
                            &observed,
                            firstError: &firstError,
                            {
                                try insertItemStatement(
                                    makeScanPage(ordering: pageOrdering),
                                    database: database
                                )
                            }
                        ) else { continue }
                        for (ordering, app) in chunk.enumerated() {
                            _ = try attemptScanWrite(
                                database: database,
                                &observed,
                                firstError: &firstError
                            ) {
                                try insertItemStatement(
                                    makeScanApp(
                                        app,
                                        parentID: pageID,
                                        ordering: ordering
                                    ),
                                    database: database
                                )
                            }
                        }
                    }
                } else {
                    try executeIncrementalScan(
                        apps,
                        snapshot: snapshot,
                        database: database,
                        result: &observed,
                        firstError: &firstError
                    )
                    try normalizeScanLayout(
                        database: database,
                        result: &observed,
                        firstError: &firstError
                    )
                }

                if let firstError {
                    throw ScanBatchWriteFailure(
                        result: observed,
                        primaryError: firstError
                    )
                }
                return observed
            }
        }
    } catch let failure as ScanBatchWriteFailure {
        throw failure
    } catch let rollbackFailure as SQLiteRollbackFailure {
        throw rollbackFailure
    } catch {
        observed.recordFailure()
        throw ScanBatchWriteFailure(
            result: observed,
            primaryError: error
        )
    }
}
```

- [x] **Step 5: Share actual grid chrome geometry and wire AppDelegate**

Replace the six VC constraint literals with named constants and use those same
constants in the helper that AppDelegate calls before calculating metrics:

```swift
nonisolated static let searchTop: CGFloat = 20
nonisolated static let searchHeight: CGFloat = 32
nonisolated static let searchToGrid: CGFloat = 12
nonisolated static let gridToPager: CGFloat = 8
nonisolated static let pagerHeight: CGFloat = 10
nonisolated static let pagerBottom: CGFloat = 20

nonisolated static var gridChromeHeight: CGFloat {
    searchTop + searchHeight + searchToGrid
        + gridToPager + pagerHeight + pagerBottom
}

nonisolated static func gridViewportSize(
    forWindowContentSize size: CGSize
) -> CGSize {
    let width = size.width.isFinite ? max(0, size.width) : 0
    let height = size.height.isFinite
        ? max(0, size.height - gridChromeHeight)
        : 0
    return CGSize(width: width, height: height)
}
```

The Auto Layout constraints use `Self.searchTop`, `Self.searchHeight`,
`Self.searchToGrid`, `Self.gridToPager`, `Self.pagerHeight` and
`Self.pagerBottom`; no duplicate literal remains. Add threshold tests for window
content heights `722/598/474/350/226`, which map to clip heights
`620/496/372/248/124` and rows `5/4/3/2/1`. For the first four thresholds,
`height.nextDown` must select one fewer row. Also assert nonfinite and negative
content sizes sanitize to finite nonnegative clip sizes.

```swift
@Test("窗口内容尺寸扣除 102pt chrome 后命中全部行阈值")
func windowContentSizeMapsToExactGridViewportThresholds() {
    let cases: [(windowHeight: CGFloat, clipHeight: CGFloat, rows: Int)] = [
        (722, 620, 5),
        (598, 496, 4),
        (474, 372, 3),
        (350, 248, 2),
        (226, 124, 1),
    ]

    #expect(LaunchPadViewController.gridChromeHeight == 102)
    for value in cases {
        let viewport = LaunchPadViewController.gridViewportSize(
            forWindowContentSize: CGSize(
                width: 1440,
                height: value.windowHeight
            )
        )
        #expect(viewport.height == value.clipHeight)
        #expect(GridLayoutCalculator.calculate(
            viewportSize: viewport
        ).rows == value.rows)
    }
    for value in cases.dropLast() {
        let viewport = LaunchPadViewController.gridViewportSize(
            forWindowContentSize: CGSize(
                width: 1440,
                height: value.windowHeight.nextDown
            )
        )
        #expect(GridLayoutCalculator.calculate(
            viewportSize: viewport
        ).rows == value.rows - 1)
    }
}

@Test("窗口尺寸异常值被规范为有限非负 grid viewport")
func invalidWindowContentSizeSanitizesGridViewport() {
    let viewport = LaunchPadViewController.gridViewportSize(
        forWindowContentSize: CGSize(width: .nan, height: -.infinity)
    )
    #expect(viewport.width == 0)
    #expect(viewport.height == 0)
    #expect(viewport.width.isFinite)
    #expect(viewport.height.isFinite)
}
```

Extend Task 18's storage installation to keep a third independently typed
reference to the same manager:

```swift
var scanBatchWriter: (any ScanBatchWriting)!

private func installStorage(_ manager: StorageManager) {
    storage = manager
    layoutMutator = manager
    scanBatchWriter = manager
}
```

Every recovery failure clears all three references. Add these AppDelegate
boundaries and the one shared scan flow:

```swift
var targetWindowContentSizeProvider: () -> CGSize = {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: {
        $0.frame.contains(mouse)
    }) ?? NSScreen.main
    return screen?.frame.size ?? CGSize(width: 1440, height: 900)
}

var viewControllerReloader: (LaunchPadViewController) -> Void = {
    $0.loadData()
}

var scanFailureLogger: (String) -> Void = {
    NSLog("[AppDelegate] %@", $0)
}

private func reloadLoadedViewControllerAfterScan() {
    mainAsyncRunner { [weak self] in
        guard let self,
              let viewController = self.viewController,
              viewController.isViewLoaded else { return }
        self.viewControllerReloader(viewController)
    }
}

private func performScan() {
    let directories = watchedPaths.map { URL(fileURLWithPath: $0) }
    let scanned = appScanner.scanDirectories(directories)
    let viewport = LaunchPadViewController.gridViewportSize(
        forWindowContentSize: targetWindowContentSizeProvider()
    )
    let capacity = GridLayoutCalculator.calculate(
        viewportSize: viewport
    ).itemsPerPage
    do {
        let result = try scanBatchWriter.synchronizeInstalledApps(
            scanned,
            initialPageCapacity: capacity
        )
        guard result.isSuccessful else {
            scanFailureLogger("scan-batch-failed")
            return
        }
        reloadLoadedViewControllerAfterScan()
    } catch {
        scanFailureLogger("scan-batch-failed")
    }
}

func performInitialScan() { performScan() }
func performIncrementalScan() { performScan() }
```

The logger never interpolates the underlying SQLite error. Display changes
after this initial normalization still only call Task 5 projection and perform
zero storage writes.

- [x] **Step 6: Run scan, viewport and controller regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'GridLayoutCalculatorTests|StorageManagerScanBatchTests|AppScannerTests|AppDelegateTests|LaunchPadViewControllerTests|IntegrationTests'
```

- [x] **Step 7: Run every storage and integration regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainStateTests|IntegrationTests'
```

Expected: every batch failure preserves the complete snapshot, the
rollback-failure case invalidates its connection, file-backed reopen contains no
partial scan rows, zero apps creates one empty page, and real incremental sync
updates/deletes/inserts from `allItems`.

- [x] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Services/ScanBatch.swift \
  Sources/LaunchPad/Services/AppScanner.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/Storage/StorageManager.swift \
  Tests/LaunchPadTests/Storage/StorageManagerScanBatchTests.swift \
  Tests/LaunchPadTests/Services/AppScannerTests.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Integration/IntegrationTests.swift
git commit -m "fix: commit app scans atomically"
```

---

### Task 21: Isolate System Side Effects and Close Every Process-global Resource

**Files:**
- Modify: `Sources/LaunchPad/Services/FileWatcher.swift:5-129`
- Modify: `Sources/LaunchPad/Utilities/AccessibilityObservers.swift`
- Modify: `Sources/LaunchPad/App/LaunchPadWindowController.swift`
- Modify: `Sources/LaunchPad/App/HotkeyManager.swift:22-183`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:14-83,174-218,292-300,378`
- Modify: `Tests/LaunchPadTests/Services/FileWatcherTests.swift`
- Modify: `Tests/LaunchPadTests/Utilities/AccessibilitySettingsTests.swift`
- Modify: `Tests/LaunchPadTests/Utilities/AccessibilityObserversTests.swift`
- Create: `Tests/LaunchPadTests/Services/FileWatcherLifecycleTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift`
- Create: `docs/superpowers/reports/2026-07-21-task-21-system-boundary-migration.md`
- Create: `.superpowers/sdd/task-21-migration.md`

**Interfaces:**
- Consumes: Task 3R-A's MainActor `Scheduler`, Task 3R-B/8's hotkey/local-monitor boundaries and Task 3R-C's injected read-only Dock exclusion parser.
- Produces: injected event stream, accessibility source/observer and status item boundaries plus idempotent shutdown.
- Produces: `FileWatcher.start(...) -> Bool`; AppDelegate must expose and handle backend startup failure.
- Keeps one non-skipped host integration test against a UUID temporary directory; all orchestration/lifecycle tests use injected backends and never touch user paths.
- Migrates: FileWatcher 14 + Accessibility 16 = 30 old methods one-to-one with zero legacy framework symbols.

- [x] **Step 1: Capture the 30-test baseline and qualified mapping inventory**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(FileWatcherTests|AccessibilitySettingsTests|AccessibilityObserverTests)/' | \
  LC_ALL=C sort > /tmp/task-21-system-boundary-actual-before.txt
test "$(wc -l < /tmp/task-21-system-boundary-actual-before.txt | tr -d ' ')" -eq 30
test "$(LC_ALL=C sort -u /tmp/task-21-system-boundary-actual-before.txt | wc -l | tr -d ' ')" -eq 30
rg -n '^\s*func test' \
  Tests/LaunchPadTests/Services/FileWatcherTests.swift \
  Tests/LaunchPadTests/Utilities/AccessibilitySettingsTests.swift
```

Expected: FileWatcher has 14 old methods and Accessibility has 16. The migration report must list qualified old/new IDs because both groups contain an `init_doesNotCrash` name. Required new FileWatcher IDs are `init_doesNotCrash`, `init_customDebounceInterval`, `stop_withoutStart_doesNotCrash`, `start_emptyPaths_doesNotCrash`, `start_thenStop_releasesProperly`, `deinit_afterStart_doesNotCrash`, `start_withMultiplePaths_doesNotCrash`, `start_stopThenStartAgain_doesNotCrash`, `init_zeroDebounceInterval_doesNotCrash`, `deinit_withoutStart_isSafe`, `start_realFileChange_triggersOnChange`, `start_streamCreationFails_doesNotCrash`, `start_streamCreationFails_thenStop_isSafe`, `handleEvents_clientCallBackInfoNil_returnsEarly`. Required Accessibility IDs are `current_returnsValidSettings`, `current_reduceMotion_isBool`, `current_reduceTransparency_isBool`, `current_increaseContrast_isBool`, `init_withExplicitValues`, `init_allFalse`, `init_allTrue`, `animationFallback_reduceMotion_returnsFadeOrInstant`, `animationFallback_normalMotion_returnsSpring`, `backgroundMaterial_reduceTransparency_returnsSolidColor`, `backgroundMaterial_normalTransparency_returnsHudWindow`, `contrastFallback_increaseContrast_returnsHighContrast`, `contrastFallback_normalContrast_returnsSystemColors`, `init_doesNotCrash`, `stop_multipleCalls_doesNotCrash`, `deinit_doesNotCrash`.

- [x] **Step 2: Add resource lifecycle and side-effect isolation RED tests**

Add deterministic lifecycle tests in new Swift Testing files before production
changes. Put the shared `MockFileEventStream` below in
`Tests/LaunchPadTests/TestHelpers/MockProtocols.swift` so the lifecycle,
legacy FileWatcher and AppDelegate fixtures consume one backend double. Keep
the existing 14-method file intact until the production lifecycle is green,
then migrate it in Step 9. Add tests for all branches:

```swift
final class MockFileEventStream: FileEventStreaming, @unchecked Sendable {
    var startResult = true
    private(set) var startedPaths: [[String]] = []
    private(set) var stopCallCount = 0
    private var onEvents: (@Sendable () -> Void)?

    func start(
        paths: [String],
        onEvents: @escaping @Sendable () -> Void
    ) -> Bool {
        startedPaths.append(paths)
        guard startResult else { return false }
        self.onEvents = onEvents
        return true
    }

    func stop() {
        stopCallCount += 1
        onEvents = nil
    }

    func emit() { onEvents?() }
}

@Test("生产 FSEvent backend 启动失败不调用 Stop 但完整释放")
func systemBackendStartFailureSkipsStopAndReleasesEverything() {
    let fakeStream: FSEventStreamRef = unsafeBitCast(
        UInt(1),
        to: FSEventStreamRef.self
    )
    var stopCalls = 0
    var invalidateCalls = 0
    var releaseCalls = 0
    let functions = FSEventStreamFunctions(
        create: { _, _, _, _, _, _ in fakeStream },
        setDispatchQueue: { _, _ in },
        start: { _ in false },
        stop: { _ in stopCalls += 1 },
        invalidate: { _ in invalidateCalls += 1 },
        release: { _ in releaseCalls += 1 }
    )
    let sut = SystemFileEventStream(functions: functions)

    #expect(!sut.start(paths: ["/Applications"]) {})
    #expect(stopCalls == 0)
    #expect(invalidateCalls == 1)
    #expect(releaseCalls == 1)
}

@MainActor
final class MockStatusItem: StatusItemManaging {
    var button: NSStatusBarButton? = nil
    var menu: NSMenu?
}
```

Use concrete lifecycle assertions rather than no-crash tests:

```swift
@Test("空路径不启动；重复启动先停止旧 backend")
@MainActor
func startEmptyAndRestartBalanceBackend() {
    let backend = MockFileEventStream()
    let scheduler = MockScheduler()
    let sut = FileWatcher(backend: backend, scheduler: scheduler)

    sut.start(paths: []) {}
    #expect(backend.startedPaths.isEmpty)
    #expect(backend.stopCallCount == 0)

    sut.start(paths: ["/Applications"]) {}
    sut.start(paths: ["/System/Applications"]) {}
    #expect(backend.startedPaths == [
        ["/Applications"], ["/System/Applications"],
    ])
    #expect(backend.stopCallCount == 1)
}

@Test("stop 取消 debounce、停止 backend 并丢弃回调")
@MainActor
func stopDropsPendingCallback() async {
    let backend = MockFileEventStream()
    let scheduler = MockScheduler()
    let sut = FileWatcher(backend: backend, scheduler: scheduler)
    var changes = 0
    sut.start(paths: ["/Applications"]) { changes += 1 }
    backend.emit()
    await Task.yield()

    sut.stop()
    scheduler.advance(by: 3)

    #expect(changes == 0)
    #expect(scheduler.scheduledActions.isEmpty)
    #expect(backend.stopCallCount == 1)
}

@Test("活动 watcher 析构只停止 backend 一次")
@MainActor
func deinitStopsBackendExactlyOnce() {
    let backend = MockFileEventStream()
    var sut: FileWatcher? = FileWatcher(
        backend: backend,
        scheduler: MockScheduler()
    )
    sut?.start(paths: ["/Applications"]) {}

    sut = nil

    #expect(backend.stopCallCount == 1)
}

@Test("local monitor 重复注册与注销各只作用一次")
func localMonitorLifecycleIsIdempotent() {
    let manager = HotkeyManager()
    let token = NSObject()
    var installs = 0
    var removals = 0
    manager.localMonitorInstaller = { _ in
        installs += 1
        return token
    }
    manager.localMonitorRemover = { received in
        #expect(received as AnyObject === token)
        removals += 1
    }

    manager.registerLocalMonitor()
    manager.registerLocalMonitor()
    manager.unregisterLocalMonitor()
    manager.unregisterLocalMonitor()

    #expect(installs == 1)
    #expect(removals == 1)
}
```

Add corresponding global-tap counter tests after Step 6's injection API and
AppDelegate shutdown counter tests after Step 7. Each asserts exact add/remove,
enable/disable and context-presence transitions; no test calls real FSEvents,
`NSStatusBar.system`, `AXIsProcessTrusted`, `SMAppService`, `NSWorkspace.open`
or a real event tap.

The watcher burst test uses `MockScheduler.advance(by:)`, never `wait(for:timeout:)`:

```swift
@Test("文件事件 burst 只触发最后一次防抖回调")
@MainActor
func eventBurstFiresLatestOnce() async {
    let backend = MockFileEventStream()
    let scheduler = MockScheduler()
    let sut = FileWatcher(backend: backend, scheduler: scheduler)
    var changes = 0
    sut.start(paths: ["/Applications"]) { changes += 1 }

    backend.emit()
    backend.emit()
    await Task.yield()
    scheduler.advance(by: 1.99)
    #expect(changes == 0)
    scheduler.advance(by: 0.01)
    #expect(changes == 1)
}
```

- [x] **Step 3: Run every old and new focused suite and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppScannerTests|FileWatcherTests|FileWatcherLifecycleTests|AccessibilitySettingsTests|AccessibilityObserverTests|AccessibilityObserversTests|HotkeyManagerTests|AppDelegateTests'
```

Expected: the newly created lifecycle/observer tests are discovered and fail
for missing production interfaces; a zero-match filter or a run that exercises
only the four pre-existing suites is not RED evidence.

- [x] **Step 4: Verify the pre-landed Dock exclusion boundary**

Task 3R-C owns this implementation and its focused/full evidence. Do not
duplicate or redesign it in Task 21. Verify the boundary remains intact after
Tasks 4-20:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter AppScannerTests

! rg -n "backup_test|createDirectory|removeItem|moveItem|data.write|try!" \
  Tests/LaunchPadTests/Services/AppScannerTests.swift
rg -n "ExcludedDataProvider|systemExcludedData|parseExcludedBundleIDs" \
  Sources/LaunchPad/Services/AppScanner.swift
```

Expected: all AppScanner tests pass using explicit exclusions or in-memory
data, the test file contains no Dock path mutation, and production retains one
read-only system provider plus the pure parser. Any regression is fixed in the
Task 21 behavior commit; there is no separate AppScanner commit in this task.

- [x] **Step 5: Separate FileWatcher orchestration from the FSEvent backend**

Define an internal backend contract in `FileWatcher.swift`:

```swift
protocol FileEventStreaming: AnyObject, Sendable {
    @discardableResult
    func start(
        paths: [String],
        onEvents: @escaping @Sendable () -> Void
    ) -> Bool
    func stop()
}

// Immutable audited function table. SystemFileEventStream serializes every
// invocation; tests replace all entries and never dereference the sentinel.
struct FSEventStreamFunctions: @unchecked Sendable {
    let create: (
        FSEventStreamCallback,
        UnsafeMutablePointer<FSEventStreamContext>,
        CFArray,
        FSEventStreamEventId,
        CFTimeInterval,
        FSEventStreamCreateFlags
    ) -> FSEventStreamRef?
    let setDispatchQueue: (FSEventStreamRef, DispatchQueue) -> Void
    let start: (FSEventStreamRef) -> Bool
    let stop: (FSEventStreamRef) -> Void
    let invalidate: (FSEventStreamRef) -> Void
    let release: (FSEventStreamRef) -> Void

    static let system = FSEventStreamFunctions(
        create: { callback, context, paths, since, latency, flags in
            FSEventStreamCreate(
                nil,
                callback,
                context,
                paths,
                since,
                latency,
                flags
            )
        },
        setDispatchQueue: { FSEventStreamSetDispatchQueue($0, $1) },
        start: { FSEventStreamStart($0) },
        stop: { FSEventStreamStop($0) },
        invalidate: { FSEventStreamInvalidate($0) },
        release: { FSEventStreamRelease($0) }
    )
}

final class SystemFileEventStream: FileEventStreaming, @unchecked Sendable {
    private final class CallbackBox {
        let onEvents: @Sendable () -> Void
        init(onEvents: @escaping @Sendable () -> Void) {
            self.onEvents = onEvents
        }
    }

    private static let callback: FSEventStreamCallback = {
        _, context, _, _, _, _ in
        guard let context else { return }
        Unmanaged<CallbackBox>
            .fromOpaque(context)
            .takeUnretainedValue()
            .onEvents()
    }

    private var stream: FSEventStreamRef?
    private var callbackContext: UnsafeMutableRawPointer?
    private var isStarted = false
    private let functions: FSEventStreamFunctions

    init(functions: FSEventStreamFunctions = .system) {
        self.functions = functions
    }

    @discardableResult
    func start(
        paths: [String],
        onEvents: @escaping @Sendable () -> Void
    ) -> Bool {
        stop()
        guard !paths.isEmpty else { return false }
        let contextPointer = Unmanaged.passRetained(
            CallbackBox(onEvents: onEvents)
        ).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: contextPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let created = functions.create(
            Self.callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
            )
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(contextPointer).release()
            return false
        }
        stream = created
        callbackContext = contextPointer
        functions.setDispatchQueue(created, DispatchQueue.main)
        guard functions.start(created) else {
            stop()
            return false
        }
        isStarted = true
        return true
    }

    func stop() {
        if let stream {
            if isStarted { functions.stop(stream) }
            functions.invalidate(stream)
            functions.release(stream)
            self.stream = nil
        }
        isStarted = false
        if let callbackContext {
            Unmanaged<CallbackBox>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
    }

    deinit {
        stop()
    }
}
```

The callback box owns only `onEvents`, never `FileWatcher`; create failure,
start failure, explicit stop and deinit each balance the retained pointer
exactly once. `FileEventStreaming` is `Sendable` so Swift 6 permits the
MainActor watcher's nonisolated `deinit` to stop it. The production backend and
test mock use `@unchecked Sendable` only as audited ownership adapters: start,
stop and mutable pointer access remain serialized by `FileWatcher` on the main
actor, and FSEvents delivers the callback on `DispatchQueue.main`.

Make orchestration MainActor-bound and deterministic:

```swift
@MainActor
public final class FileWatcher {
    private let backend: FileEventStreaming
    private let scheduler: Scheduler
    private let debounceInterval: TimeInterval
    private var onChange: (@MainActor @Sendable () -> Void)?
    private var isStarted = false

    public convenience init(debounceInterval: TimeInterval = 2.0) {
        self.init(
            debounceInterval: debounceInterval,
            backend: SystemFileEventStream(),
            scheduler: DispatchQueueScheduler()
        )
    }

    init(
        debounceInterval: TimeInterval = 2.0,
        backend: FileEventStreaming,
        scheduler: Scheduler
    ) {
        self.debounceInterval = debounceInterval
        self.backend = backend
        self.scheduler = scheduler
    }

    @discardableResult
    public func start(
        paths: [String],
        onChange: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        stop()
        guard !paths.isEmpty else { return false }
        self.onChange = onChange
        guard backend.start(paths: paths, onEvents: { [weak self] in
            Task { @MainActor in self?.receiveEvents() }
        }) else {
            self.onChange = nil
            return false
        }
        isStarted = true
        return true
    }

    private func receiveEvents() {
        scheduler.cancelPending()
        scheduler.schedule(after: debounceInterval) { [weak self] in
            self?.onChange?()
        }
    }

    public func stop() {
        scheduler.cancelPending()
        let shouldStopBackend = isStarted
        isStarted = false
        onChange = nil
        if shouldStopBackend { backend.stop() }
    }

    deinit {
        if isStarted { backend.stop() }
    }
}
```

The production backend alone touches live FSEvents. Its own `deinit` also calls
idempotent `stop`; Task 3R-A's scheduler holder cancels its pending work item.
Orchestration tests inject `MockFileEventStream`, while production backend cleanup tests inject `FSEventStreamFunctions` with a sentinel handle and never call a system function. Cover empty paths, create nil, create-success/start-false, successful start, active stop, stop after failed start, restart, double stop, active deinit, nil callback context and exactly-once context release. Keep one host integration test for a UUID temporary directory; it is added in Step 10 and may not be skipped.

Removing `streamCreationOverride` is a test-target compile cascade. Before
running any Step 5 filter, move `MockFileEventStream` to
`Tests/LaunchPadTests/TestHelpers/MockProtocols.swift` and replace every
`streamCreationOverride:` initializer in `FileWatcherTests.swift` and
`AppDelegateTests.swift` with the internal `backend:scheduler:` initializer.
Preserve the legacy FileWatcher assertions and names here; Step 9 performs the
framework-only conversion after these deterministic fixture call sites are
committed. Do not retain a production compatibility initializer solely for the
deleted override.

Also replace Task 20's temporary real-FSEvents
`setupFileWatcher_triggersIncrementalScan` fixture with `MockFileEventStream`
and `MockScheduler`: call `backend.emit()`, `await Task.yield()`, advance the
scheduler by the configured debounce interval, then assert one exact
`synchronizeInstalledApps` call. Delete `withAppDelegateTestTimeout` when its
last call is removed. After this step, only Step 10's UUID-directory host test
may start a real FSEvents stream.

AppDelegate must consume startup failure rather than retaining a dead watcher:

```swift
func setupFileWatcher() {
    let watcher = fileWatcherFactory()
    guard watcher.start(paths: watchedPaths, onChange: { [weak self] in
        self?.performIncrementalScan()
    }) else {
        fileWatcher = nil
        NSLog("[AppDelegate] File watcher failed to start")
        return
    }
    fileWatcher = watcher
}
```

Run the watcher lifecycle and AppDelegate suites, then commit the complete
watcher production range before any legacy migration:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'FileWatcherTests|FileWatcherLifecycleTests|AppDelegateTests'
git add Sources/LaunchPad/Services/FileWatcher.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Tests/LaunchPadTests/Services/FileWatcherTests.swift \
  Tests/LaunchPadTests/Services/FileWatcherLifecycleTests.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift
git commit -m "fix: expose and balance file watcher lifecycle"
```

- [x] **Step 6: Complete HotkeyManager tap ownership without duplicating 3R/8 boundaries**

Keep Task 3R-B's MainActor contract, weak `HotkeyCallbackBox`, exact callback
context ownership, `localMonitorInstaller`/`localMonitorRemover` names,
already-injected `EventTapCreator`/`eventTapCreator`, and Task 8's optional-result
handler. Add only the remaining global tap/run-loop boundaries below; do not
redeclare the event-tap creator, callback box, callback or context storage:

```swift
var runLoopSourceCreator: (CFMachPort) -> CFRunLoopSource? = {
    CFMachPortCreateRunLoopSource(kCFAllocatorDefault, $0, 0)
}
var runLoopSourceAdder: (CFRunLoopSource) -> Void = {
    CFRunLoopAddSource(CFRunLoopGetCurrent(), $0, .commonModes)
}
var runLoopSourceRemover: (CFRunLoopSource) -> Void = {
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), $0, .commonModes)
}
var eventTapEnabler: (CFMachPort, Bool) -> Void = {
    CGEvent.tapEnable(tap: $0, enable: $1)
}

@discardableResult
public func registerGlobalHotkey(
    keyCode: UInt32,
    modifiers: NSEvent.ModifierFlags
) -> Bool {
    unregisterGlobalHotkey()
    hasConflict = false
    guard accessibilityChecker() else { return false }
    let mask = CGEventMask(
        (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
    )
    let context = Unmanaged.passRetained(
        HotkeyCallbackBox(manager: self)
    ).toOpaque()
    guard let tap = eventTapCreator(mask, Self.tapCallback, context) else {
        Unmanaged<HotkeyCallbackBox>.fromOpaque(context).release()
        hasConflict = true
        return false
    }
    guard let source = runLoopSourceCreator(tap) else {
        Unmanaged<HotkeyCallbackBox>.fromOpaque(context).release()
        return false
    }
    eventTap = tap
    runLoopSource = source
    callbackContext = context
    runLoopSourceAdder(source)
    eventTapEnabler(tap, true)
    return true
}

public func unregisterGlobalHotkey() {
    if let eventTap { eventTapEnabler(eventTap, false) }
    if let runLoopSource { runLoopSourceRemover(runLoopSource) }
    eventTap = nil
    runLoopSource = nil
    if let callbackContext {
        Unmanaged<HotkeyCallbackBox>.fromOpaque(callbackContext).release()
        self.callbackContext = nil
    }
    isOptionHeld = false
}
```

Delete `retainedSelf`, its lock and the old `tapProvider`. Keep Task 3R-B's
`localMonitor == nil` guard; only assign `localMonitor` when
`localMonitorInstaller` returns a nonnil token. Tests inject every closure above,
capture the callback context passed to `eventTapCreator`, and assert no real
run-loop source is installed. Cover permission failure, tap failure, source
failure, success, re-register cleanup, double unregister and deinit; cover
local add failure/success, register twice, double unregister and deinit with
installer/remover counters. In the same step, replace every AppDelegate test
assignment to `tapProvider` with the corresponding `eventTapCreator`,
`runLoopSourceCreator`, adder/remover and enabler injection. This call-site
migration is required before the package can compile and may not be deferred
to Step 7.

```swift
@Test("global hotkey 重注册与注销平衡 source、tap 和 context")
func globalHotkeyLifecycleIsBalanced() throws {
    let manager = HotkeyManager()
    manager.accessibilityChecker = { true }
    let port = try #require(CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil))
    var adds = 0
    var removes = 0
    var enabled: [Bool] = []
    manager.eventTapCreator = { _, _, _ in port }
    manager.runLoopSourceCreator = {
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, $0, 0)
    }
    manager.runLoopSourceAdder = { _ in adds += 1 }
    manager.runLoopSourceRemover = { _ in removes += 1 }
    manager.eventTapEnabler = { _, value in enabled.append(value) }

    #expect(manager.registerGlobalHotkey(
        keyCode: 49,
        modifiers: .option
    ))
    #expect(manager.hasCallbackContext)
    #expect(manager.registerGlobalHotkey(
        keyCode: 49,
        modifiers: .option
    ))
    #expect(manager.hasCallbackContext)
    manager.unregisterGlobalHotkey()
    manager.unregisterGlobalHotkey()

    #expect(adds == 2)
    #expect(removes == 2)
    #expect(enabled == [true, false, true, false])
    #expect(!manager.hasCallbackContext)
}

@Test("tap 或 source 创建失败立即释放 callback context")
func globalHotkeyCreationFailuresLeaveNoContext() throws {
    let manager = HotkeyManager()
    manager.accessibilityChecker = { true }
    manager.eventTapCreator = { _, _, _ in nil }
    #expect(!manager.registerGlobalHotkey(
        keyCode: 49,
        modifiers: .option
    ))
    #expect(manager.hasConflict)
    #expect(!manager.hasCallbackContext)

    let port = try #require(CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil))
    manager.eventTapCreator = { _, _, _ in port }
    manager.runLoopSourceCreator = { _ in nil }
    #expect(!manager.registerGlobalHotkey(
        keyCode: 49,
        modifiers: .option
    ))
    #expect(!manager.hasCallbackContext)
}
```

Run and commit the global-tap ownership range before changing status-item
shutdown behavior:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'HotkeyManagerTests|AppDelegateTests'
git add Sources/LaunchPad/App/HotkeyManager.swift \
  Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift
git commit -m "fix: balance global hotkey ownership"
```

- [x] **Step 7: Abstract status items and add one idempotent AppDelegate shutdown path**

Add:

```swift
@MainActor
protocol StatusItemManaging: AnyObject {
    var button: NSStatusBarButton? { get }
    var menu: NSMenu? { get set }
}

@MainActor
extension NSStatusItem: StatusItemManaging {}
```

Change `statusItem`/factory to `any StatusItemManaging`, inject a remover that casts production values back to `NSStatusItem`, and make tests return a pure `MockStatusItem`. Add:

```swift
var statusItemRemover: (any StatusItemManaging) -> Void = { item in
    guard let statusItem = item as? NSStatusItem else { return }
    NSStatusBar.system.removeStatusItem(statusItem)
}

public func applicationWillTerminate(_ notification: Notification) {
    fileWatcher?.stop()
    fileWatcher = nil
    hotkeyManager?.unregisterLocalMonitor()
    hotkeyManager?.unregisterGlobalHotkey()
    if let statusItem {
        statusItemRemover(statusItem)
        self.statusItem = nil
    }
}
```

Task 9 already injects the System Settings URL opener. Delete tests that directly call real `SMAppService.register/unregister`, `AXIsProcessTrusted`, `NSStatusBar.system`, and real `NSWorkspace.open`. Replace the `Task.sleep` assertions in AppDelegate/Hotkey tests with synchronous injected runners or `withCheckedContinuation` completion signals.

Run and commit the status-item/shutdown range independently:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter AppDelegateTests
git add Sources/LaunchPad/App/AppDelegate.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift
git commit -m "fix: release app process resources on shutdown"
```

- [x] **Step 8: Read accessibility settings and notifications through local sources**

Add:

```swift
struct AccessibilitySettingsSource: Sendable {
    let reduceMotion: @Sendable () -> Bool
    let reduceTransparency: @Sendable () -> Bool
    let increaseContrast: @Sendable () -> Bool

    static let system = AccessibilitySettingsSource(
        reduceMotion: {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        reduceTransparency: {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        },
        increaseContrast: {
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    )
}

public static func current() -> AccessibilitySettings {
    current(source: .system)
}

static func current(
    source: AccessibilitySettingsSource
) -> AccessibilitySettings {
    AccessibilitySettings(
        reduceMotion: source.reduceMotion(),
        reduceTransparency: source.reduceTransparency(),
        increaseContrast: source.increaseContrast()
    )
}
```

This replaces the incorrect `UserDefaults.standard` reads that treated full
domain names as keys. Make `AccessibilitySettings` conform to `Sendable`, and
give `AccessibilityObserver` exact local dependencies:

```swift
public init(
    notificationCenter: NotificationCenter = .default,
    settingsProvider: @escaping @Sendable () -> AccessibilitySettings = {
        AccessibilitySettings.current()
    },
    callback: @escaping ChangeCallback
) {
    self.notificationCenter = notificationCenter
    self.settingsProvider = settingsProvider
    self.callback = callback
    observer = notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        guard let self else { return }
        callback(self.settingsProvider())
    }
}

public func stop() {
    guard let observer else { return }
    notificationCenter.removeObserver(observer)
    self.observer = nil
}
```

Extend the existing `LaunchPadWindowController` initializer with defaulted
dependencies so production call sites are unchanged:

```diff
- public init(lifecycle: WindowLifecycle, viewController: LaunchPadViewController) {
+ public init(
    lifecycle: WindowLifecycle,
    viewController: LaunchPadViewController,
    accessibilityNotificationCenter: NotificationCenter = .default,
    accessibilitySettingsProvider: @escaping @Sendable ()
        -> AccessibilitySettings = { AccessibilitySettings.current() }
+) {
```

Keep the existing window construction body unchanged. Replace only its current
observer assignment with the following block. Assigning the same provider to
the existing animation property is required so opening and closing never fall
back to a real system read in tests:

```swift
self.accessibilitySettingsProvider = accessibilitySettingsProvider
accessibilityObserver = AccessibilityObserver(
    notificationCenter: accessibilityNotificationCenter,
    settingsProvider: accessibilitySettingsProvider
) { [weak self] settings in
    self?.applyAccessibilitySettings(settings)
}
```

Every `LaunchPadWindowControllerTests.makeSUT()` creates its own
`NotificationCenter`, passes a constant settings provider and returns the center
in `SUT`. The notification test posts only to that center, asserts immediately
on `@MainActor`, and never calls `AccessibilitySettings.current()`. Observer
tests likewise post only to their local center and use
`defer { observer.stop() }`. Cover all false/true combinations, each
animation/material/contrast branch, one notification update, duplicate start,
duplicate stop and deinit cleanup.

Add an initializer-path regression that proves the injected settings provider
drives both animation branches:

```swift
private final class AccessibilitySettingsProviderSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private let settings: AccessibilitySettings

    init(settings: AccessibilitySettings) {
        self.settings = settings
    }

    func read() -> AccessibilitySettings {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        return settings
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }
}

@Test("initializer settings provider 同时驱动 opening 和 closing 动画")
func initializerSettingsProviderDrivesBothAnimations() {
    var durations: [TimeInterval] = []
    let provider = AccessibilitySettingsProviderSpy(
        settings: AccessibilitySettings(
            reduceMotion: true,
            reduceTransparency: false,
            increaseContrast: false
        )
    )
    let sut = makeSUT(accessibilitySettingsProvider: provider.read)
    sut.controller.mainActorDispatcher = { operation in
        MainActor.assumeIsolated { operation() }
    }
    sut.controller.mainAsyncRunner = { $0() }
    sut.controller.runAnimated = { duration, animations, completion in
        durations.append(duration)
        animations()
        completion()
    }

    sut.controller.toggle()
    #expect(sut.lifecycle.state == .visible)
    sut.controller.toggle()

    #expect(sut.lifecycle.state == .hidden)
    #expect(provider.callCount == 2)
    #expect(durations == [0.1, 0.1])
}
```

Run and commit the new accessibility production behavior and its new observer
tests. This commit is not a framework migration:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AccessibilitySettingsTests|AccessibilityObserverTests|AccessibilityObserversTests|LaunchPadWindowControllerTests'
git add Sources/LaunchPad/Utilities/AccessibilityObservers.swift \
  Sources/LaunchPad/App/LaunchPadWindowController.swift \
  Tests/LaunchPadTests/Utilities/AccessibilityObserversTests.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift
git commit -m "fix: isolate accessibility settings and observer sources"
```

- [x] **Step 9: Migrate FileWatcher 14/14 and Accessibility 16/16 in pure commits**

After Steps 5 and 8 are green, migrate each touched legacy file completely.
Both AppKit suites are suite-level `@MainActor`; use `#expect`, `try #require`,
`Issue.record` and structured concurrency only. The old real-file-change method
must become the exact timeout-protected UUID-directory test shown in Step 10
during this pure migration commit, so no `XCTestExpectation` or fixed wait
survives the static scan below. Create all 30 explicit qualified mapping rows
in the Task 21 report. In every data row, the first two backtick-delimited
fields are the exact old and new fully-qualified discovery IDs.

```bash
TASK21_MIGRATION_BASE=$(git rev-parse HEAD)

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter FileWatcherTests
git add Tests/LaunchPadTests/Services/FileWatcherTests.swift \
  docs/superpowers/reports/2026-07-21-task-21-system-boundary-migration.md
git commit -m "test: migrate file watcher tests to Swift Testing"
git diff --exit-code "$TASK21_MIGRATION_BASE"..HEAD -- Sources

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AccessibilitySettingsTests|AccessibilityObserverTests'
git add Tests/LaunchPadTests/Utilities/AccessibilitySettingsTests.swift \
  docs/superpowers/reports/2026-07-21-task-21-system-boundary-migration.md
git commit -m "test: migrate accessibility tests to Swift Testing"
git diff --exit-code "$TASK21_MIGRATION_BASE"..HEAD -- Sources

! rg -n 'import XCTest|XCTestCase|XCTAssert|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:' \
  Tests/LaunchPadTests/Services/FileWatcherTests.swift \
  Tests/LaunchPadTests/Utilities/AccessibilitySettingsTests.swift
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox list | \
  rg '^LaunchPadTests\.(FileWatcherTests|AccessibilitySettingsTests|AccessibilityObserverTests)/' | \
  LC_ALL=C sort > /tmp/task-21-system-boundary-actual-after.txt
awk -F'`' \
  '$0 ~ /^\| `LaunchPadTests\.(FileWatcherTests|AccessibilitySettingsTests|AccessibilityObserverTests)\// { print $2 }' \
  docs/superpowers/reports/2026-07-21-task-21-system-boundary-migration.md | \
  LC_ALL=C sort > /tmp/task-21-system-boundary-expected-before.txt
awk -F'`' \
  '$0 ~ /^\| `LaunchPadTests\.(FileWatcherTests|AccessibilitySettingsTests|AccessibilityObserverTests)\// { print $4 }' \
  docs/superpowers/reports/2026-07-21-task-21-system-boundary-migration.md | \
  LC_ALL=C sort > /tmp/task-21-system-boundary-expected-after.txt
test "$(wc -l < /tmp/task-21-system-boundary-expected-before.txt | tr -d ' ')" -eq 30
test "$(wc -l < /tmp/task-21-system-boundary-expected-after.txt | tr -d ' ')" -eq 30
test "$(wc -l < /tmp/task-21-system-boundary-actual-after.txt | tr -d ' ')" -eq 30
diff -u /tmp/task-21-system-boundary-actual-before.txt \
  /tmp/task-21-system-boundary-expected-before.txt
diff -u /tmp/task-21-system-boundary-expected-after.txt \
  /tmp/task-21-system-boundary-actual-after.txt
```

Expected: 30 migrated IDs pass; the old discovery/report-old diff and the
report-new/new-discovery diff are both empty, proving 30 unique one-to-one
mappings. Static output is empty and `TASK21_MIGRATION_BASE..HEAD` has no
production diff. The existing `AccessibilityObserversTests.swift` remains in
Step 8's behavior commit and is never relabeled as a pure migration.

- [x] **Step 10: Validate lifecycle suites twice, the real host test and the full zero-residue gate**

Confirm Step 9 contains this non-skipped host integration test byte-for-byte;
it touches only a test-owned UUID directory and uses structured timeout rather
than sleep/retry:

```swift
private enum WatcherTimeout: Error { case elapsed }

private func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await ContinuousClock().sleep(for: duration)
            throw WatcherTimeout.elapsed
        }
        guard let result = try await group.next() else {
            throw WatcherTimeout.elapsed
        }
        group.cancelAll()
        return result
    }
}

@Test("真实 FSEvents 在 UUID 临时目录变更后触发 callback")
func realTemporaryDirectoryChangeTriggersCallback() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LaunchPadWatcher-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let events = AsyncStream<Void>.makeStream()
    let watcher = FileWatcher(debounceInterval: 0.05)
    #expect(watcher.start(paths: [directory.path]) {
        events.continuation.yield()
    })
    defer {
        watcher.stop()
        events.continuation.finish()
    }

    try Data("event".utf8).write(
        to: directory.appendingPathComponent("probe.txt"),
        options: .atomic
    )
    let received = try await withTimeout(.seconds(10)) {
        for await _ in events.stream { return true }
        return false
    }
    #expect(received)
}
```

```bash
for run in 1 2; do
  CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
  swift test --disable-sandbox --no-parallel \
    --filter 'AppScannerTests|FileWatcherTests|FileWatcherLifecycleTests|AccessibilitySettingsTests|AccessibilityObserverTests|AccessibilityObserversTests|HotkeyManagerTests|AppDelegateTests'
done

! rg -n \
  'import XCTest|XCTestCase|XCTAssert[A-Za-z]*|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:' \
  Tests --glob '*.swift'

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel
```

Expected: both focused invocations and the complete suite exit 0 with summaries, the real temporary-directory test executes, static output is empty, and no manual termination, skip, signal or persistent system resource occurs.

- [x] **Step 11: Review every committed boundary and the aggregate range**

Review the already committed ranges independently in execution order:

1. AppScanner read-only exclusion parsing.
2. FileWatcher production lifecycle and startup failure.
3. Global hotkey ownership.
4. AppDelegate shutdown/status-item ownership.
5. Accessibility production sources and new observer behavior.
6. FileWatcher 14/14 pure migration.
7. Accessibility 16/16 pure migration.

Then review Task 21 base..head and record all commit ranges, focused commands,
the real host result, 30 mappings and zero-residue scan in
`.superpowers/sdd/task-21-migration.md`. Any review fix is committed to its
own range, reruns the exact affected suite and invalidates the old aggregate
review package.

---

### Task 22: Make Wall-clock Performance Assertions Deterministic and Add the Release Gate

**Files:**
- Modify: `Tests/LaunchPadTests/Performance/PerformanceTests.swift`
- Create: `scripts/test-release.sh`

**Interfaces:**
- Consumes: all production behavior from Tasks 1-21 and Task 4's executable
  `scripts/run-with-timeout.sh` process-group watchdog.
- Produces: `ContinuousClock` median/p95 assertions, release artifacts and one
  timeout-protected release command. It does not produce another supervisor.
- Constraint: no environment switch, test trait, `--skip PerformanceTests`, or relaxed threshold.

- [x] **Step 1: Add deterministic benchmark helpers and first RED conversions**

Replace `Date` and random selection with:

```swift
private let sampleCount = 11

private func durations<T>(
    warmupCount: Int = 3,
    operation: () -> T
) -> (samples: [Duration], last: T) {
    for _ in 0..<warmupCount { _ = operation() }
    let clock = ContinuousClock()
    var samples: [Duration] = []
    var last = operation()
    for _ in 0..<sampleCount {
        let start = clock.now
        last = operation()
        samples.append(start.duration(to: clock.now))
    }
    return (samples.sorted(), last)
}

private func median(_ samples: [Duration]) -> Duration {
    samples[samples.count / 2]
}

private func percentile95(_ samples: [Duration]) -> Duration {
    let index = min(samples.count - 1, Int(ceil(Double(samples.count) * 0.95)) - 1)
    return samples[index]
}

private func deterministicIndices(
    count: Int,
    upperBound: Int,
    seed: UInt64 = 0x4C41554E43485041
) -> [Int] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int(state % UInt64(upperBound))
    }
}
```

Replace the five measured test bodies with the exact pattern below. Fixture
creation, cache prefill, deterministic-index generation and correctness checks
remain outside each measured interval:

```swift
@Test("SearchEngine 1000 项无缓存 median/p95 < 50ms")
func search_1000items_under50ms() {
    let items = (0..<1000).map { index in
        TestDataFactory.makePageItem(
            id: Int64(index),
            uuid: "perf-\(index)",
            ordering: index,
            app: TestDataFactory.makeAppInfo(
                id: Int64(index),
                title: "Application \(index)",
                bundleId: "com.test.app\(index)"
            )
        )
    }
    let engine = SearchEngine()

    let measurement = durations {
        engine.search(items: items, query: "app")
    }

    #expect(measurement.last.count == 1000)
    #expect(median(measurement.samples) < .milliseconds(50))
    #expect(percentile95(measurement.samples) < .milliseconds(50))
}

@Test("SearchEngine 缓存命中 median/p95 < 1ms")
func search_cached_under1ms() {
    let items = (0..<1000).map { index in
        TestDataFactory.makePageItem(
            id: Int64(index),
            uuid: "cache-\(index)",
            ordering: index,
            app: TestDataFactory.makeAppInfo(
                id: Int64(index),
                title: "App \(index)",
                bundleId: "com.test.cache\(index)"
            )
        )
    }
    let engine = SearchEngine()
    _ = engine.cachedSearch(items: items, query: "test")

    let measurement = durations {
        engine.cachedSearch(items: items, query: "test")
    }

    #expect(measurement.last.count == 1000)
    #expect(median(measurement.samples) < .milliseconds(1))
    #expect(percentile95(measurement.samples) < .milliseconds(1))
}

@Test("Diffable snapshot 1002 项 median/p95 < 10ms")
func snapshot_1000items_under10ms() {
    let pages = (0..<3).map { pageIndex in
        (0..<334).map { itemIndex in
            let global = pageIndex * 334 + itemIndex
            return TestDataFactory.makePageItem(
                id: Int64(global),
                uuid: "snap-\(global)",
                ordering: itemIndex,
                app: TestDataFactory.makeAppInfo(
                    id: Int64(global),
                    title: "App \(global)",
                    bundleId: "com.test.snap\(global)"
                )
            )
        }
    }

    let measurement = durations {
        DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )
    }

    #expect(measurement.last.numberOfItems == 1002)
    #expect(median(measurement.samples) < .milliseconds(10))
    #expect(percentile95(measurement.samples) < .milliseconds(10))
}

@Test("动态 GridMetrics 三种 viewport median/p95 < 1ms")
func gridCalculation_under1ms() {
    let sizes = [
        CGSize(width: 1440, height: 620),
        CGSize(width: 1728, height: 620),
        CGSize(width: 2560, height: 620),
    ]

    let measurement = durations {
        sizes.map { GridLayoutCalculator.calculate(viewportSize: $0) }
    }

    #expect(measurement.last.allSatisfy { $0.itemsPerPage > 0 })
    #expect(median(measurement.samples) < .milliseconds(1))
    #expect(percentile95(measurement.samples) < .milliseconds(1))
}

#if canImport(AppKit)
@Test("IconCache 1000 次内存命中 median/p95 < 300ms")
func iconCache_1000randomAccess_perf() {
    let provider = MockIconProvider()
    let store = MockImageStore()
    let image = NSImage(size: NSSize(width: 16, height: 16))
    provider.iconResult = image
    let data = image.tiffRepresentation ?? Data()
    let itemCount = 50
    for index in 0..<itemCount {
        store.storedImages[Int64(index)] = (data, data)
    }
    let cache = IconCache(
        iconProvider: provider,
        imageStore: store,
        memoryLimit: 100
    )
    let paths = (0..<itemCount).map {
        "/Applications/App-\($0).app"
    }
    for (index, path) in paths.enumerated() {
        _ = cache.icon(forItemId: Int64(index), path: path)
    }
    let indices = deterministicIndices(
        count: 1000,
        upperBound: itemCount
    )

    let measurement = durations {
        var last: NSImage?
        for index in indices {
            last = cache.icon(
                forItemId: Int64(index),
                path: paths[index]
            )
        }
        return last
    }

    #expect(measurement.last != nil)
    #expect(median(measurement.samples) < .milliseconds(300))
    #expect(percentile95(measurement.samples) < .milliseconds(300))
}
#endif
```

- [x] **Step 2: Preserve every existing threshold for both median and p95**

Use these exact assertions:

```swift
#expect(median(samples) < .milliseconds(50))
#expect(percentile95(samples) < .milliseconds(50))
```

Keep the no-disk-write correctness test unmeasured, but replace its random loop
with the same deterministic index sequence:

```swift
let indices = deterministicIndices(count: 1000, upperBound: itemCount)
for index in indices {
    _ = cache.icon(forItemId: Int64(index), path: paths[index])
}
#expect(store.saveCallCount == saveCountAfterPrefill)
```

Do not add `.enabled(if:)`, `ProcessInfo.processInfo.environment`, compile flags, retries, threshold multipliers, or skipped samples. A failed wall-clock assertion remains a release failure.

- [x] **Step 3: Run the performance suite serially and fix real regressions before proceeding**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
scripts/run-with-timeout.sh 180 -- \
  swift test --disable-sandbox --no-parallel --filter PerformanceTests
```

Expected: 6/6 tests pass and the process exits 0. If a threshold fails, capture a sample of the test process and optimize the measured production path; do not skip, condition, retry or widen the assertion.

- [x] **Step 4: Create the single release test entry**

Create executable `scripts/test-release.sh` with this structure:

```zsh
#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

ROOT_DIR=${0:A:h:h}
export CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache

WATCHDOG="$ROOT_DIR/scripts/run-with-timeout.sh"
[[ -x "$WATCHDOG" ]]

assert_no_test_process() {
  ! pgrep -x swift-test >/dev/null
  ! pgrep -x LaunchPadPackageTests >/dev/null
  ! pgrep -f \
    '/LaunchPadPackageTests\.xctest/Contents/MacOS/LaunchPadPackageTests' \
    >/dev/null
}

assert_static_policy() {
  local legacy_pattern='import XCTest|XCTestCase|XCTAssert[A-Za-z]*|XCTFail|XCTSkip|XCTestExpectation|expectation\(|wait\(for:'
  local bypass_pattern='XCTSkip|\.disabled\(|\.enabled\(if:|Task\.sleep|RunLoop\.main\.run'
  local grid_legacy_pattern='delegate[[:space:]]*=[[:space:]]*self|NSCollectionViewDelegate|onItemSelected|onSelectionChanged|dragController|pasteboardUUIDReader'
  local host_legacy_pattern='interactionBounds|pageItem\(uuid:|moveSnapshotItem\(|itemsByUUID|snapshotMoves'

  if rg -n --glob '*.swift' "$legacy_pattern" Tests; then
    print -u2 'release gate: legacy test framework residue detected'
    return 1
  fi
  if rg -n --glob '*.swift' "$bypass_pattern" Tests; then
    print -u2 'release gate: skip or fixed-wait API detected'
    return 1
  fi
  if rg -n "$grid_legacy_pattern" \
      Sources/LaunchPad/Views/AppGridCollectionView.swift; then
    print -u2 'release gate: obsolete main-grid delegate API detected'
    return 1
  fi
  if rg -n --glob 'AppGrid*.swift' '[Pp]roxy' \
      Sources/LaunchPad/Views; then
    print -u2 'release gate: main-grid proxy detected'
    return 1
  fi
  if rg -n "$host_legacy_pattern" \
      Sources/LaunchPad/Views/AppGridCollectionView.swift \
      Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift \
      Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
      Tests/LaunchPadTests/Views/AppGridInteractionCoordinatorTests.swift; then
    print -u2 'release gate: obsolete grid-host surface detected'
    return 1
  fi
  if rg -n 'setCurrentVisualPageIndex' \
      Sources/LaunchPad/Views/AppGridInteractionCoordinator.swift; then
    print -u2 'release gate: grid-host page mutation detected'
    return 1
  fi
  if rg -n -U --pcre2 \
      '\b([A-Za-z_][A-Za-z0-9_]*)\.collectionView\(\s*\1\s*,' \
      Tests --glob '*.swift'; then
    print -u2 'release gate: direct main-grid delegate bypass detected'
    return 1
  fi
}

assert_run_log() {
  local log=$1
  local expected_count=$2
  local summary="✔ Test run with ${expected_count} tests"

  [[ $(rg -c '^✔ Test run with ' "$log") -eq 1 ]]
  rg -q -F "$summary" "$log"
  ! rg -n '↷|[Ss]kipped|✘|failed after|unexpected signal|signal [0-9]+' "$log"

  local name
  for name in \
    'SearchEngine 1000 项无缓存 median/p95 < 50ms' \
    'SearchEngine 缓存命中 median/p95 < 1ms' \
    'Diffable snapshot 1002 项 median/p95 < 10ms' \
    '动态 GridMetrics 三种 viewport median/p95 < 1ms' \
    'IconCache 1000 次内存命中 median/p95 < 300ms' \
    'IconCache 1000 次访问后无磁盘重复写入'
  do
    rg -q -F "Test \"$name\" passed" "$log"
  done
}

cd "$ROOT_DIR"
zsh -n "$0"
assert_static_policy
"$WATCHDOG" --self-test-timeout
"$WATCHDOG" --self-test-signal
"$WATCHDOG" --self-test-nonzero
assert_no_test_process

ARTIFACT_DIR=${LAUNCHPAD_RELEASE_ARTIFACT_DIR:-\
"$ROOT_DIR/.superpowers/sdd/release-gate-$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$ARTIFACT_DIR"

for run in 1 2 3; do
  print "release gate: test run ${run}/3"
  raw_list="$ARTIFACT_DIR/tests-${run}.raw"
  list="$ARTIFACT_DIR/tests-${run}.list"
  log="$ARTIFACT_DIR/tests-${run}.log"

  "$WATCHDOG" 180 -- swift test --disable-sandbox \
    --disable-xctest --enable-swift-testing list >"$raw_list"
  LC_ALL=C rg '^LaunchPadTests\.' "$raw_list" >"$list"
  [[ -s "$list" ]]
  ! rg -n -v '^LaunchPadTests\.' "$list"
  [[ $(rg -c '^LaunchPadTests\.PerformanceTests/' "$list") -eq 6 ]]
  if (( run > 1 )); then
    cmp -s "$ARTIFACT_DIR/tests-1.list" "$list"
  fi
  expected_count=$(wc -l <"$list" | tr -d ' ')

  "$WATCHDOG" 900 -- /bin/zsh -o pipefail -c \
    'swift test --disable-sandbox --disable-xctest \
      --enable-swift-testing --no-parallel 2>&1 | tee "$1"' \
    _ "$log"
  assert_run_log "$log" "$expected_count"
  assert_no_test_process
done

print 'release gate: release build'
"$WATCHDOG" 900 -- /bin/zsh -o pipefail -c \
  'swift build -c release --product LaunchPadApp 2>&1 | tee "$1"' \
  _ "$ARTIFACT_DIR/release-build.log"
assert_no_test_process
print "release gate: artifacts $ARTIFACT_DIR"
```

`scripts/test-release.sh` contains no supervisor, signal trap, `setpgrp`,
`setpgid` or inline Perl. It validates Task 4's shared watchdog, runs all three watchdog
self-tests, rejects legacy XCTest/fixed waits, rejects any reintroduced main-grid
self-delegate/proxy/old interaction API and rejects direct main-grid delegate
bypass calls. It then invokes every discovery, full-suite and release-build
command through `"$WATCHDOG" SECONDS -- ...`. Any timeout/signal/nonzero status
propagates through `set -e`; Task 4 remains the single owner of process-group
creation, TERM/grace/KILL, reaping and exact-PID self-test behavior.
Normal execution then performs three independent
discovery runs and three matching serial test runs. Raw discovery stdout is retained
as `tests-N.raw` for diagnostics, but only strict `^LaunchPadTests\.` test-ID lines
enter `tests-N.list`; build planning/progress lines can never inflate the count or
break list equality. Each filtered list contains exactly six Performance tests and
is byte-identical to run 1; each log contains one complete summary with the filtered
test count, all six named performance pass lines and no skip/failure/signal marker.
Release-build stdout/stderr is retained in `release-build.log`; do not suppress it,
so every warning remains visible in the artifact directory.
Run `chmod +x scripts/test-release.sh`.

- [x] **Step 5: Validate script syntax and anti-skip invariants**

```bash
zsh -n scripts/run-with-timeout.sh scripts/test-release.sh
test -x scripts/run-with-timeout.sh
test -x scripts/test-release.sh
scripts/run-with-timeout.sh --self-test-timeout
scripts/run-with-timeout.sh --self-test-signal
scripts/run-with-timeout.sh --self-test-nonzero
! rg -n 'run_with_timeout\(\)|setpgrp|setpgid|/usr/bin/perl' scripts/test-release.sh
rg -q -F 'scripts/run-with-timeout.sh' scripts/test-release.sh
! rg -n 'enabled\(if:|ProcessInfo\.processInfo\.environment|--skip.*PerformanceTests' \
  Tests/LaunchPadTests/Performance/PerformanceTests.swift scripts/test-release.sh
rg -q -F 'assert_static_policy' scripts/test-release.sh
rg -q -F 'obsolete main-grid delegate API detected' scripts/test-release.sh
rg -q -F 'main-grid proxy detected' scripts/test-release.sh
rg -q -F 'obsolete grid-host surface detected' scripts/test-release.sh
rg -q -F 'grid-host page mutation detected' scripts/test-release.sh
rg -q -F 'direct main-grid delegate bypass detected' scripts/test-release.sh
rg -q -F 'Sources/LaunchPad/Views/AppGridCollectionView.swift' \
  scripts/test-release.sh
rg -q -F -- '--pcre2' scripts/test-release.sh
rg -q -F -- "Tests --glob '*.swift'" scripts/test-release.sh
rg -q -F 'assert_run_log' scripts/test-release.sh
rg -q -F 'for run in 1 2 3' scripts/test-release.sh
rg -q -F "LC_ALL=C rg '^LaunchPadTests\\.'" scripts/test-release.sh
rg -q -F -- '--disable-xctest --enable-swift-testing' scripts/test-release.sh
rg -q -F -- '--enable-swift-testing --no-parallel' scripts/test-release.sh
rg -q -F 'release-build.log' scripts/test-release.sh
rg -q -F 'swift build -c release --product LaunchPadApp' scripts/test-release.sh
```

Expected: both scripts pass syntax/executable checks, all shared watchdog
self-tests exit 0, the negative scan prints nothing, and all required gate
fragments are found. The self-tests run no Swift command and prove exact
wrapper/supervisor/child/descendant PID cleanup for timeout, HUP/INT/TERM and
ordinary nonzero, while the separate exec-failure branch proves status `127`.
Neither script inspects or kills unrelated system `sleep` processes.
The normal path, not only manual validation, invokes all three self-tests before discovery. `--xunit-output` is intentionally not used because the current Swift Testing runner did not produce a reliable XML artifact; discovery lists, complete logs, exact summaries, named performance pass lines and exit codes are the authority.

- [x] **Step 6: Commit**

```bash
git add Tests/LaunchPadTests/Performance/PerformanceTests.swift \
  scripts/test-release.sh
git commit -m "test: enforce deterministic release performance gates"
```

---

### Task 23: Complete Reopen Durability, Run the Full Gate and Synchronize Release Documentation

**Files:**
- Modify: `Tests/LaunchPadTests/Integration/IntegrationTests.swift`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md`
- Modify: `docs/superpowers/specs/2026-07-21-swift-testing-unification-design.md`
- Modify: `docs/superpowers/specs/2026-07-22-app-grid-interaction-coordinator-design.md`
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Tasks 1-22, Task 22's timestamped artifact directory and, through
  the sole `scripts/test-release.sh` entry, Task 4's shared watchdog.
- Produces: file-backed SQLite durability evidence, three-run test/list/log evidence, release-build evidence and documentation matching production.
- Preserves: `docs/2026-07-15-release-readiness-review.md` as immutable historical evidence.

- [x] **Step 1: Add top-level blank/cross-page and complete folder durability RED tests**

Do not duplicate Task 14's `layoutCommitSurvivesReopen` or
`rollbackFailureInvalidatesAndReopenRestoresCommittedState`; those already
prove normal COMMIT durability and rollback-failure connection invalidation
with two manager lifetimes. First add a two-page file-backed proof that the
second page's blank tail anchor survives close/reopen:

```swift
@Test("跨页移动到末页空白尾部在关闭重开后保持稠密顺序")
func crossPageBlankAppendSurvivesFileReopen() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("LaunchPadCrossPage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("layout.sqlite").path
    var ids: [Int64] = []

    do {
        let storage = try StorageManager(dbPath: path)
        let firstPage = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-1",
            type: .page,
            ordering: 0
        ))
        let secondPage = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-2",
            type: .page,
            ordering: 1
        ))
        for index in 0..<4 {
            ids.append(try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "cross-page-app-\(index)",
                type: .app,
                ordering: index % 2,
                parentId: index < 2 ? firstPage : secondPage,
                app: TestDataFactory.makeAppInfo(
                    title: "Cross Page \(index)",
                    bundleId: "com.test.cross-page.\(index)"
                )
            )))
        }
        try storage.apply(
            .moveTopLevel(
                itemID: ids[0],
                placement: .afterItem(itemID: ids[3])
            ),
            pageCapacity: 2
        )
    }

    do {
        let reopened = try StorageManager(dbPath: path)
        let snapshot = try reopened.persistedLayoutSnapshot()
        #expect(snapshot.pages.map(\.ordering) == [0, 1])
        #expect(snapshot.flattenedTopLevelIDs == [ids[1], ids[2], ids[3], ids[0]])
        #expect(snapshot.pageChildren[snapshot.pages[0].id]?.map(\.ordering)
            == [0, 1])
        #expect(snapshot.pageChildren[snapshot.pages[1].id]?.map(\.ordering)
            == [0, 1])
        #expect(snapshot.pageChildren[snapshot.pages[1].id]?.map(\.id)
            == [ids[3], ids[0]])
    }
}
```

Then add both
`createFolderAndSafeDeleteSurviveFileReopen` and
`folderMutationSequenceSurvivesEveryFileReopen` to `IntegrationTests.swift`.
The second test destroys and recreates `StorageManager` after every
add/reorder/remove/auto-dissolve mutation:

```swift
@Test("create folder 与 safe delete 分别跨关闭重开持久化")
func createFolderAndSafeDeleteSurviveFileReopen() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("LaunchPadFolder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("layout.sqlite").path
    var firstID: Int64 = 0
    var secondID: Int64 = 0
    var folderID: Int64 = 0

    do {
        let storage = try StorageManager(dbPath: path)
        let pageID = try storage.insertItem(
            TestDataFactory.makePageItem(uuid: "folder-page", type: .page)
        )
        firstID = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "folder-first", parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.folder.first")
        ))
        secondID = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "folder-second", ordering: 1, parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.folder.second")
        ))
        try storage.apply(
            .createFolder(
                itemID: secondID,
                targetItemID: firstID,
                title: "Work"
            ),
            pageCapacity: 35
        )
        let snapshot = try storage.persistedLayoutSnapshot()
        folderID = try #require(
            snapshot.allItems.first { $0.group?.title == "Work" }?.id
        )
    }

    do {
        let reopened = try StorageManager(dbPath: path)
        let snapshot = try reopened.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [folderID])
        #expect(snapshot.folderChildren[folderID]?.map(\.id) == [firstID, secondID])
        try reopened.apply(.deleteFolder(folderID: folderID), pageCapacity: 35)
    }

    do {
        let reopened = try StorageManager(dbPath: path)
        let snapshot = try reopened.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [firstID, secondID])
        #expect(snapshot.allItems.contains { $0.id == folderID } == false)
    }
}

@Test("folder add/reorder/remove/auto-dissolve 每步关闭重开仍持久化")
func folderMutationSequenceSurvivesEveryFileReopen() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(
            "LaunchPadFolderSequence-\(UUID().uuidString)"
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("layout.sqlite").path

    var firstID: Int64 = 0
    var secondID: Int64 = 0
    var thirdID: Int64 = 0
    var fourthID: Int64 = 0
    var folderID: Int64 = 0

    do {
        let storage = try StorageManager(dbPath: path)
        let pageID = try storage.insertItem(
            TestDataFactory.makePageItem(
                uuid: "sequence-page",
                type: .page
            )
        )
        func insertApp(_ index: Int, ordering: Int) throws -> Int64 {
            try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "sequence-app-\(index)",
                type: .app,
                ordering: ordering,
                parentId: pageID,
                app: TestDataFactory.makeAppInfo(
                    title: "Sequence \(index)",
                    bundleId: "com.test.sequence.\(index)"
                )
            ))
        }
        firstID = try insertApp(1, ordering: 0)
        secondID = try insertApp(2, ordering: 1)
        thirdID = try insertApp(3, ordering: 2)
        fourthID = try insertApp(4, ordering: 3)
        try storage.apply(
            .createFolder(
                itemID: secondID,
                targetItemID: firstID,
                title: "Sequence Folder"
            ),
            pageCapacity: 35
        )
        folderID = try #require(
            storage.persistedLayoutSnapshot().allItems.first {
                $0.group?.title == "Sequence Folder"
            }?.id
        )
        try storage.apply(
            .addToFolder(itemID: thirdID, folderID: folderID),
            pageCapacity: 35
        )
    }

    do {
        let storage = try StorageManager(dbPath: path)
        let snapshot = try storage.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [folderID, fourthID])
        #expect(snapshot.folderChildren[folderID]?.map(\.id) == [
            firstID, secondID, thirdID,
        ])
        try storage.apply(
            .reorderFolderItem(
                itemID: thirdID,
                folderID: folderID,
                placement: .beforeItem(itemID: firstID)
            ),
            pageCapacity: 35
        )
    }

    do {
        let storage = try StorageManager(dbPath: path)
        let snapshot = try storage.persistedLayoutSnapshot()
        #expect(snapshot.folderChildren[folderID]?.map(\.id) == [
            thirdID, firstID, secondID,
        ])
        try storage.apply(
            .removeFromFolder(
                itemID: thirdID,
                folderID: folderID,
                placement: .afterItem(itemID: folderID)
            ),
            pageCapacity: 35
        )
    }

    do {
        let storage = try StorageManager(dbPath: path)
        let snapshot = try storage.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [
            folderID, thirdID, fourthID,
        ])
        #expect(snapshot.folderChildren[folderID]?.map(\.id) == [
            firstID, secondID,
        ])
        try storage.apply(
            .removeFromFolder(
                itemID: secondID,
                folderID: folderID,
                placement: .afterItem(itemID: folderID)
            ),
            pageCapacity: 35
        )
    }

    do {
        let storage = try StorageManager(dbPath: path)
        let snapshot = try storage.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [
            firstID, secondID, thirdID, fourthID,
        ])
        #expect(snapshot.allItems.contains { $0.id == folderID } == false)
        #expect(snapshot.folderChildren[folderID] == nil)
    }
}
```

- [x] **Step 2: Run integration and storage suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainStateTests|IntegrationTests'
```

- [x] **Step 3: Run every P0-adjacent suite before the expensive gate**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'GridLayoutCalculatorTests|LayoutProjectionTests|AnimationRunnerTests|LayoutPersistenceTests|EmptyStateViewTests|SearchBarTests|AppGridFlowLayoutTests|PageControlViewTests|PageScrollViewTests|DiffableDataSourceBuilderTests|DiffableDataSourceTests|AppGridInteractionCoordinatorTests|AppGridCollectionViewTests|AppIconCellTests|FolderCellTests|FolderOverlayViewTests|FolderOverlayViewPagingTests|CollectionViewDragTests|SearchDebounceTests|ProtocolTests|KeyboardNavigatorTests|HotkeyManagerTests|DragControllerTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests|TransientMessageViewTests|AppScannerTests|FileWatcherTests|FileWatcherLifecycleTests|AccessibilitySettingsTests|AccessibilityObserverTests|AccessibilityObserversTests|AppDelegateTests|StorageManager|LayoutDomainStateTests|IntegrationTests|PerformanceTests'
```

Expected: all selected suites pass, performance assertions execute, and the process exits without a residual test process.

- [x] **Step 4: Commit and independently review durability evidence**

```bash
git add Tests/LaunchPadTests/Integration/IntegrationTests.swift
git commit -m "test: prove layout durability across reopen"

CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainStateTests|IntegrationTests'
```

Review the integration commit by itself and require the focused command to exit 0. No documentation file enters this commit.

- [x] **Step 5: Run the sole final-authority gate and retain its artifact directory**

```bash
set -o pipefail
./scripts/test-release.sh 2>&1 | tee /tmp/launchpad-release-gate-final.log
```

Expected: three discovery commands, three complete test passes including all six
`PerformanceTests` each time, and one release build all execute through Task 4's
shared watchdog; the sole outer command exits 0 with no timeout, signal, skip,
warning suppression or residual test process. Record the artifact directory
printed by the script. This is the only final-authority gate run; Task 23 must
not call the watchdog directly or run a pre-document duplicate.

- [x] **Step 6: Synchronize README, all three design documents and progress from Step 5 artifacts**

Update README to state:

- grid rows are viewport-derived from 5 down to 1, with 7/9/10 columns and 64...96pt icons;
- pages are visual slices of one stable global order; monitor changes do not write storage;
- drag supports same/cross page, empty append, existing folder, 0.8s preview then drop-to-create, folder reorder and drag-out; nested folders remain forbidden;
- the only release command is `./scripts/test-release.sh`; it self-tests and
  consumes the shared `scripts/run-with-timeout.sh`, then runs three complete
  Swift Testing-only serial passes plus a release build;
- remove `Swift Testing + XCTest`, “少量历史测试使用 XCTest，两者共存”, `0 warnings`, `520+ tests`, fixed test-file counts, per-suite workaround and “full tests hang” claims;
- tests do not touch real Dock plist, accessibility settings, login items, event taps, status items or the user database; the only real FSEvents proof watches a UUID temporary directory created by the test;
- the current test count, each of the three exact summaries and release-build exit status are copied from Step 5 artifacts and are never prefilled in this plan.

README's test entry is exactly:

```bash
./scripts/test-release.sh
```

Update all three design documents' verification appendices with final task/test
names, the exact gate command and fresh Step 5 result. Update ignored
`.superpowers/sdd/progress.md` with actual branch, commit IDs, commands, three
test counts/summaries, release-build exit code and Step 5 artifact path. Do not
edit the historical review report or claim that unresolved P1/P2 release
findings are closed.

- [x] **Step 7: Review and commit documentation evidence separately**

```bash
git diff --check
git status --short
git diff -- README.md \
  docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md \
  docs/superpowers/specs/2026-07-21-swift-testing-unification-design.md \
  docs/superpowers/specs/2026-07-22-app-grid-interaction-coordinator-design.md
git add README.md \
  docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md \
  docs/superpowers/specs/2026-07-21-swift-testing-unification-design.md \
  docs/superpowers/specs/2026-07-22-app-grid-interaction-coordinator-design.md
git commit -m "docs: record verified p0 release behavior"
```

Only the four tracked documentation files may enter this commit.
`.superpowers/sdd/progress.md` is updated as execution evidence but remains
ignored unless repository policy changes explicitly. Review the integration
commit, documentation commit and Task 23 base..head separately. The historical
review report remains unmodified and untracked work outside this plan remains
untouched.

---

## P0 Test Synchronization Matrix

| P0 | Production surface | Required unit/integration suites | Negative proof |
|---|---|---|---|
| P0-1 grid | `GridLayoutCalculator`, projection, flow layout, scroll, cells, `AppGridInteractionCoordinator`, VC | `GridLayoutCalculatorTests`, `LayoutProjectionTests`, migrated `ViewLayerTests` 56/56, migrated Cell/Grid suites 128/128, `AppGridInteractionCoordinatorTests`, `PageScrollViewTests`, `LaunchPadViewControllerTests` | invalid viewport returns no reproject; display switch causes zero storage writes; no self-delegate/proxy/old grid interaction API; real reload/display/selection cycle is `< 1s` and process-watchdog protected; four migrated files have no legacy symbols or lost tolerances |
| P0-2 search input | `KeyboardNavigator`, first-character application, search debounce | `KeyboardNavigatorTests`, `SearchDebounceTests`, `LaunchPadViewControllerTests`, `AppDelegateTests` | first key atomically enters search and appears in query/results; stale callbacks cannot overwrite current query |
| P0-3 key event chain | `HotkeyManager`, AppDelegate route, VC result | `HotkeyManagerTests`, `LaunchPadViewControllerTests`, `AppDelegateTests` | flags/unknown/hidden/unhandled events return the original object; only a handled visible keyDown returns nil |
| P0-4 drag/drop and required atomic storage | contracts, domain state, transaction, drag session, coordinator, grid host, folder overlay/cell, VC, `StorageManager.apply` | `ProtocolTests`, `LayoutDomainStateTests`, `StorageManagerTests`, `StorageManagerLayoutMutationTests`, `DragControllerTests`, `CollectionViewDragTests`, `AppGridInteractionCoordinatorTests`, `AppGridCollectionViewTests`, `AppIconCellTests`, migrated FolderOverlay suites 47/47, `FolderCellTests`, `TransientMessageViewTests`, `LaunchPadViewControllerTests`, `LaunchPadWindowControllerTests`, `IntegrationTests` | BEGIN/prepare/bind/step/COMMIT failures preserve snapshot; rollback failure invalidates first connection; search/self/stale/nested/group-on-item reject; main-grid delegate calls use real wiring and coordinator-owned pasteboard reads; no optimistic snapshot; hover performs zero writes and release attempts exactly one mutation |
| P0-5 initial scan | `AppScanner`, `StorageManager` scan batch, AppDelegate, target metrics | `StorageManagerScanBatchTests`, `AppScannerTests`, `GridLayoutCalculatorTests`, `LaunchPadViewControllerTests`, `AppDelegateTests`, `IntegrationTests` | real SQLite automatic rollback leaves no autocommit rows; failed read/write does not reload; unloaded VC is not forced; real viewport capacity and all-empty-page cleanup are asserted |
| P0-6 release repeatability | system boundaries, performance, shared watchdog, release orchestrator | migrated FileWatcher/Accessibility suites 30/30, `HotkeyManagerTests`, `AppDelegateTests`, six `PerformanceTests`, `scripts/run-with-timeout.sh` self-tests, full gate | zero legacy test symbols; no user-system side effects; real FSEvents only watches a UUID temp directory; no fixed waits/performance skip/residual process; timeout/HUP/INT/TERM/nonzero clean exact wrapper/supervisor/child/descendant PIDs and exec failure preserves 127; `test-release.sh` contains no second supervisor; three lists/logs/counts/summaries match |

## Execution Batches and Checkpoints

1. **Batch A0 - crash/resource baseline:** Tasks 3R-A, 3R-B and the full-gate-triggered Task 3R-C immediately after historical Task 3. Require a complete full-suite summary with no signal, no residual process and no failure/skip outside the monotonically decreasing registered baseline before any feature work continues.
2. **Batch A1 - view migration and grid:** Task 3M, then Tasks 4-9. Review the fixture commit, each pure migration commit and behavior commits separately; confirm 56 + 128 mappings and no database write in viewport/input paths.
3. **Batch B - atomic domain/storage:** Tasks 10-14. Run every storage/domain suite and inspect rollback/reopen evidence before any UI writer is connected.
4. **Batch C - drag UI:** Tasks 15-19. Run the complete drag/folder suite, audit all 47 folder mappings and prove hover callbacks cannot reach `LayoutMutating`.
5. **Batch D - scan and resource lifecycle:** Tasks 20-21. Audit all 30 lifecycle/accessibility mappings, run focused suites twice, execute the temp-directory host test and require full-suite zero residue.
6. **Batch E - performance and final gate:** Tasks 22-23. Run focused performance, commit durability evidence, then run `scripts/test-release.sh` once as the only final authority before documentation evidence.

At each checkpoint, review `git status --short` and stage only files listed by the completed task. Do not restore or stage pre-existing user changes.

## Final Acceptance Criteria

- [x] 900/768/600pt and every row breakpoint produce 5...1 rows with no overlap or clipping; 1440x620 is 7x5 and 1440x496 is 7x4.
- [x] Folder overlay derives both axes from its actual clip viewport, never exceeds 35 items per page, and preserves/clamps its visual page across reload and resize.
- [x] Visual resize/reprojection preserves flattened stable IDs, selection and current-page clamp and performs zero storage writes.
- [x] Main grid delegate is the VC-retained `AppGridInteractionCoordinator`,
  never the grid or an internal proxy; all old grid interaction callbacks and
  dependencies are absent, real delegate selection/drag wiring is tested, and
  programmatic selection emits no business callback.
- [x] Keyboard mode/query remain identical; first character is present; only actually handled visible keyDown events are swallowed.
- [x] Same-page, cross-page, empty append, existing-folder, drop-to-create, folder reorder and drag-out all persist after reload/reopen.
- [x] App-on-app hover at 0.8s changes preview only; release is the sole commit point; nested folders are rejected.
- [x] Any layout failure reloads committed state, shows exactly `无法更新布局，请重试`, logs no underlying SQLite description and retries zero times.
- [x] Every SQLite connection operation uses one serial queue; every transaction boundary is checked; rollback failure preserves both errors, invalidates and closes the connection.
- [x] Empty persisted layouts keep exactly one page; overflow creates pages; every other empty page is deleted; all ordering is dense and row-major.
- [x] Successful initial/incremental scan reloads an already-loaded VC once, never forces an unloaded view, and uses the target display's real capacity.
- [x] Tests never change real Dock plist, login items, accessibility settings, event taps, local monitors, status items or user databases; the one real FSEvents test watches and cleans only its UUID temporary directory.
- [x] `Tests/**/*.swift` contains zero legacy framework symbols, skip APIs and fixed waits; 9 files / 15 old cases / 261 methods are represented by one-to-one migration reports and Swift Testing discovery.
- [x] All five wall-clock measurements assert median and p95 with `ContinuousClock`, deterministic input and no conditional enablement, retry, threshold widening or skip; the sixth performance test proves no repeated disk write.
- [x] `scripts/test-release.sh` invokes the shared `scripts/run-with-timeout.sh`
  self-tests, then protects all three discovery commands, three full serial
  suites and the release build with that same implementation; it verifies six
  performance pass lines per log and exits 0 without timeout, signal, hidden
  warnings or residual test processes.
- [x] README and all three design documents match observed production behavior; progress evidence records actual commits/counts/summaries/build/artifact path and unresolved P1/P2 findings remain explicitly open.

## Stop Conditions

- Stop the current task when its new test does not fail for the expected reason; fix the test before production code.
- Stop on any unexpected pre-existing suite failure, compiler diagnostic outside the task's files, or overlapping user edit; do not broaden the diff or revert user work.
- Stop any migration when discovery count, explicit mapping rows, assertion semantics, actor isolation or tolerance count differs from its recorded baseline; do not delete/skip/rename away the discrepancy.
- Stop after Task 3R if the run lacks a complete Swift Testing summary, reports
  a signal, leaves a test process alive, adds an unregistered failure/skip ID,
  or increases the registered baseline count. The registered Task 3R failures
  and skips are temporary execution evidence, not accepted release outcomes.
- Stop after Task 21 or any release-gate run that reports any failure, skip,
  signal, incomplete summary or residual test process.
- Stop on any SQLite fault test that cannot prove the complete persisted snapshot; a thrown error alone is insufficient.
- Stop on rollback failure if code reads or reuses the invalidated connection; close it and prove state only through a new file-backed instance.
- Stop on a performance failure and collect `/usr/bin/sample` evidence for the test process; optimize the measured path. Never skip, retry, condition or relax the threshold.
- Stop the release gate on the first nonzero exit, signal, timeout or residual process. Do not continue to later passes or release build.
- Do not mark P0 complete until Task 23's gate exits 0 and the fresh log shows `PerformanceTests` ran in all three passes.
