import Foundation
#if canImport(AppKit)
import AppKit

/// 全屏毛玻璃覆盖窗口管理器
public class LaunchPadWindowController: NSWindowController, WindowLifecycleDelegate {

    private let lifecycle: WindowLifecycle
    private let viewController: LaunchPadViewController
    private var accessibilityObserver: AccessibilityObserver?
    /// 测试注入：覆盖 AccessibilitySettings.current()，用于触发 reduced 动画分支
    internal var accessibilitySettingsProvider: @Sendable ()
        -> AccessibilitySettings = { .current() }

    /// 测试注入：驱动「动画 + 完成回调」。生产环境使用真实 NSAnimationContext；
    /// 测试环境注入为同步立即触发完成回调，确定性覆盖 lifecycle.xxxDidFinish()。
    internal var runAnimated: (_ duration: TimeInterval, _ animations: () -> Void, _ completion: @escaping () -> Void) -> Void = { duration, animations, completion in
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            animations()
        }, completionHandler: { completion() })
    }

    /// 测试注入：替代动画完成回调内的 DispatchQueue.main.async，使 lifecycle 状态推进可同步驱动。
    internal var mainAsyncRunner: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }

    internal nonisolated(unsafe) var mainActorDispatcher:
        (@escaping @MainActor @Sendable () -> Void) -> Void = { operation in
        DispatchQueue.main.async(execute: operation)
    }

    internal var applicationURLProvider: (String) -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
    }

    internal var applicationOpener: (URL) -> Void = { url in
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        )
    }

    internal var targetScreenFrameProvider: (NSPoint) -> NSRect? = { mouseLocation in
        (NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main)?.frame
    }

    // MARK: - Init

    public init(
        lifecycle: WindowLifecycle,
        viewController: LaunchPadViewController,
        accessibilityNotificationCenter: NotificationCenter = .default,
        accessibilitySettingsProvider: @escaping @Sendable ()
            -> AccessibilitySettings = { AccessibilitySettings.current() }
    ) {
        self.lifecycle = lifecycle
        self.viewController = viewController

        let panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Use .screenSaver so the overlay covers full-screen apps and the screen saver layer.
        panel.level = .screenSaver
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
        // Follow the window's active state so the visual effect dims correctly when blurred.
        visualEffect.state = .followsWindowActiveState
        panel.contentView = visualEffect

        // Add view controller's view
        viewController.view.frame = visualEffect.bounds
        viewController.view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(viewController.view)

        // Set up lifecycle delegate
        lifecycle.delegate = self

        // Accessibility observer
        self.accessibilitySettingsProvider = accessibilitySettingsProvider
        accessibilityObserver = AccessibilityObserver(
            notificationCenter: accessibilityNotificationCenter,
            settingsProvider: accessibilitySettingsProvider
        ) { [weak self] settings in
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
        // 不支持 NSCoding，返回 nil（可测且不崩溃）替代 fatalError
        return nil
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
        mainActorDispatcher { [weak self] in
            guard let self else { return }
            switch capturedState {
            case .opening:
                self.showWindowAnimated()
            case .visible:
                break
            case .closing:
                self.viewController.cancelActiveDrag()
                self.hideWindowAnimated()
            case .hidden:
                self.viewController.cancelActiveDrag()
                self.window?.orderOut(nil)
                self.viewController.loadData()
            case .launching:
                break
            }
        }
    }

    nonisolated public func lifecycle(_ lifecycle: WindowLifecycle, shouldLaunchApp bundleId: String) {
        mainActorDispatcher { [weak self] in
            guard let self,
                  let url = self.applicationURLProvider(bundleId) else { return }
            self.applicationOpener(url)
        }
    }

    nonisolated public func lifecycleRequestsOpenAnimation(_ lifecycle: WindowLifecycle) {}
    nonisolated public func lifecycleRequestsCloseAnimation(_ lifecycle: WindowLifecycle) {}

    nonisolated public func lifecycleRequestsLaunchAnimation(_ lifecycle: WindowLifecycle, bundleId: String) {
        mainActorDispatcher { [weak self] in
            guard let self else { return }
            // Fade the overlay completely out so the launched app receives focus.
            self.runAnimated(AnimationConstants.appLaunch.duration, {
                self.window?.animator().alphaValue = 0
            }, { [weak self] in
                self?.mainAsyncRunner { [weak self] in self?.lifecycle.launchAnimationDidFinish() }
            })
        }
    }

    // MARK: - Animations

    private func showWindowAnimated() {
        let mouseLocation = NSEvent.mouseLocation
        guard let window,
              let targetFrame = targetScreenFrameProvider(mouseLocation) else { return }
        window.setFrame(targetFrame, display: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        AnimationRunner.animate(
            settings: accessibilitySettingsProvider(),
            animation: AnimationConstants.windowExpand,
            normal: {
                window.contentView?.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)
                self.runAnimated(AnimationConstants.windowExpand.duration, {
                    window.animator().alphaValue = 1
                }, { [weak self] in
                    self?.mainAsyncRunner { [weak self] in self?.lifecycle.openAnimationDidFinish() }
                })
                let spring = CASpringAnimation(keyPath: "transform.scale")
                spring.fromValue = 0.8
                spring.toValue = 1.0
                spring.damping = 0.75
                window.contentView?.layer?.add(spring, forKey: "scaleIn")
            },
            reduced: {
                self.runAnimated(0.1, {
                    window.animator().alphaValue = 1
                }, { [weak self] in
                    self?.mainAsyncRunner { [weak self] in self?.lifecycle.openAnimationDidFinish() }
                })
            }
        )
    }

    private func hideWindowAnimated() {
        let settings = accessibilitySettingsProvider()
        let duration = settings.reduceMotion ? 0.1 : AnimationConstants.appLaunch.duration

        self.runAnimated(duration, {
            self.window?.animator().alphaValue = 0
        }, { [weak self] in
            self?.mainAsyncRunner { [weak self] in self?.lifecycle.closeAnimationDidFinish() }
        })
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard lifecycle.state == .visible else { return }
        lifecycle.handleFocusLost()
    }

    internal func applyAccessibilitySettings(_ settings: AccessibilitySettings) {
        guard let visualEffect = window?.contentView as? NSVisualEffectView else { return }
        let material = BackgroundMaterial.strategy(reduceTransparency: settings.reduceTransparency)
        switch material {
        case .hudWindow:
            visualEffect.material = .hudWindow
            visualEffect.state = .followsWindowActiveState
        case .solidColor:
            visualEffect.material = .menu
            visualEffect.state = .inactive
        }
    }
}
#endif
