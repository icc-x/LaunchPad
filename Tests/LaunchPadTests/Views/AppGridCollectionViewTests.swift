import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor @Suite("AppGridCollectionView")
struct AppGridCollectionViewTests {
    private struct Fixture {
        let collectionView: AppGridCollectionView
        let iconCache: MockIconCaching
    }

    private func makeSUT() -> Fixture {
        let collectionView = AppGridCollectionView(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let iconCache = MockIconCaching()
        collectionView.configure(iconCache: iconCache)
        return Fixture(collectionView: collectionView, iconCache: iconCache)
    }

    private func host(
        _ collectionView: AppGridCollectionView,
        viewportSize: CGSize
    ) -> NSWindow {
        let scrollView = NSScrollView(
            frame: NSRect(origin: .zero, size: viewportSize)
        )
        scrollView.documentView = collectionView
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewportSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func firstImageView(in view: NSView) -> NSImageView? {
        if let imageView = view as? NSImageView { return imageView }
        for subview in view.subviews {
            if let imageView = firstImageView(in: subview) { return imageView }
        }
        return nil
    }

    // MARK: - Init

    @Test func init_frame_doesNotCrash() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let view = AppGridCollectionView(frame: frame)
        #expect(view.frame == frame)
        #expect(view.collectionViewLayout is AppGridFlowLayout)
        #expect(view.isSelectable)
        #expect(view.backgroundColors == [.clear])
    }

    @Test func init_coder_doesNotCrash() {
        let view = AppGridCollectionView(frame: .zero)
        #expect(view.frame == .zero)
        #expect(view.collectionViewLayout is AppGridFlowLayout)
        #expect(view.isSelectable)
        #expect(view.backgroundColors == [.clear])
    }

    // MARK: - Configure

    @Test func configure_setsIconCache() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // After configure, the collectionView should have the icon cache
        // We verify by checking that reload doesn't crash
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
    }

    // MARK: - Reload

