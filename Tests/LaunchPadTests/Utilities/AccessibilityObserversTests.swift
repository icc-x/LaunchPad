import Testing
@testable import LaunchPad
#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Suite("AccessibilityObservers accessibility settings monitoring")
struct AccessibilityObserversTests {

    #if canImport(AppKit)

    @Test("局部通知源每次使用注入 settings provider")
    func observer_callsCallbackOnNotification() {
        let center = NotificationCenter()
        let expected = AccessibilitySettings(
            reduceMotion: true,
            reduceTransparency: true,
            increaseContrast: false
        )
        var received: [LaunchPad.AccessibilitySettings] = []
        let observer = AccessibilityObserver(
            notificationCenter: center,
            settingsProvider: { expected }
        ) { settings in
            received.append(settings)
        }
        defer { observer.stop() }

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(received.count == 2)
        #expect(received.allSatisfy {
            $0.reduceMotion == expected.reduceMotion
                && $0.reduceTransparency == expected.reduceTransparency
                && $0.increaseContrast == expected.increaseContrast
        })
    }

    @Test("AccessibilityObserver stop prevents further notifications")
    func observer_doesNotFireAfterStop() {
        let center = NotificationCenter()
        var callbackCount = 0
        let observer = AccessibilityObserver(
            notificationCenter: center,
            settingsProvider: {
                AccessibilitySettings(
                    reduceMotion: false,
                    reduceTransparency: false,
                    increaseContrast: false
                )
            }
        ) { _ in
            callbackCount += 1
        }
        observer.stop()

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbackCount == 0)
    }

    @Test("AccessibilityObserver stop called when already stopped -> no-op (if-let else branch)")
    func observer_stopTwice_noop() {
        let center = NotificationCenter()
        var callbackCount = 0
        let observer = AccessibilityObserver(
            notificationCenter: center,
            settingsProvider: {
                AccessibilitySettings(
                    reduceMotion: false,
                    reduceTransparency: false,
                    increaseContrast: false
                )
            }
        ) { _ in
            callbackCount += 1
        }
        observer.stop()
        // Second stop() when observer is already nil
        observer.stop()

        #expect(callbackCount == 0)
    }

    #endif

    @Test("AccessibilityObserver deinit cleans up observer")
    func observer_deinit_removesObserver() {
        let center = NotificationCenter()
        var callbackCount = 0
        var observer: AccessibilityObserver? = AccessibilityObserver(
            notificationCenter: center,
            settingsProvider: {
                AccessibilitySettings(
                    reduceMotion: false,
                    reduceTransparency: false,
                    increaseContrast: false
                )
            }
        ) { _ in
            callbackCount += 1
        }
        #expect(observer != nil)
        // Deinit runs stop()
        observer = nil

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbackCount == 0)
    }

    @Test("AccessibilitySettingsSource 原样映射全部 Bool 组合")
    func settingsSourceMapsAllBooleanCombinations() {
        for reduceMotion in [false, true] {
            for reduceTransparency in [false, true] {
                for increaseContrast in [false, true] {
                    let settings = LaunchPad.AccessibilitySettings.current(
                        source: AccessibilitySettingsSource(
                            reduceMotion: { reduceMotion },
                            reduceTransparency: { reduceTransparency },
                            increaseContrast: { increaseContrast }
                        )
                    )

                    #expect(settings.reduceMotion == reduceMotion)
                    #expect(settings.reduceTransparency == reduceTransparency)
                    #expect(settings.increaseContrast == increaseContrast)
                }
            }
        }
    }

    @Test("AnimationFallback returns different strategy based on Reduce Motion")
    func animationFallback_reduceMotion() {
        let fallbackOn = AnimationFallback.strategy(reduceMotion: true, springDamping: 0.8)
        #expect(fallbackOn == .fadeOrInstant)

        let fallbackOff = AnimationFallback.strategy(reduceMotion: false, springDamping: 0.8)
        #expect(fallbackOff == .spring(damping: 0.8))
    }

    @Test("BackgroundMaterial returns different material based on Reduce Transparency")
    func backgroundMaterial_reduceTransparency() {
        let mat1 = BackgroundMaterial.strategy(reduceTransparency: true)
        #expect(mat1 == .solidColor)

        let mat2 = BackgroundMaterial.strategy(reduceTransparency: false)
        #expect(mat2 == .hudWindow)
    }

    @Test("ContrastFallback returns different strategy based on Increase Contrast")
    func contrastFallback_increaseContrast() {
        let highContrast = ContrastFallback.strategy(increaseContrast: true)
        #expect(highContrast == .highContrastColors)

        let normal = ContrastFallback.strategy(increaseContrast: false)
        #expect(normal == .systemColors)
    }
}
