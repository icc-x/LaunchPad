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

    /// Loads a complete layout snapshot with one storage read.
    public static func loadLayout(
        reader: any LayoutReading
    ) throws -> PersistedLayoutSnapshot {
        try reader.persistedLayoutSnapshot()
    }
}
