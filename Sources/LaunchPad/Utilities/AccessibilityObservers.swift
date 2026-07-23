import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct AccessibilitySettingsSource: Sendable {
    let reduceMotion: @Sendable () -> Bool
    let reduceTransparency: @Sendable () -> Bool
    let increaseContrast: @Sendable () -> Bool

    #if canImport(AppKit)
    static let system = AccessibilitySettingsSource(
        reduceMotion: {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        reduceTransparency: {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        },
        increaseContrast: {
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    )
    #else
    static let system = AccessibilitySettingsSource(
        reduceMotion: { false },
        reduceTransparency: { false },
        increaseContrast: { false }
    )
    #endif
}

/// Accessibility settings snapshot (current values)
public struct AccessibilitySettings: Sendable {
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    /// Read current accessibility settings from system
    public static func current() -> AccessibilitySettings {
        current(source: .system)
    }

    static func current(
        source: AccessibilitySettingsSource
    ) -> AccessibilitySettings {
        AccessibilitySettings(
            reduceMotion: source.reduceMotion(),
            reduceTransparency: source.reduceTransparency(),
            increaseContrast: source.increaseContrast()
        )
    }
}

/// Reactive accessibility settings observer
/// Monitors system accessibility settings changes via NotificationCenter
public final class AccessibilityObserver: @unchecked Sendable {

    public typealias ChangeCallback = (AccessibilitySettings) -> Void

    private let notificationCenter: NotificationCenter
    private let settingsProvider: @Sendable () -> AccessibilitySettings
    private let callback: ChangeCallback
    private var observer: NSObjectProtocol?

    public init(
        notificationCenter: NotificationCenter = .default,
        settingsProvider: @escaping @Sendable () -> AccessibilitySettings = {
            AccessibilitySettings.current()
        },
        callback: @escaping ChangeCallback
    ) {
        self.notificationCenter = notificationCenter
        self.settingsProvider = settingsProvider
        self.callback = callback
        #if canImport(AppKit)
        self.observer = notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.callback(self.settingsProvider())
        }
        #endif
    }

    deinit {
        stop()
    }

    public func stop() {
        guard let observer else { return }
        notificationCenter.removeObserver(observer)
        self.observer = nil
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
