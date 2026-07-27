import Foundation
import SQLite3
import LaunchPadProtocols

struct PersistedLayoutSnapshot: Equatable {
    let allItems: [PageItem]

    var rootItems: [PageItem] {
        allItems.filter { $0.parentId == nil }.sorted(by: Self.layoutOrder)
    }

    var pages: [PageItem] {
        rootItems.filter { $0.type == .page }
    }

    var pageChildren: [Int64: [PageItem]] {
        Dictionary(uniqueKeysWithValues: pages.map { page in
            (page.id, children(of: page.id))
        })
    }

    var folderChildren: [Int64: [PageItem]] {
        let groups = allItems.filter { $0.type == .group }
        return Dictionary(uniqueKeysWithValues: groups.map { group in
            (group.id, children(of: group.id))
        })
    }

    var flattenedTopLevelIDs: [Int64] {
        pages.flatMap { pageChildren[$0.id] ?? [] }.map(\.id)
    }

    func children(of parentID: Int64) -> [PageItem] {
        allItems
            .filter { $0.parentId == parentID }
            .sorted(by: Self.layoutOrder)
    }

    private static func layoutOrder(_ lhs: PageItem, _ rhs: PageItem) -> Bool {
        lhs.ordering == rhs.ordering
            ? lhs.id < rhs.id
            : lhs.ordering < rhs.ordering
    }
}

/// SQLite 数据存储管理器。
/// 生产环境使用文件路径，测试使用 ":memory:" 内存数据库。
public final class StorageManager: DataStoring, LayoutMutating, ScanBatchWriting, @unchecked Sendable {
    private struct ResolvedPage {
        let id: Int64
        let ordering: Int
        let itemIDs: [Int64]
    }

    private var db: OpaquePointer?
    private let databaseQueue = DispatchQueue(
        label: "com.launchpad.storage.database",
        qos: .userInitiated
    )
    private let databaseQueueKey = DispatchSpecificKey<UInt8>()
    private let databaseQueueToken: UInt8 = 1
    private let sqliteDriver: SQLiteDriver
    private var isUsable = true

    internal var databaseAccessObserver: (@Sendable (Bool) -> Void)?

    public convenience init(dbPath: String) throws {
        try self.init(
            dbPath: dbPath,
            schemaSetup: { try Schema.setupSchema(db: $0) },
            faultInjector: nil
        )
    }

    /// 测试初始化入口：允许替换 schema setup 并注入 SQLite driver 故障。
    internal init(
        dbPath: String,
        schemaSetup: (OpaquePointer) throws -> Void,
        faultInjector: SQLiteDriver.FaultInjector? = nil
    ) throws {
        sqliteDriver = SQLiteDriver(faultInjector: faultInjector)
        databaseQueue.setSpecific(
            key: databaseQueueKey,
            value: databaseQueueToken
        )
        guard sqlite3_open(dbPath, &db) == SQLITE_OK,
              let database = db else {
            if let db {
                _ = sqlite3_close_v2(db)
                self.db = nil
            }
            throw StorageError.openFailed
        }

        var initializationSucceeded = false
        defer {
            if !initializationSucceeded, let db {
                _ = sqlite3_close_v2(db)
                self.db = nil
            }
        }

        guard sqlite3_exec(
            database,
            "PRAGMA journal_mode=WAL",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw StorageError.queryFailed
        }
        guard sqlite3_exec(
            database,
            "PRAGMA foreign_keys=ON",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw StorageError.queryFailed
        }
        do {
            try schemaSetup(database)
        } catch {
            throw StorageError.schemaSetupFailed
        }
        initializationSucceeded = true
    }

    deinit {
        onDatabaseQueue {
            if let db {
                _ = sqlite3_close_v2(db)
                self.db = nil
            }
        }
    }

    @discardableResult
    public func insertItem(_ item: PageItem) throws -> Int64 {
        try withDatabase { database in
            try runTransaction(database: database, mode: .deferred) {
                try insertItemStatement(item, database: database)
            }
        }
    }

    public func updateItem(_ item: PageItem) throws {
        try withDatabase { database in
            try runTransaction(database: database, mode: .deferred) {
                try updateItemStatement(item, database: database)
            }
        }
    }

    public func deleteItem(id: Int64) throws {
        try withDatabase { database in
            try deleteItemStatement(id: id, database: database)
        }
    }

