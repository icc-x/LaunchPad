import Foundation
import LaunchPadProtocols

/// Describes validation and mutation failures in the pure layout domain.
enum LayoutDomainError: Error, Equatable {
    case invalidPageCapacity
    case missingItem(Int64)
    case missingAnchor(Int64)
    case missingCreatedFolderID
    case invalidType(Int64)
    case invalidParent(Int64)
    case selfDrop
    case duplicateItem(Int64)
    case duplicatePage(Int64)
    case orphanFolder(Int64)
    case unsupportedIntent
    case persistedStateMismatch
}

/// Identifies an ordered layout item without carrying persistence or UI state.
struct LayoutNode: Equatable, Sendable {
    let id: Int64
    let type: ItemType
}

/// Records persistence side effects implied by an otherwise pure mutation.
struct LayoutMutationEffects: Equatable {
    var folderIDsToDelete: Set<Int64> = []
    var appIDsToDelete: Set<Int64> = []
    var createdFolderTitle: String?
}

/// Describes a dense page replacement while retaining reusable page IDs.
struct PageRebuildPlan: Equatable {
    struct Page: Equatable {
        let existingPageID: Int64?
        let ordering: Int
        let itemIDs: [Int64]
    }

    let pages: [Page]
    let obsoletePageIDs: [Int64]
}

/// Owns the validated global order and non-nested folder child order.
struct LayoutDomainState: Equatable {
    private(set) var existingPageIDs: [Int64]
    private(set) var topLevelItems: [LayoutNode]
    private(set) var childrenByFolderID: [Int64: [LayoutNode]]

    init(
        existingPageIDs: [Int64],
        topLevelItems: [LayoutNode],
        childrenByFolderID: [Int64: [LayoutNode]]
    ) {
        self.existingPageIDs = existingPageIDs
        self.topLevelItems = topLevelItems
        self.childrenByFolderID = childrenByFolderID
    }

    /// Enforces globally unique IDs, valid node types, and exact folder maps.
    func validateState() throws {
        var seen = Set<Int64>()

        for pageID in existingPageIDs {
            guard seen.insert(pageID).inserted else {
                throw LayoutDomainError.duplicatePage(pageID)
            }
        }

        for node in topLevelItems {
            guard node.type == .app || node.type == .group else {
                throw LayoutDomainError.invalidType(node.id)
            }
            guard seen.insert(node.id).inserted else {
                throw LayoutDomainError.duplicateItem(node.id)
            }
            if node.type == .group, childrenByFolderID[node.id] == nil {
                throw LayoutDomainError.orphanFolder(node.id)
            }
        }

        let topFolderIDs = Set(
            topLevelItems.filter { $0.type == .group }.map(\.id)
        )
        for (folderID, children) in childrenByFolderID {
            guard topFolderIDs.contains(folderID) else {
                throw LayoutDomainError.orphanFolder(folderID)
            }
            for child in children {
                guard child.type == .app else {
                    throw LayoutDomainError.invalidType(child.id)
                }
                guard seen.insert(child.id).inserted else {
                    throw LayoutDomainError.duplicateItem(child.id)
                }
            }
        }
    }

    /// Validates all state and stable identifiers before any mutation begins.
    func validate(_ intent: LayoutDropIntent) throws {
        try validateState()

        switch intent {
        case .moveTopLevel(let itemID, let placement):
            try validateTopLevelNode(itemID)
            guard itemID != placement.anchorItemID else {
                throw LayoutDomainError.selfDrop
            }
            try validateTopLevelNode(placement.anchorItemID)

        case .addToFolder(let itemID, let folderID):
            try validateTopLevelApp(itemID)
            try validateTopLevelFolder(folderID)

        case .createFolder(let itemID, let targetItemID, _):
            guard itemID != targetItemID else {
                throw LayoutDomainError.selfDrop
            }
            try validateTopLevelApp(itemID)
            try validateTopLevelApp(targetItemID)

        case .reorderFolderItem(let itemID, let folderID, let placement):
            try validateTopLevelFolder(folderID)
            let children = try folderChildren(folderID)
            guard itemID != placement.anchorItemID else {
                throw LayoutDomainError.selfDrop
            }
            try validateChild(itemID, in: children, folderID: folderID)
            guard children.contains(where: {
                $0.id == placement.anchorItemID
            }) else {
                throw LayoutDomainError.missingAnchor(placement.anchorItemID)
            }

        case .removeFromFolder(let itemID, let folderID, let placement):
            try validateTopLevelFolder(folderID)
            let children = try folderChildren(folderID)
            try validateChild(itemID, in: children, folderID: folderID)
            try validateTopLevelNode(placement.anchorItemID)

        case .deleteFolder(let folderID):
            try validateTopLevelFolder(folderID)
            _ = try folderChildren(folderID)

        case .deleteApp(let itemID):
            try validateTopLevelApp(itemID)
        }
    }

