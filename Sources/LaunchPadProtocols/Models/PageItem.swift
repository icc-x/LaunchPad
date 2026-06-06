import Foundation

/// 页面中的统一项目容器
/// 每个 item 对应数据库 items 表的一行，通过 type 区分 page/app/group
public struct PageItem: Hashable, Identifiable, Codable, Sendable {
    public let id: Int64
    public let uuid: String
    public let type: ItemType
    public let ordering: Int
    public let parentId: Int64?
    public var app: AppInfo?
    public var group: GroupInfo?

    public init(
        id: Int64,
        uuid: String,
        type: ItemType,
        ordering: Int,
        parentId: Int64?,
        app: AppInfo?,
        group: GroupInfo?
    ) {
        self.id = id
        self.uuid = uuid
        self.type = type
        self.ordering = ordering
        self.parentId = parentId
        self.app = app
        self.group = group
    }
}
