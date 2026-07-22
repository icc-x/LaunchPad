import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("Pure layout domain state")
struct LayoutDomainStateTests {
    private func node(_ id: Int64, _ type: ItemType = .app) -> LayoutNode {
        LayoutNode(id: id, type: type)
    }

    private func state(
        pages: [Int64] = [100],
        top: [LayoutNode],
        folders: [Int64: [LayoutNode]] = [:]
    ) -> LayoutDomainState {
        LayoutDomainState(
            existingPageIDs: pages,
            topLevelItems: top,
            childrenByFolderID: folders
        )
    }

    @Test("顶层 before/after 使用稳定 anchor")
    func moveTopLevelBeforeAndAfter() throws {
        var before = state(
            top: [node(1), node(2), node(3), node(4, .group)],
            folders: [4: [node(40), node(41)]]
        )
        _ = try before.apply(
            .moveTopLevel(itemID: 4, placement: .beforeItem(itemID: 2))
        )
        #expect(before.topLevelItems.map(\.id) == [1, 4, 2, 3])

        var after = state(top: [node(1), node(2), node(3)])
        _ = try after.apply(
            .moveTopLevel(itemID: 1, placement: .afterItem(itemID: 3))
        )
        #expect(after.topLevelItems.map(\.id) == [2, 3, 1])
    }

    @Test("顶层 stale/self drop 零变更")
    func moveTopLevelInvalidInputsDoNotMutate() {
        let original = state(top: [node(1), node(2)])
        let cases: [(LayoutDropIntent, LayoutDomainError)] = [
            (
                .moveTopLevel(
                    itemID: 99,
                    placement: .beforeItem(itemID: 2)
                ),
                .missingItem(99)
            ),
            (
                .moveTopLevel(
                    itemID: 1,
                    placement: .beforeItem(itemID: 99)
                ),
                .missingItem(99)
            ),
            (
                .moveTopLevel(
                    itemID: 1,
                    placement: .afterItem(itemID: 1)
                ),
                .selfDrop
            ),
        ]

        for (intent, error) in cases {
            expectApplyFailure(intent, in: original, expected: error)
        }
    }