    public func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
        try withDatabase { database in
            try fetchItems(parentID: parentId, database: database)
        }
    }

    public func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {
        try withDatabase { database in
            try runTransaction(database: database, mode: .deferred) {
                try reorderItemsStatement(
                    parentID: parentId,
                    orderedIDs: orderedIds,
                    database: database
                )
            }
        }
    }

    public func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {
        try withDatabase { database in
            try saveImageStatement(
                itemID: itemId,
                icon1x: icon1x,
                icon2x: icon2x,
                database: database
            )
        }
    }

    public func fetchImage(itemId: Int64) throws -> (Data, Data)? {
        try withDatabase { database in
            try fetchImageStatement(itemID: itemId, database: database)
        }
    }

    public func apply(
        _ intent: LayoutDropIntent,
        pageCapacity: Int
    ) throws {
        try withDatabase { database in
            try runTransaction(database: database, mode: .immediate) {
                let before = try readPersistedLayoutSnapshot(
                    database: database
                )
                var state = try readLayoutDomainState(snapshot: before)
                try state.validate(intent)

                let createdFolderID: Int64? = switch intent {
                case .createFolder(_, _, let title):
                    try insertFolder(title: title, database: database)
                case .moveTopLevel,
                     .addToFolder,
                     .reorderFolderItem,
                     .removeFromFolder,
                     .deleteFolder,
                     .deleteApp:
                    nil
                }

                let effects = try state.applyValidated(
                    intent,
                    createdFolderID: createdFolderID
                )
                try state.validateState()
                let plan = try state.makePageRebuildPlan(
                    pageCapacity: pageCapacity
                )

                try persistFolderChildren(
                    state.childrenByFolderID,
                    database: database
                )
                let resolvedPages = try persistPagePlan(
                    plan,
                    database: database
                )
                for folderID in effects.folderIDsToDelete.sorted() {
                    try deleteLayoutItem(
                        itemID: folderID,
                        database: database
                    )
                }
                for appID in effects.appIDsToDelete.sorted() {
                    try deleteLayoutItem(
                        itemID: appID,
                        database: database
                    )
                }
                try deleteObsoletePages(
                    plan.obsoletePageIDs,
                    database: database
                )

                let createdFolderTitles: [Int64: String]
                if let createdFolderID,
                   let title = effects.createdFolderTitle {
                    createdFolderTitles = [createdFolderID: title]
                } else {
                    createdFolderTitles = [:]
                }
                try verifyPersistedLayout(
                    state: state,
                    pages: resolvedPages,
                    createdFolderTitles: createdFolderTitles,
                    database: database
                )
            }
        }
    }

    func persistedLayoutSnapshot() throws -> PersistedLayoutSnapshot {
        try withDatabase { database in
            try readPersistedLayoutSnapshot(database: database)
        }
    }

    func synchronizeInstalledApps(
        _ scanned: [ScannedApp],
        initialPageCapacity: Int
    ) throws -> ScanSyncResult {
        var observed = ScanSyncResult()
        do {
            return try withDatabase { database in
                try runTransaction(database: database, mode: .immediate) {
                    let snapshot = try readPersistedLayoutSnapshot(database: database)
                    var firstError: (any Error)?
                    let apps = deduplicateScannedApps(scanned)

                    if snapshot.allItems.isEmpty {
                        guard initialPageCapacity > 0 else {
                            throw ScanBatchError.invalidPageCapacity
                        }
                        try executeInitialScan(
                            apps,
                            pageCapacity: initialPageCapacity,
                            database: database,
                            result: &observed,
                            firstError: &firstError
                        )
                    } else {
                        try executeIncrementalScan(
                            apps,
                            snapshot: snapshot,
                            database: database,
                            result: &observed,
                            firstError: &firstError
                        )
                        do {
                            try normalizeScanLayout(
                                database: database,
                                result: &observed,
                                firstError: &firstError
                            )
                        } catch {
                            if let firstError {
                                throw ScanBatchWriteFailure(
                                    result: observed,
                                    primaryError: firstError
                                )
                            }
                            throw error
                        }
                    }

                    if let firstError {
                        throw ScanBatchWriteFailure(
                            result: observed,
                            primaryError: firstError
                        )
                    }
                    return observed
                }
            }
        } catch let failure as ScanBatchWriteFailure {
            throw failure
        } catch let rollbackFailure as SQLiteRollbackFailure {
            throw rollbackFailure
        } catch {
            observed.recordFailure()
            throw ScanBatchWriteFailure(
                result: observed,
                primaryError: error
            )
        }
    }

    private func executeInitialScan(
        _ apps: [ScannedApp],
        pageCapacity: Int,
        database: OpaquePointer,
        result: inout ScanSyncResult,
        firstError: inout (any Error)?
    ) throws {
        let sorted = apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let chunks: [[ScannedApp]] = sorted.isEmpty
            ? [[]]
            : stride(from: 0, to: sorted.count, by: pageCapacity).map { start in
                Array(sorted[start..<min(start + pageCapacity, sorted.count)])
            }
        for (pageOrdering, chunk) in chunks.enumerated() {
            guard let pageID = try attemptScanWrite(
                database: database,
                result: &result,
                firstError: &firstError,
                { try insertItemStatement(makeScanPage(ordering: pageOrdering), database: database) }
            ) else { continue }
            for (ordering, app) in chunk.enumerated() {
                _ = try attemptScanWrite(
                    database: database,
                    result: &result,
                    firstError: &firstError,
                    { try insertItemStatement(makeScanApp(app, parentID: pageID, ordering: ordering), database: database) }
                )
            }
        }
    }

    private func executeIncrementalScan(
        _ scanned: [ScannedApp],
        snapshot: PersistedLayoutSnapshot,
        database: OpaquePointer,
        result: inout ScanSyncResult,
        firstError: inout (any Error)?
    ) throws {
        guard let lastPage = snapshot.pages.last else { throw ScanBatchError.missingPage }
        let existingApps = snapshot.allItems.filter { $0.type == .app }
        let existingByBundle = Dictionary(
            existingApps.compactMap { item in item.app.map { ($0.bundleId, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        let scannedByBundle = Dictionary(
            scanned.map { ($0.bundleId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var ordering = snapshot.pageChildren[lastPage.id]?.count ?? 0
        for app in scanned where existingByBundle[app.bundleId] == nil {
            if try attemptScanWrite(
                database: database,
                result: &result,
                firstError: &firstError,
                { try insertItemStatement(makeScanApp(app, parentID: lastPage.id, ordering: ordering), database: database) }
            ) != nil {
                ordering += 1
            }
        }
        for item in existingApps {
            guard let old = item.app,
                  let fresh = scannedByBundle[old.bundleId],
                  old.title != fresh.name || old.path != fresh.path else { continue }
            let updated = PageItem(
                id: item.id,
                uuid: item.uuid,
                type: item.type,
                ordering: item.ordering,
                parentId: item.parentId,
                app: AppInfo(
                    id: old.id,
                    title: fresh.name,
                    bundleId: old.bundleId,
                    path: fresh.path,
                    storeId: old.storeId,
                    category: old.category
                ),
                group: item.group
            )
            _ = try attemptScanWrite(
                database: database,
                result: &result,
                firstError: &firstError,
                { try updateItemStatement(updated, database: database) }
            )
        }
        for item in existingApps {
            guard let bundleID = item.app?.bundleId,
                  scannedByBundle[bundleID] == nil else { continue }
            _ = try attemptScanWrite(
                database: database,
                result: &result,
                firstError: &firstError,
                { try deleteItemStatement(id: item.id, database: database) }
            )
        }
    }

    private func normalizeScanLayout(
        database: OpaquePointer,
        result: inout ScanSyncResult,
        firstError: inout (any Error)?
    ) throws {
        let snapshot = try readPersistedLayoutSnapshot(database: database)
        var pages = snapshot.pages
        for page in pages {
            let children = snapshot.pageChildren[page.id] ?? []
            for (ordering, item) in children.enumerated()
            where item.parentId != page.id || item.ordering != ordering {
                _ = try attemptScanWrite(
                    database: database,
                    result: &result,
                    firstError: &firstError,
                    { try updateParentAndOrdering(itemID: item.id, parentID: page.id, ordering: ordering, database: database) }
                )
            }
        }
        let hasNonemptyPage = pages.contains { !(snapshot.pageChildren[$0.id] ?? []).isEmpty }
        let preservedEmptyPageID = hasNonemptyPage ? nil : pages.first?.id
        var deletedPageIDs = Set<Int64>()
        for page in pages where (snapshot.pageChildren[page.id] ?? []).isEmpty && page.id != preservedEmptyPageID {
            if try attemptScanWrite(
                database: database,
                result: &result,
                firstError: &firstError,
                { try deleteLayoutItem(itemID: page.id, database: database) }
            ) != nil {
                deletedPageIDs.insert(page.id)
            }
        }
        pages.removeAll { deletedPageIDs.contains($0.id) }
        for (ordering, page) in pages.enumerated() where page.ordering != ordering {
            _ = try attemptScanWrite(
                database: database,
                result: &result,
                firstError: &firstError,
                { try updatePageOrdering(pageID: page.id, ordering: ordering, database: database) }
            )
        }
    }

    private func attemptScanWrite<T>(
        database: OpaquePointer,
        result: inout ScanSyncResult,
        firstError: inout (any Error)?,
        _ body: () throws -> T
    ) throws -> T? {
        do {
            let value = try body()
            result.recordSuccess()
            return value
        } catch {
            result.recordFailure()
            if firstError == nil { firstError = error }
            guard sqlite3_get_autocommit(database) == 0 else {
                throw ScanBatchWriteFailure(result: result, primaryError: firstError ?? error)
            }
            return nil
        }
    }

    private func makeScanPage(ordering: Int) -> PageItem {
        PageItem(id: 0, uuid: UUID().uuidString, type: .page, ordering: ordering, parentId: nil, app: nil, group: nil)
    }

    private func makeScanApp(_ scanned: ScannedApp, parentID: Int64, ordering: Int) -> PageItem {
        PageItem(
            id: 0,
            uuid: UUID().uuidString,
            type: .app,
            ordering: ordering,
            parentId: parentID,
            app: AppInfo(id: 0, title: scanned.name, bundleId: scanned.bundleId, path: scanned.path, storeId: nil, category: nil),
            group: nil
        )
    }

    private func deduplicateScannedApps(_ scanned: [ScannedApp]) -> [ScannedApp] {
        var seen = Set<String>()
        return scanned.filter { seen.insert($0.bundleId).inserted }
    }

    private func requireDatabase() throws -> OpaquePointer {
        guard isUsable, let db else { throw StorageError.storageUnavailable }
        return db
    }

    private func invalidateDatabase() {
        isUsable = false
        if let db {
            _ = sqlite3_close_v2(db)
            self.db = nil
        }
    }

    private func withDatabase<T>(
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        try onDatabaseQueue {
            databaseAccessObserver?(
                DispatchQueue.getSpecific(key: databaseQueueKey)
                    == databaseQueueToken
            )
            return try body(requireDatabase())
        }
    }

    private func onDatabaseQueue<T>(
        _ body: () throws -> T
    ) rethrows -> T {
        try databaseQueue.sync {
            dispatchPrecondition(condition: .onQueueAsBarrier(databaseQueue))
            return try body()
        }
    }

    private func runTransaction<T>(
        database: OpaquePointer,
        mode: SQLiteTransactionMode,
        body: () throws -> T
    ) throws -> T {
        do {
            return try SQLiteTransaction(
                database: database,
                driver: sqliteDriver
            ).run(mode: mode, body: body)
        } catch let rollbackFailure as SQLiteRollbackFailure {
            invalidateDatabase()
            throw rollbackFailure
        }
    }

    private func fetchAllPersistedItems(
        database: OpaquePointer
    ) throws -> [PageItem] {
        let kind = SQLiteStatementKind.fetchAllItems
        let sql = """
            SELECT i.id, i.uuid, i.type, i.ordering, i.parent_id,
                   a.title, a.bundle_id, a.path, a.store_id, a.category,
                   g.title
            FROM items i
            LEFT JOIN apps a ON i.id = a.item_id
            LEFT JOIN groups g ON i.id = g.item_id
            ORDER BY i.id
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }

        var items: [PageItem] = []
        var stepCode = sqliteDriver.step(statement, kind: kind)
        while stepCode == SQLITE_ROW {
            items.append(decodePageItem(statement: statement))
            stepCode = sqliteDriver.step(statement, kind: kind)
        }
        guard stepCode == SQLITE_DONE else {
            throw StorageError.queryFailed
        }
        return items
    }

    private func readPersistedLayoutSnapshot(
        database: OpaquePointer
    ) throws -> PersistedLayoutSnapshot {
        PersistedLayoutSnapshot(
            allItems: try fetchAllPersistedItems(database: database)
        )
    }

    private func readLayoutDomainState(
        snapshot: PersistedLayoutSnapshot
    ) throws -> LayoutDomainState {
        var persistedIDs = Set<Int64>()
        for item in snapshot.allItems {
            guard persistedIDs.insert(item.id).inserted else {
                throw LayoutDomainError.duplicateItem(item.id)
            }
        }

        guard snapshot.rootItems.allSatisfy({ $0.type == .page }) else {
            throw LayoutDomainError.invalidParent(
                snapshot.rootItems.first { $0.type != .page }?.id ?? 0
            )
        }
        var reachable = Set(snapshot.pages.map(\.id))
        var topLevel: [LayoutNode] = []
        var folderChildren: [Int64: [LayoutNode]] = [:]
        for page in snapshot.pages {
            let children = snapshot.pageChildren[page.id] ?? []
            guard children.allSatisfy({
                $0.type == .app || $0.type == .group
            }) else {
                throw LayoutDomainError.invalidType(
                    children.first { $0.type == .page }?.id ?? page.id
                )
            }
            for child in children {
                guard reachable.insert(child.id).inserted else {
                    throw LayoutDomainError.duplicateItem(child.id)
                }
                topLevel.append(LayoutNode(id: child.id, type: child.type))
                if child.type == .group {
                    let nested = snapshot.folderChildren[child.id] ?? []
                    guard nested.allSatisfy({ $0.type == .app }) else {
                        throw LayoutDomainError.invalidType(
                            nested.first { $0.type != .app }?.id ?? child.id
                        )
                    }
                    for item in nested {
                        guard reachable.insert(item.id).inserted else {
                            throw LayoutDomainError.duplicateItem(item.id)
                        }
                    }
                    folderChildren[child.id] = nested.map {
                        LayoutNode(id: $0.id, type: $0.type)
                    }
                }
            }
        }

        let allIDs = Set(snapshot.allItems.map(\.id))
        guard reachable == allIDs else {
            throw LayoutDomainError.invalidParent(
                allIDs.subtracting(reachable).sorted().first ?? 0
            )
        }
        return LayoutDomainState(
            existingPageIDs: snapshot.pages.map(\.id),
            topLevelItems: topLevel,
            childrenByFolderID: folderChildren
        )
    }

    /// Inserts both folder rows using the caller's active layout transaction.
    private func insertFolder(
        title: String,
        database: OpaquePointer
    ) throws -> Int64 {
        let itemKind = SQLiteStatementKind.insertItem
        let itemSQL = """
            INSERT INTO items (uuid, type, parent_id, ordering)
            VALUES (?, ?, NULL, 0)
            """
        let uuid = UUID().uuidString
        var itemStatement: OpaquePointer?
        defer { sqlite3_finalize(itemStatement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: itemSQL,
            statement: &itemStatement,
            kind: itemKind
        ) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        guard sqliteDriver.bind(
            sqlite3_bind_text(
                itemStatement,
                1,
                (uuid as NSString).utf8String,
                -1,
                Self.sqliteTransient
            ),
            kind: itemKind,
            index: 1
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_int(
                itemStatement,
                2,
                Int32(ItemType.group.rawValue)
            ),
            kind: itemKind,
            index: 2
        ) == SQLITE_OK else {
            throw StorageError.bindFailed
        }
        guard sqliteDriver.step(itemStatement, kind: itemKind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: itemKind) == 1 else {
            throw StorageError.insertFailed
        }
        let folderID = sqlite3_last_insert_rowid(database)

        let metadataKind = SQLiteStatementKind.insertGroupMetadata
        let metadataSQL = "INSERT INTO groups (item_id, title) VALUES (?, ?)"
        var metadataStatement: OpaquePointer?
        defer { sqlite3_finalize(metadataStatement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: metadataSQL,
            statement: &metadataStatement,
            kind: metadataKind
        ) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        guard sqliteDriver.bind(
            sqlite3_bind_int64(metadataStatement, 1, folderID),
            kind: metadataKind,
            index: 1
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_text(
                metadataStatement,
                2,
                (title as NSString).utf8String,
                -1,
                Self.sqliteTransient
            ),
            kind: metadataKind,
            index: 2
        ) == SQLITE_OK else {
            throw StorageError.bindFailed
        }
        guard sqliteDriver.step(
            metadataStatement,
            kind: metadataKind
        ) == SQLITE_DONE,
        sqliteDriver.changes(
            database: database,
            kind: metadataKind
        ) == 1 else {
            throw StorageError.insertFailed
        }
        return folderID
    }

    /// Rewrites every surviving folder with deterministic dense child ordering.
    private func persistFolderChildren(
        _ childrenByFolderID: [Int64: [LayoutNode]],
        database: OpaquePointer
    ) throws {
        for folderID in childrenByFolderID.keys.sorted() {
            let children = childrenByFolderID[folderID] ?? []
            for (ordering, child) in children.enumerated() {
                try updateParentAndOrdering(
                    itemID: child.id,
                    parentID: folderID,
                    ordering: ordering,
                    database: database
                )
            }
        }
    }

    private func updateParentAndOrdering(
        itemID: Int64,
        parentID: Int64,
        ordering: Int,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.updateLayoutItem
        let sql = "UPDATE items SET parent_id = ?, ordering = ? WHERE id = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        guard sqliteDriver.bind(
            sqlite3_bind_int64(statement, 1, parentID),
            kind: kind,
            index: 1
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_int(statement, 2, Int32(ordering)),
            kind: kind,
            index: 2
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_int64(statement, 3, itemID),
            kind: kind,
            index: 3
        ) == SQLITE_OK else {
            throw StorageError.bindFailed
        }
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.updateFailed
        }
    }

    private func updatePageOrdering(
        pageID: Int64,
        ordering: Int,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.updatePageOrdering
        let sql = """
            UPDATE items
            SET parent_id = NULL, ordering = ?
            WHERE id = ? AND type = ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        guard sqliteDriver.bind(
            sqlite3_bind_int(statement, 1, Int32(ordering)),
            kind: kind,
            index: 1
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_int64(statement, 2, pageID),
            kind: kind,
            index: 2
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_int(statement, 3, Int32(ItemType.page.rawValue)),
            kind: kind,
            index: 3
        ) == SQLITE_OK else {
            throw StorageError.bindFailed
        }
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.updateFailed
        }
    }

    private func insertPage(
        ordering: Int,
        database: OpaquePointer
    ) throws -> Int64 {
        let kind = SQLiteStatementKind.insertPage
        let sql = """
            INSERT INTO items (uuid, type, parent_id, ordering)
            VALUES (?, ?, NULL, ?)
            """
        let uuid = UUID().uuidString
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        guard sqliteDriver.bind(
            sqlite3_bind_text(
                statement,
                1,
                (uuid as NSString).utf8String,
                -1,
                Self.sqliteTransient
            ),
            kind: kind,
            index: 1
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_int(statement, 2, Int32(ItemType.page.rawValue)),
            kind: kind,
            index: 2
        ) == SQLITE_OK,
        sqliteDriver.bind(
            sqlite3_bind_int(statement, 3, Int32(ordering)),
            kind: kind,
            index: 3
        ) == SQLITE_OK else {
            throw StorageError.bindFailed
        }
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.insertFailed
        }
        return sqlite3_last_insert_rowid(database)
    }

    private func deleteLayoutItem(
        itemID: Int64,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.deleteLayoutItem
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: "DELETE FROM items WHERE id = ?",
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        guard sqliteDriver.bind(
            sqlite3_bind_int64(statement, 1, itemID),
            kind: kind,
            index: 1
        ) == SQLITE_OK else {
            throw StorageError.bindFailed
        }
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.deleteFailed
        }
    }

    private func persistPagePlan(
        _ plan: PageRebuildPlan,
        database: OpaquePointer
    ) throws -> [ResolvedPage] {
        var resolved: [ResolvedPage] = []
        for page in plan.pages {
            let pageID: Int64
            if let existingPageID = page.existingPageID {
                pageID = existingPageID
            } else {
                pageID = try insertPage(
                    ordering: page.ordering,
                    database: database
                )
            }
            try updatePageOrdering(
                pageID: pageID,
                ordering: page.ordering,
                database: database
            )
            resolved.append(ResolvedPage(
                id: pageID,
                ordering: page.ordering,
                itemIDs: page.itemIDs
            ))
        }
        for page in resolved {
            for (ordering, itemID) in page.itemIDs.enumerated() {
                try updateParentAndOrdering(
                    itemID: itemID,
                    parentID: page.id,
                    ordering: ordering,
                    database: database
                )
            }
        }
        return resolved
    }

    /// Deletes obsolete pages only after all explicit folder deletes complete.
    private func deleteObsoletePages(
        _ pageIDs: [Int64],
        database: OpaquePointer
    ) throws {
        for pageID in pageIDs {
            try deleteLayoutItem(itemID: pageID, database: database)
        }
    }

    private func verifyPersistedLayout(
        state: LayoutDomainState,
        pages: [ResolvedPage],
        createdFolderTitles: [Int64: String] = [:],
        database: OpaquePointer
    ) throws {
        let snapshot = try readPersistedLayoutSnapshot(database: database)
        guard snapshot.pages.map(\.id) == pages.map(\.id),
              snapshot.pages.map(\.ordering) == Array(0..<pages.count) else {
            throw LayoutDomainError.persistedStateMismatch
        }
        for page in pages {
            let children = snapshot.pageChildren[page.id] ?? []
            guard children.map(\.id) == page.itemIDs,
                  children.map(\.ordering) == Array(0..<children.count) else {
                throw LayoutDomainError.persistedStateMismatch
            }
        }
        guard snapshot.flattenedTopLevelIDs
                == state.topLevelItems.map(\.id) else {
            throw LayoutDomainError.persistedStateMismatch
        }
        for (folderID, expectedChildren) in state.childrenByFolderID {
            let children = snapshot.folderChildren[folderID] ?? []
            guard children.map(\.id) == expectedChildren.map(\.id),
                  children.map(\.ordering) == Array(0..<children.count),
                  children.allSatisfy({ $0.type == .app }) else {
                throw LayoutDomainError.persistedStateMismatch
            }
        }
        for (folderID, title) in createdFolderTitles {
            guard snapshot.allItems.first(where: {
                $0.id == folderID
            })?.group?.title == title else {
                throw LayoutDomainError.persistedStateMismatch
            }
        }
        let expectedIDs = Set(pages.map(\.id))
            .union(state.topLevelItems.map(\.id))
            .union(state.childrenByFolderID.values.flatMap { nodes in
                nodes.map(\.id)
            })
        guard Set(snapshot.allItems.map(\.id)) == expectedIDs else {
            throw LayoutDomainError.persistedStateMismatch
        }
    }

    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private func bindText(
        _ value: String?,
        statement: OpaquePointer?,
        index: Int32,
        kind: SQLiteStatementKind
    ) throws {
        let code: Int32
        if let value {
            code = sqliteDriver.bind(
                sqlite3_bind_text(
                    statement,
                    index,
                    (value as NSString).utf8String,
                    -1,
                    Self.sqliteTransient
                ),
                kind: kind,
                index: index
            )
        } else {
            code = sqliteDriver.bind(
                sqlite3_bind_null(statement, index),
                kind: kind,
                index: index
            )
        }
        guard code == SQLITE_OK else { throw StorageError.bindFailed }
    }

    private func bindInt64(
        _ value: Int64?,
        statement: OpaquePointer?,
        index: Int32,
        kind: SQLiteStatementKind
    ) throws {
        let code = value.map {
            sqliteDriver.bind(
                sqlite3_bind_int64(statement, index, $0),
                kind: kind,
                index: index
            )
        } ?? sqliteDriver.bind(
            sqlite3_bind_null(statement, index),
            kind: kind,
            index: index
        )
        guard code == SQLITE_OK else { throw StorageError.bindFailed }
    }

    private func insertItemStatement(
        _ item: PageItem,
        database: OpaquePointer
    ) throws -> Int64 {
        let kind = SQLiteStatementKind.insertItem
        let sql = """
            INSERT INTO items (uuid, type, parent_id, ordering)
            VALUES (?, ?, ?, ?)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindText(item.uuid, statement: statement, index: 1, kind: kind)
        guard sqliteDriver.bind(
            sqlite3_bind_int(statement, 2, Int32(item.type.rawValue)),
            kind: kind,
            index: 2
        ) == SQLITE_OK else { throw StorageError.bindFailed }
        try bindInt64(item.parentId, statement: statement, index: 3, kind: kind)
        guard sqliteDriver.bind(
            sqlite3_bind_int(statement, 4, Int32(item.ordering)),
            kind: kind,
            index: 4
        ) == SQLITE_OK else { throw StorageError.bindFailed }
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.insertFailed
        }
        let itemID = sqlite3_last_insert_rowid(database)
        switch item.type {
        case .app:
            if let app = item.app {
                try insertAppMetadata(
                    itemID: itemID,
                    app: app,
                    database: database
                )
            }
        case .group:
            if let group = item.group {
                try insertGroupMetadata(
                    itemID: itemID,
                    group: group,
                    database: database
                )
            }
        case .page:
            break
        }
        return itemID
    }

    private func insertAppMetadata(
        itemID: Int64,
        app: AppInfo,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.insertAppMetadata
        let sql = """
            INSERT INTO apps
                (item_id, title, bundle_id, store_id, category, path)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindInt64(itemID, statement: statement, index: 1, kind: kind)
        try bindText(app.title, statement: statement, index: 2, kind: kind)
        try bindText(app.bundleId, statement: statement, index: 3, kind: kind)
        try bindText(app.storeId, statement: statement, index: 4, kind: kind)
        try bindText(app.category, statement: statement, index: 5, kind: kind)
        try bindText(app.path, statement: statement, index: 6, kind: kind)
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.insertFailed
        }
    }

    private func insertGroupMetadata(
        itemID: Int64,
        group: GroupInfo,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.insertGroupMetadata
        let sql = "INSERT INTO groups (item_id, title) VALUES (?, ?)"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindInt64(itemID, statement: statement, index: 1, kind: kind)
        try bindText(group.title, statement: statement, index: 2, kind: kind)
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.insertFailed
        }
    }

    private func updateItemStatement(
        _ item: PageItem,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.updateItem
        let sql = "UPDATE items SET ordering = ?, parent_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        guard sqliteDriver.bind(
            sqlite3_bind_int(statement, 1, Int32(item.ordering)),
            kind: kind,
            index: 1
        ) == SQLITE_OK else { throw StorageError.bindFailed }
        try bindInt64(item.parentId, statement: statement, index: 2, kind: kind)
        try bindInt64(item.id, statement: statement, index: 3, kind: kind)
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.updateFailed
        }
        if let app = item.app {
            try updateAppMetadata(itemID: item.id, app: app, database: database)
        }
        if let group = item.group {
            try updateGroupMetadata(
                itemID: item.id,
                group: group,
                database: database
            )
        }
    }

    private func updateAppMetadata(
        itemID: Int64,
        app: AppInfo,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.updateAppMetadata
        let sql = """
            UPDATE apps
            SET title = ?, path = ?, store_id = ?, category = ?
            WHERE item_id = ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindText(app.title, statement: statement, index: 1, kind: kind)
        try bindText(app.path, statement: statement, index: 2, kind: kind)
        try bindText(app.storeId, statement: statement, index: 3, kind: kind)
        try bindText(app.category, statement: statement, index: 4, kind: kind)
        try bindInt64(itemID, statement: statement, index: 5, kind: kind)
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.updateFailed
        }
    }

    private func updateGroupMetadata(
        itemID: Int64,
        group: GroupInfo,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.updateGroupMetadata
        let sql = "UPDATE groups SET title = ? WHERE item_id = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindText(group.title, statement: statement, index: 1, kind: kind)
        try bindInt64(itemID, statement: statement, index: 2, kind: kind)
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.updateFailed
        }
    }

    private func deleteItemStatement(
        id: Int64,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.deleteItem
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: "DELETE FROM items WHERE id = ?",
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindInt64(id, statement: statement, index: 1, kind: kind)
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.deleteFailed
        }
    }

    private func fetchItems(
        parentID: Int64?,
        database: OpaquePointer
    ) throws -> [PageItem] {
        let kind = SQLiteStatementKind.fetchItems
        let predicate = parentID == nil
            ? "i.parent_id IS NULL"
            : "i.parent_id = ?"
        let sql = """
            SELECT i.id, i.uuid, i.type, i.ordering, i.parent_id,
                   a.title, a.bundle_id, a.path, a.store_id, a.category,
                   g.title
            FROM items i
            LEFT JOIN apps a ON i.id = a.item_id
            LEFT JOIN groups g ON i.id = g.item_id
            WHERE \(predicate)
            ORDER BY i.ordering
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        if let parentID {
            try bindInt64(parentID, statement: statement, index: 1, kind: kind)
        }
        var items: [PageItem] = []
        var stepCode = sqliteDriver.step(statement, kind: kind)
        while stepCode == SQLITE_ROW {
            items.append(decodePageItem(statement: statement))
            stepCode = sqliteDriver.step(statement, kind: kind)
        }
        guard stepCode == SQLITE_DONE else { throw StorageError.queryFailed }
        return items
    }

    private func reorderItemsStatement(
        parentID: Int64,
        orderedIDs: [Int64],
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.reorderItem
        let sql = "UPDATE items SET ordering = ?, parent_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        for (ordering, id) in orderedIDs.enumerated() {
            guard sqlite3_reset(statement) == SQLITE_OK,
                  sqlite3_clear_bindings(statement) == SQLITE_OK else {
                throw StorageError.updateFailed
            }
            guard sqliteDriver.bind(
                sqlite3_bind_int(statement, 1, Int32(ordering)),
                kind: kind,
                index: 1
            ) == SQLITE_OK else { throw StorageError.bindFailed }
            try bindInt64(parentID, statement: statement, index: 2, kind: kind)
            try bindInt64(id, statement: statement, index: 3, kind: kind)
            guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
                  sqliteDriver.changes(database: database, kind: kind) == 1 else {
                throw StorageError.updateFailed
            }
        }
    }

    private func saveImageStatement(
        itemID: Int64,
        icon1x: Data,
        icon2x: Data,
        database: OpaquePointer
    ) throws {
        let kind = SQLiteStatementKind.saveImage
        let sql = """
            INSERT OR REPLACE INTO image_cache (item_id, icon_1x, icon_2x)
            VALUES (?, ?, ?)
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: sql,
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindInt64(itemID, statement: statement, index: 1, kind: kind)
        let firstCode = icon1x.withUnsafeBytes { bytes in
            sqliteDriver.bind(
                sqlite3_bind_blob(
                    statement,
                    2,
                    bytes.baseAddress,
                    Int32(bytes.count),
                    Self.sqliteTransient
                ),
                kind: kind,
                index: 2
            )
        }
        let secondCode = icon2x.withUnsafeBytes { bytes in
            sqliteDriver.bind(
                sqlite3_bind_blob(
                    statement,
                    3,
                    bytes.baseAddress,
                    Int32(bytes.count),
                    Self.sqliteTransient
                ),
                kind: kind,
                index: 3
            )
        }
        guard firstCode == SQLITE_OK, secondCode == SQLITE_OK else {
            throw StorageError.bindFailed
        }
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE,
              sqliteDriver.changes(database: database, kind: kind) == 1 else {
            throw StorageError.insertFailed
        }
    }

    private func fetchImageStatement(
        itemID: Int64,
        database: OpaquePointer
    ) throws -> (Data, Data)? {
        let kind = SQLiteStatementKind.fetchImage
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqliteDriver.prepare(
            database: database,
            sql: "SELECT icon_1x, icon_2x FROM image_cache WHERE item_id = ?",
            statement: &statement,
            kind: kind
        ) == SQLITE_OK else { throw StorageError.prepareFailed }
        try bindInt64(itemID, statement: statement, index: 1, kind: kind)
        let firstStep = sqliteDriver.step(statement, kind: kind)
        guard firstStep != SQLITE_DONE else { return nil }
        guard firstStep == SQLITE_ROW else { throw StorageError.queryFailed }
        let result: (Data, Data)?
        if let first = sqlite3_column_blob(statement, 0),
           let second = sqlite3_column_blob(statement, 1) {
            result = (
                Data(
                    bytes: first,
                    count: Int(sqlite3_column_bytes(statement, 0))
                ),
                Data(
                    bytes: second,
                    count: Int(sqlite3_column_bytes(statement, 1))
                )
            )
        } else {
            result = nil
        }
        guard sqliteDriver.step(statement, kind: kind) == SQLITE_DONE else {
            throw StorageError.queryFailed
        }
        return result
    }

    private func decodePageItem(statement: OpaquePointer?) -> PageItem {
        let id = sqlite3_column_int64(statement, 0)
        let uuid = sqlite3_column_text(statement, 1).map {
            String(cString: $0)
        } ?? ""
        let typeRaw = Int(sqlite3_column_int(statement, 2))
        let ordering = Int(sqlite3_column_int(statement, 3))
        let parentID: Int64? = sqlite3_column_type(statement, 4) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, 4)
        let type = ItemType(rawValue: typeRaw) ?? .app
        var app: AppInfo?
        var group: GroupInfo?
        if type == .app {
            app = AppInfo(
                id: id,
                title: sqlite3_column_text(statement, 5).map {
                    String(cString: $0)
                } ?? "",
                bundleId: sqlite3_column_text(statement, 6).map {
                    String(cString: $0)
                } ?? "",
                path: sqlite3_column_text(statement, 7).map {
                    String(cString: $0)
                } ?? "",
                storeId: sqlite3_column_text(statement, 8).map {
                    String(cString: $0)
                },
                category: sqlite3_column_text(statement, 9).map {
                    String(cString: $0)
                }
            )
        } else if type == .group {
            group = GroupInfo(
                id: id,
                title: sqlite3_column_text(statement, 10).map {
                    String(cString: $0)
                } ?? "New Folder"
            )
        }
        return PageItem(
            id: id,
            uuid: uuid,
            type: type,
            ordering: ordering,
            parentId: parentID,
            app: app,
            group: group
        )
    }
}

// MARK: - Errors

public enum StorageError: Error, Equatable {
    case openFailed
    case schemaSetupFailed
    case prepareFailed
    case insertFailed
    case updateFailed
    case deleteFailed
    case bindFailed
    case queryFailed
    case beginFailed
    case commitFailed
    case storageUnavailable
}
