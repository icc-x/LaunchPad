import Foundation
import SQLite3
import Testing
import LaunchPadProtocols
@testable import LaunchPad

@Suite("StorageManager atomic layout mutations")
struct StorageManagerLayoutMutationTests {
    private struct IDs {
        let firstPage: Int64
        let secondPage: Int64
        let first: Int64
        let second: Int64
        let third: Int64
        let fourth: Int64
    }

    enum RejectedMove: CaseIterable, Sendable {
        case staleSource
        case staleAnchor
        case selfDrop
        case invalidCapacity
    }

    enum CorruptTopology: CaseIterable, Sendable {
        case invalidRoot
        case invalidPageChild
        case invalidFolderChild
        case duplicateRelationship
        case unreachableRelationship
        case orphanRow

        var expectedError: LayoutDomainError {
            switch self {
            case .invalidRoot, .unreachableRelationship, .orphanRow:
                return .invalidParent(90)
            case .invalidPageChild, .invalidFolderChild:
                return .invalidType(90)
            case .duplicateRelationship:
                return .duplicateItem(90)
            }
        }
    }

    enum LayoutFault: CaseIterable, Sendable {
        case begin
        case fetchPrepare
        case fetchFirstStep
        case fetchTerminalStep
        case itemPrepare
        case itemBind
        case itemStep
        case itemChanges
        case pageBind
        case pageChanges
        case insertPageStep
        case deletePageStep
        case commit

        var point: SQLiteFaultPoint {
            switch self {
            case .begin:
                return .begin
            case .fetchPrepare:
                return .prepare(.fetchAllItems)
            case .fetchFirstStep, .fetchTerminalStep:
                return .step(.fetchAllItems)
            case .itemPrepare:
                return .prepare(.updateLayoutItem)
            case .itemBind:
                return .bind(.updateLayoutItem, index: 1)
            case .itemStep:
                return .step(.updateLayoutItem)
            case .itemChanges:
                return .changes(.updateLayoutItem)
            case .pageBind:
                return .bind(.updatePageOrdering, index: 1)
            case .pageChanges:
                return .changes(.updatePageOrdering)
            case .insertPageStep:
                return .step(.insertPage)
            case .deletePageStep:
                return .step(.deleteLayoutItem)
            case .commit:
                return .commit
            }
        }

        var occurrence: Int {
            switch self {
            case .fetchTerminalStep:
                // Two pages plus four apps are returned before terminal DONE.
                return 7
            case .itemStep:
                return 2
            default:
                return 1
            }
        }

        var code: Int32 {
            switch self {
            case .itemBind, .pageBind:
                return SQLITE_RANGE
            case .itemChanges, .pageChanges:
                return 0
            case .insertPageStep:
                return SQLITE_FULL
            case .itemStep, .deletePageStep:
                return SQLITE_CONSTRAINT
            case .begin:
                return SQLITE_BUSY
            default:
                return SQLITE_IOERR
            }
        }

        var pageCapacity: Int {
            switch self {
            case .insertPageStep:
                return 1
            case .deletePageStep:
                return 4
            default:
                return 2
            }
        }

        var expectedError: StorageError {
            switch self {
            case .begin:
                return .beginFailed
            case .fetchPrepare, .itemPrepare:
                return .prepareFailed
            case .fetchFirstStep, .fetchTerminalStep:
                return .queryFailed
            case .itemBind, .pageBind:
                return .bindFailed
            case .itemStep, .itemChanges, .pageChanges:
                return .updateFailed
            case .insertPageStep:
                return .insertFailed
            case .deletePageStep:
                return .deleteFailed
            case .commit:
                return .commitFailed
            }
        }

        var expectedRollbackCount: Int {
            self == .begin ? 0 : 1
        }
    }

    private func makeTwoPageLayout(
        script: SQLiteFaultScript = SQLiteFaultScript()
    ) throws -> (StorageManager, IDs, SQLiteFaultScript) {
        let storage = try StorageManager(
            dbPath: ":memory:",
            schemaSetup: { Schema.setupSchema(db: $0) },
            faultInjector: script.result(for:)
        )
        let firstPage = try storage.insertItem(
            TestDataFactory.makePageItem(
                uuid: "page-1",
                type: .page,
                ordering: 0
            )
        )
        let secondPage = try storage.insertItem(
            TestDataFactory.makePageItem(
                uuid: "page-2",
                type: .page,
                ordering: 1
            )
        )

        func insertApp(
            _ index: Int,
            pageID: Int64,
            ordering: Int
        ) throws -> Int64 {
            try storage.insertItem(
                TestDataFactory.makePageItem(
                    uuid: "layout-app-\(index)",
                    type: .app,
                    ordering: ordering,
                    parentId: pageID,
                    app: TestDataFactory.makeAppInfo(
                        title: "App \(index)",
                        bundleId: "com.test.layout.\(index)"
                    )
                )
            )
        }

        let first = try insertApp(1, pageID: firstPage, ordering: 0)
        let second = try insertApp(2, pageID: firstPage, ordering: 1)
        let third = try insertApp(3, pageID: secondPage, ordering: 0)
        let fourth = try insertApp(4, pageID: secondPage, ordering: 1)
        return (
            storage,
            IDs(
                firstPage: firstPage,
                secondPage: secondPage,
                first: first,
                second: second,
                third: third,
                fourth: fourth
            ),
            script
        )
    }

