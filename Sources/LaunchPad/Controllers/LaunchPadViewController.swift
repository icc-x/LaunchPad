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
    var searchBar: SearchBar!
    var pageControl: PageControlView!
    private var emptyStateView: EmptyStateView!
    var folderOverlay: FolderOverlayView!
    let resultCountLabel = NSTextField(labelWithString: "")

    // MARK: - Dependencies

    private let storage: DataStoring
    private let iconCache: IconCache
    private let searchEngine: SearchEngine
    let keyboardNavigator: KeyboardNavigator
    let dragController: DragController
    private let folderController: FolderController
    private let searchScheduler: Scheduler
    private(set) var gridInteractionCoordinator: AppGridInteractionCoordinator?

    // MARK: - Test injection points

    /// 无障碍设置提供器（默认读取系统，测试可注入 reduceMotion）
    var accessibilitySettingsProvider: () -> AccessibilitySettings = { .current() }

    /// 启动动画 cell 视图解析器（默认从 collectionView 取，测试可注入以绕过真实布局）
    var launchCellResolver: ((PageItem) -> NSView?)?

    /// 启动动画调度器（默认走 DispatchQueue.main.asyncAfter，测试可注入为同步执行）
    var launchAnimationScheduler: (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    /// 抖动状态注入点：可见 cell 的 indexPath 列表（默认从 collectionView 取，测试注入以驱动循环体）
    var visibleJiggleIndexPathsProvider: (() -> [IndexPath])?

    /// 抖动状态注入点：指定 indexPath 对应的 AppIconCell（默认从 collectionView 取，测试注入覆盖 startJiggling/stopJiggling）
    var jiggleCellProvider: ((IndexPath) -> AppIconCell?)?

    /// 启动应用 URL 解析器（默认走 NSWorkspace，测试注入 fake URL 避免真实启动应用）
    var bundleURLResolver: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }

    /// 窗口关闭回调 — 由 AppDelegate/WindowController 注入，ESC 关闭窗口时调用
    public var onClose: (() -> Void)?

    var viewportSizeProvider: (() -> CGSize)?
    var projectedLayoutDidReload: (() -> Void)?

    // MARK: - State

    private var allPages: [PageItem] = []
    private var itemsByPage: [Int64: [PageItem]] = [:]
    private(set) var gridMetrics: GridMetrics?
    private(set) var visualPages: [[PageItem]] = [[]]
    public private(set) var selectedItemID: Int64?
    private(set) var currentSearchResults: [PageItem] = []
    private(set) var currentSearchQuery: String = ""
    private var pageControlViewModel = PageControlViewModel()
    private var searchDebouncer: SearchDebouncer!
    private let searchQueue = DispatchQueue(label: "com.launchpad.search", qos: .userInitiated)

    typealias SearchRunner = @MainActor @Sendable (
        [PageItem],
        String,
        @escaping @MainActor @Sendable ([PageItem]) -> Void
    ) -> Void

    lazy var searchRunner: SearchRunner = {
        [searchQueue, searchEngine] items, query, completion in
        searchQueue.async {
            let results = searchEngine.cachedSearch(items: items, query: query)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(results) }
            }
        }
    }

    var currentVisualPage: Int { pageControlViewModel.currentPage }
    var pagingPageCount: Int { scrollView?.pagingPageCount ?? 1 }
    var gridSnapshot: AppGridCollectionView.Snapshot {
        collectionView.diffableDataSource.snapshot()
    }
    var selectedItemIndexPath: IndexPath? {
        guard let selectedItemID,
              let item = gridSnapshot.itemIdentifiers.first(where: {
                  $0.id == selectedItemID
              }) else { return nil }
        return collectionView.diffableDataSource.indexPath(for: item)
    }

    @available(*, deprecated, message: "Use selectedItemID")
    public var selectedIndex: Int? {
        guard isViewLoaded, let selectedItemID else { return nil }
        return gridSnapshot.itemIdentifiers.firstIndex {
            $0.id == selectedItemID
        }
    }

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
        // 不支持 NSCoding，返回 nil（可测且不崩溃）替代 fatalError
        return nil
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        gridInteractionCoordinator?.detach()
        view = NSView()
        view.wantsLayer = true

        // Scroll view (contains collection view)
        scrollView = PageScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Collection view
        collectionView = AppGridCollectionView(frame: .zero)
        collectionView.configure(iconCache: iconCache, storage: storage)
        let coordinator = AppGridInteractionCoordinator(
            dragController: dragController,
            pasteboardUUIDReader: { $0.string(forType: .string) }
        )
        gridInteractionCoordinator = coordinator
        coordinator.attach(to: collectionView)
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

    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupCallbacks()
        setupGestures()
        loadData()
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        let size = viewportSizeProvider?() ?? scrollView.contentView.bounds.size
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        let metrics = GridLayoutCalculator.calculate(viewportSize: size)
        guard metrics != gridMetrics else { return }
        gridMetrics = metrics
        collectionView.applyGridMetrics(metrics)
        reloadProjectedLayout(preserving: selectedItemID)
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

        // Collection view activation
        gridInteractionCoordinator?.onSelectionChanged = { [weak self] item in
            self?.selectedItemID = item.id
        }
        gridInteractionCoordinator?.onItemActivated = { [weak self] item in
            self?.handleItemSelection(item)
        }

        scrollView.onPageChanged = { [weak self] page in
            guard let self else { return }
            pageControlViewModel.currentPage = page
            pageControl.update()
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

        // 文件夹重命名：连接 FolderCell.onRenamed → FolderController.renameFolder
        collectionView.onFolderRenamed = { [weak self] item, newTitle in
            self?.handleFolderRename(item: item, newTitle: newTitle)
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

    @objc func handleLongPress(_ gesture: NSPressGestureRecognizer) {
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
    func updateJiggleState() {
        // 同步键盘导航器模式（不依赖视图加载状态）
        let jiggling = dragController.state == .jiggling
        keyboardNavigator.mode = jiggling ? .edit : .idle
        guard isViewLoaded else { return }
        for indexPath in visibleJiggleIndexPathsProvider?() ?? Array(collectionView.indexPathsForVisibleItems()) {
            guard let cell = jiggleCellProvider?(indexPath) ?? (collectionView.item(at: indexPath) as? AppIconCell) else { continue }
            if jiggling { cell.startJiggling() } else { cell.stopJiggling() }
        }
    }

    // MARK: - Data Loading

    public func loadData() {
        do {
            let layout = try LayoutPersistence.loadLayout(reader: storage)
            allPages = layout.pages
            itemsByPage = layout.itemsByPage
            reloadProjectedLayout(preserving: selectedItemID)
        } catch {
            NSLog("[LaunchPadViewController] Failed to load data: \(error)")
        }
    }

    // MARK: - Search

    func handleSearch(query: String) {
        currentSearchQuery = query

        if query.isEmpty {
            emptyStateView.hide()
            resultCountLabel.isHidden = true
            currentSearchResults = []
            reloadProjectedLayout(preserving: selectedItemID)
        } else {
            // 在主线程拷贝数据，避免 @MainActor 属性跨线程访问
            // 同样使用 compactMap（LayoutPersistence 已保证所有 page.id 都有 key）
            let allItems: [PageItem] = allPages.compactMap { page -> [PageItem]? in
                itemsByPage[page.id]
            }.flatMap { $0 }
            let capturedQuery = query
            let capturedSearchQuery = currentSearchQuery
            searchRunner(allItems, capturedQuery) { [weak self] results in
                self?.applySearchResults(
                    results,
                    query: capturedQuery,
                    expectedQuery: capturedSearchQuery
                )
            }
        }
    }

    /// 在后台执行搜索（抽出便于同步测试，无需后台线程）
    func executeSearch(items: [PageItem], query: String) -> [PageItem] {
        searchEngine.cachedSearch(items: items, query: query)
    }

    /// 应用搜索结果到 UI（抽出便于同步测试，覆盖过期守卫与结果展示）
    func applySearchResults(_ results: [PageItem], query: String, expectedQuery: String) {
        guard currentSearchQuery == expectedQuery else { return }
        currentSearchResults = results
        if results.isEmpty {
            emptyStateView.show()
        } else {
            emptyStateView.hide()
        }
        resultCountLabel.stringValue = "\(results.count) results"
        resultCountLabel.isHidden = false
        reloadProjectedLayout(preserving: selectedItemID)
    }

    private func reloadProjectedLayout(preserving itemID: Int64?) {
        guard let metrics = gridMetrics else { return }
        let isSearchActive = !currentSearchQuery.isEmpty
        visualPages = isSearchActive
            ? LayoutProjection.paginate(items: currentSearchResults, metrics: metrics)
            : LayoutProjection.project(
                pages: allPages,
                itemsByPage: itemsByPage,
                metrics: metrics
            )
        let previousPage = pageControlViewModel.currentPage
        collectionView.reload(
            pages: isSearchActive ? [] : visualPages,
            searchResults: isSearchActive ? currentSearchResults : nil,
            searchQuery: isSearchActive ? currentSearchQuery : nil,
            searchResultPages: isSearchActive ? visualPages : nil,
            animatingDifferences: false,
            reconfigureItems: true,
            animateEntrance: false
        )
        let clampedPage = min(max(previousPage, 0), max(visualPages.count - 1, 0))
        pageControlViewModel.configure(totalPages: visualPages.count)
        pageControlViewModel.currentPage = clampedPage
        pageControlViewModel.isSearchActive = isSearchActive
        pageControl.update()
        scrollView.configurePaging(
            pageWidth: metrics.pageWidth,
            pageCount: visualPages.count
        )
        scrollView.scrollToPage(clampedPage, animated: false)
        _ = selectItem(id: itemID)
        projectedLayoutDidReload?()
    }

    // MARK: - Navigation

    private func synchronizePage(to page: Int, animated: Bool) {
        guard isViewLoaded,
              page >= 0,
              page < visualPages.count else { return }
        pageControlViewModel.currentPage = page
        pageControl.update()
        scrollView.scrollToPage(page, animated: animated)
    }

    func navigateToPage(_ index: Int) {
        synchronizePage(to: index, animated: true)
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

    func handleItemSelection(_ item: PageItem) {
        _ = selectItem(id: item.id)
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

    @discardableResult
    func selectItem(id: Int64?) -> IndexPath? {
        let indexPath = collectionView.selectItem(id: id)
        selectedItemID = indexPath == nil ? nil : id
        if let indexPath {
            synchronizePage(to: indexPath.section, animated: false)
        }
        return indexPath
    }

    // MARK: - Item Deletion (Edit Mode)

    func handleItemDelete(_ item: PageItem) {
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
    func animateAppLaunch(item: PageItem, bundleId: String) {
        let settings = accessibilitySettingsProvider()

        // Reduce Motion: 直接启动（先于 cell 查找，便于无布局测试）
        if settings.reduceMotion {
            launchApp(bundleId: bundleId)
            return
        }

        // 找到对应的 cell 视图（注入优先，默认从 collectionView 解析；同行写法保证注入即覆盖）
        guard let cellView = resolveLaunchCellView(for: item) else {
            // 找不到 cell，直接启动
            launchApp(bundleId: bundleId)
            return
        }

        cellView.wantsLayer = true
        performLaunchHighlight(cellView: cellView)
        performLaunchZoom(cellView: cellView)
        scheduleLaunchCompletion(cellView: cellView, bundleId: bundleId)
    }

    /// 解析启动动画所需的 cell 视图：launchCellResolver 优先（无需 collectionView 已就绪，便于无布局测试），
    /// 默认从 collectionView 解析（可选链保证 collectionView 未加载时不崩溃）
    func resolveLaunchCellView(for item: PageItem) -> NSView? {
        if let resolved = launchCellResolver?(item) { return resolved }
        guard let indexPath = collectionView?.diffableDataSource?.indexPath(for: item) else { return nil }
        return collectionView?.item(at: indexPath)?.view
    }

    /// 阶段 1: 高亮反馈 scale 0.95→1.0 + alpha 0.8 (0.1s)
    func performLaunchHighlight(cellView: NSView) {
        cellView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            cellView.animator().alphaValue = 0.8
            let highlight = CABasicAnimation(keyPath: "transform.scale")
            highlight.fromValue = 0.95
            highlight.toValue = 1.0
            highlight.duration = 0.1
            cellView.layer?.add(highlight, forKey: "highlightScale")
        }
    }

    /// 阶段 2: 放大淡出 scale→2.0 + alpha→0 (0.3s)
    func performLaunchZoom(cellView: NSView) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AnimationConstants.appLaunch.duration
            cellView.animator().alphaValue = 0
        }
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.0
        zoom.toValue = 2.0
        zoom.duration = AnimationConstants.appLaunch.duration
        zoom.isRemovedOnCompletion = false
        zoom.fillMode = .forwards
        cellView.layer?.add(zoom, forKey: "zoomOut")
    }

    /// 阶段 3: 动画完成后启动应用（经注入调度器，测试可同步执行）
    func scheduleLaunchCompletion(cellView: NSView, bundleId: String) {
        launchAnimationScheduler(AnimationConstants.appLaunch.duration) { [weak self] in
            self?.completeLaunchAnimation(cellView: cellView, bundleId: bundleId)
        }
    }

    /// 启动应用并恢复 cell 状态（抽出便于同步测试）
    func completeLaunchAnimation(cellView: NSView, bundleId: String) {
        launchApp(bundleId: bundleId)
        cellView.layer?.removeAnimation(forKey: "zoomOut")
        cellView.alphaValue = 1
    }

    func launchApp(bundleId: String) {
        guard let url = bundleURLResolver(bundleId) else { return }
        launchApplication(at: url)
    }

    /// 实际启动应用（抽出便于测试：传入任意 URL 即覆盖 NSWorkspace 调用行，无需真实可启动应用）
    func launchApplication(at url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    func openFolder(_ folderItem: PageItem) {
        do {
            let children = try storage.fetchAllItems(parentId: folderItem.id)
                .sorted { $0.ordering < $1.ordering }
            folderOverlay.openFolder(item: folderItem, childItems: children, iconCache: iconCache)
        } catch {
            NSLog("[LaunchPadViewController] Failed to load folder contents: \(error)")
        }
    }

    func handleCreateGroup(targetId: Int64) {
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

    func handleFolderRename(item: PageItem, newTitle: String) {
        do {
            try folderController.renameFolder(item: item, newTitle: newTitle)
            loadData()
        } catch {
            NSLog("[LaunchPadViewController] Failed to rename folder: \(error)")
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
            onClose?()
        case .clearSearch:
            guard isViewLoaded else { return }
            searchBar.hide()
            searchDebouncer.cancelPending()
            handleSearch(query: "")
        case .exitEditMode:
            dragController.handleCancel()
            updateJiggleState()
        case .enterSearchMode:
            guard isViewLoaded else { return }
            searchBar.show()
        case .appendToQuery(let char):
            guard isViewLoaded else { return }
            searchBar.show()
            searchBar.stringValue += String(char)
            searchDebouncer.search(query: searchBar.stringValue)
        case .deleteLastCharacter:
            guard isViewLoaded else { return }
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
            guard isViewLoaded else { return }
            if let firstItem = collectionView.diffableDataSource.itemIdentifier(for: IndexPath(item: 0, section: 0)) {
                handleItemSelection(firstItem)
            }
        case .moveUp:
            moveSelection(.up)
        case .moveDown:
            moveSelection(.down)
        case .selectNext:
            moveSelection(.next)
        case .ignored:
            break
        }
    }

    // MARK: - Selection Navigation

    /// 方向键/Tab 移动选中位置
    private func moveSelection(_ direction: SelectionDirection) {
        guard isViewLoaded,
              let columns = gridMetrics?.columns,
              columns > 0 else { return }
        let snapshot = collectionView.diffableDataSource.snapshot()
        let items = snapshot.itemIdentifiers
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }
        let current = selectedItemID.flatMap { id in
            items.firstIndex(where: { $0.id == id })
        }
        let candidate: Int
        switch direction {
        case .down:
            candidate = current.map { $0 + columns } ?? 0
        case .up:
            guard let current else { return }
            candidate = current - columns
        case .next:
            candidate = (current ?? -1) + 1
        }
        guard items.indices.contains(candidate) else { return }
        _ = selectItem(id: items[candidate].id)
    }

    private enum SelectionDirection {
        case up
        case down
        case next
    }
}
#endif
