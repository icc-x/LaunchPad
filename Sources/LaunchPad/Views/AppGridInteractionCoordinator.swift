import AppKit
import LaunchPadProtocols

public enum GridDropDestination: Sendable, Equatable {
    case placement(ItemPlacement)
    case onItem(itemID: Int64, itemType: ItemType)
}

/// Read-only grid surface used to resolve native drag source and destination state.
@MainActor
protocol AppGridInteractionHosting: AnyObject {
    var collectionViewForDelegateInstallation: NSCollectionView { get }
    var interactionVisibleRect: NSRect { get }
    var visualPageCount: Int { get }
    var currentVisualPageIndex: Int { get }

    func section(at index: Int) -> Section?
    func pageItem(at indexPath: IndexPath) -> PageItem?
    func pageItem(id: Int64) -> PageItem?
    /// Returns the item's snapshot section, which is its visual page index.
    func visualIndex(of item: PageItem) -> Int?
    func indexPath(forItemID itemID: Int64) -> IndexPath?
    func resolvedIndexPath(at point: NSPoint) -> IndexPath?
    func layoutFrame(at indexPath: IndexPath) -> NSRect?
    func emptyPlacement(inVisualPage pageIndex: Int) -> ItemPlacement?
    func dragImage(at indexPath: IndexPath) -> NSImage?
    func setFolderCreationPreview(targetItemID: Int64?)
}

@MainActor
final class AppGridInteractionCoordinator: NSObject, NSCollectionViewDelegate {
    private(set) weak var host: (any AppGridInteractionHosting)?
    private weak var collectionView: NSCollectionView?
    let dragController: DragController

    var isDragEnabled = true {
        didSet {
            if !isDragEnabled { dragController.cancelDrag() }
        }
    }
    var onSelectionChanged: ((PageItem) -> Void)?
    var onItemActivated: ((PageItem) -> Void)?
    var onDropRequested: ((DragSession, GridDropDestination) -> Bool)?
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
        dragController.onFolderCreationPreviewChanged = { [weak self] targetID in
            self?.host?.setFolderCreationPreview(targetItemID: targetID)
        }
    }

    func detach() {
        host?.setFolderCreationPreview(targetItemID: nil)
        dragController.onFolderCreationPreviewChanged = nil
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

    func canHoverEdge(_ direction: DragPageDirection) -> Bool {
        guard let host else { return false }
        switch direction {
        case .backward:
            return host.currentVisualPageIndex > 0
        case .forward:
            return host.currentVisualPageIndex + 1 < host.visualPageCount
        }
    }

    func resolveGridDestination(at location: NSPoint) -> GridDropDestination? {
        guard let host else { return nil }
        guard let indexPath = host.resolvedIndexPath(at: location) else {
            return host.emptyPlacement(inVisualPage: host.currentVisualPageIndex).map {
                .placement($0)
            }
        }
        guard let item = host.pageItem(at: indexPath),
              let frame = host.layoutFrame(at: indexPath) else { return nil }
        let onFrame = frame.insetBy(dx: frame.width * 0.25, dy: frame.height * 0.20)
        if onFrame.contains(location) {
            return .onItem(itemID: item.id, itemType: item.type)
        }
        return .placement(
            location.x < frame.midX
                ? .beforeItem(itemID: item.id)
                : .afterItem(itemID: item.id)
        )
    }

    func topLevelPlacement(atLocalPoint location: NSPoint) -> ItemPlacement? {
        switch resolveGridDestination(at: location) {
        case .placement(let placement):
            return placement
        case .onItem(let itemID, _):
            guard let indexPath = host?.indexPath(forItemID: itemID),
                  let frame = host?.layoutFrame(at: indexPath) else { return nil }
            return location.x < frame.midX
                ? .beforeItem(itemID: itemID)
                : .afterItem(itemID: itemID)
        case nil:
            return nil
        }
    }

    func allows(session: DragSession, destination: GridDropDestination) -> Bool {
        switch destination {
        case .placement(let placement):
            return placement.anchorItemID != session.itemID
        case .onItem(let targetID, .app), .onItem(let targetID, .group):
            return session.itemType == .app && targetID != session.itemID
        case .onItem:
            return false
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        let localPoint = collectionView.convert(draggingInfo.draggingLocation, from: nil)
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
            dragController.updateDragHover(.item(itemID: itemID, itemType: itemType))
        }
        dropOperation.pointee = .on
        return .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        let localPoint = collectionView.convert(draggingInfo.draggingLocation, from: nil)
        guard let session = extractActiveSession(from: draggingInfo),
              let destination = resolveGridDestination(at: localPoint),
              allows(session: session, destination: destination) else {
            return false
        }
        return performDrop(session: session, destination: destination)
    }

    func performDrop(session: DragSession, destination: GridDropDestination) -> Bool {
        guard isDragEnabled else {
            dragController.cancelDrag()
            return false
        }
        return onDropRequested?(session, destination) ?? false
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        dragController.finishDrag()
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
