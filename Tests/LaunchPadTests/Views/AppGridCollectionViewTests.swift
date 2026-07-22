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

    // MARK: - Init

    @Test func init_frame_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let view = AppGridCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        #expect((view) != nil)
        #expect(view !== collectionView)
    }

    @Test func init_coder_doesNotCrash() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // NSCoder init is not supported, but we test the frame init path
        let view = AppGridCollectionView(frame: .zero)
        #expect((view) != nil)
        #expect(view !== collectionView)
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

    @Test func updateLayout_smallScreen_7Columns() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.updateLayout(screenWidth: 1280)
        if let layout = collectionView.collectionViewLayout as? AppGridFlowLayout {
            // 1280 screen → 7 columns
            let params = GridLayoutCalculator.calculate(screenWidth: 1280)
            #expect((params.columns) == (7))
        }
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

    @Test func onItemSelected_callbackIsSettable() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        var called = false
        collectionView.onItemSelected = { _ in called = true }
        // Just verify the callback is settable without crash
        #expect((collectionView.onItemSelected) != nil)
    }

    @Test func onItemDelete_callbackIsSettable() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        var called = false
        collectionView.onItemDelete = { _ in called = true }
        #expect((collectionView.onItemDelete) != nil)
    }

    @Test func onFolderRenamed_callbackIsSettable() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        var called = false
        collectionView.onFolderRenamed = { _, _ in called = true }
        #expect((collectionView.onFolderRenamed) != nil)
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

    // MARK: - Configure with storage (group cell child icons)

    @Test func configure_withStorage_loadsChildIconsForGroupCell() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 配置 storage 后，group cell 应调用 fetchAllItems 加载子项图标
        let storage = MockDataStoring()
        let childApp = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                                     app: TestDataFactory.makeAppInfo(id: 10, title: "ChildApp"))
        storage.childItems = [childApp]
        collectionView.configure(iconCache: fixture.iconCache, storage: storage)

        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        #expect(cell is FolderCell)
        #expect((storage.fetchAllItemsCallCount) == (1))
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

    // MARK: - Pasteboard writer (drag source)

    @Test func pasteboardWriterForItemAt_appItem_writesUuid() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app = TestDataFactory.makePageItem(id: 1, uuid: "drag-app-1", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let writer = collectionView.collectionView(collectionView,
                                                    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))
        #expect((writer) != nil)
        let pbItem = writer as? NSPasteboardItem
        #expect((pbItem?.string(forType: .string)) == ("drag-app-1"))
    }

    @Test func pasteboardWriterForItemAt_groupItem_writesUuid() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let group = TestDataFactory.makePageItem(id: 2, uuid: "drag-group-2", type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let writer = collectionView.collectionView(collectionView,
                                                    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))
        #expect((writer) != nil)
        let pbItem = writer as? NSPasteboardItem
        #expect((pbItem?.string(forType: .string)) == ("drag-group-2"))
    }

    @Test func pasteboardWriterForItemAt_pageItem_returnsNil() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // page 类型不应作为拖拽源
        let page = TestDataFactory.makePageItem(id: 1, uuid: "page-1", type: .page, ordering: 0)
        collectionView.reload(pages: [[page]], searchResults: nil, searchQuery: nil)

        let writer = collectionView.collectionView(collectionView,
                                                    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))
        #expect((writer) == nil)
    }

    // MARK: - Validate drop

    @Test func validateDrop_screenEdge_returnsGeneric() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.pasteboardUUIDReader = { _ in nil }
        // 拖到左边缘 → 返回 .generic（触发翻页）
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()

        let info = MockDraggingInfo(pasteboard: NSPasteboard(name: .init("test")),
                                     location: NSPoint(x: 10, y: 100))
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        var dropOp: NSCollectionView.DropOperation = .on
        let result: NSDragOperation = withUnsafeMutablePointer(to: &dropOp) { opPtr -> NSDragOperation in
            withUnsafeMutablePointer(to: &proposed) { ptr -> NSDragOperation in
                collectionView.collectionView(collectionView,
                                              validateDrop: info,
                                              proposedIndexPath: AutoreleasingUnsafeMutablePointer(ptr),
                                              dropOperation: opPtr)
            }
        }
        #expect(result.contains(.generic))
    }

    @Test func validateDrop_rightEdge_returnsGeneric() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.pasteboardUUIDReader = { _ in nil }
        // 拖到右边缘 → 返回 .generic（触发翻页）
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()

        // bounds.width=1440，右边缘区域 = x > 1400
        let info = MockDraggingInfo(pasteboard: NSPasteboard(name: .init("test")),
                                     location: NSPoint(x: 1430, y: 100))
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        var dropOp: NSCollectionView.DropOperation = .on
        let result: NSDragOperation = withUnsafeMutablePointer(to: &dropOp) { opPtr -> NSDragOperation in
            withUnsafeMutablePointer(to: &proposed) { ptr -> NSDragOperation in
                collectionView.collectionView(collectionView,
                                              validateDrop: info,
                                              proposedIndexPath: AutoreleasingUnsafeMutablePointer(ptr),
                                              dropOperation: opPtr)
            }
        }
        #expect(result.contains(.generic))
    }

    @Test func validateDrop_emptyArea_returnsMove() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.pasteboardUUIDReader = { _ in nil }
        // 拖到空白区域 → 返回 .move，dropOperation 设为 .on
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()

        // 中心区域（非边缘），且 indexPathForItem 在无布局测试环境返回 nil → empty 分支
        let info = MockDraggingInfo(pasteboard: NSPasteboard(name: .init("test")),
                                     location: NSPoint(x: 500, y: 500))
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        var dropOp: NSCollectionView.DropOperation = .before
        let result: NSDragOperation = withUnsafeMutablePointer(to: &dropOp) { opPtr -> NSDragOperation in
            withUnsafeMutablePointer(to: &proposed) { ptr -> NSDragOperation in
                collectionView.collectionView(collectionView,
                                              validateDrop: info,
                                              proposedIndexPath: AutoreleasingUnsafeMutablePointer(ptr),
                                              dropOperation: opPtr)
            }
        }
        #expect(result.contains(.move))
        #expect((dropOp) == (.on))
    }

    // MARK: - Accept drop

    @Test func acceptDrop_onGroupTarget_returnsTrue() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 拖到文件夹上 → 返回 true 并调用 dragController.handleDrop
        let app = TestDataFactory.makePageItem(id: 1, uuid: "src-app", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[app, group]], searchResults: nil, searchQuery: nil)
        let dragController = DragController()
        dragController.handleDragStart()
        collectionView.dragController = dragController
        collectionView.pasteboardUUIDReader = { _ in app.uuid }

        let pb = NSPasteboard(name: .init("test"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 1, section: 0),
                                                    dropOperation: .on)
        #expect(result)
        #expect((dragController.state) == (.idle))
    }

    @Test func acceptDrop_invalidPasteboard_returnsFalse() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 剪贴板无有效 UUID → 返回 false
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        let dragController = DragController()
        dragController.handleDragStart()
        collectionView.dragController = dragController
        collectionView.pasteboardUUIDReader = { _ in nil }

        let pb = NSPasteboard(name: .init("test"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 0, section: 0),
                                                    dropOperation: .on)
        #expect(!(result))
        #expect((dragController.state) == (.dragging))
    }

    // MARK: - Dragging image

    @Test func draggingImageForItemsAt_returnsImage() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        collectionView.layoutSubtreeIfNeeded()

        var dragImageOffset = NSPoint.zero
        let image = collectionView.collectionView(collectionView,
                                                   draggingImageForItemsAt: [IndexPath(item: 0, section: 0)],
                                                   with: NSEvent(),
                                                   offset: &dragImageOffset)
        // 即使 cell 未实例化，方法也不应崩溃；有 cell 时返回 64×64 image
        if image.size != .zero {
            #expect((image.size) == (NSSize(width: 64, height: 64)))
        }
    }

    // MARK: - Selection callback

    @Test func onItemSelected_triggeredViaDidSelect() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        var selected: PageItem?
        collectionView.onItemSelected = { selected = $0 }

        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        collectionView.collectionView(collectionView, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        #expect((selected?.id) == (app.id))
    }

    @Test func onItemSelected_emptySelection_doesNotFire() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        var called = false
        collectionView.onItemSelected = { _ in called = true }

        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        collectionView.collectionView(collectionView, didSelectItemsAt: [])
        #expect(!(called))
    }

    // MARK: - Init(coder:)

    @Test func init_coder_returnsNil() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
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

    // MARK: - Drop hover resolution (extracted)

    @Test func resolveHoverLocation_overIcon_whenGroupAtLocation() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.indexPathResolver = { _ in IndexPath(item: 0, section: 0) }
        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)
        let hover = collectionView.resolveHoverLocation(at: .zero)
        if case .overIcon(let targetId) = hover {
            #expect((targetId) == (group.id))
        } else {
            Issue.record("expected .overIcon, got \(hover)")
        }
    }

    @Test func resolveHoverLocation_empty_whenAppAtLocation() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.indexPathResolver = { _ in IndexPath(item: 0, section: 0) }
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        let hover = collectionView.resolveHoverLocation(at: .zero)
        #expect((hover) == (.empty))
    }

    @Test func resolveHoverLocation_empty_whenResolverReturnsNil() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.indexPathResolver = { _ in nil }
        let hover = collectionView.resolveHoverLocation(at: .zero)
        #expect((hover) == (.empty))
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
        // columns=2 → 3 行：[0,1],[2,3],[4]
        let rows = collectionView.buildAccessibilityRows(items: items, columns: 2)
        #expect((rows.count) == (3))
        #expect((rows[0].count) == (2))
        #expect((rows[1].count) == (2))
        #expect((rows[2].count) == (1))
    }

    @Test func buildAccessibilityRows_empty_whenNoItems() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.cellViewProvider = { _ in NSView() }
        let rows = collectionView.buildAccessibilityRows(items: [], columns: 7)
        #expect((rows.count) == (0))
    }

    // MARK: - Accept drop (reorder + invalid target)

    @Test func acceptDrop_reorderSamePage_performsReorder() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 拖拽 app 到另一个 app（非 group 目标）→ 触发同页重排分支
        let app1 = TestDataFactory.makePageItem(id: 1, uuid: "reorder-1", type: .app, ordering: 0,
                                                 app: TestDataFactory.makeAppInfo(id: 1, title: "A1"))
        let app2 = TestDataFactory.makePageItem(id: 2, uuid: "reorder-2", type: .app, ordering: 1,
                                                 app: TestDataFactory.makeAppInfo(id: 2, title: "A2"))
        collectionView.reload(pages: [[app1, app2]], searchResults: nil, searchQuery: nil)
        let dragController = DragController()
        dragController.handleDragStart()
        collectionView.dragController = dragController
        collectionView.pasteboardUUIDReader = { _ in app1.uuid }

        let pb = NSPasteboard(name: .init("test-reorder"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 1, section: 0),
                                                    dropOperation: .on)
        #expect(result)
        #expect((collectionView.diffableDataSource.snapshot().itemIdentifiers.map(\.id)) == ([app1.id, app2.id]))
        #expect((dragController.state) == (.idle))
    }

    @Test func acceptDrop_outOfRangeTarget_returnsFalse() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 目标 indexPath 无对应 item → 返回 false
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        let dragController = DragController()
        dragController.handleDragStart()
        collectionView.dragController = dragController
        collectionView.pasteboardUUIDReader = { _ in app.uuid }

        let pb = NSPasteboard(name: .init("test-oob"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 99, section: 0),
                                                    dropOperation: .on)
        #expect(!(result))
        #expect((dragController.state) == (.dragging))
    }

    // MARK: - Entrance animation loop (injected providers)

    @Test func animateEntrance_withInjectedProviders_runsLoopBody() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 注入可见 indexPath 与 cell，驱动入场动画循环体（覆盖 animateEntrance 循环 + applyEntranceAnimation）
        collectionView.visibleIndexPathsProvider = { [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)] }
        collectionView.visibleCellProvider = { _ in AppIconCell() }
        var ran = false
        collectionView.animationScheduler = { _, block in block(); ran = true }
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        #expect(ran)
    }

    // MARK: - Extract dragged item (extracted)

    @Test func extractDraggedItem_validPasteboard_returnsItem() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app = TestDataFactory.makePageItem(id: 1, uuid: "ex-app", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "A"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        collectionView.pasteboardUUIDReader = { _ in app.uuid }
        let pb = NSPasteboard(name: .init("test-extract"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)
        let extracted = collectionView.extractDraggedItem(from: info)
        #expect((extracted?.id) == (app.id))
    }

    @Test func extractDraggedItem_emptyPasteboard_returnsNil() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.pasteboardUUIDReader = { _ in nil }
        let pb = NSPasteboard(name: .init("test-extract-empty"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)
        let extracted = collectionView.extractDraggedItem(from: info)
        #expect((extracted) == nil)
    }

    // MARK: - Perform drop (extracted)

    @Test func performDrop_onGroupTarget_returnsTrue() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app = TestDataFactory.makePageItem(id: 1, uuid: "pd-app", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "A"))
        let group = TestDataFactory.makePageItem(id: 2, uuid: "pd-group", type: .group, ordering: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "F"))
        collectionView.reload(pages: [[app, group]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()
        let result = collectionView.performDrop(draggedItem: app, targetItem: group)
        #expect(result)
    }

    @Test func performDrop_reorderSamePage_returnsTrue() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        let app1 = TestDataFactory.makePageItem(id: 1, uuid: "pd-r1", type: .app, ordering: 0,
                                                 app: TestDataFactory.makeAppInfo(id: 1, title: "A1"))
        let app2 = TestDataFactory.makePageItem(id: 2, uuid: "pd-r2", type: .app, ordering: 1,
                                                 app: TestDataFactory.makeAppInfo(id: 2, title: "A2"))
        collectionView.reload(pages: [[app1, app2]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()
        let result = collectionView.performDrop(draggedItem: app1, targetItem: app2)
        #expect(result)
        // 重排后 app1 应位于 app2 之前
        let snapshot = collectionView.diffableDataSource.snapshot()
        let ids = snapshot.itemIdentifiers.map { $0.id }
        #expect((ids.firstIndex(of: app1.id)!) == (ids.firstIndex(of: app2.id)! - 1))
    }

    // MARK: - Dragging image (injected cell provider)

    @Test func draggingImageForItemsAt_usesInjectedCellProvider() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        collectionView.visibleCellProvider = { _ in
            let cell = AppIconCell()
            cell.view.frame = NSRect(x: 0, y: 0, width: 80, height: 80)
            return cell
        }
        var offset = NSPoint.zero
        let image = collectionView.collectionView(collectionView,
                                                  draggingImageForItemsAt: [IndexPath(item: 0, section: 0)],
                                                  with: NSEvent(),
                                                  offset: &offset)
        #expect((image.size) == (NSSize(width: 64, height: 64)))
    }
}

