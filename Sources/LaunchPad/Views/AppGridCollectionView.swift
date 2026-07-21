import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 主应用网格 CollectionView
/// 使用 NSDiffableDataSource 管理数据，支持分页和搜索模式
public class AppGridCollectionView: NSCollectionView {

    public typealias DataSource = NSCollectionViewDiffableDataSource<Section, PageItem>
    public typealias Snapshot = NSDiffableDataSourceSnapshot<Section, PageItem>

    /// 项目选中回调
    public var onItemSelected: ((PageItem) -> Void)?

    /// 删除按钮点击回调（编辑模式下）
    public var onItemDelete: ((PageItem) -> Void)?

    /// 文件夹重命名回调
    public var onFolderRenamed: ((PageItem, String) -> Void)?

    /// 拖拽状态机（可选，用于拖拽支持）
    public var dragController: DragController?

    private(set) var diffableDataSource: DataSource!
    private var iconCache: IconCaching?
    private var storage: DataStoring?
    private var currentIconSize: CGFloat = 64

    // MARK: - Test injection points（可选注入；未注入时回退到真实 collectionView 行为）

    /// 可见 cell 提供器（测试可注入以绕过真实布局；默认回退到 item(at:)）
    var visibleCellProvider: ((IndexPath) -> NSCollectionViewItem?)?

    /// 拖放位置 → indexPath 解析器（测试可注入；默认回退到 indexPathForItem(at:)）
    var indexPathResolver: ((NSPoint) -> IndexPath?)?

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

        // Use delegate for selection (supports both mouse and keyboard)
        delegate = self

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

    /// Reload the grid with new data
    public func reload(pages: [[PageItem]], searchResults: [PageItem]?, searchQuery: String?) {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: searchResults,
            searchQuery: searchQuery
        )
        diffableDataSource.apply(snapshot, animatingDifferences: true)

        // 图标入场动画：从左到右依次铺开
        animateEntrance()
    }

    /// 图标入场动画：每个 cell 按列索引延迟 colIndex * 0.02s，从左到右铺开
    private func animateEntrance() {
        // Reduce Motion: AnimationRunner 自动回退为即时显示
        AnimationRunner.run(animation: AnimationConstants.iconEntrance) { [self] in
            let columns = GridLayoutCalculator.calculate(
                screenWidth: bounds.width > 0 ? bounds.width : 1440
            ).columns
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

    /// Update layout parameters based on screen width
    public func updateLayout(screenWidth: CGFloat) {
        let params = GridLayoutCalculator.calculate(screenWidth: screenWidth)
        currentIconSize = params.iconSize
        if let layout = collectionViewLayout as? AppGridFlowLayout {
            layout.applyGridParameters(params)
        }
    }

    // MARK: - Cell Configuration

    private func configureCell(collectionView: NSCollectionView, indexPath: IndexPath, item: PageItem) -> NSCollectionViewItem {
        switch item.type {
        case .app:
            let cell = collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath) as! AppIconCell
            var icon: NSImage?
            if let app = item.app {
                icon = iconCache?.icon(forItemId: item.id, path: app.path)
            }
            cell.configure(item: item, icon: icon, iconSize: currentIconSize)
            cell.onDelete = { [weak self] in
                self?.onItemDelete?(item)
            }
            return cell

        case .group:
            let cell = collectionView.makeItem(withIdentifier: FolderCell.identifier, for: indexPath) as! FolderCell
            // 加载文件夹子项图标
            var childIcons: [NSImage] = []
            if let storage {
                if let children = try? storage.fetchAllItems(parentId: item.id) {
                    childIcons = children.prefix(9).compactMap { child in
                        guard let app = child.app else { return nil }
                        return iconCache?.icon(forItemId: child.id, path: app.path)
                    }
                }
            }
            cell.configure(item: item, childIcons: childIcons)
            cell.onRenamed = { [weak self] newTitle in
                self?.onFolderRenamed?(item, newTitle)
            }
            return cell

        case .page:
            // Pages shouldn't appear as items in the grid
            let cell = collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath) as! AppIconCell
            cell.configure(item: item, icon: nil)
            return cell
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
        let snapshot = diffableDataSource.snapshot()
        let params = GridLayoutCalculator.calculate(screenWidth: bounds.width > 0 ? bounds.width : 1440)
        let columns = params.columns
        let items = snapshot.itemIdentifiers
        return buildAccessibilityRows(items: items, columns: columns)
    }

    /// 按列数将 item 分组成行（抽出便于测试，cell view 解析可注入）
    func buildAccessibilityRows(items: [PageItem], columns: Int) -> [[Any]] {
        // 按列数分组成行
        var rows: [[Any]] = []
        for strideStart in stride(from: 0, to: items.count, by: columns) {
            let rowEnd = min(strideStart + columns, items.count)
            let rowItems = Array(strideStart..<rowEnd).compactMap { index -> Any? in
                let indexPath = IndexPath(item: index, section: 0)
                return cellViewProvider?(indexPath) ?? item(at: indexPath)?.view
            }
            if !rowItems.isEmpty {
                rows.append(rowItems)
            }
        }
        return rows
    }
}

