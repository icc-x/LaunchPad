import AppKit
import LaunchPadProtocols

/// 网格交互宿主向协调器暴露的最小能力集合。
@MainActor
protocol AppGridInteractionHosting: AnyObject {
    var collectionViewForDelegateInstallation: NSCollectionView { get }
    func pageItem(at indexPath: IndexPath) -> PageItem?
    func pageItem(uuid: String) -> PageItem?
    func resolvedIndexPath(at point: NSPoint) -> IndexPath?
    func dragImage(at indexPath: IndexPath) -> NSImage?
    func moveSnapshotItem(_ item: PageItem, before target: PageItem)
}

/// 外部拥有主网格的选择及拖放 delegate 交互。
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
