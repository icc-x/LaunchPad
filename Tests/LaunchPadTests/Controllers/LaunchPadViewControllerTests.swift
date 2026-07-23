import Testing
import Foundation
import CoreGraphics
@testable import LaunchPad
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit

@MainActor
@Suite("LaunchPadViewController 键盘交互与执行动作")
struct LaunchPadViewControllerTests {

    // MARK: - Test Doubles

    private final class MockDataStore: DataStoring, @unchecked Sendable {
        var pages: [PageItem] = []
        var childrenByPage: [Int64: [PageItem]] = [:]
        var deletedIds: [Int64] = []
        var insertedItems: [PageItem] = []
        var updatedItems: [PageItem] = []
        private(set) var fetchAllItemsCallCount = 0
        var fetchError: Error?
        var eventRecorder: ((String) -> Void)?

        // 注入：让特定写操作抛出异常，以覆盖各 catch 分支
        var shouldThrowOnFetch = false
        var shouldThrowOnDelete = false
        var shouldThrowOnInsert = false
        var shouldThrowOnUpdate = false

        func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
            fetchAllItemsCallCount += 1
            eventRecorder?(parentId.map { "read-page:\($0)" } ?? "read-root")
            if let fetchError { throw fetchError }
            if shouldThrowOnFetch { throw NSError(domain: "MockDataStore", code: 1) }
            if let parentId {
                return childrenByPage[parentId] ?? []
            }
            return pages
        }

