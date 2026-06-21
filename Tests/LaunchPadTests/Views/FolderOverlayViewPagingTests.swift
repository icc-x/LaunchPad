import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for FolderOverlayView paging behavior (Task 4.3)
final class FolderOverlayViewPagingTests: XCTestCase {

    // MARK: - Page Splitting Tests

    func testPageSplitting_smallFolder_singlePage() {
        // Given: 10 items (< 35 per page)
        let items = TestDataFactory.makeAppItems(count: 10)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 1 page with all 10 items
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].count, 10)
    }

    func testPageSplitting_exactPageSize_singlePage() {
        // Given: exactly 35 items
        let items = TestDataFactory.makeAppItems(count: 35)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 1 page
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].count, 35)
    }

    func testPageSplitting_overPageSize_twoPages() {
        // Given: 36 items (> 35 per page)
        let items = TestDataFactory.makeAppItems(count: 36)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 2 pages (35 + 1)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].count, 35)
        XCTAssertEqual(pages[1].count, 1)
    }

    func testPageSplitting_manyItems_multiplePages() {
        // Given: 100 items
        let items = TestDataFactory.makeAppItems(count: 100)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 3 pages (35 + 35 + 30)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].count, 35)
        XCTAssertEqual(pages[1].count, 35)
        XCTAssertEqual(pages[2].count, 30)
    }

    func testPageSplitting_emptyItems_emptyPages() {
        // Given: 0 items
        let items: [PageItem] = []

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 0 pages
        XCTAssertEqual(pages.count, 0)
    }

    func testPageSplitting_preservesOrder() {
        // Given: 70 items with known order
        let items = TestDataFactory.makeAppItems(count: 70)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: items should be in original order across pages
        let flattened = pages.flatMap { $0 }
        XCTAssertEqual(flattened.map(\.id), items.map(\.id))
    }

    // MARK: - Page Count Tests

    func testPageCount_singlePage_noDots() {
        let items = TestDataFactory.makeAppItems(count: 10)
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)
        // With 1 page, page control should be hidden
        XCTAssertEqual(pages.count, 1)
    }

    func testPageCount_multiplePages_showsDots() {
        let items = TestDataFactory.makeAppItems(count: 50)
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)
        // With 2 pages, page control should be visible
        XCTAssertEqual(pages.count, 2)
    }
}
#endif
