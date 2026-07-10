import Foundation
import SQLite3

/// 数据库 Schema 定义与迁移
public enum Schema {

    public static let currentVersion = 1

    // MARK: - Table Creation SQL

    static let createItemsTable = """
        CREATE TABLE IF NOT EXISTS items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid        TEXT UNIQUE NOT NULL,
            type        INTEGER NOT NULL,
            parent_id   INTEGER REFERENCES items(id) ON DELETE CASCADE,
            ordering    INTEGER NOT NULL,
            created_at  REAL DEFAULT (strftime('%s','now'))
        )
        """

    static let createAppsTable = """
        CREATE TABLE IF NOT EXISTS apps (
            item_id     INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            title       TEXT NOT NULL,
            bundle_id   TEXT UNIQUE NOT NULL,
            store_id    TEXT,
            category    TEXT,
            path        TEXT NOT NULL
        )
        """

    static let createGroupsTable = """
        CREATE TABLE IF NOT EXISTS groups (
            item_id     INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            title       TEXT NOT NULL DEFAULT 'New Folder'
        )
        """

    static let createImageCacheTable = """
        CREATE TABLE IF NOT EXISTS image_cache (
            item_id     INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            icon_1x     BLOB,
            icon_2x     BLOB,
            updated_at  REAL DEFAULT (strftime('%s','now'))
        )
        """

    static let createSchemaVersionTable = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version     INTEGER NOT NULL
        )
        """

    // MARK: - Setup

    public static func setupSchema(db: OpaquePointer) {
        setupSchema(db: db, statements: Schema.defaultStatements)
    }

    /// 在数据库上创建指定语句（幂等）。`statements` 可注入，便于测试触发
    /// `sqlite3_exec` 失败的错误日志分支（默认走 `defaultStatements` 真实建表语句）。
    public static func setupSchema(db: OpaquePointer, statements: [String]) {
        for sql in statements {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                let errmsg = sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown"
                NSLog("[LaunchPad] Schema SQL failed: \(errmsg)\nSQL: \(sql)")
            }
        }

        ensureVersionRecord(db: db)
    }

    private static let defaultStatements: [String] = [
        "PRAGMA foreign_keys = ON",
        "PRAGMA journal_mode = WAL",
        createItemsTable,
        createAppsTable,
        createGroupsTable,
        createImageCacheTable,
        createSchemaVersionTable,
    ]

    /// 写入 schema 版本号（仅首次）。
    /// checkSQL/insertSQL 可注入以便测试覆盖 prepare 失败路径（正常流程不可达的防御分支）。
    static func ensureVersionRecord(
        db: OpaquePointer,
        checkSQL: String = "SELECT COUNT(*) FROM schema_version",
        insertSQL: String = "INSERT INTO schema_version (version) VALUES (?)"
    ) {
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(checkStmt) }
        if sqlite3_step(checkStmt) == SQLITE_ROW {
            let count = sqlite3_column_int(checkStmt, 0)
            if count == 0 {
                var insertStmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
                    return
                }
                defer { sqlite3_finalize(insertStmt) }
                sqlite3_bind_int(insertStmt, 1, Int32(currentVersion))
                sqlite3_step(insertStmt)
            }
        }
    }
}