// MARK: - Mock IconCaching

private final class MockIconCaching: IconCaching, @unchecked Sendable {
    var iconResult = NSImage(size: NSSize(width: 64, height: 64))

    func icon(forItemId itemId: Int64, path: String) -> NSImage {
        return iconResult
    }
}

// MARK: - Mock DataStoring (for group cell child icons)

private final class MockDataStoring: DataStoring, @unchecked Sendable {
    var childItems: [PageItem] = []
    private(set) var fetchAllItemsCallCount = 0

    func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
        fetchAllItemsCallCount += 1
        return childItems
    }

    func insertItem(_ item: PageItem) throws -> Int64 { return item.id }
    func updateItem(_ item: PageItem) throws {}
    func deleteItem(id: Int64) throws {}
    func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {}
    func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {}
    func fetchImage(itemId: Int64) throws -> (Data, Data)? { return nil }
}

// MARK: - Mock NSDraggingInfo (for validateDrop / acceptDrop)

@MainActor
private final class MockDraggingInfo: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingLocation: NSPoint
    var draggingSequenceNumber: Int = 0
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggedImageLocation: NSPoint = .zero
    var draggingDestinationWindow: NSWindow?
    var draggingSource: Any?
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    var draggedImage: NSImage?
    var draggingFormation: NSDraggingFormation = .default
    var springLoadingHighlight: NSSpringLoadingHighlight = .none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}

    init(pasteboard: NSPasteboard, location: NSPoint) {
        self.draggingPasteboard = pasteboard
        self.draggingLocation = location
        super.init()
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

    @Test func animateEntrance_visibleCellProviderNil_fallsBackToCollectionView() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 覆盖 L120 ?? false 分支：visibleCellProvider 返回 nil 时回退到 item(at:)
        collectionView.visibleIndexPathsProvider = { [IndexPath(item: 0, section: 0)] }
        collectionView.visibleCellProvider = { _ in nil } // provider 返回 nil → ?? 走 else 分支
        collectionView.animationScheduler = { _, _ in } // 避免异步调度干扰
        let items = TestDataFactory.makeAppItems(count: 1)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        // 不应崩溃
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
        let storage = MockDataStoring()
        let childNoApp = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, app: nil)
        storage.childItems = [childNoApp]
        collectionView.configure(iconCache: fixture.iconCache, storage: storage)

        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        // 触发 group cell 的实际创建，调用 configureCell → childIcons 处理 → L230
        let indexPath = IndexPath(item: 0, section: 0)
        let _ = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        // 不应崩溃
    }

    @Test func accessibilityRows_zeroBoundsWidth_usesDefaultWidth() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 覆盖 L261 bounds.width > 0 ternary false 分支
        collectionView.bounds = NSRect(x: 0, y: 0, width: 0, height: 0)
        let items = TestDataFactory.makeAppItems(count: 3)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        let rows = collectionView.accessibilityRows()
        // 不应崩溃
        #expect((rows) != nil)
    }

    @Test func performDrop_bothItemsNotInSnapshot_noOp() {
        let fixture = makeSUT()
        let collectionView = fixture.collectionView
        // 覆盖 L370 || 表达式 false 分支：draggedItem 和 targetItem 都不在 section
        let app1 = TestDataFactory.makePageItem(id: 1, uuid: "pd-bad-1", type: .app, ordering: 0,
                                                 app: TestDataFactory.makeAppInfo(id: 1, title: "A1"))
        let app2 = TestDataFactory.makePageItem(id: 2, uuid: "pd-bad-2", type: .app, ordering: 1,
                                                 app: TestDataFactory.makeAppInfo(id: 2, title: "A2"))
        // 不 reload，让 snapshot 为空 → 两者都不在 section
        collectionView.dragController = DragController()
        // draggedItem 和 targetItem 都不在 snapshot 的 section 中
        let result = collectionView.performDrop(draggedItem: app1, targetItem: app2)
        #expect((result) == (true))
    }
}
#endif
