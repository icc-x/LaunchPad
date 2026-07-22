import Foundation
import LaunchPadProtocols

/// Identifies whether a dragged item came from the top-level grid or a folder.
public enum DragSourceKind: Sendable, Equatable {
    case topLevel
    case folderChild
}

/// Identifies the requested page-navigation direction during an edge hover.
public enum DragPageDirection: Sendable, Equatable {
    case forward
    case backward
}

/// Describes the current preview-only hover target using stable item IDs.
public enum DragHoverDestination: Sendable, Equatable {
    case edge(DragPageDirection)
    case item(itemID: Int64, itemType: ItemType)
    case empty
}

/// An immutable snapshot of one active drag and its transient preview state.
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

    /// Returns a new session with updated transient hover and preview state.
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