    private func makeCorruptLayout(
        _ topology: CorruptTopology
    ) throws -> (StorageManager, SQLiteFaultScript) {
        let script = SQLiteFaultScript()
        let storage = try StorageManager(
            dbPath: ":memory:",
            schemaSetup: { database in
                let statements = [
                    """
                    CREATE TABLE items (
                        id INTEGER NOT NULL,
                        uuid TEXT NOT NULL,
                        type INTEGER NOT NULL,
                        parent_id INTEGER,
                        ordering INTEGER NOT NULL
                    )
                    """,
                    """
                    CREATE TABLE apps (
                        item_id INTEGER,
                        title TEXT,
                        bundle_id TEXT,
                        path TEXT,
                        store_id TEXT,
                        category TEXT
                    )
                    """,
                    "CREATE TABLE groups (item_id INTEGER, title TEXT)",
                    """
                    INSERT INTO items (id, uuid, type, parent_id, ordering)
                    VALUES
                        (1, 'corrupt-page', \(ItemType.page.rawValue), NULL, 0),
                        (2, 'corrupt-source', \(ItemType.app.rawValue), 1, 0),
                        (3, 'corrupt-anchor', \(ItemType.app.rawValue), 1, 1)
                    """,
                ]
                for statement in statements {
                    precondition(
                        sqlite3_exec(database, statement, nil, nil, nil)
                            == SQLITE_OK
                    )
                }

                let corruptionSQL: String
                switch topology {
                case .invalidRoot:
                    corruptionSQL = """
                        INSERT INTO items VALUES
                            (90, 'invalid-root', \(ItemType.app.rawValue), NULL, 2)
                        """
                case .invalidPageChild:
                    corruptionSQL = """
                        INSERT INTO items VALUES
                            (90, 'invalid-page-child', \(ItemType.page.rawValue), 1, 2)
                        """
                case .invalidFolderChild:
                    precondition(sqlite3_exec(
                        database,
                        """
                        INSERT INTO items VALUES
                            (10, 'folder', \(ItemType.group.rawValue), 1, 2)
                        """,
                        nil,
                        nil,
                        nil
                    ) == SQLITE_OK)
                    corruptionSQL = """
                        INSERT INTO items VALUES
                            (90, 'invalid-folder-child', \(ItemType.group.rawValue), 10, 0)
                        """
                case .duplicateRelationship:
                    corruptionSQL = """
                        INSERT INTO items VALUES
                            (90, 'duplicate-a', \(ItemType.app.rawValue), 1, 2),
                            (90, 'duplicate-b', \(ItemType.app.rawValue), 1, 3)
                        """
                case .unreachableRelationship:
                    corruptionSQL = """
                        INSERT INTO items VALUES
                            (90, 'nested-under-app', \(ItemType.app.rawValue), 2, 0)
                        """
                case .orphanRow:
                    corruptionSQL = """
                        INSERT INTO items VALUES
                            (90, 'orphan-row', \(ItemType.app.rawValue), 999, 0)
                        """
                }
                precondition(
                    sqlite3_exec(database, corruptionSQL, nil, nil, nil)
                        == SQLITE_OK
                )
            },
            faultInjector: script.result(for:)
        )
        return (storage, script)
    }

    private func expectNoLayoutWrites(_ script: SQLiteFaultScript) {
        let kinds: [SQLiteStatementKind] = [
            .updateLayoutItem,
            .updatePageOrdering,
            .insertPage,
            .deleteLayoutItem,
        ]
        for kind in kinds {
            #expect(script.invocationCount(for: .prepare(kind)) == 0)
            #expect(script.invocationCount(for: .step(kind)) == 0)
            #expect(script.invocationCount(for: .changes(kind)) == 0)
        }
    }

