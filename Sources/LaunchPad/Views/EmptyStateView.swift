import Foundation
#if canImport(AppKit)
import AppKit

/// 搜索无结果提示视图
public class EmptyStateView: NSView {

    private let messageLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(messageLabel)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.stringValue = "No applications found"
        messageLabel.font = NSFont.systemFont(ofSize: 18, weight: .light)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        alphaValue = 0
        isHidden = true

        hideCompletionRunner = { [weak self] completion in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self?.animator().alphaValue = 0
            }, completionHandler: { completion() })
        }
    }

    public func show(animated: Bool = true) {
        isHidden = false
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }

    /// 测试注入：驱动 hide 动画的完成回调。生产环境为真实 NSAnimationContext，
    /// 测试环境可注入为同步立即触发，确定性覆盖 `isHidden = true` 分支。
    internal var hideCompletionRunner: (@escaping () -> Void) -> Void = { $0() }

    public func hide(animated: Bool = true) {
        if animated {
            hideCompletionRunner { [weak self] in
                MainActor.assumeIsolated {
                    self?.isHidden = true
                }
            }
        } else {
            alphaValue = 0
            isHidden = true
        }
    }
}
#endif
