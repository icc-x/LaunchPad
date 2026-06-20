import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 应用图标 Cell — NSCollectionViewItem 子类
/// 显示应用图标 + 标题标签，支持抖动动画和 VoiceOver
public class AppIconCell: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("AppIconCell")

    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let containerView = NSView()
    private let deleteButton = NSButton()
    private var isJiggling = false

    /// 删除按钮点击回调
    public var onDelete: (() -> Void)?

    // MARK: - Lifecycle

    override public func loadView() {
        view = NSView()

        view.addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(titleLabel)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -2),
        ])

        titleLabel.font = NSFont.systemFont(ofSize: 11)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.isSelectable = false

        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.isEditable = false

        // VoiceOver
        view.setAccessibilityRole(.button)

        // ✕ 删除按钮（左上角，默认隐藏）
        setupDeleteButton()
    }

    private func setupDeleteButton() {
        deleteButton.title = "✕"
        deleteButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        deleteButton.bezelStyle = .circular
        deleteButton.isBordered = false
        deleteButton.wantsLayer = true
        deleteButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        deleteButton.layer?.cornerRadius = 10
        deleteButton.layer?.masksToBounds = true
        deleteButton.contentTintColor = .white
        deleteButton.frame = NSRect(x: 2, y: view.bounds.height - 20, width: 20, height: 20)
        deleteButton.alphaValue = 0
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked)
        deleteButton.setAccessibilityLabel("Delete")
        view.addSubview(deleteButton)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            deleteButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            deleteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @objc private func deleteButtonClicked() {
        onDelete?()
    }

    // MARK: - Configuration

    public func configure(item: PageItem, icon: NSImage?) {
        let title = item.app?.title ?? item.group?.title ?? ""
        titleLabel.stringValue = title
        iconImageView.image = icon ?? NSImage(named: NSImage.applicationIconName)
        view.setAccessibilityLabel(title)
    }

    // MARK: - Jiggle Animation

    public func startJiggling() {
        guard !isJiggling else { return }
        isJiggling = true

        let settings = AccessibilitySettings.current()

        // 显示 ✕ 删除按钮
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            deleteButton.animator().alphaValue = 1
        }

        if settings.reduceMotion {
            // Reduce Motion: 缩放脉冲替代抖动
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1.0, 1.05, 1.0]
            pulse.duration = 0.6
            pulse.repeatCount = .infinity
            containerView.layer = CALayer()
            containerView.wantsLayer = true
            containerView.layer?.add(pulse, forKey: "jiggle")
        } else {
            // 正常: 旋转抖动
            let jiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            jiggle.values = [
                AnimationConstants.jiggleMinRotation,
                -AnimationConstants.jiggleMinRotation,
                AnimationConstants.jiggleMaxRotation,
                -AnimationConstants.jiggleMaxRotation,
                AnimationConstants.jiggleMinRotation,
            ]
            jiggle.duration = 0.4
            jiggle.repeatCount = .infinity
            jiggle.isAdditive = true
            containerView.layer = CALayer()
            containerView.wantsLayer = true
            containerView.layer?.add(jiggle, forKey: "jiggle")
        }
    }

    public func stopJiggling() {
        guard isJiggling else { return }
        isJiggling = false
        containerView.layer?.removeAnimation(forKey: "jiggle")

        // 隐藏 ✕ 删除按钮
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            deleteButton.animator().alphaValue = 0
        }
    }

    // MARK: - Reuse

    override public func prepareForReuse() {
        super.prepareForReuse()
        stopJiggling()
        iconImageView.image = nil
        titleLabel.stringValue = ""
    }
}
#endif
