import Foundation
import LaunchPadProtocols

/// 布局持久化 — 保存/加载用户自定义的应用排列顺序
public enum LayoutPersistence {

    /// 保存当前布局到数据库
    /// 注意: ItemWriting 协议暂无 batch/事务支持，中途失败会留下部分保存状态。
    /// 如果 StorageManager 支持事务，建议在此处使用。
    public static func saveLayout(items: [PageItem], writer: ItemWriting) throws {
        for item in items {
            try writer.updateItem(item)
        }
    }

    /// 从数据库加载所有页面和子项
    /// 当前实现对每个页面执行一次 fetchAllItems(parentId:)，存在 N+1 查询。
    /// 若 ItemReading 增加 `fetchAllItems(parentIds:)` 批量方法，可优化为单次查询。
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
