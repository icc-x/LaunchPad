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
    private let deleteButton = NSButton()
    private var thumbnailImageViews: [NSImageView] = []
    let containerView = NSView()
    let frostedBackground = NSVisualEffectView()

    /// 文件夹重命名回调
    public var onRenamed: ((String) -> Void)?

    /// 编辑模式下点击删除控件时的回调。
    public var onDelete: (() -> Void)?
    public private(set) var isEditing = false
    var isDeleteControlVisible: Bool { deleteButton.alphaValue > 0 }

    /// 测试注入：覆盖 AccessibilitySettings.current()，用于触发 reduceTransparency 回退分支。
    internal var accessibilitySettingsProvider: () -> AccessibilitySettings = { .current() }

    private static let gridSize = 3
    private static let thumbnailSpacing: CGFloat = 2
    private var thumbnailGridWidthConstraint: NSLayoutConstraint?
    private var thumbnailGridHeightConstraint: NSLayoutConstraint?
    private var thumbnailSizeConstraints: [NSLayoutConstraint] = []
    private var thumbnailLeadingConstraints: [(NSLayoutConstraint, column: Int)] = []
    private var thumbnailBottomConstraints: [(NSLayoutConstraint, rowFromBottom: Int)] = []
    private(set) var configuredIconSize: CGFloat = 64
    var configuredThumbnailGridSize: CGSize {
        CGSize(
            width: thumbnailGridWidthConstraint?.constant ?? 0,
            height: thumbnailGridHeightConstraint?.constant ?? 0
        )
    }
    var configuredThumbnailSizes: [CGFloat] {
        thumbnailSizeConstraints.map(\.constant)
    }
    var configuredThumbnailBottomConstants: [CGFloat] {
        thumbnailBottomConstraints.map { $0.0.constant }
    }
    var configuredThumbnailFrames: [CGRect] {
        thumbnailImageViews.map(\.frame)
    }
    var configuredThumbnailGridBounds: CGRect {
        thumbnailGrid.bounds
    }

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
        ])

        let gridWidth = thumbnailGrid.widthAnchor.constraint(equalToConstant: 64)
        let gridHeight = thumbnailGrid.heightAnchor.constraint(equalToConstant: 64)
        thumbnailGridWidthConstraint = gridWidth
        thumbnailGridHeightConstraint = gridHeight
        NSLayoutConstraint.activate([
            thumbnailGrid.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            thumbnailGrid.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            gridWidth,
            gridHeight,
        ])

        NSLayoutConstraint.activate([
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
        setupDeleteButton()

        view.setAccessibilityRole(.button)
    }

    private func setupDeleteButton() {
        deleteButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Delete folder"
        )
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteFolderClicked)
        deleteButton.alphaValue = 0
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(deleteButton)
        NSLayoutConstraint.activate([
            deleteButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            deleteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    private func setupThumbnailGrid() {
        thumbnailImageViews.removeAll()
        thumbnailSizeConstraints.removeAll()
        thumbnailLeadingConstraints.removeAll()
        thumbnailBottomConstraints.removeAll()
        thumbnailGrid.subviews.forEach { $0.removeFromSuperview() }
        let thumbnailSize = (CGFloat(64) - 2 * Self.thumbnailSpacing) / 3

        for row in 0..<Self.gridSize {
            for column in 0..<Self.gridSize {
                let imageView = NSImageView()
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                thumbnailGrid.addSubview(imageView)
                let rowFromBottom = Self.gridSize - 1 - row
                let leading = imageView.leadingAnchor.constraint(
                    equalTo: thumbnailGrid.leadingAnchor,
                    constant: CGFloat(column) * (thumbnailSize + Self.thumbnailSpacing)
                )
                let bottomInset = CGFloat(rowFromBottom)
                    * (thumbnailSize + Self.thumbnailSpacing)
                let bottom = imageView.bottomAnchor.constraint(
                    equalTo: thumbnailGrid.bottomAnchor,
                    constant: -bottomInset
                )
                let width = imageView.widthAnchor.constraint(equalToConstant: thumbnailSize)
                let height = imageView.heightAnchor.constraint(equalToConstant: thumbnailSize)
                NSLayoutConstraint.activate([leading, bottom, width, height])
                thumbnailImageViews.append(imageView)
                thumbnailSizeConstraints.append(contentsOf: [width, height])
                thumbnailLeadingConstraints.append((leading, column))
                thumbnailBottomConstraints.append((bottom, rowFromBottom))
            }
        }
    }

    // MARK: - Configuration

    public func configure(
        item: PageItem,
        childIcons: [NSImage],
        iconSize: CGFloat = 64
    ) {
        let thumbnailSpacing: CGFloat = 2
        let thumbnailSize = max(0, (iconSize - 2 * thumbnailSpacing) / 3)
        configuredIconSize = iconSize
        thumbnailGridWidthConstraint?.constant = iconSize
        thumbnailGridHeightConstraint?.constant = iconSize
        thumbnailSizeConstraints.forEach { $0.constant = thumbnailSize }
        thumbnailLeadingConstraints.forEach { constraint, column in
            constraint.constant = CGFloat(column) * (thumbnailSize + thumbnailSpacing)
        }
        thumbnailBottomConstraints.forEach { constraint, rowFromBottom in
            let bottomInset = CGFloat(rowFromBottom)
                * (thumbnailSize + thumbnailSpacing)
            constraint.constant = -bottomInset
        }

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
        setEditing(false)
        titleLabel.stringValue = ""
        titleLabel.isEditable = false
        thumbnailImageViews.forEach { $0.image = nil }
    }

    public func setEditing(_ editing: Bool) {
        isEditing = editing
        deleteButton.alphaValue = editing ? 1 : 0
    }

    @objc private func deleteFolderClicked() {
        onDelete?()
    }

    func performDeleteForTesting() {
        deleteFolderClicked()
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
