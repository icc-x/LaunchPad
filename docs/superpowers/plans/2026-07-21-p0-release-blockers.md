# LaunchPad P0 Readiness Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in the current `release-readiness` branch. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 P0-1 至 P0-6，并按已确认设计交付动态网格、完整原子拖放、真实键盘入口、首次扫描刷新和始终启用墙钟断言的可重复发布门禁。

**Architecture:** 保持 AppKit + Controller + Protocol + SQLite 分层。页面展示由稳定顶层全局顺序投影；拖放通过 `LayoutDropIntent` 和单一 `LayoutMutating` 入口在 SQLite `BEGIN IMMEDIATE` 事务中提交；网格由真实 viewport 产生 `GridMetrics`；UI 只在 COMMIT 成功后 reload。

**Tech Stack:** Swift 6.0、Swift Testing、XCTest、AppKit、SQLite3、Swift Package Manager、zsh。

**Design:** `docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md`

## Global Constraints

- 平台保持 `macOS 14.0+`，Swift tools version 保持 `6.0`，不增加第三方依赖，不修改数据库 schema。
- 本计划的成功状态仅为 **P0 readiness gate 通过**，不是正式发布授权；禁止据此打发布 tag、生成分发包或宣称项目已满足上线条件。正式分发前必须另行关闭剩余 P1/P2，并完成 release warning、CI、Developer ID、hardened runtime、notarization、stapling、`codesign` 与 Gatekeeper 独立验证。
- 当前分支必须是 `release-readiness`；不得修改或恢复工作区中与本计划无关的用户变更。
- 全程 TDD：每个行为先增加最小失败测试并实际确认 RED，再写最小生产实现并确认 GREEN。
- 所有数据库测试使用 `:memory:` 或 `/tmp` 独立文件；禁止访问用户数据库。
- 禁止测试修改真实 Dock plist、登录项、辅助功能设置、全局热键或系统设置。
- 墙钟性能断言始终启用；禁止 `.enabled(if:)`、环境变量或 `--skip PerformanceTests`。
- 拖放只允许一个写入口：`LaunchPadViewController -> LayoutMutating`。`FolderController` 仅保留重命名，不保留旧的多 CRUD 布局写路径。
- 页面空白落点必须转换为稳定 `ItemPlacement.afterItem(itemID:)`；禁止把 `visualPageIndex` 写入领域 intent。
- 文件夹禁止嵌套；新文件夹 children 保持原顶层相对顺序；0/1 child 文件夹按设计删除或解散。
- `StorageManager` 的读取、写入、事务和关闭统一使用单一串行 `databaseQueue`。
- 每个任务只提交任务列出的文件，不顺手清理无关 warning、历史计划或 P1/P2。
- 每个任务结束时整个 package 和 test target 必须可编译；`--filter` 只减少执行用例，不允许把尚未迁移的调用点留到后续任务。
- 每条 focused 命令必须匹配至少一个明确命名的 RED/GREEN 测试；零匹配退出 0 视为门禁失败。
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
- `Sources/LaunchPad/Views/TransientMessageView.swift`：非阻塞、可访问的固定错误提示。

### Modified production files

- `Sources/LaunchPad/Utilities/GridLayoutCalculator.swift`：真实 viewport、动态行数和完整 metrics。
- `Sources/LaunchPad/Views/AppGridFlowLayout.swift`：显式 row-major、一 section 一屏和真实 snap。
- `Sources/LaunchPad/Views/AppGridCollectionView.swift`：单一 metrics、稳定落点、零乐观写入。
- `Sources/LaunchPad/Views/AppIconCell.swift`、`FolderCell.swift`：尺寸重配置、folder preview 和安全删除入口。
- `Sources/LaunchPad/Views/PageScrollView.swift`：显式 page width/count 和页码回调。
- `Sources/LaunchPad/Views/FolderOverlayView.swift`：实际 clip 容量分页、文件夹内重排和拖出。
- `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`：投影、唯一领域写入口、错误反馈。
- `Sources/LaunchPad/Controllers/DragController.swift`：纯拖拽状态、方向 timer 和 hover preview。
- `Sources/LaunchPad/Controllers/KeyboardNavigator.swift`：真实 search query 状态。
- `Sources/LaunchPad/Controllers/FolderController.swift`：移除非原子布局 CRUD，只保留 rename。
- `Sources/LaunchPad/App/HotkeyManager.swift`、`AppDelegate.swift`：真实 monitor 链、扫描刷新和安全系统边界。
- `Sources/LaunchPad/Services/AppScanner.swift`：可观察扫描写入结果与只读排除列表注入。
- `Sources/LaunchPad/Services/FileWatcher.swift`：显式 FSEvent 生命周期。
- `Sources/LaunchPad/Storage/StorageManager.swift`：单队列、事务和 `LayoutMutating`。
- `Sources/LaunchPadProtocols/Protocols.swift`：新增独立 `LayoutMutating` 协议。
- `scripts/test-release.sh`：唯一发布测试入口。

### New test files

- `Tests/LaunchPadTests/Services/LayoutProjectionTests.swift`
- `Tests/LaunchPadTests/Storage/LayoutDomainStateTests.swift`
- `Tests/LaunchPadTests/Storage/StorageManagerLayoutMutationTests.swift`
- `Tests/LaunchPadTests/Storage/StorageManagerScanBatchTests.swift`
- `Tests/LaunchPadTests/Views/TransientMessageViewTests.swift`

### Existing tests synchronized by this plan

- `Tests/LaunchPadTests/Utilities/GridLayoutCalculatorTests.swift`
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

- [ ] **Step 1: Add RED tests for columns, row breakpoints, clamping and invalid input**

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

- [ ] **Step 2: Run the new tests and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter GridLayoutCalculatorTests
```

Expected: compile failure because `GridMetrics` and `calculate(viewportSize:)` do not exist.

- [ ] **Step 3: Add the exact metrics types and calculator**

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

- [ ] **Step 4: Run calculator tests and confirm GREEN**

Run the Step 2 command.

Expected: all old width tests and new viewport tests pass.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Write projection RED tests**

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

- [ ] **Step 2: Run and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LayoutProjectionTests
```

Expected: compile failure because `LayoutProjection` does not exist.

- [ ] **Step 3: Add the pure projection implementation**

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

- [ ] **Step 4: Add missing-child and immutability cases, then run GREEN**

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

- [ ] **Step 5: Commit**

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
- Compatibility: keep `applyGridParameters(_:)` and `scrollToPage(_:pageWidth:)` until Tasks 4-5 migrate current callers; the adapters must delegate to the new geometry and paging state rather than retain FlowLayout behavior. Before Task 5 explicitly configures paging, the legacy scroll adapter derives page count from `documentView` width so page-control navigation does not regress; an explicit one-page configuration must never be overwritten by that fallback.

- [ ] **Step 1: Replace both obsolete FlowLayout suites with real 2/3/5-row and multi-section RED tests**

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
```

- [ ] **Step 2: Add PageScrollView RED tests**

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

- [ ] **Step 3: Run and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridFlowLayoutTests|PageScrollViewTests'
```

Expected: old layout collapses all y values, multi-section width is not page aligned, and PageScrollView lacks configuration APIs.

- [ ] **Step 4: Replace `AppGridFlowLayout` with explicit cached item frames**

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
        let viewport = CGSize(
            width: collectionView.bounds.width > 0
                ? collectionView.bounds.width : fallbackWidth,
            height: collectionView.bounds.height > 0
                ? collectionView.bounds.height : fallbackHeight
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

- [ ] **Step 5: Add explicit PageScrollView configuration**

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

- [ ] **Step 6: Run layout and paging tests GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridFlowLayoutTests|PageScrollViewTests'
```

Expected: 2/3/5 rows are distinct, two sections are exactly two pages, the document frame expands and shrinks with section count, and paging callbacks/clamps pass without showing a real window.

- [ ] **Step 7: Commit**

```bash
git add Sources/LaunchPad/Views/AppGridFlowLayout.swift \
  Sources/LaunchPad/Views/PageScrollView.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Tests/LaunchPadTests/Views/ViewLayerTests.swift \
  Tests/LaunchPadTests/Views/PageScrollViewTests.swift
git commit -m "fix: use explicit row-major paged geometry"
```

---

### Task 4: Make Grid Cells and Accessibility Consume One Metrics Object

**Files:**
- Modify: `Sources/LaunchPad/Views/AppIconCell.swift:19-20,192-218`
- Modify: `Sources/LaunchPad/Views/FolderCell.swift:24-26,63-152`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift:25-45,99-205,209-282`
- Modify: `Sources/LaunchPad/Views/DiffableDataSourceBuilder.swift:8-49`
- Modify: `Tests/LaunchPadTests/Views/AppIconCellTests.swift`
- Modify: `Tests/LaunchPadTests/Views/FolderCellTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift`

**Interfaces:**
- Consumes: Task 1 `GridMetrics`, Task 3 layout API.
- Produces: exact cell reconfiguration, section-aware accessibility, selection by stable ID and paged search snapshots.

- [ ] **Step 1: Add RED tests for 96pt reconfiguration, paged search and section-aware rows**

Add `import Testing` to `AppIconCellTests.swift`, `FolderCellTests.swift`,
`AppGridCollectionViewTests.swift` and `DiffableDataSourceBuilderTests.swift`
before using `@Test`/`#expect`; keep their existing XCTest imports and
lifecycle methods. The top of each file must contain:

```swift
import Testing
import XCTest
```

Add these exact assertions; the read-only observability properties are implemented in Step 3, so tests never reach into private constraints:

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
func folderCellReconfiguresThumbnailGrid() {
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
    #expect(cell.configuredThumbnailSizes == Array(
        repeating: (CGFloat(96) - 4) / 3,
        count: 18
    ))
}
```

Use this exact section-aware input in the accessibility test:

```swift
let indexPaths = [
    [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)],
    [IndexPath(item: 0, section: 1)],
]
let rows = collectionView.buildAccessibilityRows(
    itemIndexPathsBySection: indexPaths,
    columns: 2
)
#expect(rows.count == 2)
#expect(requestedIndexPaths == indexPaths.flatMap { $0 })

let noRows = collectionView.buildAccessibilityRows(
    itemIndexPathsBySection: indexPaths,
    columns: 0
)
#expect(noRows.isEmpty)
```

Add stable selection and paged-search tests with exact section assertions:

```swift
@Test("稳定 ID 在重新分段后解析到新 section")
@MainActor
func stableIDSelectionResolvesReprojectedSection() {
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

    #expect(collectionView.selectItem(id: items[4].id) == IndexPath(item: 2, section: 1))
}

@Test("搜索结果视觉分页产生多个 search page sections")
func searchResultPagesProduceMultipleSections() {
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
    #expect(snapshot.sectionIdentifiers.allSatisfy {
        snapshot.itemIdentifiers(inSection: $0).count <= 4
    })
}
```

- [ ] **Step 2: Run focused suites and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppIconCellTests|FolderCellTests|AppGridCollectionViewTests|DiffableDataSourceBuilderTests'
```

- [ ] **Step 3: Add exact metrics, constraint storage and reconfiguration APIs**

In `AppGridCollectionView` replace `currentIconSize` with:

```swift
private(set) var gridMetrics: GridMetrics?

public func applyGridMetrics(_ metrics: GridMetrics) {
    guard gridMetrics != metrics else { return }
    gridMetrics = metrics
    (collectionViewLayout as? AppGridFlowLayout)?.applyGridMetrics(metrics)
}

@available(*, deprecated, message: "Use applyGridMetrics(_:)")
public func updateLayout(screenWidth: CGFloat) {
    let height = bounds.height > 0 ? bounds.height : 620
    applyGridMetrics(GridLayoutCalculator.calculate(
        viewportSize: CGSize(width: screenWidth, height: height)
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
    constraint.constant = -CGFloat(rowFromBottom) * (thumbnailSize + thumbnailSpacing)
}
```

