#if canImport(AppKit)
import AppKit
import CoreGraphics

/// 自定义分页滚动容器
/// 重写 scrollWheel 实现双指横滑翻页 + 弹性回弹
class PageScrollView: NSScrollView {

    // MARK: - Constants

    /// 速度阈值 (pt/s)，超过则直接翻页
    nonisolated static let velocityThreshold: CGFloat = 300.0

    // MARK: - 状态追踪

    private var scrollAccumulator: CGFloat = 0
    private var isScrolling = false

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPaging()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPaging()
    }

    private func setupPaging() {
        horizontalScrollElasticity = .allowed
        hasHorizontalScroller = false
        drawsBackground = false
    }

    // MARK: - 核心分页逻辑

    override func scrollWheel(with event: NSEvent) {
        // 收集滚动位移
        if event.phase.contains(.changed) {
            scrollAccumulator += event.scrollingDeltaX
            isScrolling = true
        }

        // 滚动结束 → 计算目标页并动画跳转
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard isScrolling else { return }
            isScrolling = false

            let pageWidth = bounds.width
            guard pageWidth > 0 else { return }

            let currentOffset = contentView.bounds.origin.x
            let currentPage = Int(round(currentOffset / pageWidth))
            let totalPages = max(1, Int(documentView!.bounds.width / pageWidth))

            let target = Self.targetPage(
                for: scrollAccumulator,
                velocity: event.scrollingDeltaX * 10, // 近似速度
                currentPage: currentPage,
                totalPages: totalPages,
                pageWidth: pageWidth
            )

            scrollToPage(target, pageWidth: pageWidth)
            scrollAccumulator = 0
            return
        }

        // 边缘弹性回弹：首/末页时允许系统默认弹性行为
        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            let atFirstPage = contentView.bounds.origin.x <= 0
            let documentWidth = documentView?.bounds.width ?? 0
            let atLastPage = contentView.bounds.origin.x >= documentWidth - bounds.width - 1

            if (atFirstPage && event.scrollingDeltaX > 0) ||
               (atLastPage && event.scrollingDeltaX < 0) {
                super.scrollWheel(with: event)
                return
            }
        }

        // 其他阶段不传递（阻止系统默认滚动，由我们控制翻页）
    }

    // MARK: - 翻页动画

    /// 平滑动画滚动到指定页面
    func scrollToPage(_ page: Int, pageWidth: CGFloat? = nil) {
        let pw = pageWidth ?? bounds.width
        guard pw > 0 else { return }
        let targetX = CGFloat(page) * pw

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AnimationConstants.pageScroll.duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentView.animator().bounds.origin.x = targetX
        }
    }

    // MARK: - 纯函数（保持不变）

    /// 计算目标页码（纯函数）
    nonisolated public static func targetPage(
        for offset: CGFloat,
        velocity: CGFloat,
        currentPage: Int,
        totalPages: Int,
        pageWidth: CGFloat
    ) -> Int {
        guard totalPages > 1 else { return 0 }

        let halfPage = pageWidth / 2.0

        // 高速滚动：根据方向翻页
        if abs(velocity) >= velocityThreshold {
            if velocity > 0 {
                return clampPage(currentPage + 1, totalPages: totalPages)
            } else {
                return clampPage(currentPage - 1, totalPages: totalPages)
            }
        }

        // 低速：根据位移判断
        if abs(offset) > halfPage {
            if offset > 0 {
                return clampPage(currentPage + 1, totalPages: totalPages)
            } else {
                return clampPage(currentPage - 1, totalPages: totalPages)
            }
        }

        return currentPage
    }

    private nonisolated static func clampPage(_ page: Int, totalPages: Int) -> Int {
        return max(0, min(page, totalPages - 1))
    }
}

// MARK: - PageControl state management

/// PageControl view model, manages page indicator dot states
public final class PageControlViewModel {

    // MARK: - State

    /// Current page number (0-based), clamped to valid range
    public var currentPage: Int {
        get { _currentPage }
        set {
            let clamped = max(0, min(newValue, max(0, totalPages - 1)))
            _currentPage = clamped
        }
    }
    private var _currentPage: Int = 0

    /// Total number of pages
    public private(set) var totalPages: Int = 0

    /// Whether search mode is active
    public var isSearchActive: Bool = false

    // MARK: - Computed properties

    /// Dot count (equals total pages)
    public var dotCount: Int { totalPages }

    /// Whether to show page indicator
    public var isVisible: Bool {
        !isSearchActive && totalPages > 1
    }

    public init() {}

    // MARK: - Configuration

    /// Configure total pages
    public func configure(totalPages: Int) {
        self.totalPages = max(0, totalPages)
        if totalPages == 0 || currentPage >= totalPages {
            currentPage = 0
        }
    }

    // MARK: - Dot queries

    /// Whether the dot at the given index is the current page (active state)
    public func isDotActive(at index: Int) -> Bool {
        guard index >= 0, index < totalPages else { return false }
        return index == currentPage
    }

    // MARK: - Interaction

    /// Select a dot to jump to the corresponding page
    public func selectDot(at index: Int) {
        guard index >= 0, index < totalPages else { return }
        currentPage = index
    }
}
#endif
