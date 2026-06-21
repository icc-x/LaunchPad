import XCTest
@testable import LaunchPad

#if canImport(AppKit)
import AppKit

/// Tests for AccessibilitySettings and AccessibilityObserver (0% → target 100%)
final class AccessibilitySettingsTests: XCTestCase {

    // MARK: - AccessibilitySettings

    func testCurrent_returnsValidSettings() {
        let settings = AccessibilitySettings.current()
        // Should not crash; returns system values
        XCTAssertNotNil(settings)
    }

    func testCurrent_reduceMotion_isBool() {
        let settings = AccessibilitySettings.current()
        // Just verify it's accessible (true or false)
        _ = settings.reduceMotion
    }

    func testCurrent_reduceTransparency_isBool() {
        let settings = AccessibilitySettings.current()
        _ = settings.reduceTransparency
    }

    func testCurrent_increaseContrast_isBool() {
        let settings = AccessibilitySettings.current()
        _ = settings.increaseContrast
    }

    func testInit_withExplicitValues() {
        let settings = AccessibilitySettings(
            reduceMotion: true,
            reduceTransparency: false,
            increaseContrast: true
        )
        XCTAssertTrue(settings.reduceMotion)
        XCTAssertFalse(settings.reduceTransparency)
        XCTAssertTrue(settings.increaseContrast)
    }

    func testInit_allFalse() {
        let settings = AccessibilitySettings(
            reduceMotion: false,
            reduceTransparency: false,
            increaseContrast: false
        )
        XCTAssertFalse(settings.reduceMotion)
        XCTAssertFalse(settings.reduceTransparency)
        XCTAssertFalse(settings.increaseContrast)
    }

    func testInit_allTrue() {
        let settings = AccessibilitySettings(
            reduceMotion: true,
            reduceTransparency: true,
            increaseContrast: true
        )
        XCTAssertTrue(settings.reduceMotion)
        XCTAssertTrue(settings.reduceTransparency)
        XCTAssertTrue(settings.increaseContrast)
    }

    // MARK: - AnimationFallback

    func testAnimationFallback_reduceMotion_returnsFadeOrInstant() {
        let fallback = AnimationFallback.strategy(reduceMotion: true, springDamping: 0.8)
        XCTAssertEqual(fallback, .fadeOrInstant)
    }

    func testAnimationFallback_normalMotion_returnsSpring() {
        let fallback = AnimationFallback.strategy(reduceMotion: false, springDamping: 0.75)
        XCTAssertEqual(fallback, .spring(damping: 0.75))
    }

    // MARK: - BackgroundMaterial

    func testBackgroundMaterial_reduceTransparency_returnsSolidColor() {
        let material = BackgroundMaterial.strategy(reduceTransparency: true)
        XCTAssertEqual(material, .solidColor)
    }

    func testBackgroundMaterial_normalTransparency_returnsHudWindow() {
        let material = BackgroundMaterial.strategy(reduceTransparency: false)
        XCTAssertEqual(material, .hudWindow)
    }

    // MARK: - ContrastFallback

    func testContrastFallback_increaseContrast_returnsHighContrast() {
        let fallback = ContrastFallback.strategy(increaseContrast: true)
        XCTAssertEqual(fallback, .highContrastColors)
    }

    func testContrastFallback_normalContrast_returnsSystemColors() {
        let fallback = ContrastFallback.strategy(increaseContrast: false)
        XCTAssertEqual(fallback, .systemColors)
    }
}

/// Tests for AccessibilityObserver (0% → target 80%+)
final class AccessibilityObserverTests: XCTestCase {

    func testInit_doesNotCrash() {
        let observer = AccessibilityObserver { _ in }
        XCTAssertNotNil(observer)
        observer.stop()
    }

    func testStop_multipleCalls_doesNotCrash() {
        let observer = AccessibilityObserver { _ in }
        observer.stop()
        observer.stop() // Second call should be safe
    }

    func testDeinit_doesNotCrash() {
        autoreleasepool {
            let observer = AccessibilityObserver { _ in }
            // observer goes out of scope, deinit should call stop()
        }
    }
}
#endif
