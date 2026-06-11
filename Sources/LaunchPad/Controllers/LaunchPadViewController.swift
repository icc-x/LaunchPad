import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 主视图控制器 — 协调所有子视图和控制器
/// 连接：KeyboardNavigator → SearchEngine → DiffableDataSource → NSCollectionView
///       DragController → ItemWriting
///       FolderController → FolderOverlayView
@MainActor
public class LaunchPadViewController: NSViewController {

    // MARK: - Sub-views

    private var scrollView: PageScrollView!
    private var collectionView: AppGridCollectionView!
    private var searchBar: SearchBar!
    private var pageControl: PageControlView!
    private var emptyStateView: EmptyStateView!
    private var folderOverlay: FolderOverlayView!

    // MARK: - Dependencies

    private let storage: DataStoring
    private let iconCache: IconCache
    private let searchEngine: SearchEngine
    private let keyboardNavigator: KeyboardNavigator
    private let dragController: DragController
    private let folderController: FolderController

    // MARK: - State

    private var allPages: [PageItem] = []
    private var itemsByPage: [Int64: [PageItem]] = [:]
    private var currentSearchQuery: String = ""
    private var pageControlViewModel = PageControlViewModel()

    // MARK: - Init

    public init(
        storage: DataStoring,
        iconCache: IconCache,
        searchEngine: SearchEngine = SearchEngine(),
        keyboardNavigator: KeyboardNavigator = KeyboardNavigator(),
        dragController: DragController,
        folderController: FolderController
    ) {
        self.storage = storage
        self.iconCache = iconCache
        self.searchEngine = searchEngine
        self.keyboardNavigator = keyboardNavigator
        self.dragController = dragController
        self.folderController = folderController
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true

        // Scroll view (contains collection view)
        scrollView = PageScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Collection view
        collectionView = AppGridCollectionView(frame: .zero)
        collectionView.configure(iconCache: iconCache, storage: storage)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = collectionView

        // Search bar
        searchBar = SearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        // Page control
        pageControl = PageControlView(viewModel: pageControlViewModel)
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageControl)

