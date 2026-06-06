import Foundation
import CoreGraphics

/// 网格布局参数计算器（纯函数）
/// 根据屏幕宽度计算列数、行数、图标尺寸、间距等参数
public enum GridLayoutCalculator {

    /// 布局计算结果
    public struct GridParameters {
        public let columns: Int
        public let rows: Int
        public let itemsPerPage: Int
        public let iconSize: CGFloat
        public let spacing: CGFloat
        public let horizontalMargin: CGFloat
        public let topMargin: CGFloat
        public let bottomMargin: CGFloat
    }

    /// 核心常量
    private static let rows = 5
    private static let spacing: CGFloat = 20
    private static let horizontalMargin: CGFloat = 60
    private static let topMargin: CGFloat = 100
    private static let bottomMargin: CGFloat = 60
    private static let minIconSize: CGFloat = 64
    private static let maxIconSize: CGFloat = 96

    /// 根据屏幕宽度计算网格参数
    public static func calculate(screenWidth: CGFloat) -> GridParameters {
        let columns: Int
        if screenWidth <= 1440 {
            columns = 7
        } else if screenWidth <= 1728 {
            columns = 9
        } else {
            columns = 10
        }

        let availableWidth = screenWidth - 2 * horizontalMargin
        let iconSize = (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let clampedIconSize = min(max(iconSize, minIconSize), maxIconSize)

        return GridParameters(
            columns: columns,
            rows: rows,
            itemsPerPage: columns * rows,
            iconSize: clampedIconSize,
            spacing: spacing,
            horizontalMargin: horizontalMargin,
            topMargin: topMargin,
            bottomMargin: bottomMargin
        )
    }
}
