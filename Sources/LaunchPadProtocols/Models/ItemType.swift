import Foundation

/// 页面项类型枚举
/// 与原版 LaunchPad 数据库 type 字段对应
public enum ItemType: Int, CaseIterable, Codable, Sendable {
    case page = 1
    case app = 4
    case group = 7
}
