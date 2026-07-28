import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

struct FolderGridMetrics: Sendable, Equatable {
    let columns: Int
    let rows: Int
    let pageCapacity: Int
    let horizontalInset: CGFloat
}

public enum FolderDropDestination: Sendable, Equatable {
    case inside(ItemPlacement)
    case outside(ItemPlacement)
}

private final class ScrollObservationOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    var isObserving: Bool {
        lock.withLock { token != nil }
    }

    func replace(with newToken: NSObjectProtocol) {
        let oldToken = lock.withLock {
            let oldToken = token
            token = newToken
            return oldToken
        }
        if let oldToken {
            NotificationCenter.default.removeObserver(oldToken)
        }
    }

    func remove() {
        let oldToken = lock.withLock {
            let oldToken = token
            token = nil
            return oldToken
        }
        if let oldToken {
            NotificationCenter.default.removeObserver(oldToken)
        }
    }
}

/// 文件夹展开浮动面板
/// 当用户点击文件夹时弹出，显示文件夹内的应用
/// 本视图覆盖整个父视图，backgroundView 为实际面板，
/// 点击面板外区域（即本视图背景区域）可关闭文件夹
/// 支持内部分页（最多 35 个/页），超出时显示页码点
public class FolderOverlayView: NSView {

    nonisolated static let maximumFolderItemsPerPage = 35
    nonisolated static let folderItemWidth: CGFloat = 72
    nonisolated static let folderItemHeight: CGFloat = 80
    nonisolated static let folderItemSpacing: CGFloat = 8
    nonisolated static let minimumFolderHorizontalInset: CGFloat = 12
    nonisolated static let folderVerticalInset: CGFloat = 8

    /// 点击文件夹内某个应用时的回调
    public var onAppSelected: ((PageItem) -> Void)?

    /// 关闭文件夹的回调
    public var onClosed: (() -> Void)?

    /// 文件夹浮层内的拖放交互当前是否可用。
    public var isDragEnabled = true

    public var dragController: DragController?
    public var onDropRequested: ((DragSession, FolderDropDestination) -> Bool)?
    public var topLevelPlacementResolver: ((NSPoint) -> ItemPlacement?)?
    public private(set) var currentFolderID: Int64?
    private(set) var currentVisualPageIndex = 0
    private(set) var currentPageCapacity = 0
    private(set) var currentFolderGridMetrics: FolderGridMetrics?
    var folderViewportSizeProvider: (() -> CGSize)?
    var folderIndexPathResolver: ((NSPoint) -> IndexPath?)?
    var folderItemFrameResolver: ((IndexPath) -> NSRect?)?
    var scrollPositionDidUpdate: (() -> Void)?
    internal var pasteboardUUIDReader: (NSPasteboard) -> String? = {
        $0.string(forType: .string)
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let backgroundView = NSVisualEffectView()
    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var pageControlView: PageControlView!
    private let pageControlViewModel = PageControlViewModel()
    private var childItems: [PageItem] = []
    private var pages: [[PageItem]] = []
    private var iconCache: (any IconCaching)?
    private var projectedFolderViewportSize: CGSize?
    private var isReprojectingChildren = false
    private let scrollObservationOwner = ScrollObservationOwner()
    /// 测试注入：覆盖 AccessibilitySettings.current()，用于触发 reduced 动画分支
    internal var accessibilitySettingsProvider: () -> AccessibilitySettings = { .current() }
    /// 测试注入：驱动 closeFolder 动画完成回调，确定性覆盖 isHidden/onClosed 分支。
    internal var closeFolderCompletionRunner: (@escaping () -> Void) -> Void = { $0() }
    private var backgroundWidthConstraint: NSLayoutConstraint?
    private var backgroundHeightConstraint: NSLayoutConstraint?

    var folderCollectionView: NSCollectionView { collectionView }
    var folderScrollView: NSScrollView { scrollView }
    var folderPageControl: PageControlView { pageControlView }
    var isObservingScrollPosition: Bool { scrollObservationOwner.isObserving }

    // MARK: - Page Splitting (pure function, testable)

    /// 将 items 按 pageSize 拆分为多页
    nonisolated public static func paginateItems(_ items: [PageItem], pageSize: Int) -> [[PageItem]] {
        guard !items.isEmpty, pageSize > 0 else { return [] }
        return stride(from: 0, to: items.count, by: pageSize).map { start in
            Array(items[start..<min(start + pageSize, items.count)])
        }
    }

    nonisolated static func folderGridMetrics(
        forViewportSize rawSize: CGSize
    ) -> FolderGridMetrics {
        let width = rawSize.width.isFinite ? max(0, rawSize.width) : 0
        let height = rawSize.height.isFinite ? max(0, rawSize.height) : 0
        let availableWidth = max(
            0,
            width - 2 * minimumFolderHorizontalInset
        )
        let availableHeight = max(0, height - 2 * folderVerticalInset)
        let calculatedColumns = (availableWidth + folderItemSpacing)
            / (folderItemWidth + folderItemSpacing)
        let calculatedRows = (availableHeight + folderItemSpacing)
            / (folderItemHeight + folderItemSpacing)
        let fittingColumns = max(1, Int(min(
            CGFloat(maximumFolderItemsPerPage),
            calculatedColumns
        )))
        let fittingRows = max(1, Int(min(
            CGFloat(maximumFolderItemsPerPage),
            calculatedRows
        )))
        let capacity = min(
            maximumFolderItemsPerPage,
            fittingColumns * fittingRows
        )
        let layoutColumns = min(
            fittingColumns,
            max(1, (capacity + fittingRows - 1) / fittingRows)
        )
        let occupiedWidth = CGFloat(layoutColumns) * folderItemWidth
            + CGFloat(layoutColumns - 1) * folderItemSpacing
        return FolderGridMetrics(
            columns: layoutColumns,
            rows: fittingRows,
            pageCapacity: capacity,
            horizontalInset: max(
                minimumFolderHorizontalInset,
                (width - occupiedWidth) / 2
            )
        )
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

    deinit {
        scrollObservationOwner.remove()
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
        collectionView.registerForDraggedTypes([.string])
        registerForDraggedTypes([.string])

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

        closeFolderCompletionRunner = { [weak self] completion in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = AnimationConstants.folderCollapse.duration
                self?.animator().alphaValue = 0
            }, completionHandler: { completion() })
        }
    }

