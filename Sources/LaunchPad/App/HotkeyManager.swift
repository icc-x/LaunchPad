import Foundation
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit
import Carbon.HIToolbox

/// Global hotkey manager
/// - CGEventTap two-step state machine detecting Option+Space
/// - NSEvent local monitor for in-app keyboard events
/// - Thread safety: CGEventTap callback dispatches via DispatchQueue.main.async
public final class HotkeyManager: HotkeyManaging, @unchecked Sendable {

    public var onToggle: (@Sendable () -> Void)?

    /// In-app keyboard event callback
    public var onKeyDown: (@Sendable (NSEvent) -> NSEvent?)?

    // MARK: - Option+Space state machine

    private var isOptionHeld = false

    // MARK: - Event monitors

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?

    // MARK: - Class-level strong reference with lock protection

    private static let retainedLock = NSLock()
    nonisolated(unsafe) private static var retainedSelf: HotkeyManager?

    private static func setRetained(_ manager: HotkeyManager?) {
        retainedLock.lock()
        retainedSelf = manager
        retainedLock.unlock()
    }

    // MARK: - Test injection points

    /// 是否拥有辅助功能/输入监控权限（默认查询系统，测试可注入）
    var accessibilityChecker: () -> Bool

    /// 默认权限查询实现（具名函数避免默认闭包 thunk 噪声，且可被测试直接覆盖）
    static func defaultAccessibilityCheck() -> Bool { AXIsProcessTrusted() }

    /// 事件 tap 创建器（默认走真实 CGEvent.tapCreate；测试可注入以模拟成功/失败）
    var tapProvider: (() -> CFMachPort?)?

    /// 本地键盘监视器闭包（抽出为属性，便于测试直接调用）
    var localMonitorHandler: ((NSEvent) -> NSEvent)?

    public init() {
        accessibilityChecker = HotkeyManager.defaultAccessibilityCheck
        localMonitorHandler = { [weak self] event in
            self?.handleLocalMonitorEvent(event) ?? event
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

    @discardableResult
    public func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Global event taps require Accessibility / Input Monitoring permission.
        // CGEvent.tapCreate may succeed without permission on some macOS versions but the
        // callback will never fire, so we treat "no permission" as a registration failure
        // and let the caller surface a permission prompt.
        guard accessibilityChecker() else { return false }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )

        // Use passRetained to prevent use-after-free — the callback holds a strong reference
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let tap: CFMachPort? = tapProvider?() ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: HotkeyManager.tapCallback,
            userInfo: selfPtr
        )
        eventTap = tap

        guard let tap else {
            // tapCreate 失败：可能是快捷键被其他应用占用
            hasConflict = true
            _ = Unmanaged<HotkeyManager>.fromOpaque(selfPtr).takeRetainedValue()
            HotkeyManager.setRetained(nil)
            return false
        }

        HotkeyManager.setRetained(self)

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    // MARK: - CGEventTap callback

    /// 静态 CGEventTap 回调（@convention(c)，可直接单元测试）。
    /// 解析 refcon 恢复 manager 实例，调用 handleGlobalEvent（tap 回调本就在主线程 run loop 触发）。
    static let tapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
        manager.handleGlobalEvent(type: type, event: event)
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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Reuse the source created in registerGlobalHotkey — creating a new one here
            // would be a different instance and CFRunLoopRemoveSource would be a no-op,
            // leaking the original source on the run loop.
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                runLoopSource = nil
            }
            eventTap = nil
        }
        // The retain from passRetained(self) is balanced by clearing the class-level
        // strong reference. The previous `passUnretained(self).takeRetainedValue()` call
        // was incorrect (mismatched Unmanaged pairing) and decremented an unrelated retain.
        HotkeyManager.setRetained(nil)
    }

    // MARK: - In-app keyboard monitoring

    public func registerLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: localMonitorHandler!)
    }

    /// 本地键盘监视器事件处理（抽出便于测试）。
    func handleLocalMonitorEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            return onKeyDown?(event) ?? event
        }
        if event.keyCode == 53 { return event }          // ESC
        if [123, 124, 125, 126].contains(event.keyCode) { return event } // Arrow keys
        if event.keyCode == 36 { return event }           // Enter
        return onKeyDown?(event) ?? event
    }

    public func unregisterLocalMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Test helpers

    public func simulateToggle() {
        if Thread.isMainThread {
            onToggle?()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.onToggle?()
            }
        }
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

    deinit {
        unregisterGlobalHotkey()
        unregisterLocalMonitor()
    }
}
#endif
