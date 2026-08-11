import Foundation

/// 具名平台键码（Carbon virtual key values）。
/// 生产代码统一使用这些具名常量，禁止散落无说明的键码字面量。
enum KeyboardKeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    /// 将平台键码映射为导航键；未知键码返回 nil。
    static func navigationKey(for keyCode: UInt16) -> KeyboardNavigator.Key? {
        switch keyCode {
        case KeyboardKeyCode.escape:
            return .escape
        case KeyboardKeyCode.returnKey:
            return .enter
        case KeyboardKeyCode.upArrow:
            return .upArrow
        case KeyboardKeyCode.downArrow:
            return .downArrow
        case KeyboardKeyCode.leftArrow:
            return .leftArrow
        case KeyboardKeyCode.rightArrow:
            return .rightArrow
        case KeyboardKeyCode.tab:
            return .tab
        case KeyboardKeyCode.delete:
            return .delete
        default:
            return nil
        }
    }
}
