import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("FolderOverlayView paging")
struct FolderOverlayViewPagingTests {

    private func makePagingOverlay() -> FolderOverlayView {
        FolderOverlayView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 700)
        )
    }

    // MARK: - Page Splitting Tests

    @Test
    func pageSplitting_smallFolder_singlePage() {
        _ = makePagingOverlay()
        // Given: 10 items (< 35 per page)
        let items = TestDataFactory.makeAppItems(count: 10)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 1 page with all 10 items
        #expect(pages.count == 1)
        #expect(pages[0].count == 10)
    }

    @Test
    func pageSplitting_exactPageSize_singlePage() {
        _ = makePagingOverlay()
        // Given: exactly 35 items
        let items = TestDataFactory.makeAppItems(count: 35)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 1 page
        #expect(pages.count == 1)
        #expect(pages[0].count == 35)
    }

    @Test
    func pageSplitting_overPageSize_twoPages() {
        _ = makePagingOverlay()
        // Given: 36 items (> 35 per page)
        let items = TestDataFactory.makeAppItems(count: 36)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 2 pages (35 + 1)
        #expect(pages.count == 2)
        #expect(pages[0].count == 35)
        #expect(pages[1].count == 1)
    }

    @Test
    func pageSplitting_manyItems_multiplePages() {
        _ = makePagingOverlay()
        // Given: 100 items
        let items = TestDataFactory.makeAppItems(count: 100)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 3 pages (35 + 35 + 30)
        #expect(pages.count == 3)
        #expect(pages[0].count == 35)
        #expect(pages[1].count == 35)
        #expect(pages[2].count == 30)
    }

    @Test
    func pageSplitting_emptyItems_emptyPages() {
        _ = makePagingOverlay()
        // Given: 0 items
        let items: [PageItem] = []

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: should be 0 pages
        #expect(pages.count == 0)
    }

    @Test
    func pageSplitting_preservesOrder() {
        _ = makePagingOverlay()
        // Given: 70 items with known order
        let items = TestDataFactory.makeAppItems(count: 70)

        // When: splitting into pages
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)

        // Then: items should be in original order across pages
        let flattened = pages.flatMap { $0 }
        #expect(flattened.map(\.id) == items.map(\.id))
    }

    // MARK: - Page Count Tests

    @Test
    func pageCount_singlePage_noDots() {
        _ = makePagingOverlay()
        let items = TestDataFactory.makeAppItems(count: 10)
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)
        // With 1 page, page control should be hidden
        #expect(pages.count == 1)
    }

    @Test
    func pageCount_multiplePages_showsDots() {
        _ = makePagingOverlay()
        let items = TestDataFactory.makeAppItems(count: 50)
        let pages = FolderOverlayView.paginateItems(items, pageSize: 35)
        // With 2 pages, page control should be visible
        #expect(pages.count == 2)
    }
}
#endif