    /// Applies an intent atomically after pre-validation and commits only a
    /// candidate that also satisfies all post-mutation invariants.
    mutating func apply(
        _ intent: LayoutDropIntent,
        createdFolderID: Int64? = nil
    ) throws -> LayoutMutationEffects {
        try validate(intent)

        var candidate = self
        let effects = try candidate.applyValidated(
            intent,
            createdFolderID: createdFolderID
        )
        try candidate.validateState()
        self = candidate
        return effects
    }

    /// Mutates a caller-validated state; callers needing atomicity use apply.
    mutating func applyValidated(
        _ intent: LayoutDropIntent,
        createdFolderID: Int64? = nil
    ) throws -> LayoutMutationEffects {
        var effects = LayoutMutationEffects()

        switch intent {
        case .moveTopLevel(let itemID, let placement):
            topLevelItems = try Self.moving(
                topLevelItems,
                itemID: itemID,
                placement: placement
            )

        case .addToFolder(let itemID, let folderID):
            guard let sourceIndex = topLevelItems.firstIndex(where: {
                $0.id == itemID
            }) else {
                throw LayoutDomainError.missingItem(itemID)
            }
            let source = topLevelItems.remove(at: sourceIndex)
            childrenByFolderID[folderID, default: []].append(source)

        case .createFolder(let itemID, let targetItemID, let title):
            guard let folderID = createdFolderID else {
                throw LayoutDomainError.missingCreatedFolderID
            }
            let occupiedIDs = Set(existingPageIDs)
                .union(topLevelItems.map(\.id))
                .union(childrenByFolderID.values.flatMap { $0.map(\.id) })
            guard !occupiedIDs.contains(folderID) else {
                throw LayoutDomainError.duplicateItem(folderID)
            }
            guard let sourceIndex = topLevelItems.firstIndex(where: {
                $0.id == itemID
            }) else {
                throw LayoutDomainError.missingItem(itemID)
            }
            guard let targetIndex = topLevelItems.firstIndex(where: {
                $0.id == targetItemID
            }) else {
                throw LayoutDomainError.missingItem(targetItemID)
            }

            let orderedChildren = [
                (sourceIndex, topLevelItems[sourceIndex]),
                (targetIndex, topLevelItems[targetIndex]),
            ].sorted { $0.0 < $1.0 }.map { $0.1 }
            let insertionIndex = topLevelItems[..<targetIndex]
                .filter { $0.id != itemID && $0.id != targetItemID }
                .count

            topLevelItems.removeAll {
                $0.id == itemID || $0.id == targetItemID
            }
            topLevelItems.insert(
                LayoutNode(id: folderID, type: .group),
                at: insertionIndex
            )
            childrenByFolderID[folderID] = orderedChildren
            effects.createdFolderTitle = title

        case .reorderFolderItem(let itemID, let folderID, let placement):
            guard let children = childrenByFolderID[folderID] else {
                throw LayoutDomainError.invalidParent(folderID)
            }
            childrenByFolderID[folderID] = try Self.moving(
                children,
                itemID: itemID,
                placement: placement
            )

        case .removeFromFolder(let itemID, let folderID, let placement):
            guard var children = childrenByFolderID[folderID],
                  let sourceIndex = children.firstIndex(where: {
                      $0.id == itemID
                  }),
                  let folderIndex = topLevelItems.firstIndex(where: {
                      $0.id == folderID
                  }) else {
                throw LayoutDomainError.invalidParent(folderID)
            }
            let source = children.remove(at: sourceIndex)
            let usesOwningFolderAnchor = placement.anchorItemID == folderID

            if children.count >= 2 {
                childrenByFolderID[folderID] = children
                if usesOwningFolderAnchor {
                    let insertionIndex = switch placement {
                    case .beforeItem: folderIndex
                    case .afterItem: folderIndex + 1
                    }
                    topLevelItems.insert(source, at: insertionIndex)
                } else {
                    topLevelItems = try Self.insertingExternal(
                        source,
                        into: topLevelItems,
                        placement: placement
                    )
                }
            } else {
                topLevelItems.remove(at: folderIndex)
                childrenByFolderID.removeValue(forKey: folderID)
                effects.folderIDsToDelete.insert(folderID)

                if let remaining = children.first {
                    topLevelItems.insert(remaining, at: folderIndex)
                }

                if usesOwningFolderAnchor {
                    let insertionIndex = switch placement {
                    case .beforeItem: folderIndex
                    case .afterItem:
                        children.isEmpty ? folderIndex : folderIndex + 1
                    }
                    topLevelItems.insert(source, at: insertionIndex)
                } else {
                    topLevelItems = try Self.insertingExternal(
                        source,
                        into: topLevelItems,
                        placement: placement
                    )
                }
            }

        case .deleteFolder(let folderID):
            guard let folderIndex = topLevelItems.firstIndex(where: {
                $0.id == folderID
            }), let children = childrenByFolderID[folderID] else {
                throw LayoutDomainError.invalidParent(folderID)
            }
            topLevelItems.remove(at: folderIndex)
            topLevelItems.insert(contentsOf: children, at: folderIndex)
            childrenByFolderID.removeValue(forKey: folderID)
            effects.folderIDsToDelete.insert(folderID)

        case .deleteApp(let itemID):
            guard let itemIndex = topLevelItems.firstIndex(where: {
                $0.id == itemID
            }) else {
                throw LayoutDomainError.missingItem(itemID)
            }
            topLevelItems.remove(at: itemIndex)
            effects.appIDsToDelete.insert(itemID)
        }

        return effects
    }

