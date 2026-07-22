import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 主应用网格 CollectionView
/// 使用 NSDiffableDataSource 管理数据，支持分页和搜索模式
public class AppGridCollectionView: NSCollectionView {

    public typealias DataSource = NSCollectionViewDiffableDataSource<Section, PageItem>
    public typealias Snapshot = NSDiffableDataSourceSnapshot<Section, PageItem>

    /// 删除按钮点击回调（编辑模式下）
    public var onItemDelete: ((PageItem) -> Void)?

    /// 文件夹重命名回调
    public var onFolderRenamed: ((PageItem, String) -> Void)?

    private(set) var diffableDataSource: DataSource!
    private var iconCache: IconCaching?
    private var storage: DataStoring?
    private(set) var gridMetrics: GridMetrics?
    public private(set) var currentVisualPageIndex = 0
    private var previewedFolderTargetID: Int64?

    // MARK: - Test injection points（可选注入；未注入时回退到真实 collectionView 行为）

    /// 可见 cell 提供器（测试可注入以绕过真实布局；默认回退到 item(at:)）
    var visibleCellProvider: ((IndexPath) -> NSCollectionViewItem?)?

    /// 拖放位置 → indexPath 解析器（测试可注入；默认回退到 indexPathForItem(at:)）
    var indexPathResolver: ((NSPoint) -> IndexPath?)?

    /// 兼容布局 API 的 clip 尺寸读取边界；默认读取真实 enclosing scroll view。
    var clipViewSizeProvider: (() -> CGSize?)?

    /// accessibility 行构建时的 cell view 提供器（测试可注入；默认回退到 item(at:)?.view）
    var cellViewProvider: ((IndexPath) -> NSView?)?

    /// 入场动画调度器（测试可注入为同步执行；默认走 DispatchQueue.main.asyncAfter）
    var animationScheduler: ((TimeInterval, @escaping () -> Void) -> Void)?

