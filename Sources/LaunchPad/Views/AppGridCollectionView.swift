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

    private(set) var diffableDataSource: DataSource!
    private var iconCache: IconCache?

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
    }

    // MARK: - Public API

    public func configure(iconCache: IconCache) {
        self.iconCache = iconCache
    }

    /// Reload the grid with new data
    public func reload(pages: [[PageItem]], searchResults: [PageItem]?, searchQuery: String?) {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: searchResults,
            searchQuery: searchQuery
        )
        diffableDataSource.apply(snapshot, animatingDifferences: true)
    }

    /// Update layout parameters based on screen width
    public func updateLayout(screenWidth: CGFloat) {
        let params = GridLayoutCalculator.calculate(screenWidth: screenWidth)
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
            cell.configure(item: item, icon: icon)
            return cell

        case .group:
            let cell = collectionView.makeItem(withIdentifier: FolderCell.identifier, for: indexPath) as! FolderCell
            // For folder cells, we show placeholder thumbnails
            cell.configure(item: item, childIcons: [])
            return cell

        case .page:
            // Pages shouldn't appear as items in the grid
            let cell = collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath) as! AppIconCell
            cell.configure(item: item, icon: nil)
            return cell
        }
    }

    // MARK: - Selection

    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        let location = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: location) {
            let item = diffableDataSource.itemIdentifier(for: indexPath)
            if let item {
                onItemSelected?(item)
            }
        }
    }
}
#endif
