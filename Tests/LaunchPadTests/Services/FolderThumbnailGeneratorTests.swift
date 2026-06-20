import Foundation
import Testing
@testable import LaunchPad
#if canImport(AppKit)
import AppKit

@Suite("FolderThumbnailGenerator 预览图合成")
struct FolderThumbnailGeneratorTests {

    private func makeIcon(size: NSSize = NSSize(width: 128, height: 128)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    @Test("空图标列表返回 1x1 图片")
    func generate_emptyIcons_returnsMinimalImage() {
        let result = FolderThumbnailGenerator.generate(childIcons: [])
        #expect(result.size.width == 1)
        #expect(result.size.height == 1)
    }

    @Test("单个图标生成预览图（3×3 网格大小）")
    func generate_singleIcon_returnsCompositedImage() {
        let icon = makeIcon()
        let result = FolderThumbnailGenerator.generate(childIcons: [icon])

        // 结果是 3×3 网格大小（即使只有 1 个图标也按 3×3 布局）
        let thumbSize: CGFloat = 128 * 0.4
        let spacing: CGFloat = 2
        let expectedSize = 3 * thumbSize + 2 * spacing
        #expect(abs(result.size.width - expectedSize) < 1)
        #expect(abs(result.size.height - expectedSize) < 1)
    }

    @Test("9 个图标生成 3×3 预览图")
    func generate_nineIcons_returns3x3Grid() {
        let icons = (0..<9).map { _ in makeIcon() }
        let result = FolderThumbnailGenerator.generate(childIcons: icons)

        let thumbSize: CGFloat = 128 * 0.4
        let spacing: CGFloat = 2
        let expectedWidth = 3 * thumbSize + 2 * spacing
        let expectedHeight = 3 * thumbSize + 2 * spacing

        #expect(abs(result.size.width - expectedWidth) < 1)
        #expect(abs(result.size.height - expectedHeight) < 1)
    }

    @Test("超过 9 个图标只取前 9 个")
    func generate_moreThanNineIcons_takesFirstNine() {
        let icons = (0..<15).map { _ in makeIcon() }
        let result = FolderThumbnailGenerator.generate(childIcons: icons)

        let thumbSize: CGFloat = 128 * 0.4
        let spacing: CGFloat = 2
        let expectedWidth = 3 * thumbSize + 2 * spacing

        // 结果应与 9 个图标相同
        #expect(abs(result.size.width - expectedWidth) < 1)
    }
}
#endif
