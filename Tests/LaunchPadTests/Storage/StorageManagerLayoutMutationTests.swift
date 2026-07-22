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

extension StorageManagerLayoutMutationTests {
    struct FolderIDs {
        let before: Int64
        let folder: Int64
        let after: Int64
        let children: [Int64]
    }

    enum FolderPlacementScenario: CaseIterable, Sendable {
        case owningBefore
        case owningAfter
        case externalBefore
        case externalAfter
    }

    enum FolderReorderScenario: CaseIterable, Sendable {
        case before
        case after
    }

    enum FolderInsertFault: CaseIterable, Sendable {
        case itemPrepare
        case itemBindUUID
        case itemBindType
        case itemStep
        case itemChanges
        case metadataPrepare
        case metadataBindItemID
        case metadataBindTitle
        case metadataStep
        case metadataChanges

        var point: SQLiteFaultPoint {
            switch self {
            case .itemPrepare: .prepare(.insertItem)
            case .itemBindUUID: .bind(.insertItem, index: 1)
            case .itemBindType: .bind(.insertItem, index: 2)
            case .itemStep: .step(.insertItem)
            case .itemChanges: .changes(.insertItem)
            case .metadataPrepare: .prepare(.insertGroupMetadata)
            case .metadataBindItemID: .bind(.insertGroupMetadata, index: 1)
            case .metadataBindTitle: .bind(.insertGroupMetadata, index: 2)
            case .metadataStep: .step(.insertGroupMetadata)
            case .metadataChanges: .changes(.insertGroupMetadata)
            }
        }

        var code: Int32 {
            switch self {
            case .itemPrepare, .metadataPrepare: SQLITE_ERROR
            case .itemBindUUID, .itemBindType,
                 .metadataBindItemID, .metadataBindTitle: SQLITE_RANGE
            case .itemStep, .metadataStep: SQLITE_FULL
            case .itemChanges, .metadataChanges: 0
            }
        }

        var expectedError: StorageError {
            switch self {
            case .itemPrepare, .metadataPrepare: .prepareFailed
            case .itemBindUUID, .itemBindType,
                 .metadataBindItemID, .metadataBindTitle: .bindFailed
            case .itemStep, .itemChanges, .metadataStep, .metadataChanges:
                .insertFailed
            }
        }
    }

    enum DeleteStatementFault: CaseIterable, Sendable {
        case prepare
        case bind
        case step
        case changes

        var point: SQLiteFaultPoint {
            switch self {
            case .prepare: .prepare(.deleteLayoutItem)
            case .bind: .bind(.deleteLayoutItem, index: 1)
            case .step: .step(.deleteLayoutItem)
            case .changes: .changes(.deleteLayoutItem)
            }
        }

        var code: Int32 {
            switch self {
            case .prepare: SQLITE_ERROR
            case .bind: SQLITE_RANGE
            case .step: SQLITE_IOERR
            case .changes: 0
            }
        }

        var expectedError: StorageError {
            switch self {
            case .prepare: .prepareFailed
            case .bind: .bindFailed
            case .step, .changes: .deleteFailed
            }
        }
    }

    enum FolderUpdateFault: CaseIterable, Sendable {
        case prepare
        case bindParent
        case bindOrdering
        case bindItemID
        case step
        case changes

        var point: SQLiteFaultPoint {
            switch self {
            case .prepare: .prepare(.updateLayoutItem)
            case .bindParent: .bind(.updateLayoutItem, index: 1)
            case .bindOrdering: .bind(.updateLayoutItem, index: 2)
            case .bindItemID: .bind(.updateLayoutItem, index: 3)
            case .step: .step(.updateLayoutItem)
            case .changes: .changes(.updateLayoutItem)
            }
        }

        var code: Int32 {
            switch self {
            case .prepare: SQLITE_ERROR
            case .bindParent, .bindOrdering, .bindItemID: SQLITE_RANGE
            case .step: SQLITE_IOERR
            case .changes: 0
            }
        }

        var expectedError: StorageError {
            switch self {
            case .prepare: .prepareFailed
            case .bindParent, .bindOrdering, .bindItemID: .bindFailed
            case .step, .changes: .updateFailed
            }
        }
    }

