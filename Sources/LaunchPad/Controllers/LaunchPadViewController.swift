import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

struct LayoutDropFailureEvent: Sendable, Equatable {
    let kind: String
    let sourceID: Int64
    let relatedIDs: [Int64]
    let category: String

    init(
        kind: String,
        sourceID: Int64,
        relatedIDs: [Int64],
        category: String
    ) {
        self.kind = kind
        self.sourceID = sourceID
        self.relatedIDs = relatedIDs
        self.category = category
    }

    init(intent: LayoutDropIntent) {
        category = "mutation_failed"
        switch intent {
        case .moveTopLevel(let itemID, let placement):
            kind = "move_top_level"
            sourceID = itemID
            relatedIDs = [placement.anchorItemID]
        case .addToFolder(let itemID, let folderID):
            kind = "add_to_folder"
            sourceID = itemID
            relatedIDs = [folderID]
        case .createFolder(let itemID, let targetItemID, _):
            kind = "create_folder"
            sourceID = itemID
            relatedIDs = [targetItemID]
        case .reorderFolderItem(let itemID, let folderID, let placement):
            kind = "reorder_folder_item"
            sourceID = itemID
            relatedIDs = [folderID, placement.anchorItemID]
        case .removeFromFolder(let itemID, let folderID, let placement):
            kind = "remove_from_folder"
            sourceID = itemID
            relatedIDs = [folderID, placement.anchorItemID]
        case .deleteFolder(let folderID):
            kind = "delete_folder"
            sourceID = folderID
            relatedIDs = []
        case .deleteApp(let itemID):
            kind = "delete_app"
            sourceID = itemID
            relatedIDs = []
        }
    }
}

/// 主视图控制器 — 协调所有子视图和控制器
/// 连接：KeyboardNavigator → SearchEngine → DiffableDataSource → NSCollectionView
///       DragController → drag-session preview lifecycle
///       LayoutRepository → FolderOverlayView
@MainActor
public class LaunchPadViewController: NSViewController {

    // MARK: - Sub-views

    private var scrollView: PageScrollView!
    private var collectionView: AppGridCollectionView!
    var searchBar: SearchBar!
    var pageControl: PageControlView!
    private var emptyStateView: EmptyStateView!
    var folderOverlay: FolderOverlayView!
    private(set) var transientMessageView: TransientMessageView!
    let resultCountLabel = NSTextField(labelWithString: "")

    // MARK: - Dependencies

    private let layoutRepository: any LayoutRepositoryProtocol
    private let iconCache: any IconCaching
    let keyboardNavigator: KeyboardNavigator
    let dragController: DragController
    private let applicationOpener: (URL) -> Void
    /// 窗口生命周期状态机（nil 时回退到 applicationOpener）
    public var lifecycle: WindowLifecycle?
    private let searchScheduler: Scheduler
    private(set) var gridInteractionCoordinator: AppGridInteractionCoordinator?

    // MARK: - Test injection points

    /// 无障碍设置提供器（默认读取系统，测试可注入 reduceMotion）
    var accessibilitySettingsProvider: () -> AccessibilitySettings = { .current() }

    /// 启动动画 cell 视图解析器（默认从 collectionView 取，测试可注入以绕过真实布局）
    var launchCellResolver: ((PageItem) -> NSView?)?

    /// 启动动画调度器（默认走 DispatchQueue.main.asyncAfter，测试可注入为同步执行）
    var launchAnimationScheduler: (
        TimeInterval,
        @escaping @MainActor @Sendable () -> Void
    ) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    /// 抖动状态注入点：可见 cell 的 indexPath 列表（默认从 collectionView 取，测试注入以驱动循环体）
    var visibleJiggleIndexPathsProvider: (() -> [IndexPath])?

    /// 抖动状态注入点：指定 indexPath 对应的 app/folder cell。
    var jiggleCellProvider: ((IndexPath) -> NSCollectionViewItem?)?