Pass `gridMetrics?.iconSize ?? 64` in both `.app` and `.group` cell configuration branches.

- [ ] **Step 4: Make reload reconfigure existing IDs, paginate search and keep rows section-aware**

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

Change `animateEntrance()` to `guard let columns = gridMetrics?.columns else { return }`; remove its `calculate(screenWidth:)` call. Build `accessibilityRows()` from snapshot sections and `diffableDataSource.indexPath(for:)`, then implement the row helper exactly:

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

Add `var onSelectionChanged: ((PageItem?) -> Void)?`. In `didSelectItemsAt`, remove `deselectAll(nil)`, resolve the item, then call `onSelectionChanged?(item)` before `onItemSelected?(item)`. Implement stable selection:

```swift
@discardableResult
func selectItem(id: Int64?) -> IndexPath? {
    guard let id,
          let item = diffableDataSource.snapshot().itemIdentifiers.first(
            where: { $0.id == id }
          ),
          let indexPath = diffableDataSource.indexPath(for: item) else {
        deselectAll(nil)
        return nil
    }
    selectItems(at: [indexPath], scrollPosition: [])
    return indexPath
}
```

- [ ] **Step 5: Run focused suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppIconCellTests|FolderCellTests|AppGridCollectionViewTests|DiffableDataSourceBuilderTests|DiffableDataSourceTests'
```

- [ ] **Step 6: Commit**

```bash
git add Sources/LaunchPad/Views/AppIconCell.swift \
  Sources/LaunchPad/Views/FolderCell.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/DiffableDataSourceBuilder.swift \
  Tests/LaunchPadTests/Views/AppIconCellTests.swift \
  Tests/LaunchPadTests/Views/FolderCellTests.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
  Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift
git commit -m "fix: synchronize grid cells and accessibility metrics"
```

---

### Task 5: Reproject the View Controller on Real Viewport Changes

**Files:**
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift:15-20,58-67,143-191,285-381,607-651`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Integration/IntegrationTests.swift:113-124`

**Interfaces:**
- Consumes: Tasks 1-4.
- Consumes later: Task 20 reloads this controller after scan; first-scan storage capacity remains Task 20's responsibility.
- Produces: `gridMetrics`, current-mode `visualPages`, stable selection and synchronized page control/scroll/keyboard/accessibility without storage writes.

- [ ] **Step 1: Add viewport resize and active-search RED tests**

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

- [ ] **Step 2: Run focused VC tests and confirm RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LaunchPadViewControllerTests
```

- [ ] **Step 3: Add the observable state and viewport entry**

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

- [ ] **Step 4: Centralize normal/search projection, page clamp and selection restore**

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
collectionView.onSelectionChanged = { [weak self] item in
    self?.selectedItemID = item?.id
}
scrollView.onPageChanged = { [weak self] page in
    guard let self else { return }
    pageControlViewModel.currentPage = page
    pageControl.update()
}
```

- [ ] **Step 5: Make navigation and keyboard use visual pages and current columns**

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

At the start of `handleItemSelection(_:)`, call `_ = selectItem(id: item.id)`; this closes the mouse and folder-overlay path through the same state/page synchronization used by keyboard selection. `reloadProjectedLayout` already calls this same helper, so no second manual selection state exists.

Finally, make `accessibilityRows()` use `gridMetrics.columns` and the same snapshot section/index paths from Task 4. The test `resizeSynchronizesKeyboardAndAccessibilityRows` must assert the 4-row metrics, a Down move by exactly 7 flattened items, the resolved selection section, and accessibility row count `visualPages.reduce(0) { $0 + ceilDiv($1.count, 7) }` using integer arithmetic `($1.count + 6) / 7`.

- [ ] **Step 6: Update integration expectations and run the grid regression**

Update the fixed 1440-width integration test to pass `CGSize(width: 1440, height: 620)` and assert 7x5. Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'GridLayoutCalculatorTests|LayoutProjectionTests|AppGridFlowLayoutTests|PageScrollViewTests|AppGridCollectionViewTests|LaunchPadViewControllerTests|IntegrationTests'
```

Expected: all dynamic grid, page geometry, resize and stable selection tests pass.

- [ ] **Step 7: Commit**

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

- [ ] **Step 1: Add state mutation RED tests**

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

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter KeyboardNavigatorTests
```

Expected: first character leaves mode idle and Delete does not shorten query.

- [ ] **Step 3: Replace both state entry methods**

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

- [ ] **Step 4: Run the full three-mode suite GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter KeyboardNavigatorTests
```

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Replace the reversed repeated-enter test**

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

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter charactersBuildCompleteQuery
```

Expected: the search field omits `s` and the action sequence is wrong.

- [ ] **Step 3: Consume the associated initial query**

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

- [ ] **Step 4: Run VC and debounce regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'LaunchPadViewControllerTests|SearchDebounceTests'
```

- [ ] **Step 5: Commit**

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
- Consumes: `onKeyDown: (NSEvent) -> NSEvent?`.
- Produces: callback `nil` is returned to AppKit unchanged for every key type.
- Produces: idempotent `registerLocalMonitor()` with injectable install/remove boundaries.

- [ ] **Step 1: Replace the special-key bypass test with RED entry tests**

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

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'localMonitorForwardsSpecialKeysAndNil|localMonitorWithoutCallbackReturnsOriginal|localMonitorRegistrationIsIdempotent'
```

- [ ] **Step 3: Make the handler optional-result preserving and idempotent**

```swift
var localMonitorHandler: ((NSEvent) -> NSEvent?)?
var localMonitorInstaller: (@escaping (NSEvent) -> NSEvent?) -> Any? = { handler in
    NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown, .flagsChanged],
        handler: handler
    )
}
var localMonitorRemover: (Any) -> Void = { NSEvent.removeMonitor($0) }

public init() {
    accessibilityChecker = HotkeyManager.defaultAccessibilityCheck
    localMonitorHandler = { [weak self] event in
        guard let self else { return event }
        return self.handleLocalMonitorEvent(event)
    }
}

public func registerLocalMonitor() {
    guard localMonitor == nil, let localMonitorHandler else { return }
    localMonitor = localMonitorInstaller(localMonitorHandler)
}

func handleLocalMonitorEvent(_ event: NSEvent) -> NSEvent? {
    guard let onKeyDown else { return event }
    return onKeyDown(event)
}

public func unregisterLocalMonitor() {
    guard let localMonitor else { return }
    localMonitorRemover(localMonitor)
    self.localMonitor = nil
}
```

- [ ] **Step 4: Run the complete HotkeyManager suite and verify process exit**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter HotkeyManagerTests
```

Every test that installs a real local monitor must use `defer { manager.unregisterLocalMonitor() }`.

- [ ] **Step 5: Commit**

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
- Consumes: Task 8 optional monitor result and Tasks 6-7 keyboard APIs.
- Produces: handled keyDown returns `nil`; hidden/unmapped/flagsChanged returns original event.
- Rule: suppression is exactly `Action != .ignored`; mapping a key code is not proof that the current mode handled it.

- [ ] **Step 1: Add real monitor-chain RED tests and a safe URL boundary**

Add to AppDelegate:

```swift
var workspaceURLOpener: (URL) -> Void = { url in
    _ = NSWorkspace.shared.open(url)
}
```

Set it to `{ _ in }` in the common test factory. Every test below calls `HotkeyManager.localMonitorHandler`, not AppDelegate's closure directly.

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

- [ ] **Step 2: Run entry tests and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'localMonitorVisibleHandledSpecialKeyReturnsNil|localMonitorVisibleIgnoredSpecialKeyReturnsOriginal|localMonitorVisibleCharactersBuildSearchAndReturnNil|localMonitorFlagsChangedReturnsOriginal|localMonitorUnknownEmptyCharacterReturnsOriginal|localMonitorHiddenReturnsOriginal|localMonitorMissingViewControllerReturnsOriginal|localMonitorUnloadedViewControllerReturnsOriginal'
```

- [ ] **Step 3: Replace the callback with handled-only routing**

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

Replace the direct `NSWorkspace.shared.open` call with `workspaceURLOpener(url)`.

- [ ] **Step 4: Run keyboard entry regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'KeyboardNavigatorTests|LaunchPadViewControllerTests|HotkeyManagerTests|AppDelegateTests'
```

Expected: process exits 0 and does not open System Settings.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Add RED protocol and mock tests**

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

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter ProtocolTests
```

- [ ] **Step 3: Create the exact domain contracts**

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

- [ ] **Step 4: Run protocol tests GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter ProtocolTests
```

Expected: `ProtocolTests` exits 0 and the mutator success/failure plus placement assertions pass; Task 11 later supplies exhaustive six-intent behavior coverage.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Write RED tests for all six intents and page reconstruction**

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

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LayoutDomainStateTests
```

- [ ] **Step 3: Add the complete domain implementation**

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

- [ ] **Step 4: Run all domain tests GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter LayoutDomainStateTests
```

Expected: all six intent branches, folder item 36, owning-folder anchor, and all page-plan branches pass.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Add transaction and serialization RED tests**

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

- [ ] **Step 2: Run StorageManager tests and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter StorageManager
```

Expected: the command matches the file-level transaction tests plus every named `StorageManager*Tests` suite; verify the test runner reports at least the four new tests before accepting RED.

- [ ] **Step 3: Create the checked SQLite driver and transaction runner**

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

- [ ] **Step 4: Replace both queues and initialize the driver**

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

- [ ] **Step 5: Route every existing public method through `withDatabase`**

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

- [ ] **Step 6: Extend stable storage errors**

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

- [ ] **Step 7: Run storage and null-field suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter StorageManager
```

Expected suites include `StorageManagerTests`, `StorageManagerAdvancedTests`, `StorageManagerUpdateTests`, `StorageManagerFetchImageNullBlobTests`, and `StorageManagerFetchAllItemsNullFieldsTests`; command exit 0 is required.

- [ ] **Step 8: Commit**

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

- [ ] **Step 1: Add top-level persistence RED tests**

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

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter StorageManagerLayoutMutationTests
```

- [ ] **Step 3: Add the complete persisted snapshot and transaction-local reader**

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

- [ ] **Step 4: Add checked page/item writers and resolved page persistence**

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

- [ ] **Step 5: Add exact post-write invariant verification**

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

- [ ] **Step 6: Implement the atomic top-level entry**

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

- [ ] **Step 7: Run layout mutation suite GREEN and storage regression**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainState'
```

Expected: all real `StorageManager*` suites and `LayoutDomainStateTests` execute and exit 0.

- [ ] **Step 8: Commit**

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

- [ ] **Step 1: Add complete folder RED tests**

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

- [ ] **Step 2: Run and confirm RED**

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

- [ ] **Step 3: Add checked folder insertion inside the transaction**

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

- [ ] **Step 4: Add exhaustive folder persistence to `apply`**

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

- [ ] **Step 5: Add `/tmp` reopen proofs for commit and rollback failure**

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

- [ ] **Step 6: Replace old non-atomic integration expectations**

Keep `storageManager_deleteGroup_cascadeDelete` as the low-level SQLite behavior proof. Delete only the old `folderController_createFolder_itemsInFolder` and `folderController_autoDissolve` tests at `IntegrationTests.swift:258-315`; Task 14 Step 1 and Step 5 replace them with atomic round trips. Do not delete `FolderController.renameFolder` tests because Task 19 retains rename.

