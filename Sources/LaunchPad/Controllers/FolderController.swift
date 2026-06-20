import Foundation
import LaunchPadProtocols

/// Folder operations controller (pure data layer, no UI)
/// Handles folder creation, dissolution, add/remove, rename operations
public final class FolderController {

    private let itemWriter: ItemWriting

    public init(itemWriter: ItemWriting) {
        self.itemWriter = itemWriter
    }

    /// Create folder: merge two items into a new group
    @discardableResult
    public func createFolder(from itemA: PageItem, and itemB: PageItem,
                              title: String = "New Folder") throws -> Int64 {
        let groupItem = PageItem(
            id: 0,  // DB auto-increment
            uuid: UUID().uuidString,
            type: .group,
            ordering: itemA.ordering,
            parentId: itemA.parentId,
            app: nil,
            group: GroupInfo(id: 0, title: title)
        )
        let folderId = try itemWriter.insertItem(groupItem)

        // Update both items' parentId to point to the new folder
        try itemWriter.updateItem(PageItem(
            id: itemA.id, uuid: itemA.uuid, type: itemA.type,
            ordering: 0, parentId: folderId, app: itemA.app, group: itemA.group
        ))
        try itemWriter.updateItem(PageItem(
            id: itemB.id, uuid: itemB.uuid, type: itemB.type,
            ordering: 1, parentId: folderId, app: itemB.app, group: itemB.group
        ))

        return folderId
    }

    /// Add item to existing folder
    public func addToFolder(item: PageItem, folderItem: PageItem) throws {
        try itemWriter.updateItem(PageItem(
            id: item.id, uuid: item.uuid, type: item.type,
            ordering: item.ordering, parentId: folderItem.id,
            app: item.app, group: item.group
        ))
    }

    /// Dissolve folder: delete group, move children back to target page
    public func dissolveFolder(folderId: Int64, movingChildrenTo targetPageId: Int64,
                                children: [PageItem]) throws {
        // First move children to target page
        for (index, child) in children.enumerated() {
            try itemWriter.updateItem(PageItem(
                id: child.id, uuid: child.uuid, type: child.type,
                ordering: index, parentId: targetPageId,
                app: child.app, group: child.group
            ))
        }
        // Delete folder (CASCADE deletes children, but we already moved them)
        try itemWriter.deleteItem(id: folderId)
    }

    /// Remove item from folder to main grid
    /// If only 1 child remains after removal, auto-dissolves the folder
    public func removeFromFolder(item: PageItem, folderId: Int64,
                                  targetPageId: Int64, targetOrdering: Int,
                                  reader: ItemReading) throws {
        try itemWriter.updateItem(PageItem(
            id: item.id, uuid: item.uuid, type: item.type,
            ordering: targetOrdering, parentId: targetPageId,
            app: item.app, group: item.group
        ))

        // 检查剩余子项数，仅 1 个时自动解散
        let remainingChildren = try reader.fetchAllItems(parentId: folderId)
            .filter { $0.type != .group } // 排除嵌套文件夹
        if remainingChildren.count == 1 {
            let lastChild = remainingChildren[0]
            // 将最后一个子项移回主网格
            try itemWriter.updateItem(PageItem(
                id: lastChild.id, uuid: lastChild.uuid, type: lastChild.type,
                ordering: targetOrdering + 1, parentId: targetPageId,
                app: lastChild.app, group: lastChild.group
            ))
            // 删除空文件夹
            try itemWriter.deleteItem(id: folderId)
        }
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
