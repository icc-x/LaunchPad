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

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
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

    /// 图标入场动画：每个 cell 延迟 colIndex * 0.02s
    private func animateEntrance() {
        // Reduce Motion: 直接显示，无动画
        AnimationRunner.run(animation: AnimationConstants.iconEntrance) { [self] in
            let visibleItems = indexPathsForVisibleItems().sorted()
            for (index, indexPath) in visibleItems.enumerated() {
                guard let cell = item(at: indexPath) else { continue }
                let cellView = cell.view
                cellView.wantsLayer = true
                cellView.alphaValue = 0
                cellView.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)

                let delay = Double(index) * AnimationConstants.iconEntranceDelayPerColumn
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = AnimationConstants.iconEntrance.duration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    ctx.allowsImplicitAnimation = true
                    // 延迟后动画
                }, completionHandler: { [weak cellView] in
                    guard let cellView else { return }
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = AnimationConstants.iconEntrance.duration
                        cellView.animator().alphaValue = 1
                        cellView.layer?.transform = CATransform3DIdentity
                    }
                })
            }
        }
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

        // 按列数分组成行
        var rows: [[Any]] = []
        for strideStart in stride(from: 0, to: items.count, by: columns) {
            let rowEnd = min(strideStart + columns, items.count)
            let rowItems = Array(strideStart..<rowEnd).compactMap { index -> Any? in
                let indexPath = IndexPath(item: index, section: 0)
                return self.item(at: indexPath)?.view
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
        if let targetIndexPath = collectionView.indexPathForItem(at: location),
           let targetItem = diffableDataSource.itemIdentifier(for: targetIndexPath),
           targetItem.type == .group {
            dragController?.updateDragHover(location: .overIcon(targetId: targetItem.id))
        } else {
            dragController?.updateDragHover(location: .empty)
        }

        dropOperation.pointee = .on
        return .move
    }

    /// 接受拖放，执行重排
    public func collectionView(_ collectionView: NSCollectionView,
                               acceptDrop draggingInfo: NSDraggingInfo,
                               indexPath: IndexPath,
                               dropOperation: NSCollectionView.DropOperation) -> Bool {
        // 从剪贴板提取拖拽 item 的 UUID
        guard let pasteboard = draggingInfo.draggingPasteboard.propertyList(forType: .string) as? String,
              let draggedItem = findItem(byUuid: pasteboard) else {
            return false
        }

        // 获取目标位置的 item
        guard let targetItem = diffableDataSource.itemIdentifier(for: indexPath) else {
            return false
        }

        // 如果拖到文件夹上，触发创建/添加到文件夹
        if targetItem.type == .group {
            dragController?.handleDrop()
            return true
        }

        // 同页重排：找到源和目标的索引，更新 DiffableDataSource
        var snapshot = diffableDataSource.snapshot()
        let section = snapshot.sectionIdentifier(containingItem: draggedItem)
            ?? snapshot.sectionIdentifier(containingItem: targetItem)

        if let section {
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
                               offset dragImageOffset: NSPoint) -> NSImage? {
        guard let indexPath = indexPaths.first,
              let cell = item(at: indexPath) else { return nil }

        let cellView = cell.view
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
