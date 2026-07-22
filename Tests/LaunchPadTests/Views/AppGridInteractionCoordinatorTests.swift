import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor
private final class InteractionHost: AppGridInteractionHosting {
    let collectionViewForDelegateInstallation: NSCollectionView
    var interactionVisibleRect = NSRect(x: 0, y: 0, width: 800, height: 620)
    var visualPageCount = 1
    var currentVisualPageIndex = 0
    var sections: [Int: Section] = [0: .page(0)]
    var itemsByPath: [IndexPath: PageItem] = [:]
    var itemsByID: [Int64: PageItem] = [:]
    var visualIndices: [Int64: Int] = [:]
    var pathsByID: [Int64: IndexPath] = [:]
    var resolvedPath: IndexPath?
    private(set) var resolvedPoints: [NSPoint] = []
    var frames: [IndexPath: NSRect] = [:]
    var emptyPlacementResult: ItemPlacement?
    var renderedImages: [IndexPath: NSImage] = [:]
    private(set) var previewCalls: [Int64?] = []

    init(collectionView: NSCollectionView = NSCollectionView()) {
        collectionViewForDelegateInstallation = collectionView
    }

    func section(at index: Int) -> Section? { sections[index] }
    func pageItem(at indexPath: IndexPath) -> PageItem? { itemsByPath[indexPath] }
    func pageItem(id: Int64) -> PageItem? { itemsByID[id] }
    func visualIndex(of item: PageItem) -> Int? { visualIndices[item.id] }
    func indexPath(forItemID itemID: Int64) -> IndexPath? { pathsByID[itemID] }
    func resolvedIndexPath(at point: NSPoint) -> IndexPath? {
        resolvedPoints.append(point)
        return resolvedPath
    }
    func layoutFrame(at indexPath: IndexPath) -> NSRect? { frames[indexPath] }
    func emptyPlacement(inVisualPage pageIndex: Int) -> ItemPlacement? {
        emptyPlacementResult
    }
    func dragImage(at indexPath: IndexPath) -> NSImage? { renderedImages[indexPath] }
    func setFolderCreationPreview(targetItemID: Int64?) { previewCalls.append(targetItemID) }

    func install(_ item: PageItem, at path: IndexPath, frame: NSRect? = nil) {
        itemsByPath[path] = item
        itemsByID[item.id] = item
        visualIndices[item.id] = path.section
        pathsByID[item.id] = path
        if let frame { frames[path] = frame }
    }
}

@MainActor
final class MockDraggingInfo: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingLocation: NSPoint
    var draggingSequenceNumber = 0
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggedImageLocation: NSPoint = .zero
    var draggingDestinationWindow: NSWindow?
    var draggingSource: Any?
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var draggedImage: NSImage?
    var draggingFormation: NSDraggingFormation = .default
    var springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(
        pasteboard: NSPasteboard = NSPasteboard(name: .init("grid-\(UUID().uuidString)")),
        location: NSPoint = .zero
    ) {
        draggingPasteboard = pasteboard
        draggingLocation = location
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}

@MainActor
@Suite("AppGridInteractionCoordinator")
struct AppGridInteractionCoordinatorTests {
    private typealias SUT = (
        host: InteractionHost,
        collectionView: NSCollectionView,
        coordinator: AppGridInteractionCoordinator,
        dragController: DragController
    )

    private typealias NativeDropSUT = (
        grid: AppGridCollectionView,
        coordinator: AppGridInteractionCoordinator,
        dragController: DragController,
        scheduler: MockScheduler,
        source: PageItem,
        target: PageItem,
        sourcePath: IndexPath,
        targetPath: IndexPath,
        sourceFrame: NSRect,
        targetFrame: NSRect,
        previewCell: AppIconCell
    )

    private enum NativeDropScenario {
        case extractionReject
        case destinationReject
        case allowsReject
        case callbackNil
        case callbackFalse
        case callbackTrue
    }

    private enum NativeHoverState: Equatable {
        case pendingTimer
        case visiblePreview
    }

    private func makeSUT(
        reader: @escaping (NSPasteboard) -> String? = { $0.string(forType: .string) }
    ) -> SUT {
        let host = InteractionHost()
        host.collectionViewForDelegateInstallation.frame = NSRect(x: 0, y: 0, width: 800, height: 620)
        let dragController = DragController(scheduler: MockScheduler())
        let coordinator = AppGridInteractionCoordinator(
            dragController: dragController,
            pasteboardUUIDReader: reader
        )
        coordinator.attach(to: host)
        return (host, host.collectionViewForDelegateInstallation, coordinator, dragController)
    }

