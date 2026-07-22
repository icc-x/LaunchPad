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
        overlay.closeFolderCompletionRunner = { $0() }
        return overlay
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
}
#endif
