import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 文件夹展开浮动面板
/// 当用户点击文件夹时弹出，显示文件夹内的应用
/// 本视图覆盖整个父视图，backgroundView 为实际面板，
/// 点击面板外区域（即本视图背景区域）可关闭文件夹
/// 支持内部分页（最多 35 个/页），超出时显示页码点
public class FolderOverlayView: NSView {

    /// 每页最大项目数
    static let maxItemsPerPage = 35

    /// 点击文件夹内某个应用时的回调
    public var onAppSelected: ((PageItem) -> Void)?

    /// 关闭文件夹的回调
    public var onClosed: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let backgroundView = NSVisualEffectView()
    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var pageControlView: PageControlView!
    private let pageControlViewModel = PageControlViewModel()
    private var childItems: [PageItem] = []
    private var pages: [[PageItem]] = []
    private var iconCache: IconCache?
    private var backgroundWidthConstraint: NSLayoutConstraint?
    private var backgroundHeightConstraint: NSLayoutConstraint?

    // MARK: - Page Splitting (pure function, testable)

    /// 将 items 按 pageSize 拆分为多页
    nonisolated public static func paginateItems(_ items: [PageItem], pageSize: Int) -> [[PageItem]] {
        guard !items.isEmpty, pageSize > 0 else { return [] }
        return stride(from: 0, to: items.count, by: pageSize).map { start in
            Array(items[start..<min(start + pageSize, items.count)])
        }
    }

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
        // Background with frosted glass — 作为实际面板
        backgroundView.blendingMode = .behindWindow
        backgroundView.material = .hudWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = backgroundView.widthAnchor.constraint(equalToConstant: 320)
        let heightConstraint = backgroundView.heightAnchor.constraint(equalToConstant: 360)
        backgroundWidthConstraint = widthConstraint
        backgroundHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthConstraint,
            heightConstraint,
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

        // Collection view for folder contents — horizontal paging layout
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 72, height: 80)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.scrollDirection = .horizontal
        // 每个 section 代表一页，section 间距为 0 实现连续翻页
        layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true

        scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.drawsBackground = false
        backgroundView.addSubview(scrollView)

        collectionView.register(AppIconCell.self, forItemWithIdentifier: AppIconCell.identifier)

        // Page control dots — 底部居中
        pageControlView = PageControlView(viewModel: pageControlViewModel)
        pageControlView.onDotSelected = { [weak self] pageIndex in
            self?.navigateToPage(pageIndex)
        }
        backgroundView.addSubview(pageControlView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        pageControlView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: pageControlView.topAnchor, constant: -8),
            pageControlView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 12),
            pageControlView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -12),
            pageControlView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -12),
            pageControlView.heightAnchor.constraint(equalToConstant: 12),
        ])

        alphaValue = 0
        isHidden = true
    }

    // MARK: - Open / Close

    public func openFolder(item: PageItem, childItems: [PageItem], iconCache: IconCache?) {
        self.childItems = childItems
        self.iconCache = iconCache
        self.pages = Self.paginateItems(childItems, pageSize: Self.maxItemsPerPage)
        titleLabel.stringValue = item.group?.title ?? "Folder"

        // 响应式尺寸：60% 屏幕宽度，最大 70% 屏幕高度
        if let screen = NSScreen.main {
            let screenWidth = screen.frame.width
            let screenHeight = screen.frame.height
            let targetWidth = min(screenWidth * 0.6, 800)
            let targetHeight = min(screenHeight * 0.7, 600)
            backgroundWidthConstraint?.constant = targetWidth
            backgroundHeightConstraint?.constant = targetHeight
        }

        // 配置页码控制
        pageControlViewModel.configure(totalPages: pages.count)
        pageControlView.update()

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.reloadData()

        // 注册滚动位置监听，同步页码指示器
        observeScrollPosition()

        isHidden = false

        // Scale 弹出动画（Task 4.2）— 使用 AnimationRunner 统一 Reduce Motion 处理
        AnimationRunner.animate(
            animation: AnimationConstants.folderExpand,
            normal: { [self] in
                backgroundView.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = AnimationConstants.folderExpand.duration
                    animator().alphaValue = 1
                })
                let spring = CASpringAnimation(keyPath: "transform.scale")
                spring.fromValue = 0.8
                spring.toValue = 1.0
                spring.damping = 0.8
                backgroundView.layer?.add(spring, forKey: "scaleIn")
            },
            reduced: { [self] in
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    animator().alphaValue = 1
                })
            }
        )
    }

    public func closeFolder() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = AnimationConstants.folderCollapse.duration
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
            self?.childItems = []
            self?.pages = []
            self?.onClosed?()
        })
    }

    // MARK: - Page Navigation

    private func navigateToPage(_ pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < pages.count else { return }
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let targetX = CGFloat(pageIndex) * pageWidth
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AnimationConstants.pageScroll.duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().bounds.origin.x = targetX
        }
        pageControlViewModel.currentPage = pageIndex
        pageControlView.update()
    }

    /// 从滚动位置更新当前页码
    private func updatePageFromScrollPosition() {
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let currentPage = Int(round(scrollView.contentView.bounds.origin.x / pageWidth))
        let clampedPage = max(0, min(currentPage, pages.count - 1))
        if clampedPage != pageControlViewModel.currentPage {
            pageControlViewModel.currentPage = clampedPage
            pageControlView.update()
        }
    }

    // MARK: - Click outside panel to close

    override public func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // 点击落在面板（backgroundView）外部则关闭
        let panelFrame = backgroundView.frame
        if !panelFrame.contains(location) {
            closeFolder()
        }
        super.mouseDown(with: event)
    }
}

// MARK: - NSCollectionViewDataSource

extension FolderOverlayView: NSCollectionViewDataSource {
    public func numberOfSections(in collectionView: NSCollectionView) -> Int {
        pages.count
    }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section < pages.count else { return 0 }
        return pages[section].count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let page = indexPath.section
        let index = indexPath.item
        guard page < pages.count, index < pages[page].count else {
            return NSCollectionViewItem()
        }
        let item = pages[page][index]
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
        let page = indexPath.section
        let index = indexPath.item
        guard page < pages.count, index < pages[page].count else { return }
        let item = pages[page][index]
        onAppSelected?(item)
    }
}

// MARK: - Scroll Notification

extension FolderOverlayView {
    /// 注册滚动位置变化监听，同步页码指示器
    public func observeScrollPosition() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updatePageFromScrollPosition()
        }
    }
}
#endif
