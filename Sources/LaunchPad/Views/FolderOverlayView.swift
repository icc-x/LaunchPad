import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 文件夹展开浮动面板
/// 当用户点击文件夹时弹出，显示文件夹内的应用
public class FolderOverlayView: NSView {

    /// 点击文件夹内某个应用时的回调
    public var onAppSelected: ((PageItem) -> Void)?

    /// 关闭文件夹的回调
    public var onClosed: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let backgroundView = NSVisualEffectView()
    private var collectionView: NSCollectionView!
    private var childItems: [PageItem] = []
    private var iconCache: IconCache?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Background with frosted glass
        backgroundView.blendingMode = .behindWindow
        backgroundView.material = .hudWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Title
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        backgroundView.addSubview(titleLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -12),
        ])

        // Collection view for folder contents
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 72, height: 80)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.scrollDirection = .vertical

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        backgroundView.addSubview(scrollView)

        collectionView.register(AppIconCell.self, forItemWithIdentifier: AppIconCell.identifier)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -12),
        ])

        alphaValue = 0
        isHidden = true
    }

    // MARK: - Open / Close

    public func openFolder(item: PageItem, childItems: [PageItem], iconCache: IconCache?) {
        self.childItems = childItems
        self.iconCache = iconCache
        titleLabel.stringValue = item.group?.title ?? "Folder"

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.reloadData()

        isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AnimationConstants.folderExpand.duration
            animator().alphaValue = 1
        }
    }

    public func closeFolder() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = AnimationConstants.folderCollapse.duration
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
            self?.childItems = []
            self?.onClosed?()
        })
    }

    // MARK: - Click outside to close

    override public func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if !bounds.contains(location) {
            closeFolder()
        }
        super.mouseDown(with: event)
    }
}

// MARK: - NSCollectionViewDataSource

extension FolderOverlayView: NSCollectionViewDataSource {
    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        childItems.count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = childItems[indexPath.item]
        let cell = collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath) as! AppIconCell

        var icon: NSImage?
        if let app = item.app {
            icon = iconCache?.icon(forItemId: item.id, path: app.path)
        }
        cell.configure(item: item, icon: icon)
        return cell
    }
}

// MARK: - NSCollectionViewDelegate

extension FolderOverlayView: NSCollectionViewDelegate {
    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.deselectAll(nil)
        guard let indexPath = indexPaths.first else { return }
        let item = childItems[indexPath.item]
        onAppSelected?(item)
    }
}
#endif
