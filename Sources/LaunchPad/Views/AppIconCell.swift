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
    private var isJiggling = false

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

    public func stopJiggling() {
        guard isJiggling else { return }
        isJiggling = false
        containerView.layer?.removeAnimation(forKey: "jiggle")
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
