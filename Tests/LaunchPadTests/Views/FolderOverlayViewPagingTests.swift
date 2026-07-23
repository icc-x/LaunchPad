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

    private func pagingFolder() -> PageItem {
        TestDataFactory.makePageItem(
            id: 50,
            type: .group,
            parentId: 1,
            group: TestDataFactory.makeGroupInfo(id: 50, title: "Folder")
        )
    }

    private func sectionCounts(_ overlay: FolderOverlayView) -> [Int] {
        (0..<overlay.numberOfSections(in: overlay.folderCollectionView)).map {
            overlay.collectionView(
                overlay.folderCollectionView,
                numberOfItemsInSection: $0
            )
        }
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

    @Test("folder metrics 使用实际宽高并封顶 35")
    func metricsUseActualWidthHeightAndCapAtThirtyFive() {
        let one = FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(width: 96, height: 96)
        )
        #expect(one.columns == 1)
        #expect(one.rows == 1)
        #expect(one.pageCapacity == 1)
        #expect(one.horizontalInset == 12)

        let medium = FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(width: 496, height: 360)
        )
        #expect(medium.columns == 6)
        #expect(medium.rows == 4)
        #expect(medium.pageCapacity == 24)
        #expect(medium.horizontalInset == 12)
        #expect(
            FolderOverlayView.folderGridMetrics(
                forViewportSize: CGSize(
                    width: CGFloat(496).nextDown,
                    height: 360
                )
            ).pageCapacity == 20
        )
        #expect(
            FolderOverlayView.folderGridMetrics(
                forViewportSize: CGSize(
                    width: 496,
                    height: CGFloat(360).nextDown
                )
            ).pageCapacity == 18
        )

        let capped = FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(width: 800, height: 624)
        )
        #expect(capped.columns == 5)
        #expect(capped.rows == 7)
        #expect(capped.pageCapacity == 35)
        #expect(capped.horizontalInset == 204)

        let invalid = FolderOverlayView.folderGridMetrics(
            forViewportSize: CGSize(
                width: CGFloat.nan,
                height: CGFloat.infinity
            )
        )
        #expect(invalid.columns == 1)
        #expect(invalid.rows == 1)
        #expect(invalid.pageCapacity == 1)
        #expect(invalid.horizontalInset.isFinite)
    }

    @Test("open 使用实际 folder viewport 容量")
    func openUsesActualFolderViewportCapacity() {
        let pagingOverlay = makePagingOverlay()
        pagingOverlay.folderViewportSizeProvider = {
            CGSize(width: 500, height: 400)
        }
        pagingOverlay.openFolder(
            item: pagingFolder(),
            childItems: TestDataFactory.makeAppItems(count: 41),
            iconCache: nil
        )

        #expect(pagingOverlay.currentPageCapacity == 24)
        #expect(sectionCounts(pagingOverlay) == [24, 17])
        #expect(pagingOverlay.currentVisualPageIndex == 0)
    }

    @Test("reload 重新分页并夹紧当前页")
    func reloadRepaginatesAndClampsCurrentPage() {
        let pagingOverlay = makePagingOverlay()
        pagingOverlay.folderViewportSizeProvider = {
            CGSize(width: 500, height: 400)
        }
        pagingOverlay.openFolder(
            item: pagingFolder(),
            childItems: TestDataFactory.makeAppItems(count: 60),
            iconCache: nil
        )
        pagingOverlay.folderScrollView.frame = NSRect(
            x: 0, y: 0, width: 500, height: 400
        )
        pagingOverlay.folderPageControl.onDotSelected?(2)
        #expect(pagingOverlay.currentVisualPageIndex == 2)

        pagingOverlay.reloadChildren(
            TestDataFactory.makeAppItems(count: 25)
        )

        #expect(pagingOverlay.currentPageCapacity == 24)
        #expect(sectionCounts(pagingOverlay) == [24, 1])
        #expect(pagingOverlay.currentVisualPageIndex == 1)
        #expect(pagingOverlay.emptyPlacement(inVisualPage: 1)
            == .afterItem(itemID: 25))
    }

    @Test("resize 重新分页并夹紧当前页")
    func resizeRepaginatesAndClampsCurrentPage() {
        let pagingOverlay = makePagingOverlay()
        var viewport = CGSize(width: 500, height: 400)
        pagingOverlay.folderViewportSizeProvider = { viewport }
        pagingOverlay.openFolder(
            item: pagingFolder(),
            childItems: TestDataFactory.makeAppItems(count: 60),
            iconCache: nil
        )
        pagingOverlay.folderScrollView.frame = NSRect(
            x: 0, y: 0, width: 500, height: 400
        )
        pagingOverlay.folderPageControl.onDotSelected?(2)
        #expect(pagingOverlay.currentVisualPageIndex == 2)

        viewport = CGSize(width: 500, height: 624)
        pagingOverlay.layout()

        #expect(pagingOverlay.currentPageCapacity == 35)
        #expect(sectionCounts(pagingOverlay) == [35, 25])
        #expect(pagingOverlay.currentVisualPageIndex == 1)
        #expect(pagingOverlay.emptyPlacement(inVisualPage: 1)
            == .afterItem(itemID: 60))
    }

    @Test("reload 按 ordering 与 id 稳定排序且真空页无 anchor")
    func reloadSortsByOrderingAndIDAndEmptyHasNoAnchor() {
        let overlay = makePagingOverlay()
        overlay.folderViewportSizeProvider = { CGSize(width: 176, height: 96) }
        let items = [
            TestDataFactory.makePageItem(id: 3, type: .app, ordering: 1),
            TestDataFactory.makePageItem(id: 2, type: .app, ordering: 0),
            TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0),
        ]

        overlay.openFolder(item: pagingFolder(), childItems: items, iconCache: nil)
        #expect(overlay.currentPageCapacity == 2)
        #expect(sectionCounts(overlay) == [2, 1])
        #expect(overlay.emptyPlacement(inVisualPage: 0) == .afterItem(itemID: 2))
        #expect(overlay.emptyPlacement(inVisualPage: 1) == .afterItem(itemID: 3))
        overlay.reloadChildren([])
        #expect(overlay.emptyPlacement(inVisualPage: 0) == nil)
        #expect(overlay.currentVisualPageIndex == 0)
    }
}
#endif
