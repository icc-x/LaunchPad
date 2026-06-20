import Foundation
#if canImport(AppKit)
import AppKit

/// 文件夹预览图生成器
/// 取前 9 个子应用图标，缩小到 40%，按 3×3 排列合成
public enum FolderThumbnailGenerator {

    private static let gridSize = 3
    private static let thumbnailScale: CGFloat = 0.4
    private static let spacing: CGFloat = 2

    /// 生成文件夹预览图
    /// - Parameter childIcons: 子应用图标列表（最多取前 9 个）
    /// - Returns: 合成的 3×3 缩略图
    public static func generate(childIcons: [NSImage]) -> NSImage {
        let icons = Array(childIcons.prefix(gridSize * gridSize))
        guard !icons.isEmpty else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        // 计算单个缩略图尺寸（取第一个图标的 40%）
        let sampleSize = icons.first?.size ?? NSSize(width: 128, height: 128)
        let thumbSize = NSSize(
            width: sampleSize.width * thumbnailScale,
            height: sampleSize.height * thumbnailScale
        )

        // 计算总尺寸
        let totalWidth = CGFloat(gridSize) * thumbSize.width + CGFloat(gridSize - 1) * spacing
        let totalHeight = CGFloat(gridSize) * thumbSize.height + CGFloat(gridSize - 1) * spacing
        let totalSize = NSSize(width: totalWidth, height: totalHeight)

        let composited = NSImage(size: totalSize)
        composited.lockFocus()

        // 从左上角开始，逐行绘制
        for (index, icon) in icons.enumerated() {
            let row = index / gridSize
            let col = index % gridSize
            let x = CGFloat(col) * (thumbSize.width + spacing)
            let y = totalHeight - CGFloat(row + 1) * (thumbSize.height + spacing) - CGFloat(row) * spacing
            let rect = NSRect(origin: NSPoint(x: x, y: y), size: thumbSize)

            NSGraphicsContext.current?.imageInterpolation = .high
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        composited.unlockFocus()
        return composited
    }
}
#endif
