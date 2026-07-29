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
    var onPageChanged: ((Int) -> Void)?
    private(set) var pagingPageWidth: CGFloat = 0
    private(set) var pagingPageCount: Int = 1
    private var hasExplicitPagingConfiguration = false

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
        _ = processScrollPhase(event.phase, deltaX: event.scrollingDeltaX, event: event)
    }

    /// 处理单个滚动阶段的逻辑（从 scrollWheel 抽出，便于单元测试，避免依赖 NSEvent.phase 的构造）。
    /// - Parameters:
    ///   - phase: 滚动阶段（changed / ended / cancelled / mayBegin / began 等）
    ///   - deltaX: 本阶段水平滚动位移
    ///   - event: 原始事件（仅边缘回弹分支转发给 super 时使用）
    /// - Returns: `true` 表示事件已转发给 `super`（边缘弹性回弹）；`false` 表示已自行处理或不需处理。
    @MainActor
    func processScrollPhase(_ phase: NSEvent.Phase, deltaX: CGFloat, event: NSEvent) -> Bool {
        // 收集滚动位移
        if phase.contains(.changed) {
            scrollAccumulator += deltaX
            isScrolling = true
            return false
        }

        // 滚动结束 → 计算目标页并动画跳转
        if phase.contains(.ended) || phase.contains(.cancelled) {
            let accumulatedOffset = scrollAccumulator
            scrollAccumulator = 0
            guard isScrolling else { return false }
            isScrolling = false
            guard pagingPageWidth > 0 else { return false }

            let currentPage = Int(round(
                contentView.bounds.origin.x / pagingPageWidth
            ))
            let target = Self.targetPage(
                for: accumulatedOffset,
                velocity: deltaX * 10, // 近似速度
                currentPage: currentPage,
                totalPages: pagingPageCount,
                pageWidth: pagingPageWidth
            )
            scrollToPage(target, animated: true)
            return false
        }

        // 边缘弹性回弹：首/末页时允许系统默认弹性行为
        if phase.contains(.mayBegin) || phase.contains(.began) {
            let atFirstPage = contentView.bounds.origin.x <= 0
            let documentWidth = documentView?.bounds.width ?? 0
            let atLastPage = contentView.bounds.origin.x >= documentWidth - bounds.width - 1

            if (atFirstPage && deltaX > 0) ||
               (atLastPage && deltaX < 0) {
                super.scrollWheel(with: event)
                return true
            }
        }

        // 其他阶段不传递（阻止系统默认滚动，由我们控制翻页）
        return false
    }

    // MARK: - 翻页动画

    func configurePaging(pageWidth: CGFloat, pageCount: Int) {
        hasExplicitPagingConfiguration = true
        updatePagingConfiguration(pageWidth: pageWidth, pageCount: pageCount)
    }

    private func updatePagingConfiguration(pageWidth: CGFloat, pageCount: Int) {
        pagingPageWidth = pageWidth.isFinite ? max(0, pageWidth) : 0
        pagingPageCount = max(1, pageCount)
    }

    @available(*, deprecated, message: "Configure paging, then call scrollToPage(_:animated:)")
    func scrollToPage(_ page: Int, pageWidth: CGFloat? = nil) {
        if !hasExplicitPagingConfiguration {
            let resolvedPageWidth = pageWidth ?? bounds.width
            let documentWidth = documentView?.bounds.width ?? 0
            let inferredPageCount = resolvedPageWidth.isFinite && resolvedPageWidth > 0
                ? max(1, Int(ceil(documentWidth / resolvedPageWidth)))
                : 1
            updatePagingConfiguration(
                pageWidth: resolvedPageWidth,
                pageCount: inferredPageCount
            )
        } else if let pageWidth {
            updatePagingConfiguration(
                pageWidth: pageWidth,
                pageCount: pagingPageCount
            )
        }
        scrollToPage(page, animated: true)
    }

    func scrollToPage(_ page: Int, animated: Bool) {
        guard pagingPageWidth > 0 else { return }
        let clamped = min(max(page, 0), pagingPageCount - 1)
        let target = NSPoint(x: CGFloat(clamped) * pagingPageWidth, y: 0)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = AnimationConstants.pageScroll.duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                contentView.animator().bounds.origin = target
            }
        } else {
            contentView.setBoundsOrigin(target)
        }
        onPageChanged?(clamped)
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