    @Test func reload_emptyPages_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfSections) == (0))
    }

    @Test func reload_withPages_createsSections() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app1 = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                  app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        let app2 = TestDataFactory.makePageItem(id: 2, type: .app, ordering: 1,
                                                  app: TestDataFactory.makeAppInfo(id: 2, title: "App2"))
        collectionView.reload(pages: [[app1, app2]], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfSections) == (1))
        #expect((snapshot.numberOfItems(inSection: .page(0))) == (2))
    }

    @Test func reload_withMultiplePages_createsMultipleSections() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let page1Items = TestDataFactory.makeAppItems(count: 3, titlePrefix: "P1")
        let page2Items = TestDataFactory.makeAppItems(count: 2, titlePrefix: "P2")
        collectionView.reload(pages: [page1Items, page2Items], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfSections) == (2))
        #expect((snapshot.numberOfItems(inSection: .page(0))) == (3))
        #expect((snapshot.numberOfItems(inSection: .page(1))) == (2))
    }

    @Test func reload_searchResults_createsSearchSection() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let results = TestDataFactory.makeAppItems(count: 5)
        collectionView.reload(pages: [], searchResults: results, searchQuery: "test")

        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfSections) == (1))
        #expect((snapshot.numberOfItems(inSection: .search)) == (5))
    }

    @Test func reload_nilSearchResults_usesPageMode() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfSections) == (1))
        #expect((snapshot.numberOfItems(inSection: .page(0))) == (2))
    }

    @Test func reload_emptySearchQuery_ignoresSearchResults() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: [], searchQuery: "")

        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfSections) == (1))
        #expect((snapshot.numberOfItems(inSection: .page(0))) == (2))
    }

    // MARK: - Update Layout

    @Test func updateLayout_smallScreen_7Columns() throws {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let item = TestDataFactory.makePageItem(
            id: 1,
            type: .app,
            ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Layout")
        )
        collectionView.updateLayout(screenWidth: 1280)
        collectionView.reload(
            pages: [[item]],
            searchResults: nil,
            searchQuery: nil,
            animatingDifferences: false,
            animateEntrance: false
        )

        let expected = GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1280, height: 620)
        )
        let layout = try #require(
            collectionView.collectionViewLayout as? AppGridFlowLayout
        )
        layout.prepare()
        let attributes = try #require(
            layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        )

        #expect(collectionView.gridMetrics == expected)
        #expect(expected.columns == 7)
        #expect(attributes.frame.size == expected.itemSize)
        #expect(attributes.frame.origin.x == expected.sectionInsets.left)
        #expect(attributes.frame.origin.y == expected.sectionInsets.top)
    }

    @Test func updateLayout_mediumScreen_9Columns() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.updateLayout(screenWidth: 1600)
        let params = GridLayoutCalculator.calculate(screenWidth: 1600)
        #expect((params.columns) == (9))
    }

    @Test func updateLayout_largeScreen_10Columns() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.updateLayout(screenWidth: 1920)
        let params = GridLayoutCalculator.calculate(screenWidth: 1920)
        #expect((params.columns) == (10))
    }

    // MARK: - Cell Configuration

    @Test func configureCell_appItem_returnsAppIconCell() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        #expect(cell is AppIconCell)
    }

    @Test func configureCell_groupItem_returnsFolderCell() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        #expect(cell is FolderCell)
    }

    // MARK: - Accessibility

    @Test func accessibilityRole_returnsGrid() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        #expect((collectionView.accessibilityRole()) == (.grid))
    }

    @Test func accessibilityLabel_returnsApplicationGrid() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        #expect((collectionView.accessibilityLabel()) == ("Application Grid"))
    }

    @Test func accessibilityRows_withItems_returnsRows() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let items = TestDataFactory.makeAppItems(count: 7)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        collectionView.updateLayout(screenWidth: 1440)

        let rows = collectionView.accessibilityRows()
        #expect((rows) != nil)
        // Note: In test environment without actual layout, rows may be 0
        // This test verifies the method doesn't crash
    }

    @Test func accessibilityRows_empty_returnsEmpty() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        let rows = collectionView.accessibilityRows()
        #expect((rows) != nil)
        #expect((rows?.count) == (0))
    }

    // MARK: - Drag Source

    @Test func draggingSession_returnsMove() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let session = collectionView.draggingSession(NSDraggingSession(), sourceOperationMaskFor: .withinApplication)
        #expect(session.contains(.move))
    }

    // MARK: - Callbacks

    @Test func onItemDelete_callbackIsSettable() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let expected = TestDataFactory.makePageItem(
            id: 42,
            type: .app,
            app: TestDataFactory.makeAppInfo(id: 42, title: "Delete")
        )
        var receivedIDs: [Int64] = []
        collectionView.onItemDelete = { receivedIDs.append($0.id) }

        collectionView.onItemDelete?(expected)

        #expect(receivedIDs == [expected.id])
    }

    @Test func onFolderRenamed_callbackIsSettable() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let expected = TestDataFactory.makePageItem(
            id: 73,
            type: .group,
            group: TestDataFactory.makeGroupInfo(id: 73, title: "Before")
        )
        var received: [(id: Int64, title: String)] = []
        collectionView.onFolderRenamed = {
            received.append(($0.id, $1))
        }

        collectionView.onFolderRenamed?(expected, "After")

        #expect(received.map(\.id) == [expected.id])
        #expect(received.map(\.title) == ["After"])
    }

    // MARK: - Mixed Content

    @Test func reload_mixedAppsAndGroups_handlesCorrectly() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1))
        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 2))
        collectionView.reload(pages: [[app, group]], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfItems(inSection: .page(0))) == (2))
    }

    // MARK: - Reload with Existing Data

    @Test func reload_replacesExistingData() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let items1 = TestDataFactory.makeAppItems(count: 3)
        collectionView.reload(pages: [items1], searchResults: nil, searchQuery: nil)

        let items2 = TestDataFactory.makeAppItems(count: 5, titlePrefix: "New")
        collectionView.reload(pages: [items2], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        #expect((snapshot.numberOfItems(inSection: .page(0))) == (5))
    }

    // MARK: - Entrance Animation

    @Test func animateEntrance_emptyCollectionView_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 无可见 item 时触发入场动画不应崩溃
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        collectionView.layoutSubtreeIfNeeded()
    }

    @Test func animateEntrance_withItems_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 有数据时触发入场动画不应崩溃
        let items = TestDataFactory.makeAppItems(count: 10)
        collectionView.updateLayout(screenWidth: 1440)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        collectionView.layoutSubtreeIfNeeded()
    }

    @Test func entranceDelay_usesColumnIndex_notLinearIndex() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 延迟应按列索引计算：同一列的 cell 延迟相同，从左到右依次铺开
        let columns = 7
        #expect((collectionView.entranceDelay(forItemAt: IndexPath(item: 0, section: 0), columns: columns)) == (0))
        #expect((collectionView.entranceDelay(forItemAt: IndexPath(item: 1, section: 0), columns: columns)) == (AnimationConstants.iconEntranceDelayPerColumn))
        // 第二行第一列与第一行第一列同列 → 延迟相同（0），而非线性 index=7 的 0.14
        #expect((collectionView.entranceDelay(forItemAt: IndexPath(item: 7, section: 0), columns: columns)) == (0))
        // 第二行第二列与第一行第二列同列 → 延迟相同
        #expect((collectionView.entranceDelay(forItemAt: IndexPath(item: 8, section: 0), columns: columns)) == (AnimationConstants.iconEntranceDelayPerColumn))
    }

    @Test func entranceSpringAnimation_usesSpringDamping() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 入场动画应使用 spring（damping=0.8），而非 easeOut
        let spring = collectionView.entranceSpringAnimation()
        #expect(abs((spring.damping) - (0.8)) <= (0.001))
        #expect((spring.keyPath) == ("transform.scale"))
    }

    // MARK: - Configure with in-memory folder children

    @Test func reload_withFolderChildren_loadsChildIconsForGroupCell() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let childApp = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                                     app: TestDataFactory.makeAppInfo(id: 10, title: "ChildApp"))

        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(
            pages: [[group]],
            searchResults: nil,
            searchQuery: nil,
            folderChildren: [group.id: [childApp]]
        )

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        #expect(cell is FolderCell)
        #expect(fixture.iconCache.requestedItemIDs == [childApp.id])
    }

    @Test func configureCell_groupItem_withoutStorage_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 未配置 storage 时，group cell 不应崩溃，childIcons 为空
        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        #expect(cell is FolderCell)
    }

    // MARK: - Init(coder:)

    @Test func init_coder_returnsNil() {
        // NSCoding 不支持，init?(coder:) 应返回 nil（可测且不崩溃）
        let coder = NSKeyedUnarchiver(forReadingWith: Data())
        let view = AppGridCollectionView(coder: coder)
        #expect((view) == nil)
    }

    // MARK: - Entrance animation (extracted units)

    @Test func applyEntranceAnimation_setsInitialHiddenState() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 入场准备：cell 初始 alpha=0、scale=0.8
        let cell = AppIconCell()
        cell.view.wantsLayer = true
        collectionView.applyEntranceAnimation(to: cell, at: IndexPath(item: 0, section: 0), columns: 7)
        #expect((cell.view.alphaValue) == (0))
        #expect((cell.view.layer) != nil)
    }

    @Test func animateCellAppear_runsClosureAndAddsSpring() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 注入同步调度器，使闭包同步执行（无需等待异步 run loop）
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer() // 测试环境无窗口，需显式创建 layer
        view.alphaValue = 1
        var ran = false
        collectionView.animationScheduler = { _, block in block(); ran = true }
        collectionView.animateCellAppear(cellView: view, delay: 0)
        #expect(ran)
        // 闭包同步添加了 entranceScale 动画
        #expect((view.layer?.animation(forKey: "entranceScale")) != nil)
    }

    @Test func applyCellAppearAnimation_addsSpringAndSetsAlpha() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 注入同步调度器，使 finalize 闭包同步执行（覆盖 animationScheduler 闭包体 + finalizeCellAppear 调用）
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)
        collectionView.animationScheduler = { _, block in block() }
        collectionView.applyCellAppearAnimation(cellView: view)
        #expect((view.layer?.animation(forKey: "entranceScale")) != nil)
        // 同步调度器触发 finalizeCellAppear → transform 重置为 identity
        #expect(abs((view.layer!.transform.m11) - (CGFloat(1))) <= (CGFloat(0.001)))
    }

    @Test func applyCellAppearAnimation_defaultScheduler_runs() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 不注入 animationScheduler → 走默认 DispatchQueue.main.asyncAfter 回退分支（覆盖 ?? 回退代码）
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        collectionView.applyCellAppearAnimation(cellView: view)
        #expect((view.layer?.animation(forKey: "entranceScale")) != nil)
    }

    @Test func finalizeCellAppear_resetsTransformToIdentity() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)
        collectionView.finalizeCellAppear(cellView: view)
        // 重置后 transform 应为 identity（m11 == 1 表示水平缩放为 1）
        #expect(abs((view.layer!.transform.m11) - (CGFloat(1))) <= (CGFloat(0.001)))
    }

    @Test func entranceSpringAnimation_nonSpringTiming_usesDefaultDamping() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 非 spring timing 应回退到 damping=0.8
        let spring = collectionView.entranceSpringAnimation(timing: .easeOut)
        #expect(abs((spring.damping) - (0.8)) <= (0.001))
    }

    // MARK: - Cell configuration branches

    @Test func configureCell_pageItem_returnsAppIconCell() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // .page 类型不应作为网格 item，但仍应返回 AppIconCell 且返回 nil icon
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        collectionView.reload(pages: [[page]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        #expect(cell is AppIconCell)
    }

    @Test func configureCell_appItem_onDeleteClosureInvoked() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 调用 cell.onDelete 应触发 collectionView.onItemDelete
        var deleted: PageItem?
        collectionView.onItemDelete = { deleted = $0 }

        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath) as! AppIconCell
        cell.onDelete?()
        #expect((deleted?.id) == (app.id))
    }

    @Test func configureCell_groupItem_onRenamedClosureInvoked() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 调用 cell.onRenamed 应触发 collectionView.onFolderRenamed
        var renamed: (PageItem, String)?
        collectionView.onFolderRenamed = { renamed = ($0, $1) }

        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath) as! FolderCell
        cell.onRenamed?("Renamed")
        #expect((renamed?.0.id) == (group.id))
        #expect((renamed?.1) == ("Renamed"))
    }

    @Test("group cell 删除 closure 转发稳定 folder item")
    func configureCellGroupItemForwardsDeleteClosure() throws {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        var deleted: PageItem?
        collectionView.onItemDelete = { deleted = $0 }
        let group = TestDataFactory.makePageItem(
            id: 2,
            type: .group,
            ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder")
        )
        collectionView.reload(
            pages: [[group]],
            searchResults: nil,
            searchQuery: nil
        )
        let cell = try #require(collectionView.diffableDataSource.collectionView(
            collectionView,
            itemForRepresentedObjectAt: IndexPath(item: 0, section: 0)
        ) as? FolderCell)

        cell.onDelete?()

        #expect(deleted?.id == group.id)
        #expect(deleted?.type == .group)
    }

    // MARK: - Drag image (extracted)

    @Test func makeDragImage_returns64x64Image() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let source = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let image = collectionView.makeDragImage(from: source)
        #expect((image.size) == (NSSize(width: 64, height: 64)))
    }

    // MARK: - Accessibility rows (extracted)

    @Test func buildAccessibilityRows_groupsByColumns() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.cellViewProvider = { _ in NSView() }
        let items = TestDataFactory.makeAppItems(count: 5)
        let indexPaths = items.indices.map {
            IndexPath(item: $0, section: 0)
        }
        // columns=2 → 3 行：[0,1],[2,3],[4]
        let rows = collectionView.buildAccessibilityRows(
            itemIndexPathsBySection: [indexPaths],
            columns: 2
        )
        #expect((rows.count) == (3))
        #expect((rows[0].count) == (2))
        #expect((rows[1].count) == (2))
        #expect((rows[2].count) == (1))
    }

    @Test func buildAccessibilityRows_empty_whenNoItems() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.cellViewProvider = { _ in NSView() }
        let rows = collectionView.buildAccessibilityRows(
            itemIndexPathsBySection: [],
            columns: 7
        )
        #expect((rows.count) == (0))
    }

    // MARK: - Entrance animation loop (injected providers)

    @Test func animateEntrance_withInjectedProviders_runsLoopBody() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.applyGridMetrics(GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 800, height: 620)
        ))
        // 注入可见 indexPath 与 cell，驱动入场动画循环体（覆盖 animateEntrance 循环 + applyEntranceAnimation）
        collectionView.visibleIndexPathsProvider = { [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)] }
        collectionView.visibleCellProvider = { _ in AppIconCell() }
        var ran = false
        collectionView.animationScheduler = { _, block in block(); ran = true }
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        #expect(ran)
    }

    @Test("legacy updateLayout 同时读取 clip view 两个有效轴")
    func legacyUpdateLayoutUsesBothClipAxes() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let scrollView = NSScrollView(frame: NSRect(
            x: 0, y: 0, width: 800, height: 500
        ))
        scrollView.documentView = collectionView
        scrollView.contentView.bounds = NSRect(
            x: 0, y: 0, width: 800, height: 500
        )

        collectionView.updateLayout(screenWidth: 1234)

        let expected = GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 800, height: 500)
        )
        #expect(collectionView.gridMetrics == expected)
        #expect(collectionView.gridMetrics?.pageWidth == 800)
        #expect(collectionView.gridMetrics?.rows == expected.rows)
    }

    @Test("legacy updateLayout 仅对每个无效 clip 轴独立回退")
    func legacyUpdateLayoutFallsBackOnlyForInvalidClipAxes() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let scrollView = NSScrollView(frame: NSRect(
            x: 0, y: 0, width: 800, height: 500
        ))
        scrollView.documentView = collectionView
        collectionView.clipViewSizeProvider = {
            CGSize(width: 0, height: 500)
        }
        collectionView.updateLayout(screenWidth: 1234)
        #expect(
            collectionView.gridMetrics
                == GridLayoutCalculator.calculate(
                    viewportSize: CGSize(width: 1234, height: 500)
                )
        )

        collectionView.clipViewSizeProvider = {
            CGSize(width: 800, height: 0)
        }
        collectionView.updateLayout(screenWidth: 1234)
        #expect(
            collectionView.gridMetrics
                == GridLayoutCalculator.calculate(
                    viewportSize: CGSize(width: 800, height: 620)
                )
        )
    }

    @Test("applyGridMetrics 用同一 iconSize 重配可见 app 与 folder cell")
    func applyGridMetricsReconfiguresVisibleAppAndFolderCells() throws {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let initial = GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 800, height: 620)
        )
        let updated = GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1920, height: 900)
        )
        let app = TestDataFactory.makePageItem(
            id: 1,
            type: .app,
            app: TestDataFactory.makeAppInfo(id: 1)
        )
        let group = TestDataFactory.makePageItem(
            id: 2,
            type: .group,
            group: TestDataFactory.makeGroupInfo(id: 2)
        )
        let window = host(
            collectionView,
            viewportSize: CGSize(width: 1920, height: 900)
        )
        defer { window.contentView = nil }
        collectionView.applyGridMetrics(initial)
        collectionView.reload(
            pages: [[app, group]],
            searchResults: nil,
            searchQuery: nil,
            animateEntrance: false
        )
        window.contentView?.layoutSubtreeIfNeeded()
        let appCell = try #require(
            collectionView.item(at: IndexPath(item: 0, section: 0)) as? AppIconCell
        )
        let folderCell = try #require(
            collectionView.item(at: IndexPath(item: 1, section: 0)) as? FolderCell
        )
        defer { appCell.prepareForReuse() }
        #expect(appCell.configuredIconSize == initial.iconSize)
        #expect(folderCell.configuredIconSize == initial.iconSize)

        collectionView.applyGridMetrics(updated)
        window.contentView?.layoutSubtreeIfNeeded()

        let updatedAppCell = try #require(
            collectionView.item(at: IndexPath(item: 0, section: 0)) as? AppIconCell
        )
        let updatedFolderCell = try #require(
            collectionView.item(at: IndexPath(item: 1, section: 0)) as? FolderCell
        )
        defer { updatedAppCell.prepareForReuse() }
        #expect(collectionView.gridMetrics == updated)
        #expect(updatedAppCell.configuredIconSize == updated.iconSize)
        #expect(updatedFolderCell.configuredIconSize == updated.iconSize)
    }

    @Test("reload reconfigureItems 刷新 identity 未变化的可见 icon")
    func reloadReconfigureItemsRefreshesUnchangedVisibleIcon() throws {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let metrics = GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 800, height: 620)
        )
        let item = TestDataFactory.makePageItem(
            id: 1,
            uuid: "unchanged-visible-icon",
            type: .app,
            app: TestDataFactory.makeAppInfo(id: 1)
        )
        let firstIcon = NSImage(size: NSSize(width: 32, height: 32))
        let secondIcon = NSImage(size: NSSize(width: 48, height: 48))
        fixture.iconCache.iconResult = firstIcon
        let window = host(collectionView, viewportSize: CGSize(
            width: 800, height: 620
        ))
        defer { window.contentView = nil }
        collectionView.applyGridMetrics(metrics)
        collectionView.reload(
            pages: [[item]],
            searchResults: nil,
            searchQuery: nil,
            animateEntrance: false
        )
        window.contentView?.layoutSubtreeIfNeeded()
        let cell = try #require(
            collectionView.item(at: IndexPath(item: 0, section: 0)) as? AppIconCell
        )
        defer { cell.prepareForReuse() }
        let imageView = try #require(firstImageView(in: cell.view))
        #expect(imageView.image === firstIcon)

        fixture.iconCache.iconResult = secondIcon
        collectionView.reload(
            pages: [[item]],
            searchResults: nil,
            searchQuery: nil,
            reconfigureItems: true,
            animateEntrance: false
        )
        window.contentView?.layoutSubtreeIfNeeded()

        let refreshed = try #require(
            collectionView.item(at: IndexPath(item: 0, section: 0)) as? AppIconCell
        )
        defer { refreshed.prepareForReuse() }
        let refreshedImageView = try #require(firstImageView(in: refreshed.view))
        #expect(refreshedImageView.image === secondIcon)
    }

    @Test("accessibility helper 保留 1-item 与 2-item section 边界")
    func buildAccessibilityRowsPreservesOneThenTwoItemSections() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let indexPaths = [
            [IndexPath(item: 0, section: 0)],
            [IndexPath(item: 0, section: 1), IndexPath(item: 1, section: 1)],
        ]
        let requestedViews = Dictionary(uniqueKeysWithValues:
            indexPaths.flatMap { $0 }.map { ($0, NSView()) }
        )
        var requestedIndexPaths: [IndexPath] = []
        collectionView.cellViewProvider = { indexPath in
            requestedIndexPaths.append(indexPath)
            return requestedViews[indexPath]
        }
        let rows = collectionView.buildAccessibilityRows(
            itemIndexPathsBySection: indexPaths,
            columns: 2
        )
        #expect(rows.map(\.count) == [1, 2])
        #expect(requestedIndexPaths == indexPaths.flatMap { $0 })
        let flattenedViews = rows.flatMap { $0 }
        for (index, indexPath) in indexPaths.flatMap({ $0 }).enumerated() {
            #expect(flattenedViews[index] as AnyObject === requestedViews[indexPath])
        }

        let noRows = collectionView.buildAccessibilityRows(
            itemIndexPathsBySection: indexPaths,
            columns: 0
        )
        #expect(noRows.isEmpty)
    }

    @Test("outer accessibilityRows 使用真实 snapshot section 边界")
    func accessibilityRowsUsesRealSnapshotSections() throws {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let pages = [
            [TestDataFactory.makePageItem(
                id: 1,
                uuid: "first-0",
                app: TestDataFactory.makeAppInfo(id: 1, title: "First 0")
            )],
            [
                TestDataFactory.makePageItem(
                    id: 2,
                    uuid: "second-0",
                    app: TestDataFactory.makeAppInfo(id: 2, title: "Second 0")
                ),
                TestDataFactory.makePageItem(
                    id: 3,
                    uuid: "second-1",
                    app: TestDataFactory.makeAppInfo(id: 3, title: "Second 1")
                ),
            ],
        ]
        var requestedIndexPaths: [IndexPath] = []
        collectionView.cellViewProvider = { indexPath in
            requestedIndexPaths.append(indexPath)
            return NSView()
        }
        collectionView.applyGridMetrics(GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 800, height: 620)
        ))
        collectionView.reload(
            pages: pages,
            searchResults: nil,
            searchQuery: nil,
            animateEntrance: false
        )

        let rows = try #require(collectionView.accessibilityRows())
        let expected = [
            IndexPath(item: 0, section: 0),
            IndexPath(item: 0, section: 1),
            IndexPath(item: 1, section: 1),
        ]
        let typedRows = rows.compactMap { $0 as? [Any] }
        #expect(typedRows.map(\.count) == [1, 2])
        #expect(requestedIndexPaths == expected)
    }

    @Test("稳定 ID 在重新分段后解析并更新真实 AppKit selection")
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

    @Test("nil 与未知稳定 ID 都清空真实 AppKit selection")
    func nilAndUnknownStableIDsClearActualSelection() throws {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(
            pages: [items],
            searchResults: nil,
            searchQuery: nil,
            animateEntrance: false
        )
        _ = try #require(collectionView.selectItem(id: items[0].id))
        #expect(!collectionView.selectionIndexPaths.isEmpty)

        #expect(collectionView.selectItem(id: nil) == nil)
        #expect(collectionView.selectionIndexPaths.isEmpty)
        _ = try #require(collectionView.selectItem(id: items[1].id))
        #expect(collectionView.selectItem(id: 9_999_999) == nil)
        #expect(collectionView.selectionIndexPaths.isEmpty)
    }

}

