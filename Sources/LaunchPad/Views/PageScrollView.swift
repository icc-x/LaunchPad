#if canImport(AppKit)
import AppKit
import CoreGraphics

/// Custom paging scroll container
class PageScrollView: NSScrollView {

    // MARK: - Constants

    /// Velocity threshold (pt/s), exceed this to flip page directly
    nonisolated static let velocityThreshold: CGFloat = 300.0

    // MARK: - Pure function: calculate target page

    /// Calculate target page number based on scroll offset and velocity
    ///
    /// - Parameters:
    ///   - offset: Scroll offset (positive = scroll left / next page direction)
    ///   - velocity: Scroll velocity (pt/s)
    ///   - currentPage: Current page number (0-based)
    ///   - totalPages: Total number of pages
    ///   - pageWidth: Width of each page (pt)
    /// - Returns: Target page number (0-based, clamped to valid range)
    nonisolated public static func targetPage(
        for offset: CGFloat,
        velocity: CGFloat,
        currentPage: Int,
        totalPages: Int,
        pageWidth: CGFloat
    ) -> Int {
        // Single page: always return 0
        guard totalPages > 1 else { return 0 }

        let halfPage = pageWidth / 2.0

        // Velocity exceeds threshold: flip based on velocity direction
        if abs(velocity) >= velocityThreshold {
            if velocity > 0 {
                // Positive velocity -> next page
                return clampPage(currentPage + 1, totalPages: totalPages)
            } else {
                // Negative velocity -> previous page
                return clampPage(currentPage - 1, totalPages: totalPages)
            }
        }

        // Low velocity: decide based on offset
        if abs(offset) > halfPage {
            // Offset exceeds half page -> flip to corresponding direction
            if offset > 0 {
                return clampPage(currentPage + 1, totalPages: totalPages)
            } else {
                return clampPage(currentPage - 1, totalPages: totalPages)
            }
        }

        // Offset less than half page -> stay on current page
        return currentPage
    }

    /// Clamp page number to [0, totalPages-1]
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
