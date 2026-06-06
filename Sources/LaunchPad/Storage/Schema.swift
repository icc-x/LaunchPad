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

    /// 在数据库上创建所有表（幂等，可重复调用）
    public static func setupSchema(db: OpaquePointer) {
        let statements = [
            "PRAGMA foreign_keys = ON",
            "PRAGMA journal_mode = WAL",
            createItemsTable,
            createAppsTable,
            createGroupsTable,
            createImageCacheTable,
            createSchemaVersionTable,
        ]

        for sql in statements {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                let errmsg = sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown"
                NSLog("[LaunchPad] Schema SQL failed: \(errmsg)\nSQL: \(sql)")
            }
        }

        // 写入版本号（仅首次）
        let checkSQL = "SELECT COUNT(*) FROM schema_version"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            let count = sqlite3_column_int(stmt, 0)
            if count == 0 {
                sqlite3_exec(db, "INSERT INTO schema_version (version) VALUES (\(currentVersion))",
                             nil, nil, nil)
            }
        }
    }
}
