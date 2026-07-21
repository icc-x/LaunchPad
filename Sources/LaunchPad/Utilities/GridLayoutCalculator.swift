import Foundation
import CoreGraphics

public struct GridInsets: Equatable, Sendable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat
}

public struct GridMetrics: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let itemsPerPage: Int
    public let iconSize: CGFloat
    public let itemSize: CGSize
    public let horizontalSpacing: CGFloat
    public let verticalSpacing: CGFloat
    public let sectionInsets: GridInsets
    public let pageWidth: CGFloat
}

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

    static let minimumIconSize: CGFloat = 64
    static let maximumIconSize: CGFloat = 96
    static let labelExtent: CGFloat = 40
    static let minimumHorizontalInset: CGFloat = 60
    static let minimumHorizontalSpacing: CGFloat = 20
    static let minimumVerticalInset: CGFloat = 10
    static let approvedVerticalSpacing: CGFloat = 20

    public static func calculate(viewportSize: CGSize) -> GridMetrics {
        let width = viewportSize.width.isFinite ? max(0, viewportSize.width) : 0
        let height = viewportSize.height.isFinite ? max(0, viewportSize.height) : 0
        let columns = width <= 1440 ? 7 : (width <= 1728 ? 9 : 10)
        let rows = stride(from: 5, through: 1, by: -1).first { candidate in
            let itemHeights = CGFloat(candidate) * (minimumIconSize + labelExtent)
            let gaps = CGFloat(candidate - 1) * approvedVerticalSpacing
            return height >= 2 * minimumVerticalInset + itemHeights + gaps
        } ?? 1

        let widthLimit = (width - 2 * minimumHorizontalInset
            - CGFloat(columns - 1) * minimumHorizontalSpacing) / CGFloat(columns)
        let heightLimit = (height - 2 * minimumVerticalInset
            - CGFloat(rows - 1) * approvedVerticalSpacing) / CGFloat(rows) - labelExtent
        let iconSize = min(
            maximumIconSize,
            max(minimumIconSize, min(widthLimit, heightLimit))
        )
        let itemSize = CGSize(width: iconSize, height: iconSize + labelExtent)
        let horizontalInset = min(
            minimumHorizontalInset,
            max(0, (width - CGFloat(columns) * iconSize) / 2)
        )
        let horizontalSpacing = max(
            0,
            (width - 2 * horizontalInset - CGFloat(columns) * iconSize)
                / CGFloat(max(columns - 1, 1))
        )
        let verticalInset = max(
            0,
            (height - CGFloat(rows) * itemSize.height
                - CGFloat(rows - 1) * approvedVerticalSpacing) / 2
        )

        return GridMetrics(
            columns: columns,
            rows: rows,
            itemsPerPage: columns * rows,
            iconSize: iconSize,
            itemSize: itemSize,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: approvedVerticalSpacing,
            sectionInsets: GridInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            ),
            pageWidth: width
        )
    }

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
