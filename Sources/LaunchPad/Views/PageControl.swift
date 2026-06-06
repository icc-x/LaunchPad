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
        .group
    }

    override public func accessibilityLabel() -> String? {
        "Page indicator"
    }
}
#endif