    /// 可见 indexPath 提供器（测试可注入以驱动入场动画循环体；默认回退到 indexPathsForVisibleItems()）
    var visibleIndexPathsProvider: (() -> [IndexPath])?

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        // 不支持 NSCoding，返回 nil（可测且不崩溃）替代 fatalError
        return nil
    }

    /// Prevents AppKit from collapsing horizontally paged content to the clip width.
    override public func setFrameSize(_ newSize: NSSize) {
        var resolvedSize = newSize
        let contentWidth = collectionViewLayout?.collectionViewContentSize.width ?? 0
        if contentWidth.isFinite && contentWidth > 0 {
            resolvedSize.width = max(resolvedSize.width, contentWidth)
        }
        super.setFrameSize(resolvedSize)
    }

    private func setup() {
        // Flow layout
        let layout = AppGridFlowLayout()
        collectionViewLayout = layout

        // Appearance
        backgroundColors = [.clear]
        isSelectable = true
        allowsMultipleSelection = false

        // Register cells
        register(AppIconCell.self, forItemWithIdentifier: AppIconCell.identifier)
        register(FolderCell.self, forItemWithIdentifier: FolderCell.identifier)

        // Configure data source
        diffableDataSource = DataSource(collectionView: self) { [weak self] collectionView, indexPath, item in
            self?.configureCell(collectionView: collectionView, indexPath: indexPath, item: item)
        }

        // Enable drag source
        registerForDraggedTypes([.string])
    }

    /// 拖拽操作类型
    override public func draggingSession(_ session: NSDraggingSession,
                                          sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.move]
    }

    // MARK: - Public API

    public func configure(iconCache: IconCaching, storage: DataStoring? = nil) {
        self.iconCache = iconCache
        self.storage = storage
    }

    /// Reload the grid with new data.
    public func reload(
        pages: [[PageItem]],
        searchResults: [PageItem]?,
        searchQuery: String?,
        searchResultPages: [[PageItem]]? = nil,
        animatingDifferences: Bool = true,
        reconfigureItems: Bool = false,
        animateEntrance: Bool = true
    ) {
        setFolderCreationPreview(targetItemID: nil)
        var snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: searchResults,
            searchQuery: searchQuery,
            searchResultPages: searchResultPages
        )
        if reconfigureItems {
            let existingItems = Set(diffableDataSource.snapshot().itemIdentifiers)
            snapshot.reloadItems(
                snapshot.itemIdentifiers.filter(existingItems.contains)
            )
        }
        diffableDataSource.apply(
            snapshot,
            animatingDifferences: animatingDifferences
        )
        setCurrentVisualPageIndex(currentVisualPageIndex)

        // 图标入场动画：从左到右依次铺开
        if animateEntrance { self.animateEntrance() }
    }

    public func setCurrentVisualPageIndex(_ index: Int) {
        let pageCount = diffableDataSource.snapshot().sectionIdentifiers.reduce(into: 0) {
            if case .page = $1 { $0 += 1 }
        }
        currentVisualPageIndex = max(0, min(index, max(0, pageCount - 1)))
    }

    /// 图标入场动画：每个 cell 按列索引延迟 colIndex * 0.02s，从左到右铺开
    private func animateEntrance() {
        guard let columns = gridMetrics?.columns else { return }
        // Reduce Motion: AnimationRunner 自动回退为即时显示
        AnimationRunner.run(animation: AnimationConstants.iconEntrance) { [self] in
            let indexPaths = visibleIndexPathsProvider?() ?? Array(indexPathsForVisibleItems())
            for indexPath in indexPaths.sorted() {
                guard let cell = visibleCellProvider?(indexPath) ?? item(at: indexPath) else { continue }
                applyEntranceAnimation(to: cell, at: indexPath, columns: columns)
            }
        }
    }

    /// 单个 cell 的入场准备（抽出便于同步测试，无需真实布局）
    func applyEntranceAnimation(to cell: NSCollectionViewItem, at indexPath: IndexPath, columns: Int) {
        let cellView = cell.view
        cellView.wantsLayer = true
        cellView.alphaValue = 0
        cellView.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)

        // 按列索引延迟：同一列的 cell 同时动画
        let delay = entranceDelay(forItemAt: indexPath, columns: columns)
        animateCellAppear(cellView: cellView, delay: delay)
    }

    /// 单个 cell 的入场动画（延迟后执行，抽出便于同步测试闭包体）
    func animateCellAppear(cellView: NSView, delay: TimeInterval) {
        let block: () -> Void = { [weak self, weak cellView] in
            self?.applyCellAppearAnimation(cellView: cellView)
        }
        if let scheduler = animationScheduler {
            scheduler(delay, block)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
        }
    }

    /// 同步执行单个 cell 的入场动画主体（抽出便于测试）
    func applyCellAppearAnimation(cellView: NSView?) {
        guard let cellView else { return }
        // transform 使用 spring（damping=0.8）
        cellView.layer?.add(self.entranceSpringAnimation(), forKey: "entranceScale")
        // alpha 使用 NSAnimationContext
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AnimationConstants.iconEntrance.duration
            ctx.allowsImplicitAnimation = true
            cellView.animator().alphaValue = 1
        }
        // 动画结束后重置 transform：经调度器触发（未注入时回退到 DispatchQueue.main.asyncAfter）
        let block: () -> Void = { [weak self] in
            self?.finalizeCellAppear(cellView: cellView)
        }
        if let scheduler = animationScheduler {
            scheduler(AnimationConstants.iconEntrance.duration, block)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + AnimationConstants.iconEntrance.duration, execute: block)
        }
    }

    /// 入场动画结束后重置 transform（抽出便于测试）
    func finalizeCellAppear(cellView: NSView) {
        cellView.layer?.transform = CATransform3DIdentity
    }

    /// 入场动画延迟：按列索引计算（同一列的 cell 同时动画）
    func entranceDelay(forItemAt indexPath: IndexPath, columns: Int) -> TimeInterval {
        let colIndex = indexPath.item % max(columns, 1)
        return TimeInterval(colIndex) * AnimationConstants.iconEntranceDelayPerColumn
    }

    /// 入场 spring 动画（transform.scale，damping 来自 AnimationConstants.iconEntrance）
    /// timing 可注入以便覆盖非 spring 回退分支
    func entranceSpringAnimation(timing: AnimationConstants.Timing = AnimationConstants.iconEntrance.timing) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.8
        spring.toValue = 1.0
        spring.duration = AnimationConstants.iconEntrance.duration
        if case .spring(let damping) = timing {
            spring.damping = damping
        } else {
            spring.damping = 0.8
        }
        return spring
    }

    /// Applies authoritative grid metrics to layout and visible item content.
    public func applyGridMetrics(_ metrics: GridMetrics) {
        guard gridMetrics != metrics else { return }
        gridMetrics = metrics
        (collectionViewLayout as? AppGridFlowLayout)?.applyGridMetrics(metrics)

        var snapshot = diffableDataSource.snapshot()
        let items = snapshot.itemIdentifiers
        if !items.isEmpty {
            snapshot.reloadItems(items)
            diffableDataSource.apply(snapshot, animatingDifferences: false)
            reconfigureVisibleCells()
        }
    }

    /// Updates layout through the legacy screen-width API.
    @available(*, deprecated, message: "Use applyGridMetrics(_:)")
    public func updateLayout(screenWidth: CGFloat) {
        let clipSize = clipViewSizeProvider?()
            ?? enclosingScrollView?.contentView.bounds.size
            ?? .zero
        let width = clipSize.width.isFinite && clipSize.width > 0
            ? clipSize.width : screenWidth
        let height = clipSize.height.isFinite && clipSize.height > 0
            ? clipSize.height : 620
        applyGridMetrics(GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: width, height: height)
        ))
    }

    // MARK: - Cell Configuration

    private func configureCell(collectionView: NSCollectionView, indexPath: IndexPath, item: PageItem) -> NSCollectionViewItem {
        switch item.type {
        case .app:
            let cell = collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath) as! AppIconCell
            configureAppCell(cell, item: item)
            return cell

        case .group:
            let cell = collectionView.makeItem(withIdentifier: FolderCell.identifier, for: indexPath) as! FolderCell
            configureFolderCell(cell, item: item)
            return cell

        case .page:
            // Pages shouldn't appear as items in the grid
            let cell = collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath) as! AppIconCell
            cell.configure(item: item, icon: nil)
            return cell
        }
    }

    private func reconfigureVisibleCells() {
        for indexPath in indexPathsForVisibleItems() {
            guard let pageItem = diffableDataSource.itemIdentifier(for: indexPath),
                  let cell = item(at: indexPath) else { continue }
            switch (pageItem.type, cell) {
            case (.app, let appCell as AppIconCell):
                configureAppCell(appCell, item: pageItem)
            case (.group, let folderCell as FolderCell):
                configureFolderCell(folderCell, item: pageItem)
            case (.page, let appCell as AppIconCell):
                appCell.configure(item: pageItem, icon: nil)
            default:
                continue
            }
        }
    }

    private func configureAppCell(_ cell: AppIconCell, item: PageItem) {
        let icon = item.app.flatMap {
            iconCache?.icon(forItemId: item.id, path: $0.path)
        }
        cell.configure(
            item: item,
            icon: icon,
            iconSize: gridMetrics?.iconSize ?? 64
        )
        cell.onDelete = { [weak self] in
            self?.onItemDelete?(item)
        }
    }

    private func configureFolderCell(_ cell: FolderCell, item: PageItem) {
        let childIcons: [NSImage]
        if let storage,
           let children = try? storage.fetchAllItems(parentId: item.id) {
            childIcons = children.prefix(9).compactMap { child in
                guard let app = child.app else { return nil }
                return iconCache?.icon(forItemId: child.id, path: app.path)
            }
        } else {
            childIcons = []
        }
        cell.configure(
            item: item,
            childIcons: childIcons,
            iconSize: gridMetrics?.iconSize ?? 64
        )
        cell.onRenamed = { [weak self] newTitle in
            self?.onFolderRenamed?(item, newTitle)
        }
    }

    // MARK: - Accessibility

    override public func accessibilityRole() -> NSAccessibility.Role? {
        return .grid
    }

    override public func accessibilityLabel() -> String? {
        return "Application Grid"
    }

    override public func accessibilityRows() -> [Any]? {
        guard let columns = gridMetrics?.columns else { return [] }
        let snapshot = diffableDataSource.snapshot()
        let itemIndexPathsBySection = snapshot.sectionIdentifiers.map { section in
            snapshot.itemIdentifiers(inSection: section).compactMap {
                diffableDataSource.indexPath(for: $0)
            }
        }
        return buildAccessibilityRows(
            itemIndexPathsBySection: itemIndexPathsBySection,
            columns: columns
        )
    }

    /// 按 section 边界和列数构建 accessibility 行。
    func buildAccessibilityRows(
        itemIndexPathsBySection: [[IndexPath]],
        columns: Int
    ) -> [[Any]] {
        guard columns > 0 else { return [] }
        return itemIndexPathsBySection.flatMap { indexPaths in
            stride(from: 0, to: indexPaths.count, by: columns).compactMap { start in
                let end = min(start + columns, indexPaths.count)
                let views = indexPaths[start..<end].compactMap {
                    cellViewProvider?($0) ?? item(at: $0)?.view
                }
                return views.isEmpty ? nil : views
            }
        }
    }

    /// Selects an item by stable identifier and returns its current index path.
    @discardableResult
    func selectItem(id: Int64?) -> IndexPath? {
        guard let id,
              let item = diffableDataSource.snapshot().itemIdentifiers.first(
                where: { $0.id == id }
              ),
              let indexPath = diffableDataSource.indexPath(for: item) else {
            deselectItems(at: selectionIndexPaths)
            return nil
        }
        selectItems(at: [indexPath], scrollPosition: [])
        return indexPath
    }
}