        // Empty state
        emptyStateView = EmptyStateView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)

        // Folder overlay
        folderOverlay = FolderOverlayView()
        folderOverlay.translatesAutoresizingMaskIntoConstraints = false
        folderOverlay.isHidden = true
        view.addSubview(folderOverlay)

        // Layout
        NSLayoutConstraint.activate([
            // Search bar at top
            searchBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            searchBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchBar.widthAnchor.constraint(equalToConstant: 400),
            searchBar.heightAnchor.constraint(equalToConstant: 32),

            // Scroll view fills most of the space
            scrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -8),

            // Page control at bottom center
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            pageControl.heightAnchor.constraint(equalToConstant: 10),

            // Empty state centered
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // Folder overlay 覆盖整个视图（点击外部关闭功能需要）
            folderOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            folderOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            folderOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Configure grid layout
        collectionView.updateLayout(screenWidth: view.bounds.width > 0 ? view.bounds.width : 1440)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupCallbacks()
        loadData()
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        collectionView.updateLayout(screenWidth: view.bounds.width)
    }

    // MARK: - Setup

    private func setupCallbacks() {
        // Search bar
        searchBar.onQueryChanged = { [weak self] query in
            self?.handleSearch(query: query)
        }

        // Collection view selection
        collectionView.onItemSelected = { [weak self] item in
            self?.handleItemSelection(item)
        }

        // Page control
        pageControl.onDotSelected = { [weak self] pageIndex in
            self?.navigateToPage(pageIndex)
        }

        // Drag controller
        dragController.onPageChange = { [weak self] direction in
            self?.handlePageChange(direction)
        }

        dragController.onCreateGroup = { [weak self] targetId in
            self?.handleCreateGroup(targetId: targetId)
        }

        // Folder overlay
        folderOverlay.onAppSelected = { [weak self] item in
            self?.handleItemSelection(item)
        }

        folderOverlay.onClosed = { [weak self] in
            self?.folderOverlay.isHidden = true
        }
    }

    // MARK: - Data Loading

    public func loadData() {
        do {
            let layout = try LayoutPersistence.loadLayout(reader: storage)
            allPages = layout.pages
            itemsByPage = layout.itemsByPage

            let allItems = allPages.map { itemsByPage[$0.id] ?? [] }

            pageControlViewModel.configure(totalPages: allPages.count)
            pageControl.update()
            collectionView.reload(pages: allItems, searchResults: nil, searchQuery: nil)
        } catch {
            NSLog("[LaunchPadViewController] Failed to load data: \(error)")
        }
    }

    // MARK: - Search

    private func handleSearch(query: String) {
        currentSearchQuery = query

        if query.isEmpty {
            emptyStateView.hide()
            let allItems = allPages.map { itemsByPage[$0.id] ?? [] }
            pageControlViewModel.isSearchActive = false
            pageControl.update()
            collectionView.reload(pages: allItems, searchResults: nil, searchQuery: nil)
        } else {
            let allItems = allPages.flatMap { itemsByPage[$0.id] ?? [] }
            let results = searchEngine.cachedSearch(items: allItems, query: query)

            if results.isEmpty {
                emptyStateView.show()
            } else {
                emptyStateView.hide()
            }

            pageControlViewModel.isSearchActive = true
            pageControl.update()
            collectionView.reload(pages: [[PageItem]](), searchResults: results, searchQuery: query)
        }
    }

    // MARK: - Navigation

    private func navigateToPage(_ index: Int) {
        guard index >= 0 && index < allPages.count else { return }
        let pageWidth = scrollView.bounds.width
        let targetX = CGFloat(index) * pageWidth
        scrollView.contentView.scrollToVisible(NSRect(x: targetX, y: 0, width: pageWidth, height: 1))
        pageControlViewModel.currentPage = index
        pageControl.update()
    }

    private func handlePageChange(_ direction: DragController.PageChangeDirection) {
        let newPage: Int
        switch direction {
        case .forward:
            newPage = min(pageControlViewModel.currentPage + 1, pageControlViewModel.totalPages - 1)
        case .backward:
            newPage = max(pageControlViewModel.currentPage - 1, 0)
        }
        navigateToPage(newPage)
    }

    // MARK: - Item Selection

    private func handleItemSelection(_ item: PageItem) {
        switch item.type {
        case .app:
            if let bundleId = item.app?.bundleId,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        case .group:
            openFolder(item)
        case .page:
            break
        }
    }

    private func openFolder(_ folderItem: PageItem) {
        do {
            let children = try storage.fetchAllItems(parentId: folderItem.id)
                .sorted { $0.ordering < $1.ordering }
            folderOverlay.openFolder(item: folderItem, childItems: children, iconCache: iconCache)
        } catch {
            NSLog("[LaunchPadViewController] Failed to load folder contents: \(error)")
        }
    }

    private func handleCreateGroup(targetId: Int64) {
        // Find the target item and create a folder
        guard let targetItem = findItem(byId: targetId) else { return }

        let draggedItemIds = dragController.currentOrder
        guard draggedItemIds.count >= 2 else { return }

        // Find another item (not the target) to group with
        if let otherId = draggedItemIds.first(where: { $0 != targetId }),
           let otherItem = findItem(byId: otherId) {
            do {
                _ = try folderController.createFolder(from: otherItem, and: targetItem)
                loadData()
            } catch {
                NSLog("[LaunchPadViewController] Failed to create folder: \(error)")
            }
        }
    }

    private func findItem(byId id: Int64) -> PageItem? {
        for (_, items) in itemsByPage {
            if let item = items.first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }

    // MARK: - Keyboard

    public func handleKeyEvent(_ key: KeyboardNavigator.Key) -> KeyboardNavigator.Action {
        let action = keyboardNavigator.handleKey(key)
        executeAction(action)
        return action
    }

    public func handleCharacterInput(_ char: String) -> KeyboardNavigator.Action {
        let action = keyboardNavigator.handleCharacter(char)
        executeAction(action)
        return action
    }

    private func executeAction(_ action: KeyboardNavigator.Action) {
        switch action {
        case .closeWindow:
            break
        case .clearSearch:
            searchBar.hide()
            handleSearch(query: "")
        case .exitEditMode:
            break
        case .enterSearchMode:
            searchBar.show()
        case .appendToQuery(let char):
            searchBar.show()
            searchBar.stringValue += String(char)
            handleSearch(query: searchBar.stringValue)
        case .deleteLastCharacter:
            if !searchBar.stringValue.isEmpty {
                searchBar.stringValue.removeLast()
                handleSearch(query: searchBar.stringValue)
            }
        case .nextPage:
            handlePageChange(.forward)
        case .previousPage:
            handlePageChange(.backward)
        case .launchSelected, .launchFirstMatch:
            if let firstItem = collectionView.diffableDataSource.itemIdentifier(for: IndexPath(item: 0, section: 0)) {
                handleItemSelection(firstItem)
            }
        case .moveUp, .moveDown, .selectNext:
            break
        case .ignored:
            break
        }
    }
}
#endif
