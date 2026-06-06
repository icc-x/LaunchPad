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

    public var onToggle: (() -> Void)?

    /// In-app keyboard event callback, return nil to consume event, return event to pass to next responder
    public var onKeyDown: ((NSEvent) -> NSEvent?)?

    // MARK: - Option+Space state machine

    /// Whether Option key is held down (tracked via flagsChanged events)
    private var isOptionHeld = false

    // MARK: - Event monitors

    private var eventTap: CFMachPort?
    private var localMonitor: Any?

    // MARK: - Class-level strong reference (prevent dangling pointer in CGEventTap callback)

    /// Strong reference to self, preventing dangling pointers in CGEventTap callback with passUnretained.
    /// Set in registerGlobalHotkey, cleared in unregisterGlobalHotkey.
    /// This class is @unchecked Sendable, and access is protected by external synchronization (main thread).
    nonisolated(unsafe) private static var retainedSelf: HotkeyManager?

    public init() {}

    // MARK: - HotkeyManaging

    @discardableResult
    public func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Monitor flagsChanged (Option key) and keyDown (Space key)
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            switch type {
            case .flagsChanged:
                // Track Option key press/release state
                // Dispatch to main thread to avoid data race with isOptionHeld read in keyDown
                let isOptionNow = event.flags.contains(.maskAlternate)
                DispatchQueue.main.async {
                    manager.isOptionHeld = isOptionNow
                }

            case .keyDown:
                // Detect Option+Space combination
                // Move isOptionHeld read and onToggle call to main thread to avoid data race
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

        // Use class-level strong reference to prevent dangling pointer
        HotkeyManager.retainedSelf = self
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            HotkeyManager.retainedSelf = nil
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
            eventTap = nil
        }
        HotkeyManager.retainedSelf = nil
    }

    // MARK: - In-app keyboard monitoring

    /// Register in-app keyboard event monitor, forwarding events to onKeyDown callback
    public func registerLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }

            // flagsChanged events (modifier keys) forwarded to onKeyDown callback
            if event.type == .flagsChanged {
                return self.onKeyDown?(event) ?? event
            }

            // ESC
            if event.keyCode == 53 { return event }

            // Arrow keys
            if [123, 124, 125, 126].contains(event.keyCode) { return event }

            // Enter
            if event.keyCode == 36 { return event }

            // Other character keys -> forward to onKeyDown callback
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

    /// Test-only: simulate onToggle callback firing (executes synchronously on main thread)
    public func simulateToggle() {
        if Thread.isMainThread {
            onToggle?()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.onToggle?()
            }
        }
    }

    /// Test-only: simulate Option key down (flagsChanged)
    public func simulateOptionKeyDown() {
        isOptionHeld = true
    }

    /// Test-only: simulate Option key up (flagsChanged)
    public func simulateOptionKeyUp() {
        isOptionHeld = false
    }

    /// Test-only: simulate Space key down (keyDown, checks if Option is held)
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
