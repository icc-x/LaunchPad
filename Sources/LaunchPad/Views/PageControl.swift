import Foundation
#if canImport(AppKit)
import AppKit

/// 页码指示点 — 底部居中显示的圆点指示器
public class PageControlView: NSView {

    /// 点击某个圆点时的回调
    public var onDotSelected: ((Int) -> Void)?

    private let viewModel: PageControlViewModel
    private let dotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 8

    public init(viewModel: PageControlViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
    }

    public required init?(coder: NSCoder) {
        self.viewModel = PageControlViewModel()
        super.init(coder: coder)
    }

    // MARK: - Layout

    public func update() {
        // totalPages 变化后 intrinsicContentSize 随之变化，必须通知布局系统重算，
        // 否则无宽度约束时 Auto Layout 缓存初始宽度 0，圆点看得到但点击区域为零。
        invalidateIntrinsicContentSize()
        needsDisplay = true
        isHidden = !viewModel.isVisible
    }

    override public var intrinsicContentSize: NSSize {
        let count = max(viewModel.totalPages, 0)
        let width = CGFloat(count) * dotSize + CGFloat(max(count - 1, 0)) * dotSpacing
        return NSSize(width: width, height: dotSize)
    }

    // MARK: - Drawing

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalPages = viewModel.totalPages
        guard totalPages > 0 else { return }

        let totalWidth = CGFloat(totalPages) * dotSize + CGFloat(totalPages - 1) * dotSpacing
        var x = (bounds.width - totalWidth) / 2
        let y = (bounds.height - dotSize) / 2

        for i in 0..<totalPages {
            let rect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
            let path = NSBezierPath(ovalIn: rect)

            if viewModel.isDotActive(at: i) {
                NSColor.white.setFill()
            } else {
                NSColor.white.withAlphaComponent(0.4).setFill()
            }
            path.fill()

            x += dotSize + dotSpacing
        }
    }

    // MARK: - Mouse

    override public func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let totalPages = viewModel.totalPages
        guard totalPages > 0 else { return }

        let totalWidth = CGFloat(totalPages) * dotSize + CGFloat(totalPages - 1) * dotSpacing
        let startX = (bounds.width - totalWidth) / 2

        let relativeX = location.x - startX
        guard relativeX >= 0 else { return }

        let dotIndex = Int(relativeX / (dotSize + dotSpacing))
        guard dotIndex >= 0 && dotIndex < totalPages else { return }

        viewModel.selectDot(at: dotIndex)
        onDotSelected?(dotIndex)
        update()
    }

    // MARK: - Accessibility

    override public func accessibilityRole() -> NSAccessibility.Role? {
        .slider
    }

    override public func accessibilityLabel() -> String? {
        "Page indicator"
    }

    override public func accessibilityValue() -> Any? {
        viewModel.currentPage + 1
    }

    override public func accessibilityMinValue() -> Any? {
        viewModel.totalPages == 0 ? 0 : 1
    }

    override public func accessibilityMaxValue() -> Any? {
        viewModel.totalPages
    }

    override public func accessibilityValueDescription() -> String? {
        guard viewModel.totalPages > 0 else { return "No pages" }
        return "Page \(viewModel.currentPage + 1) of \(viewModel.totalPages)"
    }

    override public func accessibilityPerformIncrement() -> Bool {
        adjustPage(by: 1)
    }

    override public func accessibilityPerformDecrement() -> Bool {
        adjustPage(by: -1)
    }

    /// 复用鼠标选择的调用顺序：selectDot → onDotSelected → update()。
    /// 零页或目标页超出边界时不产生任何动作并返回 false。
    private func adjustPage(by delta: Int) -> Bool {
        guard viewModel.totalPages > 0 else { return false }
        let target = viewModel.currentPage + delta
        guard target >= 0, target < viewModel.totalPages, target != viewModel.currentPage else {
            return false
        }
        viewModel.selectDot(at: target)
        onDotSelected?(target)
        update()
        return true
    }
}
#endif
