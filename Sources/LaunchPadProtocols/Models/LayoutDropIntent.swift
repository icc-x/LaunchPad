import Foundation

/// Describes a stable relative position for an item in a layout.
public enum ItemPlacement: Sendable, Equatable {
    /// Places the item before the anchor item.
    case beforeItem(itemID: Int64)
    /// Places the item after the anchor item.
    case afterItem(itemID: Int64)

    /// The stable identifier of the item used as the placement anchor.
    public var anchorItemID: Int64 {
        switch self {
        case .beforeItem(let itemID), .afterItem(let itemID): itemID
        }
    }
}

/// Describes one requested layout mutation using stable item identifiers.
public enum LayoutDropIntent: Sendable, Equatable {
    /// Moves a top-level item relative to another top-level item.
    case moveTopLevel(itemID: Int64, placement: ItemPlacement)
    /// Adds an item to a folder.
    case addToFolder(itemID: Int64, folderID: Int64)
    /// Creates a folder from an item and a target item.
    case createFolder(itemID: Int64, targetItemID: Int64, title: String)
    /// Reorders an item within a folder.
    case reorderFolderItem(
        itemID: Int64,
        folderID: Int64,
        placement: ItemPlacement
    )
    /// Removes an item from a folder and places it at the top level.
    case removeFromFolder(
        itemID: Int64,
        folderID: Int64,
        placement: ItemPlacement
    )
    /// Deletes a folder.
    case deleteFolder(folderID: Int64)
}