    /// 启动应用 URL 解析器（默认走 NSWorkspace，测试注入 fake URL 避免真实启动应用）
    var bundleURLResolver: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }

    /// 窗口关闭回调 — 由 AppDelegate/WindowController 注入，ESC 关闭窗口时调用
    public var onClose: (() -> Void)?

    var confirmFolderDeletion: (PageItem) -> Bool = { _ in
        let alert = NSAlert()
        alert.messageText = "删除文件夹？"
        alert.informativeText = "文件夹中的应用会移回主网格。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    var viewportSizeProvider: (() -> CGSize)?
    var projectedLayoutDidReload: (() -> Void)?
    var layoutDropFailureLogger: (LayoutDropFailureEvent) -> Void = { event in
        NSLog(
            "[LaunchPadViewController] layout_drop_failed kind=%@ source=%lld related=%@ category=%@",
            event.kind,
            event.sourceID,
            event.relatedIDs.map(String.init).joined(separator: ","),
            event.category
        )
    }
    var authoritativeLayoutReadFailureLogger: (String) -> Void = { category in
        NSLog(
            "[LaunchPadViewController] layout_reload_failed category=%@",
            category
        )
    }

    nonisolated static let searchTop: CGFloat = 20
    nonisolated static let searchHeight: CGFloat = 32
    nonisolated static let searchToGrid: CGFloat = 12
    nonisolated static let gridToPager: CGFloat = 8
    nonisolated static let pagerHeight: CGFloat = 10
    nonisolated static let pagerBottom: CGFloat = 20

    nonisolated static var gridChromeHeight: CGFloat {
        searchTop + searchHeight + searchToGrid
            + gridToPager + pagerHeight + pagerBottom
    }

    nonisolated static func gridViewportSize(
        forWindowContentSize size: CGSize
    ) -> CGSize {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height - gridChromeHeight) : 0
        return CGSize(width: width, height: height)
    }

    // MARK: - State

    private var allPages: [PageItem] = []
    private var itemsByPage: [Int64: [PageItem]] = [:]
    private(set) var authoritativeSnapshot: PersistedLayoutSnapshot?
    private var layoutLoadGeneration = 0
    private var isLayoutMutationInFlight = false
    private(set) var layoutMutationTask: Task<Bool, Never>?
    private(set) var gridMetrics: GridMetrics?
    private(set) var visualPages: [[PageItem]] = [[]]
    public private(set) var selectedItemID: Int64?
    private(set) var currentSearchResults: [PageItem] = []
    private(set) var currentSearchQuery: String = ""
    private(set) var searchRequestGeneration = 0
    private var pageControlViewModel = PageControlViewModel()
    private var searchDebouncer: SearchDebouncer!
    private let searchQueue = DispatchQueue(label: "com.launchpad.search", qos: .userInitiated)

    typealias SearchRunner = @MainActor @Sendable (
        [PageItem],
        String,
        @escaping @MainActor @Sendable ([PageItem]) -> Void
    ) -> Void

    lazy var searchRunner: SearchRunner = {
        [searchQueue] items, query, completion in
        searchQueue.async {
            let results = SearchEngine().search(items: items, query: query)
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

    init(
        layoutRepository: any LayoutRepositoryProtocol,
        iconCache: any IconCaching,
        keyboardNavigator: KeyboardNavigator = KeyboardNavigator(),
        dragController: DragController,
        applicationOpener: @escaping (URL) -> Void,
        searchScheduler: Scheduler = DispatchQueueScheduler()
    ) {
        self.layoutRepository = layoutRepository
        self.iconCache = iconCache
        self.keyboardNavigator = keyboardNavigator
        self.dragController = dragController
        self.applicationOpener = applicationOpener
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
        collectionView.configure(iconCache: iconCache)
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

        // Layout mutation feedback
        transientMessageView = TransientMessageView(frame: .zero)
        transientMessageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transientMessageView)

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
            searchBar.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.searchTop),
            searchBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchBar.widthAnchor.constraint(equalToConstant: 400),
            searchBar.heightAnchor.constraint(equalToConstant: Self.searchHeight),

            // Scroll view fills most of the space
            scrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Self.searchToGrid),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -Self.gridToPager),

            // Page control at bottom center
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.pagerBottom),
            pageControl.heightAnchor.constraint(equalToConstant: Self.pagerHeight),

            transientMessageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            transientMessageView.bottomAnchor.constraint(
                equalTo: pageControl.topAnchor,
                constant: -12
            ),
            transientMessageView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

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

        synchronizeDragAvailability()
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
        guard metrics != gridMetrics || collectionView.gridMetrics != metrics else { return }
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

        gridInteractionCoordinator?.onDropRequested = { [weak self] session, destination in
            guard let self,
                  let intent = self.makeGridIntent(
                      session: session,
                      destination: destination
                  ) else { return false }
            return self.applyDropIntent(intent)
        }

        scrollView.onPageChanged = { [weak self] page in
            guard let self else { return }
            pageControlViewModel.currentPage = page
            collectionView.setCurrentVisualPageIndex(page)
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

        // 文件夹重命名：连接 FolderCell.onRenamed → LayoutRepository.renameFolder
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
        folderOverlay.dragController = dragController
        folderOverlay.topLevelPlacementResolver = { [weak self] overlayPoint in
            guard let self else { return nil }
            let windowPoint = self.folderOverlay.convert(overlayPoint, to: nil)
            let gridPoint = self.collectionView.convert(windowPoint, from: nil)
            return self.gridInteractionCoordinator?
                .topLevelPlacement(atLocalPoint: gridPoint)
        }
        folderOverlay.onDropRequested = { [weak self] session, destination in
            self?.handleFolderDrop(
                session: session,
                destination: destination
            ) ?? false
        }
    }

    private func setupGestures() {
        // 长按手势：连接 DragController 编辑模式
        let longPress = NSPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
    }

    func makeGridIntent(
        session: DragSession,
        destination: GridDropDestination
    ) -> LayoutDropIntent? {
        guard session.sourceKind == .topLevel else { return nil }

        switch destination {
        case .placement(let placement):
            guard placement.anchorItemID != session.itemID else { return nil }
            return .moveTopLevel(itemID: session.itemID, placement: placement)
        case .onItem(let targetID, .app):
            guard session.itemType == .app, targetID != session.itemID else {
                return nil
            }
            return .createFolder(
                itemID: session.itemID,
                targetItemID: targetID,
                title: "New Folder"
            )
        case .onItem(let targetID, .group):
            guard session.itemType == .app, targetID != session.itemID else {
                return nil
            }
            return .addToFolder(itemID: session.itemID, folderID: targetID)
        case .onItem:
            return nil
        }
    }

    func makeFolderIntent(
        session: DragSession,
        destination: FolderDropDestination
    ) -> LayoutDropIntent? {
        guard session.sourceKind == .folderChild,
              session.itemType == .app,
              destination.anchorItemID != session.itemID else { return nil }
        switch destination {
        case .inside(let placement):
            return .reorderFolderItem(
                itemID: session.itemID,
                folderID: session.sourceParentID,
                placement: placement
            )
        case .outside(let placement):
            return .removeFromFolder(
                itemID: session.itemID,
                folderID: session.sourceParentID,
                placement: placement
            )
        }
    }

    @discardableResult
    func handleFolderDrop(
        session: DragSession,
        destination: FolderDropDestination
    ) -> Bool {
        guard let intent = makeFolderIntent(
            session: session,
            destination: destination
        ) else {
            dragController.cancelDrag()
            return false
        }

        return applyDropIntent(intent)
    }

    private func findItem(byId itemID: Int64) -> PageItem? {
        authoritativeSnapshot?.allItems.first { $0.id == itemID }
    }

    private var isSearchActive: Bool {
        if case .search = keyboardNavigator.mode { return true }
        return !currentSearchQuery.isEmpty
    }

    private func synchronizeDragAvailability() {
        let enabled = !isSearchActive
        if !enabled,
           gridInteractionCoordinator?.isDragEnabled == true
            || folderOverlay?.isDragEnabled == true {
            cancelActiveDrag()
        }
        if gridInteractionCoordinator?.isDragEnabled != enabled {
            gridInteractionCoordinator?.isDragEnabled = enabled
        }
        if folderOverlay?.isDragEnabled != enabled {
            folderOverlay?.isDragEnabled = enabled
        }
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
                // Native drag 由 AppKit 的 draggingSession ended 回调统一清理。
                if dragController.session == nil {
                    dragController.finishDrag()
                    loadData()
                }
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
            guard let cell = jiggleCellProvider?(indexPath)
                    ?? collectionView.item(at: indexPath) else { continue }
            if let appCell = cell as? AppIconCell {
                if jiggling { appCell.startJiggling() } else { appCell.stopJiggling() }
            } else if let folderCell = cell as? FolderCell {
                folderCell.setEditing(jiggling)
            }
        }
    }

    func cancelActiveDrag() {
        dragController.cancelDrag()
    }

    // MARK: - Data Loading

    @discardableResult
    public func loadData() -> Task<Void, Never> {
        layoutLoadGeneration += 1
        let generation = layoutLoadGeneration
        return Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await reloadAuthoritativeLayout(
                generation: generation,
                logRawError: true
            )
        }
    }

    @discardableResult
    private func reloadAuthoritativeLayout(
        generation: Int,
        logRawError: Bool
    ) async -> Bool {
        do {
            let snapshot = try await layoutRepository.load()
            guard generation == layoutLoadGeneration else { return false }
            applyAuthoritativeSnapshot(snapshot)
            return true
        } catch {
            guard generation == layoutLoadGeneration else { return false }
            if logRawError {
                NSLog("[LaunchPadViewController] Failed to load data: \(error)")
            } else {
                authoritativeLayoutReadFailureLogger("authoritative_read_failed")
            }
            return false
        }
    }

    private func applyAuthoritativeSnapshot(
        _ snapshot: PersistedLayoutSnapshot
    ) {
        authoritativeSnapshot = snapshot
        allPages = snapshot.pages
        itemsByPage = snapshot.pageChildren
        if currentSearchQuery.isEmpty {
            reloadProjectedLayout(preserving: selectedItemID)
        } else {
            scheduleSearch(query: currentSearchQuery)
        }

        guard isViewLoaded,
              let openFolderID = folderOverlay.currentFolderID else { return }
        if findItem(byId: openFolderID)?.type == .group {
            folderOverlay.reloadChildren(snapshot.folderChildren[openFolderID] ?? [])
        } else {
            folderOverlay.closeFolder()
        }
    }

    @discardableResult
    func applyDropIntent(_ intent: LayoutDropIntent) -> Bool {
        guard !isSearchActive,
              let capacity = gridMetrics?.itemsPerPage,
              !isLayoutMutationInFlight else { return false }

        isLayoutMutationInFlight = true
        let repository = layoutRepository
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            let mutationSucceeded: Bool
            do {
                try await repository.apply(intent, pageCapacity: capacity)
                mutationSucceeded = true
            } catch {
                mutationSucceeded = false
            }

            layoutLoadGeneration += 1
            let generation = layoutLoadGeneration
            _ = await reloadAuthoritativeLayout(
                generation: generation,
                logRawError: false
            )
            isLayoutMutationInFlight = false

            if mutationSucceeded {
                if case .deleteApp = intent {
                    dragController.handleCancel()
                    updateJiggleState()
                }
            } else {
                transientMessageView.show(message: "无法更新布局，请重试")
                layoutDropFailureLogger(LayoutDropFailureEvent(intent: intent))
            }
            return mutationSucceeded
        }
        layoutMutationTask = task
        return true
    }

    // MARK: - Search

    func handleSearch(query: String) {
        currentSearchQuery = query
        synchronizeDragAvailability()

        if query.isEmpty {
            searchRequestGeneration += 1
            emptyStateView.hide()
            resultCountLabel.isHidden = true
            currentSearchResults = []
            reloadProjectedLayout(preserving: selectedItemID)
        } else {
            scheduleSearch(query: query)
        }
    }

    /// 以当前权威布局发起搜索，并为相同 query 的乱序完成分配唯一代次。
    private func scheduleSearch(query: String) {
        searchRequestGeneration += 1
        let generation = searchRequestGeneration
        let allItems = allPages.flatMap { itemsByPage[$0.id] ?? [] }
        searchRunner(allItems, query) { [weak self] results in
            self?.applySearchResults(
                results,
                expectedQuery: query,
                expectedGeneration: generation
            )
        }
    }

    /// 在后台执行搜索（抽出便于同步测试，无需后台线程）
    func executeSearch(items: [PageItem], query: String) -> [PageItem] {
        SearchEngine().search(items: items, query: query)
    }

    /// 应用搜索结果到 UI（抽出便于同步测试，覆盖过期守卫与结果展示）
    func applySearchResults(
        _ results: [PageItem],
        expectedQuery: String,
        expectedGeneration: Int
    ) {
        guard currentSearchQuery == expectedQuery,
              searchRequestGeneration == expectedGeneration else { return }
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
            folderChildren: authoritativeSnapshot?.folderChildren ?? [:],
            animatingDifferences: false,
            reconfigureItems: true,
            animateEntrance: false
        )
        collectionView.setFolderCreationPreview(
            targetItemID: dragController.session?.folderCreationPreviewTargetID
        )
        let clampedPage = min(max(previousPage, 0), max(visualPages.count - 1, 0))
        pageControlViewModel.configure(totalPages: visualPages.count)
        pageControlViewModel.currentPage = clampedPage
        collectionView.setCurrentVisualPageIndex(clampedPage)
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
        collectionView.setCurrentVisualPageIndex(page)
        pageControl.update()
        scrollView.scrollToPage(page, animated: animated)
    }

    func navigateToPage(_ index: Int) {
        synchronizePage(to: index, animated: true)
    }

    private func handlePageChange(_ direction: DragPageDirection) {
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
                lifecycle?.handleAppClick(bundleId: bundleId)
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
        switch item.type {
        case .group:
            guard confirmFolderDeletion(item) else { return }
            _ = applyDropIntent(.deleteFolder(folderID: item.id))
        case .app:
            _ = applyDropIntent(.deleteApp(itemID: item.id))
        case .page:
            return
        }
    }

    /// 三阶段启动动画：高亮反馈 → 放大淡出 → 启动应用
    func animateAppLaunch(item: PageItem, bundleId: String) {
        let settings = accessibilitySettingsProvider()

        // Reduce Motion: lifecycle handles actual launch when available
        if settings.reduceMotion {
            if lifecycle == nil { launchApp(bundleId: bundleId) }
            return
        }

        // 找到对应的 cell 视图（注入优先，默认从 collectionView 解析；同行写法保证注入即覆盖）
        guard let cellView = resolveLaunchCellView(for: item) else {
            // 找不到 cell，lifecycle 负责实际启动
            if lifecycle == nil { launchApp(bundleId: bundleId) }
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
        if lifecycle == nil { launchApp(bundleId: bundleId) }
        cellView.layer?.removeAnimation(forKey: "zoomOut")
        cellView.alphaValue = 1
    }

    func launchApp(bundleId: String) {
        guard let url = bundleURLResolver(bundleId) else { return }
        launchApplication(at: url)
    }

    /// 将已解析的应用 URL 交付给进程边界；生产实现由 AppDelegate 注入。
    func launchApplication(at url: URL) {
        applicationOpener(url)
    }

    func openFolder(_ folderItem: PageItem) {
        guard let authoritativeFolder = findItem(byId: folderItem.id),
              authoritativeFolder.type == .group else { return }
        folderOverlay.openFolder(
            item: authoritativeFolder,
            childItems: authoritativeSnapshot?.folderChildren[folderItem.id] ?? [],
            iconCache: iconCache
        )
    }

    func handleFolderRename(item: PageItem, newTitle: String) {
        guard !isLayoutMutationInFlight else { return }
        isLayoutMutationInFlight = true
        let repository = layoutRepository
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            let renameSucceeded: Bool
            do {
                try await repository.renameFolder(item, newTitle: newTitle)
                renameSucceeded = true
            } catch {
                renameSucceeded = false
                NSLog("[LaunchPadViewController] Failed to rename folder")
            }
            layoutLoadGeneration += 1
            let generation = layoutLoadGeneration
            _ = await reloadAuthoritativeLayout(
                generation: generation,
                logRawError: false
            )
            isLayoutMutationInFlight = false
            return renameSucceeded
        }
        layoutMutationTask = task
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
            cancelActiveDrag()
            onClose?()
        case .clearSearch:
            guard isViewLoaded else { return }
            searchBar.hide()
            searchDebouncer.cancelPending()
            handleSearch(query: "")
        case .exitEditMode:
            cancelActiveDrag()
            updateJiggleState()
        case .enterSearchMode(let initialQuery):
            synchronizeDragAvailability()
            guard isViewLoaded else { return }
            searchBar.show()
            searchBar.stringValue = initialQuery
            searchBar.window?.makeFirstResponder(searchBar)
            searchDebouncer.search(query: initialQuery)
        case .appendToQuery(let char):
            synchronizeDragAvailability()
            guard isViewLoaded else { return }
            searchBar.show()
            searchBar.stringValue += String(char)
            searchDebouncer.search(query: searchBar.stringValue)
        case .deleteLastCharacter:
            synchronizeDragAvailability()
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