    enum InsertPageFault: CaseIterable, Sendable {
        case prepare
        case bindUUID
        case bindType
        case bindOrdering
        case step
        case changes

        var point: SQLiteFaultPoint {
            switch self {
            case .prepare: .prepare(.insertPage)
            case .bindUUID: .bind(.insertPage, index: 1)
            case .bindType: .bind(.insertPage, index: 2)
            case .bindOrdering: .bind(.insertPage, index: 3)
            case .step: .step(.insertPage)
            case .changes: .changes(.insertPage)
            }
        }

        var code: Int32 {
            switch self {
            case .prepare: SQLITE_ERROR
            case .bindUUID, .bindType, .bindOrdering: SQLITE_RANGE
            case .step: SQLITE_FULL
            case .changes: 0
            }
        }

        var expectedError: StorageError {
            switch self {
            case .prepare: .prepareFailed
            case .bindUUID, .bindType, .bindOrdering: .bindFailed
            case .step, .changes: .insertFailed
            }
        }
    }

    private func makeFolderLayout(
        childCount: Int = 2,
        script: SQLiteFaultScript = SQLiteFaultScript()
    ) throws -> (StorageManager, FolderIDs, SQLiteFaultScript) {
        let storage = try StorageManager(
            dbPath: ":memory:",
            schemaSetup: { Schema.setupSchema(db: $0) },
            faultInjector: script.result(for:)
        )
        let pageID = try storage.insertItem(
            TestDataFactory.makePageItem(uuid: "folder-page", type: .page)
        )
        func app(_ suffix: String, parentID: Int64, ordering: Int) throws -> Int64 {
            try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "folder-app-\(suffix)",
                type: .app,
                ordering: ordering,
                parentId: parentID,
                app: TestDataFactory.makeAppInfo(
                    title: "Folder App \(suffix)",
                    bundleId: "com.test.folder.\(suffix)"
                )
            ))
        }

        let before = try app("before", parentID: pageID, ordering: 0)
        let folder = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "folder",
            type: .group,
            ordering: 1,
            parentId: pageID,
            group: TestDataFactory.makeGroupInfo(title: "Folder")
        ))
        let after = try app("after", parentID: pageID, ordering: 2)
        let children = try (0..<childCount).map { index in
            try app("child-\(index)", parentID: folder, ordering: index)
        }
        return (
            storage,
            FolderIDs(
                before: before,
                folder: folder,
                after: after,
                children: children
            ),
            script
        )
    }

    private func expectDenseCompleteSnapshot(
        _ snapshot: PersistedLayoutSnapshot,
        nonPageIDs: [Int64]
    ) {
        #expect(Set(snapshot.allItems.map(\.id)).count == snapshot.allItems.count)
        #expect(snapshot.pages.map(\.ordering) == Array(0..<snapshot.pages.count))
        for page in snapshot.pages {
            let children = snapshot.pageChildren[page.id] ?? []
            #expect(children.map(\.ordering) == Array(0..<children.count))
            #expect(children.allSatisfy { $0.parentId == page.id })
        }
        for (folderID, children) in snapshot.folderChildren {
            #expect(children.map(\.ordering) == Array(0..<children.count))
            #expect(children.allSatisfy { $0.parentId == folderID })
        }
        #expect(
            Set(snapshot.allItems.filter { $0.type != .page }.map(\.id))
                == Set(nonPageIDs)
        )
    }

    @Test("create folder 原子持久化顺序、title 且 metadata 恰好写一次")
    func createFolderPersistsOrderTitleAndMetadataExactlyOnce() throws {
        let (sut, ids, script) = try makeTwoPageLayout()

        try sut.apply(
            .createFolder(
                itemID: ids.fourth,
                targetItemID: ids.second,
                title: "Work"
            ),
            pageCapacity: 2
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        let folder = try #require(
            snapshot.allItems.first { $0.group?.title == "Work" }
        )
        #expect(snapshot.flattenedTopLevelIDs == [ids.first, folder.id, ids.third])
        #expect(snapshot.folderChildren[folder.id]?.map(\.id) == [
            ids.second, ids.fourth,
        ])
        expectDenseCompleteSnapshot(
            snapshot,
            nonPageIDs: [ids.first, ids.second, ids.third, ids.fourth, folder.id]
        )
        #expect(script.invocationCount(for: .prepare(.insertGroupMetadata)) == 1)
        #expect(script.invocationCount(for: .bind(.insertGroupMetadata, index: 1)) == 1)
        #expect(script.invocationCount(for: .bind(.insertGroupMetadata, index: 2)) == 1)
        #expect(script.invocationCount(for: .step(.insertGroupMetadata)) == 1)
        #expect(script.invocationCount(for: .changes(.insertGroupMetadata)) == 1)
    }

    @Test(
        "create folder 两张 INSERT 的 prepare/bind/step/changes 精确报错并回滚",
        arguments: FolderInsertFault.allCases
    )
    func createFolderInsertFaultRollsBack(_ fault: FolderInsertFault) throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(fault.point, onOccurrence: 1, code: fault.code)

        #expect(throws: fault.expectedError) {
            try sut.apply(
                .createFolder(
                    itemID: ids.fourth,
                    targetItemID: ids.second,
                    title: "Never committed"
                ),
                pageCapacity: 2
            )
        }

        #expect(script.invocationCount(for: .rollback) == 1)
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("create folder 第二个 child UPDATE 精确失败并完整回滚")
    func createFolderSecondChildUpdateFailureRollsBack() throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(
            .step(.updateLayoutItem),
            onOccurrence: 2,
            code: SQLITE_CONSTRAINT
        )

        #expect(throws: StorageError.updateFailed) {
            try sut.apply(
                .createFolder(
                    itemID: ids.fourth,
                    targetItemID: ids.second,
                    title: "Rollback"
                ),
                pageCapacity: 2
            )
        }

        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("addToFolder 追加 dense child 并从顶层移除")
    func addToFolderAppendsDenseChild() throws {
        let (sut, ids, _) = try makeFolderLayout()

        try sut.apply(
            .addToFolder(itemID: ids.before, folderID: ids.folder),
            pageCapacity: 3
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [ids.folder, ids.after])
        #expect(snapshot.folderChildren[ids.folder]?.map(\.id)
            == ids.children + [ids.before])
        expectDenseCompleteSnapshot(
            snapshot,
            nonPageIDs: [ids.before, ids.folder, ids.after] + ids.children
        )
    }

    @Test(
        "folder child UPDATE prepare/bind/step/changes 精确失败并完整回滚",
        arguments: FolderUpdateFault.allCases
    )
    func addToFolderUpdateFailureRollsBack(_ fault: FolderUpdateFault) throws {
        let (sut, ids, script) = try makeFolderLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(fault.point, onOccurrence: 1, code: fault.code)

        #expect(throws: fault.expectedError) {
            try sut.apply(
                .addToFolder(itemID: ids.before, folderID: ids.folder),
                pageCapacity: 3
            )
        }

        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test(
        "folder 内 before/after 重排保持 parent 与 dense ordering",
        arguments: FolderReorderScenario.allCases
    )
    func reorderFolderItemPersists(_ scenario: FolderReorderScenario) throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 3)
        let placement: ItemPlacement
        let expected: [Int64]
        switch scenario {
        case .before:
            placement = .beforeItem(itemID: ids.children[0])
            expected = [ids.children[2], ids.children[0], ids.children[1]]
        case .after:
            placement = .afterItem(itemID: ids.children[0])
            expected = [ids.children[0], ids.children[2], ids.children[1]]
        }

        try sut.apply(
            .reorderFolderItem(
                itemID: ids.children[2],
                folderID: ids.folder,
                placement: placement
            ),
            pageCapacity: 3
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.folderChildren[ids.folder]?.map(\.id) == expected)
        expectDenseCompleteSnapshot(
            snapshot,
            nonPageIDs: [ids.before, ids.folder, ids.after] + ids.children
        )
    }

    @Test("folder stale anchor 与 wrong parent 精确报错且完整快照不变")
    func rejectedFolderMutationsPreserveSnapshot() throws {
        do {
            let (sut, ids, _) = try makeFolderLayout()
            let before = try sut.persistedLayoutSnapshot()
            #expect(throws: LayoutDomainError.missingItem(999)) {
                try sut.apply(
                    .removeFromFolder(
                        itemID: ids.children[0],
                        folderID: ids.folder,
                        placement: .afterItem(itemID: 999)
                    ),
                    pageCapacity: 3
                )
            }
            #expect(try sut.persistedLayoutSnapshot() == before)
        }
        do {
            let (sut, ids, _) = try makeFolderLayout(childCount: 3)
            let before = try sut.persistedLayoutSnapshot()
            #expect(throws: LayoutDomainError.invalidParent(ids.folder)) {
                try sut.apply(
                    .reorderFolderItem(
                        itemID: ids.after,
                        folderID: ids.folder,
                        placement: .afterItem(itemID: ids.children[0])
                    ),
                    pageCapacity: 3
                )
            }
            #expect(try sut.persistedLayoutSnapshot() == before)
        }
    }

    @Test(
        "三项 folder 移出后保留：owning/external before/after 全矩阵",
        arguments: FolderPlacementScenario.allCases
    )
    func removeFromFolderRetainedMatrix(
        _ scenario: FolderPlacementScenario
    ) throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 3)
        let placement: ItemPlacement
        let expectedTopLevel: [Int64]
        switch scenario {
        case .owningBefore:
            placement = .beforeItem(itemID: ids.folder)
            expectedTopLevel = [ids.before, ids.children[2], ids.folder, ids.after]
        case .owningAfter:
            placement = .afterItem(itemID: ids.folder)
            expectedTopLevel = [ids.before, ids.folder, ids.children[2], ids.after]
        case .externalBefore:
            placement = .beforeItem(itemID: ids.after)
            expectedTopLevel = [ids.before, ids.folder, ids.children[2], ids.after]
        case .externalAfter:
            placement = .afterItem(itemID: ids.before)
            expectedTopLevel = [ids.before, ids.children[2], ids.folder, ids.after]
        }

        try sut.apply(
            .removeFromFolder(
                itemID: ids.children[2],
                folderID: ids.folder,
                placement: placement
            ),
            pageCapacity: 4
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == expectedTopLevel)
        #expect(snapshot.folderChildren[ids.folder]?.map(\.id)
            == Array(ids.children.prefix(2)))
        expectDenseCompleteSnapshot(
            snapshot,
            nonPageIDs: [ids.before, ids.folder, ids.after] + ids.children
        )
    }

    @Test(
        "二项 folder 移出后解散：owning/external before/after 全矩阵",
        arguments: FolderPlacementScenario.allCases
    )
    func removeFromFolderDissolvedMatrix(
        _ scenario: FolderPlacementScenario
    ) throws {
        let (sut, ids, _) = try makeFolderLayout()
        let placement: ItemPlacement
        let expectedTopLevel: [Int64]
        switch scenario {
        case .owningBefore:
            placement = .beforeItem(itemID: ids.folder)
            expectedTopLevel = [ids.before, ids.children[1], ids.children[0], ids.after]
        case .owningAfter:
            placement = .afterItem(itemID: ids.folder)
            expectedTopLevel = [ids.before, ids.children[0], ids.children[1], ids.after]
        case .externalBefore:
            placement = .beforeItem(itemID: ids.after)
            expectedTopLevel = [ids.before, ids.children[0], ids.children[1], ids.after]
        case .externalAfter:
            placement = .afterItem(itemID: ids.before)
            expectedTopLevel = [ids.before, ids.children[1], ids.children[0], ids.after]
        }

        try sut.apply(
            .removeFromFolder(
                itemID: ids.children[1],
                folderID: ids.folder,
                placement: placement
            ),
            pageCapacity: 4
        )

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == expectedTopLevel)
        #expect(snapshot.allItems.contains { $0.id == ids.folder } == false)
        expectDenseCompleteSnapshot(
            snapshot,
            nonPageIDs: [ids.before, ids.after] + ids.children
        )
    }

    @Test("deleteFolder 支持 zero-child 并保持完整 dense 快照")
    func deleteEmptyFolderPersists() throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 0)

        try sut.apply(.deleteFolder(folderID: ids.folder), pageCapacity: 3)

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [ids.before, ids.after])
        #expect(snapshot.allItems.contains { $0.id == ids.folder } == false)
        expectDenseCompleteSnapshot(snapshot, nonPageIDs: [ids.before, ids.after])
    }

    @Test("safe delete 按原位展开 children 且 overflow 创建新页")
    func deleteFolderPreservesChildrenAndSpillsPage() throws {
        let (sut, ids, _) = try makeFolderLayout(childCount: 3)

        try sut.apply(.deleteFolder(folderID: ids.folder), pageCapacity: 2)

        let snapshot = try sut.persistedLayoutSnapshot()
        #expect(snapshot.flattenedTopLevelIDs == [
            ids.before,
            ids.children[0],
            ids.children[1],
            ids.children[2],
            ids.after,
        ])
        #expect(snapshot.pages.count == 3)
        #expect(snapshot.allItems.contains { $0.id == ids.folder } == false)
        expectDenseCompleteSnapshot(
            snapshot,
            nonPageIDs: [ids.before, ids.after] + ids.children
        )
    }

    @Test(
        "folder row delete prepare/bind/step/changes 精确报错并回滚",
        arguments: DeleteStatementFault.allCases
    )
    func folderDeleteFaultRollsBack(_ fault: DeleteStatementFault) throws {
        let (sut, ids, script) = try makeFolderLayout(childCount: 3)
        let before = try sut.persistedLayoutSnapshot()
        script.fail(fault.point, onOccurrence: 1, code: fault.code)

        #expect(throws: fault.expectedError) {
            try sut.apply(.deleteFolder(folderID: ids.folder), pageCapacity: 5)
        }

        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test(
        "folder overflow insertPage prepare/bind/step/changes 精确报错并回滚",
        arguments: InsertPageFault.allCases
    )
    func folderOverflowInsertPageFaultRollsBack(_ fault: InsertPageFault) throws {
        let (sut, ids, script) = try makeFolderLayout(childCount: 3)
        let before = try sut.persistedLayoutSnapshot()
        script.fail(fault.point, onOccurrence: 1, code: fault.code)

        #expect(throws: fault.expectedError) {
            try sut.apply(.deleteFolder(folderID: ids.folder), pageCapacity: 2)
        }

        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test(
        "folder shrink obsolete page delete prepare/bind/step/changes 精确报错并回滚",
        arguments: DeleteStatementFault.allCases
    )
    func folderShrinkPageDeleteFaultRollsBack(
        _ fault: DeleteStatementFault
    ) throws {
        let (sut, ids, script) = try makeTwoPageLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(fault.point, onOccurrence: 1, code: fault.code)

        #expect(throws: fault.expectedError) {
            try sut.apply(
                .createFolder(
                    itemID: ids.fourth,
                    targetItemID: ids.second,
                    title: "Shrink"
                ),
                pageCapacity: 4
            )
        }

        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("folder COMMIT 精确失败并回滚完整快照")
    func folderCommitFailureRollsBack() throws {
        let (sut, ids, script) = try makeFolderLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.failNext(.commit, code: SQLITE_IOERR)

        #expect(throws: StorageError.commitFailed) {
            try sut.apply(
                .addToFolder(itemID: ids.before, folderID: ids.folder),
                pageCapacity: 3
            )
        }

        #expect(script.invocationCount(for: .rollback) == 1)
        #expect(try sut.persistedLayoutSnapshot() == before)
    }

    @Test("folder child 静默未写由提交前完整 verify 捕获并回滚")
    func folderPostWriteMismatchRollsBack() throws {
        let (sut, ids, script) = try makeFolderLayout()
        let before = try sut.persistedLayoutSnapshot()
        script.fail(
            .step(.updateLayoutItem),
            onOccurrence: 3,
            code: SQLITE_DONE
        )

        #expect(throws: LayoutDomainError.persistedStateMismatch) {
            try sut.apply(
                .addToFolder(itemID: ids.before, folderID: ids.folder),
                pageCapacity: 3
            )
        }

        #expect(try sut.persistedLayoutSnapshot() == before)
    }
}
