import Foundation
import SQLite3
import LaunchPadProtocols

/// SQLite 数据存储管理器
/// 生产环境使用文件路径，测试使用 ":memory:" 内存数据库
public final class StorageManager: DataStoring, @unchecked Sendable {

    private var db: OpaquePointer?
    private let writeQueue = DispatchQueue(label: "com.launchpad.storage.write", qos: .utility)

    public init(dbPath: String) throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw StorageError.openFailed
        }
        guard let db else { throw StorageError.openFailed }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
        Schema.setupSchema(db: db)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - ItemWriting

    @discardableResult
    public func insertItem(_ item: PageItem) throws -> Int64 {
        try writeQueue.sync {
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

            let sql = """
                INSERT INTO items (uuid, type, parent_id, ordering)
                VALUES (?, ?, ?, ?)
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed
            }

            sqlite3_bind_text(stmt, 1, (item.uuid as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(item.type.rawValue))
            if let parentId = item.parentId {
                sqlite3_bind_int64(stmt, 3, parentId)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_int(stmt, 4, Int32(item.ordering))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.insertFailed
            }

            let itemId = sqlite3_last_insert_rowid(db)

            switch item.type {
            case .app:
                if let app = item.app {
                    try insertApp(itemId: itemId, app: app)
                }
            case .group:
                if let group = item.group {
                    try insertGroup(itemId: itemId, group: group)
                }
            case .page:
                break
            }

            return itemId
        }
    }

    public func updateItem(_ item: PageItem) throws {
        try writeQueue.sync {
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            var committed = false
            defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }

            // Update items table (ordering + parent_id)
            let sql = "UPDATE items SET ordering = ?, parent_id = ? WHERE id = ?"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed
            }
            sqlite3_bind_int(stmt, 1, Int32(item.ordering))
            if let pid = item.parentId {
                sqlite3_bind_int64(stmt, 2, pid)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_int64(stmt, 3, item.id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.updateFailed
            }

            // Update apps table if app data changed
            if let app = item.app {
                let appSQL = "UPDATE apps SET title = ?, path = ?, store_id = ?, category = ? WHERE item_id = ?"
                var appStmt: OpaquePointer?
                defer { sqlite3_finalize(appStmt) }
                guard sqlite3_prepare_v2(db, appSQL, -1, &appStmt, nil) == SQLITE_OK else {
                    throw StorageError.prepareFailed
                }
                sqlite3_bind_text(appStmt, 1, (app.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(appStmt, 2, (app.path as NSString).utf8String, -1, nil)
                if let sid = app.storeId {
                    sqlite3_bind_text(appStmt, 3, (sid as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(appStmt, 3)
                }
                if let cat = app.category {
                    sqlite3_bind_text(appStmt, 4, (cat as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(appStmt, 4)
                }
                sqlite3_bind_int64(appStmt, 5, item.id)
                guard sqlite3_step(appStmt) == SQLITE_DONE else {
                    throw StorageError.updateFailed
                }
            }

            // Update groups table if group data changed
            if let group = item.group {
                let groupSQL = "UPDATE groups SET title = ? WHERE item_id = ?"
                var groupStmt: OpaquePointer?
                defer { sqlite3_finalize(groupStmt) }
                guard sqlite3_prepare_v2(db, groupSQL, -1, &groupStmt, nil) == SQLITE_OK else {
                    throw StorageError.prepareFailed
                }
                sqlite3_bind_text(groupStmt, 1, (group.title as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(groupStmt, 2, item.id)
                guard sqlite3_step(groupStmt) == SQLITE_DONE else {
                    throw StorageError.updateFailed
                }
            }

            committed = true
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    public func deleteItem(id: Int64) throws {
        try writeQueue.sync {
            let sql = "DELETE FROM items WHERE id = ?"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed
            }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.deleteFailed
            }
        }
    }

    // MARK: - ItemReading

    public func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
        try writeQueue.sync {
            let sql = """
                SELECT i.id, i.uuid, i.type, i.ordering, i.parent_id,
                       a.title, a.bundle_id, a.path, a.store_id, a.category,
                       g.title
                FROM items i
                LEFT JOIN apps a ON i.id = a.item_id
                LEFT JOIN groups g ON i.id = g.item_id
                WHERE \(parentId == nil ? "i.parent_id IS NULL" : "i.parent_id = ?")
                ORDER BY i.ordering
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if let parentId = parentId {
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw StorageError.prepareFailed
                }
                sqlite3_bind_int64(stmt, 1, parentId)
            } else {
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw StorageError.prepareFailed
                }
            }

            var items: [PageItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let uuid = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let typeRaw = Int(sqlite3_column_int(stmt, 2))
                let ordering = Int(sqlite3_column_int(stmt, 3))
                let parentId: Int64? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 4)
                let type = ItemType(rawValue: typeRaw) ?? .app

                var app: AppInfo?
                var group: GroupInfo?

                if type == .app {
                    let title = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
                    let bundleId = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
                    let path = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
                    let storeId = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
                    let category = sqlite3_column_text(stmt, 9).map { String(cString: $0) }
                    app = AppInfo(id: id, title: title, bundleId: bundleId, path: path,
                                  storeId: storeId, category: category)
                } else if type == .group {
                    let title = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? "New Folder"
                    group = GroupInfo(id: id, title: title)
                }

                items.append(PageItem(id: id, uuid: uuid, type: type, ordering: ordering,
                                       parentId: parentId, app: app, group: group))
            }
            return items
        }
    }

    public func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {
        try writeQueue.sync {
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            var committed = false
            defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }

            let sql = "UPDATE items SET ordering = ?, parent_id = ? WHERE id = ?"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed
            }

            for (index, id) in orderedIds.enumerated() {
                sqlite3_reset(stmt)
                sqlite3_bind_int(stmt, 1, Int32(index))
                sqlite3_bind_int64(stmt, 2, parentId)
                sqlite3_bind_int64(stmt, 3, id)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw StorageError.updateFailed
                }
            }

            committed = true
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    // MARK: - ImageStoring

    public func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {
        try writeQueue.sync {
            let sql = """
                INSERT OR REPLACE INTO image_cache (item_id, icon_1x, icon_2x)
                VALUES (?, ?, ?)
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed
            }
            sqlite3_bind_int64(stmt, 1, itemId)
            icon1x.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(icon1x.count), nil)
            }
            icon2x.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(icon2x.count), nil)
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.insertFailed
            }
        }
    }

    public func fetchImage(itemId: Int64) throws -> (Data, Data)? {
        try writeQueue.sync {
            let sql = "SELECT icon_1x, icon_2x FROM image_cache WHERE item_id = ?"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed
            }
            sqlite3_bind_int64(stmt, 1, itemId)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard let blob1 = sqlite3_column_blob(stmt, 0),
                  let blob2 = sqlite3_column_blob(stmt, 1) else { return nil }
            let len1 = Int(sqlite3_column_bytes(stmt, 0))
            let len2 = Int(sqlite3_column_bytes(stmt, 1))
            return (Data(bytes: blob1, count: len1), Data(bytes: blob2, count: len2))
        }
    }

    // MARK: - Private

    private func insertApp(itemId: Int64, app: AppInfo) throws {
        let sql = """
            INSERT INTO apps (item_id, title, bundle_id, store_id, category, path)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        sqlite3_bind_int64(stmt, 1, itemId)
        sqlite3_bind_text(stmt, 2, (app.title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (app.bundleId as NSString).utf8String, -1, nil)
        if let sid = app.storeId {
            sqlite3_bind_text(stmt, 4, (sid as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let cat = app.category {
            sqlite3_bind_text(stmt, 5, (cat as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_text(stmt, 6, (app.path as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.insertFailed
        }
    }

    private func insertGroup(itemId: Int64, group: GroupInfo) throws {
        let sql = "INSERT INTO groups (item_id, title) VALUES (?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed
        }
        sqlite3_bind_int64(stmt, 1, itemId)
        sqlite3_bind_text(stmt, 2, (group.title as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.insertFailed
        }
    }
}

// MARK: - Errors

public enum StorageError: Error {
    case openFailed
    case prepareFailed
    case insertFailed
    case updateFailed
    case deleteFailed
    case queryFailed
}
