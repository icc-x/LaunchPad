import Foundation

/// 页面项元数据组合校验失败。
public enum ValidationError: Error, Equatable, Sendable {
    case invalidMetadata(ItemType)
}

/// 页面中的统一项目容器
/// 每个 item 对应数据库 items 表的一行，通过 type 区分 page/app/group。
/// 合法状态只有三类，由类型化工厂与解码验证器共同保证：
/// - page：`type == .page`，`app == nil`，`group == nil`；
/// - app：`type == .app`，`app != nil`，`group == nil`；
/// - group：`type == .group`，`app == nil`，`group != nil`。
public struct PageItem: Hashable, Identifiable, Codable, Sendable {
    public let id: Int64
    public let uuid: String
    public let type: ItemType
    public let ordering: Int
    public let parentId: Int64?
    public let app: AppInfo?
    public let group: GroupInfo?

    // MARK: - Typed factories

    public static func page(
        id: Int64,
        uuid: String,
        ordering: Int,
        parentId: Int64? = nil
    ) -> PageItem {
        PageItem(
            storedID: id, uuid: uuid, type: .page, ordering: ordering,
            parentID: parentId, app: nil, group: nil
        )
    }

    public static func app(
        id: Int64,
        uuid: String,
        ordering: Int,
        parentId: Int64?,
        app: AppInfo
    ) -> PageItem {
        PageItem(
            storedID: id, uuid: uuid, type: .app, ordering: ordering,
            parentID: parentId, app: app, group: nil
        )
    }

    public static func group(
        id: Int64,
        uuid: String,
        ordering: Int,
        parentId: Int64?,
        group: GroupInfo
    ) -> PageItem {
        PageItem(
            storedID: id, uuid: uuid, type: .group, ordering: ordering,
            parentID: parentId, app: nil, group: group
        )
    }

    // MARK: - Validation

    /// 校验 type/app/group 组合是否为唯一合法状态；Codable 解码与 SQLite 行解码复用此验证器。
    internal static func validate(
        type: ItemType, app: AppInfo?, group: GroupInfo?
    ) throws {
        switch (type, app, group) {
        case (.page, nil, nil),
             (.app, .some, nil),
             (.group, nil, .some):
            return
        default:
            throw ValidationError.invalidMetadata(type)
        }
    }

    // MARK: - Initializers

    /// 内部 throwing 初始化器：生产代码通过类型化工厂构造合法状态，
    /// 解码路径在调用前显式校验，本入口只负责最终防御。
    init(
        id: Int64,
        uuid: String,
        type: ItemType,
        ordering: Int,
        parentId: Int64?,
        app: AppInfo?,
        group: GroupInfo?
    ) throws {
        try Self.validate(type: type, app: app, group: group)
        self.init(
            storedID: id, uuid: uuid, type: type, ordering: ordering,
            parentID: parentId, app: app, group: group
        )
    }

    /// 存储初始化器：不校验，仅允许本类型内部使用（工厂与验证后的解码路径）。
    private init(
        storedID: Int64,
        uuid: String,
        type: ItemType,
        ordering: Int,
        parentID: Int64?,
        app: AppInfo?,
        group: GroupInfo?
    ) {
        self.id = storedID
        self.uuid = uuid
        self.type = type
        self.ordering = ordering
        self.parentId = parentID
        self.app = app
        self.group = group
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, uuid, type, ordering, parentId, app, group
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int64.self, forKey: .id)
        let uuid = try container.decode(String.self, forKey: .uuid)
        let type = try container.decode(ItemType.self, forKey: .type)
        let ordering = try container.decode(Int.self, forKey: .ordering)
        let parentId = try container.decodeIfPresent(Int64.self, forKey: .parentId)
        let app = try container.decodeIfPresent(AppInfo.self, forKey: .app)
        let group = try container.decodeIfPresent(GroupInfo.self, forKey: .group)
        try Self.validate(type: type, app: app, group: group)
        self.init(
            storedID: id, uuid: uuid, type: type, ordering: ordering,
            parentID: parentId, app: app, group: group
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(type, forKey: .type)
        try container.encode(ordering, forKey: .ordering)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(group, forKey: .group)
    }
}
