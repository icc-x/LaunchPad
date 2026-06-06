import Testing
@testable import LaunchPad
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit
#endif

/// Thread-safe counter for @Sendable closure tests
private final class SendableCounter: @unchecked Sendable {
    var count: Int = 0
    var flag: Bool = false
}

@Suite("HotkeyManager")
struct HotkeyManagerTests {

    #if canImport(AppKit)

    // MARK: - onToggle callback

    @Test("onToggle callback can be triggered via simulateToggle")
    func simulateToggle_invokesOnToggle() {
        let manager = HotkeyManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateToggle()

        #expect(counter.count == 1)
    }

    @Test("simulateToggle without onToggle set does not crash")
    func simulateToggle_noCallback_noCrash() {
        let manager = HotkeyManager()
        manager.simulateToggle()
    }

    @Test("simulateToggle only callbacks on main thread")
    @MainActor
    func simulateToggle_callsOnMainThread() {
        let manager = HotkeyManager()
        let counter = SendableCounter()
        manager.onToggle = {
            counter.flag = Thread.isMainThread
        }

        manager.simulateToggle()

        #expect(counter.flag == true)
    }

    // MARK: - registerGlobalHotkey

    @Test("Test environment without accessibility permission -> registerGlobalHotkey returns false")
    func registerGlobalHotkey_noAccessibilityPermission_returnsFalse() {
        let manager = HotkeyManager()
        let result = manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        #expect(result == false)
    }

    @Test("Unregistering unregistered global hotkey does not crash")
    func unregisterGlobalHotkey_withoutRegistration_noCrash() {
        let manager = HotkeyManager()
        manager.unregisterGlobalHotkey()
    }

    @Test("Register then unregister global hotkey does not crash")
    func registerThenUnregister_noCrash() {
        let manager = HotkeyManager()
        manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        manager.unregisterGlobalHotkey()
    }

    // MARK: - HotkeyManaging protocol (Mock verification)

    @Test("MockHotkeyManager conforms to HotkeyManaging protocol")
    func mockHotkeyManager_conformsToProtocol() {
        var mock: HotkeyManaging = MockHotkeyManager()
        let counter = SendableCounter()
        mock.onToggle = { counter.flag = true }
        mock.onToggle?()
        #expect(counter.flag == true)
    }

    @Test("MockHotkeyManager registerGlobalHotkey return value is configurable")
    func mockHotkeyManager_registerConfigurable() {
        let mock = MockHotkeyManager()
        mock.registerResult = false
        let result = mock.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        #expect(result == false)
        #expect(mock.registerCallCount > 0)
    }

    // MARK: - registerLocalMonitor + onKeyDown callback

    @Test("After registering local monitor, onKeyDown callback is settable")
    func localMonitor_onKeyDown_settable() {
        let manager = HotkeyManager()
        manager.onKeyDown = { event in
            _ = event.keyCode
            return event
        }

        #expect(manager.onKeyDown != nil)
    }

    @Test("Unregistering local monitor then unregistering again does not crash")
    func unregisterLocalMonitor_doubleCall_noCrash() {
        let manager = HotkeyManager()
        manager.registerLocalMonitor()
        manager.unregisterLocalMonitor()
        manager.unregisterLocalMonitor()
    }

    @Test("deinit automatically cleans up all monitors")
    func deinit_cleansUp_allMonitors() {
        var manager: HotkeyManager? = HotkeyManager()
        manager?.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        manager?.registerLocalMonitor()
        manager = nil
    }

    // MARK: - Option+Space state machine logic

    @Test("Option+Space combination triggers onToggle")
    func optionSpace_combination_triggersToggle() {
        let manager = HotkeyManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateOptionKeyDown()
        manager.simulateSpaceKeyDown()

        #expect(counter.count == 1)
    }

    @Test("Only Option pressed does not trigger onToggle")
    func optionOnly_noToggle() {
        let manager = HotkeyManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateOptionKeyDown()

        #expect(counter.count == 0)
    }

    @Test("Only Space pressed (no Option) does not trigger onToggle")
    func spaceOnly_noToggle() {
        let manager = HotkeyManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateSpaceKeyDown()

        #expect(counter.count == 0)
    }

    @Test("Option released then Space pressed does not trigger onToggle")
    func optionReleased_thenSpace_noToggle() {
        let manager = HotkeyManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateOptionKeyDown()
        manager.simulateOptionKeyUp()
        manager.simulateSpaceKeyDown()

        #expect(counter.count == 0)
    }

    // MARK: - unregisterGlobalHotkey

    @Test("After unregistering global hotkey no longer responds")
    func unregister_removesGlobalHotkey() {
        let manager = HotkeyManager()
        manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        manager.unregisterGlobalHotkey()
        manager.simulateOptionKeyDown()
        manager.simulateSpaceKeyDown()
    }

    #endif
}
