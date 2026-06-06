import Foundation
import LaunchPadProtocols

/// 布局持久化 — 保存/加载用户自定义的应用排列顺序
public enum LayoutPersistence {

    /// 保存当前布局到数据库
    public static func saveLayout(items: [PageItem], writer: ItemWriting) throws {
        for item in items {
            try writer.updateItem(item)
        }
    }

    /// 从数据库加载所有页面和子项
    public static func loadLayout(reader: ItemReading) throws -> (pages: [PageItem], itemsByPage: [Int64: [PageItem]]) {
        let pages = try reader.fetchAllItems(parentId: nil)
            .filter { $0.type == .page }
            .sorted { $0.ordering < $1.ordering }

        var itemsByPage: [Int64: [PageItem]] = [:]
        for page in pages {
            let children = try reader.fetchAllItems(parentId: page.id)
                .sorted { $0.ordering < $1.ordering }
            itemsByPage[page.id] = children
        }

        return (pages, itemsByPage)
    }
}
