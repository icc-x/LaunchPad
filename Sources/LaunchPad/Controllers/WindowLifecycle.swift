import Foundation

/// 窗口生命周期状态机委托协议
@preconcurrency
public protocol WindowLifecycleDelegate: AnyObject {
    func lifecycle(_ lifecycle: WindowLifecycle, didTransitionTo state: WindowLifecycle.State)
    func lifecycle(_ lifecycle: WindowLifecycle, shouldLaunchApp bundleId: String)
    func lifecycleRequestsOpenAnimation(_ lifecycle: WindowLifecycle)
    func lifecycleRequestsCloseAnimation(_ lifecycle: WindowLifecycle)
    func lifecycleRequestsLaunchAnimation(_ lifecycle: WindowLifecycle, bundleId: String)
}

/// 窗口生命周期状态机
public final class WindowLifecycle {

    public enum State: Equatable {
        case hidden
        case opening
        case visible
        case closing
        case launching
    }

    public private(set) var state: State = .hidden
    public weak var delegate: WindowLifecycleDelegate?

    public init(delegate: WindowLifecycleDelegate? = nil) {
        self.delegate = delegate
    }

    public func handleToggle() {
        switch state {
        case .hidden:
            transition(to: .opening)
            delegate?.lifecycleRequestsOpenAnimation(self)
        case .visible:
            transition(to: .closing)
            delegate?.lifecycleRequestsCloseAnimation(self)
        case .opening:
            // 打开动画可能因无可用屏幕等原因无法完成；允许再次 toggle 撤销，避免永久卡死。
            transition(to: .hidden)
        case .closing, .launching:
            break
        }
    }

    public func handleEscape() {
        switch state {
        case .visible:
            transition(to: .closing)
            delegate?.lifecycleRequestsCloseAnimation(self)
        case .opening:
            transition(to: .hidden)
        case .hidden, .closing, .launching:
            break
        }
    }

    public func handleAppClick(bundleId: String) {
        guard state == .visible else { return }
        transition(to: .launching)
        delegate?.lifecycle(self, shouldLaunchApp: bundleId)
        delegate?.lifecycleRequestsLaunchAnimation(self, bundleId: bundleId)
    }

    public func handleFocusLost() {
        guard state == .visible || state == .opening else { return }
        transition(to: .closing)
        delegate?.lifecycleRequestsCloseAnimation(self)
    }

    public func openAnimationDidFinish() {
        guard state == .opening else { return }
        transition(to: .visible)
    }

    public func closeAnimationDidFinish() {
        guard state == .closing else { return }
        transition(to: .hidden)
    }

    public func launchAnimationDidFinish() {
        guard state == .launching else { return }
        transition(to: .closing)
        delegate?.lifecycleRequestsCloseAnimation(self)
    }

    private func transition(to newState: State) {
        state = newState
        delegate?.lifecycle(self, didTransitionTo: newState)
    }
}
