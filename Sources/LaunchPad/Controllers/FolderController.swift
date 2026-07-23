import Foundation
import LaunchPadProtocols

/// Folder metadata controller. Layout mutations are committed atomically elsewhere.
public final class FolderController {

    private let itemWriter: ItemWriting

    public init(itemWriter: ItemWriting) {
        self.itemWriter = itemWriter
    }

    /// Rename folder
    public func renameFolder(item: PageItem, newTitle: String) throws {
        var group = item.group ?? GroupInfo(id: item.id, title: newTitle)
        group.title = newTitle
        try itemWriter.updateItem(PageItem(
            id: item.id, uuid: item.uuid, type: item.type,
            ordering: item.ordering, parentId: item.parentId,
            app: item.app, group: group
        ))
    }
}
