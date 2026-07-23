import Foundation
import Testing
@testable import LaunchPad

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("AccessibilitySettings")
struct AccessibilitySettingsTests {

    @Test("注入 source 返回完整设置快照")
    func current_returnsValidSettings() {
        let settings = LaunchPad.AccessibilitySettings.current(
            source: AccessibilitySettingsSource(
                reduceMotion: { true },
                reduceTransparency: { false },
                increaseContrast: { true }
            )
        )

        #expect(settings.reduceMotion)
        #expect(!settings.reduceTransparency)
        #expect(settings.increaseContrast)
    }

    @Test("注入 source 返回 reduce motion")
    func current_reduceMotion_isBool() {
        let settings = LaunchPad.AccessibilitySettings.current(
            source: AccessibilitySettingsSource(
                reduceMotion: { true },
                reduceTransparency: { false },
                increaseContrast: { false }
            )
        )

        #expect(settings.reduceMotion)
    }

    @Test("注入 source 返回 reduce transparency")
    func current_reduceTransparency_isBool() {
        let settings = LaunchPad.AccessibilitySettings.current(
            source: AccessibilitySettingsSource(
                reduceMotion: { false },
                reduceTransparency: { true },
                increaseContrast: { false }
            )
        )

        #expect(settings.reduceTransparency)
    }

    @Test("注入 source 返回 increase contrast")
    func current_increaseContrast_isBool() {
        let settings = LaunchPad.AccessibilitySettings.current(
            source: AccessibilitySettingsSource(
                reduceMotion: { false },
                reduceTransparency: { false },
                increaseContrast: { true }
            )
        )

        #expect(settings.increaseContrast)
    }

    @Test("显式值按字段保存")
    func init_withExplicitValues() {
        let settings = AccessibilitySettings(
            reduceMotion: true,
            reduceTransparency: false,
            increaseContrast: true
        )

        #expect(settings.reduceMotion)
        #expect(!settings.reduceTransparency)
        #expect(settings.increaseContrast)
    }

    @Test("全 false 值按字段保存")
    func init_allFalse() {
        let settings = AccessibilitySettings(
            reduceMotion: false,
            reduceTransparency: false,
            increaseContrast: false
        )

        #expect(!settings.reduceMotion)
        #expect(!settings.reduceTransparency)
        #expect(!settings.increaseContrast)
    }

    @Test("全 true 值按字段保存")
    func init_allTrue() {
        let settings = AccessibilitySettings(
            reduceMotion: true,
            reduceTransparency: true,
            increaseContrast: true
        )

        #expect(settings.reduceMotion)
        #expect(settings.reduceTransparency)
        #expect(settings.increaseContrast)
    }

    @Test("reduce motion 使用 fade 或 instant")
    func animationFallback_reduceMotion_returnsFadeOrInstant() {
        let fallback = AnimationFallback.strategy(
            reduceMotion: true,
            springDamping: 0.8
        )
        #expect(fallback == .fadeOrInstant)
    }

    @Test("normal motion 使用 spring")
    func animationFallback_normalMotion_returnsSpring() {
        let fallback = AnimationFallback.strategy(
            reduceMotion: false,
            springDamping: 0.75
        )
        #expect(fallback == .spring(damping: 0.75))
    }

    @Test("reduce transparency 使用 solid color")
    func backgroundMaterial_reduceTransparency_returnsSolidColor() {
        #expect(
            BackgroundMaterial.strategy(reduceTransparency: true)
                == .solidColor
        )
    }

    @Test("normal transparency 使用 hud window")
    func backgroundMaterial_normalTransparency_returnsHudWindow() {
        #expect(
            BackgroundMaterial.strategy(reduceTransparency: false)
                == .hudWindow
        )
    }

    @Test("increase contrast 使用高对比色")
    func contrastFallback_increaseContrast_returnsHighContrast() {
        #expect(
            ContrastFallback.strategy(increaseContrast: true)
                == .highContrastColors
        )
    }

    @Test("normal contrast 使用系统色")
    func contrastFallback_normalContrast_returnsSystemColors() {
        #expect(
            ContrastFallback.strategy(increaseContrast: false)
                == .systemColors
        )
    }
}

@MainActor
@Suite("AccessibilityObserver")
struct AccessibilityObserverTests {

    @Test("初始化后接收局部通知一次")
    func init_doesNotCrash() {
        let center = NotificationCenter()
        var callbacks = 0
        let observer = AccessibilityObserver(
            notificationCenter: center,
            settingsProvider: {
                AccessibilitySettings(
                    reduceMotion: false,
                    reduceTransparency: false,
                    increaseContrast: false
                )
            }
        ) { _ in callbacks += 1 }
        defer { observer.stop() }

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbacks == 1)
    }

    @Test("重复 stop 后局部通知不再回调")
    func stop_multipleCalls_doesNotCrash() {
        let center = NotificationCenter()
        var callbacks = 0
        let observer = AccessibilityObserver(
            notificationCenter: center,
            settingsProvider: {
                AccessibilitySettings(
                    reduceMotion: false,
                    reduceTransparency: false,
                    increaseContrast: false
                )
            }
        ) { _ in callbacks += 1 }

        observer.stop()
        observer.stop()
        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbacks == 0)
    }

    @Test("析构移除局部通知 token")
    func deinit_doesNotCrash() {
        let center = NotificationCenter()
        var callbacks = 0
        var observer: AccessibilityObserver? = AccessibilityObserver(
            notificationCenter: center,
            settingsProvider: {
                AccessibilitySettings(
                    reduceMotion: false,
                    reduceTransparency: false,
                    increaseContrast: false
                )
            }
        ) { _ in callbacks += 1 }
        #expect(observer != nil)

        observer = nil
        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbacks == 0)
    }
}
#endif
