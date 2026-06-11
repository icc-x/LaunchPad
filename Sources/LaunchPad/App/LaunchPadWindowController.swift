import Foundation
#if canImport(AppKit)
import AppKit

/// 全屏毛玻璃覆盖窗口管理器
public class LaunchPadWindowController: NSWindowController, WindowLifecycleDelegate {

    private let lifecycle: WindowLifecycle
    private let viewController: LaunchPadViewController
    private var accessibilityObserver: AccessibilityObserver?

    // MARK: - Init

    public init(lifecycle: WindowLifecycle, viewController: LaunchPadViewController) {
        self.lifecycle = lifecycle
        self.viewController = viewController

        let panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        super.init(window: panel)

        // Setup visual effect background
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        panel.contentView = visualEffect

        // Add view controller's view
        viewController.view.frame = visualEffect.bounds
        viewController.view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(viewController.view)

        // Set up lifecycle delegate
        lifecycle.delegate = self

        // Accessibility observer
        accessibilityObserver = AccessibilityObserver { [weak self] settings in
            self?.applyAccessibilitySettings(settings)
        }

        // Focus loss detection
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Public API

    public func toggle() {
        lifecycle.handleToggle()
    }

    public func escape() {
        lifecycle.handleEscape()
    }

    // MARK: - WindowLifecycleDelegate

    nonisolated public func lifecycle(_ lifecycle: WindowLifecycle, didTransitionTo state: WindowLifecycle.State) {
        nonisolated(unsafe) let capturedState = state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch capturedState {
            case .opening:
                self.showWindowAnimated()
            case .visible:
                break
            case .closing:
                self.hideWindowAnimated()
            case .hidden:
                self.window?.orderOut(nil)
                self.viewController.loadData()
            case .launching:
                break
            }
        }
    }

    nonisolated public func lifecycle(_ lifecycle: WindowLifecycle, shouldLaunchApp bundleId: String) {
        DispatchQueue.main.async {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        }
    }

    nonisolated public func lifecycleRequestsOpenAnimation(_ lifecycle: WindowLifecycle) {}
    nonisolated public func lifecycleRequestsCloseAnimation(_ lifecycle: WindowLifecycle) {}

    nonisolated public func lifecycleRequestsLaunchAnimation(_ lifecycle: WindowLifecycle, bundleId: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = AnimationConstants.appLaunch.duration
                self.window?.animator().alphaValue = 0.8
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.lifecycle.launchAnimationDidFinish()
                }
            })
        }
    }

    // MARK: - Animations

    private func showWindowAnimated() {
        guard let window = window, let screen = NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        let settings = AccessibilitySettings.current()
        let duration = settings.reduceMotion ? 0.1 : AnimationConstants.appLaunch.duration

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.lifecycle.openAnimationDidFinish()
            }
        })
    }

    private func hideWindowAnimated() {
        let settings = AccessibilitySettings.current()
        let duration = settings.reduceMotion ? 0.1 : AnimationConstants.appLaunch.duration

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            self.window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.lifecycle.closeAnimationDidFinish()
            }
        })
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard lifecycle.state == .visible else { return }
        lifecycle.handleFocusLost()
    }

    private func applyAccessibilitySettings(_ settings: AccessibilitySettings) {
        guard let visualEffect = window?.contentView as? NSVisualEffectView else { return }
        let material = BackgroundMaterial.strategy(reduceTransparency: settings.reduceTransparency)
        switch material {
        case .hudWindow:
            visualEffect.material = .hudWindow
            visualEffect.state = .active
        case .solidColor:
            visualEffect.material = .menu
            visualEffect.state = .inactive
        }
    }
}
#endif
