import Testing
@testable import LaunchPad
#if canImport(AppKit)
import AppKit
#endif

@Suite("AccessibilityObservers accessibility settings monitoring")
struct AccessibilityObserversTests {

    #if canImport(AppKit)

    @Test("AccessibilityObserver callback is called on notification")
    func observer_callsCallbackOnNotification() {
        var callbackCount = 0
        let observer = AccessibilityObserver { settings in
            callbackCount += 1
        }

        // Reset count in case any background notification fired during init
        callbackCount = 0

        NotificationCenter.default.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbackCount >= 1)
        observer.stop()
    }

    @Test("AccessibilityObserver stop prevents further notifications")
    func observer_doesNotFireAfterStop() {
        var callbackCount = 0
        let observer = AccessibilityObserver { settings in
            callbackCount += 1
        }
        observer.stop()

        NotificationCenter.default.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbackCount == 0)
    }

    @Test("AccessibilityObserver stop called when already stopped -> no-op (if-let else branch)")
    func observer_stopTwice_noop() {
        var callbackCount = 0
        let observer = AccessibilityObserver { settings in
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
        var callbackCount = 0
        var observer: AccessibilityObserver? = AccessibilityObserver { settings in
            callbackCount += 1
        }
        // Deinit runs stop()
        observer = nil

        NotificationCenter.default.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(callbackCount == 0)
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
