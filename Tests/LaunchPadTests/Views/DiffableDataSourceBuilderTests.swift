import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@Suite("DiffableDataSourceBuilder")
struct DiffableDataSourceBuilderTests {
    @Test func buildSnapshot_emptyPages_returnsEmptySnapshot() {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: nil,
            searchQuery: nil
        )
        #expect(snapshot.numberOfSections == 0)
        #expect(snapshot.numberOfItems == 0)
    }

    @Test func buildSnapshot_singlePage_createsOneSection() {
        let items = TestDataFactory.makeAppItems(count: 5)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: nil,
            searchQuery: nil
        )
        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.numberOfItems(inSection: .page(0)) == 5)
    }

    @Test func buildSnapshot_multiplePages_createsMultipleSections() {
        let page1 = TestDataFactory.makeAppItems(count: 3, titlePrefix: "P1")
        let page2 = TestDataFactory.makeAppItems(count: 2, titlePrefix: "P2")
        let page3 = TestDataFactory.makeAppItems(count: 4, titlePrefix: "P3")
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [page1, page2, page3],
            searchResults: nil,
            searchQuery: nil
        )
        #expect(snapshot.numberOfSections == 3)
        #expect(snapshot.numberOfItems(inSection: .page(0)) == 3)
        #expect(snapshot.numberOfItems(inSection: .page(1)) == 2)
        #expect(snapshot.numberOfItems(inSection: .page(2)) == 4)
    }

    @Test func buildSnapshot_emptyPage_createsEmptySection() {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [[]],
            searchResults: nil,
            searchQuery: nil
        )
        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.numberOfItems(inSection: .page(0)) == 0)
    }

    @Test func buildSnapshot_searchResults_createsSearchSection() {
        let results = TestDataFactory.makeAppItems(count: 3)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: results,
            searchQuery: "test"
        )
        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.numberOfItems(inSection: .search) == 3)
    }

    @Test func buildSnapshot_emptySearchQuery_ignoresSearchResults() {
        let items = TestDataFactory.makeAppItems(count: 2)
        let results = TestDataFactory.makeAppItems(count: 5)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: results,
            searchQuery: ""
        )
        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.numberOfItems(inSection: .page(0)) == 2)
    }

    @Test func buildSnapshot_nilSearchQuery_ignoresSearchResults() {
        let items = TestDataFactory.makeAppItems(count: 2)
        let results = TestDataFactory.makeAppItems(count: 5)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: results,
            searchQuery: nil
        )
        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.numberOfItems(inSection: .page(0)) == 2)
    }

    @Test func buildSnapshot_nilSearchResults_usesPageMode() {
        let items = TestDataFactory.makeAppItems(count: 3)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: nil,
            searchQuery: "test"
        )
        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.numberOfItems(inSection: .page(0)) == 3)
    }

    @Test func buildSnapshot_emptySearchResults_returnsEmptySearchSection() {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: [],
            searchQuery: "test"
        )
        #expect(snapshot.numberOfSections == 1)
        #expect(snapshot.numberOfItems(inSection: .search) == 0)
    }

    @Test func buildSnapshot_normalMode_usesPageSections() {
        let items = TestDataFactory.makeAppItems(count: 2)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: nil,
            searchQuery: nil
        )
        let sections = snapshot.sectionIdentifiers
        #expect(sections.count == 1)
        if case .page(let index) = sections[0] {
            #expect(index == 0)
        } else {
            Issue.record("Expected .page section")
        }
    }

    @Test func buildSnapshot_searchMode_usesSearchSection() {
        let results = TestDataFactory.makeAppItems(count: 2)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: results,
            searchQuery: "test"
        )
        let sections = snapshot.sectionIdentifiers
        #expect(sections.count == 1)
        #expect(sections[0] == .search)
    }

    @Test("paged search contents 是权威输入并保持精确顺序")
    func searchResultPagesAreAuthoritative() {
        let items = TestDataFactory.makeAppItems(count: 9)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: Array(items.reversed()),
            searchQuery: "app",
            searchResultPages: [
                Array(items[0..<4]),
                Array(items[4..<8]),
                Array(items[8..<9]),
            ]
        )

        #expect(snapshot.sectionIdentifiers == [
            .searchPage(0), .searchPage(1), .searchPage(2),
        ])
        #expect(snapshot.itemIdentifiers.map(\.id) == items.map(\.id))
    }

    @Test("nil paged search 保留 legacy 单一 search section 与精确顺序")
    func nilSearchResultPagesUsesLegacySearchSection() {
        let items = TestDataFactory.makeAppItems(count: 4)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: items,
            searchQuery: "app",
            searchResultPages: nil
        )

        #expect(snapshot.sectionIdentifiers == [.search])
        #expect(snapshot.itemIdentifiers.map(\.id) == items.map(\.id))
    }
}
#endif