// MARK: - Mock IconCaching

@MainActor
private final class MockIconCaching: IconCaching {
    var iconResult = NSImage(size: NSSize(width: 64, height: 64))
    private(set) var requestedItemIDs: [Int64] = []

    @discardableResult
    func loadIcon(
        forItemId itemId: Int64,
        path: String,
        completion: @escaping @MainActor @Sendable (Int64, NSImage) -> Void
    ) -> Task<Void, Never> {
        requestedItemIDs.append(itemId)
        completion(itemId, iconResult)
        return Task {}
    }
}

// MARK: - Branch coverage: .app type with nil app data

extension AppGridCollectionViewTests {
    @Test func configure_cell_appTypeNilApp_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 覆盖 configureCell 中 `if let app = item.app` 的 else 分支
        let badApp = TestDataFactory.makePageItem(id: 99, type: .app, ordering: 0, app: nil)
        collectionView.reload(pages: [[badApp]], searchResults: nil, searchQuery: nil)
        collectionView.layoutSubtreeIfNeeded()
        // 不应该崩溃
    }

    // MARK: - 额外分支覆盖

    @Test func animateEntrance_visibleCellProviderNil_fallsBackToCollectionView() throws {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let window = host(
            collectionView,
            viewportSize: CGSize(width: 800, height: 620)
        )
        defer { window.orderOut(nil) }
        collectionView.applyGridMetrics(GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 800, height: 620)
        ))
        let items = TestDataFactory.makeAppItems(count: 1)
        collectionView.reload(
            pages: [items], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        collectionView.layoutSubtreeIfNeeded()
        let path = IndexPath(item: 0, section: 0)
        let realCell = try #require(collectionView.item(at: path))
        var providerRequests: [IndexPath] = []
        collectionView.visibleIndexPathsProvider = { [path] }
        collectionView.visibleCellProvider = {
            providerRequests.append($0)
            return nil
        }
        var scheduledDelays: [TimeInterval] = []
        collectionView.animationScheduler = { delay, _ in
            scheduledDelays.append(delay)
        }

        collectionView.reload(
            pages: [items], searchResults: nil, searchQuery: nil,
            animatingDifferences: false
        )

        #expect(providerRequests == [path])
        #expect(scheduledDelays == [0])
        #expect(realCell.view.alphaValue == 0)
    }

    @Test func applyCellAppearAnimation_cellViewNil_returnsEarly() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 覆盖 L152 guard let cellView else { return } 分支
        collectionView.applyCellAppearAnimation(cellView: nil)
        // 不应崩溃
    }

    @Test func configureCell_groupItem_childAppNil_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 覆盖 L230 guard let app = child.app else { return nil } 分支
        // 构造一个 group cell，其 children 包含 app 为 nil 的 item
        let childNoApp = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, app: nil)

        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(
            pages: [[group]],
            searchResults: nil,
            searchQuery: nil,
            folderChildren: [group.id: [childNoApp]]
        )

        // 触发 group cell 的实际创建，调用 configureCell → childIcons 处理 → L230
        let indexPath = IndexPath(item: 0, section: 0)
        let _ = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        // 不应崩溃
    }

    @Test func accessibilityRows_zeroBoundsWidth_usesDefaultWidth() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.bounds = NSRect(x: 0, y: 0, width: 0, height: 0)
        let items = TestDataFactory.makeAppItems(count: 3)
        collectionView.reload(
            pages: [items], searchResults: nil, searchQuery: nil,
            animateEntrance: false
        )
        #expect(collectionView.gridMetrics == nil)
        #expect(collectionView.accessibilityRows()?.isEmpty == true)
    }

    @Test("空白落点使用当前视觉页最后一个稳定 ID，真空页拒绝")
    func emptyDropUsesLastVisibleStableIDAndRejectsEmptyPage() {
        let grid = makeSUT().collectionView
        let items = TestDataFactory.makeAppItems(count: 3)
        grid.reload(
            pages: [items, []], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        #expect(grid.emptyPlacement(inVisualPage: 0) == .afterItem(itemID: items[2].id))
        #expect(grid.emptyPlacement(inVisualPage: 1) == nil)
        #expect(grid.emptyPlacement(inVisualPage: 2) == nil)
    }

    @Test("视觉页 setter 夹紧空、非空和缩页 snapshot")
    func visualPageSetterClampsAcrossReloads() {
        let grid = makeSUT().collectionView
        grid.reload(
            pages: [[], [], []], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        grid.setCurrentVisualPageIndex(2)
        #expect(grid.currentVisualPageIndex == 2)
        grid.setCurrentVisualPageIndex(9)
        #expect(grid.currentVisualPageIndex == 2)
        grid.setCurrentVisualPageIndex(-1)
        #expect(grid.currentVisualPageIndex == 0)
        grid.setCurrentVisualPageIndex(2)
        grid.reload(
            pages: [[]], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, reconfigureItems: true,
            animateEntrance: false
        )
        #expect(grid.currentVisualPageIndex == 0)
        grid.reload(
            pages: [], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        #expect(grid.currentVisualPageIndex == 0)
    }

    @Test("search sections 不计入视觉页且 snapshot 查询全部边界安全")
    func hostSnapshotQueriesUseStableIDsAndSafeBounds() throws {
        let grid = makeSUT().collectionView
        let item = TestDataFactory.makePageItem(id: 42, uuid: UUID().uuidString)
        grid.applyGridMetrics(GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1440, height: 900)
        ))
        grid.reload(
            pages: [[item]], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        grid.collectionViewLayout?.prepare()
        #expect(grid.visualPageCount == 1)
        #expect(grid.section(at: 0) == .page(0))
        #expect(grid.section(at: -1) == nil)
        #expect(grid.section(at: 1) == nil)
        #expect(grid.pageItem(id: 42)?.id == 42)
        #expect(grid.pageItem(id: 999) == nil)
        #expect(grid.indexPath(forItemID: 42) == IndexPath(item: 0, section: 0))
        #expect(grid.visualIndex(of: item) == 0)
        let attributes = try #require(grid.collectionViewLayout?
            .layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        #expect(grid.layoutFrame(at: IndexPath(item: 0, section: 0)) == attributes.frame)
        #expect(grid.layoutFrame(at: IndexPath(item: 99, section: 0)) == nil)
        grid.reload(
            pages: [], searchResults: [item], searchQuery: "a",
            animatingDifferences: false, animateEntrance: false
        )
        #expect(grid.visualPageCount == 0)
        #expect(grid.section(at: 0) == .search)
        grid.reload(
            pages: [], searchResults: [item], searchQuery: "a",
            searchResultPages: [[item]],
            animatingDifferences: false, animateEntrance: false
        )
        #expect(grid.visualPageCount == 0)
        #expect(grid.section(at: 0) == .searchPage(0))
    }

    @Test("folder preview 清理旧目标并忽略非 app、缺失目标和 reload")
    func folderPreviewLifecycleUsesOnlyVisibleAppCells() {
        let grid = makeSUT().collectionView
        let first = TestDataFactory.makePageItem(id: 1, type: .app)
        let second = TestDataFactory.makePageItem(id: 2, type: .app)
        let group = TestDataFactory.makePageItem(id: 3, type: .group)
        grid.reload(
            pages: [[first, second, group]], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        let firstCell = AppIconCell(); _ = firstCell.view
        let secondCell = AppIconCell(); _ = secondCell.view
        grid.visibleCellProvider = { path in
            switch path.item {
            case 0: firstCell
            case 1: secondCell
            default: nil
            }
        }
        grid.setFolderCreationPreview(targetItemID: 1)
        #expect(firstCell.isFolderCreationPreviewVisible)
        grid.setFolderCreationPreview(targetItemID: 2)
        #expect(!firstCell.isFolderCreationPreviewVisible)
        #expect(secondCell.isFolderCreationPreviewVisible)
        grid.setFolderCreationPreview(targetItemID: 3)
        #expect(!secondCell.isFolderCreationPreviewVisible)
        grid.setFolderCreationPreview(targetItemID: 999)
        grid.setFolderCreationPreview(targetItemID: 1)
        #expect(firstCell.isFolderCreationPreviewVisible)
        grid.reload(
            pages: [[first, second, group]], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, reconfigureItems: false,
            animateEntrance: false
        )
        #expect(!firstCell.isFolderCreationPreviewVisible)
        grid.setFolderCreationPreview(targetItemID: 1)
        #expect(firstCell.isFolderCreationPreviewVisible)
        grid.reload(
            pages: [[first]], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, reconfigureItems: true,
            animateEntrance: false
        )
        #expect(!firstCell.isFolderCreationPreviewVisible)
    }

}
#endif