    // MARK: - Open / Close

    public func openFolder(
        item: PageItem,
        childItems: [PageItem],
        iconCache: (any IconCaching)?
    ) {
        currentFolderID = item.id
        currentVisualPageIndex = 0
        self.childItems = childItems.sorted {
            $0.ordering == $1.ordering
                ? $0.id < $1.id
                : $0.ordering < $1.ordering
        }
        self.iconCache = iconCache
        titleLabel.stringValue = item.group?.title ?? "Folder"

        // 响应式尺寸：基于 superview（多显示器正确），回退到 NSScreen.main
        let viewWidth = superview?.bounds.width ?? NSScreen.main?.frame.width ?? 800
        let viewHeight = superview?.bounds.height ?? NSScreen.main?.frame.height ?? 600
        let targetWidth = min(viewWidth * 0.6, 800)
        let targetHeight = min(viewHeight * 0.7, 600)
        backgroundWidthConstraint?.constant = targetWidth
        backgroundHeightConstraint?.constant = targetHeight

        collectionView.dataSource = self
        collectionView.delegate = self

        isHidden = false
        layoutSubtreeIfNeeded()
        reprojectChildren(resetCurrentPage: true, forceReload: true)
        observeScrollPosition()

        // Scale 弹出动画（Task 4.2）— 使用 AnimationRunner 统一 Reduce Motion 处理
        AnimationRunner.animate(
            settings: accessibilitySettingsProvider(),
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
        closeFolderCompletionRunner { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopObservingScrollPosition()
                self.currentVisualPageIndex = 0
                self.currentPageCapacity = 0
                self.currentFolderGridMetrics = nil
                self.projectedFolderViewportSize = nil
                self.currentFolderID = nil
                self.isHidden = true
                self.childItems = []
                self.pages = []
                self.onClosed?()
            }
        }
    }

    public func reloadChildren(_ children: [PageItem]) {
        childItems = children.sorted {
            $0.ordering == $1.ordering
                ? $0.id < $1.id
                : $0.ordering < $1.ordering
        }
        reprojectChildren(resetCurrentPage: false, forceReload: true)
    }

