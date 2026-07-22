import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor
private final class InteractionHost: AppGridInteractionHosting {
    let collectionViewForDelegateInstallation: NSCollectionView
    var itemsByPath: [IndexPath: PageItem] = [:]
    var itemsByUUID: [String: PageItem] = [:]
    var resolvedPath: IndexPath?
    var renderedImages: [IndexPath: NSImage] = [:]
    private(set) var snapshotMoves: [(PageItem, PageItem)] = []

    init(collectionView: NSCollectionView = NSCollectionView()) {
        collectionViewForDelegateInstallation = collectionView
    }

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
        let knownIDs = Set(itemsByPath.values.map(\.id))
        guard knownIDs.contains(item.id) || knownIDs.contains(target.id) else { return }
        snapshotMoves.append((item, target))
    }
}

@MainActor
private final class CoordinatorDraggingInfo: NSObject, @MainActor NSDraggingInfo {
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

    init(location: NSPoint = .zero) {
        draggingPasteboard = NSPasteboard(
            name: .init("AppGridInteractionCoordinatorTests-\(UUID().uuidString)")
        )
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

    private func makeSUT(
        reader: @escaping (NSPasteboard) -> String? = {
            $0.string(forType: .string)
        }
    ) -> SUT {
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

    private func app(id: Int64, uuid: String? = nil) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: uuid ?? "app-\(id)",
            type: .app,
            app: TestDataFactory.makeAppInfo(id: id, title: "App \(id)")
        )
    }

