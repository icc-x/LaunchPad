import Foundation
import SQLite3
import LaunchPadProtocols

/// SQLite 数据存储管理器。
/// 生产环境使用文件路径，测试使用 ":memory:" 内存数据库。
public final class StorageManager: DataStoring, @unchecked Sendable {
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
            schemaSetup: { Schema.setupSchema(db: $0) },
            faultInjector: nil
        )
    }

    /// 测试初始化入口：允许替换 schema setup 并注入 SQLite driver 故障。
    internal init(
        dbPath: String,
        schemaSetup: (OpaquePointer) -> Void,
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
        _ = sqlite3_exec(database, "PRAGMA journal_mode=WAL", nil, nil, nil)
        _ = sqlite3_exec(database, "PRAGMA foreign_keys=ON", nil, nil, nil)
        schemaSetup(database)
    }

    deinit {
        databaseQueue.sync {
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
        try databaseQueue.sync {
            databaseAccessObserver?(
                DispatchQueue.getSpecific(key: databaseQueueKey)
                    == databaseQueueToken
            )
            return try body(requireDatabase())
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