    private func reprojectChildren(
        resetCurrentPage: Bool,
        forceReload: Bool = false
    ) {
        guard !isReprojectingChildren else { return }
        let rawViewport = folderViewportSizeProvider?()
            ?? scrollView.contentView.bounds.size
        let viewport = CGSize(
            width: rawViewport.width.isFinite ? max(0, rawViewport.width) : 0,
            height: rawViewport.height.isFinite ? max(0, rawViewport.height) : 0
        )
        let metrics = Self.folderGridMetrics(forViewportSize: viewport)
        let capacity = metrics.pageCapacity
        guard forceReload
                || capacity != currentPageCapacity
                || viewport != projectedFolderViewportSize else { return }

        isReprojectingChildren = true
        defer { isReprojectingChildren = false }
        currentPageCapacity = capacity
        currentFolderGridMetrics = metrics
        projectedFolderViewportSize = viewport

        if let layout = collectionView.collectionViewLayout
            as? NSCollectionViewFlowLayout {
            layout.itemSize = NSSize(
                width: Self.folderItemWidth,
                height: Self.folderItemHeight
            )
            layout.minimumInteritemSpacing = Self.folderItemSpacing
            layout.minimumLineSpacing = Self.folderItemSpacing
            layout.sectionInset = NSEdgeInsets(
                top: Self.folderVerticalInset,
                left: metrics.horizontalInset,
                bottom: Self.folderVerticalInset,
                right: metrics.horizontalInset
            )
            layout.invalidateLayout()
        }

        pages = Self.paginateItems(childItems, pageSize: capacity)
        let requestedPage = resetCurrentPage ? 0 : currentVisualPageIndex
        currentVisualPageIndex = max(
            0,
            min(requestedPage, max(0, pages.count - 1))
        )
        pageControlViewModel.configure(totalPages: pages.count)
        pageControlViewModel.currentPage = currentVisualPageIndex
        pageControlView.update()
        collectionView.reloadData()
        collectionView.layoutSubtreeIfNeeded()
        if viewport.width > 0 {
            scrollView.contentView.scroll(to: NSPoint(
                x: CGFloat(currentVisualPageIndex) * viewport.width,
                y: 0
            ))
        }
    }

    override public func layout() {
        super.layout()
        guard !isHidden, currentFolderID != nil else { return }
        reprojectChildren(resetCurrentPage: false)
    }

    // MARK: - Page Navigation