// MARK: - NSCollectionViewDelegate

extension AppGridCollectionView: NSCollectionViewDelegate {
    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.deselectAll(nil)
        guard let indexPath = indexPaths.first else { return }
        if let item = diffableDataSource.itemIdentifier(for: indexPath) {
            onItemSelected?(item)
        }
    }

    // MARK: - 拖拽支持

    /// 提供拖拽数据（item UUID 写入剪贴板）
    public func collectionView(_ collectionView: NSCollectionView,
                               pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let item = diffableDataSource.itemIdentifier(for: indexPath),
              item.type != .page else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.uuid, forType: .string)
        return pasteboardItem
    }

    /// 验证拖放位置
    public func collectionView(_ collectionView: NSCollectionView,
                               validateDrop draggingInfo: NSDraggingInfo,
                               proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                               dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let location = draggingInfo.draggingLocation
        let edgeWidth: CGFloat = 40

        // 边缘区域 → 通知 DragController 触发翻页
        if location.x < edgeWidth || location.x > collectionView.bounds.width - edgeWidth {
            dragController?.updateDragHover(location: .screenEdge)
            return .generic
        }

        // 检查是否悬停在图标上
        let hover = resolveHoverLocation(at: location)
        dragController?.updateDragHover(location: hover)

        dropOperation.pointee = .on
        return .move
    }

    /// 根据拖放位置解析悬停类型（抽出便于测试，indexPath 解析可注入）
    func resolveHoverLocation(at location: NSPoint) -> DragController.HoverLocation {
        guard let targetIndexPath = indexPathResolver?(location) ?? indexPathForItem(at: location),
              let targetItem = diffableDataSource.itemIdentifier(for: targetIndexPath),
              targetItem.type == .group else { return .empty }
        return .overIcon(targetId: targetItem.id)
    }

    /// 接受拖放，执行重排
    public func collectionView(_ collectionView: NSCollectionView,
                               acceptDrop draggingInfo: NSDraggingInfo,
                               indexPath: IndexPath,
                               dropOperation: NSCollectionView.DropOperation) -> Bool {
        // 从拖拽信息提取被拖拽 item，并解析目标位置 item（任一缺失即拒绝）
        guard let draggedItem = extractDraggedItem(from: draggingInfo),
              let targetItem = diffableDataSource.itemIdentifier(for: indexPath) else {
            return false
        }
        return performDrop(draggedItem: draggedItem, targetItem: targetItem)
    }

    /// 从拖拽信息中提取被拖拽的 item（抽出便于测试，无需真实剪贴板往返）
    func extractDraggedItem(from draggingInfo: NSDraggingInfo) -> PageItem? {
        guard let pasteboard = draggingInfo.draggingPasteboard.propertyList(forType: .string) as? String else {
            return nil
        }
        return findItem(byUuid: pasteboard)
    }

    /// 执行拖放重排/移动到文件夹（抽出便于测试，覆盖 group 与普通重排分支）
    func performDrop(draggedItem: PageItem, targetItem: PageItem) -> Bool {
        // 如果拖到文件夹上，触发创建/添加到文件夹
        if targetItem.type == .group {
            dragController?.handleDrop()
            return true
        }

        // 同页重排：找到源和目标的索引，更新 DiffableDataSource
        var snapshot = diffableDataSource.snapshot()
        if snapshot.sectionIdentifier(containingItem: draggedItem) != nil
            || snapshot.sectionIdentifier(containingItem: targetItem) != nil {
            // 移动 item 到目标位置之前
            snapshot.deleteItems([draggedItem])
            snapshot.insertItems([draggedItem], beforeItem: targetItem)
            diffableDataSource.apply(snapshot, animatingDifferences: true)
        }

        dragController?.handleDrop()
        return true
    }

    // MARK: - 拖拽预览

    /// 自定义拖拽预览：半透明图标
    public func collectionView(_ collectionView: NSCollectionView,
                               draggingImageForItemsAt indexPaths: Set<IndexPath>,
                               with event: NSEvent,
                               offset dragImageOffset: NSPointPointer) -> NSImage {
        guard let indexPath = indexPaths.first,
              let cell = visibleCellProvider?(indexPath) ?? item(at: indexPath) else { return NSImage() }
        return makeDragImage(from: cell.view)
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

    // MARK: - 辅助方法

    private func findItem(byUuid uuid: String) -> PageItem? {
        let snapshot = diffableDataSource.snapshot()
        return snapshot.itemIdentifiers.first { $0.uuid == uuid }
    }
}
#endif