extension AppGridCollectionView: AppGridInteractionHosting {
    var collectionViewForDelegateInstallation: NSCollectionView { self }
    var interactionVisibleRect: NSRect { visibleRect }
    var visualPageCount: Int {
        diffableDataSource.snapshot().sectionIdentifiers.reduce(into: 0) {
            if case .page = $1 { $0 += 1 }
        }
    }

    func section(at index: Int) -> Section? {
        let sections = diffableDataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(index) else { return nil }
        return sections[index]
    }

    func pageItem(at indexPath: IndexPath) -> PageItem? {
        diffableDataSource.itemIdentifier(for: indexPath)
    }

    func pageItem(id: Int64) -> PageItem? {
        diffableDataSource.snapshot().itemIdentifiers.first { $0.id == id }
    }

    func visualIndex(of item: PageItem) -> Int? {
        diffableDataSource.indexPath(for: item)?.section
    }

    func indexPath(forItemID itemID: Int64) -> IndexPath? {
        guard let item = pageItem(id: itemID) else { return nil }
        return diffableDataSource.indexPath(for: item)
    }

    func resolvedIndexPath(at point: NSPoint) -> IndexPath? {
        indexPathResolver?(point) ?? indexPathForItem(at: point)
    }

    func layoutFrame(at indexPath: IndexPath) -> NSRect? {
        collectionViewLayout?.layoutAttributesForItem(at: indexPath)?.frame
    }