    @Test("空数据库 complete snapshot 返回空行集")
    func persistedSnapshotReadsEmptyDatabase() throws {
        let sut = try StorageManager(dbPath: ":memory:")

        let snapshot = try sut.persistedLayoutSnapshot()

        #expect(snapshot.allItems.isEmpty)
        #expect(snapshot.pages.isEmpty)
        #expect(snapshot.flattenedTopLevelIDs.isEmpty)
    }

    @Test("跨页 before 提交稳定全局顺序和连续 page ordering")
    func moveTopLevelPersistsCrossPageOrder() throws {
        let (sut, ids, _) = try makeTwoPageLayout()
        try sut.apply(
            .moveTopLevel(
                itemID: ids.fourth,
                placement: .beforeItem(itemID: ids.second)
            ),
            pageCapacity: 2
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.pages.map(\.ordering) == [0, 1])
        #expect(snapshot.flattenedTopLevelIDs == [
            ids.first, ids.fourth, ids.second, ids.third,
        ])
        #expect(snapshot.pageChildren.values.allSatisfy { children in
            children.map(\.ordering) == Array(0..<children.count)
        })
    }

    @Test("same-page after 使用 anchor 当前数据库位置")
    func moveTopLevelPersistsSamePageAfter() throws {
        let (sut, ids, _) = try makeTwoPageLayout()
        try sut.apply(
            .moveTopLevel(
                itemID: ids.first,
                placement: .afterItem(itemID: ids.second)
            ),
            pageCapacity: 2
        )

        #expect(try sut.persistedLayoutSnapshot().flattenedTopLevelIDs == [
            ids.second, ids.first, ids.third, ids.fourth,
        ])
    }

    @Test("扩页、复用页和缩页均保持 dense page cardinality")
    func pageRebuildCardinalityPersistsExactly() throws {
        do {
            let (sut, ids, _) = try makeTwoPageLayout()
            try sut.apply(
                .moveTopLevel(
                    itemID: ids.fourth,
                    placement: .beforeItem(itemID: ids.first)
                ),
                pageCapacity: 1
            )
            let snapshot = try sut.persistedLayoutSnapshot()
            #expect(snapshot.pages.count == 4)
            #expect(snapshot.pages.prefix(2).map(\.id) == [
                ids.firstPage, ids.secondPage,
            ])
            #expect(snapshot.pages.map(\.ordering) == [0, 1, 2, 3])
            #expect(snapshot.pageChildren.values.allSatisfy {
                $0.count == 1 && $0[0].ordering == 0
            })
        }

        do {
            let (sut, ids, _) = try makeTwoPageLayout()
            try sut.apply(
                .moveTopLevel(
                    itemID: ids.fourth,
                    placement: .beforeItem(itemID: ids.first)
                ),
                pageCapacity: 4
            )
            let snapshot = try sut.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [ids.firstPage])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [
                ids.fourth, ids.first, ids.second, ids.third,
            ])
            #expect(!snapshot.allItems.contains { $0.id == ids.secondPage })
        }
    }

    @Test("移动 top-level folder 保留完整 folder children")
    func moveTopLevelFolderPreservesChildren() throws {
        let sut = try StorageManager(dbPath: ":memory:")
        let pageID = try sut.insertItem(
            TestDataFactory.makePageItem(uuid: "folder-page", type: .page)
        )
        let folderID = try sut.insertItem(TestDataFactory.makePageItem(
            uuid: "folder",
            type: .group,
            ordering: 0,
            parentId: pageID,
            group: TestDataFactory.makeGroupInfo(title: "Utilities")
        ))
        let anchorID = try sut.insertItem(TestDataFactory.makePageItem(
            uuid: "folder-anchor",
            type: .app,
            ordering: 1,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "folder.anchor")
        ))
        let firstChildID = try sut.insertItem(TestDataFactory.makePageItem(
            uuid: "folder-child-1",
            type: .app,
            ordering: 0,
            parentId: folderID,
            app: TestDataFactory.makeAppInfo(bundleId: "folder.child.1")
        ))
        let secondChildID = try sut.insertItem(TestDataFactory.makePageItem(
            uuid: "folder-child-2",
            type: .app,
            ordering: 1,
            parentId: folderID,
            app: TestDataFactory.makeAppInfo(bundleId: "folder.child.2")
        ))

        try sut.apply(
            .moveTopLevel(
                itemID: folderID,
                placement: .afterItem(itemID: anchorID)
            ),
            pageCapacity: 2
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [anchorID, folderID])
        #expect(snapshot.folderChildren[folderID]?.map(\.id) == [
            firstChildID, secondChildID,
        ])
        #expect(snapshot.folderChildren[folderID]?.map(\.ordering) == [0, 1])
    }

    @Test(
        "stale source/anchor、self 和零容量精确报错且完整快照不变",
        arguments: RejectedMove.allCases
    )
    func rejectedTopLevelMutationPreservesSnapshot(
        _ scenario: RejectedMove
    ) throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let intent: LayoutDropIntent
        let capacity: Int
        let expectedError: LayoutDomainError
        switch scenario {
        case .staleSource:
            intent = .moveTopLevel(
                itemID: 999,
                placement: .beforeItem(itemID: ids.first)
            )
            capacity = 2
            expectedError = .missingItem(999)
        case .staleAnchor:
            intent = .moveTopLevel(
                itemID: ids.first,
                placement: .beforeItem(itemID: 999)
            )
            capacity = 2
            expectedError = .missingItem(999)
        case .selfDrop:
            intent = .moveTopLevel(
                itemID: ids.first,
                placement: .afterItem(itemID: ids.first)
            )
            capacity = 2
            expectedError = .selfDrop
        case .invalidCapacity:
            intent = .moveTopLevel(
                itemID: ids.first,
                placement: .afterItem(itemID: ids.second)
            )
            capacity = 0
            expectedError = .invalidPageCapacity
        }
        let before = try sut.persistedLayoutSnapshot()

        #expect(throws: expectedError) {
            try sut.apply(intent, pageCapacity: capacity)
        }

        #expect(script.invocationCount(for: .rollback) == 1)
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test(
        "腐败持久拓扑拒绝且完整快照不变",
        arguments: CorruptTopology.allCases
    )
    func corruptPersistedTopologyPreservesSnapshot(
        _ topology: CorruptTopology
    ) throws {
        let (sut, script) = try makeCorruptLayout(topology)
        let before = try sut.persistedLayoutSnapshot()

        #expect(throws: topology.expectedError) {
            try sut.apply(
                .moveTopLevel(
                    itemID: 2,
                    placement: .beforeItem(itemID: 3)
                ),
                pageCapacity: 2
            )
        }

        expectNoLayoutWrites(script)
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test(
        "五种 future intent 精确 unsupported 且零 layout SQL",
        arguments: [
            LayoutDropIntent.addToFolder(itemID: 1, folderID: 2),
            LayoutDropIntent.createFolder(
                itemID: 1,
                targetItemID: 2,
                title: "Future"
            ),
            LayoutDropIntent.reorderFolderItem(
                itemID: 1,
                folderID: 2,
                placement: .beforeItem(itemID: 3)
            ),
            LayoutDropIntent.removeFromFolder(
                itemID: 1,
                folderID: 2,
                placement: .afterItem(itemID: 3)
            ),
            LayoutDropIntent.deleteFolder(folderID: 2),
        ]
    )
    func unsupportedIntentDoesNotReadOrWriteLayout(
        _ intent: LayoutDropIntent
    ) throws {
        let (sut, _, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        let fetchPrepareCount = script.invocationCount(
            for: .prepare(.fetchAllItems)
        )
        let fetchStepCount = script.invocationCount(for: .step(.fetchAllItems))

        #expect(throws: LayoutDomainError.unsupportedIntent) {
            try sut.apply(intent, pageCapacity: 2)
        }

        #expect(
            script.invocationCount(for: .prepare(.fetchAllItems))
                == fetchPrepareCount
        )
        #expect(
            script.invocationCount(for: .step(.fetchAllItems))
                == fetchStepCount
        )
        expectNoLayoutWrites(script)
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test(
        "BEGIN/read/item/page/insert/delete/COMMIT fault 精确映射并完整回滚",
        arguments: LayoutFault.allCases
    )
    func injectedLayoutFailureRollsBack(_ fault: LayoutFault) throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(
            fault.point,
            onOccurrence: fault.occurrence,
            code: fault.code
        )

        #expect(throws: fault.expectedError) {
            try sut.apply(
                .moveTopLevel(
                    itemID: ids.fourth,
                    placement: .beforeItem(itemID: ids.first)
                ),
                pageCapacity: fault.pageCapacity
            )
        }

        #expect(
            script.invocationCount(for: .rollback)
                == fault.expectedRollbackCount
        )
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("提交前完整 verify 捕获静默未写并回滚")
    func postWriteMismatchRollsBack() throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.failNext(.step(.updateLayoutItem), code: SQLITE_DONE)

        #expect(throws: LayoutDomainError.persistedStateMismatch) {
            try sut.apply(
                .moveTopLevel(
                    itemID: ids.fourth,
                    placement: .beforeItem(itemID: ids.first)
                ),
                pageCapacity: 2
            )
        }

        #expect(script.invocationCount(for: .rollback) == 1)
        #expect(try sut.persistedLayoutSnapshot() == before)
    }
}
