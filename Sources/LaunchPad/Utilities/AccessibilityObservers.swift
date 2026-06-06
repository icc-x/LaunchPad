import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Accessibility settings snapshot (current values)
public struct AccessibilitySettings {
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    /// Read current accessibility settings from system
    public static func current() -> AccessibilitySettings {
        #if canImport(AppKit)
        return AccessibilitySettings(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: NSWorkspace.shared
                .accessibilityDisplayShouldReduceTransparency,
            increaseContrast: UserDefaults.standard
                .bool(forKey: "com.apple.universalaccess.highContrast")
        )
        #else
        return AccessibilitySettings(
            reduceMotion: false,
            reduceTransparency: false,
            increaseContrast: false
        )
        #endif
    }
}

/// Reactive accessibility settings observer
/// Monitors system accessibility settings changes via NotificationCenter
public final class AccessibilityObserver {

    public typealias ChangeCallback = (AccessibilitySettings) -> Void

    private let callback: ChangeCallback
    private var observer: NSObjectProtocol?

    public init(callback: @escaping ChangeCallback) {
        self.callback = callback
        #if canImport(AppKit)
        self.observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.callback(AccessibilitySettings.current())
        }
        #endif
    }

    deinit {
        stop()
    }

    public func stop() {
        #if canImport(AppKit)
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        #endif
    }
}

/// Animation fallback strategy
public enum AnimationFallback: Equatable {
    case spring(damping: CGFloat)
    case fadeOrInstant

    public static func strategy(reduceMotion: Bool, springDamping: CGFloat) -> AnimationFallback {
        if reduceMotion {
            return .fadeOrInstant
        }
        return .spring(damping: springDamping)
    }
}

/// Background material strategy
public enum BackgroundMaterial: Equatable {
    case hudWindow
    case solidColor

    public static func strategy(reduceTransparency: Bool) -> BackgroundMaterial {
        if reduceTransparency {
            return .solidColor
        }
        return .hudWindow
    }
}

/// Contrast fallback strategy (Increase Contrast support)
public enum ContrastFallback: Equatable {
    case highContrastColors
    case systemColors

    public static func strategy(increaseContrast: Bool) -> ContrastFallback {
        if increaseContrast {
            return .highContrastColors
        }
        return .systemColors
    }
}
