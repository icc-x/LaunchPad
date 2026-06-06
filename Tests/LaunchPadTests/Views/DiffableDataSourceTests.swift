import Testing
import Foundation
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit
#endif
@testable import LaunchPad

#if canImport(AppKit)
@Suite("DiffableDataSource Snapshot Builder")
struct DiffableDataSourceTests {

    // MARK: - Helpers

    private func makeItem(id: Int64, title: String, parentId: Int64? = nil) -> PageItem {
        return PageItem(
            id: id,
            uuid: "uuid-\(id)",
            type: .app,
            ordering: Int(id),
            parentId: parentId,
            app: AppInfo(
                id: id,
                title: title,
                bundleId: "com.test.\(title.lowercased().replacingOccurrences(of: " ", with: ""))",
                path: "/Applications/\(title).app",
                storeId: nil,
                category: nil
            ),
            group: nil
        )
    }

    private func makePage(count: Int, pageOffset: Int, parentId: Int64) -> [PageItem] {
        return (0..<count).map { i in
            let id = Int64(pageOffset * 100 + i + 1)
            let title = "App\(id)"
            return PageItem(
                id: id,
                uuid: "uuid-\(id)",
                type: .app,
                ordering: Int(id),
                parentId: parentId,
                app: AppInfo(
                    id: id,
                    title: title,
                    bundleId: "com.test.\(title.lowercased())",
                    path: "/Applications/\(title).app",
                    storeId: nil,
                    category: nil
                ),
                group: nil
            )
        }
    }

    private func sectionPage(_ index: Int) -> Section { .page(index) }
    private var sectionSearch: Section { .search }

    // MARK: - Multi-page Snapshot building

    @Test("3 pages x 35 items -> 3 sections, each 35 items")
    func threePages_35each_threeSections() {
        let page1 = makePage(count: 35, pageOffset: 0, parentId: 1)
        let page2 = makePage(count: 35, pageOffset: 1, parentId: 2)
        let page3 = makePage(count: 35, pageOffset: 2, parentId: 3)
        let pages = [page1, page2, page3]

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )

        #expect(snapshot.numberOfSections == 3)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(0)).count == 35)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(1)).count == 35)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(2)).count == 35)
    }

    @Test("Each section's items order matches input")
    func sectionItems_orderMatchesInput() {
        let page1 = makePage(count: 5, pageOffset: 0, parentId: 1)
        let pages = [page1]

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )

        let items = snapshot.itemIdentifiers(inSection: sectionPage(0))
        #expect(items.map(\.id) == page1.map(\.id))
    }

    // MARK: - Search Snapshot

    @Test("Search 'safari' -> single section with filtered results")
    func search_safari_singleSection_filteredResults() {
        let safariItem = makeItem(id: 1, title: "Safari")
        let finderItem = makeItem(id: 2, title: "Finder")
        let safariWebItem = makeItem(id: 3, title: "Safari Web Inspector")

        let page1 = [safariItem, finderItem, safariWebItem]
        let searchResults = [safariItem, safariWebItem]

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [page1],
            searchResults: searchResults,
            searchQuery: "safari"
        )

        #expect(snapshot.numberOfSections == 1)
        let items = snapshot.itemIdentifiers(inSection: sectionSearch)
        #expect(items.count == 2)
        let itemIds = items.map { $0.id }
        #expect(itemIds == [1, 3])
    }

    @Test("Search no results -> single empty section")
    func search_noResults_emptySection() {
        let page1 = [makeItem(id: 1, title: "Finder")]
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [page1],
            searchResults: [],
            searchQuery: "xyznonexistent"
        )

        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.itemIdentifiers(inSection: sectionSearch).isEmpty)
    }

    // MARK: - Clear search restores

    @Test("Clear search -> restores original paging sections")
    func clearSearch_restoresOriginalSections() {
        let page1 = makePage(count: 10, pageOffset: 0, parentId: 1)
        let page2 = makePage(count: 10, pageOffset: 1, parentId: 2)
        let pages = [page1, page2]

        // Build search snapshot first
        let searchSnapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: [page1[0]],
            searchQuery: "test"
        )
        #expect(searchSnapshot.numberOfSections == 1)

        // Clear search (searchResults = nil, searchQuery = nil)
        let restoredSnapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )

        #expect(restoredSnapshot.numberOfSections == 2)
        #expect(restoredSnapshot.itemIdentifiers(inSection: sectionPage(0)).count == 10)
        #expect(restoredSnapshot.itemIdentifiers(inSection: sectionPage(1)).count == 10)
    }

    // MARK: - Different screen widths

    @Test("7 column config: 35 items per page -> correct section/item counts")
    func config_7col_35perPage_correctCounts() {
        let items = (0..<70).map { i -> PageItem in
            let id = Int64(i + 1)
            let parentId = Int64(i / 35 + 1)
            return PageItem(
                id: id,
                uuid: "uuid-\(id)",
                type: .app,
                ordering: i,
                parentId: parentId,
                app: AppInfo(id: id, title: "App\(id)", bundleId: "com.test.app\(id)",
                              path: "/Applications/App\(id).app", storeId: nil, category: nil),
                group: nil
            )
        }
        let maxPerPage = 35
        let pages = stride(from: 0, to: items.count, by: maxPerPage).map { start in
            Array(items[start..<min(start + maxPerPage, items.count)])
        }

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )

        #expect(snapshot.numberOfSections == 2)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(0)).count == 35)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(1)).count == 35)
    }

    @Test("10 column config: 50 items per page -> correct section/item counts")
    func config_10col_50perPage_correctCounts() {
        let items = (0..<120).map { i -> PageItem in
            let id = Int64(i + 1)
            let parentId = Int64(i / 50 + 1)
            return PageItem(
                id: id,
                uuid: "uuid-\(id)",
                type: .app,
                ordering: i,
                parentId: parentId,
                app: AppInfo(id: id, title: "App\(id)", bundleId: "com.test.app\(id)",
                              path: "/Applications/App\(id).app", storeId: nil, category: nil),
                group: nil
            )
        }
        let maxPerPage = 50
        let pages = stride(from: 0, to: items.count, by: maxPerPage).map { start in
            Array(items[start..<min(start + maxPerPage, items.count)])
        }

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )

        #expect(snapshot.numberOfSections == 3)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(0)).count == 50)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(1)).count == 50)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(2)).count == 20)
    }

    @Test("9 column config: 45 items per page, partial last page -> correct last page count")
    func config_9col_partialPage_correctLastPage() {
        let items = (0..<60).map { i -> PageItem in
            let id = Int64(i + 1)
            let parentId = Int64(i / 45 + 1)
            return PageItem(
                id: id,
                uuid: "uuid-\(id)",
                type: .app,
                ordering: i,
                parentId: parentId,
                app: AppInfo(id: id, title: "App\(id)", bundleId: "com.test.app\(id)",
                              path: "/Applications/App\(id).app", storeId: nil, category: nil),
                group: nil
            )
        }
        let maxPerPage = 45
        let pages = stride(from: 0, to: items.count, by: maxPerPage).map { start in
            Array(items[start..<min(start + maxPerPage, items.count)])
        }

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )

        #expect(snapshot.numberOfSections == 2)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(0)).count == 45)
        #expect(snapshot.itemIdentifiers(inSection: sectionPage(1)).count == 15)
    }

    // MARK: - Empty data

    @Test("Empty pages -> 0 sections")
    func emptyPages_zeroSections() {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: nil,
            searchQuery: nil
        )

        #expect(snapshot.numberOfSections == 0)
        #expect(snapshot.itemIdentifiers.isEmpty)
    }

    // MARK: - Search results from different pages

    @Test("Search results from multiple pages -> merged into single search section")
    func searchResults_fromMultiplePages_mergedIntoOneSection() {
        let page1Item = makeItem(id: 1, title: "Safari", parentId: 1)
        let page2Item = makeItem(id: 50, title: "Safari Extension", parentId: 2)
        let page1 = [page1Item, makeItem(id: 2, title: "Finder", parentId: 1)]
        let page2 = [page2Item, makeItem(id: 51, title: "Mail", parentId: 2)]

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [page1, page2],
            searchResults: [page1Item, page2Item],
            searchQuery: "safari"
        )

        #expect(snapshot.numberOfSections == 1)
        let items = snapshot.itemIdentifiers(inSection: sectionSearch)
        #expect(items.count == 2)
        let itemIds = items.map { $0.id }.sorted()
        #expect(itemIds == [1, 50])
    }
}
#endif