    @Test("新文件夹占 target 位置且 children 保持原全局相对顺序")
    func createFolderPreservesGlobalOrder() throws {
        for (source, target) in [(Int64(3), Int64(1)), (Int64(1), Int64(3))] {
            var sut = state(top: [node(1), node(2), node(3)])
            let effects = try sut.apply(
                .createFolder(
                    itemID: source,
                    targetItemID: target,
                    title: "Work"
                ),
                createdFolderID: 90
            )
            #expect(
                sut.topLevelItems.map(\.id)
                    == (target == 1 ? [90, 2] : [2, 90])
            )
            #expect(sut.childrenByFolderID[90]?.map(\.id) == [1, 3])
            #expect(effects.createdFolderTitle == "Work")
        }
    }

    @Test("create folder 拒绝 self/group/stale 且不变更")
    func createFolderRejectsInvalidInputs() {
        let original = state(
            top: [node(1), node(2), node(7, .group)],
            folders: [7: [node(70), node(71)]]
        )
        let cases: [(LayoutDropIntent, LayoutDomainError)] = [
            (
                .createFolder(
                    itemID: 1,
                    targetItemID: 1,
                    title: "Work"
                ),
                .selfDrop
            ),
            (
                .createFolder(
                    itemID: 7,
                    targetItemID: 1,
                    title: "Work"
                ),
                .invalidType(7)
            ),
            (
                .createFolder(
                    itemID: 1,
                    targetItemID: 7,
                    title: "Work"
                ),
                .invalidType(7)
            ),
            (
                .createFolder(
                    itemID: 99,
                    targetItemID: 1,
                    title: "Work"
                ),
                .missingItem(99)
            ),
            (
                .createFolder(
                    itemID: 1,
                    targetItemID: 99,
                    title: "Work"
                ),
                .missingItem(99)
            ),
        ]

        for (intent, error) in cases {
            expectApplyFailure(
                intent,
                createdFolderID: 90,
                in: original,
                expected: error
            )
        }
    }

    @Test("create folder 拒绝缺失或冲突的 generated ID 且不变更")
    func createFolderRejectsMissingOrOccupiedGeneratedID() {
        let original = state(
            top: [node(1), node(2), node(7, .group)],
            folders: [7: [node(70), node(71)]]
        )
        let intent = LayoutDropIntent.createFolder(
            itemID: 1,
            targetItemID: 2,
            title: "Work"
        )
        let cases: [(Int64?, LayoutDomainError)] = [
            (nil, .missingCreatedFolderID),
            (100, .duplicateItem(100)),
            (2, .duplicateItem(2)),
            (70, .duplicateItem(70)),
        ]

        for (createdFolderID, error) in cases {
            expectApplyFailure(
                intent,
                createdFolderID: createdFolderID,
                in: original,
                expected: error
            )
        }
    }

    @Test("add folder 只接受顶层 app 和顶层 group")
    func addToFolderAppendsAndRejectsInvalidTypes() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(8, .group)],
            folders: [7: [node(70), node(71)], 8: [node(80), node(81)]]
        )
        _ = try sut.apply(.addToFolder(itemID: 1, folderID: 7))
        #expect(sut.topLevelItems.map(\.id) == [7, 8])
        #expect(sut.childrenByFolderID[7]?.map(\.id) == [70, 71, 1])

        let original = sut
        expectApplyFailure(
            .addToFolder(itemID: 8, folderID: 7),
            in: original,
            expected: .invalidType(8)
        )
    }

    @Test("add folder 拒绝 stale 与错误类型且不变更")
    func addToFolderRejectsMissingAndWrongTypes() {
        let original = state(
            top: [node(1), node(2), node(7, .group)],
            folders: [7: [node(70), node(71)]]
        )
        let cases: [(LayoutDropIntent, LayoutDomainError)] = [
            (.addToFolder(itemID: 99, folderID: 7), .missingItem(99)),
            (.addToFolder(itemID: 1, folderID: 99), .missingItem(99)),
            (.addToFolder(itemID: 7, folderID: 7), .invalidType(7)),
            (.addToFolder(itemID: 1, folderID: 2), .invalidType(2)),
        ]

        for (intent, error) in cases {
            expectApplyFailure(intent, in: original, expected: error)
        }
    }

    @Test("folder 第 36 项可 before/after 重排，stale anchor 零变更")
    func reorderFolderItemThirtySix() throws {
        let children = (1...36).map { node(Int64($0)) }
        var sut = state(
            top: [node(70, .group)],
            folders: [70: children]
        )
        _ = try sut.apply(
            .reorderFolderItem(
                itemID: 36,
                folderID: 70,
                placement: .beforeItem(itemID: 1)
            )
        )
        #expect(sut.childrenByFolderID[70]?.first?.id == 36)

        _ = try sut.apply(
            .reorderFolderItem(
                itemID: 36,
                folderID: 70,
                placement: .afterItem(itemID: 35)
            )
        )
        #expect(sut.childrenByFolderID[70]?.last?.id == 36)

        let original = sut
        expectApplyFailure(
            .reorderFolderItem(
                itemID: 36,
                folderID: 70,
                placement: .afterItem(itemID: 99)
            ),
            in: original,
            expected: .missingAnchor(99)
        )
    }

    @Test("folder 重排拒绝 stale、错误类型与 self drop 且不变更")
    func reorderFolderItemRejectsInvalidInputs() {
        let original = state(
            top: [node(1), node(7, .group)],
            folders: [7: [node(70), node(71)]]
        )
        let cases: [(LayoutDropIntent, LayoutDomainError)] = [
            (
                .reorderFolderItem(
                    itemID: 70,
                    folderID: 99,
                    placement: .beforeItem(itemID: 71)
                ),
                .missingItem(99)
            ),
            (
                .reorderFolderItem(
                    itemID: 70,
                    folderID: 1,
                    placement: .beforeItem(itemID: 71)
                ),
                .invalidType(1)
            ),
            (
                .reorderFolderItem(
                    itemID: 99,
                    folderID: 7,
                    placement: .beforeItem(itemID: 71)
                ),
                .invalidParent(7)
            ),
            (
                .reorderFolderItem(
                    itemID: 70,
                    folderID: 7,
                    placement: .afterItem(itemID: 70)
                ),
                .selfDrop
            ),
            (
                .reorderFolderItem(
                    itemID: 70,
                    folderID: 7,
                    placement: .afterItem(itemID: 99)
                ),
                .missingAnchor(99)
            ),
        ]

        for (intent, error) in cases {
            expectApplyFailure(intent, in: original, expected: error)
        }
    }

    @Test("移出三项文件夹保留两个连续 child")
    func removeFromThreeItemFolderKeepsFolder() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(2)],
            folders: [7: [node(70), node(71), node(72)]]
        )
        let effects = try sut.apply(
            .removeFromFolder(
                itemID: 72,
                folderID: 7,
                placement: .beforeItem(itemID: 2)
            )
        )
        #expect(sut.topLevelItems.map(\.id) == [1, 7, 72, 2])
        #expect(sut.childrenByFolderID[7]?.map(\.id) == [70, 71])
        #expect(effects.folderIDsToDelete.isEmpty)
    }

    @Test("移出二项文件夹时 sibling 原位替换 folder")
    func removeFromTwoItemFolderAutoDissolves() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(2)],
            folders: [7: [node(70), node(71)]]
        )
        let effects = try sut.apply(
            .removeFromFolder(
                itemID: 71,
                folderID: 7,
                placement: .beforeItem(itemID: 2)
            )
        )
        #expect(sut.topLevelItems.map(\.id) == [1, 70, 71, 2])
        #expect(sut.childrenByFolderID[7] == nil)
        #expect(effects.folderIDsToDelete == [7])
    }

    @Test("folder 自身可作拖出锚点，单 child 移出后删除空 folder")
    func removeOnlyChildAllowsOwningFolderAnchor() throws {
        for placement in [
            ItemPlacement.beforeItem(itemID: 7),
            ItemPlacement.afterItem(itemID: 7),
        ] {
            var sut = state(
                top: [node(1), node(7, .group), node(2)],
                folders: [7: [node(70)]]
            )
            let effects = try sut.apply(
                .removeFromFolder(
                    itemID: 70,
                    folderID: 7,
                    placement: placement
                )
            )
            #expect(sut.topLevelItems.map(\.id) == [1, 70, 2])
            #expect(effects.folderIDsToDelete == [7])
        }
    }

    @Test("保留 folder 分支支持 owning/external anchor 的 before/after")
    func removeFromFolderKeepsStableAnchorsWhenFolderRemains() throws {
        let cases: [(ItemPlacement, [Int64])] = [
            (.beforeItem(itemID: 7), [1, 72, 7, 2]),
            (.afterItem(itemID: 7), [1, 7, 72, 2]),
            (.beforeItem(itemID: 2), [1, 7, 72, 2]),
            (.afterItem(itemID: 2), [1, 7, 2, 72]),
        ]

        for (placement, expectedIDs) in cases {
            var sut = state(
                top: [node(1), node(7, .group), node(2)],
                folders: [7: [node(70), node(71), node(72)]]
            )
            let effects = try sut.apply(
                .removeFromFolder(
                    itemID: 72,
                    folderID: 7,
                    placement: placement
                )
            )
            #expect(sut.topLevelItems.map(\.id) == expectedIDs)
            #expect(sut.childrenByFolderID[7]?.map(\.id) == [70, 71])
            #expect(effects.folderIDsToDelete.isEmpty)
        }
    }

    @Test("解散 folder 分支支持 external anchor 的 before/after")
    func removeFromFolderDissolvesWithStableExternalAnchors() throws {
        let cases: [(ItemPlacement, [Int64])] = [
            (.beforeItem(itemID: 2), [1, 70, 71, 2]),
            (.afterItem(itemID: 2), [1, 70, 2, 71]),
        ]

        for (placement, expectedIDs) in cases {
            var sut = state(
                top: [node(1), node(7, .group), node(2)],
                folders: [7: [node(70), node(71)]]
            )
            let effects = try sut.apply(
                .removeFromFolder(
                    itemID: 71,
                    folderID: 7,
                    placement: placement
                )
            )
            #expect(sut.topLevelItems.map(\.id) == expectedIDs)
            #expect(sut.childrenByFolderID[7] == nil)
            #expect(effects.folderIDsToDelete == [7])
        }
    }

    @Test("移出 folder 拒绝 stale 与错误类型且不变更")
    func removeFromFolderRejectsInvalidInputs() {
        let original = state(
            top: [node(1), node(7, .group), node(2)],
            folders: [7: [node(70), node(71), node(72)]]
        )
        let cases: [(LayoutDropIntent, LayoutDomainError)] = [
            (
                .removeFromFolder(
                    itemID: 70,
                    folderID: 99,
                    placement: .beforeItem(itemID: 2)
                ),
                .missingItem(99)
            ),
            (
                .removeFromFolder(
                    itemID: 70,
                    folderID: 1,
                    placement: .beforeItem(itemID: 2)
                ),
                .invalidType(1)
            ),
            (
                .removeFromFolder(
                    itemID: 99,
                    folderID: 7,
                    placement: .beforeItem(itemID: 2)
                ),
                .invalidParent(7)
            ),
            (
                .removeFromFolder(
                    itemID: 70,
                    folderID: 7,
                    placement: .afterItem(itemID: 99)
                ),
                .missingItem(99)
            ),
        ]

        for (intent, error) in cases {
            expectApplyFailure(intent, in: original, expected: error)
        }
    }

    @Test("安全删除在 folder 原位展开 children")
    func deleteFolderPreservesChildren() throws {
        var sut = state(
            top: [node(1), node(7, .group), node(2)],
            folders: [7: [node(70), node(71)]]
        )
        let effects = try sut.apply(.deleteFolder(folderID: 7))
        #expect(sut.topLevelItems.map(\.id) == [1, 70, 71, 2])
        #expect(sut.childrenByFolderID[7] == nil)
        #expect(effects.folderIDsToDelete == [7])
    }

    @Test("删除 folder 拒绝 stale 与 app-as-folder 且不变更")
    func deleteFolderRejectsInvalidInputs() {
        let original = state(
            top: [node(1), node(7, .group)],
            folders: [7: [node(70), node(71)]]
        )

        expectApplyFailure(
            .deleteFolder(folderID: 99),
            in: original,
            expected: .missingItem(99)
        )
        expectApplyFailure(
            .deleteFolder(folderID: 1),
            in: original,
            expected: .invalidType(1)
        )
    }

    @Test("page plan 复用、创建、删除并保留唯一空页")
    func pagePlanCoversEveryCardinality() throws {
        let overflow = state(
            pages: [100, 101],
            top: (1...5).map { node(Int64($0)) }
        )
        #expect(
            try overflow.makePageRebuildPlan(pageCapacity: 2)
                == PageRebuildPlan(
                    pages: [
                        .init(
                            existingPageID: 100,
                            ordering: 0,
                            itemIDs: [1, 2]
                        ),
                        .init(
                            existingPageID: 101,
                            ordering: 1,
                            itemIDs: [3, 4]
                        ),
                        .init(
                            existingPageID: nil,
                            ordering: 2,
                            itemIDs: [5]
                        ),
                    ],
                    obsoletePageIDs: []
                )
        )

        let compacted = state(
            pages: [100, 101, 102],
            top: [node(1), node(2), node(3)]
        )
        #expect(
            try compacted.makePageRebuildPlan(pageCapacity: 2)
                == PageRebuildPlan(
                    pages: [
                        .init(
                            existingPageID: 100,
                            ordering: 0,
                            itemIDs: [1, 2]
                        ),
                        .init(
                            existingPageID: 101,
                            ordering: 1,
                            itemIDs: [3]
                        ),
                    ],
                    obsoletePageIDs: [102]
                )
        )

        let empty = state(pages: [100, 101], top: [])
        #expect(
            try empty.makePageRebuildPlan(pageCapacity: 35)
                == PageRebuildPlan(
                    pages: [
                        .init(
                            existingPageID: 100,
                            ordering: 0,
                            itemIDs: []
                        )
                    ],
                    obsoletePageIDs: [101]
                )
        )
    }

    @Test("非法容量、重复 ID、非法类型与 orphan folder 被拒绝")
    func invariantsRejectCorruptState() {
        let corruptStates = [
            state(pages: [100, 100], top: [node(1)]),
            state(top: [node(1), node(1)]),
            state(top: [node(1, .page)]),
            state(top: [node(7, .group)]),
            state(
                top: [node(7, .group)],
                folders: [7: [node(8, .group)]]
            ),
            state(
                top: [node(7, .group)],
                folders: [7: [node(8, .page)]]
            ),
            state(
                top: [node(7, .group)],
                folders: [7: [node(70), node(70)]]
            ),
            state(
                top: [node(1), node(7, .group)],
                folders: [7: [node(1)]]
            ),
            state(pages: [100], top: [node(100)]),
            state(top: [node(1)], folders: [7: [node(70)]]),
        ]

        for original in corruptStates {
            #expect(throws: LayoutDomainError.self) {
                _ = try original.makePageRebuildPlan(pageCapacity: 35)
            }

            var sut = original
            #expect(throws: LayoutDomainError.self) {
                _ = try sut.apply(.deleteFolder(folderID: 99))
            }
            #expect(sut == original)
        }

        let valid = state(top: [node(1)])
        #expect(throws: LayoutDomainError.invalidPageCapacity) {
            _ = try valid.makePageRebuildPlan(pageCapacity: 0)
        }
    }

    private func expectApplyFailure(
        _ intent: LayoutDropIntent,
        createdFolderID: Int64? = nil,
        in original: LayoutDomainState,
        expected: LayoutDomainError
    ) {
        var sut = original
        #expect(throws: expected) {
            _ = try sut.apply(intent, createdFolderID: createdFolderID)
        }
        #expect(sut == original)
    }
}
