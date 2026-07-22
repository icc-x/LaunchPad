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

private final class KeyCodeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UInt16] = []

    func append(_ keyCode: UInt16) {
        lock.lock()
        storage.append(keyCode)
        lock.unlock()
    }

    var values: [UInt16] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
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

    private func makeMachPort() throws -> CFMachPort {
        let port = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
        return try #require(port)
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

    @Test("isAccessibilityTrusted returns the injected permission value")
    func isAccessibilityTrusted_returnsInjectedValue() {
        let manager = makeIsolatedManager(accessibilityTrusted: false)
        #expect(manager.isAccessibilityTrusted == false)

        manager.accessibilityChecker = { true }
        #expect(manager.isAccessibilityTrusted == true)
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

    // MARK: - C callback delivery

    @Test("main-runloop C callbacks synchronously preserve flags/keyDown ordering")
    func tapCallback_onMainRunLoop_preservesEventOrdering() throws {
        let manager = makeIsolatedManager(accessibilityTrusted: true)
        let port = try makeMachPort()
        manager.tapProvider = nil
        var callbackContext: UnsafeMutableRawPointer?
        var creatorCalls = 0
        var creatorRanOnMainThread = false
        manager.eventTapCreator = { _, _, context in
            MainActor.preconditionIsolated()
            creatorCalls += 1
            creatorRanOnMainThread = Thread.isMainThread
            callbackContext = context
            return port
        }
        let counter = SendableCounter()
        manager.onToggle = {
            MainActor.preconditionIsolated()
            counter.flag = Thread.isMainThread
            counter.count += 1
        }
        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == true)
        let context = try #require(callbackContext)
        let flagsEvent = try makeCGKeyEvent(keyCode: 49)
        flagsEvent.flags = .maskAlternate
        let keyEvent = try makeCGKeyEvent(keyCode: 49)
        let proxy = try #require(CGEventTapProxy(bitPattern: 1))

        let flagsResult = HotkeyManager.tapCallback(
            proxy,
            .flagsChanged,
            flagsEvent,
            context
        )
        let keyResult = HotkeyManager.tapCallback(
            proxy,
            .keyDown,
            keyEvent,
            context
        )

        #expect(creatorCalls == 1)
        #expect(creatorRanOnMainThread == true)
        #expect(flagsResult != nil)
        #expect(keyResult != nil)
        #expect(counter.count == 1)
        #expect(counter.flag == true)
        manager.unregisterGlobalHotkey()
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

    private func makeCGKeyEvent(keyCode: UInt16) throws -> CGEvent {
        try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
    }

    @Test("tapCallbackEntry with nil refcon returns event unchanged")
    func tapCallbackEntry_nilRefcon_returnsEvent() throws {
        let event = try makeCGKeyEvent(keyCode: 49)
        let proxy = try #require(CGEventTapProxy(bitPattern: 1))
        let result = HotkeyManager.tapCallback(proxy, .keyDown, event, nil)
        #expect(result != nil)
    }

    @Test("tapCallbackEntry with valid refcon dispatches to handleGlobalEvent")
    func tapCallbackEntry_validRefcon_dispatches() throws {
        let manager = makeIsolatedManager(accessibilityTrusted: true)
        let port = try makeMachPort()
        manager.tapProvider = nil
        var contextAddress: UInt?
        manager.eventTapCreator = { _, _, context in
            contextAddress = context.map { UInt(bitPattern: $0) }
            return port
        }
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == true)

        let event = try makeCGKeyEvent(keyCode: 49)
        event.flags = .maskAlternate
        let address = try #require(contextAddress)
        let context = try #require(UnsafeMutableRawPointer(bitPattern: address))
        let proxy = try #require(CGEventTapProxy(bitPattern: 1))
        let result = HotkeyManager.tapCallback(
            proxy,
            .flagsChanged,
            event,
            context
        )
        manager.simulateSpaceKeyDown()

        #expect(result != nil)
        #expect(counter.count == 1)
        manager.unregisterGlobalHotkey()
    }

    @Test("handleGlobalEvent flagsChanged updates isOptionHeld (true)")
    func handleGlobalEvent_flagsChanged_setsOptionHeldTrue() throws {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        let event = try makeCGKeyEvent(keyCode: 49)
        event.flags = .maskAlternate
        manager.handleGlobalEvent(type: .flagsChanged, event: event)
        // isOptionHeld 应为 true → simulateSpaceKeyDown 触发 onToggle
        manager.simulateSpaceKeyDown()
        #expect(counter.count == 1)
    }

    @Test("handleGlobalEvent flagsChanged updates isOptionHeld (false)")
    func handleGlobalEvent_flagsChanged_setsOptionHeldFalse() throws {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        manager.simulateOptionKeyDown() // isOptionHeld = true
        let event = try makeCGKeyEvent(keyCode: 49)
        event.flags = [] // 无 Alternate 标志
        manager.handleGlobalEvent(type: .flagsChanged, event: event)
        // isOptionHeld 应为 false → simulateSpaceKeyDown 不触发
        manager.simulateSpaceKeyDown()
        #expect(counter.count == 0)
    }

    @Test("handleGlobalEvent keyDown with Option+Space triggers onToggle")
    func handleGlobalEvent_keyDown_optionSpace_triggersToggle() throws {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        manager.simulateOptionKeyDown() // isOptionHeld = true
        let event = try makeCGKeyEvent(keyCode: 49) // Space
        manager.handleGlobalEvent(type: .keyDown, event: event)
        #expect(counter.count == 1)
    }

    @Test("handleGlobalEvent keyDown without Option does not trigger onToggle")
    func handleGlobalEvent_keyDown_withoutOption_noToggle() throws {
        let manager = makeIsolatedManager()
        let counter = SendableCounter()
        manager.onToggle = { counter.count += 1 }
        manager.simulateOptionKeyUp() // isOptionHeld = false
        let event = try makeCGKeyEvent(keyCode: 49)
        manager.handleGlobalEvent(type: .keyDown, event: event)
        #expect(counter.count == 0)
    }

    @Test("handleGlobalEvent default type does nothing")
    func handleGlobalEvent_defaultType_noOp() throws {
        let manager = makeIsolatedManager()
        let event = try makeCGKeyEvent(keyCode: 49)
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

    @Test("no tap override calls the injected creator exactly once")
    func eventTapCreatorWithoutOverrideCalledExactlyOnce() {
        let manager = makeIsolatedManager(accessibilityTrusted: true)
        manager.tapProvider = nil
        var creatorCalls = 0
        weak var weakBox: HotkeyManager.HotkeyCallbackBox?
        manager.eventTapCreator = { _, _, context in
            creatorCalls += 1
            if let context {
                weakBox = Unmanaged<HotkeyManager.HotkeyCallbackBox>
                    .fromOpaque(context)
                    .takeUnretainedValue()
            }
            return nil
        }

        let registered = manager.registerGlobalHotkey(keyCode: 49, modifiers: .option)

        #expect(registered == false)
        #expect(manager.hasConflict == true)
        #expect(creatorCalls == 1)
        #expect(weakBox == nil)
    }

    @Test("conflict resets before permission failure and later success")
    func conflictStateResetsAcrossRegistrationAttempts() throws {
        let manager = makeIsolatedManager(accessibilityTrusted: true)
        let port = try makeMachPort()
        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == false)
        #expect(manager.hasConflict == true)

        manager.accessibilityChecker = { false }
        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == false)
        #expect(manager.hasConflict == false)

        manager.accessibilityChecker = { true }
        manager.tapProvider = { port }
        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == true)
        #expect(manager.hasConflict == false)
        manager.unregisterGlobalHotkey()
    }

    @Test("successful unregister releases callback ownership")
    func successfulUnregisterReleasesManager() throws {
        let port = try makeMachPort()
        weak var weakManager: HotkeyManager?
        weak var weakBox: HotkeyManager.HotkeyCallbackBox?
        do {
            let manager = makeIsolatedManager(accessibilityTrusted: true)
            manager.tapProvider = nil
            manager.eventTapCreator = { _, _, context in
                if let context {
                    weakBox = Unmanaged<HotkeyManager.HotkeyCallbackBox>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                }
                return port
            }
            weakManager = manager
            #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == true)
            #expect(weakBox != nil)
            manager.unregisterGlobalHotkey()
            #expect(weakBox == nil)
        }

        #expect(weakManager == nil)
    }

    @Test("re-registration and double unregister release each callback context once")
    func repeatedRegistrationAndDoubleUnregisterReleaseOwnedContexts() throws {
        let manager = makeIsolatedManager(accessibilityTrusted: true)
        let firstPort = try makeMachPort()
        let secondPort = try makeMachPort()
        manager.tapProvider = nil
        weak var firstBox: HotkeyManager.HotkeyCallbackBox?
        weak var secondBox: HotkeyManager.HotkeyCallbackBox?
        var creatorCalls = 0
        manager.eventTapCreator = { _, _, context in
            creatorCalls += 1
            if let context {
                let box = Unmanaged<HotkeyManager.HotkeyCallbackBox>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                if creatorCalls == 1 {
                    firstBox = box
                } else {
                    secondBox = box
                }
            }
            return creatorCalls == 1 ? firstPort : secondPort
        }

        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == true)
        #expect(firstBox != nil)
        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == true)
        #expect(firstBox == nil)
        #expect(secondBox != nil)

        manager.unregisterGlobalHotkey()
        manager.unregisterGlobalHotkey()

        #expect(secondBox == nil)
        #expect(creatorCalls == 2)
    }

    @Test("deinit releases an active callback context")
    func deinitReleasesActiveCallbackContext() throws {
        let port = try makeMachPort()
        weak var weakManager: HotkeyManager?
        weak var weakBox: HotkeyManager.HotkeyCallbackBox?
        do {
            let manager = makeIsolatedManager(accessibilityTrusted: true)
            manager.tapProvider = nil
            manager.eventTapCreator = { _, _, context in
                if let context {
                    weakBox = Unmanaged<HotkeyManager.HotkeyCallbackBox>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                }
                return port
            }
            weakManager = manager
            #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option) == true)
            #expect(weakBox != nil)
        }

        #expect(weakManager == nil)
        #expect(weakBox == nil)
    }

    @Test("重复注册 local monitor 只安装一次")
    func localMonitorRegistrationIsIdempotent() {
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

    @Test("local monitor 转发 ESC 方向键 Enter 并保留 nil")
    func localMonitorForwardsSpecialKeysAndNil() {
        let manager = makeIsolatedManager()
        let keyCodes = KeyCodeRecorder()
        manager.onKeyDown = { event in
            keyCodes.append(event.keyCode)
            return nil
        }
        let handler = manager.localMonitorHandler

        for keyCode: UInt16 in [53, 123, 124, 125, 126, 36] {
            #expect(handler?(makeNSKeyEvent(type: .keyDown, keyCode: keyCode)) == nil)
        }
        #expect(keyCodes.values == [53, 123, 124, 125, 126, 36])
    }

    @Test("local monitor 无 callback 时放行原对象")
    func localMonitorWithoutCallbackReturnsOriginal() {
        let manager = makeIsolatedManager()
        let event = makeNSKeyEvent(type: .keyDown, keyCode: 53)

        #expect(manager.localMonitorHandler?(event) === event)
    }

    @Test("local monitor manager 释放后放行原对象")
    func localMonitorHandlerAfterManagerDeallocationReturnsOriginal() {
        var manager: HotkeyManager? = makeIsolatedManager()
        weak var weakManager: HotkeyManager?
        weakManager = manager
        manager?.onKeyDown = { _ in nil }
        let handler = manager?.localMonitorHandler
        let event = makeNSKeyEvent(type: .keyDown, keyCode: 53)

        #expect(handler?(event) == nil)
        manager = nil
        #expect(weakManager == nil)
        #expect(handler?(event) === event)
    }

    @Test("local monitor flagsChanged 转发并保留 nil")
    func localMonitorForwardsFlagsChangedAndNil() {
        let manager = makeIsolatedManager()
        let keyCodes = KeyCodeRecorder()
        manager.onKeyDown = { event in
            keyCodes.append(event.keyCode)
            return nil
        }

        #expect(manager.localMonitorHandler?(
            makeNSKeyEvent(type: .flagsChanged, keyCode: 58)
        ) == nil)
        #expect(keyCodes.values == [58])
    }

    @Test("local monitor 转发普通按键并保留 nil")
    func localMonitorForwardsRegularKeyAndNil() {
        let manager = makeIsolatedManager()
        let keyCodes = KeyCodeRecorder()
        manager.onKeyDown = { event in
            keyCodes.append(event.keyCode)
            return nil
        }
        let event = makeNSKeyEvent(type: .keyDown, keyCode: 0)

        #expect(manager.localMonitorHandler?(event) == nil)
        #expect(keyCodes.values == [0])
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
        defer { manager.unregisterLocalMonitor() }
        let counter = SendableCounter()
        manager.onKeyDown = { event in counter.flag = true; return event }
        _ = manager.localMonitorHandler?(makeNSKeyEvent(type: .keyDown, keyCode: 0))
        #expect(counter.flag == true)
    }

    #endif
}