- [ ] **Step 7: Run folder, storage and integration GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainState|IntegrationTests'
```

Expected: every `StorageManager*` suite, `LayoutDomainStateTests`, and `IntegrationTests` executes and exits 0.

- [ ] **Step 8: Commit**

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
- Modify: `Sources/LaunchPad/Services/SearchDebouncer.swift`
- Modify: `Sources/LaunchPadProtocols/Protocols.swift:92-98`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift:150-176`
- Modify: `Tests/LaunchPadTests/Controllers/DragControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Views/CollectionViewDragTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Modify: `Tests/LaunchPadTests/Models/ProtocolTests.swift:47-50`

**Interfaces:**
- Consumes: Task 10 `ItemPlacement`, `ItemType` and stable IDs.
- Produces: immutable `DragSession`, directional edge timer, preview-only app hover, idempotent cleanup and a single-work-item `DispatchQueueScheduler` that Task 21 may safely reuse.
- Removes in the same commit: `currentOrder`, `pendingCrossPageMove`, `beginEditing`, `simulateReorder`, `onCreateGroup`, `handleCreateGroup(targetId:)` and the `ItemWriting` constructor dependency.
- Preserves: existing long-press idle/jiggling/dragging transitions; `handleCancel()` remains as a compatibility alias for edit-mode callers and delegates to `cancelDrag()` without writing.

- [ ] **Step 1: Replace obsolete reorder tests with RED session and timer tests**

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

@Test("重复 schedule 取消旧任务，scheduler 释放时取消剩余任务")
func schedulerReplacementAndDeinitCancelPendingWork() {
    var first: DispatchWorkItem?
    var second: DispatchWorkItem?
    weak var weakScheduler: DispatchQueueScheduler?
    do {
        let scheduler = DispatchQueueScheduler()
        weakScheduler = scheduler
        scheduler.workItemObserver = { item in
            if first == nil { first = item } else { second = item }
        }
        scheduler.schedule(after: 60) {}
        scheduler.schedule(after: 60) {}
        #expect(first?.isCancelled == true)
        #expect(second?.isCancelled == false)
    }

    #expect(weakScheduler == nil)
    #expect(second?.isCancelled == true)
}
```

Retain explicit long-press RED cases for `< 0.5s`, `0.5s/<=10pt`, `>10pt`, release, cancel and repeated state entry. Delete every assertion about `currentOrder`, `reorderItems` and synthetic cross-page IDs.

- [ ] **Step 2: Run the new tests and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DragControllerTests|CollectionViewDragTests'
```

Expected: compile RED for missing `DragSession`, `DragPageDirection`, `beginDrag`, `finishDrag` and `cancelDrag`.

- [ ] **Step 3: Make Scheduler explicitly MainActor-bound**

Replace the protocol:

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

Replace `DispatchQueueScheduler` with a main-queue implementation; do not retain its background queue or lock:

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

        deinit {
            item?.cancel()
        }
    }

    private let pendingWork = PendingWork()

    // Internal test observation only; production leaves this nil.
    var workItemObserver: ((DispatchWorkItem) -> Void)?

    public init() {}

    public func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        cancelPending()
        let workItem = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        pendingWork.replace(with: workItem)
        workItemObserver?(workItem)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + interval,
            execute: workItem
        )
    }

    public func cancelPending() {
        pendingWork.cancel()
    }
}
```

Mark `MockScheduler` `@MainActor`; change its stored closure to `@MainActor @Sendable () -> Void`. `SearchDebouncer` is already `@MainActor`; remove its `nonisolated(unsafe)`/`MainActor.assumeIsolated` bridge and call the captured handler directly inside the scheduled closure. The production scheduler must retain exactly one pending work item: every `schedule` calls `cancelPending()` first, `cancelPending()` clears the reference, and the `@unchecked Sendable` holder cancels the last pending item in its own nonisolated `deinit`. The holder is a narrow ownership adapter: all mutation still occurs through the enclosing MainActor scheduler, and it exists because Swift 6 forbids an actor-isolated `deinit` from touching `DispatchWorkItem?` directly.

The scheduler conformance test must cross the same actor boundary explicitly:

```swift
@Test("MockScheduler 遵循 Scheduler")
@MainActor
func mockScheduler_conformsToScheduler() {
    let scheduler = MockScheduler()
    let value: Scheduler = scheduler
    #expect(value is Scheduler)
}
```

- [ ] **Step 4: Create immutable drag model types**

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

- [ ] **Step 5: Replace DragController persistence with the complete session state machine**

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

- [ ] **Step 6: Migrate every removed API caller in the same task**

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

- [ ] **Step 7: Run complete compile-adjacent regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DragControllerTests|CollectionViewDragTests|SearchDebounceTests|ProtocolTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests|AppDelegateTests'
```

Expected: PASS with no remaining reference to `itemWriter`, `currentOrder`, `pendingCrossPageMove`, `beginEditing`, `simulateReorder` or `onCreateGroup` in DragController callers.

- [ ] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Models/DragSession.swift \
  Sources/LaunchPad/Controllers/DragController.swift \
  Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Sources/LaunchPad/Services/SearchDebouncer.swift \
  Sources/LaunchPadProtocols/Protocols.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift \
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
- Modify: `Sources/LaunchPad/Views/AppIconCell.swift:12-21,31-83,190-218,274-284`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppIconCellTests.swift`

**Interfaces:**
- Consumes: Task 15 `DragSession`, Task 10 `ItemPlacement`.
- Produces: `GridDropDestination`, stable empty anchors, `topLevelPlacement(at:)`, synchronized visual-page state, preview UI and `onDropRequested`.
- Constraint: source/validation/acceptance never mutate a diffable snapshot; only a later COMMIT-triggered VC reload may change it.

- [ ] **Step 1: Add RED tests for source identity, all destinations and immutable snapshots**

Use valid UUID strings in every accepted source fixture. Add these helpers and representative tests:

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

func testPasteboardWriterStartsSessionWithRealSourceIdentity() throws {
    let source = makeApp(id: 10, parentID: 77, ordering: 2)
    loadSnapshot(pages: [[source]])
    let dragController = DragController(scheduler: MockScheduler())
    collectionView.dragController = dragController

    let writer = collectionView.collectionView(
        collectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    )

    XCTAssertNotNil(writer)
    let session = try XCTUnwrap(dragController.session)
    XCTAssertEqual(session.itemID, 10)
    XCTAssertEqual(session.sourceParentID, 77)
    XCTAssertEqual(session.sourceVisualIndex, 0)
}

func testEmptyDropUsesLastVisibleStableID() {
    let items = [makeApp(id: 10), makeApp(id: 20), makeApp(id: 30)]
    loadSnapshot(pages: [items])

    XCTAssertEqual(
        collectionView.emptyPlacement(inVisualPage: 0),
        .afterItem(itemID: 30)
    )
}

func testDropForwardsStableAnchorWithoutChangingSnapshot() {
    let source = makeApp(id: 1)
    let target = makeApp(id: 9, parentID: 200)
    loadSnapshot(pages: [[source], [target]])
    let before = collectionView.diffableDataSource.snapshot().itemIdentifiers
    var received: GridDropDestination?
    collectionView.onDropRequested = { _, destination in
        received = destination
        return true
    }

    XCTAssertTrue(collectionView.performDrop(
        session: DragSession(
            itemID: source.id,
            itemUUID: source.uuid,
            itemType: source.type,
            sourceKind: .topLevel,
            sourceParentID: source.parentId!,
            sourceVisualIndex: 0
        ),
        destination: .placement(.afterItem(itemID: target.id))
    ))

    XCTAssertEqual(received, .placement(.afterItem(itemID: 9)))
    XCTAssertEqual(
        collectionView.diffableDataSource.snapshot().itemIdentifiers,
        before
    )
}

func testVisualPageSetterClampsAndEnablesBothEdgeDirections() {
    loadSnapshot(pages: [[makeApp(id: 1)], [makeApp(id: 2)], [makeApp(id: 3)]])

    collectionView.setCurrentVisualPageIndex(1)

    XCTAssertEqual(collectionView.currentVisualPageIndex, 1)
    XCTAssertTrue(collectionView.canHoverEdge(.backward))
    XCTAssertTrue(collectionView.canHoverEdge(.forward))
}

func testValidateDropUsesVisibleEdgesOnMiddlePage() throws {
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

    let controller = DragController(scheduler: MockScheduler())
    collectionView.dragController = controller
    let session = DragSession(
        itemID: source.id,
        itemUUID: source.uuid,
        itemType: source.type,
        sourceKind: .topLevel,
        sourceParentID: source.parentId!,
        sourceVisualIndex: 0
    )
    controller.beginDrag(session)

    func validate(at localPoint: NSPoint) -> NSDragOperation {
        let info = draggingInfo(
            for: session,
            at: collectionView.convert(localPoint, to: nil)
        )
        var proposed = NSIndexPath(forItem: 0, inSection: 1)
        var operation: NSCollectionView.DropOperation = .on
        return withUnsafeMutablePointer(to: &operation) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                collectionView.collectionView(
                    collectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                        proposedPointer
                    ),
                    dropOperation: operationPointer
                )
            }
        }
    }

    let visible = collectionView.visibleRect
    XCTAssertEqual(
        validate(at: NSPoint(x: visible.minX + 1, y: visible.midY)),
        .generic
    )
    XCTAssertEqual(controller.session?.hoverDestination, .edge(.backward))
    XCTAssertEqual(
        validate(at: NSPoint(x: visible.maxX - 1, y: visible.midY)),
        .generic
    )
    XCTAssertEqual(controller.session?.hoverDestination, .edge(.forward))
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
    pasteboard.setString(session.itemUUID, forType: .string)
    return MockDraggingInfo(pasteboard: pasteboard, location: windowPoint)
}

func testValidateDropConvertsWindowPointForNonZeroViewOrigin() throws {
    let source = makeApp(id: 1)
    let target = makeApp(id: 2, ordering: 1)
    loadSnapshot(pages: [[source, target]])
    let controller = DragController(scheduler: MockScheduler())
    collectionView.dragController = controller
    let session = DragSession(
        itemID: source.id,
        itemUUID: source.uuid,
        itemType: source.type,
        sourceKind: .topLevel,
        sourceParentID: source.parentId!,
        sourceVisualIndex: 0
    )
    controller.beginDrag(session)
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
            collectionView.collectionView(
                collectionView,
                validateDrop: info,
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                    proposedPointer
                ),
                dropOperation: operationPointer
            )
        }
    }

    let resolved = try XCTUnwrap(resolvedPoint)
    XCTAssertEqual(resolved.x, localPoint.x, accuracy: 0.001)
    XCTAssertEqual(resolved.y, localPoint.y, accuracy: 0.001)
}

