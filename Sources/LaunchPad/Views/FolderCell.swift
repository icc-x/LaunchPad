import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 文件夹 Cell — NSCollectionViewItem 子类
/// 显示 3×3 图标缩略网格 + 文件夹标题
public class FolderCell: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("FolderCell")

    let titleLabel = NSTextField(labelWithString: "")
    private let thumbnailGrid = NSView()
    private var thumbnailImageViews: [NSImageView] = []
    let containerView = NSView()
    let frostedBackground = NSVisualEffectView()

    /// 文件夹重命名回调
    public var onRenamed: ((String) -> Void)?

    /// 测试注入：覆盖 AccessibilitySettings.current()，用于触发 reduceTransparency 回退分支。
    internal var accessibilitySettingsProvider: () -> AccessibilitySettings = { .current() }

    private static let gridSize = 3
    private static let thumbnailSize: CGFloat = 20
    private static let thumbnailSpacing: CGFloat = 2

    // MARK: - Lifecycle

    override public func loadView() {
        view = NSView()

        // 毛玻璃背景（圆角矩形）
        frostedBackground.blendingMode = .withinWindow
        frostedBackground.material = .hudWindow
        frostedBackground.state = .active
        frostedBackground.wantsLayer = true
        frostedBackground.layer?.cornerRadius = 8
        frostedBackground.layer?.masksToBounds = true
        frostedBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frostedBackground)
        NSLayoutConstraint.activate([
            frostedBackground.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            frostedBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            frostedBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            frostedBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
        ])

        view.addSubview(containerView)
        containerView.addSubview(thumbnailGrid)
        containerView.addSubview(titleLabel)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailGrid.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            thumbnailGrid.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            thumbnailGrid.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            thumbnailGrid.widthAnchor.constraint(equalToConstant: Self.gridTotalSize),
            thumbnailGrid.heightAnchor.constraint(equalToConstant: Self.gridTotalSize),

            titleLabel.topAnchor.constraint(equalTo: thumbnailGrid.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -2),
        ])

        containerView.wantsLayer = true

        titleLabel.font = NSFont.systemFont(ofSize: 11)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.isSelectable = false
        titleLabel.isEditable = false
        titleLabel.delegate = self

        // 双击进入编辑模式
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        titleLabel.addGestureRecognizer(doubleClick)

        setupThumbnailGrid()

        view.setAccessibilityRole(.button)
    }

    private static var gridTotalSize: CGFloat {
        CGFloat(gridSize) * thumbnailSize + CGFloat(gridSize - 1) * thumbnailSpacing
    }

    private func setupThumbnailGrid() {
        thumbnailImageViews.removeAll()
        thumbnailGrid.subviews.forEach { $0.removeFromSuperview() }

        for row in 0..<Self.gridSize {
            for col in 0..<Self.gridSize {
                let imageView = NSImageView()
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                thumbnailGrid.addSubview(imageView)

                let x = CGFloat(col) * (Self.thumbnailSize + Self.thumbnailSpacing)
                let y = CGFloat(Self.gridSize - 1 - row) * (Self.thumbnailSize + Self.thumbnailSpacing)

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: thumbnailGrid.leadingAnchor, constant: x),
                    imageView.bottomAnchor.constraint(equalTo: thumbnailGrid.bottomAnchor, constant: -y),
                    imageView.widthAnchor.constraint(equalToConstant: Self.thumbnailSize),
                    imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailSize),
                ])

                thumbnailImageViews.append(imageView)
            }
        }
    }

    // MARK: - Configuration

    public func configure(item: PageItem, childIcons: [NSImage]) {
        let title = item.group?.title ?? "Folder"
        titleLabel.stringValue = title
        view.setAccessibilityLabel(title)

        // Reduce Transparency 回退
        let settings = accessibilitySettingsProvider()
        if settings.reduceTransparency {
            frostedBackground.material = .menu
            frostedBackground.state = .inactive
            frostedBackground.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        // Increase Contrast: 边框 + 加粗文字
        if settings.increaseContrast {
            containerView.layer?.borderWidth = 1
            containerView.layer?.borderColor = NSColor.labelColor.cgColor
            titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        } else {
            containerView.layer?.borderWidth = 0
            titleLabel.font = NSFont.systemFont(ofSize: 11)
        }

        for (index, imageView) in thumbnailImageViews.enumerated() {
            imageView.image = index < childIcons.count ? childIcons[index] : nil
            imageView.isHidden = index >= childIcons.count
        }
    }

    // MARK: - Reuse

    override public func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.stringValue = ""
        titleLabel.isEditable = false
        thumbnailImageViews.forEach { $0.image = nil }
    }

    // MARK: - 双击编辑

    @objc private func handleDoubleClick() {
        titleLabel.isEditable = true
        titleLabel.window?.makeFirstResponder(titleLabel)
        titleLabel.selectText(nil)
    }
}

// MARK: - NSTextFieldDelegate

extension FolderCell: NSTextFieldDelegate {
    public func controlTextDidEndEditing(_ obj: Notification) {
        titleLabel.isEditable = false
        let newTitle = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty {
            onRenamed?(newTitle)
        }
    }
}
#endif
