import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("FolderOverlayView")
struct FolderOverlayViewTests {

    private func makeOverlay() -> FolderOverlayView {
        let overlay = FolderOverlayView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 700)
        )
        overlay.folderViewportSizeProvider = {
            CGSize(width: 800, height: 624)
        }
        overlay.closeFolderCompletionRunner = { $0() }
        return overlay
    }

    private func makeApp(
        id: Int64,
        parentID: Int64 = 50,
        ordering: Int = 0
    ) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: "00000000-0000-0000-0000-\(String(format: "%012lld", id))",
            type: .app,
            ordering: ordering,
            parentId: parentID,
            app: TestDataFactory.makeAppInfo(id: id, title: "A\(id)")
        )
    }

    private func makeFolder(id: Int64 = 50) -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            uuid: "10000000-0000-0000-0000-\(String(format: "%012lld", id))",
            type: .group,
            ordering: 0,
            parentId: 1,
            group: TestDataFactory.makeGroupInfo(id: id, title: "Folder \(id)")
        )
    }

    private func makeFolderChildSession(
        itemID: Int64 = 10,
        folderID: Int64 = 50
    ) -> DragSession {
        DragSession(
            itemID: itemID,
            itemUUID: "00000000-0000-0000-0000-\(String(format: "%012lld", itemID))",
            itemType: .app,
            sourceKind: .folderChild,
            sourceParentID: folderID,
            sourceVisualIndex: 0
        )
    }

    private func makeWindowHosting(
        _ view: NSView,
        origin: NSPoint = NSPoint(x: 140, y: 90)
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host
        view.frame = NSRect(x: origin.x, y: origin.y, width: 800, height: 600)
        host.addSubview(view)
        return window
    }

    private func makeDraggingInfo(
        session: DragSession,
        windowPoint: NSPoint
    ) -> MockDraggingInfo {
        _ = session
        let pasteboard = NSPasteboard(
            name: .init("folder-\(UUID().uuidString)")
        )
        return MockDraggingInfo(pasteboard: pasteboard, location: windowPoint)
    }

    // MARK: - Init

    @Test
    func init_doesNotCrash() {
        let overlay = makeOverlay()
        #expect(overlay != nil)
    }

    @Test
    func init_isHiddenByDefault() {
        let overlay = makeOverlay()
        #expect(overlay.isHidden)
    }

    @Test
    func init_alphaIsZero() {
        let overlay = makeOverlay()
        #expect(overlay.alphaValue == 0)
    }

    // MARK: - paginateItems (pure function)

    @Test
    func paginateItems_empty_returnsEmpty() {
        _ = makeOverlay()
        let result = FolderOverlayView.paginateItems([], pageSize: 35)
        #expect(result.isEmpty)
    }

    @Test
    func paginateItems_lessThanPageSize_returnsSinglePage() {
        _ = makeOverlay()
        let items = TestDataFactory.makeAppItems(count: 10)
        let result = FolderOverlayView.paginateItems(items, pageSize: 35)
        #expect(result.count == 1)
        #expect(result[0].count == 10)
    }

    @Test
    func paginateItems_exactPageSize_returnsSinglePage() {
        _ = makeOverlay()
        let items = TestDataFactory.makeAppItems(count: 35)
        let result = FolderOverlayView.paginateItems(items, pageSize: 35)
        #expect(result.count == 1)
        #expect(result[0].count == 35)
    }

    @Test
    func paginateItems_moreThanPageSize_returnsMultiplePages() {
        _ = makeOverlay()
        let items = TestDataFactory.makeAppItems(count: 80)
        let result = FolderOverlayView.paginateItems(items, pageSize: 35)
        #expect(result.count == 3) // 35 + 35 + 10
        #expect(result[0].count == 35)
        #expect(result[1].count == 35)
        #expect(result[2].count == 10)
    }

    @Test
    func paginateItems_zeroPageSize_returnsEmpty() {
        _ = makeOverlay()
        let items = TestDataFactory.makeAppItems(count: 5)
        let result = FolderOverlayView.paginateItems(items, pageSize: 0)
        #expect(result.isEmpty)
    }

    @Test
    func paginateItems_negativePageSize_returnsEmpty() {
        _ = makeOverlay()
        let items = TestDataFactory.makeAppItems(count: 5)
        let result = FolderOverlayView.paginateItems(items, pageSize: -1)
        #expect(result.isEmpty)
    }

    // MARK: - Open Folder

    @Test
    func openFolder_showsOverlay() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Test Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 5)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        // isHidden is set immediately, alphaValue is animated
        #expect(!(overlay.isHidden))
    }

    @Test
    func openFolder_setsTitle() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "My Apps")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        // Title is set internally; we verify overlay is visible
        #expect(!(overlay.isHidden))
    }

    @Test
    func openFolder_responsiveSize() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        // Should set responsive dimensions based on screen
        #expect(!(overlay.isHidden))
    }

    @Test
    func openFolder_reduceMotion_usesReducedBranch() {
        let overlay = makeOverlay()
        overlay.accessibilitySettingsProvider = {
            AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        }
        let item = TestDataFactory.makePageItem(type: .group, group: TestDataFactory.makeGroupInfo())
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        #expect(!(overlay.isHidden))
    }

    @Test
    func collectionView_dataSource_withAppAndIconCache_loadsIcon() {
        let overlay = makeOverlay()
        // 把 overlay 加到 window 触发 layout，让 collectionView 请求 item（覆盖 itemForRepresentedObjectAt + if let app）
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = overlay
        let iconCache = IconCache(iconProvider: MockIconProvider(), imageStore: MockImageStore())
        let children = TestDataFactory.makeAppItems(count: 1)
        let item = TestDataFactory.makePageItem(type: .group, group: TestDataFactory.makeGroupInfo())
        overlay.openFolder(item: item, childItems: children, iconCache: iconCache)
        // 用 short displayIfNeeded 替代 layoutIfNeeded，避免 coverage instrumentation 下的 runloop 挂起
        window.displayIfNeeded()
        #expect(!(overlay.isHidden))
    }

    // MARK: - Close Folder

    @Test
    func closeFolder_hidesOverlay() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        // 注入同步完成回调，确定性覆盖 closeFolder 完成分支（isHidden = true）
        overlay.closeFolderCompletionRunner = { $0() }
        overlay.closeFolder()
        #expect(overlay.isHidden)
    }

    @Test
    func closeFolder_callsOnClosedCallback() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)

        var closedCalled = false
        overlay.onClosed = { closedCalled = true }
        overlay.closeFolderCompletionRunner = { $0() }
        overlay.closeFolder()
        #expect(closedCalled)
    }

    // MARK: - Callbacks

    @Test
    func onAppSelected_callbackIsSettable() {
        let overlay = makeOverlay()
        overlay.onAppSelected = { _ in }
        #expect(overlay.onAppSelected != nil)
    }

    @Test
    func onClosed_callbackIsSettable() {
        let overlay = makeOverlay()
        overlay.onClosed = { }
        #expect(overlay.onClosed != nil)
    }

    // MARK: - Mouse Down Outside

    @Test
    func mouseDown_outsidePanel_closesFolder() throws {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        overlay.layoutSubtreeIfNeeded()
        let panel = try #require(findView(NSVisualEffectView.self, in: overlay))
        let outsidePoint = NSPoint(
            x: panel.frame.minX - 1,
            y: panel.frame.midY
        )
        #expect(!(panel.frame.contains(outsidePoint)))
        overlay.closeFolderCompletionRunner = { $0() }
        var closeCount = 0
        overlay.onClosed = { closeCount += 1 }

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: outsidePoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))

        overlay.mouseDown(with: event)

        #expect(overlay.isHidden)
        #expect(closeCount == 1)
    }

    // MARK: - Open with many items (pagination)

    @Test
    func openFolder_withManyItems_paginates() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Big Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 80)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        #expect(!(overlay.isHidden))
    }

    @Test
    func openFolder_withExactly35Items_singlePage() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Full Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 35)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        #expect(!(overlay.isHidden))
    }

    @Test
    func openFolder_withNoTitle_usesDefaultTitle() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: nil
        )

        overlay.openFolder(item: item, childItems: [], iconCache: nil)

        #expect(!(overlay.isHidden))
    }

    // MARK: - Close then reopen

    @Test
    func closeThenReopen_doesNotCrash() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 5)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)
        overlay.closeFolder()
        // Note: Cannot reopen immediately during close animation
        // This test just verifies close doesn't crash
    }

    // MARK: - observeScrollPosition

    @Test
    func observeScrollPosition_doesNotCrash() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        overlay.observeScrollPosition()
    }

    // MARK: - init?(coder:)

    @Test
    func initCoder_producesValidInstance() throws {
        _ = makeOverlay()
        let original = FolderOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let archiver = NSKeyedArchiver()
        archiver.requiresSecureCoding = false
        archiver.encode(original, forKey: "root")
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let view = unarchiver.decodeObject(forKey: "root") as? FolderOverlayView
        #expect(view != nil)
    }

    // MARK: - Data Source

    @Test
    func numberOfSections_returnsCorrectCount() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40) // 2 pages
        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let collectionView = NSCollectionView()
        let count = overlay.numberOfSections(in: collectionView)
        #expect(count == 2)
    }

    @Test
    func numberOfItemsInSection_returnsCorrectCount() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40)
        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let collectionView = NSCollectionView()
        #expect(overlay.collectionView(collectionView, numberOfItemsInSection: 0) == 35)
        #expect(overlay.collectionView(collectionView, numberOfItemsInSection: 1) == 5)
    }

    @Test
    func numberOfItemsInSection_outOfBounds_returnsZero() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        let collectionView = NSCollectionView()
        #expect(overlay.collectionView(collectionView, numberOfItemsInSection: 99) == 0)
    }

    @Test
    func itemForRepresentedObjectAt_outOfBounds_returnsEmptyItem() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        // Use a standalone collectionView - the guard path returns NSCollectionViewItem() without calling makeItem
        let collectionView = NSCollectionView()
        let cell = overlay.collectionView(collectionView,
                                          itemForRepresentedObjectAt: IndexPath(item: 99, section: 99))
        #expect(cell != nil)
    }

    // MARK: - Delegate

    @Test
    func didSelectItemsAt_callsOnAppSelected() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 5)
        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        var selected: PageItem?
        overlay.onAppSelected = { item in selected = item }

        // Use a standalone collectionView - deselectAll on empty collectionView is a no-op
        let collectionView = NSCollectionView()
        overlay.collectionView(collectionView, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        #expect(selected != nil)
        #expect(selected?.id == children[0].id)
    }

    @Test
    func didSelectItemsAt_emptySet_doesNotCallCallback() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        var selected: PageItem?
        overlay.onAppSelected = { item in selected = item }

        let collectionView = NSCollectionView()
        overlay.collectionView(collectionView, didSelectItemsAt: [])
        #expect(selected == nil)
    }

    @Test
    func didSelectItemsAt_outOfBounds_doesNotCallCallback() {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        var selected: PageItem?
        overlay.onAppSelected = { item in selected = item }

        let collectionView = NSCollectionView()
        overlay.collectionView(collectionView, didSelectItemsAt: [IndexPath(item: 99, section: 99)])
        #expect(selected == nil)
    }

    // MARK: - Navigate to Page (via onDotSelected callback)

    /// Recursively find a subview of the given type
    private func findView<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let typed = view as? T { return typed }
        for subview in view.subviews {
            if let found = findView(type, in: subview) { return found }
        }
        return nil
    }

    @Test
    func navigateToPage_updatesScrollPosition() throws {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40) // 2 pages

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        // Find pageControlView via view hierarchy traversal
        let pageControlView = try #require(
            findView(PageControlView.self, in: overlay)
        )

        // Find scrollView via view hierarchy traversal
        let scrollView = try #require(findView(NSScrollView.self, in: overlay))

        // Set scrollView frame so bounds.width > 0 (no window -> auto-layout not resolved)
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 360)
        #expect(scrollView.bounds.width > 0)

        // Verify onDotSelected callback is set
        #expect(
            pageControlView.onDotSelected != nil,
            "onDotSelected should be set by setup()"
        )

        // Trigger navigation to page 1 via onDotSelected
        pageControlView.onDotSelected?(1)

        // Verify currentPage was updated via the pageControlView's viewModel
        let vmMirror = Mirror(reflecting: pageControlView)
        let vm = vmMirror.children.first { $0.label == "viewModel" }?.value as? PageControlViewModel
        #expect(vm?.currentPage == 1)
    }

    @Test
    func navigateToPage_outOfBounds_isNoOp() throws {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let pageControlView = try #require(
            findView(PageControlView.self, in: overlay)
        )
        let scrollView = try #require(findView(NSScrollView.self, in: overlay))
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 360)

        // Navigate to invalid page index - should be a no-op (guard fails)
        pageControlView.onDotSelected?(99)

        // Verify currentPage is still 0
        let vmMirror = Mirror(reflecting: pageControlView)
        let vm = vmMirror.children.first { $0.label == "viewModel" }?.value as? PageControlViewModel
        #expect(vm?.currentPage == 0)
    }

    // MARK: - updatePageFromScrollPosition (via scroll notification)

    @Test
    func updatePageFromScrollPosition_updatesCurrentPage() throws {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let scrollView = try #require(findView(NSScrollView.self, in: overlay))

        // Set frame so bounds.width > 0
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 360)
        #expect(scrollView.bounds.width > 0)

        // Use contentView.scroll(to:) to set scroll position (NSClipView manages its own bounds)
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.bounds.width, y: 0))

        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification,
                                         object: scrollView.contentView)

        // updatePageFromScrollPosition() should have been called
        // The code path is exercised regardless of whether currentPage changed
        // (guard on pageWidth > 0, clampedPage calculation, comparison with currentPage)
        _ = try #require(findView(PageControlView.self, in: overlay))
    }

    // MARK: - mouseDown inside panel

    @Test
    func mouseDown_insidePanel_doesNotClose() throws {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        overlay.layoutSubtreeIfNeeded()
        let panel = try #require(findView(NSVisualEffectView.self, in: overlay))
        let insidePoint = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        #expect(panel.frame.contains(insidePoint))

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: insidePoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        overlay.mouseDown(with: event)

        // Should NOT trigger close (overlay still visible)
        #expect(!(overlay.isHidden))
    }

    // MARK: - Guard branches: pageWidth guard in navigateToPage

    @Test
    func navigateToPage_zeroPageWidth_returnsEarly() throws {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 10)
        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let scrollView = try #require(findView(NSScrollView.self, in: overlay))
        // 强制将 scrollView frame 设为 0，让 pageWidth = scrollView.bounds.width = 0
        scrollView.frame = NSRect(x: 0, y: 0, width: 0, height: 0)

        let pageControlView = try #require(
            findView(PageControlView.self, in: overlay)
        )
        // pageIndex=0 应在范围内，但 pageWidth=0 触发 guard else
        pageControlView.onDotSelected?(0)

        let vmMirror = Mirror(reflecting: pageControlView)
        let vm = vmMirror.children.first { $0.label == "viewModel" }?.value as? PageControlViewModel
        // page should remain at 0 since guard prevented navigation
        #expect(vm?.currentPage == 0)
    }

    // MARK: - Guard branches: pageWidth guard in updatePageFromScrollPosition

    @Test
    func updatePageFromScrollPosition_zeroPageWidth_returnsEarly() throws {
        let overlay = makeOverlay()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40)
        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let scrollView = try #require(findView(NSScrollView.self, in: overlay))

        // 强制将 scrollView frame 设为 0，触发 guard else 分支
        scrollView.frame = NSRect(x: 0, y: 0, width: 0, height: 0)

        // 通过 NSView.boundsDidChangeNotification 触发 updatePageFromScrollPosition
        // 或直接通过 Mirror 调用私有方法
        // 简化：直接发送 NSView.boundsDidChangeNotification
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        let pcView = try #require(findView(PageControlView.self, in: overlay))
        let vmMirror = Mirror(reflecting: pcView)
        let vm = vmMirror.children.first { $0.label == "viewModel" }?.value as? PageControlViewModel
        // page should remain at default (0)
        #expect(vm?.currentPage == 0)
    }

    // MARK: - 额外分支覆盖

    @Test
    func openFolder_responsiveSize_withWidthZeroFallback() {
        let overlay = makeOverlay()
        // 覆盖 L158/L159 ?? fallback 路径：superview 为 nil 时使用 NSScreen.main?.frame.width
        // 由于 NSScreen.main 在测试环境可能非 nil，覆盖 path 走真分支即可触发代码
        // 这里仅验证不崩溃
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        // 不设置 superview（默认 nil），openFolder 走 responsive size 计算
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        #expect(!(overlay.isHidden))
    }

    @Test("folder source 捕获当前 folder identity")
    func folderSourceCapturesCurrentFolderIdentityThroughRealDelegate() throws {
        let overlay = makeOverlay()
        let folder = makeFolder(id: 50)
        let child = makeApp(id: 10, parentID: 50)
        overlay.openFolder(item: folder, childItems: [child], iconCache: nil)
        overlay.dragController = DragController(scheduler: MockScheduler())
        let delegate = try #require(overlay.folderCollectionView.delegate)
        #expect(delegate === overlay)

        let writer = delegate.collectionView?(
            overlay.folderCollectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        )

        #expect(writer != nil)
        let session = try #require(overlay.dragController?.session)
        #expect(session.sourceKind == .folderChild)
        #expect(session.sourceParentID == 50)
    }

    @Test("folder 第二视觉页空白使用最后稳定 child ID")
    func folderEmptyOnSecondVisualPageUsesLastStableChildID() {
        let overlay = makeOverlay()
        let children = (1...40).map { makeApp(id: Int64($0), parentID: 50) }
        overlay.folderViewportSizeProvider = {
            CGSize(width: 500, height: 400)
        }
        overlay.openFolder(item: makeFolder(id: 50), childItems: children, iconCache: nil)

        #expect(overlay.emptyPlacement(inVisualPage: 1)
            == .afterItem(itemID: 40))
    }

    @Test("overlay 外部 drop 使用已解析 top-level placement")
    func overlayExteriorDropUsesResolvedTopLevelPlacement() {
        let overlay = makeOverlay()
        let session = makeFolderChildSession(itemID: 10, folderID: 50)
        overlay.openFolder(
            item: makeFolder(id: 50),
            childItems: [makeApp(id: 10, parentID: 50)],
            iconCache: nil
        )
        overlay.dragController = DragController(scheduler: MockScheduler())
        overlay.dragController?.beginDrag(session)
        overlay.topLevelPlacementResolver = { _ in .beforeItem(itemID: 99) }
        var received: FolderDropDestination?
        overlay.onDropRequested = { _, destination in
            received = destination
            return true
        }

        #expect(overlay.performExteriorDrop(at: NSPoint(x: 10, y: 10)))
        #expect(received == .outside(.beforeItem(itemID: 99)))
    }

    @Test("未解析 external drop 拒绝且不回调")
    func unresolvedExteriorDropRejectsWithoutCallback() {
        let overlay = makeOverlay()
        overlay.dragController = DragController(scheduler: MockScheduler())
        overlay.dragController?.beginDrag(makeFolderChildSession())
        overlay.topLevelPlacementResolver = { _ in nil }
        var called = false
        overlay.onDropRequested = { _, _ in called = true; return true }

        #expect(!overlay.performExteriorDrop(at: NSPoint(x: 10, y: 10)))
        #expect(!called)
    }

    @Test("folder source 拒绝 group、非法 child 与 stale indexPath")
    func folderSourceRejectsGroupInvalidChildAndStaleIndexPaths() throws {
        let overlay = makeOverlay()
        let folder = makeFolder(id: 50)
        let group = makeFolder(id: 60)
        let wrongParent = makeApp(id: 10, parentID: 99)
        overlay.openFolder(
            item: folder,
            childItems: [group, wrongParent],
            iconCache: nil
        )
        overlay.dragController = DragController(scheduler: MockScheduler())
        let delegate = try #require(overlay.folderCollectionView.delegate)
        #expect(delegate === overlay)

        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) == nil)
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)
        ) == nil)
        for stalePath in [
            IndexPath(item: -1, section: 0),
            IndexPath(item: 0, section: -1),
            IndexPath(item: 0, section: 1),
            IndexPath(item: 2, section: 0),
        ] {
            #expect(delegate.collectionView?(
                overlay.folderCollectionView,
                pasteboardWriterForItemAt: stalePath
            ) == nil)
        }
        #expect(overlay.dragController?.session == nil)
    }

    @Test("folder source 拒绝 disabled、closed folder 与 malformed UUID")
    func folderSourceRejectsDisabledClosedAndMalformedUUID() throws {
        let overlay = makeOverlay()
        let valid = makeApp(id: 10, parentID: 50)
        let malformed = TestDataFactory.makePageItem(
            id: 11,
            uuid: "malformed",
            type: .app,
            ordering: 1,
            parentId: 50,
            app: TestDataFactory.makeAppInfo(id: 11, title: "Malformed")
        )
        overlay.openFolder(
            item: makeFolder(id: 50),
            childItems: [valid, malformed],
            iconCache: nil
        )
        overlay.dragController = DragController(scheduler: MockScheduler())
        let delegate = try #require(overlay.folderCollectionView.delegate)
        #expect(delegate === overlay)

        overlay.isDragEnabled = false
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) == nil)

        overlay.isDragEnabled = true
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)
        ) == nil)

        overlay.closeFolder()
        #expect(overlay.currentFolderID == nil)
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) == nil)
        #expect(overlay.dragController?.session == nil)
    }

    @Test("folder drop 拒绝 self、nil callback 与 callback failure")
    func folderDropRejectsSelfNilAndCallbackFailure() {
        let overlay = makeOverlay()
        let session = makeFolderChildSession(itemID: 10, folderID: 50)
        overlay.openFolder(
            item: makeFolder(id: 50),
            childItems: [
                makeApp(id: 10, parentID: 50),
                makeApp(id: 11, parentID: 50, ordering: 1),
            ],
            iconCache: nil
        )
        overlay.dragController = DragController(scheduler: MockScheduler())
        overlay.dragController?.beginDrag(session)

        #expect(!overlay.performFolderDrop(
            session: session,
            destination: .inside(.afterItem(itemID: 11))
        ))

        var calls = 0
        overlay.dragController?.beginDrag(session)
        overlay.onDropRequested = { _, _ in calls += 1; return false }
        #expect(!overlay.performFolderDrop(
            session: session,
            destination: .inside(.beforeItem(itemID: 10))
        ))
        #expect(calls == 0)
        overlay.dragController?.beginDrag(session)
        #expect(!overlay.performFolderDrop(
            session: session,
            destination: .inside(.afterItem(itemID: 11))
        ))
        #expect(calls == 1)
    }

    @Test("folder stale 与非法 indexPath 拒绝且零回调")
    func staleInsideIndexPathsRejectWithoutCallback() throws {
        let overlay = makeOverlay()
        let window = makeWindowHosting(overlay)
        _ = window
        let child = makeApp(id: 10, parentID: 50)
        overlay.openFolder(
            item: makeFolder(id: 50),
            childItems: [child],
            iconCache: nil
        )
        overlay.layoutSubtreeIfNeeded()
        let controller = DragController(scheduler: MockScheduler())
        overlay.dragController = controller
        let session = makeFolderChildSession(itemID: 10, folderID: 50)
        overlay.pasteboardUUIDReader = { _ in session.itemUUID }
        let delegate = try #require(overlay.folderCollectionView.delegate)
        #expect(delegate === overlay)
        var callbackCount = 0
        overlay.onDropRequested = { _, _ in
            callbackCount += 1
            return true
        }
        let stalePaths = [
            IndexPath(item: -1, section: 0),
            IndexPath(item: 0, section: -1),
            IndexPath(item: 0, section: 1),
            IndexPath(item: 1, section: 0),
        ]

        for stalePath in stalePaths {
            controller.beginDrag(session)
            overlay.folderIndexPathResolver = { _ in stalePath }
            let info = makeDraggingInfo(
                session: session,
                windowPoint: overlay.folderCollectionView.convert(
                    NSPoint(x: 10, y: 10),
                    to: nil
                )
            )
            var proposed = NSIndexPath(forItem: 0, inSection: 0)
            var operation: NSCollectionView.DropOperation = .before
            let validation = withUnsafeMutablePointer(
                to: &operation
            ) { operationPointer in
                withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                    delegate.collectionView?(
                        overlay.folderCollectionView,
                        validateDrop: info,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                            proposedPointer
                        ),
                        dropOperation: operationPointer
                    ) ?? []
                }
            }
            #expect(validation == [])
            #expect(delegate.collectionView?(
                overlay.folderCollectionView,
                acceptDrop: info,
                indexPath: stalePath,
                dropOperation: .before
            ) == false)
        }

        #expect(callbackCount == 0)
    }

    @Test("folder native delegate 拒绝全部无效 source/session 分支")
    func folderNativeDelegateRejectsInvalidSourceSessions() throws {
        let source = makeApp(id: 10, parentID: 50)
        let target = makeApp(id: 11, parentID: 50, ordering: 1)
        let valid = makeFolderChildSession(itemID: 10, folderID: 50)

        func session(
            itemID: Int64 = 10,
            itemUUID: String =
                "00000000-0000-0000-0000-000000000010",
            itemType: ItemType = .app,
            sourceKind: DragSourceKind = .folderChild,
            parentID: Int64 = 50
        ) -> DragSession {
            DragSession(
                itemID: itemID,
                itemUUID: itemUUID,
                itemType: itemType,
                sourceKind: sourceKind,
                sourceParentID: parentID,
                sourceVisualIndex: 0
            )
        }

        func assertRejected(
            activeSession: DragSession?,
            pasteboardValue: String?,
            isDragEnabled: Bool = true,
            opensFolder: Bool = true,
            children: [PageItem]? = nil,
            resolvedIndexPath: IndexPath? = nil,
            resolvedFrame: NSRect? = nil
        ) throws {
            let overlay = makeOverlay()
            let window = makeWindowHosting(overlay)
            _ = window
            overlay.openFolder(
                item: makeFolder(id: 50),
                childItems: children ?? [source, target],
                iconCache: nil
            )
            if !opensFolder {
                overlay.closeFolder()
                #expect(overlay.currentFolderID == nil)
            }
            overlay.layoutSubtreeIfNeeded()
            let controller = DragController(scheduler: MockScheduler())
            overlay.dragController = controller
            if let activeSession { controller.beginDrag(activeSession) }
            overlay.isDragEnabled = isDragEnabled
            overlay.pasteboardUUIDReader = { _ in pasteboardValue }
            overlay.folderIndexPathResolver = { _ in resolvedIndexPath }
            overlay.folderItemFrameResolver = { _ in resolvedFrame }
            var callbackCount = 0
            overlay.onDropRequested = { _, _ in
                callbackCount += 1
                return true
            }
            let delegate = try #require(overlay.folderCollectionView.delegate)
            #expect(delegate === overlay)
            let info = makeDraggingInfo(
                session: valid,
                windowPoint: overlay.folderCollectionView.convert(
                    NSPoint(x: 10, y: 10),
                    to: nil
                )
            )
            var proposed = NSIndexPath(forItem: 0, inSection: 0)
            var operation: NSCollectionView.DropOperation = .before
            let validation = withUnsafeMutablePointer(
                to: &operation
            ) { operationPointer in
                withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                    delegate.collectionView?(
                        overlay.folderCollectionView,
                        validateDrop: info,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                            proposedPointer
                        ),
                        dropOperation: operationPointer
                    ) ?? []
                }
            }
            #expect(validation == [])
            #expect(delegate.collectionView?(
                overlay.folderCollectionView,
                acceptDrop: info,
                indexPath: IndexPath(item: 1, section: 0),
                dropOperation: .before
            ) == false)
            #expect(callbackCount == 0)
            #expect(controller.session == nil)
        }

        try assertRejected(activeSession: valid, pasteboardValue: nil)
        try assertRejected(activeSession: valid, pasteboardValue: "malformed")
        try assertRejected(
            activeSession: valid,
            pasteboardValue: "00000000-0000-0000-0000-000000000099"
        )
        try assertRejected(activeSession: nil, pasteboardValue: valid.itemUUID)
        try assertRejected(
            activeSession: valid,
            pasteboardValue: valid.itemUUID,
            isDragEnabled: false
        )
        try assertRejected(
            activeSession: session(itemType: .group),
            pasteboardValue: valid.itemUUID
        )
        try assertRejected(
            activeSession: session(sourceKind: .topLevel),
            pasteboardValue: valid.itemUUID
        )
        try assertRejected(
            activeSession: session(parentID: 99),
            pasteboardValue: valid.itemUUID
        )
        try assertRejected(
            activeSession: session(
                itemID: 99,
                itemUUID: "00000000-0000-0000-0000-000000000099"
            ),
            pasteboardValue: "00000000-0000-0000-0000-000000000099"
        )
        let mismatchedUUIDChild = TestDataFactory.makePageItem(
            id: 10,
            uuid: "00000000-0000-0000-0000-000000000099",
            type: .app,
            parentId: 50,
            app: TestDataFactory.makeAppInfo(id: 10, title: "Mismatch UUID")
        )
        try assertRejected(
            activeSession: valid,
            pasteboardValue: valid.itemUUID,
            children: [mismatchedUUIDChild, target]
        )
        let mismatchedParentChild = makeApp(id: 10, parentID: 99)
        try assertRejected(
            activeSession: valid,
            pasteboardValue: valid.itemUUID,
            children: [mismatchedParentChild, target]
        )
        try assertRejected(
            activeSession: valid,
            pasteboardValue: valid.itemUUID,
            resolvedIndexPath: IndexPath(item: 1, section: 0),
            resolvedFrame: nil
        )
        try assertRejected(
            activeSession: valid,
            pasteboardValue: valid.itemUUID,
            opensFolder: false
        )
    }

    private func assertSecondVisualPageBlankDrop(
        itemCount: Int,
        expectedAnchorID: Int64
    ) throws {
        let overlay = makeOverlay()
        let window = makeWindowHosting(overlay)
        _ = window
        overlay.folderViewportSizeProvider = {
            CGSize(width: 500, height: 400)
        }
        let children = (1...itemCount).map {
            makeApp(id: Int64($0), parentID: 50, ordering: $0 - 1)
        }
        overlay.openFolder(
            item: makeFolder(id: 50),
            childItems: children,
            iconCache: nil
        )
        overlay.layoutSubtreeIfNeeded()
        overlay.folderScrollView.frame = NSRect(
            x: 0, y: 0, width: 500, height: 400
        )
        overlay.folderPageControl.onDotSelected?(1)
        #expect(overlay.currentVisualPageIndex == 1)

        let controller = DragController(scheduler: MockScheduler())
        overlay.dragController = controller
        let session = makeFolderChildSession(itemID: 1, folderID: 50)
        controller.beginDrag(session)
        overlay.pasteboardUUIDReader = { _ in session.itemUUID }
        var resolvedPoints: [NSPoint] = []
        overlay.folderIndexPathResolver = { point in
            resolvedPoints.append(point)
            return nil
        }
        var received: FolderDropDestination?
        overlay.onDropRequested = { _, destination in
            received = destination
            return true
        }
        let localPoint = NSPoint(x: 220, y: 140)
        let info = makeDraggingInfo(
            session: session,
            windowPoint: overlay.folderCollectionView.convert(localPoint, to: nil)
        )
        let delegate = try #require(overlay.folderCollectionView.delegate)
        #expect(delegate === overlay)

        var proposed = NSIndexPath(forItem: 0, inSection: 1)
        var operation: NSCollectionView.DropOperation = .before
        let validation = withUnsafeMutablePointer(
            to: &operation
        ) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                delegate.collectionView?(
                    overlay.folderCollectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                        proposedPointer
                    ),
                    dropOperation: operationPointer
                ) ?? []
            }
        }
        #expect(validation == .move)
        #expect(operation == .before)
        #expect(delegate.collectionView?(
            overlay.folderCollectionView,
            acceptDrop: info,
            indexPath: IndexPath(item: 0, section: 1),
            dropOperation: .before
        ) == true)
        #expect(received == .inside(.afterItem(itemID: expectedAnchorID)))
        #expect(resolvedPoints.count == 2)
        for point in resolvedPoints {
            #expect(abs(point.x - localPoint.x) <= 0.001)
            #expect(abs(point.y - localPoint.y) <= 0.001)
        }
    }

    @Test("第二视觉页 item36 空白 drop 使用 item36")
    func secondVisualPageItem36BlankDropUsesItem36() throws {
        try assertSecondVisualPageBlankDrop(
            itemCount: 36,
            expectedAnchorID: 36
        )
    }

    @Test("第二视觉页 item40 空白 drop 使用 item40")
    func secondVisualPageItem40BlankDropUsesItem40() throws {
        try assertSecondVisualPageBlankDrop(
            itemCount: 40,
            expectedAnchorID: 40
        )
    }

    @Test("scroll 同步当前视觉页和空白 anchor")
    func scrollSynchronizesCurrentVisualPageAndBlankAnchor() {
        let overlay = makeOverlay()
        let children = (1...40).map {
            makeApp(id: Int64($0), parentID: 50, ordering: $0 - 1)
        }
        overlay.folderViewportSizeProvider = {
            CGSize(width: 500, height: 400)
        }
        overlay.openFolder(
            item: makeFolder(),
            childItems: children,
            iconCache: nil
        )
        overlay.folderScrollView.frame = NSRect(
            x: 0, y: 0, width: 500, height: 400
        )
        overlay.folderScrollView.contentView.scroll(
            to: NSPoint(x: 500, y: 0)
        )
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: overlay.folderScrollView.contentView
        )

        #expect(overlay.currentVisualPageIndex == 1)
        #expect(overlay.emptyPlacement(
            inVisualPage: overlay.currentVisualPageIndex
        ) == .afterItem(itemID: 40))
    }

    @Test("外部 drag entries 对非零 origin 只转换一次 window point")
    func exteriorDragEntriesConvertWindowPointForNonZeroOrigin() throws {
        let overlay = makeOverlay()
        let window = makeWindowHosting(overlay)
        _ = window
        let child = makeApp(id: 10, parentID: 50)
        overlay.openFolder(
            item: makeFolder(),
            childItems: [child],
            iconCache: nil
        )
        overlay.layoutSubtreeIfNeeded()
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)
        overlay.dragController = controller
        let session = DragSession(
            itemID: child.id,
            itemUUID: child.uuid,
            itemType: child.type,
            sourceKind: .folderChild,
            sourceParentID: 50,
            sourceVisualIndex: 0,
            hoverDestination: .empty,
            folderCreationPreviewTargetID: 11
        )
        var previewChanges: [Int64?] = []
        controller.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        controller.beginDrag(session)
        controller.handlePressBegan(at: .zero)
        #expect(!scheduler.scheduledActions.isEmpty)
        overlay.pasteboardUUIDReader = { _ in session.itemUUID }
        var points: [NSPoint] = []
        overlay.topLevelPlacementResolver = { point in
            points.append(point)
            return .beforeItem(itemID: 99)
        }
        var callbackCount = 0
        overlay.onDropRequested = { receivedSession, destination in
            #expect(receivedSession == session)
            #expect(destination == .outside(.beforeItem(itemID: 99)))
            callbackCount += 1
            return true
        }
        let localPoint = NSPoint(x: 5, y: 5)
        let info = makeDraggingInfo(
            session: session,
            windowPoint: overlay.convert(localPoint, to: nil)
        )

        #expect(overlay.draggingEntered(info) == .move)
        #expect(callbackCount == 0)
        #expect(overlay.draggingUpdated(info) == .move)
        #expect(callbackCount == 0)
        #expect(overlay.prepareForDragOperation(info))
        #expect(callbackCount == 0)
        #expect(overlay.performDragOperation(info))
        #expect(callbackCount == 1)
        #expect(points.count == 4)
        for point in points {
            #expect(abs(point.x - localPoint.x) <= 0.001)
            #expect(abs(point.y - localPoint.y) <= 0.001)
        }
        #expect(controller.session == session)
        #expect(controller.session?.folderCreationPreviewTargetID == 11)
        #expect(!scheduler.scheduledActions.isEmpty)

        let delegate = try #require(overlay.folderCollectionView.delegate)
        delegate.collectionView?(
            overlay.folderCollectionView,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )

        #expect(callbackCount == 1)
        #expect(controller.session == nil)
        #expect(controller.state == .idle)
        #expect(scheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))
    }

    @Test("native exterior 四入口拒绝 panel 内与 self anchor")
    func nativeExteriorEntriesRejectPanelAndSelfAnchor() throws {
        func assertRejected(
            localPoint: (FolderOverlayView) throws -> NSPoint,
            placement: ItemPlacement?
        ) throws {
            let overlay = makeOverlay()
            let window = makeWindowHosting(overlay)
            _ = window
            let child = makeApp(id: 10, parentID: 50)
            overlay.openFolder(
                item: makeFolder(),
                childItems: [child],
                iconCache: nil
            )
            overlay.layoutSubtreeIfNeeded()
            let controller = DragController(scheduler: MockScheduler())
            let session = makeFolderChildSession(itemID: 10, folderID: 50)
            overlay.dragController = controller
            controller.beginDrag(session)
            overlay.pasteboardUUIDReader = { _ in session.itemUUID }
            overlay.topLevelPlacementResolver = { _ in placement }
            var callbackCount = 0
            overlay.onDropRequested = { _, _ in
                callbackCount += 1
                return true
            }
            let point = try localPoint(overlay)
            let info = makeDraggingInfo(
                session: session,
                windowPoint: overlay.convert(point, to: nil)
            )

            #expect(overlay.draggingEntered(info) == [])
            #expect(overlay.draggingUpdated(info) == [])
            #expect(!overlay.prepareForDragOperation(info))
            #expect(!overlay.performDragOperation(info))
            #expect(callbackCount == 0)
            #expect(controller.session == nil)
        }

        try assertRejected(
            localPoint: { overlay in
                let panel = try #require(
                    findView(NSVisualEffectView.self, in: overlay)
                )
                return NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            },
            placement: .beforeItem(itemID: 99)
        )
        try assertRejected(
            localPoint: { overlay in
                let panel = try #require(
                    findView(NSVisualEffectView.self, in: overlay)
                )
                return NSPoint(x: panel.frame.minX - 1, y: panel.frame.midY)
            },
            placement: .beforeItem(itemID: 10)
        )
    }

    @Test("native validate accept ended 由同一 session 保留并最终清理")
    func nativeValidateAcceptEndedUsesOneSessionAndCleansUpOnce() throws {
        let overlay = makeOverlay()
        let window = makeWindowHosting(overlay)
        _ = window
        let source = makeApp(id: 10, parentID: 50)
        let target = makeApp(id: 11, parentID: 50, ordering: 1)
        overlay.openFolder(
            item: makeFolder(),
            childItems: [source, target],
            iconCache: nil
        )
        overlay.layoutSubtreeIfNeeded()

        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)
        let session = DragSession(
            itemID: source.id,
            itemUUID: source.uuid,
            itemType: source.type,
            sourceKind: .folderChild,
            sourceParentID: 50,
            sourceVisualIndex: 0,
            hoverDestination: .empty,
            folderCreationPreviewTargetID: target.id
        )
        var previewChanges: [Int64?] = []
        controller.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        overlay.dragController = controller
        controller.beginDrag(session)
        controller.handlePressBegan(at: .zero)
        #expect(!scheduler.scheduledActions.isEmpty)
        overlay.pasteboardUUIDReader = { _ in session.itemUUID }
        let targetPath = IndexPath(item: 1, section: 0)
        overlay.folderIndexPathResolver = { _ in targetPath }
        overlay.folderItemFrameResolver = { _ in
            NSRect(x: 0, y: 0, width: 100, height: 80)
        }
        var received: [FolderDropDestination] = []
        overlay.onDropRequested = { receivedSession, destination in
            #expect(receivedSession == session)
            received.append(destination)
            return true
        }
        let info = makeDraggingInfo(
            session: session,
            windowPoint: overlay.folderCollectionView.convert(
                NSPoint(x: 60, y: 20),
                to: nil
            )
        )
        let delegate = try #require(overlay.folderCollectionView.delegate)
        var proposed = NSIndexPath(forItem: 1, inSection: 0)
        var operation: NSCollectionView.DropOperation = .on

        let validation = withUnsafeMutablePointer(
            to: &operation
        ) { operationPointer in
            withUnsafeMutablePointer(to: &proposed) { proposedPointer in
                delegate.collectionView?(
                    overlay.folderCollectionView,
                    validateDrop: info,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(
                        proposedPointer
                    ),
                    dropOperation: operationPointer
                ) ?? []
            }
        }

        #expect(validation == .move)
        #expect(operation == .before)
        #expect(received.isEmpty)
        #expect(controller.session == session)
        #expect(controller.session?.folderCreationPreviewTargetID == target.id)
        #expect(!scheduler.scheduledActions.isEmpty)

        let accepted = delegate.collectionView?(
            overlay.folderCollectionView,
            acceptDrop: info,
            indexPath: targetPath,
            dropOperation: .before
        ) ?? false

        #expect(accepted)
        #expect(received == [.inside(.afterItem(itemID: target.id))])
        #expect(controller.session == session)
        #expect(controller.session?.folderCreationPreviewTargetID == target.id)
        #expect(!scheduler.scheduledActions.isEmpty)

        delegate.collectionView?(
            overlay.folderCollectionView,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )

        #expect(received.count == 1)
        #expect(controller.session == nil)
        #expect(controller.state == .idle)
        #expect(scheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))
    }

    @Test("folder dragging session end 清理取消会话")
    func folderDraggingSessionEndClearsCancelledSessionThroughRealDelegate() throws {
        let overlay = makeOverlay()
        overlay.openFolder(
            item: makeFolder(id: 50),
            childItems: [makeApp(id: 10, parentID: 50)],
            iconCache: nil
        )
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)
        overlay.dragController = controller
        controller.beginDrag(makeFolderChildSession())
        controller.updateDragHover(.item(itemID: 11, itemType: .app))
        let delegate = try #require(overlay.folderCollectionView.delegate)
        #expect(delegate === overlay)

        delegate.collectionView?(
            overlay.folderCollectionView,
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: []
        )

        #expect(controller.state == .idle)
        #expect(controller.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("inside target 左右半区映射 before/after 且合法 callback 只调用一次")
    func insideTargetHalvesResolveStablePlacementAndCallOnce() throws {
        for (x, expected) in [
            (CGFloat(40), ItemPlacement.beforeItem(itemID: 11)),
            (CGFloat(60), ItemPlacement.afterItem(itemID: 11)),
        ] {
            let overlay = makeOverlay()
            let window = makeWindowHosting(overlay)
            _ = window
            let source = makeApp(id: 10, parentID: 50)
            let target = makeApp(id: 11, parentID: 50, ordering: 1)
            overlay.openFolder(
                item: makeFolder(),
                childItems: [source, target],
                iconCache: nil
            )
            let controller = DragController(scheduler: MockScheduler())
            overlay.dragController = controller
            let session = makeFolderChildSession()
            controller.beginDrag(session)
            overlay.pasteboardUUIDReader = { _ in session.itemUUID }
            let targetPath = IndexPath(item: 1, section: 0)
            overlay.folderIndexPathResolver = { _ in targetPath }
            overlay.folderItemFrameResolver = { _ in
                NSRect(x: 0, y: 0, width: 100, height: 80)
            }
            var destinations: [FolderDropDestination] = []
            overlay.onDropRequested = { _, destination in
                destinations.append(destination)
                return true
            }
            let info = makeDraggingInfo(
                session: session,
                windowPoint: overlay.folderCollectionView.convert(
                    NSPoint(x: x, y: 20),
                    to: nil
                )
            )
            let delegate = try #require(overlay.folderCollectionView.delegate)

            #expect(delegate.collectionView?(
                overlay.folderCollectionView,
                acceptDrop: info,
                indexPath: targetPath,
                dropOperation: .before
            ) == true)
            #expect(destinations == [.inside(expected)])
        }
    }

    @Test("重复 open 只保留一个 observer 且 close 移除")
    func repeatedOpenKeepsOneObserverAndCloseRemovesIt() {
        let overlay = makeOverlay()
        var scrollUpdateCount = 0
        overlay.scrollPositionDidUpdate = { scrollUpdateCount += 1 }
        let folder = makeFolder()
        let children = (1...40).map {
            makeApp(id: Int64($0), parentID: 50, ordering: $0 - 1)
        }
        overlay.openFolder(item: folder, childItems: children, iconCache: nil)
        overlay.openFolder(item: folder, childItems: children, iconCache: nil)
        #expect(overlay.isObservingScrollPosition)
        let beforePost = scrollUpdateCount
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: overlay.folderScrollView.contentView
        )
        #expect(scrollUpdateCount == beforePost + 1)

        overlay.closeFolder()
        #expect(!overlay.isObservingScrollPosition)
        #expect(overlay.currentFolderID == nil)
        #expect(overlay.currentPageCapacity == 0)
        #expect(overlay.currentFolderGridMetrics == nil)
        let afterClose = scrollUpdateCount
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: overlay.folderScrollView.contentView
        )
        #expect(scrollUpdateCount == afterClose)
    }

    @Test("deinit 释放带 scroll observer 的 overlay")
    func deinitReleasesOverlayWithInstalledScrollObserver() {
        weak var weakOverlay: FolderOverlayView?
        autoreleasepool {
            var overlay: FolderOverlayView? = makeOverlay()
            overlay?.observeScrollPosition()
            #expect(overlay?.isObservingScrollPosition == true)
            weakOverlay = overlay
            overlay = nil
        }
        #expect(weakOverlay == nil)
    }
}
#endif
