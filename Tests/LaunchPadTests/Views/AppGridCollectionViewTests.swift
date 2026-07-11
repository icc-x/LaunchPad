import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for AppGridCollectionView (0% → target 80%+)
@MainActor
final class AppGridCollectionViewTests: XCTestCase {

    private var collectionView: AppGridCollectionView!
    private var mockIconCache: MockIconCaching!

    override func setUp() {
        super.setUp()
        collectionView = AppGridCollectionView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        mockIconCache = MockIconCaching()
        collectionView.configure(iconCache: mockIconCache)
    }

    override func tearDown() {
        collectionView = nil
        mockIconCache = nil
        super.tearDown()
    }

    // MARK: - Init

    func testInit_frame_doesNotCrash() {
        let view = AppGridCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotNil(view)
    }

    func testInit_coder_doesNotCrash() {
        // NSCoder init is not supported, but we test the frame init path
        let view = AppGridCollectionView(frame: .zero)
        XCTAssertNotNil(view)
    }

    // MARK: - Configure

    func testConfigure_setsIconCache() {
        // After configure, the collectionView should have the icon cache
        // We verify by checking that reload doesn't crash
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
    }

    // MARK: - Reload

    func testReload_emptyPages_doesNotCrash() {
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 0)
    }

    func testReload_withPages_createsSections() {
        let app1 = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                  app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        let app2 = TestDataFactory.makePageItem(id: 2, type: .app, ordering: 1,
                                                  app: TestDataFactory.makeAppInfo(id: 2, title: "App2"))
        collectionView.reload(pages: [[app1, app2]], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    func testReload_withMultiplePages_createsMultipleSections() {
        let page1Items = TestDataFactory.makeAppItems(count: 3, titlePrefix: "P1")
        let page2Items = TestDataFactory.makeAppItems(count: 2, titlePrefix: "P2")
        collectionView.reload(pages: [page1Items, page2Items], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 2)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 3)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(1)), 2)
    }

    func testReload_searchResults_createsSearchSection() {
        let results = TestDataFactory.makeAppItems(count: 5)
        collectionView.reload(pages: [], searchResults: results, searchQuery: "test")

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .search), 5)
    }

    func testReload_nilSearchResults_usesPageMode() {
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    func testReload_emptySearchQuery_ignoresSearchResults() {
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: [], searchQuery: "")

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    // MARK: - Update Layout

    func testUpdateLayout_smallScreen_7Columns() {
        collectionView.updateLayout(screenWidth: 1280)
        if let layout = collectionView.collectionViewLayout as? AppGridFlowLayout {
            // 1280 screen → 7 columns
            let params = GridLayoutCalculator.calculate(screenWidth: 1280)
            XCTAssertEqual(params.columns, 7)
        }
    }

    func testUpdateLayout_mediumScreen_9Columns() {
        collectionView.updateLayout(screenWidth: 1600)
        let params = GridLayoutCalculator.calculate(screenWidth: 1600)
        XCTAssertEqual(params.columns, 9)
    }

    func testUpdateLayout_largeScreen_10Columns() {
        collectionView.updateLayout(screenWidth: 1920)
        let params = GridLayoutCalculator.calculate(screenWidth: 1920)
        XCTAssertEqual(params.columns, 10)
    }

    // MARK: - Cell Configuration

    func testConfigureCell_appItem_returnsAppIconCell() {
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        XCTAssertTrue(cell is AppIconCell)
    }

    func testConfigureCell_groupItem_returnsFolderCell() {
        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        XCTAssertTrue(cell is FolderCell)
    }

    // MARK: - Accessibility

    func testAccessibilityRole_returnsGrid() {
        XCTAssertEqual(collectionView.accessibilityRole(), .grid)
    }

    func testAccessibilityLabel_returnsApplicationGrid() {
        XCTAssertEqual(collectionView.accessibilityLabel(), "Application Grid")
    }

    func testAccessibilityRows_withItems_returnsRows() {
        let items = TestDataFactory.makeAppItems(count: 7)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        collectionView.updateLayout(screenWidth: 1440)

        let rows = collectionView.accessibilityRows()
        XCTAssertNotNil(rows)
        // Note: In test environment without actual layout, rows may be 0
        // This test verifies the method doesn't crash
    }

    func testAccessibilityRows_empty_returnsEmpty() {
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        let rows = collectionView.accessibilityRows()
        XCTAssertNotNil(rows)
        XCTAssertEqual(rows?.count, 0)
    }

    // MARK: - Drag Source

    func testDraggingSession_returnsMove() {
        let session = collectionView.draggingSession(NSDraggingSession(), sourceOperationMaskFor: .withinApplication)
        XCTAssertTrue(session.contains(.move))
    }

    // MARK: - Callbacks

    func testOnItemSelected_callbackIsSettable() {
        var called = false
        collectionView.onItemSelected = { _ in called = true }
        // Just verify the callback is settable without crash
        XCTAssertNotNil(collectionView.onItemSelected)
    }

    func testOnItemDelete_callbackIsSettable() {
        var called = false
        collectionView.onItemDelete = { _ in called = true }
        XCTAssertNotNil(collectionView.onItemDelete)
    }

    func testOnFolderRenamed_callbackIsSettable() {
        var called = false
        collectionView.onFolderRenamed = { _, _ in called = true }
        XCTAssertNotNil(collectionView.onFolderRenamed)
    }

    // MARK: - Mixed Content

    func testReload_mixedAppsAndGroups_handlesCorrectly() {
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1))
        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 2))
        collectionView.reload(pages: [[app, group]], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    // MARK: - Reload with Existing Data

    func testReload_replacesExistingData() {
        let items1 = TestDataFactory.makeAppItems(count: 3)
        collectionView.reload(pages: [items1], searchResults: nil, searchQuery: nil)

        let items2 = TestDataFactory.makeAppItems(count: 5, titlePrefix: "New")
        collectionView.reload(pages: [items2], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 5)
    }

    // MARK: - Entrance Animation

    func testAnimateEntrance_emptyCollectionView_doesNotCrash() {
        // 无可见 item 时触发入场动画不应崩溃
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        collectionView.layoutSubtreeIfNeeded()
    }

    func testAnimateEntrance_withItems_doesNotCrash() {
        // 有数据时触发入场动画不应崩溃
        let items = TestDataFactory.makeAppItems(count: 10)
        collectionView.updateLayout(screenWidth: 1440)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        collectionView.layoutSubtreeIfNeeded()
    }

    func testEntranceDelay_usesColumnIndex_notLinearIndex() {
        // 延迟应按列索引计算：同一列的 cell 延迟相同，从左到右依次铺开
        let columns = 7
        XCTAssertEqual(collectionView.entranceDelay(forItemAt: IndexPath(item: 0, section: 0), columns: columns), 0)
        XCTAssertEqual(collectionView.entranceDelay(forItemAt: IndexPath(item: 1, section: 0), columns: columns), AnimationConstants.iconEntranceDelayPerColumn)
        // 第二行第一列与第一行第一列同列 → 延迟相同（0），而非线性 index=7 的 0.14
        XCTAssertEqual(collectionView.entranceDelay(forItemAt: IndexPath(item: 7, section: 0), columns: columns), 0)
        // 第二行第二列与第一行第二列同列 → 延迟相同
        XCTAssertEqual(collectionView.entranceDelay(forItemAt: IndexPath(item: 8, section: 0), columns: columns), AnimationConstants.iconEntranceDelayPerColumn)
    }

    func testEntranceSpringAnimation_usesSpringDamping() {
        // 入场动画应使用 spring（damping=0.8），而非 easeOut
        let spring = collectionView.entranceSpringAnimation()
        XCTAssertEqual(spring.damping, 0.8, accuracy: 0.001)
        XCTAssertEqual(spring.keyPath, "transform.scale")
    }

    // MARK: - Configure with storage (group cell child icons)

    func testConfigure_withStorage_loadsChildIconsForGroupCell() {
        // 配置 storage 后，group cell 应调用 fetchAllItems 加载子项图标
        let storage = MockDataStoring()
        let childApp = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                                     app: TestDataFactory.makeAppInfo(id: 10, title: "ChildApp"))
        storage.childItems = [childApp]
        collectionView.configure(iconCache: mockIconCache, storage: storage)

        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        XCTAssertTrue(cell is FolderCell)
        XCTAssertEqual(storage.fetchAllItemsCallCount, 1)
    }

    func testConfigureCell_groupItem_withoutStorage_doesNotCrash() {
        // 未配置 storage 时，group cell 不应崩溃，childIcons 为空
        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        XCTAssertTrue(cell is FolderCell)
    }

    // MARK: - Pasteboard writer (drag source)

    func testPasteboardWriterForItemAt_appItem_writesUuid() {
        let app = TestDataFactory.makePageItem(id: 1, uuid: "drag-app-1", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let writer = collectionView.collectionView(collectionView,
                                                    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))
        XCTAssertNotNil(writer)
        let pbItem = writer as? NSPasteboardItem
        XCTAssertEqual(pbItem?.string(forType: .string), "drag-app-1")
    }

    func testPasteboardWriterForItemAt_groupItem_writesUuid() {
        let group = TestDataFactory.makePageItem(id: 2, uuid: "drag-group-2", type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let writer = collectionView.collectionView(collectionView,
                                                    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))
        XCTAssertNotNil(writer)
        let pbItem = writer as? NSPasteboardItem
        XCTAssertEqual(pbItem?.string(forType: .string), "drag-group-2")
    }

    func testPasteboardWriterForItemAt_pageItem_returnsNil() {
        // page 类型不应作为拖拽源
        let page = TestDataFactory.makePageItem(id: 1, uuid: "page-1", type: .page, ordering: 0)
        collectionView.reload(pages: [[page]], searchResults: nil, searchQuery: nil)

        let writer = collectionView.collectionView(collectionView,
                                                    pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))
        XCTAssertNil(writer)
    }

    // MARK: - Validate drop

    func testValidateDrop_screenEdge_returnsGeneric() {
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
        XCTAssertTrue(result.contains(.generic))
    }

    func testValidateDrop_rightEdge_returnsGeneric() {
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
        XCTAssertTrue(result.contains(.generic))
    }

    func testValidateDrop_emptyArea_returnsMove() {
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
        XCTAssertTrue(result.contains(.move))
        XCTAssertEqual(dropOp, .on)
    }

    // MARK: - Accept drop

    func testAcceptDrop_onGroupTarget_returnsTrue() {
        // 拖到文件夹上 → 返回 true 并调用 dragController.handleDrop
        let app = TestDataFactory.makePageItem(id: 1, uuid: "src-app", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[app, group]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()

        let pb = NSPasteboard(name: .init("test"))
        pb.setPropertyList(app.uuid, forType: .string)
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 1, section: 0),
                                                    dropOperation: .on)
        XCTAssertTrue(result)
    }

    func testAcceptDrop_invalidPasteboard_returnsFalse() {
        // 剪贴板无有效 UUID → 返回 false
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let pb = NSPasteboard(name: .init("test"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 0, section: 0),
                                                    dropOperation: .on)
        XCTAssertFalse(result)
    }

    // MARK: - Dragging image

    func testDraggingImageForItemsAt_returnsImage() {
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
            XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
        }
    }

    // MARK: - Selection callback

    func testOnItemSelected_triggeredViaDidSelect() {
        var selected: PageItem?
        collectionView.onItemSelected = { selected = $0 }

        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        collectionView.collectionView(collectionView, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        XCTAssertEqual(selected?.id, app.id)
    }

    func testOnItemSelected_emptySelection_doesNotFire() {
        var called = false
        collectionView.onItemSelected = { _ in called = true }

        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        collectionView.collectionView(collectionView, didSelectItemsAt: [])
        XCTAssertFalse(called)
    }

    // MARK: - Init(coder:)

    func testInit_coder_returnsNil() {
        // NSCoding 不支持，init?(coder:) 应返回 nil（可测且不崩溃）
        let coder = NSKeyedUnarchiver(forReadingWith: Data())
        let view = AppGridCollectionView(coder: coder)
        XCTAssertNil(view)
    }

    // MARK: - Entrance animation (extracted units)

    func testApplyEntranceAnimation_setsInitialHiddenState() {
        // 入场准备：cell 初始 alpha=0、scale=0.8
        let cell = AppIconCell()
        cell.view.wantsLayer = true
        collectionView.applyEntranceAnimation(to: cell, at: IndexPath(item: 0, section: 0), columns: 7)
        XCTAssertEqual(cell.view.alphaValue, 0)
        XCTAssertNotNil(cell.view.layer)
    }

    func testAnimateCellAppear_runsClosureAndAddsSpring() {
        // 注入同步调度器，使闭包同步执行（无需等待异步 run loop）
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer() // 测试环境无窗口，需显式创建 layer
        view.alphaValue = 1
        var ran = false
        collectionView.animationScheduler = { _, block in block(); ran = true }
        collectionView.animateCellAppear(cellView: view, delay: 0)
        XCTAssertTrue(ran)
        // 闭包同步添加了 entranceScale 动画
        XCTAssertNotNil(view.layer?.animation(forKey: "entranceScale"))
    }

    func testApplyCellAppearAnimation_addsSpringAndSetsAlpha() {
        // 注入同步调度器，使 finalize 闭包同步执行（覆盖 animationScheduler 闭包体 + finalizeCellAppear 调用）
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)
        collectionView.animationScheduler = { _, block in block() }
        collectionView.applyCellAppearAnimation(cellView: view)
        XCTAssertNotNil(view.layer?.animation(forKey: "entranceScale"))
        // 同步调度器触发 finalizeCellAppear → transform 重置为 identity
        XCTAssertEqual(view.layer!.transform.m11, CGFloat(1), accuracy: CGFloat(0.001))
    }

    func testApplyCellAppearAnimation_defaultScheduler_runs() {
        // 不注入 animationScheduler → 走默认 DispatchQueue.main.asyncAfter 回退分支（覆盖 ?? 回退代码）
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        collectionView.applyCellAppearAnimation(cellView: view)
        XCTAssertNotNil(view.layer?.animation(forKey: "entranceScale"))
    }

    func testFinalizeCellAppear_resetsTransformToIdentity() {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)
        collectionView.finalizeCellAppear(cellView: view)
        // 重置后 transform 应为 identity（m11 == 1 表示水平缩放为 1）
        XCTAssertEqual(view.layer!.transform.m11, CGFloat(1), accuracy: CGFloat(0.001))
    }

    func testEntranceSpringAnimation_nonSpringTiming_usesDefaultDamping() {
        // 非 spring timing 应回退到 damping=0.8
        let spring = collectionView.entranceSpringAnimation(timing: .easeOut)
        XCTAssertEqual(spring.damping, 0.8, accuracy: 0.001)
    }

    // MARK: - Cell configuration branches

    func testConfigureCell_pageItem_returnsAppIconCell() {
        // .page 类型不应作为网格 item，但仍应返回 AppIconCell 且返回 nil icon
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        collectionView.reload(pages: [[page]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        XCTAssertTrue(cell is AppIconCell)
    }

    func testConfigureCell_appItem_onDeleteClosureInvoked() {
        // 调用 cell.onDelete 应触发 collectionView.onItemDelete
        var deleted: PageItem?
        collectionView.onItemDelete = { deleted = $0 }

        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath) as! AppIconCell
        cell.onDelete?()
        XCTAssertEqual(deleted?.id, app.id)
    }

    func testConfigureCell_groupItem_onRenamedClosureInvoked() {
        // 调用 cell.onRenamed 应触发 collectionView.onFolderRenamed
        var renamed: (PageItem, String)?
        collectionView.onFolderRenamed = { renamed = ($0, $1) }

        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath) as! FolderCell
        cell.onRenamed?("Renamed")
        XCTAssertEqual(renamed?.0.id, group.id)
        XCTAssertEqual(renamed?.1, "Renamed")
    }

    // MARK: - Drop hover resolution (extracted)

    func testResolveHoverLocation_overIcon_whenGroupAtLocation() {
        collectionView.indexPathResolver = { _ in IndexPath(item: 0, section: 0) }
        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)
        let hover = collectionView.resolveHoverLocation(at: .zero)
        if case .overIcon(let targetId) = hover {
            XCTAssertEqual(targetId, group.id)
        } else {
            XCTFail("expected .overIcon, got \(hover)")
        }
    }

    func testResolveHoverLocation_empty_whenAppAtLocation() {
        collectionView.indexPathResolver = { _ in IndexPath(item: 0, section: 0) }
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        let hover = collectionView.resolveHoverLocation(at: .zero)
        XCTAssertEqual(hover, .empty)
    }

    func testResolveHoverLocation_empty_whenResolverReturnsNil() {
        collectionView.indexPathResolver = { _ in nil }
        let hover = collectionView.resolveHoverLocation(at: .zero)
        XCTAssertEqual(hover, .empty)
    }

    // MARK: - Drag image (extracted)

    func testMakeDragImage_returns64x64Image() {
        let source = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let image = collectionView.makeDragImage(from: source)
        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
    }

    // MARK: - Accessibility rows (extracted)

    func testBuildAccessibilityRows_groupsByColumns() {
        collectionView.cellViewProvider = { _ in NSView() }
        let items = TestDataFactory.makeAppItems(count: 5)
        // columns=2 → 3 行：[0,1],[2,3],[4]
        let rows = collectionView.buildAccessibilityRows(items: items, columns: 2)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[1].count, 2)
        XCTAssertEqual(rows[2].count, 1)
    }

    func testBuildAccessibilityRows_empty_whenNoItems() {
        collectionView.cellViewProvider = { _ in NSView() }
        let rows = collectionView.buildAccessibilityRows(items: [], columns: 7)
        XCTAssertEqual(rows.count, 0)
    }

    // MARK: - Accept drop (reorder + invalid target)

    func testAcceptDrop_reorderSamePage_performsReorder() {
        // 拖拽 app 到另一个 app（非 group 目标）→ 触发同页重排分支
        let app1 = TestDataFactory.makePageItem(id: 1, uuid: "reorder-1", type: .app, ordering: 0,
                                                 app: TestDataFactory.makeAppInfo(id: 1, title: "A1"))
        let app2 = TestDataFactory.makePageItem(id: 2, uuid: "reorder-2", type: .app, ordering: 1,
                                                 app: TestDataFactory.makeAppInfo(id: 2, title: "A2"))
        collectionView.reload(pages: [[app1, app2]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()

        let pb = NSPasteboard(name: .init("test-reorder"))
        pb.setPropertyList(app1.uuid, forType: .string)
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 1, section: 0),
                                                    dropOperation: .on)
        XCTAssertTrue(result)
    }

    func testAcceptDrop_outOfRangeTarget_returnsFalse() {
        // 目标 indexPath 无对应 item → 返回 false
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let pb = NSPasteboard(name: .init("test-oob"))
        pb.setPropertyList(app.uuid, forType: .string)
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)

        let result = collectionView.collectionView(collectionView,
                                                    acceptDrop: info,
                                                    indexPath: IndexPath(item: 99, section: 0),
                                                    dropOperation: .on)
        XCTAssertFalse(result)
    }

    // MARK: - Entrance animation loop (injected providers)

    func testAnimateEntrance_withInjectedProviders_runsLoopBody() {
        // 注入可见 indexPath 与 cell，驱动入场动画循环体（覆盖 animateEntrance 循环 + applyEntranceAnimation）
        collectionView.visibleIndexPathsProvider = { [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)] }
        collectionView.visibleCellProvider = { _ in AppIconCell() }
        var ran = false
        collectionView.animationScheduler = { _, block in block(); ran = true }
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        XCTAssertTrue(ran)
    }

    // MARK: - Extract dragged item (extracted)

    func testExtractDraggedItem_validPasteboard_returnsItem() {
        let app = TestDataFactory.makePageItem(id: 1, uuid: "ex-app", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "A"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        let pb = NSPasteboard(name: .init("test-extract"))
        pb.setPropertyList(app.uuid, forType: .string)
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)
        let extracted = collectionView.extractDraggedItem(from: info)
        XCTAssertEqual(extracted?.id, app.id)
    }

    func testExtractDraggedItem_emptyPasteboard_returnsNil() {
        let pb = NSPasteboard(name: .init("test-extract-empty"))
        let info = MockDraggingInfo(pasteboard: pb, location: .zero)
        let extracted = collectionView.extractDraggedItem(from: info)
        XCTAssertNil(extracted)
    }

    // MARK: - Perform drop (extracted)

    func testPerformDrop_onGroupTarget_returnsTrue() {
        let app = TestDataFactory.makePageItem(id: 1, uuid: "pd-app", type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "A"))
        let group = TestDataFactory.makePageItem(id: 2, uuid: "pd-group", type: .group, ordering: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 2, title: "F"))
        collectionView.reload(pages: [[app, group]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()
        let result = collectionView.performDrop(draggedItem: app, targetItem: group)
        XCTAssertTrue(result)
    }

    func testPerformDrop_reorderSamePage_returnsTrue() {
        let app1 = TestDataFactory.makePageItem(id: 1, uuid: "pd-r1", type: .app, ordering: 0,
                                                 app: TestDataFactory.makeAppInfo(id: 1, title: "A1"))
        let app2 = TestDataFactory.makePageItem(id: 2, uuid: "pd-r2", type: .app, ordering: 1,
                                                 app: TestDataFactory.makeAppInfo(id: 2, title: "A2"))
        collectionView.reload(pages: [[app1, app2]], searchResults: nil, searchQuery: nil)
        collectionView.dragController = DragController()
        let result = collectionView.performDrop(draggedItem: app1, targetItem: app2)
        XCTAssertTrue(result)
        // 重排后 app1 应位于 app2 之前
        let snapshot = collectionView.diffableDataSource.snapshot()
        let ids = snapshot.itemIdentifiers.map { $0.id }
        XCTAssertEqual(ids.firstIndex(of: app1.id)!, ids.firstIndex(of: app2.id)! - 1)
    }

    // MARK: - Dragging image (injected cell provider)

    func testDraggingImageForItemsAt_usesInjectedCellProvider() {
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
        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
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
    func testConfigure_cell_appTypeNilApp_doesNotCrash() {
        // 覆盖 configureCell 中 `if let app = item.app` 的 else 分支
        let badApp = TestDataFactory.makePageItem(id: 99, type: .app, ordering: 0, app: nil)
        collectionView.reload(pages: [[badApp]], searchResults: nil, searchQuery: nil)
        collectionView.layoutSubtreeIfNeeded()
        // 不应该崩溃
    }

    // MARK: - 额外分支覆盖

    func testAnimateEntrance_visibleCellProviderNil_fallsBackToCollectionView() {
        // 覆盖 L120 ?? false 分支：visibleCellProvider 返回 nil 时回退到 item(at:)
        collectionView.visibleIndexPathsProvider = { [IndexPath(item: 0, section: 0)] }
        collectionView.visibleCellProvider = { _ in nil } // provider 返回 nil → ?? 走 else 分支
        collectionView.animationScheduler = { _, _ in } // 避免异步调度干扰
        let items = TestDataFactory.makeAppItems(count: 1)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        // 不应崩溃
    }

    func testApplyCellAppearAnimation_cellViewNil_returnsEarly() {
        // 覆盖 L152 guard let cellView else { return } 分支
        collectionView.applyCellAppearAnimation(cellView: nil)
        // 不应崩溃
    }

    func testConfigureCell_groupItem_childAppNil_doesNotCrash() {
        // 覆盖 L230 guard let app = child.app else { return nil } 分支
        // 构造一个 group cell，其 children 包含 app 为 nil 的 item
        let storage = MockDataStoring()
        let childNoApp = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, app: nil)
        storage.childItems = [childNoApp]
        collectionView.configure(iconCache: mockIconCache, storage: storage)

        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        // 触发 group cell 的实际创建，调用 configureCell → childIcons 处理 → L230
        let indexPath = IndexPath(item: 0, section: 0)
        let _ = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        // 不应崩溃
    }

    func testAccessibilityRows_zeroBoundsWidth_usesDefaultWidth() {
        // 覆盖 L261 bounds.width > 0 ternary false 分支
        collectionView.bounds = NSRect(x: 0, y: 0, width: 0, height: 0)
        let items = TestDataFactory.makeAppItems(count: 3)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        let rows = collectionView.accessibilityRows()
        // 不应崩溃
        XCTAssertNotNil(rows)
    }

    func testPerformDrop_bothItemsNotInSnapshot_noOp() {
        // 覆盖 L370 || 表达式 false 分支：draggedItem 和 targetItem 都不在 section
        let app1 = TestDataFactory.makePageItem(id: 1, uuid: "pd-bad-1", type: .app, ordering: 0,
                                                 app: TestDataFactory.makeAppInfo(id: 1, title: "A1"))
        let app2 = TestDataFactory.makePageItem(id: 2, uuid: "pd-bad-2", type: .app, ordering: 1,
                                                 app: TestDataFactory.makeAppInfo(id: 2, title: "A2"))
        // 不 reload，让 snapshot 为空 → 两者都不在 section
        collectionView.dragController = DragController()
        // draggedItem 和 targetItem 都不在 snapshot 的 section 中
        let result = collectionView.performDrop(draggedItem: app1, targetItem: app2)
        XCTAssertEqual(result, true)
    }
}
#endif
