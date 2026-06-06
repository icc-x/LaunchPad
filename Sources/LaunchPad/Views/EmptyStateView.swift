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

    public func hide(animated: Bool = true) {
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.isHidden = true
            })
        } else {
            alphaValue = 0
            isHidden = true
        }
    }
}
#endif
