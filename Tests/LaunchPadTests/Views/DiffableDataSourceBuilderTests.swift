import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for DiffableDataSourceBuilder (pure function, likely low coverage)
final class DiffableDataSourceBuilderTests: XCTestCase {

    // MARK: - Empty State

    func testBuildSnapshot_emptyPages_returnsEmptySnapshot() {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: nil,
            searchQuery: nil
        )
        XCTAssertEqual(snapshot.numberOfSections, 0)
        XCTAssertEqual(snapshot.numberOfItems, 0)
    }

    // MARK: - Normal Mode

    func testBuildSnapshot_singlePage_createsOneSection() {
        let items = TestDataFactory.makeAppItems(count: 5)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: nil,
            searchQuery: nil
        )
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 5)
    }

    func testBuildSnapshot_multiplePages_createsMultipleSections() {
        let page1 = TestDataFactory.makeAppItems(count: 3, titlePrefix: "P1")
        let page2 = TestDataFactory.makeAppItems(count: 2, titlePrefix: "P2")
        let page3 = TestDataFactory.makeAppItems(count: 4, titlePrefix: "P3")

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [page1, page2, page3],
            searchResults: nil,
            searchQuery: nil
        )
        XCTAssertEqual(snapshot.numberOfSections, 3)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 3)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(1)), 2)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(2)), 4)
    }

    func testBuildSnapshot_emptyPage_createsEmptySection() {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [[]],
            searchResults: nil,
            searchQuery: nil
        )
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 0)
    }

    // MARK: - Search Mode

    func testBuildSnapshot_searchResults_createsSearchSection() {
        let results = TestDataFactory.makeAppItems(count: 3)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: results,
            searchQuery: "test"
        )
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .search), 3)
    }

    func testBuildSnapshot_emptySearchQuery_ignoresSearchResults() {
        let items = TestDataFactory.makeAppItems(count: 2)
        let results = TestDataFactory.makeAppItems(count: 5)

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: results,
            searchQuery: ""
        )
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    func testBuildSnapshot_nilSearchQuery_ignoresSearchResults() {
        let items = TestDataFactory.makeAppItems(count: 2)
        let results = TestDataFactory.makeAppItems(count: 5)

        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: results,
            searchQuery: nil
        )
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 2)
    }

    func testBuildSnapshot_nilSearchResults_usesPageMode() {
        let items = TestDataFactory.makeAppItems(count: 3)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: nil,
            searchQuery: "test"
        )
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .page(0)), 3)
    }

    func testBuildSnapshot_emptySearchResults_returnsEmptySearchSection() {
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: [],
            searchQuery: "test"
        )
        XCTAssertEqual(snapshot.numberOfSections, 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .search), 0)
    }

    // MARK: - Section Identifiers

    func testBuildSnapshot_normalMode_usesPageSections() {
        let items = TestDataFactory.makeAppItems(count: 2)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [items],
            searchResults: nil,
            searchQuery: nil
        )
        let sections = snapshot.sectionIdentifiers
        XCTAssertEqual(sections.count, 1)
        // Should be .page(0)
        if case .page(let index) = sections[0] {
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("Expected .page section")
        }
    }

    func testBuildSnapshot_searchMode_usesSearchSection() {
        let results = TestDataFactory.makeAppItems(count: 2)
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: [],
            searchResults: results,
            searchQuery: "test"
        )
        let sections = snapshot.sectionIdentifiers
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0], .search)
    }
}
#endif
