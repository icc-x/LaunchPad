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
    private let resultCountLabel = NSTextField(labelWithString: "")

    // MARK: - Dependencies

    private let storage: DataStoring
    private let iconCache: IconCache
    private let searchEngine: SearchEngine
    private let keyboardNavigator: KeyboardNavigator
    private let dragController: DragController
    private let folderController: FolderController
    private let searchScheduler: Scheduler

    // MARK: - State

    private var allPages: [PageItem] = []
    private var itemsByPage: [Int64: [PageItem]] = [:]
    private var currentSearchQuery: String = ""
    private var pageControlViewModel = PageControlViewModel()
    private var searchDebouncer: SearchDebouncer!
    private let searchQueue = DispatchQueue(label: "com.launchpad.search", qos: .userInitiated)

    // MARK: - Init

    public init(
        storage: DataStoring,
        iconCache: IconCache,
        searchEngine: SearchEngine = SearchEngine(),
        keyboardNavigator: KeyboardNavigator = KeyboardNavigator(),
        dragController: DragController,
        folderController: FolderController,
        searchScheduler: Scheduler = DispatchQueueScheduler()
    ) {
        self.storage = storage
        self.iconCache = iconCache
        self.searchEngine = searchEngine
        self.keyboardNavigator = keyboardNavigator
        self.dragController = dragController
        self.folderController = folderController
        self.searchScheduler = searchScheduler
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
        collectionView.dragController = dragController
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

        // 搜索结果计数标签（搜索时替换页码点）
        resultCountLabel.font = NSFont.systemFont(ofSize: 13, weight: .light)
        resultCountLabel.textColor = .secondaryLabelColor
        resultCountLabel.alignment = .center
        resultCountLabel.isHidden = true
        resultCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultCountLabel)

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

            // 搜索结果计数（与页码点同一位置）
            resultCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            resultCountLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),

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
        setupGestures()
        loadData()
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        collectionView.updateLayout(screenWidth: view.bounds.width)
    }

    // MARK: - Setup

    private func setupCallbacks() {
        // 搜索防抖：100ms debounce，空查询和 Backspace 立即触发
        searchDebouncer = SearchDebouncer(scheduler: searchScheduler) { [weak self] query in
            self?.handleSearch(query: query)
        }
        searchBar.onQueryChanged = { [weak self] query in
            self?.searchDebouncer.search(query: query)
        }

        // Collection view selection
        collectionView.onItemSelected = { [weak self] item in
            self?.handleItemSelection(item)
        }

        // 编辑模式删除
        collectionView.onItemDelete = { [weak self] item in
            self?.handleItemDelete(item)
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

    private func setupGestures() {
        // 长按手势：连接 DragController 编辑模式
        let longPress = NSPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: NSPressGestureRecognizer) {
        let location = gesture.location(in: collectionView)

        switch gesture.state {
        case .began:
            dragController.handlePressBegan(at: location)
        case .changed:
            dragController.handleDragMoved(to: location)
        case .ended, .cancelled, .failed:
            if dragController.state == .jiggling {
                // 长按结束时已在抖动状态 → 保持抖动（编辑模式）
                updateJiggleState()
            } else if dragController.state == .dragging {
                dragController.handleDrop()
                loadData()
            } else {
                dragController.handlePressEnded()
            }
        default:
            break
        }
    }

    /// 根据 DragController 状态更新所有可见 cell 的抖动
    private func updateJiggleState() {
        let snapshot = collectionView.diffableDataSource.snapshot()
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let cell = collectionView.item(at: indexPath) as? AppIconCell else { continue }
            if dragController.state == .jiggling {
                cell.startJiggling()
            } else {
                cell.stopJiggling()
            }
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
            // 空查询：主线程快速处理
            emptyStateView.hide()
            resultCountLabel.isHidden = true
            let allItems = allPages.map { itemsByPage[$0.id] ?? [] }
            pageControlViewModel.isSearchActive = false
            pageControl.update()
            collectionView.reload(pages: allItems, searchResults: nil, searchQuery: nil)
        } else {
            // 在主线程拷贝数据，避免 @MainActor 属性跨线程访问
            let allItems = allPages.flatMap { itemsByPage[$0.id] ?? [] }
            let capturedQuery = query
            let capturedSearchQuery = currentSearchQuery
            // 后台线程执行搜索，避免阻塞 UI
            searchQueue.async { [searchEngine] in
                let results = searchEngine.cachedSearch(items: allItems, query: capturedQuery)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // 仅当查询未过期时更新 UI
                    guard self.currentSearchQuery == capturedSearchQuery else { return }
                    if results.isEmpty {
                        self.emptyStateView.show()
                    } else {
                        self.emptyStateView.hide()
                    }
                    self.pageControlViewModel.isSearchActive = true
                    self.pageControl.update()
                    // 显示结果计数
                    self.resultCountLabel.stringValue = "\(results.count) results"
                    self.resultCountLabel.isHidden = false
                    self.collectionView.reload(pages: [[PageItem]](), searchResults: results, searchQuery: capturedQuery)
                }
            }
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
            if let bundleId = item.app?.bundleId {
                animateAppLaunch(item: item, bundleId: bundleId)
            }
        case .group:
            openFolder(item)
        case .page:
            break
        }
    }

    // MARK: - Item Deletion (Edit Mode)

    private func handleItemDelete(_ item: PageItem) {
        do {
            try storage.deleteItem(id: item.id)
            // 退出编辑模式
            dragController.handleCancel()
            updateJiggleState()
            // 重新加载数据
            loadData()
        } catch {
            NSLog("[LaunchPadViewController] Failed to delete item: \(error)")
        }
    }

    /// 三阶段启动动画：高亮反馈 → 放大淡出 → 启动应用
    private func animateAppLaunch(item: PageItem, bundleId: String) {
        let settings = AccessibilitySettings.current()

        // 找到对应的 cell
        guard let indexPath = collectionView.diffableDataSource.indexPath(for: item),
              let cell = collectionView.item(at: indexPath) else {
            // 找不到 cell，直接启动
            launchApp(bundleId: bundleId)
            return
        }

        if settings.reduceMotion {
            // Reduce Motion: 直接启动
            launchApp(bundleId: bundleId)
            return
        }

        let cellView = cell.view
        cellView.wantsLayer = true

        // 阶段 1: 高亮反馈 scale 0.95→1.0 (0.1s)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            cellView.animator().alphaValue = 0.8
        }, completionHandler: { [weak self] in
            // 阶段 2: 放大淡出 scale→2.0 + alpha→0 (0.3s)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = AnimationConstants.appLaunch.duration
                cellView.animator().alphaValue = 0
            })
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = 1.0
            zoom.toValue = 2.0
            zoom.duration = AnimationConstants.appLaunch.duration
            zoom.isRemovedOnCompletion = false
            zoom.fillMode = .forwards
            cellView.layer?.add(zoom, forKey: "zoomOut")

            // 阶段 3: 动画完成后启动应用
            DispatchQueue.main.asyncAfter(deadline: .now() + AnimationConstants.appLaunch.duration) {
                self?.launchApp(bundleId: bundleId)
                // 恢复 cell 状态
                cellView.layer?.removeAnimation(forKey: "zoomOut")
                cellView.alphaValue = 1
            }
        })
    }

    private func launchApp(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config)
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
            searchDebouncer.cancelPending()
            handleSearch(query: "")
        case .exitEditMode:
            break
        case .enterSearchMode:
            searchBar.show()
        case .appendToQuery(let char):
            searchBar.show()
            searchBar.stringValue += String(char)
            searchDebouncer.search(query: searchBar.stringValue)
        case .deleteLastCharacter:
            if !searchBar.stringValue.isEmpty {
                searchBar.stringValue.removeLast()
                // Backspace: 查询变短，debouncer 内部会立即触发
                searchDebouncer.search(query: searchBar.stringValue)
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