func testAcceptDropConvertsWindowPointForNonZeroViewOrigin() throws {
    let source = makeApp(id: 1)
    let target = makeApp(id: 2, ordering: 1)
    loadSnapshot(pages: [[source, target]])
    let controller = DragController(scheduler: MockScheduler())
    collectionView.dragController = controller
    let session = DragSession(
        itemID: source.id,
        itemUUID: source.uuid,
        itemType: source.type,
        sourceKind: .topLevel,
        sourceParentID: source.parentId!,
        sourceVisualIndex: 0
    )
    controller.beginDrag(session)
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
    collectionView.onDropRequested = { _, _ in true }
    let localPoint = NSPoint(x: 250, y: 180)
    let info = draggingInfo(
        for: session,
        at: collectionView.convert(localPoint, to: nil)
    )

    XCTAssertTrue(collectionView.collectionView(
        collectionView,
        acceptDrop: info,
        indexPath: IndexPath(item: 1, section: 0),
        dropOperation: .on
    ))
    let resolved = try XCTUnwrap(resolvedPoint)
    XCTAssertEqual(resolved.x, localPoint.x, accuracy: 0.001)
    XCTAssertEqual(resolved.y, localPoint.y, accuracy: 0.001)
}
```

Change the existing `MockDraggingInfo` declaration from `private final class`
to module-internal `final class`; Task 19 reuses it for folder coordinate tests.

The complete branch matrix uses these XCTest method identifiers:

```text
testPasteboardWriter_groupStartsTopLevelSession
testPasteboardWriter_pageSearchMissingParentAndMalformedUUIDReturnNil
testExtractSession_unknownUUIDStaleSourceAndMismatchedActiveSessionReturnNil
testValidateDrop_leftEdgeFirstPageAndRightEdgeLastPageReject
testValidateDrop_leftEdgeMiddlePageArmsBackward
testValidateDrop_rightEdgeMiddlePageArmsForward
testResolveDestination_beforeAfterAndEmptyUseStableIDs
testResolveDestination_appOnAppAndAppOnGroupAreOnItem
testResolveDestination_groupOnAppGroupAndSelfReject
testResolveDestination_staleTargetRejects
testAcceptDrop_callbackFailureKeepsSnapshotUnchanged
testDraggingSessionEndClearsSessionTimerAndPreview
```

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridCollectionViewTests|AppIconCellTests'
```

Expected: compile RED for `GridDropDestination`, page synchronization, placement resolution and preview APIs.

- [ ] **Step 3: Add exact destination and page synchronization APIs**