    private func navigateToPage(_ pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < pages.count else { return }
        let pageWidth = scrollView.contentView.bounds.width
        guard pageWidth > 0 else { return }
        currentVisualPageIndex = pageIndex
        pageControlViewModel.currentPage = pageIndex
        pageControlView.update()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AnimationConstants.pageScroll.duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().bounds.origin.x =
                CGFloat(pageIndex) * pageWidth
        }
    }

    /// 从滚动位置更新当前页码
    func updatePageFromScrollPosition() {
        scrollPositionDidUpdate?()
        let pageWidth = scrollView.contentView.bounds.width
        guard pageWidth > 0 else { return }
        let page = Int(round(
            scrollView.contentView.bounds.origin.x / pageWidth
        ))
        let clamped = max(0, min(page, max(0, pages.count - 1)))
        currentVisualPageIndex = clamped
        if clamped != pageControlViewModel.currentPage {
            pageControlViewModel.currentPage = clamped
            pageControlView.update()
        }
    }

    func emptyPlacement(inVisualPage pageIndex: Int) -> ItemPlacement? {
        guard pageIndex >= 0, pageIndex < pages.count,
              let last = pages[pageIndex].last else { return nil }
        return .afterItem(itemID: last.id)
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

    override public func draggingEntered(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        let localPoint = convert(sender.draggingLocation, from: nil)
        return exteriorDestination(for: sender, at: localPoint) == nil ? [] : .move
    }

    override public func draggingUpdated(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        let localPoint = convert(sender.draggingLocation, from: nil)
        return exteriorDestination(for: sender, at: localPoint) == nil ? [] : .move
    }

    override public func prepareForDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        let localPoint = convert(sender.draggingLocation, from: nil)
        return exteriorDestination(for: sender, at: localPoint) != nil
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let localPoint = convert(sender.draggingLocation, from: nil)
        guard let (session, destination) = exteriorDestination(
            for: sender,
            at: localPoint
        ) else {
            dragController?.cancelDrag()
            return false
        }
        return performFolderDrop(session: session, destination: destination)
    }

    func performExteriorDrop(at localPoint: NSPoint) -> Bool {
        guard let session = dragController?.session,
              !backgroundView.frame.contains(localPoint),
              let placement = topLevelPlacementResolver?(localPoint) else {
            return false
        }
        return performFolderDrop(
            session: session,
            destination: .outside(placement)
        )
    }

    func performFolderDrop(
        session: DragSession,
        destination: FolderDropDestination
    ) -> Bool {
        guard isDragEnabled,
              session.sourceKind == .folderChild,
              session.sourceParentID == currentFolderID,
              destination.anchorItemID != session.itemID else {
            dragController?.cancelDrag()
            return false
        }
        return onDropRequested?(session, destination) ?? false
    }

    private func exteriorDestination(
        for draggingInfo: NSDraggingInfo,
        at localPoint: NSPoint
    ) -> (DragSession, FolderDropDestination)? {
        guard let session = activeFolderSession(from: draggingInfo),
              !backgroundView.frame.contains(localPoint),
              let placement = topLevelPlacementResolver?(localPoint),
              placement.anchorItemID != session.itemID else { return nil }
        return (session, .outside(placement))
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

        cell.configure(item: item, icon: nil)
        if let app = item.app, let iconCache {
            cell.loadIcon(from: iconCache, itemID: item.id, path: app.path)
        }
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

    public func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard isDragEnabled,
              let folderID = currentFolderID,
              pages.indices.contains(indexPath.section),
              pages[indexPath.section].indices.contains(indexPath.item) else {
            return nil
        }
        let item = pages[indexPath.section][indexPath.item]
        guard item.type == .app,
              item.parentId == folderID,
              UUID(uuidString: item.uuid) != nil,
              let visualIndex = childItems.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }

        dragController?.beginDrag(DragSession(
            itemID: item.id,
            itemUUID: item.uuid,
            itemType: item.type,
            sourceKind: .folderChild,
            sourceParentID: folderID,
            sourceVisualIndex: visualIndex
        ))
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.uuid, forType: .string)
        return pasteboardItem
    }

    public func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath:
            AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        let localPoint = collectionView.convert(
            draggingInfo.draggingLocation,
            from: nil
        )
        guard let session = activeFolderSession(from: draggingInfo),
              let destination = insideDestination(at: localPoint),
              destination.anchorItemID != session.itemID else {
            dragController?.updateDragHover(.empty)
            return []
        }
        dragController?.updateDragHover(.empty)
        dropOperation.pointee = .before
        return .move
    }

    public func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        let localPoint = collectionView.convert(
            draggingInfo.draggingLocation,
            from: nil
        )
        guard let session = activeFolderSession(from: draggingInfo),
              let destination = insideDestination(at: localPoint) else {
            dragController?.cancelDrag()
            return false
        }
        return performFolderDrop(session: session, destination: destination)
    }

    public func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        dragController?.finishDrag()
    }

    private func activeFolderSession(
        from draggingInfo: NSDraggingInfo
    ) -> DragSession? {
        guard isDragEnabled,
              let folderID = currentFolderID,
              let uuid = pasteboardUUIDReader(draggingInfo.draggingPasteboard),
              UUID(uuidString: uuid) != nil,
              let session = dragController?.session,
              session.itemUUID == uuid,
              session.itemType == .app,
              session.sourceKind == .folderChild,
              session.sourceParentID == folderID,
              childItems.contains(where: {
                  $0.id == session.itemID
                    && $0.uuid == uuid
                    && $0.parentId == folderID
              }) else { return nil }
        return session
    }

    private func insideDestination(
        at localPoint: NSPoint
    ) -> FolderDropDestination? {
        let indexPath: IndexPath?
        if let folderIndexPathResolver {
            indexPath = folderIndexPathResolver(localPoint)
        } else {
            indexPath = collectionView.indexPathForItem(at: localPoint)
        }
        guard let indexPath else {
            return emptyPlacement(
                inVisualPage: currentVisualPageIndex
            ).map { .inside($0) }
        }
        guard pages.indices.contains(indexPath.section),
              pages[indexPath.section].indices.contains(indexPath.item) else {
            return nil
        }
        let target = pages[indexPath.section][indexPath.item]
        let frame: NSRect?
        if let folderItemFrameResolver {
            frame = folderItemFrameResolver(indexPath)
        } else {
            frame = collectionView.collectionViewLayout?
                .layoutAttributesForItem(at: indexPath)?.frame
        }
        guard let frame else { return nil }
        return .inside(
            localPoint.x < frame.midX
                ? .beforeItem(itemID: target.id)
                : .afterItem(itemID: target.id)
        )
    }
}

// MARK: - Scroll Notification

extension FolderOverlayView {
    /// 注册滚动位置变化监听，同步页码指示器
    public func observeScrollPosition() {
        stopObservingScrollPosition()
        scrollView.contentView.postsBoundsChangedNotifications = true
        let token = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePageFromScrollPosition()
            }
        }
        scrollObservationOwner.replace(with: token)
    }

    private func stopObservingScrollPosition() {
        scrollObservationOwner.remove()
    }
}

extension FolderDropDestination {
    var anchorItemID: Int64 {
        switch self {
        case .inside(let placement), .outside(let placement):
            return placement.anchorItemID
        }
    }
}
#endif
