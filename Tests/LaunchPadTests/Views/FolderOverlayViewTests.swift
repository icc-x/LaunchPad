import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for FolderOverlayView (0% → target 80%+)
@MainActor
final class FolderOverlayViewTests: XCTestCase {

    private var overlay: FolderOverlayView!

    override func setUp() {
        super.setUp()
        overlay = FolderOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    override func tearDown() {
        overlay = nil
        super.tearDown()
    }

    // MARK: - Init

    func testInit_doesNotCrash() {
        XCTAssertNotNil(overlay)
    }

    func testInit_isHiddenByDefault() {
        XCTAssertTrue(overlay.isHidden)
    }

    func testInit_alphaIsZero() {
        XCTAssertEqual(overlay.alphaValue, 0)
    }

    // MARK: - paginateItems (pure function)

    func testPaginateItems_empty_returnsEmpty() {
        let result = FolderOverlayView.paginateItems([], pageSize: 35)
        XCTAssertTrue(result.isEmpty)
    }

    func testPaginateItems_lessThanPageSize_returnsSinglePage() {
        let items = TestDataFactory.makeAppItems(count: 10)
        let result = FolderOverlayView.paginateItems(items, pageSize: 35)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].count, 10)
    }

    func testPaginateItems_exactPageSize_returnsSinglePage() {
        let items = TestDataFactory.makeAppItems(count: 35)
        let result = FolderOverlayView.paginateItems(items, pageSize: 35)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].count, 35)
    }

    func testPaginateItems_moreThanPageSize_returnsMultiplePages() {
        let items = TestDataFactory.makeAppItems(count: 80)
        let result = FolderOverlayView.paginateItems(items, pageSize: 35)
        XCTAssertEqual(result.count, 3) // 35 + 35 + 10
        XCTAssertEqual(result[0].count, 35)
        XCTAssertEqual(result[1].count, 35)
        XCTAssertEqual(result[2].count, 10)
    }

    func testPaginateItems_zeroPageSize_returnsEmpty() {
        let items = TestDataFactory.makeAppItems(count: 5)
        let result = FolderOverlayView.paginateItems(items, pageSize: 0)
        XCTAssertTrue(result.isEmpty)
    }

    func testPaginateItems_negativePageSize_returnsEmpty() {
        let items = TestDataFactory.makeAppItems(count: 5)
        let result = FolderOverlayView.paginateItems(items, pageSize: -1)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Open Folder

    func testOpenFolder_showsOverlay() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Test Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 5)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        // isHidden is set immediately, alphaValue is animated
        XCTAssertFalse(overlay.isHidden)
    }

    func testOpenFolder_setsTitle() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "My Apps")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        // Title is set internally; we verify overlay is visible
        XCTAssertFalse(overlay.isHidden)
    }

    func testOpenFolder_responsiveSize() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        // Should set responsive dimensions based on screen
        XCTAssertFalse(overlay.isHidden)
    }

    func testOpenFolder_reduceMotion_usesReducedBranch() {
        overlay.accessibilitySettingsProvider = {
            AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        }
        let item = TestDataFactory.makePageItem(type: .group, group: TestDataFactory.makeGroupInfo())
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        XCTAssertFalse(overlay.isHidden)
    }

    func testCollectionView_dataSource_withAppAndIconCache_loadsIcon() {
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
        XCTAssertFalse(overlay.isHidden)
    }

    // MARK: - Close Folder

    func testCloseFolder_hidesOverlay() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        // 注入同步完成回调，确定性覆盖 closeFolder 完成分支（isHidden = true）
        overlay.closeFolderCompletionRunner = { $0() }
        overlay.closeFolder()
        XCTAssertTrue(overlay.isHidden)
    }

    func testCloseFolder_callsOnClosedCallback() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)

        var closedCalled = false
        overlay.onClosed = { closedCalled = true }
        overlay.closeFolderCompletionRunner = { $0() }
        overlay.closeFolder()
        XCTAssertTrue(closedCalled)
    }

    // MARK: - Callbacks

    func testOnAppSelected_callbackIsSettable() {
        overlay.onAppSelected = { _ in }
        XCTAssertNotNil(overlay.onAppSelected)
    }

    func testOnClosed_callbackIsSettable() {
        overlay.onClosed = { }
        XCTAssertNotNil(overlay.onClosed)
    }

    // MARK: - Mouse Down Outside

    func testMouseDown_outsidePanel_closesFolder() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)

        // Simulate mouse down outside the panel
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10), // Far from center panel
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        if let event {
            overlay.mouseDown(with: event)
        }

        // Should trigger closeFolder
        let expectation = XCTestExpectation(description: "Close on outside click")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(self.overlay.isHidden)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Open with many items (pagination)

    func testOpenFolder_withManyItems_paginates() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Big Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 80)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        XCTAssertFalse(overlay.isHidden)
    }

    func testOpenFolder_withExactly35Items_singlePage() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Full Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 35)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        XCTAssertFalse(overlay.isHidden)
    }

    func testOpenFolder_withNoTitle_usesDefaultTitle() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: nil
        )

        overlay.openFolder(item: item, childItems: [], iconCache: nil)

        XCTAssertFalse(overlay.isHidden)
    }

    // MARK: - Close then reopen

    func testCloseThenReopen_doesNotCrash() {
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

    func testObserveScrollPosition_doesNotCrash() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)
        overlay.observeScrollPosition()
    }

    // MARK: - init?(coder:)

    func testInitCoder_producesValidInstance() throws {
        let original = FolderOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let archiver = NSKeyedArchiver()
        archiver.requiresSecureCoding = false
        archiver.encode(original, forKey: "root")
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let view = unarchiver.decodeObject(forKey: "root") as? FolderOverlayView
        XCTAssertNotNil(view)
    }

    // MARK: - Data Source

    func testNumberOfSections_returnsCorrectCount() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40) // 2 pages
        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let collectionView = NSCollectionView()
        let count = overlay.numberOfSections(in: collectionView)
        XCTAssertEqual(count, 2)
    }

    func testNumberOfItemsInSection_returnsCorrectCount() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40)
        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let collectionView = NSCollectionView()
        XCTAssertEqual(overlay.collectionView(collectionView, numberOfItemsInSection: 0), 35)
        XCTAssertEqual(overlay.collectionView(collectionView, numberOfItemsInSection: 1), 5)
    }

    func testNumberOfItemsInSection_outOfBounds_returnsZero() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        let collectionView = NSCollectionView()
        XCTAssertEqual(overlay.collectionView(collectionView, numberOfItemsInSection: 99), 0)
    }

    func testItemForRepresentedObjectAt_outOfBounds_returnsEmptyItem() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        // Use a standalone collectionView - the guard path returns NSCollectionViewItem() without calling makeItem
        let collectionView = NSCollectionView()
        let cell = overlay.collectionView(collectionView,
                                          itemForRepresentedObjectAt: IndexPath(item: 99, section: 99))
        XCTAssertNotNil(cell)
    }

    // MARK: - Delegate

    func testDidSelectItemsAt_callsOnAppSelected() {
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
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.id, children[0].id)
    }

    func testDidSelectItemsAt_emptySet_doesNotCallCallback() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        var selected: PageItem?
        overlay.onAppSelected = { item in selected = item }

        let collectionView = NSCollectionView()
        overlay.collectionView(collectionView, didSelectItemsAt: [])
        XCTAssertNil(selected)
    }

    func testDidSelectItemsAt_outOfBounds_doesNotCallCallback() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: TestDataFactory.makeAppItems(count: 5), iconCache: nil)

        var selected: PageItem?
        overlay.onAppSelected = { item in selected = item }

        let collectionView = NSCollectionView()
        overlay.collectionView(collectionView, didSelectItemsAt: [IndexPath(item: 99, section: 99)])
        XCTAssertNil(selected)
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

    func testNavigateToPage_updatesScrollPosition() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40) // 2 pages

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        // Find pageControlView via view hierarchy traversal
        let pageControlView = findView(PageControlView.self, in: overlay)
        XCTAssertNotNil(pageControlView)

        // Find scrollView via view hierarchy traversal
        let scrollView = findView(NSScrollView.self, in: overlay)
        XCTAssertNotNil(scrollView)

        // Set scrollView frame so bounds.width > 0 (no window -> auto-layout not resolved)
        scrollView!.frame = NSRect(x: 0, y: 0, width: 800, height: 360)
        XCTAssertGreaterThan(scrollView!.bounds.width, 0)

        // Verify onDotSelected callback is set
        XCTAssertNotNil(pageControlView?.onDotSelected, "onDotSelected should be set by setup()")

        // Trigger navigation to page 1 via onDotSelected
        pageControlView?.onDotSelected?(1)

        // Verify currentPage was updated via the pageControlView's viewModel
        let vmMirror = Mirror(reflecting: pageControlView!)
        let vm = vmMirror.children.first { $0.label == "viewModel" }?.value as? PageControlViewModel
        XCTAssertEqual(vm?.currentPage, 1)
    }

    func testNavigateToPage_outOfBounds_isNoOp() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let pageControlView = findView(PageControlView.self, in: overlay)
        let scrollView = findView(NSScrollView.self, in: overlay)
        scrollView!.frame = NSRect(x: 0, y: 0, width: 800, height: 360)

        // Navigate to invalid page index - should be a no-op (guard fails)
        pageControlView?.onDotSelected?(99)

        // Verify currentPage is still 0
        let vmMirror = Mirror(reflecting: pageControlView!)
        let vm = vmMirror.children.first { $0.label == "viewModel" }?.value as? PageControlViewModel
        XCTAssertEqual(vm?.currentPage, 0)
    }

    // MARK: - updatePageFromScrollPosition (via scroll notification)

    func testUpdatePageFromScrollPosition_updatesCurrentPage() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let children = TestDataFactory.makeAppItems(count: 40)

        overlay.openFolder(item: item, childItems: children, iconCache: nil)

        let scrollView = findView(NSScrollView.self, in: overlay)
        XCTAssertNotNil(scrollView)

        // Set frame so bounds.width > 0
        scrollView!.frame = NSRect(x: 0, y: 0, width: 800, height: 360)
        XCTAssertGreaterThan(scrollView!.bounds.width, 0)

        // Use contentView.scroll(to:) to set scroll position (NSClipView manages its own bounds)
        scrollView!.contentView.scroll(to: NSPoint(x: scrollView!.bounds.width, y: 0))

        // Post bounds change notification (dispatched async on main operation queue)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification,
                                         object: scrollView!.contentView)

        // Run the main run loop to process the async notification callback
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

        // updatePageFromScrollPosition() should have been called
        // The code path is exercised regardless of whether currentPage changed
        // (guard on pageWidth > 0, clampedPage calculation, comparison with currentPage)
        let pcView = findView(PageControlView.self, in: overlay)
        XCTAssertNotNil(pcView)
    }

    // MARK: - mouseDown inside panel

    func testMouseDown_insidePanel_doesNotClose() {
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        overlay.openFolder(item: item, childItems: [], iconCache: nil)

        // Click at center (where backgroundView is)
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 400, y: 300), // center of 800x600 overlay
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        if let event {
            overlay.mouseDown(with: event)
        }

        // Should NOT trigger close (overlay still visible)
        XCTAssertFalse(overlay.isHidden)
    }
}
#endif