```swift
public enum GridDropDestination: Sendable, Equatable {
    case placement(ItemPlacement)
    case onItem(itemID: Int64, itemType: ItemType)
}

public var isDragEnabled = true {
    didSet {
        if !isDragEnabled { dragController?.cancelDrag() }
    }
}
public private(set) var currentVisualPageIndex = 0
public var onDropRequested: ((DragSession, GridDropDestination) -> Bool)?

public func setCurrentVisualPageIndex(_ index: Int) {
    let pageCount = diffableDataSource.snapshot().sectionIdentifiers.reduce(into: 0) {
        if case .page = $1 { $0 += 1 }
    }
    currentVisualPageIndex = max(0, min(index, max(0, pageCount - 1)))
}

func canHoverEdge(_ direction: DragPageDirection) -> Bool {
    let pageCount = diffableDataSource.snapshot().sectionIdentifiers.reduce(into: 0) {
        if case .page = $1 { $0 += 1 }
    }
    switch direction {
    case .backward:
        return currentVisualPageIndex > 0
    case .forward:
        return currentVisualPageIndex + 1 < pageCount
    }
}

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

After every `reload`, call `setCurrentVisualPageIndex(currentVisualPageIndex)` so a reduced page count clamps immediately. Task 18 synchronizes this property with the VC/page-scroll source of truth.

- [ ] **Step 4: Build and validate a real top-level source session**

Replace the pasteboard writer with:

```swift
public func collectionView(
    _ collectionView: NSCollectionView,
    pasteboardWriterForItemAt indexPath: IndexPath
) -> NSPasteboardWriting? {
    guard isDragEnabled,
          case .page = diffableDataSource.snapshot().sectionIdentifiers[indexPath.section],
          let item = diffableDataSource.itemIdentifier(for: indexPath),
          item.type != .page,
          let parentID = item.parentId,
          UUID(uuidString: item.uuid) != nil,
          let visualIndex = diffableDataSource.snapshot()
            .itemIdentifiers.firstIndex(of: item) else { return nil }

    dragController?.beginDrag(DragSession(
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
          let value = draggingInfo.draggingPasteboard.string(forType: .string),
          UUID(uuidString: value) != nil,
          let session = dragController?.session,
          session.itemUUID == value,
          diffableDataSource.snapshot().itemIdentifiers.contains(where: {
              $0.id == session.itemID && $0.uuid == value
          }) else { return nil }
    return session
}
```

- [ ] **Step 5: Resolve edges, on-item, before/after and empty deterministically**

Use a center rectangle for `.onItem`; outside it, compare x with the target midpoint. Expose the same placement-only resolver for folder drag-out:

```swift
func resolveGridDestination(at location: NSPoint) -> GridDropDestination? {
    let indexPath: IndexPath?
    if let indexPathResolver {
        indexPath = indexPathResolver(location)
    } else {
        indexPath = indexPathForItem(at: location)
    }
    guard let indexPath,
          let item = diffableDataSource.itemIdentifier(for: indexPath),
          let attributes = collectionViewLayout?
            .layoutAttributesForItem(at: indexPath) else {
        return emptyPlacement(inVisualPage: currentVisualPageIndex).map {
            .placement($0)
        }
    }

    let frame = attributes.frame
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

public func topLevelPlacement(at location: NSPoint) -> ItemPlacement? {
    switch resolveGridDestination(at: location) {
    case .placement(let placement):
        return placement
    case .onItem(let itemID, _):
        let snapshot = diffableDataSource.snapshot()
        guard let item = snapshot.itemIdentifiers.first(where: { $0.id == itemID }),
              let indexPath = diffableDataSource.indexPath(for: item),
              let frame = collectionViewLayout?
                .layoutAttributesForItem(at: indexPath)?.frame else {
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
        dragController?.updateDragHover(.empty)
        return []
    }

    let edgeWidth: CGFloat = 40
    let visibleBounds = collectionView.visibleRect
    if localPoint.x < visibleBounds.minX + edgeWidth {
        guard canHoverEdge(.backward) else {
            dragController?.updateDragHover(.empty)
            return []
        }
        dragController?.updateDragHover(.edge(.backward))
        return .generic
    }
    if localPoint.x > visibleBounds.maxX - edgeWidth {
        guard canHoverEdge(.forward) else {
            dragController?.updateDragHover(.empty)
            return []
        }
        dragController?.updateDragHover(.edge(.forward))
        return .generic
    }

    guard let destination = resolveGridDestination(at: localPoint),
          allows(session: session, destination: destination) else {
        dragController?.updateDragHover(.empty)
        return []
    }
    switch destination {
    case .placement:
        dragController?.updateDragHover(.empty)
    case .onItem(let itemID, let itemType):
        dragController?.updateDragHover(
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
        dragController?.cancelDrag()
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
        dragController?.cancelDrag()
        return false
    }
    return onDropRequested?(session, destination) ?? false
}

override public func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
) {
    dragController?.finishDrag()
}
```

Delete the old `snapshot.deleteItems/insertItems/apply` block completely.

- [ ] **Step 6: Add a visible, reusable folder-creation preview**

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

When assigning `dragController`, bind `onFolderCreationPreviewChanged` to this method. Clear it before replacing controllers and during reload.

- [ ] **Step 7: Run grid, icon and drag suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppGridCollectionViewTests|AppIconCellTests|DragControllerTests|CollectionViewDragTests'
```

Expected: PASS; accepted/rejected drops leave the pre-COMMIT snapshot unchanged, edge direction respects the synchronized page, and preview border visibly toggles.

- [ ] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/AppIconCell.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
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

- [ ] **Step 1: Write deterministic RED tests without a window or sleep**

```swift
@MainActor
final class TransientMessageViewTests: XCTestCase {
    func testShowDisplaysExactTextAndPostsAnnouncement() {
        let sut = TransientMessageView(frame: .zero)
        var announced: String?
        sut.postAnnouncement = { announced = $0 }
        sut.scheduleHide = { _, _ in }

        sut.show(message: "无法更新布局，请重试")

        XCTAssertEqual(sut.message, "无法更新布局，请重试")
        XCTAssertFalse(sut.isHidden)
        XCTAssertEqual(sut.accessibilityLabel(), "无法更新布局，请重试")
        XCTAssertEqual(announced, "无法更新布局，请重试")
    }

    func testRepeatedShowCancelsOldWorkAndReplacesText() throws {
        let sut = TransientMessageView(frame: .zero)
        var workItems: [DispatchWorkItem] = []
        sut.postAnnouncement = { _ in }
        sut.scheduleHide = { _, workItems.append($1) }

        sut.show(message: "first")
        sut.show(message: "second")

        XCTAssertTrue(try XCTUnwrap(workItems.first).isCancelled)
        XCTAssertFalse(try XCTUnwrap(workItems.last).isCancelled)
        XCTAssertEqual(sut.message, "second")
    }

    func testScheduledWorkHidesDeterministically() throws {
        let sut = TransientMessageView(frame: .zero)
        var scheduled: DispatchWorkItem?
        sut.postAnnouncement = { _ in }
        sut.scheduleHide = { _, scheduled = $1 }
        sut.show(message: "error")

        try XCTUnwrap(scheduled).perform()

        XCTAssertNil(sut.message)
        XCTAssertTrue(sut.isHidden)
        XCTAssertEqual(sut.accessibilityLabel(), "")
    }
}
```

- [ ] **Step 2: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter TransientMessageViewTests
```

Expected: compile RED because `TransientMessageView` does not exist.

- [ ] **Step 3: Add the complete NSView initializer, hierarchy and scheduling implementation**

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
    var postAnnouncement: (String) -> Void = { message in
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
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
        postAnnouncement(message)

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

- [ ] **Step 4: Run GREEN and commit**

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
- Modify: `Sources/LaunchPad/Views/FolderOverlayView.swift:11-35`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:12-18,111-160`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadWindowControllerTests.swift`

**Interfaces:**
- Consumes: Task 10 `LayoutMutating`, Task 16 `GridDropDestination`, Task 17 `TransientMessageView`, Task 5 `GridMetrics`/visual paging.
- Produces: one mutation attempt, COMMIT-then-reload, synchronous search triple guard, sanitized structured log and current-page synchronization.
- Constraint: `DataStoring` remains independent from `LayoutMutating`; AppDelegate retains two separately typed references to the same production `StorageManager`.

- [ ] **Step 1: Extend the mutator test double with attempt accounting**

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

- [ ] **Step 2: Add RED mapping, failure, search and page synchronization tests**

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
    let apps = TestDataFactory.makeAppItems(count: 2)
    loadViewWithData(sut, storage: storage, apps: apps)
    sut.viewportSizeProvider = { CGSize(width: 1440, height: 620) }
    sut.viewDidLayout()
    let grid = try #require(firstGrid(in: sut.view))
    let previewCell = AppIconCell()
    _ = previewCell.view
    grid.visibleCellProvider = { indexPath in
        indexPath == IndexPath(item: 1, section: 0) ? previewCell : nil
    }
    let session = makeSession(itemID: apps[0].id, type: .app)
    sut.dragController.beginDrag(session)

    sut.dragController.updateDragHover(
        .item(itemID: apps[1].id, itemType: .app)
    )
    scheduler.advance(by: 0.8)

    #expect(previewCell.isFolderCreationPreviewVisible)
    #expect(mutator.applyAttemptCount == 0)
    #expect(grid.performDrop(
        session: session,
        destination: .onItem(itemID: apps[1].id, itemType: .app)
    ))
    #expect(mutator.applyAttemptCount == 1)
    #expect(mutator.attemptedIntents == [
        .createFolder(
            itemID: apps[0].id,
            targetItemID: apps[1].id,
            title: "New Folder"
        ),
    ])
    #expect(sut.dragController.session == nil)
}
```

Add the mapping matrix as one exhaustive pure-controller test; same-page,
cross-page and empty destinations are all stable placements and therefore must
map identically without page numbers:

```swift
@Test("全部 grid destination 映射稳定 intent 或明确拒绝")
func gridDestinationMappingIsExhaustive() {
    let (sut, _, _) = makeSUT(layoutMutator: MockLayoutMutator())
    let app = makeSession(itemID: 2, type: .app)
    let group = makeSession(itemID: 7, type: .group)

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

In `AppGridCollectionViewTests`, set `isDragEnabled = false`, assert the
pasteboard writer returns nil, then feed a valid active session to both native
validate/accept entries and assert `[]`/`false`, zero callback invocations and
an unchanged snapshot. Re-enable drag and assert the same source is accepted;
this proves search toggles all three boundaries rather than only the writer.

- [ ] **Step 3: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'LaunchPadViewControllerTests|AppGridCollectionViewTests|AppDelegateTests|LaunchPadWindowControllerTests'
```

Expected: compile RED for the new VC initializer, message/log members, AppDelegate mutator property and page synchronization.

- [ ] **Step 4: Retain separate storage and mutator references in AppDelegate**

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

- [ ] **Step 5: Add the VC dependency, transient view and sanitized log event**

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

- [ ] **Step 6: Map grid destinations and bind the only writer**

```swift
func makeGridIntent(
    session: DragSession,
    destination: GridDropDestination
) -> LayoutDropIntent? {
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
collectionView.onDropRequested = { [weak self] session, destination in
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

- [ ] **Step 7: Disable drag synchronously at source, validation and writer boundaries**

Task 19 adds folder delegates, but add `public var isDragEnabled = true` to `FolderOverlayView` now so search code compiles independently. Add:

```swift
private func setDragEnabled(_ enabled: Bool) {
    collectionView.isDragEnabled = enabled
    folderOverlay.isDragEnabled = enabled
    if !enabled { dragController.cancelDrag() }
}
```

Call `setDragEnabled(false)` in `.enterSearchMode` and `.appendToQuery` before scheduling search. Call `setDragEnabled(true)` in `.clearSearch` after `keyboardNavigator.mode` returns idle and in `handleSearch(query: "")`. Keep Task 16 pasteboard/validate guards and `applyDropIntent`'s synchronous `keyboardNavigator.mode` guard.

- [ ] **Step 8: Synchronize currentVisualPageIndex at every navigation entry**

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

- [ ] **Step 9: Update every VC constructor and run regression GREEN**

Pass `MockLayoutMutator` from VC/window test factories and real `layoutMutator` from AppDelegate. Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'LaunchPadViewControllerTests|AppGridCollectionViewTests|AppDelegateTests|LaunchPadWindowControllerTests|TransientMessageViewTests'
```

Expected: PASS; failure has one attempt and zero successful apply, search races make zero attempts, all page paths synchronize, and logs contain no underlying error text.

- [ ] **Step 10: Commit**

```bash
git add Sources/LaunchPad/Controllers/LaunchPadViewController.swift \
  Sources/LaunchPad/Views/AppGridCollectionView.swift \
  Sources/LaunchPad/Views/FolderOverlayView.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift \
  Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift \
  Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift \
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
- Consumes: Task 16 `topLevelPlacement(at:)`, Task 18's only writer/error path, Task 14's atomic folder intents.
- Consumes: the actual folder clip viewport; both axes use the existing 72x80 item geometry and capacity never exceeds the existing maximum of 35.
- Produces: width/height-derived folder rows, columns and capped capacity, one shared open/reload/resize reprojection path, inner and overlay-exterior drop destinations, stable child placement, drag-out, deterministic folder reload, real edit-mode delete control, confirmed safe delete and all lifecycle cleanup.

- [ ] **Step 1: Add RED tests for inner folder and overlay-exterior branches**

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

// In FolderOverlayViewPagingTests.swift, mark the XCTestCase @MainActor,
// retain paginateItems as a pure helper test, and add this fixture/state:
private var pagingOverlay: FolderOverlayView!

override func setUp() {
    super.setUp()
    pagingOverlay = FolderOverlayView(
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

func testMetricsUseActualWidthHeightAndCapAtThirtyFive() {
    let one = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: 96, height: 96)
    )
    XCTAssertEqual(one.columns, 1)
    XCTAssertEqual(one.rows, 1)
    XCTAssertEqual(one.pageCapacity, 1)
    XCTAssertEqual(one.horizontalInset, 12)

    let medium = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: 496, height: 360)
    )
    XCTAssertEqual(medium.columns, 6)
    XCTAssertEqual(medium.rows, 4)
    XCTAssertEqual(medium.pageCapacity, 24)
    XCTAssertEqual(medium.horizontalInset, 12)
    XCTAssertEqual(
        FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(
                width: CGFloat(496).nextDown,
                height: 360
            )
        ).pageCapacity,
        20
    )
    XCTAssertEqual(
        FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(
                width: 496,
                height: CGFloat(360).nextDown
            )
        ).pageCapacity,
        18
    )

    let capped = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: 800, height: 624)
    )
    XCTAssertEqual(capped.columns, 5)
    XCTAssertEqual(capped.rows, 7)
    XCTAssertEqual(capped.pageCapacity, 35)
    XCTAssertEqual(capped.horizontalInset, 204)

    let invalid = FolderOverlayView.folderGridMetrics(
        forViewportSize: CGSize(width: .nan, height: .infinity)
    )
    XCTAssertEqual(invalid.columns, 1)
    XCTAssertEqual(invalid.rows, 1)
    XCTAssertEqual(invalid.pageCapacity, 1)
    XCTAssertTrue(invalid.horizontalInset.isFinite)
}

func testOpenUsesActualFolderViewportCapacity() {
    pagingOverlay.folderViewportSizeProvider = {
        CGSize(width: 500, height: 400)
    }
    pagingOverlay.openFolder(
        item: pagingFolder(),
        childItems: TestDataFactory.makeAppItems(count: 41),
        iconCache: nil
    )

    XCTAssertEqual(pagingOverlay.currentPageCapacity, 24)
    XCTAssertEqual(sectionCounts(pagingOverlay), [24, 17])
    XCTAssertEqual(pagingOverlay.currentVisualPageIndex, 0)
}

func testReloadRepaginatesAndClampsCurrentPage() {
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
    XCTAssertEqual(pagingOverlay.currentVisualPageIndex, 2)

    pagingOverlay.reloadChildren(
        TestDataFactory.makeAppItems(count: 25)
    )

    XCTAssertEqual(pagingOverlay.currentPageCapacity, 24)
    XCTAssertEqual(sectionCounts(pagingOverlay), [24, 1])
    XCTAssertEqual(pagingOverlay.currentVisualPageIndex, 1)
    XCTAssertEqual(
        pagingOverlay.emptyPlacement(inVisualPage: 1),
        .afterItem(itemID: 25)
    )
}

func testResizeRepaginatesAndClampsCurrentPage() {
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
    XCTAssertEqual(pagingOverlay.currentVisualPageIndex, 2)

    viewport = CGSize(width: 500, height: 624)
    pagingOverlay.layout()

    XCTAssertEqual(pagingOverlay.currentPageCapacity, 35)
    XCTAssertEqual(sectionCounts(pagingOverlay), [35, 25])
    XCTAssertEqual(pagingOverlay.currentVisualPageIndex, 1)
    XCTAssertEqual(
        pagingOverlay.emptyPlacement(inVisualPage: 1),
        .afterItem(itemID: 60)
    )
}

// FolderOverlayViewTests keeps its historical 35-item expectations on one
// deterministic viewport that reaches the cap; 500x400 drag tests override it.
override func setUp() {
    super.setUp()
    overlay = FolderOverlayView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 700)
    )
    overlay.folderViewportSizeProvider = {
        CGSize(width: 800, height: 624)
    }
}

func testFolderSourceCapturesCurrentFolderIdentity() throws {
    let folder = makeFolder(id: 50)
    let child = makeApp(id: 10, parentID: 50)
    overlay.openFolder(item: folder, childItems: [child], iconCache: nil)
    overlay.dragController = DragController(scheduler: MockScheduler())

    let writer = overlay.collectionView(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    )

    XCTAssertNotNil(writer)
    let session = try XCTUnwrap(overlay.dragController?.session)
    XCTAssertEqual(session.sourceKind, .folderChild)
    XCTAssertEqual(session.sourceParentID, 50)
}

func testFolderEmptyOnSecondVisualPageUsesLastStableChildID() {
    let children = (1...40).map { makeApp(id: Int64($0), parentID: 50) }
    overlay.folderViewportSizeProvider = {
        CGSize(width: 500, height: 400)
    }
    overlay.openFolder(item: makeFolder(id: 50), childItems: children, iconCache: nil)

    XCTAssertEqual(
        overlay.emptyPlacement(inVisualPage: 1),
        .afterItem(itemID: 40)
    )
}

func testOverlayExteriorDropUsesResolvedTopLevelPlacement() {
    let session = makeFolderChildSession(itemID: 10, folderID: 50)
    overlay.dragController = DragController(scheduler: MockScheduler())
    overlay.dragController?.beginDrag(session)
    overlay.topLevelPlacementResolver = { _ in .beforeItem(itemID: 99) }
    var received: FolderDropDestination?
    overlay.onDropRequested = { _, destination in
        received = destination
        return true
    }

    XCTAssertTrue(overlay.performExteriorDrop(at: NSPoint(x: 10, y: 10)))
    XCTAssertEqual(received, .outside(.beforeItem(itemID: 99)))
}

func testUnresolvedExteriorDropRejectsWithoutCallback() {
    overlay.dragController = DragController(scheduler: MockScheduler())
    overlay.dragController?.beginDrag(makeFolderChildSession())
    overlay.topLevelPlacementResolver = { _ in nil }
    var called = false
    overlay.onDropRequested = { _, _ in called = true; return true }

    XCTAssertFalse(overlay.performExteriorDrop(at: NSPoint(x: 10, y: 10)))
    XCTAssertFalse(called)
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
    pasteboard.setString(session.itemUUID, forType: .string)
    return MockDraggingInfo(pasteboard: pasteboard, location: windowPoint)
}

private func assertSecondVisualPageBlankDrop(
    itemCount: Int,
    expectedAnchorID: Int64
) throws {
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
    XCTAssertEqual(overlay.currentVisualPageIndex, 1)

    let controller = DragController(scheduler: MockScheduler())
    overlay.dragController = controller
    let session = makeFolderChildSession(itemID: 1, folderID: 50)
    controller.beginDrag(session)
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

    var proposed = NSIndexPath(forItem: 0, inSection: 1)
    var operation: NSCollectionView.DropOperation = .before
    let validation = withUnsafeMutablePointer(
        to: &operation
    ) { operationPointer in
        withUnsafeMutablePointer(to: &proposed) { proposedPointer in
            overlay.collectionView(
                overlay.folderCollectionView,
                validateDrop: info,
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                    proposedPointer
                ),
                dropOperation: operationPointer
            )
        }
    }
    XCTAssertEqual(validation, .move)
    XCTAssertTrue(overlay.collectionView(
        overlay.folderCollectionView,
        acceptDrop: info,
        indexPath: IndexPath(item: 0, section: 1),
        dropOperation: .before
    ))
    XCTAssertEqual(
        received,
        .inside(.afterItem(itemID: expectedAnchorID))
    )
    XCTAssertEqual(resolvedPoints.count, 2)
    for point in resolvedPoints {
        XCTAssertEqual(point.x, localPoint.x, accuracy: 0.001)
        XCTAssertEqual(point.y, localPoint.y, accuracy: 0.001)
    }
}

func testSecondVisualPageItem36BlankDropUsesItem36() throws {
    try assertSecondVisualPageBlankDrop(
        itemCount: 36,
        expectedAnchorID: 36
    )
}

func testSecondVisualPageItem40BlankDropUsesItem40() throws {
    try assertSecondVisualPageBlankDrop(
        itemCount: 40,
        expectedAnchorID: 40
    )
}

func testScrollSynchronizesCurrentVisualPageAndBlankAnchor() {
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

    XCTAssertEqual(overlay.currentVisualPageIndex, 1)
    XCTAssertEqual(
        overlay.emptyPlacement(
            inVisualPage: overlay.currentVisualPageIndex
        ),
        .afterItem(itemID: 40)
    )
}

func testExteriorDragEntriesConvertWindowPointForNonZeroOrigin() {
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

    XCTAssertEqual(overlay.draggingEntered(info), .move)
    XCTAssertEqual(overlay.draggingUpdated(info), .move)
    XCTAssertTrue(overlay.prepareForDragOperation(info))
    XCTAssertTrue(overlay.performDragOperation(info))
    XCTAssertEqual(points.count, 4)
    for point in points {
        XCTAssertEqual(point.x, localPoint.x, accuracy: 0.001)
        XCTAssertEqual(point.y, localPoint.y, accuracy: 0.001)
    }
}

func testFolderDraggingSessionEndClearsCancelledSession() {
    let scheduler = MockScheduler()
    let controller = DragController(scheduler: scheduler)
    overlay.dragController = controller
    controller.beginDrag(makeFolderChildSession())
    controller.updateDragHover(.item(itemID: 11, itemType: .app))

    overlay.collectionView(
        overlay.folderCollectionView,
        draggingSession: NSDraggingSession(),
        endedAt: .zero,
        dragOperation: []
    )

    XCTAssertEqual(controller.state, .idle)
    XCTAssertNil(controller.session)
    XCTAssertTrue(scheduler.scheduledActions.isEmpty)
}
```

Add the remaining source and intent branches explicitly:

```swift
func testFolderSourceRejectsGroupAndInvalidChild() {
    let folder = makeFolder(id: 50)
    let group = makeFolder(id: 60)
    let wrongParent = makeApp(id: 10, parentID: 99)
    overlay.openFolder(
        item: folder,
        childItems: [group, wrongParent],
        iconCache: nil
    )
    overlay.dragController = DragController(scheduler: MockScheduler())

    XCTAssertNil(overlay.collectionView(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
    ))
    XCTAssertNil(overlay.collectionView(
        overlay.folderCollectionView,
        pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)
    ))
    XCTAssertNil(overlay.dragController?.session)
}

func testFolderDropRejectsSelfAndCallbackFailure() {
    let session = makeFolderChildSession(itemID: 10, folderID: 50)
    overlay.dragController = DragController(scheduler: MockScheduler())
    overlay.dragController?.beginDrag(session)
    var calls = 0
    overlay.onDropRequested = { _, _ in calls += 1; return false }

    XCTAssertFalse(overlay.performFolderDrop(
        session: session,
        destination: .inside(.beforeItem(itemID: 10))
    ))
    XCTAssertEqual(calls, 0)
    XCTAssertFalse(overlay.performFolderDrop(
        session: session,
        destination: .inside(.afterItem(itemID: 11))
    ))
    XCTAssertEqual(calls, 1)
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

- [ ] **Step 2: Add RED safe-delete and lifecycle tests**

```swift
func testFolderCellEditingShowsWorkingDeleteButton() {
    let cell = FolderCell()
    _ = cell.view
    var deleted = false
    cell.onDelete = { deleted = true }

    cell.setEditing(true)
    XCTAssertTrue(cell.isDeleteControlVisible)
    cell.performDeleteForTesting()
    XCTAssertTrue(deleted)

    cell.setEditing(false)
    XCTAssertFalse(cell.isDeleteControlVisible)
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
func closingWindowClearsDragSession() async {
    let sut = makeSUT()
    sut.viewController.dragController.beginDrag(makeSession())

    sut.controller.lifecycle(sut.lifecycle, didTransitionTo: .closing)
    await flushMainQueue(for: 0.01)

    #expect(sut.viewController.dragController.session == nil)
}

func testRepeatedOpenKeepsOneObserverAndCloseRemovesIt() {
    let sut = FolderOverlayView(frame: overlay.frame)
    sut.closeFolderCompletionRunner = { $0() }
    var scrollUpdateCount = 0
    sut.scrollPositionDidUpdate = { scrollUpdateCount += 1 }
    let folder = makeFolder()
    let children = (1...40).map {
        makeApp(id: Int64($0), parentID: 50, ordering: $0 - 1)
    }
    sut.openFolder(item: folder, childItems: children, iconCache: nil)
    sut.openFolder(item: folder, childItems: children, iconCache: nil)
    XCTAssertTrue(sut.isObservingScrollPosition)
    let beforePost = scrollUpdateCount
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: sut.folderScrollView.contentView
    )
    XCTAssertEqual(scrollUpdateCount, beforePost + 1)

    sut.closeFolder()
    XCTAssertFalse(sut.isObservingScrollPosition)
    let afterClose = scrollUpdateCount
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: sut.folderScrollView.contentView
    )
    XCTAssertEqual(scrollUpdateCount, afterClose)
}

func testDeinitReleasesOverlayWithInstalledScrollObserver() {
    weak var weakOverlay: FolderOverlayView?
    autoreleasepool {
        var sut: FolderOverlayView? = FolderOverlayView(frame: overlay.frame)
        sut?.openFolder(
            item: makeFolder(),
            childItems: [makeApp(id: 1)],
            iconCache: nil
        )
        XCTAssertTrue(sut?.isObservingScrollPosition == true)
        weakOverlay = sut
        sut = nil
    }
    XCTAssertNil(weakOverlay)
}
```

- [ ] **Step 3: Run and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'FolderOverlayViewTests|FolderOverlayViewPagingTests|FolderCellTests|AppGridCollectionViewTests|FolderControllerTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests'
```

Expected: compile RED for folder viewport capacity/reprojection, folder
destination, overlay-exterior destination methods, reload API, delete control
and window cleanup.

- [ ] **Step 4: Add complete FolderOverlay source, inner destination and reload APIs**

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
          indexPath.section < pages.count,
          indexPath.item < pages[indexPath.section].count else { return nil }
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

Implement the inner resolver and both AppKit collection-view entries completely.
Each native entry converts the window point once before any local frame lookup:

```swift
private func activeFolderSession(
    from draggingInfo: NSDraggingInfo
) -> DragSession? {
    guard isDragEnabled,
          let folderID = currentFolderID,
          let uuid = draggingInfo.draggingPasteboard.string(forType: .string),
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
    guard let indexPath,
          indexPath.section < pages.count,
          indexPath.item < pages[indexPath.section].count else {
        return emptyPlacement(
            inVisualPage: currentVisualPageIndex
        ).map { .inside($0) }
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

- [ ] **Step 5: Make FolderOverlay itself receive exterior drops**

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

- [ ] **Step 6: Bind overlay-local points to main-grid stable placements and reload folder state**

In VC setup:

```swift
folderOverlay.dragController = dragController
folderOverlay.topLevelPlacementResolver = { [weak self] overlayPoint in
    guard let self else { return nil }
    let windowPoint = self.folderOverlay.convert(overlayPoint, to: nil)
    let gridPoint = self.collectionView.convert(windowPoint, from: nil)
    return self.collectionView.topLevelPlacement(at: gridPoint)
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

- [ ] **Step 7: Remove FolderController's non-atomic layout APIs**

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

- [ ] **Step 8: Add a real FolderCell edit/delete control and wire it**

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

- [ ] **Step 9: Confirm safe folder delete and retain app deletion**

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

- [ ] **Step 10: Clear drag state on ESC, window close and window lifecycle closing**

Add one idempotent VC entry:

```swift
func cancelActiveDrag() {
    dragController.cancelDrag()
}
```

Call it before `onClose?()` in `.closeWindow`, in `.exitEditMode`, and before disabling drag for search. Task 16 already handles native drag-session end. In `LaunchPadWindowController.lifecycle(_:didTransitionTo:)`:

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

- [ ] **Step 11: Run all folder/drag suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'DragControllerTests|CollectionViewDragTests|AppGridCollectionViewTests|AppIconCellTests|FolderOverlayViewTests|FolderOverlayViewPagingTests|FolderCellTests|FolderControllerTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests|TransientMessageViewTests'
```

Expected: PASS; folder capacity follows the real clip height, open/reload/resize
repaginate and clamp, child before/after/empty and item 36 use stable IDs,
exterior drop reaches the grid resolver, safe delete has a real edit control,
failure reloads and returns false, and every lifecycle exit clears
session/timer/preview.

- [ ] **Step 12: Commit**

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

- [ ] **Step 1: Replace constant assertions with scan data-flow RED tests**

Replace scan tests that inspect unrelated `ItemWriting` calls with one narrow
writer double. `DataStoring` does not inherit `ScanBatchWriting`:

```swift
private final class RecordingScanBatchWriter:
    ScanBatchWriting,
    @unchecked Sendable
{
    var result = ScanSyncResult()
    var error: Error?
    private(set) var receivedApps: [[ScannedApp]] = []
    private(set) var receivedCapacities: [Int] = []

    func synchronizeInstalledApps(
        _ apps: [ScannedApp],
        initialPageCapacity: Int
    ) throws -> ScanSyncResult {
        receivedApps.append(apps)
        receivedCapacities.append(initialPageCapacity)
        if let error { throw error }
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
@Test("setupFileWatcher：文件变更触发一次批量增量扫描")
func setupFileWatcher_triggersIncrementalScan() async throws {
    let sut = makeDelegate()
    let writer = RecordingScanBatchWriter()
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

    try await Task.sleep(for: .seconds(2))
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

- [ ] **Step 2: Run scan suites and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManagerScanBatchTests|AppScannerTests|AppDelegateTests|LaunchPadViewControllerTests|IntegrationTests'
```

Expected: compile RED for `ScanBatchWriting`, storage batch transaction and
shared window-to-grid viewport geometry. Verify all five named suites are
reported; zero-match success is a failure.

- [ ] **Step 3: Add the narrow scan batch contract**

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

- [ ] **Step 4: Implement the single-transaction scan repository**

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

- [ ] **Step 5: Share actual grid chrome geometry and wire AppDelegate**

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

- [ ] **Step 6: Run scan, viewport and controller regression GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'GridLayoutCalculatorTests|StorageManagerScanBatchTests|AppScannerTests|AppDelegateTests|LaunchPadViewControllerTests|IntegrationTests'
```

- [ ] **Step 7: Run every storage and integration regression GREEN**

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

- [ ] **Step 8: Commit**

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
- Modify: `Sources/LaunchPad/Services/AppScanner.swift:10-40`
- Modify: `Sources/LaunchPad/Services/FileWatcher.swift:5-129`
- Modify: `Sources/LaunchPad/App/HotkeyManager.swift:22-183`
- Modify: `Sources/LaunchPad/App/AppDelegate.swift:14-83,174-218,292-300,378`
- Modify: `Tests/LaunchPadTests/Services/AppScannerTests.swift:130-175`
- Modify: `Tests/LaunchPadTests/Services/FileWatcherTests.swift`
- Modify: `Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift`
- Modify: `Tests/LaunchPadTests/App/AppDelegateTests.swift`
- Modify: `Tests/LaunchPadTests/TestHelpers/MockProtocols.swift`

**Interfaces:**
- Consumes: Task 15's MainActor `Scheduler` for deterministic debounce.
- Produces: injected Dock plist, local monitor, event stream and status item boundaries plus idempotent shutdown.
- Removes from tests: real FSEvents, real status items, real login-item calls, real Dock plist writes and arbitrary sleeps.

- [ ] **Step 1: Add resource lifecycle and side-effect isolation RED tests**

Replace `FileWatcherTests.swift`'s XCTest-only header with `import Testing` and
an `@MainActor @Suite("FileWatcher lifecycle") struct FileWatcherTests`; remove
the real FSEvents tests rather than retaining a second XCTest class. Add tests
for all branches before production changes:

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
    manager.localMonitorAdder = { _, _ in
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

Add corresponding global-tap counter tests after Step 5's injection API and
AppDelegate shutdown counter tests after Step 6. Each asserts exact add/remove,
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

- [ ] **Step 2: Run four focused suites and confirm RED**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'AppScannerTests|FileWatcherTests|HotkeyManagerTests|AppDelegateTests'
```

- [ ] **Step 3: Parse Dock exclusions through an injected read-only data provider**

Replace the path-writing test with a pure parser and add this initializer boundary:

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
          let root = try? PropertyListSerialization.propertyList(
            from: data,
            format: nil
          ) as? [String: Any],
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
                  visible == false else { continue }
            result.insert(id)
        }
    }
    return result
}
```

Tests pass nil, malformed data, missing pages, malformed items, visible entries
and hidden string IDs as in-memory plist data; they never create or delete the
user's Dock directory.

- [ ] **Step 4: Separate FileWatcher orchestration from the FSEvent backend**

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

    public func start(
        paths: [String],
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        stop()
        guard !paths.isEmpty else { return }
        self.onChange = onChange
        guard backend.start(paths: paths, onEvents: { [weak self] in
            Task { @MainActor in self?.receiveEvents() }
        }) else {
            self.onChange = nil
            return
        }
        isStarted = true
    }

    private func receiveEvents() {
        scheduler.cancelPending()
        scheduler.schedule(after: debounceInterval) { [weak self] in
            self?.onChange?()
        }
    }

    public func stop() {
        scheduler.cancelPending()
        if isStarted { backend.stop() }
        isStarted = false
        onChange = nil
    }

    deinit {
        if isStarted { backend.stop() }
    }
}
```

The production backend alone touches live FSEvents. Its own `deinit` also calls
idempotent `stop`; Task 15's scheduler holder must cancel its pending work item.
Orchestration tests inject `MockFileEventStream`, while the single production
backend cleanup test injects `FSEventStreamFunctions` with a sentinel handle and
never calls a system FSEvents function. Remove the real temp-directory FSEvent
test, 10-second expectation and Mirror-only assertion.

- [ ] **Step 5: Make HotkeyManager monitor/tap ownership injectable and balanced**

Inject local monitor functions:

```swift
var localMonitorAdder: (
    NSEvent.EventTypeMask,
    @escaping (NSEvent) -> NSEvent?
) -> Any? = { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) }
var localMonitorRemover: (Any) -> Void = { NSEvent.removeMonitor($0) }

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

private final class HotkeyCallbackBox {
    weak var manager: HotkeyManager?
    init(manager: HotkeyManager) { self.manager = manager }
}

static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<HotkeyCallbackBox>
        .fromOpaque(refcon).takeUnretainedValue()
    box.manager?.handleGlobalEvent(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

private var callbackContext: UnsafeMutableRawPointer?
var hasCallbackContext: Bool { callbackContext != nil }

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

Delete `retainedSelf`, its lock and the old `tapProvider`. Keep Task 8's
`localMonitor == nil` guard; only assign `localMonitor` when
`localMonitorAdder` returns a nonnil token. Tests inject every closure above,
capture the callback context passed to `eventTapCreator`, and assert no real
run-loop source is installed. Cover permission failure, tap failure, source
failure, success, re-register cleanup, double unregister and deinit; cover
local add failure/success, register twice, double unregister and deinit with
installer/remover counters.

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

- [ ] **Step 6: Abstract status items and add one idempotent AppDelegate shutdown path**

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

- [ ] **Step 7: Run lifecycle suites twice and prove clean process exit**

```bash
for run in 1 2; do
  CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
  swift test --disable-sandbox --no-parallel \
    --filter 'AppScannerTests|FileWatcherTests|HotkeyManagerTests|AppDelegateTests'
done
```

Expected: both invocations exit 0 without manual termination, real sleeps or persistent system resources.

- [ ] **Step 8: Commit**

```bash
git add Sources/LaunchPad/Services/AppScanner.swift \
  Sources/LaunchPad/Services/FileWatcher.swift \
  Sources/LaunchPad/App/HotkeyManager.swift \
  Sources/LaunchPad/App/AppDelegate.swift \
  Tests/LaunchPadTests/Services/AppScannerTests.swift \
  Tests/LaunchPadTests/Services/FileWatcherTests.swift \
  Tests/LaunchPadTests/Controllers/HotkeyManagerTests.swift \
  Tests/LaunchPadTests/App/AppDelegateTests.swift \
  Tests/LaunchPadTests/TestHelpers/MockProtocols.swift
git commit -m "fix: isolate and release process-global system resources"
```

---

### Task 22: Make Wall-clock Performance Assertions Deterministic and Add the Release Gate

**Files:**
- Modify: `Tests/LaunchPadTests/Performance/PerformanceTests.swift`
- Create: `scripts/test-release.sh`

**Interfaces:**
- Consumes: all production behavior from Tasks 1-21.
- Produces: `ContinuousClock` median/p95 assertions and one timeout-protected release command.
- Constraint: no environment switch, test trait, `--skip PerformanceTests`, or relaxed threshold.

- [ ] **Step 1: Add deterministic benchmark helpers and first RED conversions**

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

- [ ] **Step 2: Preserve every existing threshold for both median and p95**

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

- [ ] **Step 3: Run the performance suite serially and fix real regressions before proceeding**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel --filter PerformanceTests
```

Expected: 6/6 tests pass and the process exits 0. If a threshold fails, capture a sample of the test process and optimize the measured production path; do not skip, condition, retry or widen the assertion.

- [ ] **Step 4: Create the single release test entry**

Create executable `scripts/test-release.sh` with this structure:

```zsh
#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

ROOT_DIR=${0:A:h:h}
export CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache

run_with_timeout() {
  local seconds=$1
  shift
  local supervisor_pid=0
  local forwarded_signal=0
  local wait_status=0
  trap 'forwarded_signal=129; (( supervisor_pid > 0 )) && kill -HUP "$supervisor_pid" 2>/dev/null || true' HUP
  trap 'forwarded_signal=130; (( supervisor_pid > 0 )) && kill -INT "$supervisor_pid" 2>/dev/null || true' INT
  trap 'forwarded_signal=143; (( supervisor_pid > 0 )) && kill -TERM "$supervisor_pid" 2>/dev/null || true' TERM
  /usr/bin/perl -e '
    use Errno qw(EINTR);
    use POSIX qw(SIGHUP SIGINT SIGTERM);
    my $seconds = shift @ARGV;
    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ($pid == 0) {
      setpgrp(0, 0) or die "setpgrp failed: $!";
      exec { $ARGV[0] } @ARGV or exit 127;
    }
    my $timed_out = 0;
    my $forwarded_signal = 0;
    my $terminating = 0;
    my $terminate_group = sub {
      my ($number, $name) = @_;
      return if $terminating;
      $terminating = 1;
      $forwarded_signal = $number if $number;
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
    if (my $pidfile = $ENV{RUN_TIMEOUT_SUPERVISOR_PIDFILE}) {
      open my $handle, ">", $pidfile or die "open pidfile failed: $!";
      print {$handle} $$;
      close $handle or die "close pidfile failed: $!";
    }
    alarm $seconds;
    my $waited;
    do { $waited = waitpid($pid, 0) } while $waited == -1 && $! == EINTR;
    my $status = $?;
    alarm 0;
    $terminate_group->(0, "TERM")
      if !$timed_out && !$forwarded_signal && kill(0, -$pid);
    exit 124 if $timed_out;
    exit 128 + $forwarded_signal if $forwarded_signal;
    exit 128 + ($status & 127) if $status & 127;
    exit($status >> 8);
  ' "$seconds" "$@" &
  supervisor_pid=$!
  case $forwarded_signal in
    129) kill -HUP "$supervisor_pid" 2>/dev/null || true ;;
    130) kill -INT "$supervisor_pid" 2>/dev/null || true ;;
    143) kill -TERM "$supervisor_pid" 2>/dev/null || true ;;
  esac
  wait "$supervisor_pid" || wait_status=$?
  if (( forwarded_signal != 0 )) && kill -0 "$supervisor_pid" 2>/dev/null; then
    wait "$supervisor_pid" || wait_status=$?
  fi
  trap - HUP INT TERM
  (( forwarded_signal != 0 )) && return "$forwarded_signal"
  return "$wait_status"
}

assert_no_test_process() {
  if pgrep -f '[L]aunchPadPackageTests' >/dev/null; then
    print -u2 'release gate: residual LaunchPadPackageTests process detected'
    return 1
  fi
}

if [[ ${1:-} == '--self-test-timeout' ]]; then
  pidfile=$(mktemp /tmp/launchpad-timeout.XXXXXX)
  trap 'rm -f "$pidfile"' EXIT
  timeout_status=0
  run_with_timeout 1 /bin/zsh -c \
    'print -r -- $$ > "$1"; exec /bin/sleep 2' \
    _ "$pidfile" || timeout_status=$?
  [[ $timeout_status -eq 124 ]]
  child_pid=$(<"$pidfile")
  ! kill -0 "$child_pid" 2>/dev/null
  exit 0
fi

if [[ ${1:-} == '--self-test-signal' ]]; then
  child_pidfile=$(mktemp /tmp/launchpad-signal-child.XXXXXX)
  supervisor_pidfile=$(mktemp /tmp/launchpad-signal-supervisor.XXXXXX)
  trap 'rm -f "$child_pidfile" "$supervisor_pidfile"' EXIT
  signal_status=0
  RUN_TIMEOUT_SUPERVISOR_PIDFILE=$supervisor_pidfile \
    run_with_timeout 30 /bin/zsh -c \
      'print -r -- $$ > "$1"; exec /bin/sleep 30' \
      _ "$child_pidfile" &
  wrapper_pid=$!
  for _ in {1..500}; do
    [[ -s $child_pidfile && -s $supervisor_pidfile ]] && break
    /bin/sleep 0.01
  done
  [[ -s $child_pidfile && -s $supervisor_pidfile ]]
  supervisor_pid=$(<"$supervisor_pidfile")
  child_pid=$(<"$child_pidfile")
  kill -TERM "$wrapper_pid"
  wait "$wrapper_pid" || signal_status=$?
  [[ $signal_status -eq 143 ]]
  ! kill -0 "$supervisor_pid" 2>/dev/null
  ! kill -0 "$child_pid" 2>/dev/null
  exit 0
fi

if [[ ${1:-} == '--self-test-nonzero' ]]; then
  descendant_pidfile=$(mktemp /tmp/launchpad-nonzero-child.XXXXXX)
  trap 'rm -f "$descendant_pidfile"' EXIT
  nonzero_status=0
  run_with_timeout 30 /usr/bin/perl -e '
    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ($pid == 0) { exec "/bin/sleep", "30" or exit 127; }
    open my $handle, ">", $ARGV[0] or die "open pidfile failed: $!";
    print {$handle} $pid;
    close $handle or die "close pidfile failed: $!";
    exit 17;
  ' "$descendant_pidfile" || nonzero_status=$?
  [[ $nonzero_status -eq 17 ]]
  descendant_pid=$(<"$descendant_pidfile")
  ! kill -0 "$descendant_pid" 2>/dev/null
  exit 0
fi

cd "$ROOT_DIR"
assert_no_test_process
for run in 1 2 3; do
  print "release gate: test run ${run}/3"
  run_with_timeout 900 swift test --disable-sandbox --no-parallel
  assert_no_test_process
done

print 'release gate: release build'
run_with_timeout 900 swift build -c release --product LaunchPadApp
assert_no_test_process
```

The top-level zsh function traps HUP, INT and TERM, forwards them to its current
Perl supervisor, waits for that supervisor to finish cleanup, then returns
`128 + signal`. The macOS-available Perl supervisor puts the command and all
inherited children in a dedicated process group. Timeout sends TERM to the
whole group, waits two seconds, sends KILL, reaps the child and exits 124;
forwarded signals use the same cleanup. After any ordinary command exit, a
still-live process group is also terminated while the original exit/signal
status is preserved. Ctrl-C and nonzero exits cannot strand the supervisor,
`swift test` or `swift build`. The PID-file hook exists only for the signal
self-test. Any timeout/signal/nonzero status propagates through `set -e`. Do not
suppress or redirect build output, so every warning remains in the gate log.
Run `chmod +x scripts/test-release.sh`.

- [ ] **Step 5: Validate script syntax and anti-skip invariants**

```bash
zsh -n scripts/test-release.sh
test -x scripts/test-release.sh
scripts/test-release.sh --self-test-timeout
scripts/test-release.sh --self-test-signal
scripts/test-release.sh --self-test-nonzero
! rg -n 'enabled\(if:|ProcessInfo\.processInfo\.environment|--skip.*PerformanceTests' \
  Tests/LaunchPadTests/Performance/PerformanceTests.swift scripts/test-release.sh
rg -n 'for run in 1 2 3|--no-parallel|swift build -c release' scripts/test-release.sh
```

Expected: syntax/executable/timeout/signal/nonzero cleanup checks exit 0, the negative
scan prints nothing, and all three required gate fragments are found. The
self-tests run no Swift command: one proves timeout exit 124 leaves its exact
child PID dead; one signals the real top-level zsh wrapper and proves TERM exit
143 leaves both its exact supervisor PID and child PID dead; the third preserves
exit 17 while killing an exact forked descendant.
Neither test inspects or kills unrelated system `sleep` processes.

- [ ] **Step 6: Commit**

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

**Interfaces:**
- Consumes: Tasks 1-22.
- Produces: file-backed SQLite durability evidence, final P0 regression evidence and documentation matching production.
- Preserves: `docs/2026-07-15-release-readiness-review.md` as immutable historical evidence.

- [ ] **Step 1: Add top-level blank/cross-page and complete folder durability RED tests**

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

- [ ] **Step 2: Run integration and storage suites GREEN**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'StorageManager|LayoutDomainStateTests|IntegrationTests'
```

- [ ] **Step 3: Run every P0-adjacent suite before the expensive gate**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel \
  --filter 'GridLayoutCalculatorTests|LayoutProjectionTests|ViewLayerTests|PageScrollViewTests|DiffableDataSourceBuilderTests|DiffableDataSourceTests|AppGridCollectionViewTests|AppIconCellTests|FolderCellTests|FolderOverlayViewTests|FolderOverlayViewPagingTests|CollectionViewDragTests|SearchDebounceTests|ProtocolTests|KeyboardNavigatorTests|HotkeyManagerTests|DragControllerTests|LaunchPadViewControllerTests|LaunchPadWindowControllerTests|TransientMessageViewTests|AppScannerTests|FileWatcherTests|AppDelegateTests|StorageManager|LayoutDomainStateTests|IntegrationTests|PerformanceTests'
```

Expected: all selected suites pass, performance assertions execute, and the process exits without a residual test process.

- [ ] **Step 4: Run the only release gate and retain fresh output**

```bash
set -o pipefail
./scripts/test-release.sh 2>&1 | tee /tmp/launchpad-release-gate.log
```

Expected: three complete test passes, including `PerformanceTests` each time,
followed by a release build; the command exits 0 with no timeout or signal, no
warning suppression and no residual `LaunchPadPackageTests` process.

- [ ] **Step 5: Synchronize README and design with shipped behavior**

Update README to state:

- grid rows are viewport-derived from 5 down to 1, with 7/9/10 columns and 64...96pt icons;
- pages are visual slices of one stable global order; monitor changes do not write storage;
- drag supports same/cross page, empty append, existing folder, 0.8s preview then drop-to-create, folder reorder and drag-out; nested folders remain forbidden;
- the only release command is `./scripts/test-release.sh` and it runs three complete serial test passes plus a release build;
- remove `0 warnings`, `520+ tests`, per-suite workaround and "full tests hang" claims; report only the newly observed gate result from Step 4;
- tests do not touch real Dock plist, login items, global monitors, status items or the user database.

Update the design document's verification appendix with final task/test names, the exact gate command, and the fresh Step 4 result. Do not edit the historical review report or claim that unresolved P1/P2 release findings are closed.

- [ ] **Step 6: Review final diff and commit documentation/integration evidence**

```bash
git diff --check
git status --short
git diff -- Tests/LaunchPadTests/Integration/IntegrationTests.swift \
  README.md docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md
git add Tests/LaunchPadTests/Integration/IntegrationTests.swift \
  README.md docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md
git commit -m "docs: record verified p0 release behavior"
```

Only the three listed files may enter this commit. The review report remains unmodified and untracked work outside this plan remains untouched.

---

## P0 Test Synchronization Matrix

| P0 | Production surface | Required unit/integration suites | Negative proof |
|---|---|---|---|
| P0-1 grid | `GridLayoutCalculator`, projection, flow layout, scroll, cells, VC | `GridLayoutCalculatorTests`, `LayoutProjectionTests`, `ViewLayerTests`, `PageScrollViewTests`, `AppGridCollectionViewTests`, `AppIconCellTests`, `FolderCellTests`, `LaunchPadViewControllerTests` | invalid viewport returns no reproject; display switch causes zero storage writes |
| P0-2 search input | `KeyboardNavigator`, first-character application, search debounce | `KeyboardNavigatorTests`, `SearchDebounceTests`, `LaunchPadViewControllerTests`, `AppDelegateTests` | first key atomically enters search and appears in query/results; stale callbacks cannot overwrite current query |
| P0-3 key event chain | `HotkeyManager`, AppDelegate route, VC result | `HotkeyManagerTests`, `LaunchPadViewControllerTests`, `AppDelegateTests` | flags/unknown/hidden/unhandled events return the original object; only a handled visible keyDown returns nil |
| P0-4 drag/drop and required atomic storage | contracts, domain state, transaction, drag session, grid, folder overlay/cell, VC, `StorageManager.apply` | `ProtocolTests`, `LayoutDomainStateTests`, `StorageManagerTests`, `StorageManagerLayoutMutationTests`, `DragControllerTests`, `CollectionViewDragTests`, `AppGridCollectionViewTests`, `AppIconCellTests`, `FolderOverlayViewTests`, `FolderOverlayViewPagingTests`, `FolderCellTests`, `TransientMessageViewTests`, `LaunchPadViewControllerTests`, `LaunchPadWindowControllerTests`, `IntegrationTests` | BEGIN/prepare/bind/step/COMMIT failures preserve snapshot; rollback failure invalidates first connection; search/self/stale/nested/group-on-item reject; no optimistic snapshot; hover performs zero writes and release attempts exactly one mutation |
| P0-5 initial scan | `AppScanner`, `StorageManager` scan batch, AppDelegate, target metrics | `StorageManagerScanBatchTests`, `AppScannerTests`, `GridLayoutCalculatorTests`, `LaunchPadViewControllerTests`, `AppDelegateTests`, `IntegrationTests` | real SQLite automatic rollback leaves no autocommit rows; failed read/write does not reload; unloaded VC is not forced; real viewport capacity and all-empty-page cleanup are asserted |
| P0-6 release repeatability | system boundaries, performance, script | `FileWatcherTests`, `HotkeyManagerTests`, `AppDelegateTests`, `PerformanceTests`, full gate | no real user-system side effects, no sleeps, no performance skip, no residual process; timeout/signal/nonzero stops immediately and kills its exact process group |

## Execution Batches and Checkpoints

1. **Batch A - viewport and input:** Tasks 1-9. Run the Task 9 regression, inspect the diff, and confirm no database write was added to viewport/input paths.
2. **Batch B - atomic domain/storage:** Tasks 10-14. Run every storage/domain suite and inspect rollback/reopen evidence before any UI writer is connected.
3. **Batch C - drag UI:** Tasks 15-19. Run the complete drag/folder suite and manually verify that hover callbacks cannot reach `LayoutMutating`.
4. **Batch D - scan and resource lifecycle:** Tasks 20-21. Run relevant suites twice and confirm process exit plus zero real-system test calls.
5. **Batch E - performance and final gate:** Tasks 22-23. Run focused performance first, then integration, then `scripts/test-release.sh` once as the only final authority.

At each checkpoint, review `git status --short` and stage only files listed by the completed task. Do not restore or stage pre-existing user changes.

## Final Acceptance Criteria

- [ ] 900/768/600pt and every row breakpoint produce 5...1 rows with no overlap or clipping; 1440x620 is 7x5 and 1440x496 is 7x4.
- [ ] Folder overlay derives both axes from its actual clip viewport, never exceeds 35 items per page, and preserves/clamps its visual page across reload and resize.
- [ ] Visual resize/reprojection preserves flattened stable IDs, selection and current-page clamp and performs zero storage writes.
- [ ] Keyboard mode/query remain identical; first character is present; only actually handled visible keyDown events are swallowed.
- [ ] Same-page, cross-page, empty append, existing-folder, drop-to-create, folder reorder and drag-out all persist after reload/reopen.
- [ ] App-on-app hover at 0.8s changes preview only; release is the sole commit point; nested folders are rejected.
- [ ] Any layout failure reloads committed state, shows exactly `无法更新布局，请重试`, logs no underlying SQLite description and retries zero times.
- [ ] Every SQLite connection operation uses one serial queue; every transaction boundary is checked; rollback failure preserves both errors, invalidates and closes the connection.
- [ ] Empty persisted layouts keep exactly one page; overflow creates pages; every other empty page is deleted; all ordering is dense and row-major.
- [ ] Successful initial/incremental scan reloads an already-loaded VC once, never forces an unloaded view, and uses the target display's real capacity.
- [ ] Unit tests never change real Dock plist, login items, accessibility settings, event monitors, FSEvents, status items or user databases.
- [ ] All five wall-clock thresholds assert median and p95 with `ContinuousClock`, fixed input and no conditional enablement or skip.
- [ ] `scripts/test-release.sh` runs three full serial suites plus release build and exits 0 without timeout, signal, warnings hidden or residual test processes.
- [ ] README/design match observed production behavior and keep unresolved P1/P2 findings explicitly open.

## Stop Conditions

- Stop the current task when its new test does not fail for the expected reason; fix the test before production code.
- Stop on any unexpected pre-existing suite failure, compiler diagnostic outside the task's files, or overlapping user edit; do not broaden the diff or revert user work.
- Stop on any SQLite fault test that cannot prove the complete persisted snapshot; a thrown error alone is insufficient.
- Stop on rollback failure if code reads or reuses the invalidated connection; close it and prove state only through a new file-backed instance.
- Stop on a performance failure and collect `/usr/bin/sample` evidence for the test process; optimize the measured path. Never skip, retry, condition or relax the threshold.
- Stop the release gate on the first nonzero exit, signal, timeout or residual process. Do not continue to later passes or release build.
- Do not mark P0 complete until Task 23's gate exits 0 and the fresh log shows `PerformanceTests` ran in all three passes.
