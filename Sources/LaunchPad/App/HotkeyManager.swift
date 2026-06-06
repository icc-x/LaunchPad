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
    private var localMonitor: Any?

    // MARK: - Class-level strong reference with lock protection

    private static let retainedLock = NSLock()
    nonisolated(unsafe) private static var retainedSelf: HotkeyManager?

    private static func setRetained(_ manager: HotkeyManager?) {
        retainedLock.lock()
        retainedSelf = manager
        retainedLock.unlock()
    }

    private static func getRetained() -> HotkeyManager? {
        retainedLock.lock()
        defer { retainedLock.unlock() }
        return retainedSelf
    }

    public init() {}

    // MARK: - HotkeyManaging

    @discardableResult
    public func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )

        // Use passRetained to prevent use-after-free — the callback holds a strong reference
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            switch type {
            case .flagsChanged:
                let isOptionNow = event.flags.contains(.maskAlternate)
                DispatchQueue.main.async {
                    manager.isOptionHeld = isOptionNow
                }

            case .keyDown:
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                DispatchQueue.main.async {
                    if manager.isOptionHeld && keyCode == 49 { // 49 = Space
                        manager.onToggle?()
                    }
                }

            default:
                break
            }

            return Unmanaged.passUnretained(event)
        }

        HotkeyManager.setRetained(self)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            // Balance the retain from passRetained
            _ = Unmanaged<HotkeyManager>.fromOpaque(selfPtr).takeRetainedValue()
            HotkeyManager.setRetained(nil)
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    public func unregisterGlobalHotkey() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Remove from run loop before releasing the strong reference
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            eventTap = nil
            // Balance the retain from passRetained
            _ = Unmanaged<HotkeyManager>.passUnretained(self).takeRetainedValue()
        }
        HotkeyManager.setRetained(nil)
    }

    // MARK: - In-app keyboard monitoring

    public func registerLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                return self.onKeyDown?(event) ?? event
            }
            if event.keyCode == 53 { return event }          // ESC
            if [123, 124, 125, 126].contains(event.keyCode) { return event } // Arrow keys
            if event.keyCode == 36 { return event }           // Enter
            return self.onKeyDown?(event) ?? event
        }
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
