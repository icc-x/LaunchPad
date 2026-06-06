import Foundation

/// 已安装应用的元数据
public struct AppInfo: Hashable, Codable, Sendable {
    public let id: Int64
    public let title: String
    public let bundleId: String
    public let path: String
    public let storeId: String?
    public let category: String?

    public init(
        id: Int64,
        title: String,
        bundleId: String,
        path: String,
        storeId: String?,
        category: String?
    ) {
        self.id = id
        self.title = title
        self.bundleId = bundleId
        self.path = path
        self.storeId = storeId
        self.category = category
    }
}