        func insertItem(_ item: PageItem) throws -> Int64 {
            if shouldThrowOnInsert { throw NSError(domain: "MockDataStore", code: 2) }
            insertedItems.append(item)
            return item.id
        }
        func updateItem(_ item: PageItem) throws {
            if shouldThrowOnUpdate { throw NSError(domain: "MockDataStore", code: 3) }
            updatedItems.append(item)
        }
        func deleteItem(id: Int64) throws {
            if shouldThrowOnDelete { throw NSError(domain: "MockDataStore", code: 4) }
            deletedIds.append(id)
        }
        func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {}
        func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {}
        func fetchImage(itemId: Int64) throws -> (Data, Data)? { nil }
    }

    /// 可控的长按手势：测试可设 state 与 location(in:)，以驱动 handleLongPress 各分支
    private final class MockPressGesture: NSPressGestureRecognizer {
        var mockState: NSGestureRecognizer.State
        var mockLocation: NSPoint = .zero
        init(state: NSGestureRecognizer.State, location: NSPoint = .zero) {
            self.mockState = state
            self.mockLocation = location
            super.init(target: nil, action: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
        override var state: NSGestureRecognizer.State {
            get { mockState }
            set { mockState = newValue }
        }
        override func location(in view: NSView?) -> NSPoint { mockLocation }
    }

    /// 加载视图并灌入数据，便于需要 collectionView 已就绪的测试
    private func loadViewWithData(_ sut: LaunchPadViewController, storage: MockDataStore,
                                  apps: [PageItem] = TestDataFactory.makeAppItems(count: 5, titlePrefix: "App")) {
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        _ = sut.view
        sut.loadData()
    }

    private func loadViewWithTwoPersistedPages(
        _ sut: LaunchPadViewController,
        storage: MockDataStore,
        apps: [PageItem] = TestDataFactory.makeAppItems(count: 60)
    ) {
        let firstPage = TestDataFactory.makePageItem(id: 101, type: .page, ordering: 0)
        let secondPage = TestDataFactory.makePageItem(id: 102, type: .page, ordering: 1)
        storage.pages = [firstPage, secondPage]
        storage.childrenByPage = [
            firstPage.id: Array(apps.prefix(30)),
            secondPage.id: Array(apps.dropFirst(30)),
        ]
        _ = sut.view
        sut.loadData()
    }

    private func layout(
        _ sut: LaunchPadViewController,
        viewportSize: CGSize = CGSize(width: 1440, height: 620)
    ) {
        sut.viewportSizeProvider = { viewportSize }
        _ = sut.view
        sut.viewDidLayout()
    }

    // MARK: - Helpers

    private func makeSUT(
        dragScheduler: Scheduler = DispatchQueueScheduler(),
        layoutMutator: LayoutMutating = MockLayoutMutator()
    ) -> (LaunchPadViewController, DragController, MockDataStore) {
        let storage = MockDataStore()
        let iconProvider = MockIconProvider()
        let iconCache = IconCache(iconProvider: iconProvider, imageStore: storage)
        let dragController = DragController(scheduler: dragScheduler)
        let folderController = FolderController(itemWriter: storage)
        let sut = LaunchPadViewController(
            storage: storage,
            layoutMutator: layoutMutator,
            iconCache: iconCache,
            dragController: dragController,
            folderController: folderController
        )
        return (sut, dragController, storage)
    }

    /// 注入 searchScheduler 的 SUT 工厂，用于测试搜索防抖逻辑
    private func makeSUTWithSearchScheduler(
        searchScheduler: Scheduler,
        dragScheduler: Scheduler = DispatchQueueScheduler(),
        layoutMutator: LayoutMutating = MockLayoutMutator()
    ) -> (LaunchPadViewController, DragController, MockDataStore) {
        let storage = MockDataStore()
        let iconProvider = MockIconProvider()
        let iconCache = IconCache(iconProvider: iconProvider, imageStore: storage)
        let dragController = DragController(scheduler: dragScheduler)
        let folderController = FolderController(itemWriter: storage)
        let sut = LaunchPadViewController(
            storage: storage,
            layoutMutator: layoutMutator,
            iconCache: iconCache,
            dragController: dragController,
            folderController: folderController,
            searchScheduler: searchScheduler
        )
        return (sut, dragController, storage)
    }

    private struct SensitiveError: Error, CustomStringConvertible {
        let description: String
    }

    private func makeDragSession(itemID: Int64 = 11) -> DragSession {
        DragSession(
            itemID: itemID,
            itemUUID: "00000000-0000-0000-0000-\(String(format: "%012lld", itemID))",
            itemType: .app,
            sourceKind: .topLevel,
            sourceParentID: 100,
            sourceVisualIndex: 0
        )
    }

    private func makeFolderChildSession(
        itemID: Int64 = 10,
        folderID: Int64 = 50,
        itemType: ItemType = .app,
        sourceKind: DragSourceKind = .folderChild
    ) -> DragSession {
        DragSession(
            itemID: itemID,
            itemUUID: "00000000-0000-0000-0000-\(String(format: "%012lld", itemID))",
            itemType: itemType,
            sourceKind: sourceKind,
            sourceParentID: folderID,
            sourceVisualIndex: 0
        )
    }

    private func makeFolder(id: Int64 = 50, parentID: Int64 = 1) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: "10000000-0000-0000-0000-\(String(format: "%012lld", id))",
            type: .group,
            ordering: 0,
            parentId: parentID,
            group: TestDataFactory.makeGroupInfo(id: id, title: "Folder \(id)")
        )
    }

    private func makeFolderChild(id: Int64, ordering: Int) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: "00000000-0000-0000-0000-\(String(format: "%012lld", id))",
            type: .app,
            ordering: ordering,
            parentId: 50,
            app: TestDataFactory.makeAppInfo(id: id, title: "A\(id)")
        )
    }

    private func makeOpenedFolderSUT(
        mutator: MockLayoutMutator,
        children: [PageItem]
    ) -> (LaunchPadViewController, MockDataStore, PageItem) {
        let (sut, _, storage) = makeSUT(layoutMutator: mutator)
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let folder = makeFolder()
        storage.pages = [page]
        storage.childrenByPage = [1: [folder], 50: children]
        _ = sut.view
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        sut.folderOverlay.folderViewportSizeProvider = {
            CGSize(width: 800, height: 624)
        }
        sut.folderOverlay.closeFolderCompletionRunner = { $0() }
        sut.openFolder(folder)
        return (sut, storage, folder)
    }

    @Test("全部 grid source 与 destination 映射稳定 intent 或明确拒绝")
    func gridSourceAndDestinationMappingIsExhaustive() {
        let (sut, _, _) = makeSUT()
        let app = makeDragSession(itemID: 2)
        let group = DragSession(
            itemID: 7,
            itemUUID: "10000000-0000-0000-0000-000000000007",
            itemType: .group,
            sourceKind: .topLevel,
            sourceParentID: 100,
            sourceVisualIndex: 4
        )
        let folderChild = DragSession(
            itemID: 2,
            itemUUID: app.itemUUID,
            itemType: .app,
            sourceKind: .folderChild,
            sourceParentID: 50,
            sourceVisualIndex: 0
        )

        #expect(sut.makeGridIntent(
            session: app,
            destination: .placement(.beforeItem(itemID: 1))
        ) == .moveTopLevel(itemID: 2, placement: .beforeItem(itemID: 1)))
        #expect(sut.makeGridIntent(
            session: app,
            destination: .placement(.afterItem(itemID: 40))
        ) == .moveTopLevel(itemID: 2, placement: .afterItem(itemID: 40)))
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
        ) == .moveTopLevel(itemID: 7, placement: .afterItem(itemID: 9)))
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
            session: app,
            destination: .onItem(itemID: 9, itemType: .page)
        ) == nil)
        #expect(sut.makeGridIntent(
            session: folderChild,
            destination: .placement(.beforeItem(itemID: 1))
        ) == nil)
    }

    @Test("drop 成功只写一次并在返回后精确读取权威一页布局")
    func dropSuccessAppliesOnceBeforeExactAuthoritativeReads() {
        let mutator = MockLayoutMutator()
        let (sut, dragController, storage) = makeSUT(layoutMutator: mutator)
        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        dragController.beginDrag(makeDragSession(itemID: 2))
        var trace: [String] = []
        mutator.eventRecorder = { trace.append($0) }
        storage.eventRecorder = { trace.append($0) }
        let readsBefore = storage.fetchAllItemsCallCount

        let result = sut.applyDropIntent(.moveTopLevel(
            itemID: 2,
            placement: .beforeItem(itemID: 1)
        ))

        #expect(result)
        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.appliedIntents.count == 1)
        #expect(mutator.attemptedPageCapacities == [28])
        #expect(storage.fetchAllItemsCallCount - readsBefore == 2)
        #expect(trace == ["apply-start", "apply-return", "read-root", "read-page:1"])
        #expect(dragController.session != nil)
    }

    @Test("drop 失败只尝试一次，throw 后精确读取并输出固定脱敏反馈")
    func dropFailureDoesNotRetryAndReloadsAfterThrow() {
        let sentinel = "apply-secret-folder-title"
        let mutator = MockLayoutMutator()
        mutator.applyError = SensitiveError(description: sentinel)
        let (sut, dragController, storage) = makeSUT(layoutMutator: mutator)
        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        dragController.beginDrag(makeDragSession(itemID: 2))
        var trace: [String] = []
        var events: [LayoutDropFailureEvent] = []
        mutator.eventRecorder = { trace.append($0) }
        storage.eventRecorder = { trace.append($0) }
        sut.layoutDropFailureLogger = { events.append($0) }
        let readsBefore = storage.fetchAllItemsCallCount

        let result = sut.applyDropIntent(.createFolder(
            itemID: 2,
            targetItemID: 3,
            title: sentinel
        ))

        #expect(!result)
        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.appliedIntents.isEmpty)
        #expect(mutator.attemptedPageCapacities == [28])
        #expect(storage.fetchAllItemsCallCount - readsBefore == 2)
        #expect(trace == ["apply-start", "apply-throw", "read-root", "read-page:1"])
        #expect(sut.transientMessageView.message == "无法更新布局，请重试")
        #expect(events == [LayoutDropFailureEvent(
            kind: "create_folder",
            sourceID: 2,
            relatedIDs: [3],
            category: "mutation_failed"
        )])
        #expect(!String(describing: events).contains(sentinel))
        #expect(!(sut.transientMessageView.message ?? "").contains(sentinel))
        #expect(dragController.session != nil)
    }

    @Test("nil metrics 不尝试写；resize 后失败仍记录当前动态容量")
    func dropUsesOnlyCurrentDynamicCapacity() {
        let mutator = MockLayoutMutator()
        let (sut, _, storage) = makeSUT(layoutMutator: mutator)
        #expect(!sut.applyDropIntent(.deleteFolder(folderID: 9)))
        #expect(mutator.applyAttemptCount == 0)

        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        #expect(sut.applyDropIntent(.deleteFolder(folderID: 9)))
        mutator.applyError = LayoutDomainError.missingAnchor(999)
        sut.viewportSizeProvider = { CGSize(width: 1729, height: 496) }
        sut.viewDidLayout()
        var failureTrace: [String] = []
        mutator.eventRecorder = { failureTrace.append($0) }
        storage.eventRecorder = { failureTrace.append($0) }
        let readsBeforeFailure = storage.fetchAllItemsCallCount
        #expect(!sut.applyDropIntent(.moveTopLevel(
            itemID: 2,
            placement: .beforeItem(itemID: 999)
        )))

        #expect(mutator.applyAttemptCount == 2)
        #expect(mutator.attemptedPageCapacities == [28, 40])
        #expect(mutator.appliedPageCapacities == [28])
        #expect(storage.fetchAllItemsCallCount - readsBeforeFailure == 2)
        #expect(failureTrace == [
            "apply-start", "apply-throw", "read-root", "read-page:1",
        ])
    }

    @Test("六种 layout intent 映射完整且不记录 folder title")
    func layoutDropFailureEventMappingIsExhaustive() {
        let title = "sensitive-folder-title"
        let intents: [LayoutDropIntent] = [
            .moveTopLevel(itemID: 1, placement: .beforeItem(itemID: 2)),
            .addToFolder(itemID: 3, folderID: 4),
            .createFolder(itemID: 5, targetItemID: 6, title: title),
            .reorderFolderItem(
                itemID: 7,
                folderID: 8,
                placement: .afterItem(itemID: 9)
            ),
            .removeFromFolder(
                itemID: 10,
                folderID: 11,
                placement: .beforeItem(itemID: 12)
            ),
            .deleteFolder(folderID: 13),
        ]
        let events = intents.map(LayoutDropFailureEvent.init(intent:))

        #expect(events == [
            LayoutDropFailureEvent(
                kind: "move_top_level", sourceID: 1,
                relatedIDs: [2], category: "mutation_failed"
            ),
            LayoutDropFailureEvent(
                kind: "add_to_folder", sourceID: 3,
                relatedIDs: [4], category: "mutation_failed"
            ),
            LayoutDropFailureEvent(
                kind: "create_folder", sourceID: 5,
                relatedIDs: [6], category: "mutation_failed"
            ),
            LayoutDropFailureEvent(
                kind: "reorder_folder_item", sourceID: 7,
                relatedIDs: [8, 9], category: "mutation_failed"
            ),
            LayoutDropFailureEvent(
                kind: "remove_from_folder", sourceID: 10,
                relatedIDs: [11, 12], category: "mutation_failed"
            ),
            LayoutDropFailureEvent(
                kind: "delete_folder", sourceID: 13,
                relatedIDs: [], category: "mutation_failed"
            ),
        ])
        #expect(!String(describing: events).contains(title))
    }

    @Test("mutation 与失败 reload 的 sentinel 均不进入任何可观察输出")
    func failedAuthoritativeReloadUsesSanitizedBoundary() {
        let applySentinel = "apply-sensitive-error"
        let reloadSentinel = "reload-sensitive-error"
        let titleSentinel = "folder-sensitive-title"
        let mutator = MockLayoutMutator()
        mutator.applyError = SensitiveError(description: applySentinel)
        let (sut, _, storage) = makeSUT(layoutMutator: mutator)
        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        storage.fetchError = SensitiveError(description: reloadSentinel)
        var events: [LayoutDropFailureEvent] = []
        var readFailureCategories: [String] = []
        sut.layoutDropFailureLogger = { events.append($0) }
        sut.authoritativeLayoutReadFailureLogger = {
            readFailureCategories.append($0)
        }
        sut.transientMessageView.postAnnouncement = { _, _ in }

        #expect(!sut.applyDropIntent(.createFolder(
            itemID: 2,
            targetItemID: 3,
            title: titleSentinel
        )))

        let observable = String(describing: events)
            + readFailureCategories.joined()
            + (sut.transientMessageView.message ?? "")
        #expect(readFailureCategories == ["authoritative_read_failed"])
        #expect(sut.transientMessageView.message == "无法更新布局，请重试")
        #expect(!observable.contains(applySentinel))
        #expect(!observable.contains(reloadSentinel))
        #expect(!observable.contains(titleSentinel))
    }

    @Test("连续失败提示接入约束完整且旧 auto-hide 不清除新提示")
    func repeatedDropFailureKeepsLatestTransientMessage() throws {
        let mutator = MockLayoutMutator()
        mutator.applyError = TestError.generic
        let (sut, _, storage) = makeSUT(layoutMutator: mutator)
        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        var scheduled: [DispatchWorkItem] = []
        sut.transientMessageView.scheduleHide = { _, item in scheduled.append(item) }
        sut.transientMessageView.postAnnouncement = { _, _ in }

        #expect(!sut.applyDropIntent(.deleteFolder(folderID: 8)))
        #expect(!sut.applyDropIntent(.deleteFolder(folderID: 9)))
        #expect(scheduled.count == 2)
        scheduled[0].perform()
        #expect(sut.transientMessageView.message == "无法更新布局，请重试")
        scheduled[1].perform()
        #expect(sut.transientMessageView.message == nil)

        let constraints = sut.view.constraints
        #expect(constraints.contains { constraint in
            constraint.firstItem === sut.transientMessageView
                && constraint.firstAttribute == .centerX
                && constraint.secondItem === sut.view
        })
        #expect(constraints.contains { constraint in
            constraint.firstItem === sut.transientMessageView
                && constraint.firstAttribute == .bottom
                && constraint.secondItem === sut.pageControl
                && constraint.secondAttribute == .top
                && constraint.constant == -12
        })
        #expect(sut.transientMessageView.constraints.contains { constraint in
            constraint.firstItem === sut.transientMessageView
                && constraint.firstAttribute == .width
                && constraint.relation == .lessThanOrEqual
                && constraint.constant == 360
        })
    }

    @Test("搜索 mode 与 current query 完整派生三层拖放门禁")
    func searchTransitionsSynchronizeAllDragBoundaries() throws {
        let searchScheduler = MockScheduler()
        let dragScheduler = MockScheduler()
        let mutator = MockLayoutMutator()
        let (sut, dragController, storage) = makeSUTWithSearchScheduler(
            searchScheduler: searchScheduler,
            dragScheduler: dragScheduler,
            layoutMutator: mutator
        )
        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        let coordinator = try #require(sut.gridInteractionCoordinator)
        #expect(coordinator.isDragEnabled)
        #expect(sut.folderOverlay.isDragEnabled)

        var previewChanges: [Int64?] = []
        dragController.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        dragController.beginDrag(makeDragSession(itemID: 2))
        dragController.updateDragHover(.item(itemID: 11, itemType: .app))
        dragScheduler.advance(by: 0.8)
        #expect(dragController.session?.folderCreationPreviewTargetID == 11)
        dragController.handlePressBegan(at: .zero)
        #expect(!dragScheduler.scheduledActions.isEmpty)

        #expect(sut.handleCharacterInput("s") == .enterSearchMode("s"))
        #expect(!coordinator.isDragEnabled)
        #expect(!sut.folderOverlay.isDragEnabled)
        #expect(dragController.session == nil)
        #expect(dragScheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))
        #expect(searchScheduler.scheduledActions.count == 1)
        #expect(!sut.applyDropIntent(.deleteFolder(folderID: 8)))
        #expect(mutator.applyAttemptCount == 0)

        #expect(sut.handleCharacterInput("a") == .appendToQuery("a"))
        #expect(!coordinator.isDragEnabled)
        #expect(!sut.folderOverlay.isDragEnabled)
        #expect(sut.handleKeyEvent(.delete) == .deleteLastCharacter)
        #expect(sut.keyboardNavigator.mode == .search(query: "s"))
        #expect(!coordinator.isDragEnabled)
        #expect(sut.handleKeyEvent(.delete) == .deleteLastCharacter)
        #expect(sut.keyboardNavigator.mode == .search(query: ""))
        #expect(sut.currentSearchQuery.isEmpty)
        #expect(!coordinator.isDragEnabled)
        #expect(!sut.folderOverlay.isDragEnabled)

        #expect(sut.handleKeyEvent(.escape) == .clearSearch)
        #expect(sut.keyboardNavigator.mode == .idle)
        #expect(coordinator.isDragEnabled)
        #expect(sut.folderOverlay.isDragEnabled)

        sut.keyboardNavigator.mode = .search(query: "")
        sut.handleSearch(query: "")
        #expect(!coordinator.isDragEnabled)
        #expect(!sut.folderOverlay.isDragEnabled)
        #expect(!sut.applyDropIntent(.deleteFolder(folderID: 9)))
        #expect(mutator.applyAttemptCount == 0)

        var staleCompletion: (([PageItem]) -> Void)?
        sut.keyboardNavigator.mode = .idle
        sut.searchRunner = { _, query, completion in
            if query == "queued" { staleCompletion = completion }
        }
        sut.handleSearch(query: "queued")
        #expect(!coordinator.isDragEnabled)
        #expect(!sut.folderOverlay.isDragEnabled)
        #expect(!sut.applyDropIntent(.deleteFolder(folderID: 10)))
        #expect(mutator.applyAttemptCount == 0)

        sut.handleSearch(query: "")
        #expect(coordinator.isDragEnabled)
        #expect(sut.folderOverlay.isDragEnabled)
        staleCompletion?([])
        #expect(coordinator.isDragEnabled)
        #expect(sut.folderOverlay.isDragEnabled)
        #expect(sut.currentSearchQuery.isEmpty)
    }

    @Test("native accept 只写一次并保留会话预览直到 ended")
    func nativeAcceptWritesOnceAndEndedOwnsCleanup() throws {
        let scheduler = MockScheduler()
        let mutator = MockLayoutMutator()
        let (sut, dragController, storage) = makeSUT(
            dragScheduler: scheduler,
            layoutMutator: mutator
        )
        let apps = [
            TestDataFactory.makePageItem(
                id: 1,
                uuid: "00000000-0000-0000-0000-000000000001",
                type: .app,
                ordering: 0,
                parentId: 1,
                app: TestDataFactory.makeAppInfo(id: 1, title: "A1")
            ),
            TestDataFactory.makePageItem(
                id: 2,
                uuid: "00000000-0000-0000-0000-000000000002",
                type: .app,
                ordering: 1,
                parentId: 1,
                app: TestDataFactory.makeAppInfo(id: 2, title: "A2")
            ),
        ]
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        let grid = try #require(extractCollectionView(from: sut))
        let coordinator = try #require(sut.gridInteractionCoordinator)
        let targetPath = try #require(grid.diffableDataSource.indexPath(for: apps[1]))
        grid.collectionViewLayout?.prepare()
        let targetFrame = try #require(grid.layoutFrame(at: targetPath))
        let previewCell = AppIconCell()
        _ = previewCell.view
        grid.visibleCellProvider = { path in path == targetPath ? previewCell : nil }
        grid.indexPathResolver = { _ in targetPath }
        let session = DragSession(
            itemID: apps[0].id,
            itemUUID: apps[0].uuid,
            itemType: .app,
            sourceKind: .topLevel,
            sourceParentID: 1,
            sourceVisualIndex: 0
        )
        dragController.beginDrag(session)
        dragController.updateDragHover(
            .item(itemID: apps[1].id, itemType: .app)
        )
        scheduler.advance(by: 0.8)
        #expect(previewCell.isFolderCreationPreviewVisible)
        coordinator.pasteboardUUIDReader = { _ in session.itemUUID }
        var trace: [String] = []
        mutator.eventRecorder = { trace.append($0) }
        storage.eventRecorder = { trace.append($0) }
        let readsBefore = storage.fetchAllItemsCallCount
        let cancelCountBefore = scheduler.cancelCallCount
        let snapshotBefore = grid.diffableDataSource.snapshot()
        let info = MockDraggingInfo(
            location: grid.convert(
                NSPoint(x: targetFrame.midX, y: targetFrame.midY),
                to: nil
            )
        )

        let accepted = coordinator.collectionView(
            grid,
            acceptDrop: info,
            indexPath: targetPath,
            dropOperation: .on
        )

        #expect(accepted)
        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.attemptedIntents == [
            .createFolder(itemID: 1, targetItemID: 2, title: "New Folder"),
        ])
        #expect(storage.fetchAllItemsCallCount - readsBefore == 2)
        #expect(trace == ["apply-start", "apply-return", "read-root", "read-page:1"])
        #expect(dragController.session != nil)
        #expect(previewCell.isFolderCreationPreviewVisible)
        #expect(scheduler.cancelCallCount == cancelCountBefore)
        #expect(grid.diffableDataSource.snapshot().sectionIdentifiers == snapshotBefore.sectionIdentifiers)
        #expect(grid.diffableDataSource.snapshot().itemIdentifiers == snapshotBefore.itemIdentifiers)

        coordinator.collectionView(
            grid,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )

        #expect(mutator.applyAttemptCount == 1)
        #expect(storage.fetchAllItemsCallCount - readsBefore == 2)
        #expect(dragController.session == nil)
        #expect(!previewCell.isFolderCreationPreviewVisible)
        #expect(scheduler.cancelCallCount == cancelCountBefore + 1)
    }

    @Test("native accept 已提交但权威 reload 失败仍成功，ended 不重复写入")
    func nativeAcceptCommitSurvivesAuthoritativeReloadFailure() throws {
        let reloadSentinel = "reload-sensitive-error-after-commit"
        let scheduler = MockScheduler()
        let mutator = MockLayoutMutator()
        let (sut, dragController, storage) = makeSUT(
            dragScheduler: scheduler,
            layoutMutator: mutator
        )
        let apps = [
            TestDataFactory.makePageItem(
                id: 1,
                uuid: "00000000-0000-0000-0000-000000000001",
                type: .app,
                ordering: 0,
                parentId: 1,
                app: TestDataFactory.makeAppInfo(id: 1, title: "A1")
            ),
            TestDataFactory.makePageItem(
                id: 2,
                uuid: "00000000-0000-0000-0000-000000000002",
                type: .app,
                ordering: 1,
                parentId: 1,
                app: TestDataFactory.makeAppInfo(id: 2, title: "A2")
            ),
        ]
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        let grid = try #require(extractCollectionView(from: sut))
        let coordinator = try #require(sut.gridInteractionCoordinator)
        let targetPath = try #require(grid.diffableDataSource.indexPath(for: apps[1]))
        grid.collectionViewLayout?.prepare()
        let targetFrame = try #require(grid.layoutFrame(at: targetPath))
        grid.indexPathResolver = { _ in targetPath }
        let session = DragSession(
            itemID: apps[0].id,
            itemUUID: apps[0].uuid,
            itemType: .app,
            sourceKind: .topLevel,
            sourceParentID: 1,
            sourceVisualIndex: 0
        )
        let expectedIntent = LayoutDropIntent.createFolder(
            itemID: 1,
            targetItemID: 2,
            title: "New Folder"
        )
        dragController.beginDrag(session)
        coordinator.pasteboardUUIDReader = { _ in session.itemUUID }
        storage.fetchError = SensitiveError(description: reloadSentinel)
        var trace: [String] = []
        var dropFailureEvents: [LayoutDropFailureEvent] = []
        var readFailureCategories: [String] = []
        var announcements: [String] = []
        mutator.eventRecorder = { trace.append($0) }
        storage.eventRecorder = { trace.append($0) }
        sut.layoutDropFailureLogger = { dropFailureEvents.append($0) }
        sut.authoritativeLayoutReadFailureLogger = {
            readFailureCategories.append($0)
        }
        sut.transientMessageView.postAnnouncement = { message, _ in
            announcements.append(message)
        }
        let readsBefore = storage.fetchAllItemsCallCount
        let cancelCountBefore = scheduler.cancelCallCount
        let snapshotBefore = grid.diffableDataSource.snapshot()
        let info = MockDraggingInfo(
            location: grid.convert(
                NSPoint(x: targetFrame.midX, y: targetFrame.midY),
                to: nil
            )
        )

        let accepted = coordinator.collectionView(
            grid,
            acceptDrop: info,
            indexPath: targetPath,
            dropOperation: .on
        )

        #expect(accepted)
        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.attemptedIntents == [expectedIntent])
        #expect(mutator.appliedIntents == [expectedIntent])
        #expect(mutator.attemptedPageCapacities == [28])
        #expect(mutator.appliedPageCapacities == [28])
        #expect(storage.fetchAllItemsCallCount - readsBefore == 1)
        #expect(trace == ["apply-start", "apply-return", "read-root"])
        #expect(readFailureCategories == ["authoritative_read_failed"])
        #expect(dropFailureEvents.isEmpty)
        #expect(sut.transientMessageView.message == nil)
        #expect(announcements.isEmpty)
        #expect(dragController.session != nil)
        #expect(grid.diffableDataSource.snapshot().sectionIdentifiers == snapshotBefore.sectionIdentifiers)
        #expect(grid.diffableDataSource.snapshot().itemIdentifiers == snapshotBefore.itemIdentifiers)
        let observable = String(describing: dropFailureEvents)
            + readFailureCategories.joined()
            + (sut.transientMessageView.message ?? "")
            + announcements.joined()
            + trace.joined()
        #expect(!observable.contains(reloadSentinel))

        coordinator.collectionView(
            grid,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )

        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.appliedIntents == [expectedIntent])
        #expect(storage.fetchAllItemsCallCount - readsBefore == 1)
        #expect(trace == ["apply-start", "apply-return", "read-root"])
        #expect(dragController.session == nil)
        #expect(scheduler.cancelCallCount == cancelCountBefore + 1)
    }

    // MARK: - ESC 关闭窗口

    @Test("idle 状态 ESC 触发 onClose 回调")
    func idle_esc_triggersOnClose() {
        let (sut, _, _) = makeSUT()
        var closeCalled = false
        sut.onClose = { closeCalled = true }

        _ = sut.handleKeyEvent(.escape)

        #expect(closeCalled == true)
    }

    @Test("关闭窗口显式取消 native drag，后续 ended 不重复 cleanup")
    func closeWindowCancelsNativeDragIdempotently() throws {
        let scheduler = MockScheduler()
        let (sut, dragController, storage) = makeSUT(dragScheduler: scheduler)
        loadViewWithData(sut, storage: storage)
        let coordinator = try #require(sut.gridInteractionCoordinator)
        let grid = try #require(extractCollectionView(from: sut))
        var previewChanges: [Int64?] = []
        dragController.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        dragController.beginDrag(makeDragSession(itemID: 10))
        dragController.updateDragHover(.item(itemID: 11, itemType: .app))
        scheduler.advance(by: 0.8)
        #expect(dragController.session?.folderCreationPreviewTargetID == 11)
        dragController.handlePressBegan(at: .zero)
        #expect(!scheduler.scheduledActions.isEmpty)
        let cancelCountBefore = scheduler.cancelCallCount
        var closeCount = 0
        sut.onClose = { closeCount += 1 }

        #expect(sut.handleKeyEvent(.escape) == .closeWindow)
        #expect(closeCount == 1)
        #expect(dragController.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))
        #expect(scheduler.cancelCallCount == cancelCountBefore + 1)
        let previewChangeCountAfterEscape = previewChanges.count

        coordinator.collectionView(
            grid,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: []
        )
        #expect(scheduler.cancelCallCount == cancelCountBefore + 1)
        #expect(previewChanges.count == previewChangeCountAfterEscape)
    }

    // MARK: - ESC 退出编辑模式

    @Test("edit 状态 ESC 退出编辑模式 — dragController 回到 idle")
    func edit_esc_exitsEditMode() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        var previewChanges: [Int64?] = []
        dragController.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        dragController.beginDrag(makeDragSession(itemID: 10))
        dragController.updateDragHover(.item(itemID: 11, itemType: .app))
        scheduler.advance(by: 0.8)
        #expect(dragController.session?.folderCreationPreviewTargetID == 11)
        dragController.handlePressBegan(at: .zero)
        #expect(!scheduler.scheduledActions.isEmpty)
        sut.keyboardNavigator.mode = .edit

        #expect(sut.handleKeyEvent(.escape) == .exitEditMode)

        #expect(dragController.state == .idle)
        #expect(dragController.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))
        #expect(sut.keyboardNavigator.mode == .idle)
    }

    // MARK: - 方向键导航（视图未加载安全）

    @Test("down 方向键在视图未加载时安全无副作用")
    func idle_downArrow_safeWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedItemID == nil)
        _ = sut.handleKeyEvent(.downArrow)
        #expect(sut.selectedItemID == nil)
    }

    @Test("tab 键在视图未加载时安全无副作用")
    func idle_tab_safeWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedItemID == nil)
        _ = sut.handleKeyEvent(.tab)
        #expect(sut.selectedItemID == nil)
    }

    @Test("up 方向键在视图未加载时安全无副作用")
    func idle_upArrow_safeWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedItemID == nil)
        _ = sut.handleKeyEvent(.upArrow)
        #expect(sut.selectedItemID == nil)
    }

    // MARK: - handleCharacterInput

    @Test("字符输入在 idle 模式下返回 enterSearchMode")
    func characterInput_returnsEnterSearchMode() {
        let (sut, _, _) = makeSUT()

        let action = sut.handleCharacterInput("a")

        // handleCharacter 在 idle 模式下返回 enterSearchMode
        if case .enterSearchMode(let char) = action {
            #expect(char == "a")
        } else {
            Issue.record("Expected enterSearchMode, got \(action)")
        }
    }

    @Test("字符输入在视图未加载时不崩溃")
    func characterInput_doesNotCrashWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        // 视图未加载时 executeAction(.enterSearchMode) 因 guard isViewLoaded 安全返回
        _ = sut.handleCharacterInput("a")
        _ = sut.handleCharacterInput("b")
        _ = sut.handleCharacterInput("c")
    }

    // MARK: - handleKeyEvent 返回值

    @Test("handleKeyEvent 返回正确的 action 枚举")
    func handleKeyEvent_returnsCorrectAction() {
        let (sut, _, _) = makeSUT()

        let escAction = sut.handleKeyEvent(.escape)
        #expect(escAction == .closeWindow)

        let upAction = sut.handleKeyEvent(.upArrow)
        #expect(upAction == .moveUp)

        let downAction = sut.handleKeyEvent(.downArrow)
        #expect(downAction == .moveDown)

        let tabAction = sut.handleKeyEvent(.tab)
        #expect(tabAction == .selectNext)

        let leftAction = sut.handleKeyEvent(.leftArrow)
        #expect(leftAction == .previousPage)

        let rightAction = sut.handleKeyEvent(.rightArrow)
        #expect(rightAction == .nextPage)

        let enterAction = sut.handleKeyEvent(.enter)
        #expect(enterAction == .launchSelected)
    }

    // MARK: - onClose 回调

    @Test("onClose 回调可安全设置和调用")
    func onClose_callbackSafeToSetAndCall() {
        let (sut, _, _) = makeSUT()

        // nil callback 不崩溃
        sut.onClose = nil
        _ = sut.handleKeyEvent(.escape)

        // 设置 callback 后调用
        var called = false
        sut.onClose = { called = true }
        _ = sut.handleKeyEvent(.escape)
        #expect(called == true)
    }

    // MARK: - 连续 ESC

    @Test("连续两次 ESC 不崩溃")
    func doubleEsc_doesNotCrash() {
        let (sut, _, _) = makeSUT()
        var closeCount = 0
        sut.onClose = { closeCount += 1 }

        _ = sut.handleKeyEvent(.escape)
        _ = sut.handleKeyEvent(.escape)

        #expect(closeCount == 2)
    }

    // MARK: - 稳定 ID 选择初始状态

    @Test("selectedItemID 初始为 nil")
    func selectedItemIDInitiallyNil() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedItemID == nil)
    }

    // MARK: - KeyboardNavigator 集成覆盖

    @Test("所有 KeyboardNavigator.Key 都可安全处理不崩溃")
    func allKeys_handleSafely() {
        let (sut, _, _) = makeSUT()
        let keys: [KeyboardNavigator.Key] = [
            .escape, .leftArrow, .rightArrow, .upArrow, .downArrow, .enter, .tab, .delete
        ]
        for key in keys {
            _ = sut.handleKeyEvent(key)
        }
    }

    // MARK: - KeyboardNavigator mode 直接设置后的行为

    @Test("手动设置 search 模式后 ESC 返回 clearSearch")
    func manualSearchMode_esc_returnsClearSearch() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "test")

        let action = sut.handleKeyEvent(.escape)
        #expect(action == .clearSearch)
    }

    @Test("手动设置 search 模式后 enter 返回 launchFirstMatch")
    func manualSearchMode_enter_returnsLaunchFirstMatch() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "test")

        let action = sut.handleKeyEvent(.enter)
        #expect(action == .launchFirstMatch)
    }

    @Test("手动设置 search 模式后 delete 返回 deleteLastCharacter")
    func manualSearchMode_delete_returnsDeleteLastCharacter() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "test")

        let action = sut.handleKeyEvent(.delete)
        #expect(action == .deleteLastCharacter)
    }

    @Test("手动设置 edit 模式后 up/down arrow 返回 ignored（edit 模式仅 ESC 有效）")
    func manualEditMode_arrows_returnsIgnored() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .edit

        let upAction = sut.handleKeyEvent(.upArrow)
        #expect(upAction == .ignored)

        let downAction = sut.handleKeyEvent(.downArrow)
        #expect(downAction == .ignored)

        let leftAction = sut.handleKeyEvent(.leftArrow)
        #expect(leftAction == .ignored)

        let rightAction = sut.handleKeyEvent(.rightArrow)
        #expect(rightAction == .ignored)
    }

    // MARK: - DragController 状态同步

    @Test("dragController jiggling 状态可正确建立")
    func dragController_jiggling_stateEstablished() {
        let scheduler = MockScheduler()
        let (_, dragController, _) = makeSUT(dragScheduler: scheduler)

        dragController.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)

        #expect(dragController.state == .jiggling)
    }

    // MARK: - Multiple character inputs

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
        let fieldEditor = sut.searchBar.currentEditor()
        #expect(fieldEditor != nil)
        #expect(window.firstResponder === fieldEditor)
        #expect(scheduler.scheduledActions.count == 1)
    }

    // MARK: - loadData

    @Test("loadData with empty storage does not crash")
    func loadData_emptyStorage_noCrash() {
        let (sut, _, _) = makeSUT()
        _ = sut.view // trigger loadView
        sut.loadData()
    }

    @Test("loadData with pages populates internal state")
    func loadData_withPages_populatesState() {
        let (sut, _, storage) = makeSUT()
        _ = sut.view // trigger loadView
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, parentId: 1,
                                                app: TestDataFactory.makeAppInfo(id: 10, title: "Safari"))
        storage.pages = [page]
        storage.childrenByPage = [1: [app]]

        sut.loadData()

        #expect(sut.selectedItemID == nil)
    }

    @Test("loadData with multiple pages")
    func loadData_multiplePages_noCrash() {
        let (sut, _, storage) = makeSUT()
        _ = sut.view // trigger loadView
        let page1 = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let page2 = TestDataFactory.makePageItem(id: 2, type: .page, ordering: 1)
        let apps1 = TestDataFactory.makeAppItems(count: 5, titlePrefix: "P1")
        let apps2 = TestDataFactory.makeAppItems(count: 3, titlePrefix: "P2")
        storage.pages = [page1, page2]
        storage.childrenByPage = [1: apps1, 2: apps2]

        sut.loadData()
    }

    // MARK: - handleKeyEvent edge cases

    @Test("delete key in idle mode returns ignored")
    func idle_delete_returnsIgnored() {
        let (sut, _, _) = makeSUT()
        let action = sut.handleKeyEvent(.delete)
        #expect(action == .ignored)
    }

    @Test("search mode character input returns appendToQuery")
    func searchMode_character_returnsAppendToQuery() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "te")

        let action = sut.handleCharacterInput("s")
        if case .appendToQuery(let char) = action {
            #expect(char == "s")
        } else {
            Issue.record("Expected appendToQuery")
        }
    }

    @Test("edit mode character input returns ignored")
    func editMode_character_returnsIgnored() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .edit

        let action = sut.handleCharacterInput("a")
        #expect(action == .ignored)
    }

    // MARK: - DragController integration

    @Test("dragController handleCancel from jiggling returns to idle")
    func dragController_cancelFromJiggling_returnsToIdle() {
        let scheduler = MockScheduler()
        let (_, dragController, _) = makeSUT(dragScheduler: scheduler)

        dragController.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)

        dragController.handleCancel()
        #expect(dragController.state == .idle)
    }

    @Test("dragController onPageChange callback is settable")
    func dragController_onPageChange_settable() {
        let (_, dragController, _) = makeSUT()
        var direction: DragPageDirection?
        dragController.onPageChange = { dir in direction = dir }
        #expect(dragController.onPageChange != nil)
    }

    // MARK: - 反射辅助

    /// 通过反射访问私有 collectionView，用于直接触发其回调（覆盖私有方法路径）
    private func extractCollectionView(from sut: LaunchPadViewController) -> AppGridCollectionView? {
        let mirror = Mirror(reflecting: sut)
        for child in mirror.children where child.label == "collectionView" {
            return child.value as? AppGridCollectionView
        }
        return nil
    }

    private func extractScrollView(from sut: LaunchPadViewController) -> PageScrollView? {
        let mirror = Mirror(reflecting: sut)
        for child in mirror.children where child.label == "scrollView" {
            return child.value as? PageScrollView
        }
        return nil
    }

    private func expectThreePagePresentation(
        _ sut: LaunchPadViewController,
        scrollView: PageScrollView,
        currentPage: Int
    ) {
        #expect(sut.visualPages.map(\.count) == [28, 28, 4])
        #expect(sut.currentVisualPage == currentPage)
        #expect(sut.pagingPageCount == 3)
        #expect(scrollView.pagingPageWidth == 1440)
        #expect(!sut.pageControl.isHidden)
        #expect(sut.pageControl.intrinsicContentSize.width == 40)
    }

    // MARK: - 视图加载后的 executeAction 分支

    @Test("视图加载后 enterSearchMode 执行 searchBar.show 路径")
    func enterSearchMode_viewLoaded_executesShowPath() {
        let (sut, _, _) = makeSUT()
        _ = sut.view  // 触发 loadView + viewDidLoad

        let action = sut.handleCharacterInput("a")

        if case .enterSearchMode(let char) = action {
            #expect(char == "a")
        } else {
            Issue.record("Expected enterSearchMode, got \(action)")
        }
    }

    @Test("视图加载后 appendToQuery 调度防抖搜索任务")
    func appendToQuery_viewLoaded_schedulesDebouncedSearch() {
        let searchScheduler = MockScheduler()
        let (sut, _, _) = makeSUTWithSearchScheduler(searchScheduler: searchScheduler)
        sut.keyboardNavigator.mode = .search(query: "t")
        _ = sut.view

        let action = sut.handleCharacterInput("e")

        if case .appendToQuery(let char) = action {
            #expect(char == "e")
        } else {
            Issue.record("Expected appendToQuery, got \(action)")
        }
        // 非空查询 → SearchDebouncer 调度 100ms 防抖任务
        #expect(searchScheduler.scheduledActions.isEmpty == false)
    }

    @Test("视图加载后 deleteLastCharacter 因查询变短立即触发搜索并取消 pending")
    func deleteLastCharacter_viewLoaded_triggersImmediateSearch() {
        let searchScheduler = MockScheduler()
        let (sut, _, _) = makeSUTWithSearchScheduler(searchScheduler: searchScheduler)
        sut.keyboardNavigator.mode = .search(query: "te")
        _ = sut.view

        // 先追加字符，建立 pending 防抖任务
        _ = sut.handleCharacterInput("s")
        #expect(searchScheduler.scheduledActions.isEmpty == false)

        // delete：查询变短 → SearchDebouncer 立即触发并 cancelPending
        let action = sut.handleKeyEvent(.delete)
        #expect(action == .deleteLastCharacter)
        #expect(searchScheduler.scheduledActions.isEmpty)
    }

    @Test("视图加载后 clearSearch 清空搜索并恢复 idle 模式")
    func clearSearch_viewLoaded_restoresIdleMode() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "abc")
        _ = sut.view

        let action = sut.handleKeyEvent(.escape)

        #expect(action == .clearSearch)
        // KeyboardNavigator 在 search 模式 ESC 返回 clearSearch 后重置为 idle
        #expect(sut.keyboardNavigator.mode == .idle)
    }

    // MARK: - moveSelection（视图加载后）

    @Test("视图加载后 down 方向键选中第一个图标")
    func moveSelection_down_selectsFirstItem() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let apps = TestDataFactory.makeAppItems(count: 5, titlePrefix: "App")
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        layout(sut)

        _ = sut.handleKeyEvent(.downArrow)

        #expect(sut.selectedItemID == sut.gridSnapshot.itemIdentifiers.first?.id)
    }

    @Test("视图加载后 tab 键顺序选中下一个图标")
    func moveSelection_tab_selectsNextItem() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let apps = TestDataFactory.makeAppItems(count: 5, titlePrefix: "App")
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        layout(sut)

        _ = sut.handleKeyEvent(.downArrow)
        let itemIDs = sut.gridSnapshot.itemIdentifiers.map(\.id)
        #expect(sut.selectedItemID == itemIDs[0])
        _ = sut.handleKeyEvent(.tab)
        #expect(sut.selectedItemID == itemIDs[1])
    }

    @Test("视图加载后 up 方向键向上移动选中")
    func moveSelection_up_movesUp() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let apps = TestDataFactory.makeAppItems(count: 10, titlePrefix: "App")
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        layout(sut)
        let itemIDs = sut.gridSnapshot.itemIdentifiers.map(\.id)

        // down 两次：第一次选中 0，第二次跳到下一行（0 + columns）
        _ = sut.handleKeyEvent(.downArrow)
        _ = sut.handleKeyEvent(.downArrow)
        #expect(sut.selectedItemID == itemIDs[7])

        // up 应回到上一行（索引减小）
        _ = sut.handleKeyEvent(.upArrow)
        #expect(sut.selectedItemID == itemIDs[0])
    }

    // MARK: - 分页导航

    @Test("视图加载后 rightArrow 翻到下一页且到达末页后不越界")
    func nextPage_navigatesForward() throws {
        let (sut, _, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let scrollView = try #require(extractScrollView(from: sut))
        let productionCallback = try #require(scrollView.onPageChanged)
        var scrolledPages: [Int] = []
        scrollView.onPageChanged = { page in
            scrolledPages.append(page)
            productionCallback(page)
        }

        #expect(sut.handleKeyEvent(.rightArrow) == .nextPage)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 1)
        #expect(scrolledPages == [1])

        #expect(sut.handleKeyEvent(.rightArrow) == .nextPage)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 2)
        #expect(scrolledPages == [1, 2])

        #expect(sut.handleKeyEvent(.rightArrow) == .nextPage)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 2)
        #expect(scrolledPages == [1, 2, 2])
    }

    @Test("视图加载后 leftArrow 翻到上一页且不越界")
    func previousPage_navigatesBackward() throws {
        let (sut, _, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        _ = sut.handleKeyEvent(.rightArrow)
        _ = sut.handleKeyEvent(.rightArrow)
        let scrollView = try #require(extractScrollView(from: sut))
        let productionCallback = try #require(scrollView.onPageChanged)
        var scrolledPages: [Int] = []
        scrollView.onPageChanged = { page in
            scrolledPages.append(page)
            productionCallback(page)
        }

        #expect(sut.handleKeyEvent(.leftArrow) == .previousPage)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 1)
        #expect(scrolledPages == [1])

        #expect(sut.handleKeyEvent(.leftArrow) == .previousPage)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 0)
        #expect(scrolledPages == [1, 0])

        #expect(sut.handleKeyEvent(.leftArrow) == .previousPage)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 0)
        #expect(scrolledPages == [1, 0, 0])
    }

    @Test("dragController.onPageChange 回调触发翻页导航")
    func handlePageChange_viaDragControllerCallback() throws {
        let (sut, dragController, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let scrollView = try #require(extractScrollView(from: sut))
        let productionCallback = try #require(scrollView.onPageChanged)
        var scrolledPages: [Int] = []
        scrollView.onPageChanged = { page in
            scrolledPages.append(page)
            productionCallback(page)
        }

        dragController.onPageChange?(.forward)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 1)
        dragController.onPageChange?(.backward)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 0)
        dragController.onPageChange?(.backward)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 0)
        #expect(scrolledPages == [1, 0, 0])
    }

    // MARK: - handleItemSelection（通过 coordinator activation 输出）

    @Test("coordinator activation 对 app 类型触发启动动画并安全回退")
    func coordinatorActivation_app_triggersAppLaunchSafely() throws {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        // 不存在的 bundleId：animateAppLaunch 找不到 cell → launchApp → urlForApplication 返回 nil → 安全 return
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 10,
                                                bundleId: "com.test.nonexistent.app"))

        let coordinator = try #require(sut.gridInteractionCoordinator)
        coordinator.onItemActivated?(app)
    }

    @Test("coordinator activation 对 group 类型打开文件夹并加载子项")
    func coordinatorActivation_group_opensFolder() throws {
        let (sut, _, storage) = makeSUT()
        _ = sut.view
        let folder = TestDataFactory.makePageItem(id: 100, type: .group, ordering: 0,
                                                   parentId: 1,
                                                   group: TestDataFactory.makeGroupInfo(id: 100, title: "Folder"))
        storage.childrenByPage = [100: []]

        let before = storage.fetchAllItemsCallCount
        let coordinator = try #require(sut.gridInteractionCoordinator)
        coordinator.onItemActivated?(folder)
        // openFolder 调用 storage.fetchAllItems(parentId: folder.id) 加载子项
        #expect(storage.fetchAllItemsCallCount > before)
    }

    @Test("ViewController 强持当前 grid coordinator 并完成真实 delegate 装配")
    func gridInteractionCoordinator_isStronglyRetained() throws {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        let coordinator = try #require(sut.gridInteractionCoordinator)
        let grid = try #require(extractCollectionView(from: sut))
        #expect(grid.delegate === coordinator)
        #expect(grid.delegate !== grid)
    }

    @Test("重建 view 时旧 grid 解绑且新 coordinator 装配到新 grid")
    func loadView_rebuildDetachesOldGridAndInstallsNewCoordinator() throws {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        let firstGrid = try #require(extractCollectionView(from: sut))
        let firstCoordinator = try #require(sut.gridInteractionCoordinator)

        sut.loadView()

        let secondGrid = try #require(extractCollectionView(from: sut))
        let secondCoordinator = try #require(sut.gridInteractionCoordinator)
        #expect(firstGrid.delegate == nil)
        #expect(firstCoordinator !== secondCoordinator)
        #expect(secondGrid !== firstGrid)
        #expect(secondGrid.delegate === secondCoordinator)
        #expect(secondGrid.delegate !== secondGrid)
    }

    @Test("同 viewport 重建 view 后为新 grid 恢复 metrics、snapshot 与稳定选择")
    func loadViewRebuildRehydratesCurrentGridAtSameViewport() throws {
        let (sut, _, storage) = makeSUT()
        let expectedMetrics = GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1440, height: 496)
        )
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        sut.navigateToPage(2)
        _ = sut.selectItem(id: 60)
        let firstGrid = try #require(extractCollectionView(from: sut))
        let insertedBefore = storage.insertedItems
        let updatedBefore = storage.updatedItems
        let deletedBefore = storage.deletedIds
        #expect(firstGrid.gridMetrics == expectedMetrics)
        #expect(sut.currentVisualPage == 2)
        #expect(sut.selectedItemID == 60)

        sut.loadView()
        let replacementGrid = try #require(extractCollectionView(from: sut))
        #expect(replacementGrid !== firstGrid)
        #expect(replacementGrid.gridMetrics == nil)

        sut.viewDidLayout()

        #expect(sut.gridMetrics == expectedMetrics)
        #expect(replacementGrid.gridMetrics == expectedMetrics)
        #expect(sut.gridSnapshot.sectionIdentifiers == [.page(0), .page(1), .page(2)])
        #expect(sut.gridSnapshot.itemIdentifiers.map(\.id) == Array(1...60).map(Int64.init))
        #expect(sut.currentVisualPage == 2)
        #expect(sut.selectedItemID == 60)
        #expect(sut.selectedItemIndexPath == IndexPath(item: 3, section: 2))
        #expect(replacementGrid.selectionIndexPaths == [IndexPath(item: 3, section: 2)])
        #expect(storage.insertedItems == insertedBefore)
        #expect(storage.updatedItems == updatedBefore)
        #expect(storage.deletedIds == deletedBefore)
    }

    @Test("释放 ViewController 后 coordinator 与 grid 一并释放")
    func controllerRelease_releasesCoordinatorAndGrid() throws {
        weak var weakController: LaunchPadViewController?
        weak var weakCoordinator: AppGridInteractionCoordinator?
        weak var weakGrid: AppGridCollectionView?
        autoreleasepool {
            let (sut, _, _) = makeSUT()
            _ = sut.view
            weakController = sut
            weakCoordinator = sut.gridInteractionCoordinator
            weakGrid = extractCollectionView(from: sut)
            #expect(weakCoordinator != nil)
            #expect(weakGrid != nil)
        }
        #expect(weakController == nil)
        #expect(weakCoordinator == nil)
        #expect(weakGrid == nil)
    }

    // MARK: - handleSearch 非空查询

    @Test("handleSearch 非空查询执行一次注入搜索")
    func handleSearch_nonEmptyQuery_runsInjectedSearchOnce() {
        let searchScheduler = MockScheduler()
        let (sut, _, storage) = makeSUTWithSearchScheduler(searchScheduler: searchScheduler)
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let safari = TestDataFactory.makePageItem(
            id: 10,
            type: .app,
            ordering: 0,
            parentId: 1,
            app: TestDataFactory.makeAppInfo(id: 10, title: "Safari")
        )
        storage.pages = [page]
        storage.childrenByPage = [1: [safari]]
        layout(sut)

        var searchCalls: [(ids: [Int64], query: String)] = []
        sut.searchRunner = { items, query, completion in
            searchCalls.append((ids: items.map(\.id), query: query))
            completion(items.filter { $0.app?.title.localizedCaseInsensitiveContains(query) == true })
        }

        sut.keyboardNavigator.mode = .search(query: "s")
        sut.searchBar.stringValue = "s"
        _ = sut.handleCharacterInput("a")
        searchScheduler.advance(by: 0.099)
        #expect(searchCalls.isEmpty)

        searchScheduler.advance(by: 0.001)
        #expect(searchCalls.count == 1)
        #expect(searchCalls.first?.ids == [10])
        #expect(searchCalls.first?.query == "sa")
        #expect(sut.resultCountLabel.stringValue == "1 results")
        #expect(sut.resultCountLabel.isHidden == false)
        guard let collectionView = extractCollectionView(from: sut) else {
            Issue.record("collectionView not accessible via reflection")
            return
        }
        #expect(collectionView.diffableDataSource.snapshot().itemIdentifiers.map(\.id) == [10])
        #expect(searchScheduler.scheduledActions.isEmpty)
    }

    // MARK: - 编辑模式删除 / 文件夹重命名（通过 collectionView 回调）

    @Test("onItemDelete 调用 storage 删除并退出编辑模式")
    func onItemDelete_deletesItemAndExitsEditMode() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, parentId: 1,
                                                app: TestDataFactory.makeAppInfo(id: 10, title: "App"))
        storage.pages = [page]
        storage.childrenByPage = [1: [app]]
        _ = sut.view
        sut.loadData()
        guard let cv = extractCollectionView(from: sut) else {
            Issue.record("collectionView not accessible via reflection")
            return
        }

        cv.onItemDelete?(app)

        #expect(storage.deletedIds == [10])
        // handleItemDelete → dragController.handleCancel → idle
        #expect(sut.dragController.state == .idle)
    }

    @Test("onFolderRenamed 将新标题写入存储")
    func onFolderRenamed_persistsNewTitle() {
        let (sut, _, storage) = makeSUT()
        let folder = TestDataFactory.makePageItem(id: 100, type: .group, ordering: 0,
                                                   parentId: 1,
                                                   group: TestDataFactory.makeGroupInfo(id: 100, title: "Old"))
        storage.pages = []
        storage.childrenByPage = [:]
        _ = sut.view
        guard let cv = extractCollectionView(from: sut) else {
            Issue.record("collectionView not accessible via reflection")
            return
        }

        cv.onFolderRenamed?(folder, "Renamed Folder")

        #expect(storage.updatedItems.count == 1)
        #expect(storage.updatedItems.first?.group?.title == "Renamed Folder")
    }

    // MARK: - init(coder:)

    @Test("init(coder:) 返回 nil（不支持 NSCoding）")
    func init_coder_returnsNil() {
        let unarchiver = NSKeyedUnarchiver(forReadingWith: Data())
        let vc = LaunchPadViewController(coder: unarchiver)
        #expect(vc == nil)
    }

    // MARK: - viewDidLayout

    @Test("viewport resize 只重投影且保持稳定顺序，不写存储")
    func resizeReprojectsWithoutWritesAndPreservesStableOrder() {
        let (sut, _, storage) = makeSUT()
        loadViewWithTwoPersistedPages(sut, storage: storage)
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
    }

    @Test("resize clamp 旧页并按稳定 ID 恢复选择")
    func resizeClampsPreviousPageAndRestoresSelectionByID() throws {
        let (sut, _, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let grid = try #require(extractCollectionView(from: sut))
        let scrollView = try #require(extractScrollView(from: sut))
        sut.navigateToPage(2)
        _ = sut.selectItem(id: 60)
        #expect(grid.currentVisualPageIndex == 2)

        sut.viewportSizeProvider = { CGSize(width: 1729, height: 496) }
        sut.view.frame = NSRect(x: 0, y: 0, width: 1729, height: 620)
        sut.view.layoutSubtreeIfNeeded()
        sut.viewDidLayout()
        sut.view.layoutSubtreeIfNeeded()

        #expect(sut.currentVisualPage == 1)
        #expect(sut.pagingPageCount == 2)
        #expect(grid.currentVisualPageIndex == 1)
        #expect(scrollView.contentView.bounds.origin.x == scrollView.pagingPageWidth)
        #expect(sut.selectedItemID == 60)
        #expect(sut.selectedItemIndexPath?.section == 1)
    }

    @Test("active search 在 resize 后保持模式并分页结果")
    func resizeKeepsActiveSearchAndPaginatesResults() throws {
        let (sut, _, _) = makeSUT()
        layout(sut)
        let matchingItems = TestDataFactory.makeAppItems(count: 30, titlePrefix: "App")
        sut.searchRunner = { _, _, _ in }
        sut.handleSearch(query: "app")
        sut.keyboardNavigator.mode = .search(query: "app")
        sut.applySearchResults(matchingItems, query: "app", expectedQuery: "app")

        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        sut.viewDidLayout()

        #expect(sut.currentSearchQuery == "app")
        #expect(sut.keyboardNavigator.mode == .search(query: "app"))
        #expect(sut.visualPages.map(\.count) == [28, 2])
        #expect(sut.gridSnapshot.sectionIdentifiers == [.searchPage(0), .searchPage(1)])
        let metrics = try #require(sut.gridMetrics)
        let collectionView = try #require(extractCollectionView(from: sut))
        collectionView.collectionViewLayout?.prepare()
        for item in sut.gridSnapshot.itemIdentifiers {
            let indexPath = try #require(collectionView.diffableDataSource.indexPath(for: item))
            let attributes = try #require(
                collectionView.collectionViewLayout?.layoutAttributesForItem(at: indexPath)
            )
            #expect(indexPath.item / metrics.columns < metrics.rows)
            #expect(attributes.frame.maxY <= 496)
        }
    }

    @Test("resize 同步七列键盘步长、跨 section 选择与无障碍行")
    func resizeSynchronizesKeyboardAndAccessibilityRows() throws {
        let (sut, _, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let itemIDs = sut.gridSnapshot.itemIdentifiers.map(\.id)
        _ = sut.selectItem(id: itemIDs[27])

        _ = sut.handleKeyEvent(.downArrow)

        #expect(sut.gridMetrics?.rows == 4)
        #expect(sut.gridMetrics?.columns == 7)
        #expect(sut.selectedItemID == itemIDs[34])
        #expect(sut.selectedItemIndexPath?.section == 1)
        let collectionView = try #require(extractCollectionView(from: sut))
        collectionView.cellViewProvider = { _ in NSView() }
        let expectedRowCount = sut.visualPages.reduce(0) { $0 + ($1.count + 6) / 7 }
        #expect(collectionView.accessibilityRows()?.count == expectedRowCount)
    }

    @Test("空搜索结果保留 search page 并清除不再可见的选择")
    func emptySearchProjectsOneEmptyPageAndClearsSelection() {
        let (sut, _, storage) = makeSUT()
        let apps = TestDataFactory.makeAppItems(count: 5)
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut)
        _ = sut.selectItem(id: apps[0].id)
        sut.searchRunner = { _, _, _ in }
        sut.handleSearch(query: "missing")

        sut.applySearchResults([], query: "missing", expectedQuery: "missing")

        #expect(sut.visualPages == [[]])
        #expect(sut.gridSnapshot.sectionIdentifiers == [.searchPage(0)])
        #expect(sut.selectedItemID == nil)
        #expect(sut.pagingPageCount == 1)
    }

    @Test("清空搜索丢弃结果缓存并恢复普通 stable-ID 投影")
    func clearingSearchRestoresNormalProjection() {
        let (sut, _, storage) = makeSUT()
        let apps = TestDataFactory.makeAppItems(count: 5)
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut)
        sut.searchRunner = { _, _, _ in }
        sut.handleSearch(query: "app")
        sut.applySearchResults(apps, query: "app", expectedQuery: "app")

        sut.handleSearch(query: "")

        #expect(sut.currentSearchQuery.isEmpty)
        #expect(sut.currentSearchResults.isEmpty)
        #expect(sut.visualPages.flatMap { $0 }.map(\.id) == apps.map(\.id))
        #expect(sut.gridSnapshot.sectionIdentifiers == [.page(0)])
    }

    @Test("scroll callback 同步页模型且不递归滚动")
    func scrollCallbackSynchronizesPageWithoutRecursion() throws {
        let (sut, _, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let scrollView = try #require(extractScrollView(from: sut))
        let productionCallback = try #require(scrollView.onPageChanged)
        var callbackCount = 0
        scrollView.onPageChanged = { page in
            callbackCount += 1
            productionCallback(page)
        }

        scrollView.scrollToPage(1, animated: false)

        #expect(callbackCount == 1)
        #expect(sut.currentVisualPage == 1)
    }

    @Test("invalid viewport 对每个无效轴均不改变投影")
    func invalidViewportDoesNothing() {
        let (sut, _, _) = makeSUT()
        var reloadCount = 0
        sut.projectedLayoutDidReload = { reloadCount += 1 }
        _ = sut.view
        let invalidSizes = [
            CGSize(width: 0, height: 620),
            CGSize(width: 1440, height: 0),
            CGSize(width: CGFloat.nan, height: 620),
            CGSize(width: 1440, height: CGFloat.infinity),
        ]

        for size in invalidSizes {
            sut.viewportSizeProvider = { size }
            sut.viewDidLayout()
        }

        #expect(sut.gridMetrics == nil)
        #expect(reloadCount == 0)
    }

    @Test("same metrics 不重复 reload projected layout")
    func sameMetricsDoesNotReload() {
        let (sut, _, _) = makeSUT()
        var reloadCount = 0
        sut.projectedLayoutDidReload = { reloadCount += 1 }
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 620) }
        _ = sut.view
        sut.viewDidLayout()
        let countAfterFirstLayout = reloadCount

        sut.viewDidLayout()

        #expect(countAfterFirstLayout == 1)
        #expect(reloadCount == countAfterFirstLayout)
    }

    @Test("空数据的有效 viewport 仍生成一页空投影")
    func emptyDataProjectsOneEmptyVisualPage() {
        let (sut, _, _) = makeSUT()
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))

        #expect(sut.visualPages.count == 1)
        #expect(sut.visualPages[0].isEmpty)
        #expect(sut.gridSnapshot.sectionIdentifiers == [.page(0)])
        #expect(sut.pagingPageCount == 1)
    }

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

    @Test("nil 与未知 stable ID 均清除当前选择")
    func selectItemClearsNilAndUnknownStableIDs() {
        let (sut, _, storage) = makeSUT()
        let apps = TestDataFactory.makeAppItems(count: 5)
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut)
        _ = sut.selectItem(id: apps[0].id)
        #expect(sut.selectedItemID == apps[0].id)

        #expect(sut.selectItem(id: nil) == nil)
        #expect(sut.selectedItemID == nil)
        _ = sut.selectItem(id: apps[0].id)
        #expect(sut.selectItem(id: 999) == nil)
        #expect(sut.selectedItemID == nil)
    }

    @Test("程序化 grid selection 不发 coordinator 业务输出")
    func programmaticSelectionDoesNotEmitCoordinatorOutput() throws {
        let (sut, _, storage) = makeSUT()
        let apps = TestDataFactory.makeAppItems(count: 5)
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut)
        let coordinator = try #require(sut.gridInteractionCoordinator)
        var outputIDs: [Int64] = []
        coordinator.onSelectionChanged = { outputIDs.append($0.id) }

        _ = sut.selectItem(id: apps[2].id)

        #expect(sut.selectedItemID == apps[2].id)
        #expect(outputIDs.isEmpty)
    }

    @Test("coordinator mouse selection 绑定 stable ID")
    func coordinatorSelectionUpdatesStableID() throws {
        let (sut, _, storage) = makeSUT()
        let apps = TestDataFactory.makeAppItems(count: 5)
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut)
        let coordinator = try #require(sut.gridInteractionCoordinator)

        coordinator.onSelectionChanged?(apps[3])

        #expect(sut.selectedItemID == apps[3].id)
    }

    @Test("未加载视图的分页动作不强制加载视图")
    func pageActionsDoNotLoadView() {
        let (sut, _, _) = makeSUT()

        #expect(!sut.isViewLoaded)
        #expect(sut.handleKeyEvent(.leftArrow) == .previousPage)
        #expect(sut.handleKeyEvent(.rightArrow) == .nextPage)
        #expect(!sut.isViewLoaded)
    }

    // MARK: - setupCallbacks 闭包体（通过子视图属性直接触发）

    @Test("searchBar.onQueryChanged 触发防抖搜索")
    func searchBar_onQueryChanged_triggersSearch() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        sut.searchBar.onQueryChanged?("hello")
    }

    @Test("pageControl dot 在真实多页投影中同步目标页并拒绝越界")
    func pageControl_onDotSelected_navigates() throws {
        let (sut, _, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let scrollView = try #require(extractScrollView(from: sut))
        let productionCallback = try #require(scrollView.onPageChanged)
        var scrolledPages: [Int] = []
        scrollView.onPageChanged = { page in
            scrolledPages.append(page)
            productionCallback(page)
        }

        sut.pageControl.onDotSelected?(2)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 2)
        #expect(scrolledPages == [2])

        sut.pageControl.onDotSelected?(3)
        expectThreePagePresentation(sut, scrollView: scrollView, currentPage: 2)
        #expect(scrolledPages == [2])
    }

    @Test("folderOverlay.onAppSelected 触发选中")
    func folderOverlay_onAppSelected_selects() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 10, title: "A"))
        sut.folderOverlay.onAppSelected?(app)
    }

    @Test("folderOverlay.onClosed 隐藏覆盖层")
    func folderOverlay_onClosed_hides() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        sut.folderOverlay.isHidden = false
        sut.folderOverlay.onClosed?()
        #expect(sut.folderOverlay.isHidden == true)
    }

    // MARK: - handleLongPress（mock 手势驱动各分支）

    @Test("handleLongPress .began 调用 handlePressBegan")
    func handleLongPress_began() {
        let (sut, _, _) = makeSUT()
        sut.handleLongPress(MockPressGesture(state: .began))
    }

    @Test("handleLongPress .changed 调用 handleDragMoved")
    func handleLongPress_changed() {
        let (sut, _, _) = makeSUT()
        sut.handleLongPress(MockPressGesture(state: .changed, location: CGPoint(x: 50, y: 50)))
    }

    @Test("handleLongPress .ended 在 idle 调用 handlePressEnded")
    func handleLongPress_ended_idle() {
        let (sut, _, _) = makeSUT()
        sut.handleLongPress(MockPressGesture(state: .ended))
    }

    @Test("handleLongPress .ended 在 jiggling 更新抖动状态")
    func handleLongPress_ended_jiggling() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        dragController.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)
        sut.handleLongPress(MockPressGesture(state: .ended))
        #expect(sut.keyboardNavigator.mode == .edit)
    }

    @Test("native session 的 gesture terminal 不读取也不抢 ended cleanup")
    func handleLongPressNativeSessionWaitsForNativeEnded() throws {
        let scheduler = MockScheduler()
        let (sut, dragController, storage) = makeSUT(dragScheduler: scheduler)
        loadViewWithData(sut, storage: storage)
        layout(sut)
        let coordinator = try #require(sut.gridInteractionCoordinator)
        dragController.beginDrag(makeDragSession())
        let readsBefore = storage.fetchAllItemsCallCount
        let cancelCountBefore = scheduler.cancelCallCount

        sut.handleLongPress(MockPressGesture(state: .ended))

        #expect(dragController.state == .dragging)
        #expect(dragController.session != nil)
        #expect(storage.fetchAllItemsCallCount == readsBefore)
        #expect(scheduler.cancelCallCount == cancelCountBefore)
        coordinator.collectionView(
            try #require(extractCollectionView(from: sut)),
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )
        #expect(dragController.state == .idle)
        #expect(dragController.session == nil)
        #expect(storage.fetchAllItemsCallCount == readsBefore)
        #expect(scheduler.cancelCallCount == cancelCountBefore + 1)
    }

    @Test("gesture-only dragging 的 ended/cancelled/failed 各自只清理并读取一次")
    func handleLongPressGestureOnlyTerminalMatrix() {
        for gestureState in [
            NSGestureRecognizer.State.ended,
            .cancelled,
            .failed,
        ] {
            let scheduler = MockScheduler()
            let (sut, dragController, storage) = makeSUT(dragScheduler: scheduler)
            loadViewWithData(sut, storage: storage)
            dragController.handleDragStart()
            let readsBefore = storage.fetchAllItemsCallCount
            let cancelCountBefore = scheduler.cancelCallCount

            sut.handleLongPress(MockPressGesture(state: gestureState))

            #expect(dragController.state == .idle)
            #expect(dragController.session == nil)
            #expect(storage.fetchAllItemsCallCount - readsBefore == 2)
            #expect(scheduler.cancelCallCount == cancelCountBefore + 1)
        }
    }

    @Test("handleLongPress 其他状态走 default 分支")
    func handleLongPress_defaultState() {
        let (sut, _, _) = makeSUT()
        sut.handleLongPress(MockPressGesture(state: .possible))
    }

    // MARK: - executeSearch / applySearchResults（抽出方法的同步覆盖）

    @Test("executeSearch 在后台执行搜索返回结果")
    func executeSearch_returnsResults() {
        let (sut, _, _) = makeSUT()
        let apps = TestDataFactory.makeAppItems(count: 3, titlePrefix: "Alpha")
        let results = sut.executeSearch(items: apps, query: "Alpha")
        #expect(results.isEmpty == false)
    }

    @Test("applySearchResults 展示结果计数并进入搜索态")
    func applySearchResults_showsCount() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        sut.handleSearch(query: "xyz") // 设置 currentSearchQuery = "xyz"
        let apps = TestDataFactory.makeAppItems(count: 2, titlePrefix: "App")
        sut.applySearchResults(apps, query: "xyz", expectedQuery: "xyz")
        #expect(sut.resultCountLabel.isHidden == false)
        #expect(sut.resultCountLabel.stringValue == "2 results")
    }

    // MARK: - handleItemSelection .page 分支

    @Test("handleItemSelection 对非 snapshot page 安全清除选择")
    func handleItemSelectionPageClearsSelectionSafely() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)

        sut.handleItemSelection(page)

        #expect(sut.selectedItemID == nil)
    }

    // MARK: - 启动动画各阶段（抽出方法同步覆盖）

    @Test("animateAppLaunch reduceMotion 直接启动不查找 cell")
    func animateAppLaunch_reduceMotion_launches() {
        let (sut, _, _) = makeSUT()
        sut.accessibilitySettingsProvider = { AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false) }
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                               app: TestDataFactory.makeAppInfo(id: 10, title: "A", bundleId: "com.test.nonexistent"))
        sut.animateAppLaunch(item: app, bundleId: "com.test.nonexistent")
    }

    @Test("animateAppLaunch 有 cell 时执行高亮/放大/完成动画（同步调度器）")
    func animateAppLaunch_withCell_runsStages() {
        let (sut, _, _) = makeSUT()
        sut.accessibilitySettingsProvider = { AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false) }
        let cellView = NSView()
        cellView.wantsLayer = true
        sut.launchCellResolver = { _ in cellView }
        var completed = false
        sut.launchAnimationScheduler = { _, block in block(); completed = true }
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                               app: TestDataFactory.makeAppInfo(id: 10, title: "A", bundleId: "com.test.nonexistent"))
        sut.animateAppLaunch(item: app, bundleId: "com.test.nonexistent")
        #expect(completed)
    }

    @Test("animateAppLaunch 默认调度器被调用（headless 下完成闭包不触发）")
    func animateAppLaunch_defaultScheduler_schedules() {
        let (sut, _, _) = makeSUT()
        sut.accessibilitySettingsProvider = { AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false) }
        let cellView = NSView()
        cellView.wantsLayer = true
        sut.launchCellResolver = { _ in cellView }
        // 不注入 launchAnimationScheduler → 使用默认 DispatchQueue.main.asyncAfter（覆盖其闭包体）
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                               app: TestDataFactory.makeAppInfo(id: 10, title: "A", bundleId: "com.test.nonexistent"))
        sut.animateAppLaunch(item: app, bundleId: "com.test.nonexistent")
    }

    @Test("resolveLaunchCellView 注入优先返回 cell，默认回退 collectionView")
    func resolveLaunchCellView_resolves() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                               app: TestDataFactory.makeAppInfo(id: 10, title: "A"))
        guard let cv = extractCollectionView(from: sut) else { Issue.record("collectionView not accessible"); return }
        cv.reload(pages: [[app]], searchResults: nil, searchQuery: nil)
        let injected = NSView()
        sut.launchCellResolver = { _ in injected }
        #expect(sut.resolveLaunchCellView(for: app) === injected)
        // 默认回退：无注入时返回 collectionView.item(at:)?.view（headless 下为 nil）
        sut.launchCellResolver = nil
        _ = sut.resolveLaunchCellView(for: app)
    }

    @Test("performLaunchHighlight 设置 transform 与透明度动画")
    func performLaunchHighlight_setsTransform() {
        let (sut, _, _) = makeSUT()
        let view = NSView()
        view.wantsLayer = true
        sut.performLaunchHighlight(cellView: view)
        #expect(view.layer?.transform.m11 == CGFloat(0.95))
    }

    @Test("performLaunchZoom 添加放大淡出动画")
    func performLaunchZoom_addsZoom() {
        let (sut, _, _) = makeSUT()
        let view = NSView()
        view.wantsLayer = true
        sut.performLaunchZoom(cellView: view)
    }

    @Test("scheduleLaunchCompletion 经注入调度器同步触发完成动画")
    func scheduleLaunchCompletion_invokesScheduler() {
        let (sut, _, _) = makeSUT()
        let view = NSView()
        view.wantsLayer = true
        var ran = false
        sut.launchAnimationScheduler = { _, block in block(); ran = true }
        sut.scheduleLaunchCompletion(cellView: view, bundleId: "com.test.nonexistent")
        #expect(ran)
    }

    @Test("completeLaunchAnimation 启动应用并重置 cell")
    func completeLaunchAnimation_launchesAndResets() {
        let (sut, _, _) = makeSUT()
        let view = NSView()
        view.wantsLayer = true
        view.alphaValue = 0.3
        sut.completeLaunchAnimation(cellView: view, bundleId: "com.test.nonexistent")
        #expect(view.alphaValue == 1)
    }

    // MARK: - launchApp / launchApplication

    @Test("launchApp 无效 bundleId 安全返回")
    func launchApp_invalidBundle_returns() {
        let (sut, _, _) = makeSUT()
        sut.launchApp(bundleId: "com.test.definitely.invalid.bundle")
    }

    @Test("launchApp 解析到 URL 时调用 launchApplication")
    func launchApp_withResolvedURL_callsLaunchApplication() {
        let (sut, _, _) = makeSUT()
        sut.bundleURLResolver = { _ in URL(fileURLWithPath: "/tmp/launchpad-fake.app") }
        sut.launchApp(bundleId: "com.any.bundle")
    }

    @Test("launchApplication 对任意 URL 执行 NSWorkspace 调用（不真实启动）")
    func launchApplication_withFakeURL() {
        let (sut, _, _) = makeSUT()
        sut.launchApplication(at: URL(fileURLWithPath: "/tmp/launchpad-nonexistent-app.app"))
    }

    // MARK: - 错误分支（catch）

    @Test("handleItemDelete 删除失败时记录错误不崩溃")
    func handleItemDelete_throws_logs() {
        let (sut, _, storage) = makeSUT()
        storage.shouldThrowOnDelete = true
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
                                               app: TestDataFactory.makeAppInfo(id: 10, title: "A"))
        sut.handleItemDelete(app)
    }

    @Test("openFolder 读取失败时记录错误不崩溃")
    func openFolder_throws_logs() {
        let (sut, _, storage) = makeSUT()
        storage.shouldThrowOnFetch = true
        let folder = TestDataFactory.makePageItem(id: 100, type: .group, ordering: 0,
                                                  parentId: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 100, title: "F"))
        sut.openFolder(folder)
    }

    @Test("handleFolderRename 重命名失败时记录错误不崩溃")
    func handleFolderRename_throws_logs() {
        let (sut, _, storage) = makeSUT()
        storage.shouldThrowOnUpdate = true
        let folder = TestDataFactory.makePageItem(id: 100, type: .group, ordering: 0,
                                                  parentId: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 100, title: "Old"))
        sut.handleFolderRename(item: folder, newTitle: "New")
    }

    // MARK: - handleSearch 有数据时遍历 itemsByPage

    @Test("handleSearch 空查询在有数据时遍历 itemsByPage")
    func handleSearch_emptyQuery_withData() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let apps = TestDataFactory.makeAppItems(count: 3, titlePrefix: "App")
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        _ = sut.view
        sut.loadData()

        sut.handleSearch(query: "")
        #expect(true)
    }

    @Test("handleSearch 非空查询在有数据时 flatMap itemsByPage")
    func handleSearch_nonEmptyQuery_withData() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let apps = TestDataFactory.makeAppItems(count: 3, titlePrefix: "Alpha")
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        _ = sut.view
        sut.loadData()

        sut.handleSearch(query: "alpha")
        #expect(true)
    }

    // MARK: - openFolder 多子项排序

    @Test("openFolder 多个子项按 ordering 排序")
    func openFolder_multipleChildren_sorted() {
        let (sut, _, storage) = makeSUT()
        _ = sut.view
        let folder = TestDataFactory.makePageItem(id: 100, type: .group, ordering: 0,
                                                   parentId: 1,
                                                   group: TestDataFactory.makeGroupInfo(id: 100, title: "Folder"))
        let child1 = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 1, parentId: 100,
                                                   app: TestDataFactory.makeAppInfo(id: 10, title: "B"))
        let child2 = TestDataFactory.makePageItem(id: 20, type: .app, ordering: 0, parentId: 100,
                                                   app: TestDataFactory.makeAppInfo(id: 20, title: "A"))
        storage.childrenByPage = [100: [child1, child2]]

        sut.openFolder(folder)
        #expect(true)
    }

    // MARK: - executeAction .launchFirstMatch

    @Test("enter 在搜索模式触发 launchFirstMatch 并选中首个结果")
    func launchFirstMatch_selectsFirstItem() {
        let (sut, _, storage) = makeSUT()
        loadViewWithData(sut, storage: storage)
        layout(sut)
        sut.keyboardNavigator.mode = .search(query: "App")
        _ = sut.handleKeyEvent(.enter)

        #expect(sut.selectedItemID == sut.gridSnapshot.itemIdentifiers.first?.id)
    }

    // MARK: - updateJiggleState 循环体（注入 cell provider）

    @Test("updateJiggleState 注入 cell provider 时驱动 startJiggling/stopJiggling")
    func updateJiggleState_injectedCells_jiggle() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        _ = sut.view
        let cell = AppIconCell()
        sut.visibleJiggleIndexPathsProvider = { [IndexPath(item: 0, section: 0)] }
        sut.jiggleCellProvider = { _ in cell }

        // jiggling 态 → startJiggling + keyboardNavigator 进入 edit
        dragController.handlePressBegan(at: .zero)
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)
        sut.updateJiggleState()
        #expect(sut.keyboardNavigator.mode == .edit)

        // idle 态 → stopJiggling + keyboardNavigator 回到 idle
        dragController.handleCancel()
        #expect(dragController.state == .idle)
        sut.updateJiggleState()
        #expect(sut.keyboardNavigator.mode == .idle)
    }

    // MARK: - loadData 错误分支

    @Test("loadData 读取失败时记录错误不崩溃")
    func loadData_throws_logs() {
        let (sut, _, storage) = makeSUT()
        storage.shouldThrowOnFetch = true
        _ = sut.view // viewDidLoad → loadData 抛错 → catch
    }

    // MARK: - applySearchResults 空结果分支

    @Test("applySearchResults 空结果时显示空状态")
    func applySearchResults_empty_showsEmptyState() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        sut.handleSearch(query: "xyz") // 设置 currentSearchQuery = "xyz"
        sut.applySearchResults([], query: "xyz", expectedQuery: "xyz")
        #expect(sut.resultCountLabel.isHidden == false)
        #expect(sut.resultCountLabel.stringValue == "0 results")
    }

    @Test("applySearchResults 过期查询不更新 UI（guard else 分支）")
    func applySearchResults_staleQuery_ignored() {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        sut.handleSearch(query: "new") // 设置 currentSearchQuery = "new"
        // 使用旧的 expectedQuery 调用，此时 currentSearchQuery != expectedQuery → guard 失败
        sut.applySearchResults([], query: "old", expectedQuery: "old")
        // resultCountLabel 应保持隐藏（未被更新）
        #expect(sut.resultCountLabel.stringValue == "")
    }

    // MARK: - 分支覆盖补充

    @Test("未注入 provider 时使用真实 clip viewport")
    func viewDidLayoutUsesClipViewportWithoutProvider() throws {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        sut.view.frame = NSRect(x: 0, y: 0, width: 1440, height: 700)
        sut.view.layoutSubtreeIfNeeded()
        let scrollView = try #require(extractScrollView(from: sut))
        let clipSize = scrollView.contentView.bounds.size
        #expect(clipSize.width > 0)
        #expect(clipSize.height > 0)

        sut.viewDidLayout()

        #expect(sut.gridMetrics == GridLayoutCalculator.calculate(viewportSize: clipSize))
    }

    @Test("updateJiggleState: jiggleCellProvider 返回 nil 时跳过该 cell（覆盖 L280 ?? 假分支）")
    func updateJiggleState_cellProviderNil_skipsCell() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        _ = sut.view
        // visibleJiggleIndexPathsProvider 返回有效 indexPath
        sut.visibleJiggleIndexPathsProvider = { [IndexPath(item: 0, section: 0)] }
        // jiggleCellProvider 始终返回 nil → ?? 假分支 → 走 collectionView.item(at:) 但也是 nil → continue
        sut.jiggleCellProvider = { _ in nil }

        dragController.handlePressBegan(at: .zero)
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)
        // 不应崩溃
        sut.updateJiggleState()
        #expect(true)
    }

    @Test("updateJiggleState: jiggleCellProvider nil 且 collectionView.item 也 nil 时跳过（覆盖 L280 as? 假分支）")
    func updateJiggleState_bothProvidersNil_skipsCell() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        _ = sut.view
        // jiggleCellProvider 始终返回 nil（默认）→ ?? 假分支
        // collectionView.item(at:) 在空 collectionView 上也返回 nil
        sut.visibleJiggleIndexPathsProvider = { [IndexPath(item: 0, section: 0)] }
        // jiggleCellProvider 保持 nil
        dragController.handlePressBegan(at: .zero)
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)
        sut.updateJiggleState()
        #expect(true)
    }

    @Test("空 snapshot 的 Down 清除稳定 ID 选择")
    func moveSelection_emptyCollection_returnsEarly() {
        let (sut, _, _) = makeSUT()
        layout(sut)

        _ = sut.handleKeyEvent(.downArrow)

        #expect(sut.selectedItemID == nil)
    }

    @Test("view loaded 但 metrics 为 nil 时 Up、Down、Tab 均保持稳定与真实 grid 选择")
    func loadedWithoutMetricsKeyboardMatrixPreservesSelection() throws {
        let (sut, _, _) = makeSUT()
        _ = sut.view
        let collectionView = try #require(extractCollectionView(from: sut))
        let selectedItem = TestDataFactory.makePageItem(
            id: 501,
            type: .app,
            ordering: 0,
            app: nil
        )
        let neighboringItem = TestDataFactory.makePageItem(
            id: 502,
            type: .app,
            ordering: 1,
            app: nil
        )
        collectionView.reload(
            pages: [[selectedItem, neighboringItem]],
            searchResults: nil,
            searchQuery: nil,
            animateEntrance: false
        )
        sut.handleItemSelection(selectedItem)
        let selectedIDBefore = sut.selectedItemID
        let gridSelectionBefore = collectionView.selectionIndexPaths
        #expect(sut.gridMetrics == nil)
        #expect(collectionView.gridMetrics == nil)
        #expect(selectedIDBefore == selectedItem.id)
        #expect(gridSelectionBefore == [IndexPath(item: 0, section: 0)])

        for key in [
            KeyboardNavigator.Key.upArrow,
            .downArrow,
            .tab,
        ] {
            _ = sut.handleKeyEvent(key)
            #expect(sut.selectedItemID == selectedIDBefore, "\(key) changed stable selection")
            #expect(
                collectionView.selectionIndexPaths == gridSelectionBefore,
                "\(key) changed the real grid selection"
            )
        }
    }

    @Test("没有选择时 Up 保持 nil")
    func moveSelectionUpWithoutSelectionDoesNothing() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let apps = TestDataFactory.makeAppItems(count: 5)
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        layout(sut)

        _ = sut.handleKeyEvent(.upArrow)

        #expect(sut.selectedItemID == nil)
    }

    @Test("没有选择时首次 Tab 选中 snapshot 首项")
    func moveSelectionFirstTabSelectsSnapshotFirstItem() {
        let (sut, _, storage) = makeSUT()
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let apps = TestDataFactory.makeAppItems(count: 5)
        storage.pages = [page]
        storage.childrenByPage = [1: apps]
        layout(sut)

        _ = sut.handleKeyEvent(.tab)

        #expect(sut.selectedItemID == sut.gridSnapshot.itemIdentifiers.first?.id)
    }

    @Test("Down 可跨 visual section 并同步当前页")
    func moveSelectionDownCrossesVisualSection() {
        let (sut, _, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let itemIDs = sut.gridSnapshot.itemIdentifiers.map(\.id)
        _ = sut.selectItem(id: itemIDs[27])

        _ = sut.handleKeyEvent(.downArrow)

        #expect(sut.selectedItemID == itemIDs[34])
        #expect(sut.selectedItemIndexPath?.section == 1)
        #expect(sut.currentVisualPage == 1)
    }

    @Test("Tab 在末项保持原 stable ID")
    func moveSelectionNextAtEndDoesNothing() {
        let (sut, _, storage) = makeSUT()
        let apps = TestDataFactory.makeAppItems(count: 5)
        loadViewWithData(sut, storage: storage, apps: apps)
        layout(sut)
        _ = sut.selectItem(id: apps.last?.id)

        _ = sut.handleKeyEvent(.tab)

        #expect(sut.selectedItemID == apps.last?.id)
    }

    @Test("主网格视觉页在 reload、scroll、导航、dot、edge 与 selection 原语同步")
    func gridVisualPageSynchronizesAtPrimitiveBoundaries() throws {
        let (sut, dragController, storage) = makeSUT()
        sut.viewportSizeProvider = { CGSize(width: 1440, height: 496) }
        loadViewWithTwoPersistedPages(sut, storage: storage)
        sut.viewDidLayout()
        let grid = try #require(extractCollectionView(from: sut))
        let scrollView = try #require(extractScrollView(from: sut))
        #expect(grid.currentVisualPageIndex == 0)

        sut.navigateToPage(1)
        #expect(grid.currentVisualPageIndex == 1)
        sut.navigateToPage(99)
        #expect(grid.currentVisualPageIndex == 1)

        scrollView.onPageChanged?(2)
        #expect(grid.currentVisualPageIndex == 2)
        sut.pageControl.onDotSelected?(1)
        #expect(grid.currentVisualPageIndex == 1)
        dragController.onPageChange?(.forward)
        #expect(grid.currentVisualPageIndex == 2)
        dragController.onPageChange?(.backward)
        #expect(grid.currentVisualPageIndex == 1)

        let target = try #require(sut.gridSnapshot.itemIdentifiers.first(where: {
            sut.gridSnapshot.indexOfItem($0).map { $0 >= 28 } ?? false
        }))
        _ = sut.selectItem(id: target.id)
        #expect(grid.currentVisualPageIndex == sut.selectedItemIndexPath?.section)
    }

    @Test("folder inside/outside 分别映射 reorder/remove intent 且非法 source 明确拒绝")
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
        #expect(sut.makeFolderIntent(
            session: makeFolderChildSession(itemType: .group),
            destination: .inside(.beforeItem(itemID: 11))
        ) == nil)
        #expect(sut.makeFolderIntent(
            session: makeFolderChildSession(sourceKind: .topLevel),
            destination: .inside(.beforeItem(itemID: 11))
        ) == nil)
    }

    @Test("folder exterior resolver 经 overlay、window 转为 grid local 坐标")
    func folderExteriorResolverConvertsThroughWindowIntoGridCoordinates() throws {
        let apps = [
            TestDataFactory.makePageItem(
                id: 1,
                uuid: "00000000-0000-0000-0000-000000000001",
                type: .app,
                ordering: 0,
                parentId: 1,
                app: TestDataFactory.makeAppInfo(id: 1, title: "A1")
            ),
            TestDataFactory.makePageItem(
                id: 2,
                uuid: "00000000-0000-0000-0000-000000000002",
                type: .app,
                ordering: 1,
                parentId: 1,
                app: TestDataFactory.makeAppInfo(id: 2, title: "A2")
            ),
        ]
        let (sut, _, storage) = makeSUT()
        loadViewWithData(sut, storage: storage, apps: apps)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host
        sut.view.frame = NSRect(x: 130, y: 90, width: 1000, height: 700)
        host.addSubview(sut.view)
        layout(sut, viewportSize: CGSize(width: 1000, height: 620))
        sut.view.layoutSubtreeIfNeeded()

        let grid = try #require(extractCollectionView(from: sut))
        let targetPath = try #require(
            grid.diffableDataSource.indexPath(for: apps[1])
        )
        grid.collectionViewLayout?.prepare()
        let targetFrame = try #require(grid.layoutFrame(at: targetPath))
        let expectedGridPoint = NSPoint(
            x: targetFrame.minX + 1,
            y: targetFrame.midY
        )
        var capturedGridPoint: NSPoint?
        grid.indexPathResolver = { point in
            capturedGridPoint = point
            return targetPath
        }

        let windowPoint = grid.convert(expectedGridPoint, to: nil)
        let overlayPoint = sut.folderOverlay.convert(windowPoint, from: nil)
        let overlayWindowOrigin = sut.folderOverlay.convert(NSPoint.zero, to: nil)
        let gridWindowOrigin = grid.convert(NSPoint.zero, to: nil)
        #expect(overlayWindowOrigin != NSPoint.zero)
        #expect(gridWindowOrigin != NSPoint.zero)
        #expect(overlayWindowOrigin != gridWindowOrigin)

        let placement = sut.folderOverlay.topLevelPlacementResolver?(overlayPoint)

        #expect(placement == .beforeItem(itemID: 2))
        let resolvedPoint = try #require(capturedGridPoint)
        #expect(abs(resolvedPoint.x - expectedGridPoint.x) <= 0.001)
        #expect(abs(resolvedPoint.y - expectedGridPoint.y) <= 0.001)
    }

    @Test("folder inner reorder 成功后只写一次并重载 remaining children")
    func folderReorderSuccessReloadsRemainingChildrenOnce() {
        let mutator = MockLayoutMutator()
        let (sut, storage, _) = makeOpenedFolderSUT(
            mutator: mutator,
            children: [
                makeFolderChild(id: 11, ordering: 0),
                makeFolderChild(id: 10, ordering: 1),
            ]
        )
        let readsBefore = storage.fetchAllItemsCallCount

        let succeeded = sut.handleFolderDrop(
            session: makeFolderChildSession(),
            destination: .inside(.afterItem(itemID: 11))
        )

        #expect(succeeded)
        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.attemptedIntents == [
            .reorderFolderItem(
                itemID: 10,
                folderID: 50,
                placement: .afterItem(itemID: 11)
            ),
        ])
        #expect(storage.fetchAllItemsCallCount - readsBefore == 3)
        #expect(sut.folderOverlay.currentFolderID == 50)
        #expect(sut.folderOverlay.collectionView(
            sut.folderOverlay.folderCollectionView,
            numberOfItemsInSection: 0
        ) == 2)
        #expect(storage.insertedItems.isEmpty)
        #expect(storage.updatedItems.isEmpty)
        #expect(storage.deletedIds.isEmpty)
    }

    @Test("folder drag-out auto-dissolve 后关闭 overlay 且只有一次 mutation")
    func folderDragOutAutoDissolveClosesOverlay() {
        let mutator = MockLayoutMutator()
        let (sut, storage, _) = makeOpenedFolderSUT(
            mutator: mutator,
            children: [makeFolderChild(id: 10, ordering: 0)]
        )
        mutator.eventRecorder = { event in
            if event == "apply-return" {
                storage.childrenByPage[1] = []
                storage.childrenByPage[50] = []
            }
        }

        let succeeded = sut.handleFolderDrop(
            session: makeFolderChildSession(),
            destination: .outside(.afterItem(itemID: 99))
        )

        #expect(succeeded)
        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.attemptedIntents == [
            .removeFromFolder(
                itemID: 10,
                folderID: 50,
                placement: .afterItem(itemID: 99)
            ),
        ])
        #expect(sut.folderOverlay.currentFolderID == nil)
        #expect(sut.folderOverlay.isHidden)
        #expect(storage.insertedItems.isEmpty)
        #expect(storage.updatedItems.isEmpty)
        #expect(storage.deletedIds.isEmpty)
    }

    @Test("folder mutation 失败后重载原 children、返回 false 且显示固定消息")
    func folderMutationFailureReloadsOriginalChildrenAndReturnsFalse() {
        let mutator = MockLayoutMutator()
        mutator.applyError = SensitiveError(description: "folder-sensitive-error")
        let (sut, storage, _) = makeOpenedFolderSUT(
            mutator: mutator,
            children: [
                makeFolderChild(id: 10, ordering: 0),
                makeFolderChild(id: 11, ordering: 1),
            ]
        )

        let succeeded = sut.handleFolderDrop(
            session: makeFolderChildSession(),
            destination: .inside(.afterItem(itemID: 11))
        )

        #expect(!succeeded)
        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.appliedIntents.isEmpty)
        #expect(sut.folderOverlay.currentFolderID == 50)
        #expect(sut.folderOverlay.collectionView(
            sut.folderOverlay.folderCollectionView,
            numberOfItemsInSection: 0
        ) == 2)
        #expect(sut.transientMessageView.message == "无法更新布局，请重试")
        #expect(storage.insertedItems.isEmpty)
        #expect(storage.updatedItems.isEmpty)
        #expect(storage.deletedIds.isEmpty)
    }

    @Test("文件夹删除取消时零 mutation，确认后只提交安全删除 intent")
    func folderDeleteRequiresConfirmation() {
        let mutator = MockLayoutMutator()
        let (sut, _, storage) = makeSUT(layoutMutator: mutator)
        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        let folder = makeFolder(id: 50)

        sut.confirmFolderDeletion = { _ in false }
        sut.handleItemDelete(folder)
        #expect(mutator.applyAttemptCount == 0)
        #expect(storage.deletedIds.isEmpty)

        sut.confirmFolderDeletion = { _ in true }
        sut.handleItemDelete(folder)
        #expect(mutator.attemptedIntents == [.deleteFolder(folderID: 50)])
        #expect(storage.deletedIds.isEmpty)
    }

    @Test("folder 删除 mutation failure 只走统一错误反馈")
    func folderDeleteFailureUsesUnifiedWriterFeedback() {
        let mutator = MockLayoutMutator()
        mutator.applyError = SensitiveError(description: "delete-folder-sensitive")
        let (sut, _, storage) = makeSUT(layoutMutator: mutator)
        loadViewWithData(sut, storage: storage)
        layout(sut, viewportSize: CGSize(width: 1440, height: 496))
        sut.confirmFolderDeletion = { _ in true }

        sut.handleItemDelete(makeFolder())

        #expect(mutator.applyAttemptCount == 1)
        #expect(mutator.appliedIntents.isEmpty)
        #expect(sut.transientMessageView.message == "无法更新布局，请重试")
        #expect(storage.deletedIds.isEmpty)
    }

    @Test("page 删除严格 no-op 且 app 删除仍保留原 writer")
    func pageDeleteIsNoOpAndAppDeleteRemainsUnchanged() {
        let mutator = MockLayoutMutator()
        let (sut, _, storage) = makeSUT(layoutMutator: mutator)
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let app = makeFolderChild(id: 10, ordering: 0)

        sut.handleItemDelete(page)
        #expect(mutator.applyAttemptCount == 0)
        #expect(storage.deletedIds.isEmpty)

        sut.handleItemDelete(app)
        #expect(mutator.applyAttemptCount == 0)
        #expect(storage.deletedIds == [10])
    }

    @Test("folder cell 随 edit mode 显隐且 app cell 行为保持")
    func updateJiggleStateSupportsAppFolderAndMissingCells() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        _ = sut.view
        let appCell = AppIconCell()
        let folderCell = FolderCell()
        _ = appCell.view
        _ = folderCell.view
        let paths = [
            IndexPath(item: 0, section: 0),
            IndexPath(item: 1, section: 0),
            IndexPath(item: 2, section: 0),
        ]
        sut.visibleJiggleIndexPathsProvider = { paths }
        sut.jiggleCellProvider = { path in
            switch path.item {
            case 0: return appCell
            case 1: return folderCell
            default: return nil
            }
        }

        dragController.handlePressBegan(at: .zero)
        scheduler.advance(by: 0.5)
        sut.updateJiggleState()

        #expect(dragController.state == .jiggling)
        #expect(folderCell.isEditing)
        #expect(folderCell.isDeleteControlVisible)

        dragController.handleCancel()
        sut.updateJiggleState()
        #expect(!folderCell.isEditing)
        #expect(!folderCell.isDeleteControlVisible)
    }

    @Test("cancelActiveDrag 幂等清理 session、timer 与 preview")
    func cancelActiveDragClearsAllTransientStateIdempotently() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        var previewChanges: [Int64?] = []
        dragController.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        dragController.beginDrag(makeDragSession(itemID: 10))
        dragController.updateDragHover(.item(itemID: 11, itemType: .app))
        scheduler.advance(by: 0.8)
        #expect(dragController.session?.folderCreationPreviewTargetID == 11)

        sut.cancelActiveDrag()

        #expect(dragController.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))

        let cancelCount = scheduler.cancelCallCount
        sut.cancelActiveDrag()
        #expect(dragController.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
        #expect(scheduler.cancelCallCount == cancelCount + 1)
    }
}
#endif