    /// Repositions a node after removing it, so the stable anchor is resolved
    /// against the final peer sequence rather than a stale array index.
    private static func moving(
        _ nodes: [LayoutNode],
        itemID: Int64,
        placement: ItemPlacement
    ) throws -> [LayoutNode] {
        guard itemID != placement.anchorItemID else {
            throw LayoutDomainError.selfDrop
        }
        guard let source = nodes.first(where: { $0.id == itemID }) else {
            throw LayoutDomainError.missingItem(itemID)
        }

        var result = nodes.filter { $0.id != itemID }
        guard let anchorIndex = result.firstIndex(where: {
            $0.id == placement.anchorItemID
        }) else {
            throw LayoutDomainError.missingAnchor(placement.anchorItemID)
        }
        let insertionIndex = switch placement {
        case .beforeItem: anchorIndex
        case .afterItem: anchorIndex + 1
        }
        result.insert(source, at: insertionIndex)
        return result
    }

    /// Inserts a folder child relative to a top-level anchor without changing
    /// the peer sequence until all insertion preconditions have passed.
    private static func insertingExternal(
        _ source: LayoutNode,
        into nodes: [LayoutNode],
        placement: ItemPlacement
    ) throws -> [LayoutNode] {
        guard !nodes.contains(where: { $0.id == source.id }) else {
            throw LayoutDomainError.duplicateItem(source.id)
        }
        guard let anchorIndex = nodes.firstIndex(where: {
            $0.id == placement.anchorItemID
        }) else {
            throw LayoutDomainError.missingAnchor(placement.anchorItemID)
        }

        var result = nodes
        let insertionIndex = switch placement {
        case .beforeItem: anchorIndex
        case .afterItem: anchorIndex + 1
        }
        result.insert(source, at: insertionIndex)
        return result
    }

    private func validateTopLevelNode(_ itemID: Int64) throws {
        guard let node = topLevelItems.first(where: { $0.id == itemID }) else {
            throw LayoutDomainError.missingItem(itemID)
        }
        guard node.type == .app || node.type == .group else {
            throw LayoutDomainError.invalidType(itemID)
        }
    }

    private func validateTopLevelApp(_ itemID: Int64) throws {
        guard let node = topLevelItems.first(where: { $0.id == itemID }) else {
            throw LayoutDomainError.missingItem(itemID)
        }
        guard node.type == .app else {
            throw LayoutDomainError.invalidType(itemID)
        }
    }

    private func validateTopLevelFolder(_ folderID: Int64) throws {
        guard let node = topLevelItems.first(where: {
            $0.id == folderID
        }) else {
            throw LayoutDomainError.missingItem(folderID)
        }
        guard node.type == .group else {
            throw LayoutDomainError.invalidType(folderID)
        }
        guard childrenByFolderID[folderID] != nil else {
            throw LayoutDomainError.invalidParent(folderID)
        }
    }

    private func folderChildren(_ folderID: Int64) throws -> [LayoutNode] {
        guard let children = childrenByFolderID[folderID] else {
            throw LayoutDomainError.invalidParent(folderID)
        }
        return children
    }

    private func validateChild(
        _ itemID: Int64,
        in children: [LayoutNode],
        folderID: Int64
    ) throws {
        guard let child = children.first(where: {
            $0.id == itemID
        }) else {
            throw LayoutDomainError.invalidParent(folderID)
        }
        guard child.type == .app else {
            throw LayoutDomainError.invalidType(itemID)
        }
    }

    /// Produces dense pages in global order and retains exactly one empty page.
    func makePageRebuildPlan(pageCapacity: Int) throws -> PageRebuildPlan {
        guard pageCapacity > 0 else {
            throw LayoutDomainError.invalidPageCapacity
        }
        try validateState()

        let chunks: [[LayoutNode]] = topLevelItems.isEmpty
            ? [[]]
            : stride(
                from: 0,
                to: topLevelItems.count,
                by: pageCapacity
            ).map { start in
                Array(
                    topLevelItems[
                        start..<min(
                            start + pageCapacity,
                            topLevelItems.count
                        )
                    ]
                )
            }
        let pages = chunks.enumerated().map { ordering, chunk in
            PageRebuildPlan.Page(
                existingPageID: ordering < existingPageIDs.count
                    ? existingPageIDs[ordering]
                    : nil,
                ordering: ordering,
                itemIDs: chunk.map(\.id)
            )
        }

        return PageRebuildPlan(
            pages: pages,
            obsoletePageIDs: Array(existingPageIDs.dropFirst(pages.count))
        )
    }
}
