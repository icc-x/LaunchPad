import Foundation
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit
import Carbon.HIToolbox

typealias EventTapCreator = (
    CGEventMask,
    CGEventTapCallBack,
    UnsafeMutableRawPointer?
) -> CFMachPort?

/// Global hotkey manager
/// - CGEventTap two-step state machine detecting Option+Space
/// - NSEvent local monitor for in-app keyboard events
/// - CGEventTap callback synchronously preserves event ordering on MainActor
@MainActor
public final class HotkeyManager: HotkeyManaging {

    final class HotkeyCallbackBox {
        weak var manager: HotkeyManager?

        init(manager: HotkeyManager) {
            self.manager = manager
        }
    }

    public var onToggle: (@Sendable () -> Void)?

    /// In-app keyboard event callback
    public var onKeyDown: (@Sendable (NSEvent) -> NSEvent?)?

    // MARK: - Option+Space state machine

    private var isOptionHeld = false

    // MARK: - Event monitors

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var callbackContext: UnsafeMutableRawPointer?

    // MARK: - Test injection points

    /// 是否拥有辅助功能/输入监控权限（默认查询系统，测试可注入）
    var accessibilityChecker: () -> Bool

    /// 默认权限查询实现（具名函数避免默认闭包 thunk 噪声，且可被测试直接覆盖）
    static func defaultAccessibilityCheck() -> Bool { AXIsProcessTrusted() }

    /// 事件 tap 系统边界（测试可注入，避免触及真实事件 tap）
    var eventTapCreator: EventTapCreator = { mask, callback, context in
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: context
        )
    }

    /// run-loop source 生命周期边界；测试替换后不会注册进程级 source。
    var runLoopSourceCreator: (CFMachPort) -> CFRunLoopSource? = {
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, $0, 0)
    }
    var runLoopSourceAdder: (CFRunLoopSource) -> Void = {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), $0, .commonModes)
    }
    var runLoopSourceRemover: (CFRunLoopSource) -> Void = {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), $0, .commonModes)
    }

    /// event tap 启停边界；所有成功注册都由注销路径精确关闭。
    var eventTapEnabler: (CFMachPort, Bool) -> Void = {
        CGEvent.tapEnable(tap: $0, enable: $1)
    }

    /// 本地键盘监视器闭包（抽出为属性，便于测试直接调用）
    var localMonitorHandler: ((NSEvent) -> NSEvent?)?

    /// 本地键盘监视器安装边界（测试可注入）
    var localMonitorInstaller: (@escaping (NSEvent) -> NSEvent?) -> Any? = {
        handler in
        NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged],
            handler: handler
        )
    }

    /// 本地键盘监视器移除边界（测试可注入）
    var localMonitorRemover: (Any) -> Void = { NSEvent.removeMonitor($0) }

    public init() {
        accessibilityChecker = HotkeyManager.defaultAccessibilityCheck
        localMonitorHandler = { [weak self] event in
            guard let self else { return event }
            return self.handleLocalMonitorEvent(event)
        }
    }

    // MARK: - HotkeyManaging

    /// Whether the current process has Accessibility / Input Monitoring permission.
    public var isAccessibilityTrusted: Bool {
        accessibilityChecker()
    }

    /// Indicates if the last registration failed due to a hotkey conflict
    /// (CGEvent.tapCreate returned nil despite having permission)
    public private(set) var hasConflict: Bool = false

    var hasCallbackContext: Bool { callbackContext != nil }

    @discardableResult
    public func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        unregisterGlobalHotkey()
        hasConflict = false

        // Global event taps require Accessibility / Input Monitoring permission.
        // CGEvent.tapCreate may succeed without permission on some macOS versions but the
        // callback will never fire, so we treat "no permission" as a registration failure
        // and let the caller surface a permission prompt.
        guard accessibilityChecker() else { return false }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )

        let context = Unmanaged.passRetained(HotkeyCallbackBox(manager: self)).toOpaque()

        guard let tap = eventTapCreator(mask, HotkeyManager.tapCallback, context) else {
            // tapCreate 失败：可能是快捷键被其他应用占用
            hasConflict = true
            Unmanaged<HotkeyCallbackBox>.fromOpaque(context).release()
            return false
        }

        guard let source = runLoopSourceCreator(tap) else {
            Unmanaged<HotkeyCallbackBox>.fromOpaque(context).release()
            return false
        }

        eventTap = tap
        runLoopSource = source
        callbackContext = context
        runLoopSourceAdder(source)
        eventTapEnabler(tap, true)

        return true
    }

    // MARK: - CGEventTap callback

    /// 静态 CGEventTap 回调（@convention(c)）。事件状态机必须同步交付，
    /// 否则 flagsChanged 和随后的 keyDown 可能发生乱序。
    nonisolated static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        precondition(
            Thread.isMainThread,
            "CGEventTap callback must execute on the main run loop"
        )
        // The source is installed on MainActor's current run loop. These aliases
        // remain valid only for this synchronous callback invocation.
        nonisolated(unsafe) let mainThreadRefcon = refcon
        nonisolated(unsafe) let mainThreadEvent = event
        MainActor.assumeIsolated {
            guard let mainThreadRefcon else { return }
            let box = Unmanaged<HotkeyCallbackBox>
                .fromOpaque(mainThreadRefcon)
                .takeUnretainedValue()
            box.manager?.handleGlobalEvent(type: type, event: mainThreadEvent)
        }
        return Unmanaged.passUnretained(event)
    }

    /// CGEventTap 回调核心逻辑（抽出便于测试，主线程执行）。
    func handleGlobalEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            isOptionHeld = event.flags.contains(.maskAlternate)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if isOptionHeld && keyCode == 49 { // 49 = Space
                onToggle?()
            }

        default:
            break
        }
    }

    public func unregisterGlobalHotkey() {
        if let eventTap {
            eventTapEnabler(eventTap, false)
        }
        if let runLoopSource {
            runLoopSourceRemover(runLoopSource)
        }
        eventTap = nil
        runLoopSource = nil
        releaseCallbackContext()
        isOptionHeld = false
    }

    private func releaseCallbackContext() {
        guard let callbackContext else { return }
        self.callbackContext = nil
        Unmanaged<HotkeyCallbackBox>.fromOpaque(callbackContext).release()
    }

    // MARK: - In-app keyboard monitoring

    public func registerLocalMonitor() {
        guard localMonitor == nil, let localMonitorHandler else { return }
        guard let monitor = localMonitorInstaller(localMonitorHandler) else { return }
        localMonitor = monitor
    }

    /// 本地键盘监视器事件处理（抽出便于测试）。
    func handleLocalMonitorEvent(_ event: NSEvent) -> NSEvent? {
        guard let onKeyDown else { return event }
        return onKeyDown(event)
    }

    public func unregisterLocalMonitor() {
        guard let localMonitor else { return }
        localMonitorRemover(localMonitor)
        self.localMonitor = nil
    }

    // MARK: - Test helpers

    public func simulateToggle() {
        onToggle?()
    }

    public func simulateOptionKeyDown() {
        isOptionHeld = true
    }

    public func simulateOptionKeyUp() {
        isOptionHeld = false
    }

    public func simulateSpaceKeyDown() {
        guard isOptionHeld else { return }
        onToggle?()
    }

    isolated deinit {
        unregisterGlobalHotkey()
        unregisterLocalMonitor()
    }
}
#endif
