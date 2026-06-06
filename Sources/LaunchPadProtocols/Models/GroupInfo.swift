import Foundation

/// 文件夹信息
public struct GroupInfo: Hashable, Codable, Sendable {
    public let id: Int64
    public var title: String

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }
}
