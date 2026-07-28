import Foundation

/// A complete, immutable view of the persisted page, folder, and app hierarchy.
public struct PersistedLayoutSnapshot: Sendable, Equatable {
    public let allItems: [PageItem]

    public var rootItems: [PageItem] {
        allItems.filter { $0.parentId == nil }.sorted(by: Self.layoutOrder)
    }

    public var pages: [PageItem] {
        rootItems.filter { $0.type == .page }
    }

    public var pageChildren: [Int64: [PageItem]] {
        Dictionary(uniqueKeysWithValues: pages.map { page in
            (page.id, children(of: page.id))
        })
    }

    public var folderChildren: [Int64: [PageItem]] {
        let folders = allItems.filter { $0.type == .group }
        return Dictionary(uniqueKeysWithValues: folders.map { folder in
            (folder.id, children(of: folder.id))
        })
    }

    public init(allItems: [PageItem]) {
        self.allItems = allItems
    }

    public func children(of parentID: Int64) -> [PageItem] {
        allItems
            .filter { $0.parentId == parentID }
            .sorted(by: Self.layoutOrder)
    }

    public var flattenedTopLevelIDs: [Int64] {
        pages.flatMap { pageChildren[$0.id] ?? [] }.map(\.id)
    }

    private static func layoutOrder(_ lhs: PageItem, _ rhs: PageItem) -> Bool {
        lhs.ordering == rhs.ordering
            ? lhs.id < rhs.id
            : lhs.ordering < rhs.ordering
    }
}