    func emptyPlacement(inVisualPage pageIndex: Int) -> ItemPlacement? {
        let snapshot = diffableDataSource.snapshot()
        let section = Section.page(pageIndex)
        guard snapshot.sectionIdentifiers.contains(section),
              let last = snapshot.itemIdentifiers(inSection: section).last else {
            return nil
        }
        return .afterItem(itemID: last.id)
    }

    func dragImage(at indexPath: IndexPath) -> NSImage? {
        guard let cell = visibleCellProvider?(indexPath) ?? item(at: indexPath)
        else { return nil }
        return makeDragImage(from: cell.view)
    }

    func setFolderCreationPreview(targetItemID: Int64?) {
        if let oldID = previewedFolderTargetID,
           let oldItem = diffableDataSource.snapshot().itemIdentifiers.first(where: {
               $0.id == oldID
           }),
           let oldPath = diffableDataSource.indexPath(for: oldItem),
           let oldCell = (visibleCellProvider?(oldPath) ?? item(at: oldPath)) as? AppIconCell {
            oldCell.setFolderCreationPreviewVisible(false)
        }

        previewedFolderTargetID = targetItemID
        guard let targetItemID,
              let item = diffableDataSource.snapshot().itemIdentifiers.first(where: {
                  $0.id == targetItemID && $0.type == .app
              }),
              let path = diffableDataSource.indexPath(for: item),
              let cell = (visibleCellProvider?(path) ?? self.item(at: path)) as? AppIconCell else {
            return
        }
        cell.setFolderCreationPreviewVisible(true)
    }

    /// 由 cell view 生成半透明 64×64 拖拽预览图（抽出便于同步测试绘制逻辑）
    func makeDragImage(from cellView: NSView) -> NSImage {
        let size = cellView.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        cellView.draw(cellView.bounds)
        image.unlockFocus()

        // 缩放到 64×64 并设置半透明
        let dragSize = NSSize(width: 64, height: 64)
        let dragImage = NSImage(size: dragSize)
        dragImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: dragSize),
                   from: .zero,
                   operation: .copy,
                   fraction: 0.7)
        dragImage.unlockFocus()

        return dragImage
    }
}
#endif
