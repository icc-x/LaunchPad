import Testing
import CoreGraphics
@testable import LaunchPad
import LaunchPadProtocols

@Suite("LayoutProjection stable order")
struct LayoutProjectionTests {
    @Test("跨持久化页按稳定顺序重新分段")
    func rechunksAcrossPersistedPages() {
        let firstPage = TestDataFactory.makePageItem(id: 100, type: .page, ordering: 1)
        let secondPage = TestDataFactory.makePageItem(id: 200, type: .page, ordering: 0)
        let itemsByPage: [Int64: [PageItem]] = [
            100: [
                TestDataFactory.makePageItem(id: 3, ordering: 1),
                TestDataFactory.makePageItem(id: 2, ordering: 0),
            ],
            200: [
                TestDataFactory.makePageItem(id: 1, ordering: 0),
            ],
        ]
        let metrics = GridMetrics(
            columns: 2, rows: 1, itemsPerPage: 2, iconSize: 64,
            itemSize: CGSize(width: 64, height: 104), horizontalSpacing: 20,
            verticalSpacing: 20,
            sectionInsets: GridInsets(top: 10, left: 10, bottom: 10, right: 10),
            pageWidth: 200
        )

        let result = LayoutProjection.project(
            pages: [firstPage, secondPage],
            itemsByPage: itemsByPage,
            metrics: metrics
        )

        #expect(result.map { $0.map(\.id) } == [[1, 2], [3]])
    }

    @Test("空布局仍产生一个空视觉页")
    func emptyLayoutReturnsOneEmptyPage() {
        let metrics = GridMetrics(
            columns: 7, rows: 5, itemsPerPage: 35, iconSize: 64,
            itemSize: CGSize(width: 64, height: 104), horizontalSpacing: 20,
            verticalSpacing: 20,
            sectionInsets: GridInsets(top: 10, left: 60, bottom: 10, right: 60),
            pageWidth: 1440
        )
        #expect(LayoutProjection.project(
            pages: [], itemsByPage: [:], metrics: metrics
        ) == [[]])
    }

    @Test("容量变化只改变分段不改变稳定顺序")
    func capacityChangePreservesStableOrder() {
        let page = TestDataFactory.makePageItem(id: 100, type: .page)
        let items = (1...8).map { TestDataFactory.makePageItem(id: Int64($0), ordering: $0) }
        let wide = makeMetrics(columns: 4, rows: 1)
        let narrow = makeMetrics(columns: 3, rows: 1)

        let wideResult = LayoutProjection.project(
            pages: [page], itemsByPage: [100: items], metrics: wide)
        let narrowResult = LayoutProjection.project(
            pages: [page], itemsByPage: [100: items], metrics: narrow)

        #expect(wideResult.flatMap { $0 }.map(\.id) == Array(1...8).map(Int64.init))
        #expect(narrowResult.flatMap { $0 }.map(\.id) == Array(1...8).map(Int64.init))
        #expect(wideResult.map(\.count) == [4, 4])
        #expect(narrowResult.map(\.count) == [3, 3, 2])
    }

    @Test("搜索结果也按视觉容量分页且最后一页不超容量")
    func searchResultsUseVisualPagination() {
        let items = (1...9).map {
            TestDataFactory.makePageItem(id: Int64($0), ordering: $0)
        }
        let metrics = makeMetrics(columns: 4, rows: 1)

        let result = LayoutProjection.paginate(items: items, metrics: metrics)

        #expect(result.map(\.count) == [4, 4, 1])
        #expect(result.flatMap { $0 }.map(\.id) == items.map(\.id))
        #expect(result.allSatisfy { $0.count <= metrics.itemsPerPage })
    }

    @Test("持久化页缺少 children key 时仍返回一个空视觉页")
    func missingPageChildrenStillReturnsOneEmptyPage() {
        let page = TestDataFactory.makePageItem(id: 100, type: .page, ordering: 0)
        let metrics = makeMetrics(columns: 7, rows: 5)

        #expect(LayoutProjection.project(
            pages: [page], itemsByPage: [:], metrics: metrics
        ) == [[]])
    }

    @Test("投影不修改 parentId 或 ordering")
    func projectionDoesNotMutateParentOrOrdering() {
        let page = TestDataFactory.makePageItem(id: 100, type: .page, ordering: 0)
        let items = [
            TestDataFactory.makePageItem(id: 2, ordering: 1, parentId: 100),
            TestDataFactory.makePageItem(id: 1, ordering: 0, parentId: 100),
        ]
        let originalPage = page
        let originalItems = items

        _ = LayoutProjection.project(
            pages: [page],
            itemsByPage: [100: items],
            metrics: makeMetrics(columns: 1, rows: 1)
        )

        #expect(page == originalPage)
        #expect(items == originalItems)
    }

    private func makeMetrics(columns: Int, rows: Int) -> GridMetrics {
        GridMetrics(
            columns: columns, rows: rows, itemsPerPage: columns * rows,
            iconSize: 64, itemSize: CGSize(width: 64, height: 104),
            horizontalSpacing: 20, verticalSpacing: 20,
            sectionInsets: GridInsets(top: 10, left: 10, bottom: 10, right: 10),
            pageWidth: 400
        )
    }
}
