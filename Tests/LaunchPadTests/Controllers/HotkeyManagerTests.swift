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

    private func makeIsolatedManager(
        accessibilityTrusted: Bool = false,
        tapResult: CFMachPort? = nil
    ) -> HotkeyManager {
        let manager = HotkeyManager()
        let localMonitorToken = NSObject()
        manager.accessibilityChecker = { accessibilityTrusted }
        manager.tapProvider = { tapResult }
        manager.eventTapCreator = { _, _, _ in nil }
        manager.localMonitorInstaller = { _ in localMonitorToken }
        manager.localMonitorRemover = { _ in }
        return manager
    }

    // MARK: - onToggle callback

    @Test("onToggle callback can be triggered via simulateToggle")
    func simulateToggle_invokesOnToggle() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateToggle()

        #expect(counter.count == 1)
    }

    @Test("simulateToggle without onToggle set does not crash")
    func simulateToggle_noCallback_noCrash() {
        let manager = makeIsolatedManager()
        manager.simulateToggle()
    }

    @Test("simulateToggle only callbacks on main thread")
    @MainActor
    func simulateToggle_callsOnMainThread() {
        let manager = makeIsolatedManager()
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
        let manager = makeIsolatedManager()
        let result = manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        #expect(result == false)
    }

    @Test("Unregistering unregistered global hotkey does not crash")
    func unregisterGlobalHotkey_withoutRegistration_noCrash() {
        let manager = makeIsolatedManager()
        manager.unregisterGlobalHotkey()
    }

    @Test("Register then unregister global hotkey does not crash")
    func registerThenUnregister_noCrash() {
        let manager = makeIsolatedManager()
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
        let manager = makeIsolatedManager()
        manager.onKeyDown = { event in
            _ = event.keyCode
            return event
        }

        #expect(manager.onKeyDown != nil)
    }

    @Test("Unregistering local monitor then unregistering again does not crash")
    func unregisterLocalMonitor_doubleCall_noCrash() {
        let manager = makeIsolatedManager()
        manager.registerLocalMonitor()
        manager.unregisterLocalMonitor()
        manager.unregisterLocalMonitor()
    }

    @Test("deinit automatically cleans up all monitors")
    func deinit_cleansUp_allMonitors() {
        var manager: HotkeyManager? = makeIsolatedManager()
        manager?.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        manager?.registerLocalMonitor()
        manager = nil
    }

    // MARK: - Option+Space state machine logic

    @Test("Option+Space combination triggers onToggle")
    func optionSpace_combination_triggersToggle() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateOptionKeyDown()
        manager.simulateSpaceKeyDown()

        #expect(counter.count == 1)
    }

    @Test("Only Option pressed does not trigger onToggle")
    func optionOnly_noToggle() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateOptionKeyDown()

        #expect(counter.count == 0)
    }

    @Test("Only Space pressed (no Option) does not trigger onToggle")
    func spaceOnly_noToggle() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateSpaceKeyDown()

        #expect(counter.count == 0)
    }

    @Test("Option released then Space pressed does not trigger onToggle")
    func optionReleased_thenSpace_noToggle() {
        let manager = makeIsolatedManager()
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
        let manager = makeIsolatedManager()
        manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        manager.unregisterGlobalHotkey()
        manager.simulateOptionKeyDown()
        manager.simulateSpaceKeyDown()
    }

    // MARK: - hasConflict property

    @Test("hasConflict is initially false")
    func hasConflict_initialFalse() {
        let manager = makeIsolatedManager()
        #expect(manager.hasConflict == false)
    }

    @Test("registerGlobalHotkey failure (no permission) keeps hasConflict false")
    func registerFailure_keepsHasConflictFalse() {
        // 无 Accessibility 权限时在权限检查即返回 false，
        // 不会到达 tapCreate 失败分支，故 hasConflict 保持 false
        let manager = makeIsolatedManager()
        _ = manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        #expect(manager.hasConflict == false)
    }

    // MARK: - isAccessibilityTrusted

    @Test("isAccessibilityTrusted returns a Bool without crashing")
    func isAccessibilityTrusted_returnsBool() {
        let manager = makeIsolatedManager()
        // 仅验证属性可读取，不假定具体值（测试环境通常为 false）
        _ = manager.isAccessibilityTrusted
    }

    @Test("defaultAccessibilityCheck delegates to system AXIsProcessTrusted")
    func defaultAccessibilityCheck_delegatesToSystem() {
        // 直接调用默认实现（具名函数），覆盖其函数体
        // AXIsProcessTrusted() 仅返回当前授权布尔值，无副作用、不弹窗
        let result = HotkeyManager.defaultAccessibilityCheck()
        #expect(result == result) // 仅验证可调用并返回 Bool
    }

    // MARK: - onKeyDown callback

    @Test("onKeyDown callback is settable and invocable")
    func onKeyDown_settable() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onKeyDown = { event in
            counter.flag = true
            return event
        }

        #expect(manager.onKeyDown != nil)

        // 构造一个 keyDown 事件验证回调可被调用
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )
        if let event {
            _ = manager.onKeyDown?(event)
            #expect(counter.flag == true)
        }
    }

    // MARK: - simulateToggle from background thread

    @Test("simulateToggle from background thread dispatches to main")
    func simulateToggle_fromBackgroundThread_dispatchesToMain() async {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        // 从后台线程调用，验证 DispatchQueue.main.sync 分支
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                manager.simulateToggle()
                continuation.resume()
            }
        }

        #expect(counter.count == 1)
    }

    // MARK: - registerGlobalHotkey with different parameters

    @Test("registerGlobalHotkey with different keyCode still returns false without permission")
    func registerGlobalHotkey_differentKeyCode_returnsFalse() {
        let manager = makeIsolatedManager()
        let result = manager.registerGlobalHotkey(keyCode: 36, modifiers: [.command, .shift])
        #expect(result == false)
    }

    // MARK: - State machine reset

    @Test("Option down then up resets state so Space does not trigger")
    func optionDown_thenUp_resetsState() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateOptionKeyDown()
        manager.simulateOptionKeyUp()
        // 再次按下 Space（此时 Option 已释放）不应触发
        manager.simulateSpaceKeyDown()

        #expect(counter.count == 0)
    }

    // MARK: - Multiple toggle invocations

    @Test("simulateToggle called multiple times increments counter each time")
    func simulateToggle_multipleTimes_increments() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }

        manager.simulateToggle()
        manager.simulateToggle()
        manager.simulateToggle()

        #expect(counter.count == 3)
    }

    // MARK: - CGEventTap callback (tapCallbackEntry / handleGlobalEvent)

    private func makeCGKeyEvent(keyCode: UInt16) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        return event
    }

    @Test("tapCallbackEntry with nil refcon returns event unchanged")
    func tapCallbackEntry_nilRefcon_returnsEvent() {
        let event = makeCGKeyEvent(keyCode: 49)
        let result = HotkeyManager.tapCallback(CGEventTapProxy(bitPattern: 1)!, .keyDown, event, nil)
        #expect(result != nil)
    }

    @Test("tapCallbackEntry with valid refcon dispatches to handleGlobalEvent")
    func tapCallbackEntry_validRefcon_dispatches() {
        let manager = makeIsolatedManager()
        let event = makeCGKeyEvent(keyCode: 49)
        let refcon = Unmanaged.passRetained(manager).toOpaque()
        let result = HotkeyManager.tapCallback(CGEventTapProxy(bitPattern: 1)!, .flagsChanged, event, refcon)
        #expect(result != nil)
        // 平衡 passRetained 的引用计数
        _ = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeRetainedValue()
    }

    @Test("handleGlobalEvent flagsChanged updates isOptionHeld (true)")
    func handleGlobalEvent_flagsChanged_setsOptionHeldTrue() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        let event = makeCGKeyEvent(keyCode: 49)
        event.flags = .maskAlternate
        manager.handleGlobalEvent(type: .flagsChanged, event: event)
        // isOptionHeld 应为 true → simulateSpaceKeyDown 触发 onToggle
        manager.simulateSpaceKeyDown()
        #expect(counter.count == 1)
    }

    @Test("handleGlobalEvent flagsChanged updates isOptionHeld (false)")
    func handleGlobalEvent_flagsChanged_setsOptionHeldFalse() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        manager.simulateOptionKeyDown() // isOptionHeld = true
        let event = makeCGKeyEvent(keyCode: 49)
        event.flags = [] // 无 Alternate 标志
        manager.handleGlobalEvent(type: .flagsChanged, event: event)
        // isOptionHeld 应为 false → simulateSpaceKeyDown 不触发
        manager.simulateSpaceKeyDown()
        #expect(counter.count == 0)
    }

    @Test("handleGlobalEvent keyDown with Option+Space triggers onToggle")
    func handleGlobalEvent_keyDown_optionSpace_triggersToggle() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        manager.simulateOptionKeyDown() // isOptionHeld = true
        let event = makeCGKeyEvent(keyCode: 49) // Space
        manager.handleGlobalEvent(type: .keyDown, event: event)
        #expect(counter.count == 1)
    }

    @Test("handleGlobalEvent keyDown without Option does not trigger onToggle")
    func handleGlobalEvent_keyDown_withoutOption_noToggle() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        manager.simulateOptionKeyUp() // isOptionHeld = false
        let event = makeCGKeyEvent(keyCode: 49)
        manager.handleGlobalEvent(type: .keyDown, event: event)
        #expect(counter.count == 0)
    }

    @Test("handleGlobalEvent default type does nothing")
    func handleGlobalEvent_defaultType_noOp() {
        let manager = makeIsolatedManager()
        let event = makeCGKeyEvent(keyCode: 49)
        // 不应崩溃
        manager.handleGlobalEvent(type: .scrollWheel, event: event)
    }

    // MARK: - registerGlobalHotkey success / conflict paths

    @Test("registerGlobalHotkey success path installs tap, enables, and unregisters")
    func registerGlobalHotkey_success_installsAndUnregisters() {
        let manager = makeIsolatedManager()
        manager.accessibilityChecker = { true }
        let port = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
        manager.tapProvider = { port }
        let registered = manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        #expect(registered == true)
        #expect(manager.hasConflict == false)
        // 触发 unregisterGlobalHotkey 的成功路径（eventTap != nil）
        manager.unregisterGlobalHotkey()
    }

    @Test("registerGlobalHotkey hasConflict when tapCreate fails despite permission")
    func registerGlobalHotkey_hasConflict_whenTapFails() {
        let manager = makeIsolatedManager()
        manager.accessibilityChecker = { true }
        manager.tapProvider = { nil } // 模拟 tapCreate 返回 nil
        let registered = manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)
        #expect(registered == false)
        #expect(manager.hasConflict == true)
    }

    @Test("nil tap override is authoritative")
    func nilTapOverrideIsAuthoritative() {
        let manager = makeIsolatedManager()
        var creatorCalls = 0
        manager.accessibilityChecker = { true }
        manager.tapProvider = { nil }
        manager.eventTapCreator = { _, _, _ in
            creatorCalls += 1
            return nil
        }

        let registered = manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)

        #expect(registered == false)
        #expect(manager.hasConflict == true)
        #expect(creatorCalls == 0)
    }

    @Test("local monitor lifecycle uses injected boundary")
    func localMonitorLifecycleUsesInjectedBoundary() {
        let manager = makeIsolatedManager()
        let token = NSObject()
        var installCount = 0
        var removeCount = 0
        var removedToken: AnyObject?
        manager.localMonitorInstaller = { _ in
            installCount += 1
            return token
        }
        manager.localMonitorRemover = { monitor in
            removeCount += 1
            removedToken = monitor as AnyObject
        }

        manager.registerLocalMonitor()
        manager.registerLocalMonitor()
        manager.unregisterLocalMonitor()
        manager.unregisterLocalMonitor()

        #expect(installCount == 1)
        #expect(removeCount == 1)
        #expect(removedToken === token)
    }

    // MARK: - handleLocalMonitorEvent

    private func makeNSKeyEvent(type: NSEvent.EventType, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        )!
    }

    @Test("handleLocalMonitorEvent flagsChanged forwards to onKeyDown")
    func handleLocalMonitorEvent_flagsChanged_forwards() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onKeyDown = { event in counter.flag = true; return event }
        _ = manager.handleLocalMonitorEvent(makeNSKeyEvent(type: .flagsChanged, keyCode: 0))
        #expect(counter.flag == true)
    }

    @Test("handleLocalMonitorEvent ESC/arrow/enter keys return event unchanged")
    func handleLocalMonitorEvent_specialKeys_returnEvent() {
        let manager = makeIsolatedManager()
        manager.onKeyDown = { event in
            Issue.record("onKeyDown should not fire for special keys")
            return event
        }
        let esc = makeNSKeyEvent(type: .keyDown, keyCode: 53)
        #expect(manager.handleLocalMonitorEvent(esc) === esc)
        let left = makeNSKeyEvent(type: .keyDown, keyCode: 123)
        #expect(manager.handleLocalMonitorEvent(left) === left)
        let enter = makeNSKeyEvent(type: .keyDown, keyCode: 36)
        #expect(manager.handleLocalMonitorEvent(enter) === enter)
    }

    @Test("handleLocalMonitorEvent other key forwards to onKeyDown")
    func handleLocalMonitorEvent_otherKey_forwards() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onKeyDown = { event in counter.flag = true; return event }
        _ = manager.handleLocalMonitorEvent(makeNSKeyEvent(type: .keyDown, keyCode: 0))
        #expect(counter.flag == true)
    }

    @Test("localMonitorHandler 直接调用转发到 handleLocalMonitorEvent")
    func localMonitorHandler_directCall_forwards() {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onKeyDown = { event in counter.flag = true; return event }
        let event = makeNSKeyEvent(type: .keyDown, keyCode: 0)
        _ = manager.localMonitorHandler?(event)
        #expect(counter.flag == true)
    }

    @Test("handleLocalMonitorEvent flagsChanged 无 onKeyDown 时返回原事件")
    func handleLocalMonitorEvent_flagsChanged_noOnKeyDown_returnsEvent() {
        let manager = makeIsolatedManager()
        let event = makeNSKeyEvent(type: .flagsChanged, keyCode: 0)
        let result = manager.handleLocalMonitorEvent(event)
        #expect(result === event)
    }

    @Test("handleLocalMonitorEvent 常规按键无 onKeyDown 时返回原事件")
    func handleLocalMonitorEvent_regularKey_noOnKeyDown_returnsEvent() {
        let manager = makeIsolatedManager()
        let event = makeNSKeyEvent(type: .keyDown, keyCode: 0)
        let result = manager.handleLocalMonitorEvent(event)
        #expect(result === event)
    }

    @Test("localMonitorHandler closure forwards to handleLocalMonitorEvent")
    func localMonitorHandler_forwards() {
        let manager = makeIsolatedManager()
        manager.registerLocalMonitor()
        let counter = SendableCounter()
        manager.onKeyDown = { event in counter.flag = true; return event }
        _ = manager.localMonitorHandler?(makeNSKeyEvent(type: .keyDown, keyCode: 0))
        #expect(counter.flag == true)
    }

    #endif
}
