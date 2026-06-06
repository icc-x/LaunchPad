import Foundation
import CoreGraphics

/// Centralized animation parameters table from design document section 12
enum AnimationConstants {

    // MARK: - Timing types

    enum Timing: Equatable {
        case spring(damping: CGFloat)
        case easeIn
        case easeOut
        case easeInOut
        case autoreverse
    }

    // MARK: - Reduce Motion fallback types

    enum ReduceMotionFallback: Equatable {
        /// Fade in/out with specified duration
        case fade(duration: TimeInterval)
        /// Scale pulse (for jiggle replacement)
        case scalePulse
        /// Instant switch, no animation
        case instant
    }

    // MARK: - Animation definition

    struct Animation: Equatable {
        let duration: TimeInterval
        let timing: Timing
        let reduceMotionFallback: ReduceMotionFallback
    }

    // MARK: - Window animations

    /// Window expand: 0.35s, Spring(damping: 0.75), Reduce Motion -> Fade 0.2s
    static let windowExpand = Animation(
        duration: 0.35,
        timing: .spring(damping: 0.75),
        reduceMotionFallback: .fade(duration: 0.2)
    )

    /// Window collapse: 0.25s, EaseOut, Reduce Motion -> Fade 0.2s
    static let windowCollapse = Animation(
        duration: 0.25,
        timing: .easeOut,
        reduceMotionFallback: .fade(duration: 0.2)
    )

    // MARK: - App animations

    /// App launch: 0.3s, EaseOut, Reduce Motion -> instant switch
    static let appLaunch = Animation(
        duration: 0.3,
        timing: .easeOut,
        reduceMotionFallback: .instant
    )

    // MARK: - Paging animations

    /// Page scroll: 0.35s, EaseInOut, Reduce Motion -> instant switch
    static let pageScroll = Animation(
        duration: 0.35,
        timing: .easeInOut,
        reduceMotionFallback: .instant
    )

    // MARK: - Icon animations

    /// Icon entrance: 0.3s/item, Spring(damping: 0.8), Reduce Motion -> direct display
    static let iconEntrance = Animation(
        duration: 0.3,
        timing: .spring(damping: 0.8),
        reduceMotionFallback: .instant
    )

    /// Jiggle mode: 0.13s loop, Autoreverse, Reduce Motion -> scale pulse
    static let jiggle = Animation(
        duration: 0.13,
        timing: .autoreverse,
        reduceMotionFallback: .scalePulse
    )

    // MARK: - Folder animations

    /// Folder expand: 0.25s, Spring(damping: 0.8), Reduce Motion -> Fade 0.15s
    static let folderExpand = Animation(
        duration: 0.25,
        timing: .spring(damping: 0.8),
        reduceMotionFallback: .fade(duration: 0.15)
    )

    /// Folder collapse: 0.2s, EaseOut, Reduce Motion -> Fade 0.15s
    static let folderCollapse = Animation(
        duration: 0.2,
        timing: .easeOut,
        reduceMotionFallback: .fade(duration: 0.15)
    )

    // MARK: - Edit mode animations

    /// Delete (scale fade out): 0.3s, EaseIn, Reduce Motion -> instant delete
    static let delete = Animation(
        duration: 0.3,
        timing: .easeIn,
        reduceMotionFallback: .instant
    )

    /// Drag displace: 0.25s, Spring(damping: 0.85), Reduce Motion -> instant move
    static let dragDisplace = Animation(
        duration: 0.25,
        timing: .spring(damping: 0.85),
        reduceMotionFallback: .instant
    )

    // MARK: - Jiggle parameters

    /// Minimum jiggle rotation angle (degrees)
    static let jiggleMinRotation: CGFloat = 2.0

    /// Maximum jiggle rotation angle (degrees)
    static let jiggleMaxRotation: CGFloat = 3.0

    // MARK: - Entrance delay

    /// Icon entrance delay per column (seconds)
    static let iconEntranceDelayPerColumn: TimeInterval = 0.02
}