    private func group(id: Int64, uuid: String? = nil) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: uuid ?? "group-\(id)",
            type: .group,
            group: TestDataFactory.makeGroupInfo(id: id, title: "Folder \(id)")
        )
    }

    private func page(id: Int64) -> PageItem {
        TestDataFactory.makePageItem(id: id, uuid: "page-\(id)", type: .page)
    }

    private func validate(
        _ coordinator: AppGridInteractionCoordinator,
        collectionView: NSCollectionView,
        location: NSPoint,
        dropOperation: inout NSCollectionView.DropOperation
    ) -> NSDragOperation {
        let info = CoordinatorDraggingInfo(location: location)
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        return withUnsafeMutablePointer(to: &dropOperation) { operation in
            withUnsafeMutablePointer(to: &proposed) { path in
                coordinator.collectionView(
                    collectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(path),
                    dropOperation: operation
                )
            }
        }
    }

    @Test func onItemActivated_callbackIsSettable() {
        let sut = makeSUT()
        sut.coordinator.onItemActivated = { _ in }
        #expect(sut.coordinator.onItemActivated != nil)
    }

    @Test func pasteboardWriterForItemAt_appItem_writesUuid() throws {
        let sut = makeSUT()
        let item = app(id: 1, uuid: "drag-app-1")
        sut.host.itemsByPath[IndexPath(item: 0, section: 0)] = item
        let writer = sut.coordinator.collectionView(
            sut.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        )
        let pasteboardItem = try #require(writer as? NSPasteboardItem)
        #expect(pasteboardItem.string(forType: .string) == item.uuid)
    }

    @Test func pasteboardWriterForItemAt_groupItem_writesUuid() throws {
        let sut = makeSUT()
        let item = group(id: 2, uuid: "drag-group-2")
        sut.host.itemsByPath[IndexPath(item: 0, section: 0)] = item
        let writer = sut.coordinator.collectionView(
            sut.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        )
        let pasteboardItem = try #require(writer as? NSPasteboardItem)
        #expect(pasteboardItem.string(forType: .string) == item.uuid)
    }

    @Test func pasteboardWriterForItemAt_pageItem_returnsNil() {
        let sut = makeSUT()
        sut.host.itemsByPath[IndexPath(item: 0, section: 0)] = page(id: 1)
        #expect(sut.coordinator.collectionView(
            sut.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) == nil)
    }

    @Test func validateDrop_screenEdge_returnsGeneric() {
        let sut = makeSUT()
        var operation: NSCollectionView.DropOperation = .on
        let result = validate(
            sut.coordinator,
            collectionView: sut.collectionView,
            location: NSPoint(x: 10, y: 100),
            dropOperation: &operation
        )
        #expect(result == .generic)
    }

    @Test func validateDrop_rightEdge_returnsGeneric() {
        let sut = makeSUT()
        var operation: NSCollectionView.DropOperation = .on
        let result = validate(
            sut.coordinator,
            collectionView: sut.collectionView,
            location: NSPoint(x: 790, y: 100),
            dropOperation: &operation
        )
        #expect(result == .generic)
    }

    @Test func validateDrop_emptyArea_returnsMove() {
        let sut = makeSUT()
        var operation: NSCollectionView.DropOperation = .before
        let result = validate(
            sut.coordinator,
            collectionView: sut.collectionView,
            location: NSPoint(x: 400, y: 100),
            dropOperation: &operation
        )
        #expect(result == .move)
        #expect(operation == .on)
    }

    @Test func acceptDrop_onGroupTarget_returnsTrue() {
        let source = app(id: 1)
        let sut = makeSUT(reader: { _ in source.uuid })
        let target = group(id: 2)
        sut.host.itemsByUUID[source.uuid] = source
        sut.host.itemsByPath[IndexPath(item: 1, section: 0)] = target
        sut.dragController.handleDragStart()
        let accepted = sut.coordinator.collectionView(
            sut.collectionView,
            acceptDrop: CoordinatorDraggingInfo(),
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .on
        )
        #expect(accepted)
        #expect(sut.dragController.state == .idle)
    }

    @Test func acceptDrop_invalidPasteboard_returnsFalse() {
        let sut = makeSUT(reader: { _ in nil })
        sut.dragController.handleDragStart()
        #expect(!sut.coordinator.collectionView(
            sut.collectionView,
            acceptDrop: CoordinatorDraggingInfo(),
            indexPath: IndexPath(item: 0, section: 0),
            dropOperation: .on
        ))
        #expect(sut.dragController.state == .dragging)
    }

    @Test func draggingImageForItemsAt_returnsImage() {
        let sut = makeSUT()
        let path = IndexPath(item: 0, section: 0)
        sut.host.renderedImages[path] = NSImage(size: NSSize(width: 64, height: 64))
        var offset = NSPoint.zero
        let image = sut.coordinator.collectionView(
            sut.collectionView,
            draggingImageForItemsAt: [path],
            with: NSEvent(),
            offset: &offset
        )
        #expect(image.size == NSSize(width: 64, height: 64))
    }

    @Test func onItemActivated_triggeredViaDidSelect() {
        let sut = makeSUT()
        let item = app(id: 1)
        let path = IndexPath(item: 0, section: 0)
        sut.host.itemsByPath[path] = item
        var selected: PageItem?
        sut.coordinator.onItemActivated = { selected = $0 }
        sut.coordinator.collectionView(sut.collectionView, didSelectItemsAt: [path])
        #expect(selected?.id == item.id)
    }

    @Test func onItemActivated_emptySelection_doesNotFire() {
        let sut = makeSUT()
        var called = false
        sut.coordinator.onItemActivated = { _ in called = true }
        sut.coordinator.collectionView(sut.collectionView, didSelectItemsAt: [])
        #expect(!called)
    }

    @Test func resolveHoverLocation_overIcon_whenGroupAtLocation() {
        let sut = makeSUT()
        let path = IndexPath(item: 0, section: 0)
        let item = group(id: 2)
        sut.host.resolvedPath = path
        sut.host.itemsByPath[path] = item
        #expect(sut.coordinator.resolveHoverLocation(at: .zero) == .overIcon(targetId: item.id))
    }

    @Test func resolveHoverLocation_empty_whenAppAtLocation() {
        let sut = makeSUT()
        let path = IndexPath(item: 0, section: 0)
        sut.host.resolvedPath = path
        sut.host.itemsByPath[path] = app(id: 1)
        #expect(sut.coordinator.resolveHoverLocation(at: .zero) == .empty)
    }

    @Test func resolveHoverLocation_empty_whenResolverReturnsNil() {
        let sut = makeSUT()
        #expect(sut.coordinator.resolveHoverLocation(at: .zero) == .empty)
    }

    @Test func acceptDrop_reorderSamePage_performsReorder() {
        let source = app(id: 1)
        let target = app(id: 2)
        let sut = makeSUT(reader: { _ in source.uuid })
        sut.host.itemsByUUID[source.uuid] = source
        sut.host.itemsByPath[IndexPath(item: 0, section: 0)] = source
        sut.host.itemsByPath[IndexPath(item: 1, section: 0)] = target
        #expect(sut.coordinator.collectionView(
            sut.collectionView,
            acceptDrop: CoordinatorDraggingInfo(),
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .on
        ))
        #expect(sut.host.snapshotMoves.map { [$0.0.id, $0.1.id] } == [[source.id, target.id]])
    }

    @Test func acceptDrop_outOfRangeTarget_returnsFalse() {
        let source = app(id: 1)
        let sut = makeSUT(reader: { _ in source.uuid })
        sut.host.itemsByUUID[source.uuid] = source
        #expect(!sut.coordinator.collectionView(
            sut.collectionView,
            acceptDrop: CoordinatorDraggingInfo(),
            indexPath: IndexPath(item: 99, section: 0),
            dropOperation: .on
        ))
    }

    @Test func extractDraggedItem_validPasteboard_returnsItem() {
        let item = app(id: 1)
        let sut = makeSUT(reader: { _ in item.uuid })
        sut.host.itemsByUUID[item.uuid] = item
        #expect(sut.coordinator.extractDraggedItem(from: CoordinatorDraggingInfo())?.id == item.id)
    }

    @Test func extractDraggedItem_emptyPasteboard_returnsNil() {
        let sut = makeSUT(reader: { _ in nil })
        #expect(sut.coordinator.extractDraggedItem(from: CoordinatorDraggingInfo()) == nil)
    }

    @Test func performDrop_onGroupTarget_returnsTrue() {
        let sut = makeSUT()
        #expect(sut.coordinator.performDrop(draggedItem: app(id: 1), targetItem: group(id: 2)))
        #expect(sut.host.snapshotMoves.isEmpty)
    }

    @Test func performDrop_reorderSamePage_returnsTrue() {
        let sut = makeSUT()
        let source = app(id: 1)
        let target = app(id: 2)
        sut.host.itemsByPath[IndexPath(item: 0, section: 0)] = source
        sut.host.itemsByPath[IndexPath(item: 1, section: 0)] = target
        #expect(sut.coordinator.performDrop(draggedItem: source, targetItem: target))
        #expect(sut.host.snapshotMoves.count == 1)
    }

    @Test func draggingImageForItemsAt_usesInjectedCellProvider() {
        let sut = makeSUT()
        let path = IndexPath(item: 0, section: 0)
        let expected = NSImage(size: NSSize(width: 64, height: 64))
        sut.host.renderedImages[path] = expected
        var offset = NSPoint.zero
        let result = sut.coordinator.collectionView(
            sut.collectionView,
            draggingImageForItemsAt: [path],
            with: NSEvent(),
            offset: &offset
        )
        #expect(result === expected)
    }

    @Test func performDrop_bothItemsNotInSnapshot_noOp() {
        let sut = makeSUT()
        #expect(sut.coordinator.performDrop(draggedItem: app(id: 1), targetItem: app(id: 2)))
        #expect(sut.host.snapshotMoves.isEmpty)
    }

    @Test("selection callbacks 保持 changed 后 activated 的精确顺序")
    func selectionCallbacksPreserveChangedThenActivatedOrder() {
        let sut = makeSUT()
        let item = app(id: 1)
        let path = IndexPath(item: 0, section: 0)
        sut.host.itemsByPath[path] = item
        var events: [String] = []
        sut.coordinator.onSelectionChanged = { events.append("changed:\($0.id)") }
        sut.coordinator.onItemActivated = { events.append("activated:\($0.id)") }
        let delegate = sut.collectionView.delegate
        delegate?.collectionView?(sut.collectionView, didSelectItemsAt: [path])
        #expect(events == ["changed:1", "activated:1"])
    }

    @Test func selection_emptyAndStaleEmitNothing() {
        let sut = makeSUT()
        var events: [Int64] = []
        sut.coordinator.onSelectionChanged = { events.append($0.id) }
        sut.coordinator.onItemActivated = { events.append($0.id) }
        sut.coordinator.collectionView(sut.collectionView, didSelectItemsAt: [])
        sut.coordinator.collectionView(
            sut.collectionView,
            didSelectItemsAt: [IndexPath(item: 99, section: 0)]
        )
        #expect(events.isEmpty)
    }

    @Test func selection_validEmitsChangedThenActivated() {
        let sut = makeSUT()
        let item = app(id: 7)
        let path = IndexPath(item: 0, section: 0)
        sut.host.itemsByPath[path] = item
        var events: [String] = []
        sut.coordinator.onSelectionChanged = { events.append("changed:\($0.id)") }
        sut.coordinator.onItemActivated = { events.append("activated:\($0.id)") }
        sut.coordinator.collectionView(sut.collectionView, didSelectItemsAt: [path])
        #expect(events == ["changed:7", "activated:7"])
    }

    @Test func selection_hasNoDeselectOutput() {
        let sut = makeSUT()
        var events: [Int64] = []
        sut.coordinator.onSelectionChanged = { events.append($0.id) }
        sut.collectionView.selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: [])
        sut.collectionView.deselectItems(at: sut.collectionView.selectionIndexPaths)
        #expect(events.isEmpty)
    }

    @Test func writer_appGroupPageAndMissing() throws {
        let sut = makeSUT()
        let values = [app(id: 1), group(id: 2), page(id: 3)]
        for (index, item) in values.enumerated() {
            sut.host.itemsByPath[IndexPath(item: index, section: 0)] = item
        }
        for index in 0..<2 {
            let writer = try #require(sut.coordinator.collectionView(
                sut.collectionView,
                pasteboardWriterForItemAt: IndexPath(item: index, section: 0)
            ) as? NSPasteboardItem)
            #expect(writer.string(forType: .string) == values[index].uuid)
        }
        #expect(sut.coordinator.collectionView(
            sut.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 2, section: 0)
        ) == nil)
        #expect(sut.coordinator.collectionView(
            sut.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 99, section: 0)
        ) == nil)
    }

    @Test func validation_allLocationAndStateBranches() {
        let sut = makeSUT()
        let groupPath = IndexPath(item: 0, section: 0)
        let appPath = IndexPath(item: 1, section: 0)
        let pagePath = IndexPath(item: 2, section: 0)
        sut.host.itemsByPath[groupPath] = group(id: 1)
        sut.host.itemsByPath[appPath] = app(id: 2)
        sut.host.itemsByPath[pagePath] = page(id: 3)
        var operation: NSCollectionView.DropOperation = .before

        for path in [groupPath, appPath, pagePath, IndexPath(item: 99, section: 0)] {
            sut.host.resolvedPath = path
            #expect(validate(
                sut.coordinator,
                collectionView: sut.collectionView,
                location: NSPoint(x: 400, y: 100),
                dropOperation: &operation
            ) == .move)
        }
        sut.host.resolvedPath = nil
        #expect(validate(
            sut.coordinator,
            collectionView: sut.collectionView,
            location: NSPoint(x: 400, y: 100),
            dropOperation: &operation
        ) == .move)
        #expect(sut.dragController.state == .idle)
        sut.dragController.handleDragStart()
        sut.host.resolvedPath = groupPath
        _ = validate(
            sut.coordinator,
            collectionView: sut.collectionView,
            location: NSPoint(x: 400, y: 100),
            dropOperation: &operation
        )
        #expect(sut.dragController.draggingSubstate == .overIcon(targetId: 1))
        for x in [CGFloat(10), CGFloat(790)] {
            #expect(validate(
                sut.coordinator,
                collectionView: sut.collectionView,
                location: NSPoint(x: x, y: 100),
                dropOperation: &operation
            ) == .generic)
        }
    }

    @Test func validation_edgePreservesDropOperationSentinel() {
        let sut = makeSUT()
        for x in [CGFloat(10), CGFloat(790)] {
            var operation: NSCollectionView.DropOperation = .before
            #expect(validate(
                sut.coordinator,
                collectionView: sut.collectionView,
                location: NSPoint(x: x, y: 100),
                dropOperation: &operation
            ) == .generic)
            #expect(operation == .before)
        }
    }

    @Test func acceptance_allSourceAndTargetBranches() {
        let source = app(id: 1)
        let ordinary = app(id: 2)
        let folder = group(id: 3)
        var value: String?
        let sut = makeSUT(reader: { _ in value })
        sut.host.itemsByUUID[source.uuid] = source
        sut.host.itemsByPath[IndexPath(item: 0, section: 0)] = ordinary
        sut.host.itemsByPath[IndexPath(item: 1, section: 0)] = folder
        let info = CoordinatorDraggingInfo()

        value = nil
        #expect(!sut.coordinator.collectionView(
            sut.collectionView, acceptDrop: info,
            indexPath: IndexPath(item: 0, section: 0), dropOperation: .on
        ))
        for invalid in ["malformed", "unknown-source"] {
            value = invalid
            #expect(!sut.coordinator.collectionView(
                sut.collectionView, acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0), dropOperation: .on
            ))
        }
        value = source.uuid
        #expect(!sut.coordinator.collectionView(
            sut.collectionView, acceptDrop: info,
            indexPath: IndexPath(item: 99, section: 0), dropOperation: .on
        ))
        #expect(sut.coordinator.collectionView(
            sut.collectionView, acceptDrop: info,
            indexPath: IndexPath(item: 1, section: 0), dropOperation: .on
        ))
        #expect(sut.coordinator.collectionView(
            sut.collectionView, acceptDrop: info,
            indexPath: IndexPath(item: 0, section: 0), dropOperation: .on
        ))
        let absentSource = app(id: 10)
        let absentTarget = app(id: 11)
        #expect(sut.coordinator.performDrop(
            draggedItem: absentSource,
            targetItem: absentTarget
        ))
        #expect(!sut.host.snapshotMoves.contains {
            $0.0.id == absentSource.id && $0.1.id == absentTarget.id
        })
    }

    @Test func dragImage_emptyMissingAndValid() {
        let sut = makeSUT()
        var offset = NSPoint.zero
        let empty = sut.coordinator.collectionView(
            sut.collectionView,
            draggingImageForItemsAt: [],
            with: NSEvent(), offset: &offset
        )
        let missing = sut.coordinator.collectionView(
            sut.collectionView,
            draggingImageForItemsAt: [IndexPath(item: 9, section: 0)],
            with: NSEvent(), offset: &offset
        )
        let path = IndexPath(item: 0, section: 0)
        let expected = NSImage(size: NSSize(width: 64, height: 64))
        sut.host.renderedImages[path] = expected
        let valid = sut.coordinator.collectionView(
            sut.collectionView,
            draggingImageForItemsAt: [path],
            with: NSEvent(), offset: &offset
        )
        #expect(empty.size == .zero)
        #expect(missing.size == .zero)
        #expect(valid === expected)
    }

    @Test func attach_isIdempotentAndMovesFromAToB() {
        let sut = makeSUT()
        #expect(sut.collectionView.delegate === sut.coordinator)
        #expect(sut.collectionView.delegate !== sut.collectionView)
        sut.coordinator.attach(to: sut.host)
        #expect(sut.collectionView.delegate === sut.coordinator)
        let second = InteractionHost()
        sut.coordinator.attach(to: second)
        #expect(sut.collectionView.delegate == nil)
        #expect(second.collectionViewForDelegateInstallation.delegate === sut.coordinator)
    }

    @Test func detach_preservesExternalDelegateAndIsIdempotent() {
        final class ExternalDelegate: NSObject, NSCollectionViewDelegate {}
        let sut = makeSUT()
        let external = ExternalDelegate()
        sut.collectionView.delegate = external
        sut.coordinator.detach()
        sut.coordinator.detach()
        #expect(sut.collectionView.delegate === external)
        #expect(sut.coordinator.host == nil)
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

    @Test func hostReleaseMakesAllFiveEntrypointsSafe() {
        var host: InteractionHost? = InteractionHost()
        let collectionView = host!.collectionViewForDelegateInstallation
        collectionView.frame = NSRect(x: 0, y: 0, width: 800, height: 620)
        let coordinator = AppGridInteractionCoordinator(
            dragController: DragController(scheduler: MockScheduler()),
            pasteboardUUIDReader: { _ in nil }
        )
        coordinator.attach(to: host!)
        host = nil
        var events = 0
        coordinator.onSelectionChanged = { _ in events += 1 }
        coordinator.onItemActivated = { _ in events += 1 }
        coordinator.collectionView(
            collectionView,
            didSelectItemsAt: [IndexPath(item: 0, section: 0)]
        )
        #expect(coordinator.collectionView(
            collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) == nil)
        var operation: NSCollectionView.DropOperation = .before
        #expect(validate(
            coordinator,
            collectionView: collectionView,
            location: NSPoint(x: 400, y: 100),
            dropOperation: &operation
        ).isEmpty)
        #expect(!coordinator.collectionView(
            collectionView,
            acceptDrop: CoordinatorDraggingInfo(),
            indexPath: IndexPath(item: 0, section: 0),
            dropOperation: .on
        ))
        var offset = NSPoint.zero
        #expect(coordinator.collectionView(
            collectionView,
            draggingImageForItemsAt: [IndexPath(item: 0, section: 0)],
            with: NSEvent(), offset: &offset
        ).size == .zero)
        #expect(events == 0)
    }

    @Test func delegateWiringSelectionAndDragAreReal() throws {
        let sut = makeSUT()
        let item = app(id: 1)
        let path = IndexPath(item: 0, section: 0)
        sut.host.itemsByPath[path] = item
        sut.dragController.handleDragStart()
        var selected: Int64?
        sut.coordinator.onItemActivated = { selected = $0.id }
        let delegate = try #require(sut.collectionView.delegate)
        #expect(delegate === sut.coordinator)
        #expect(delegate !== sut.collectionView)
        delegate.collectionView?(sut.collectionView, didSelectItemsAt: [path])
        let writer = delegate.collectionView?(
            sut.collectionView,
            pasteboardWriterForItemAt: path
        )
        var operation: NSCollectionView.DropOperation = .before
        let validation = validate(
            sut.coordinator,
            collectionView: sut.collectionView,
            location: NSPoint(x: 400, y: 100),
            dropOperation: &operation
        )
        #expect(selected == item.id)
        #expect(writer != nil)
        #expect(validation == .move)
    }

    @Test func programmaticSelectionNeverEmitsBusinessOutput() throws {
        let grid = AppGridCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 620))
        let coordinator = AppGridInteractionCoordinator(
            dragController: DragController(scheduler: MockScheduler()),
            pasteboardUUIDReader: { _ in nil }
        )
        coordinator.attach(to: grid)
        #expect(grid.delegate === coordinator)
        #expect(grid.delegate !== grid)
        let items = [app(id: 1), app(id: 2)]
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
}
#endif
