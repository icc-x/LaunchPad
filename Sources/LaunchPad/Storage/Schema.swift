import Foundation
import SQLite3

public enum SchemaError: Error, Equatable {
    case executeFailed(index: Int, code: Int32)
    case versionCheckPrepareFailed(Int32)
    case versionCheckStepFailed(Int32)
    case versionInsertPrepareFailed(Int32)
    case versionBindFailed(Int32)
    case versionInsertStepFailed(Int32)
    case versionReadPrepareFailed(Int32)
    case versionReadStepFailed(Int32)
    case unsupportedVersion(Int32)
    case migrationBeginFailed(Int32)
    case migrationStatementFailed(index: Int, code: Int32)
    case migrationCommitFailed(Int32)
    case migrationRollbackFailed(Int32)
}

/// 数据库 Schema 定义与迁移
public enum Schema {

    public static let currentVersion = 2

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
            source_modified_at REAL,
            updated_at  REAL DEFAULT (strftime('%s','now'))
        )
        """

    static let createSchemaVersionTable = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version     INTEGER NOT NULL
        )
        """

    // MARK: - Setup

    public static func setupSchema(db: OpaquePointer) throws {
        try setupSchema(db: db, statements: Schema.defaultStatements)
    }

    /// 在数据库上幂等执行 Schema 语句；任一步失败都会立即返回错误。
    public static func setupSchema(db: OpaquePointer, statements: [String]) throws {
        for (index, sql) in statements.enumerated() {
            let code = sqlite3_exec(db, sql, nil, nil, nil)
            guard code == SQLITE_OK else {
                throw SchemaError.executeFailed(index: index, code: code)
            }
        }

        try ensureVersionRecord(db: db)
        try migrateIfNeeded(db: db)
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
    ) throws {
        var checkStmt: OpaquePointer?
        let checkPrepareCode = sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil)
        guard checkPrepareCode == SQLITE_OK else {
            throw SchemaError.versionCheckPrepareFailed(checkPrepareCode)
        }
        defer { sqlite3_finalize(checkStmt) }

        let checkStepCode = sqlite3_step(checkStmt)
        guard checkStepCode == SQLITE_ROW else {
            throw SchemaError.versionCheckStepFailed(checkStepCode)
        }
        guard sqlite3_column_int(checkStmt, 0) == 0 else { return }

        var insertStmt: OpaquePointer?
        let insertPrepareCode = sqlite3_prepare_v2(
            db,
            insertSQL,
            -1,
            &insertStmt,
            nil
        )
        guard insertPrepareCode == SQLITE_OK else {
            throw SchemaError.versionInsertPrepareFailed(insertPrepareCode)
        }
        defer { sqlite3_finalize(insertStmt) }

        let bindCode = sqlite3_bind_int(insertStmt, 1, Int32(currentVersion))
        guard bindCode == SQLITE_OK else {
            throw SchemaError.versionBindFailed(bindCode)
        }

        let insertStepCode = sqlite3_step(insertStmt)
        guard insertStepCode == SQLITE_DONE else {
            throw SchemaError.versionInsertStepFailed(insertStepCode)
        }
    }

    private static func migrateIfNeeded(db: OpaquePointer) throws {
        let version = try readVersion(db: db)
        switch version {
        case 1:
            try migrateV1ToV2(db: db)
        case Int32(currentVersion):
            return
        default:
            throw SchemaError.unsupportedVersion(version)
        }
    }

    private static func readVersion(db: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(
            db,
            "SELECT version FROM schema_version LIMIT 1",
            -1,
            &statement,
            nil
        )
        guard prepareCode == SQLITE_OK else {
            throw SchemaError.versionReadPrepareFailed(prepareCode)
        }
        defer { sqlite3_finalize(statement) }

        let stepCode = sqlite3_step(statement)
        guard stepCode == SQLITE_ROW else {
            throw SchemaError.versionReadStepFailed(stepCode)
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func migrateV1ToV2(db: OpaquePointer) throws {
        let beginCode = sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        guard beginCode == SQLITE_OK else {
            throw SchemaError.migrationBeginFailed(beginCode)
        }

        do {
            let statements = [
                "ALTER TABLE image_cache ADD COLUMN source_modified_at REAL",
                "UPDATE schema_version SET version = 2",
            ]
            for (index, sql) in statements.enumerated() {
                let code = sqlite3_exec(db, sql, nil, nil, nil)
                guard code == SQLITE_OK else {
                    throw SchemaError.migrationStatementFailed(
                        index: index,
                        code: code
                    )
                }
            }

            let commitCode = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            guard commitCode == SQLITE_OK else {
                throw SchemaError.migrationCommitFailed(commitCode)
            }
        } catch {
            let rollbackCode = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            guard rollbackCode == SQLITE_OK else {
                throw SchemaError.migrationRollbackFailed(rollbackCode)
            }
            throw error
        }
    }
}