    private func makeApp(
        id: Int64,
        parentID: Int64? = 100,
        ordering: Int = 0,
        uuid: String? = nil
    ) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: uuid ?? "00000000-0000-0000-0000-\(String(format: "%012lld", id))",
            type: .app,
            ordering: ordering,
            parentId: parentID,
            app: TestDataFactory.makeAppInfo(id: id, title: "A\(id)")
        )
    }

    private func makeGroup(id: Int64, parentID: Int64? = 100) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: "10000000-0000-0000-0000-\(String(format: "%012lld", id))",
            type: .group,
            parentId: parentID,
            group: TestDataFactory.makeGroupInfo(id: id)
        )
    }

    private func makePage(id: Int64) -> PageItem {
        TestDataFactory.makePageItem(id: id, uuid: UUID().uuidString, type: .page)
    }

    private func session(for item: PageItem, kind: DragSourceKind = .topLevel) -> DragSession {
        DragSession(
            itemID: item.id,
            itemUUID: item.uuid,
            itemType: item.type,
            sourceKind: kind,
            sourceParentID: item.parentId ?? 100,
            sourceVisualIndex: 0
        )
    }

    private func beginValidSession(_ item: PageItem, sut: SUT) {
        sut.host.itemsByID[item.id] = item
        sut.dragController.beginDrag(session(for: item))
        sut.coordinator.pasteboardUUIDReader = { _ in item.uuid }
    }

    private func makeNativeDropSUT() throws -> NativeDropSUT {
        let grid = AppGridCollectionView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 620)
        )
        grid.applyGridMetrics(GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 800, height: 620)
        ))
        let source = makeApp(id: 1)
        let target = makeApp(id: 2)
        let sourcePath = IndexPath(item: 0, section: 0)
        let targetPath = IndexPath(item: 1, section: 0)
        grid.reload(
            pages: [[source, target]],
            searchResults: nil,
            searchQuery: nil,
            animatingDifferences: false,
            animateEntrance: false
        )
        grid.collectionViewLayout?.prepare()
        let sourceFrame = try #require(grid.layoutFrame(at: sourcePath))
        let targetFrame = try #require(grid.layoutFrame(at: targetPath))
        let previewCell = AppIconCell()
        _ = previewCell.view
        grid.visibleCellProvider = { path in
            path == targetPath ? previewCell : nil
        }
        grid.indexPathResolver = { _ in targetPath }

        let scheduler = MockScheduler()
        let dragController = DragController(scheduler: scheduler)
        let coordinator = AppGridInteractionCoordinator(
            dragController: dragController,
            pasteboardUUIDReader: { _ in source.uuid }
        )
        coordinator.attach(to: grid)
        return (
            grid, coordinator, dragController, scheduler, source, target,
            sourcePath, targetPath, sourceFrame, targetFrame, previewCell
        )
    }

    private func verifyNativeDropScenario(
        _ scenario: NativeDropScenario,
        hoverState: NativeHoverState = .visiblePreview
    ) throws {
        let sut = try makeNativeDropSUT()
        sut.dragController.beginDrag(session(for: sut.source))
        sut.dragController.updateDragHover(
            .item(itemID: sut.target.id, itemType: sut.target.type)
        )
        switch hoverState {
        case .pendingTimer:
            #expect(!sut.scheduler.scheduledActions.isEmpty)
            #expect(!sut.previewCell.isFolderCreationPreviewVisible)
        case .visiblePreview:
            sut.scheduler.advance(by: 0.8)
            #expect(sut.scheduler.scheduledActions.isEmpty)
            #expect(sut.previewCell.isFolderCreationPreviewVisible)
        }

        var localPoint = NSPoint(x: sut.targetFrame.midX, y: sut.targetFrame.midY)
        var callbackCount = 0
        switch scenario {
        case .extractionReject:
            sut.coordinator.pasteboardUUIDReader = { _ in nil }
        case .destinationReject:
            sut.grid.indexPathResolver = { _ in IndexPath(item: 99, section: 0) }
        case .allowsReject:
            sut.grid.indexPathResolver = { _ in sut.sourcePath }
            localPoint = NSPoint(x: sut.sourceFrame.midX, y: sut.sourceFrame.midY)
        case .callbackNil:
            break
        case .callbackFalse:
            sut.coordinator.onDropRequested = { _, _ in
                callbackCount += 1
                return false
            }
        case .callbackTrue:
            sut.coordinator.onDropRequested = { _, _ in
                callbackCount += 1
                return true
            }
        }

        let snapshotBefore = sut.grid.diffableDataSource.snapshot()
        let sessionBefore = sut.dragController.session
        let cancelCountBefore = sut.scheduler.cancelCallCount
        let accepted = sut.coordinator.collectionView(
            sut.grid,
            acceptDrop: MockDraggingInfo(
                location: sut.grid.convert(localPoint, to: nil)
            ),
            indexPath: sut.targetPath,
            dropOperation: .on
        )
        let expectedAccepted = scenario == .callbackTrue
        let expectedCallbackCount = (scenario == .callbackFalse || scenario == .callbackTrue) ? 1 : 0

        #expect(accepted == expectedAccepted)
        #expect(callbackCount == expectedCallbackCount)
        #expect(sut.grid.diffableDataSource.snapshot().sectionIdentifiers == snapshotBefore.sectionIdentifiers)
        #expect(sut.grid.diffableDataSource.snapshot().itemIdentifiers == snapshotBefore.itemIdentifiers)
        #expect(sut.dragController.session == sessionBefore)
        #expect(sut.dragController.state == .dragging)
        #expect(
            sut.previewCell.isFolderCreationPreviewVisible
                == (hoverState == .visiblePreview)
        )
        #expect(sut.scheduler.cancelCallCount == cancelCountBefore)

        sut.coordinator.collectionView(
            sut.grid,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: []
        )

        #expect(sut.dragController.session == nil)
        #expect(sut.dragController.state == .idle)
        #expect(sut.scheduler.scheduledActions.isEmpty)
        #expect(!sut.previewCell.isFolderCreationPreviewVisible)
        #expect(sut.scheduler.cancelCallCount == cancelCountBefore + 1)
        #expect(callbackCount == expectedCallbackCount)
        #expect(sut.grid.diffableDataSource.snapshot().sectionIdentifiers == snapshotBefore.sectionIdentifiers)
        #expect(sut.grid.diffableDataSource.snapshot().itemIdentifiers == snapshotBefore.itemIdentifiers)
    }

    private func validate(
        sut: SUT,
        location: NSPoint,
        operation: inout NSCollectionView.DropOperation
    ) -> NSDragOperation {
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        let info = MockDraggingInfo(
            location: sut.collectionView.convert(location, to: nil)
        )
        return withUnsafeMutablePointer(to: &operation) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                sut.coordinator.collectionView(
                    sut.collectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(proposedPointer),
                    dropOperation: operationPointer
                )
            }
        }
    }

    private func attachToWindow(_ view: NSView, origin: NSPoint) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [], backing: .buffered, defer: false
        )
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = container
        view.frame = NSRect(x: origin.x, y: origin.y, width: 700, height: 500)
        container.addSubview(view)
        return window
    }

    @Test("pasteboard writer 使用 section 作为真实视觉页")
    func pasteboardWriterStartsSessionWithRealSourceIdentity() throws {
        let sut = makeSUT()
        let source = makeApp(id: 10, parentID: 77, ordering: 5)
        let path = IndexPath(item: 5, section: 2)
        sut.host.sections[2] = .page(2)
        sut.host.install(source, at: path)
        let writer = try #require(sut.coordinator.collectionView(
            sut.collectionView, pasteboardWriterForItemAt: path
        ) as? NSPasteboardItem)
        #expect(writer.string(forType: .string) == source.uuid)
        #expect(sut.dragController.session?.itemID == 10)
        #expect(sut.dragController.session?.sourceParentID == 77)
        #expect(sut.dragController.session?.sourceVisualIndex == 2)
    }

    @Test func pasteboardWriter_groupStartsTopLevelSession() throws {
        let sut = makeSUT()
        let source = makeGroup(id: 2)
        sut.host.install(source, at: IndexPath(item: 0, section: 0))
        #expect(sut.coordinator.collectionView(
            sut.collectionView, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) != nil)
        #expect(sut.dragController.session?.sourceKind == .topLevel)
        #expect(sut.dragController.session?.itemType == .group)
    }

    @Test func pasteboardWriter_pageSearchMissingParentAndMalformedUUIDReturnNil() {
        let sut = makeSUT()
        let path = IndexPath(item: 0, section: 0)
        let missingParent = makeApp(id: 1, parentID: nil)
        sut.host.install(missingParent, at: path)
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.host.install(makeApp(id: 2, uuid: "bad"), at: path)
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.host.install(makePage(id: 3), at: path)
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.host.sections[0] = .search
        sut.host.install(makeApp(id: 4), at: path)
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.host.sections[0] = .searchPage(0)
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.host.sections.removeAll()
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.host.sections[0] = .page(0)
        sut.host.itemsByPath.removeAll()
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.host.install(makeApp(id: 5), at: path)
        sut.host.visualIndices.removeAll()
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.coordinator.isDragEnabled = false
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
        sut.coordinator.detach()
        sut.coordinator.isDragEnabled = true
        #expect(sut.coordinator.collectionView(sut.collectionView, pasteboardWriterForItemAt: path) == nil)
    }

    @Test func extractSession_unknownUUIDStaleSourceAndMismatchedActiveSessionReturnNil() {
        var value: String?
        let sut = makeSUT(reader: { _ in value })
        let source = makeApp(id: 1)
        let other = makeApp(id: 2)
        let info = MockDraggingInfo()
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
        value = "bad"
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
        value = source.uuid
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
        sut.dragController.beginDrag(session(for: source, kind: .folderChild))
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
        sut.dragController.beginDrag(session(for: other))
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
        sut.dragController.beginDrag(session(for: source))
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
        sut.host.itemsByID[source.id] = makeApp(id: source.id, uuid: other.uuid)
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
        sut.host.itemsByID[source.id] = source
        #expect(sut.coordinator.extractActiveSession(from: info) == session(for: source))
        sut.coordinator.isDragEnabled = false
        #expect(sut.coordinator.extractActiveSession(from: info) == nil)
    }

    @Test func validateDrop_leftEdgeFirstPageAndRightEdgeLastPageReject() {
        let source = makeApp(id: 1)
        let sut = makeSUT()
        beginValidSession(source, sut: sut)
        sut.host.emptyPlacementResult = .afterItem(itemID: 9)
        var operation: NSCollectionView.DropOperation = .before
        #expect(validate(sut: sut, location: NSPoint(x: 1, y: 100), operation: &operation).isEmpty)
        #expect(sut.dragController.session?.hoverDestination == .empty)
        sut.host.visualPageCount = 3
        sut.host.currentVisualPageIndex = 2
        #expect(validate(sut: sut, location: NSPoint(x: 799, y: 100), operation: &operation).isEmpty)
        #expect(sut.dragController.session?.hoverDestination == .empty)
    }

    @Test func validateDrop_leftEdgeMiddlePageArmsBackward() {
        let source = makeApp(id: 1)
        let sut = makeSUT()
        beginValidSession(source, sut: sut)
        sut.host.visualPageCount = 3
        sut.host.currentVisualPageIndex = 1
        sut.host.interactionVisibleRect = NSRect(x: 700, y: 0, width: 700, height: 500)
        var operation: NSCollectionView.DropOperation = .before
        #expect(validate(sut: sut, location: NSPoint(x: 701, y: 100), operation: &operation) == .generic)
        #expect(sut.dragController.session?.hoverDestination == .edge(.backward))
        #expect(operation == .before)
    }

    @Test func validateDrop_rightEdgeMiddlePageArmsForward() {
        let source = makeApp(id: 1)
        let sut = makeSUT()
        beginValidSession(source, sut: sut)
        sut.host.visualPageCount = 3
        sut.host.currentVisualPageIndex = 1
        sut.host.interactionVisibleRect = NSRect(x: 700, y: 0, width: 700, height: 500)
        var operation: NSCollectionView.DropOperation = .before
        #expect(validate(sut: sut, location: NSPoint(x: 1399, y: 100), operation: &operation) == .generic)
        #expect(sut.dragController.session?.hoverDestination == .edge(.forward))
        #expect(operation == .before)
    }

    @Test func resolveDestination_beforeAfterAndEmptyUseStableIDs() {
        let sut = makeSUT()
        let target = makeApp(id: 20)
        let path = IndexPath(item: 0, section: 0)
        sut.host.install(target, at: path, frame: NSRect(x: 100, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = path
        #expect(sut.coordinator.resolveGridDestination(at: NSPoint(x: 101, y: 101)) == .placement(.beforeItem(itemID: 20)))
        #expect(sut.coordinator.resolveGridDestination(at: NSPoint(x: 199, y: 101)) == .placement(.afterItem(itemID: 20)))
        sut.host.resolvedPath = nil
        sut.host.emptyPlacementResult = .afterItem(itemID: 30)
        #expect(sut.coordinator.resolveGridDestination(at: .zero) == .placement(.afterItem(itemID: 30)))
        sut.host.emptyPlacementResult = nil
        #expect(sut.coordinator.resolveGridDestination(at: .zero) == nil)
    }

    @Test func resolveDestination_appOnAppAndAppOnGroupAreOnItem() {
        let sut = makeSUT()
        for target in [makeApp(id: 2), makeGroup(id: 3)] {
            let path = IndexPath(item: Int(target.id), section: 0)
            sut.host.install(target, at: path, frame: NSRect(x: 100, y: 100, width: 100, height: 100))
            sut.host.resolvedPath = path
            #expect(sut.coordinator.resolveGridDestination(at: NSPoint(x: 150, y: 150)) == .onItem(itemID: target.id, itemType: target.type))
        }
    }

    @Test func resolveDestination_groupOnAppGroupAndSelfReject() {
        let sut = makeSUT()
        let group = makeGroup(id: 1)
        let app = makeApp(id: 2)
        for target in [app, makeGroup(id: 3), group] {
            #expect(!sut.coordinator.allows(session: session(for: group), destination: .onItem(itemID: target.id, itemType: target.type)))
        }
        #expect(!sut.coordinator.allows(session: session(for: app), destination: .onItem(itemID: app.id, itemType: .app)))
        #expect(!sut.coordinator.allows(session: session(for: app), destination: .onItem(itemID: 9, itemType: .page)))
        #expect(!sut.coordinator.allows(session: session(for: app), destination: .placement(.afterItem(itemID: app.id))))
    }

    @Test func resolveDestination_staleTargetRejects() {
        let sut = makeSUT()
        sut.host.resolvedPath = IndexPath(item: 9, section: 0)
        #expect(sut.coordinator.resolveGridDestination(at: .zero) == nil)
        let item = makeApp(id: 9)
        sut.host.itemsByPath[sut.host.resolvedPath!] = item
        #expect(sut.coordinator.resolveGridDestination(at: .zero) == nil)
    }

    @Test func topLevelPlacement_coversPlacementOnItemAndNil() {
        let sut = makeSUT()
        sut.host.emptyPlacementResult = .afterItem(itemID: 8)
        #expect(sut.coordinator.topLevelPlacement(atLocalPoint: .zero) == .afterItem(itemID: 8))
        let item = makeApp(id: 2)
        let path = IndexPath(item: 0, section: 0)
        sut.host.install(item, at: path, frame: NSRect(x: 100, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = path
        #expect(sut.coordinator.topLevelPlacement(atLocalPoint: NSPoint(x: 125, y: 150)) == .beforeItem(itemID: 2))
        #expect(sut.coordinator.topLevelPlacement(atLocalPoint: NSPoint(x: 175, y: 150)) == .afterItem(itemID: 2))
        sut.host.pathsByID.removeAll()
        #expect(sut.coordinator.topLevelPlacement(atLocalPoint: NSPoint(x: 150, y: 150)) == nil)
    }

    @Test func acceptDrop_callbackFailureKeepsSnapshotUnchanged() throws {
        try verifyNativeDropScenario(.callbackFalse, hoverState: .pendingTimer)
        try verifyNativeDropScenario(.callbackFalse, hoverState: .visiblePreview)
    }

    @Test func validateDrop_destinationPolicyMatrixUsesModernHover() {
        let source = makeApp(id: 1)
        let appTarget = makeApp(id: 2)
        let groupTarget = makeGroup(id: 3)
        let pageTarget = makePage(id: 4)
        let sut = makeSUT()
        beginValidSession(source, sut: sut)
        var operation: NSCollectionView.DropOperation = .before

        sut.host.resolvedPath = nil
        sut.host.emptyPlacementResult = nil
        #expect(validate(sut: sut, location: NSPoint(x: 400, y: 300), operation: &operation).isEmpty)
        #expect(sut.dragController.session?.hoverDestination == .empty)

        let sourcePath = IndexPath(item: 0, section: 0)
        sut.host.install(source, at: sourcePath, frame: NSRect(x: 100, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = sourcePath
        #expect(validate(sut: sut, location: NSPoint(x: 101, y: 101), operation: &operation).isEmpty)
        #expect(validate(sut: sut, location: NSPoint(x: 150, y: 150), operation: &operation).isEmpty)
        #expect(sut.dragController.session?.hoverDestination == .empty)

        let appPath = IndexPath(item: 1, section: 0)
        sut.host.install(appTarget, at: appPath, frame: NSRect(x: 200, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = appPath
        #expect(validate(sut: sut, location: NSPoint(x: 201, y: 101), operation: &operation) == .move)
        #expect(sut.dragController.session?.hoverDestination == .empty)
        #expect(validate(sut: sut, location: NSPoint(x: 299, y: 101), operation: &operation) == .move)
        #expect(sut.dragController.session?.hoverDestination == .empty)
        #expect(validate(sut: sut, location: NSPoint(x: 250, y: 150), operation: &operation) == .move)
        #expect(sut.dragController.session?.hoverDestination == .item(itemID: 2, itemType: .app))

        let groupPath = IndexPath(item: 2, section: 0)
        sut.host.install(groupTarget, at: groupPath, frame: NSRect(x: 300, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = groupPath
        #expect(validate(sut: sut, location: NSPoint(x: 350, y: 150), operation: &operation) == .move)
        #expect(sut.dragController.session?.hoverDestination == .item(itemID: 3, itemType: .group))

        let pagePath = IndexPath(item: 3, section: 0)
        sut.host.install(pageTarget, at: pagePath, frame: NSRect(x: 400, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = pagePath
        #expect(validate(sut: sut, location: NSPoint(x: 450, y: 150), operation: &operation).isEmpty)
        #expect(sut.dragController.session?.hoverDestination == .empty)
        sut.host.resolvedPath = IndexPath(item: 99, section: 0)
        #expect(validate(sut: sut, location: NSPoint(x: 400, y: 300), operation: &operation).isEmpty)
        #expect(sut.dragController.session?.hoverDestination == .empty)

        sut.coordinator.pasteboardUUIDReader = { _ in nil }
        #expect(validate(sut: sut, location: NSPoint(x: 400, y: 300), operation: &operation).isEmpty)
        #expect(sut.dragController.session?.hoverDestination == .empty)
    }

    @Test func acceptDrop_rejectionsWaitForNativeEndedWithoutCallback() throws {
        for scenario in [
            NativeDropScenario.extractionReject,
            .destinationReject,
            .allowsReject,
        ] {
            try verifyNativeDropScenario(scenario, hoverState: .pendingTimer)
            try verifyNativeDropScenario(scenario, hoverState: .visiblePreview)
        }
    }

    @Test func validateDropConvertsWindowPointForNonZeroViewOrigin() throws {
        let source = makeApp(id: 1)
        let target = makeApp(id: 2)
        let sut = makeSUT()
        beginValidSession(source, sut: sut)
        let path = IndexPath(item: 1, section: 0)
        sut.host.install(target, at: path, frame: NSRect(x: 200, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = path
        let window = attachToWindow(sut.collectionView, origin: NSPoint(x: 120, y: 80))
        _ = window
        let localPoint = NSPoint(x: 250, y: 150)
        let info = MockDraggingInfo(location: sut.collectionView.convert(localPoint, to: nil))
        var proposed = NSIndexPath(forItem: 1, inSection: 0)
        var operation: NSCollectionView.DropOperation = .before
        let result = withUnsafeMutablePointer(to: &operation) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                sut.coordinator.collectionView(
                    sut.collectionView, validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(proposedPointer),
                    dropOperation: operationPointer
                )
            }
        }
        let resolved = try #require(sut.host.resolvedPoints.last)
        #expect(abs(resolved.x - localPoint.x) <= 0.001)
        #expect(abs(resolved.y - localPoint.y) <= 0.001)
        #expect(result == .move)
        #expect(operation == .on)
        #expect(sut.dragController.session?.hoverDestination == .item(itemID: 2, itemType: .app))
    }

    @Test func acceptDropConvertsWindowPointForNonZeroViewOrigin() throws {
        let source = makeApp(id: 1)
        let target = makeApp(id: 2)
        let sut = makeSUT()
        beginValidSession(source, sut: sut)
        let path = IndexPath(item: 1, section: 0)
        sut.host.install(target, at: path, frame: NSRect(x: 200, y: 100, width: 100, height: 100))
        sut.host.resolvedPath = path
        sut.coordinator.onDropRequested = { _, _ in true }
        let window = attachToWindow(sut.collectionView, origin: NSPoint(x: 120, y: 80))
        _ = window
        let localPoint = NSPoint(x: 250, y: 150)
        let accepted = sut.coordinator.collectionView(
            sut.collectionView,
            acceptDrop: MockDraggingInfo(location: sut.collectionView.convert(localPoint, to: nil)),
            indexPath: path,
            dropOperation: .on
        )
        let resolved = try #require(sut.host.resolvedPoints.last)
        #expect(abs(resolved.x - localPoint.x) <= 0.001)
        #expect(abs(resolved.y - localPoint.y) <= 0.001)
        #expect(accepted)
        #expect(sut.dragController.session != nil)
    }

    @Test func acceptDrop_callbackNilWaitsForNativeEnded() throws {
        try verifyNativeDropScenario(.callbackNil)
    }

    @Test func draggingSessionEndClearsSessionTimerAndPreview() throws {
        try verifyNativeDropScenario(.callbackTrue, hoverState: .pendingTimer)
        try verifyNativeDropScenario(.callbackTrue, hoverState: .visiblePreview)
    }

    @Test("禁用拖放同步拒绝 source、validate、accept 且不改 snapshot")
    func disabledDragRejectsAllNativeBoundariesWithoutSnapshotMutation() throws {
        let sut = try makeNativeDropSUT()
        let snapshotBefore = sut.grid.diffableDataSource.snapshot()
        sut.coordinator.isDragEnabled = false
        #expect(sut.coordinator.collectionView(
            sut.grid,
            pasteboardWriterForItemAt: sut.sourcePath
        ) == nil)

        sut.dragController.beginDrag(session(for: sut.source))
        var proposed = NSIndexPath(forItem: sut.targetPath.item, inSection: 0)
        var operation: NSCollectionView.DropOperation = .before
        let info = MockDraggingInfo(
            location: sut.grid.convert(
                NSPoint(x: sut.targetFrame.midX, y: sut.targetFrame.midY),
                to: nil
            )
        )
        let validation = withUnsafeMutablePointer(to: &operation) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                sut.coordinator.collectionView(
                    sut.grid,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(proposedPointer),
                    dropOperation: operationPointer
                )
            }
        }
        var callbackCount = 0
        sut.coordinator.onDropRequested = { _, _ in
            callbackCount += 1
            return true
        }
        let accepted = sut.coordinator.collectionView(
            sut.grid,
            acceptDrop: info,
            indexPath: sut.targetPath,
            dropOperation: .on
        )

        #expect(validation.isEmpty)
        #expect(!accepted)
        #expect(callbackCount == 0)
        #expect(sut.grid.diffableDataSource.snapshot().sectionIdentifiers == snapshotBefore.sectionIdentifiers)
        #expect(sut.grid.diffableDataSource.snapshot().itemIdentifiers == snapshotBefore.itemIdentifiers)

        sut.coordinator.isDragEnabled = true
        #expect(sut.coordinator.collectionView(
            sut.grid,
            pasteboardWriterForItemAt: sut.sourcePath
        ) != nil)
    }

    @Test("显式取消后重复禁用和 native ended 不重复 cleanup")
    func explicitCancellationMakesLaterNativeEndedIdempotent() throws {
        let sut = try makeNativeDropSUT()
        sut.dragController.beginDrag(session(for: sut.source))
        sut.dragController.updateDragHover(
            .item(itemID: sut.target.id, itemType: sut.target.type)
        )
        let cancelCountBefore = sut.scheduler.cancelCallCount

        sut.coordinator.isDragEnabled = false
        #expect(sut.dragController.session == nil)
        #expect(sut.scheduler.cancelCallCount == cancelCountBefore + 1)
        sut.coordinator.isDragEnabled = false
        sut.coordinator.collectionView(
            sut.grid,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: []
        )

        #expect(sut.scheduler.cancelCallCount == cancelCountBefore + 1)
        #expect(sut.dragController.state == .idle)
        #expect(sut.dragController.session == nil)
        #expect(sut.scheduler.scheduledActions.isEmpty)
    }

    @Test func lifecycle_attachDetachAndReattachOwnPreviewBinding() {
        let sut = makeSUT()
        let source = makeApp(id: 1)
        sut.dragController.beginDrag(session(for: source))
        sut.dragController.updateDragHover(.item(itemID: 2, itemType: .app))
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)
        let coordinator = AppGridInteractionCoordinator(dragController: controller, pasteboardUUIDReader: { _ in nil })
        let first = InteractionHost()
        let second = InteractionHost()
        coordinator.attach(to: first)
        coordinator.attach(to: first)
        coordinator.attach(to: second)
        #expect(first.collectionViewForDelegateInstallation.delegate == nil)
        controller.beginDrag(session(for: source))
        controller.updateDragHover(.item(itemID: 2, itemType: .app))
        scheduler.advance(by: 0.8)
        #expect(first.previewCalls.count == 2)
        #expect(first.previewCalls.last! == nil)
        #expect(second.previewCalls.last == 2)
        coordinator.detach()
        #expect(second.previewCalls.last! == nil)
        controller.updateDragHover(.empty)
        #expect(second.previewCalls.last! == nil)
    }

    @Test func detach_preservesExternalDelegateAndHostDeallocationIsSafe() {
        final class ExternalDelegate: NSObject, NSCollectionViewDelegate {}
        var host: InteractionHost? = InteractionHost()
        let grid = host!.collectionViewForDelegateInstallation
        let coordinator = AppGridInteractionCoordinator(dragController: DragController(scheduler: MockScheduler()), pasteboardUUIDReader: { _ in nil })
        coordinator.attach(to: host!)
        let external = ExternalDelegate()
        grid.delegate = external
        coordinator.detach()
        #expect(grid.delegate === external)
        coordinator.attach(to: host!)
        host = nil
        #expect(coordinator.host == nil)
        #expect(coordinator.collectionView(grid, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)) == nil)
    }

    @Test func selectionAndDragImageDelegateBranches() throws {
        let sut = makeSUT()
        let item = makeApp(id: 1)
        let path = IndexPath(item: 0, section: 0)
        sut.host.install(item, at: path)
        var events: [String] = []
        sut.coordinator.onSelectionChanged = { events.append("changed:\($0.id)") }
        sut.coordinator.onItemActivated = { events.append("activated:\($0.id)") }
        sut.coordinator.collectionView(sut.collectionView, didSelectItemsAt: [])
        sut.coordinator.collectionView(sut.collectionView, didSelectItemsAt: [IndexPath(item: 9, section: 0)])
        sut.coordinator.collectionView(sut.collectionView, didSelectItemsAt: [path])
        #expect(events == ["changed:1", "activated:1"])
        var offset = NSPoint.zero
        #expect(sut.coordinator.collectionView(sut.collectionView, draggingImageForItemsAt: [], with: NSEvent(), offset: &offset).size == .zero)
        sut.host.renderedImages[path] = NSImage(size: NSSize(width: 64, height: 64))
        #expect(sut.coordinator.collectionView(sut.collectionView, draggingImageForItemsAt: [path], with: NSEvent(), offset: &offset).size.width == 64)
    }

    @Test func weakHostAndOwnerGraphReleaseWithoutCycle() {
        weak var weakHost: InteractionHost?
        weak var weakGrid: NSCollectionView?
        weak var weakCoordinator: AppGridInteractionCoordinator?
        do {
            let sut = makeSUT()
            weakHost = sut.host
            weakGrid = sut.collectionView
            weakCoordinator = sut.coordinator
        }
        #expect(weakHost == nil)
        #expect(weakGrid == nil)
        #expect(weakCoordinator == nil)
    }

    @Test func programmaticSelectionNeverEmitsBusinessOutput() throws {
        let grid = AppGridCollectionView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 620)
        )
        let coordinator = AppGridInteractionCoordinator(
            dragController: DragController(scheduler: MockScheduler()),
            pasteboardUUIDReader: { _ in nil }
        )
        coordinator.attach(to: grid)
        #expect(grid.delegate === coordinator)
        #expect(grid.delegate !== grid)
        let items = [makeApp(id: 1), makeApp(id: 2)]
        grid.reload(
            pages: [items], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        var events: [Int64] = []
        coordinator.onSelectionChanged = { events.append($0.id) }
        coordinator.onItemActivated = { events.append($0.id) }
        _ = try #require(grid.selectItem(id: items[0].id))
        _ = grid.selectItem(id: nil)
        _ = grid.selectItem(id: 999)
        #expect(events.isEmpty)
    }

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

        let app = makeApp(id: 1)
        let folder = makeGroup(id: 2)
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
        let delegate = try #require(grid.delegate)
        delegate.collectionView?(
            grid,
            didSelectItemsAt: [IndexPath(item: 0, section: 0)]
        )
        _ = grid.selectItem(id: nil)
        grid.reload(
            pages: [[app, folder]], searchResults: nil, searchQuery: nil,
            animatingDifferences: false, animateEntrance: false
        )
        grid.layoutSubtreeIfNeeded()
        delegate.collectionView?(
            grid,
            didSelectItemsAt: [IndexPath(item: 1, section: 0)]
        )

        #expect(clock.now - start < .seconds(1))
    }
}
#endif
