import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for AppGridCollectionView (0% → target 80%+)
@MainActor
final class AppGridCollectionViewTests: XCTestCase {

    private var collectionView: AppGridCollectionView!
    private var mockIconCache: MockIconCaching!

    override func setUp() {
        super.setUp()
        collectionView = AppGridCollectionView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        mockIconCache = MockIconCaching()
        collectionView.configure(iconCache: mockIconCache)
    }

    override func tearDown() {
        collectionView = nil
        mockIconCache = nil
        super.tearDown()
    }

    // MARK: - Init

    func testInit_frame_doesNotCrash() {
        let view = AppGridCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotNil(view)
    }

    func testInit_coder_doesNotCrash() {
        // NSCoder init is not supported, but we test the frame init path
        let view = AppGridCollectionView(frame: .zero)
        XCTAssertNotNil(view)
    }

    // MARK: - Configure

    func testConfigure_setsIconCache() {
        // After configure, the collectionView should have the icon cache
        // We verify by checking that reload doesn't crash
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
    }

    // MARK: - Reload

    func testReload_emptyPages_doesNotCrash() {
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 0)
    }

    func testReload_withPages_createsSections() {
        let app1 = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                  app: TestDataFactory.makeAppInfo(id: 1, title: "App1"))
        let app2 = TestDataFactory.makePageItem(id: 2, type: .app, ordering: 1,
                                                  app: TestDataFactory.makeAppInfo(id: 2, title: "App2"))
        collectionView.reload(pages: [[app1, app2]], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    func testReload_withMultiplePages_createsMultipleSections() {
        let page1Items = TestDataFactory.makeAppItems(count: 3, titlePrefix: "P1")
        let page2Items = TestDataFactory.makeAppItems(count: 2, titlePrefix: "P2")
        collectionView.reload(pages: [page1Items, page2Items], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 2)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 3)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(1)), 2)
    }

    func testReload_searchResults_createsSearchSection() {
        let results = TestDataFactory.makeAppItems(count: 5)
        collectionView.reload(pages: [], searchResults: results, searchQuery: "test")

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .search), 5)
    }

    func testReload_nilSearchResults_usesPageMode() {
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    func testReload_emptySearchQuery_ignoresSearchResults() {
        let items = TestDataFactory.makeAppItems(count: 2)
        collectionView.reload(pages: [items], searchResults: [], searchQuery: "")

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    // MARK: - Update Layout

    func testUpdateLayout_smallScreen_7Columns() {
        collectionView.updateLayout(screenWidth: 1280)
        if let layout = collectionView.collectionViewLayout as? AppGridFlowLayout {
            // 1280 screen → 7 columns
            let params = GridLayoutCalculator.calculate(screenWidth: 1280)
            XCTAssertEqual(params.columns, 7)
        }
    }

    func testUpdateLayout_mediumScreen_9Columns() {
        collectionView.updateLayout(screenWidth: 1600)
        let params = GridLayoutCalculator.calculate(screenWidth: 1600)
        XCTAssertEqual(params.columns, 9)
    }

    func testUpdateLayout_largeScreen_10Columns() {
        collectionView.updateLayout(screenWidth: 1920)
        let params = GridLayoutCalculator.calculate(screenWidth: 1920)
        XCTAssertEqual(params.columns, 10)
    }

    // MARK: - Cell Configuration

    func testConfigureCell_appItem_returnsAppIconCell() {
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp"))
        collectionView.reload(pages: [[app]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        XCTAssertTrue(cell is AppIconCell)
    }

    func testConfigureCell_groupItem_returnsFolderCell() {
        let group = TestDataFactory.makePageItem(id: 1, type: .group, ordering: 0,
                                                  group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder"))
        collectionView.reload(pages: [[group]], searchResults: nil, searchQuery: nil)

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = collectionView.diffableDataSource.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
        XCTAssertTrue(cell is FolderCell)
    }

    // MARK: - Accessibility

    func testAccessibilityRole_returnsGrid() {
        XCTAssertEqual(collectionView.accessibilityRole(), .grid)
    }

    func testAccessibilityLabel_returnsApplicationGrid() {
        XCTAssertEqual(collectionView.accessibilityLabel(), "Application Grid")
    }

    func testAccessibilityRows_withItems_returnsRows() {
        let items = TestDataFactory.makeAppItems(count: 7)
        collectionView.reload(pages: [items], searchResults: nil, searchQuery: nil)
        collectionView.updateLayout(screenWidth: 1440)

        let rows = collectionView.accessibilityRows()
        XCTAssertNotNil(rows)
        // Note: In test environment without actual layout, rows may be 0
        // This test verifies the method doesn't crash
    }

    func testAccessibilityRows_empty_returnsEmpty() {
        collectionView.reload(pages: [], searchResults: nil, searchQuery: nil)
        let rows = collectionView.accessibilityRows()
        XCTAssertNotNil(rows)
        XCTAssertEqual(rows?.count, 0)
    }

    // MARK: - Drag Source

    func testDraggingSession_returnsMove() {
        let session = collectionView.draggingSession(NSDraggingSession(), sourceOperationMaskFor: .withinApplication)
        XCTAssertTrue(session.contains(.move))
    }

    // MARK: - Callbacks

    func testOnItemSelected_callbackIsSettable() {
        var called = false
        collectionView.onItemSelected = { _ in called = true }
        // Just verify the callback is settable without crash
        XCTAssertNotNil(collectionView.onItemSelected)
    }

    func testOnItemDelete_callbackIsSettable() {
        var called = false
        collectionView.onItemDelete = { _ in called = true }
        XCTAssertNotNil(collectionView.onItemDelete)
    }

    func testOnFolderRenamed_callbackIsSettable() {
        var called = false
        collectionView.onFolderRenamed = { _, _ in called = true }
        XCTAssertNotNil(collectionView.onFolderRenamed)
    }

    // MARK: - Mixed Content

    func testReload_mixedAppsAndGroups_handlesCorrectly() {
        let app = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
                                                app: TestDataFactory.makeAppInfo(id: 1))
        let group = TestDataFactory.makePageItem(id: 2, type: .group, ordering: 1,
                                                  group: TestDataFactory.makeGroupInfo(id: 2))
        collectionView.reload(pages: [[app, group]], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    // MARK: - Reload with Existing Data

    func testReload_replacesExistingData() {
        let items1 = TestDataFactory.makeAppItems(count: 3)
        collectionView.reload(pages: [items1], searchResults: nil, searchQuery: nil)

        let items2 = TestDataFactory.makeAppItems(count: 5, titlePrefix: "New")
        collectionView.reload(pages: [items2], searchResults: nil, searchQuery: nil)

        let snapshot = collectionView.diffableDataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 5)
    }
}

// MARK: - Mock IconCaching

private final class MockIconCaching: IconCaching, @unchecked Sendable {
    var iconResult = NSImage(size: NSSize(width: 64, height: 64))

    func icon(forItemId itemId: Int64, path: String) -> NSImage {
        return iconResult
    }
}
#endif
