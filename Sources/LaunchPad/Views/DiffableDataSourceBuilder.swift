#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

// MARK: - Section definition

/// DiffableDataSource section type
/// In normal mode each page is a section, in search mode there is a single search section
public enum Section: Hashable {
    case page(Int)
    case search
}

// MARK: - Snapshot Builder

/// DiffableDataSource Snapshot builder pure function
public enum DiffableDataSourceBuilder {

    /// Build a DiffableDataSourceSnapshot
    ///
    /// - Parameters:
    ///   - pages: PageItem arrays grouped by page, each element represents one page
    ///   - searchResults: Search results (nil means non-search mode)
    ///   - searchQuery: Current search query (nil or empty means non-search mode)
    /// - Returns: The built snapshot
    public static func buildSnapshot(
        pages: [[PageItem]],
        searchResults: [PageItem]?,
        searchQuery: String?
    ) -> NSDiffableDataSourceSnapshot<Section, PageItem> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, PageItem>()

        // Search mode: single section containing filtered results
        if let results = searchResults, let query = searchQuery, !query.isEmpty {
            snapshot.appendSections([.search])
            snapshot.appendItems(results, toSection: .search)
            return snapshot
        }

        // Normal mode: each page is a section
        let sections = pages.indices.map { Section.page($0) }
        snapshot.appendSections(sections)

        for (index, pageItems) in pages.enumerated() {
            snapshot.appendItems(pageItems, toSection: .page(index))
        }

        return snapshot
    }
}
#endif
