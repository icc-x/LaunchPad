import Testing
import Foundation
import SQLite3
@testable import LaunchPad

@Suite("SQLite Schema")
struct SchemaTests {

    private func openMemoryDB() -> OpaquePointer? {
        var db: OpaquePointer?
        sqlite3_open(":memory:", &db)
        return db
    }

    private func createV1Schema(db: OpaquePointer) {
        #expect(sqlite3_exec(db, Schema.createItemsTable, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(
            db,
            """
            CREATE TABLE image_cache (
                item_id INTEGER PRIMARY KEY,
                icon_1x BLOB,
                icon_2x BLOB,
                updated_at REAL
            )
            """,
            nil,
            nil,
            nil
        ) == SQLITE_OK)
        #expect(sqlite3_exec(db, Schema.createSchemaVersionTable, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(
            db,
            "INSERT INTO schema_version (version) VALUES (1)",
            nil,
            nil,
            nil
        ) == SQLITE_OK)
        #expect(sqlite3_exec(
            db,
            "INSERT INTO image_cache (item_id, icon_1x, icon_2x) VALUES (1, x'0102', x'0304')",
            nil,
            nil,
            nil
        ) == SQLITE_OK)
    }

    private func columnNames(table: String, db: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                names.append(String(cString: name))
            }
        }
        return names
    }

    private func storedVersion(db: OpaquePointer) -> Int32? {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db,
            "SELECT version FROM schema_version",
            -1,
            &statement,
            nil
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int(statement, 0)
    }

    private func legacyImageIsReadable(db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db,
            "SELECT icon_1x, icon_2x FROM image_cache WHERE item_id = 1",
            -1,
            &statement,
            nil
        )
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
            && sqlite3_column_bytes(statement, 0) == 2
            && sqlite3_column_bytes(statement, 1) == 2
    }

    @Test("Schema 包含 items 表 CREATE 语句")
    func schema_hasItemsTable() {
        #expect(Schema.createItemsTable.contains("CREATE TABLE"))
        #expect(Schema.createItemsTable.contains("items"))
        #expect(Schema.createItemsTable.contains("id"))
        #expect(Schema.createItemsTable.contains("uuid"))
        #expect(Schema.createItemsTable.contains("type"))
        #expect(Schema.createItemsTable.contains("parent_id"))
        #expect(Schema.createItemsTable.contains("ordering"))
    }

    @Test("Schema 包含 apps 表 CREATE 语句")
    func schema_hasAppsTable() {
        #expect(Schema.createAppsTable.contains("CREATE TABLE"))
        #expect(Schema.createAppsTable.contains("apps"))
        #expect(Schema.createAppsTable.contains("bundle_id"))
        #expect(Schema.createAppsTable.contains("path"))
    }

    @Test("Schema 包含 groups 表 CREATE 语句")
    func schema_hasGroupsTable() {
        #expect(Schema.createGroupsTable.contains("CREATE TABLE"))
        #expect(Schema.createGroupsTable.contains("groups"))
        #expect(Schema.createGroupsTable.contains("title"))
    }

    @Test("Schema 包含 image_cache 表 CREATE 语句")
    func schema_hasImageCacheTable() {
        #expect(Schema.createImageCacheTable.contains("CREATE TABLE"))
        #expect(Schema.createImageCacheTable.contains("image_cache"))
        #expect(Schema.createImageCacheTable.contains("icon_1x"))
        #expect(Schema.createImageCacheTable.contains("icon_2x"))
        #expect(Schema.createImageCacheTable.contains("source_modified_at"))
    }

    @Test("setupSchema 在空数据库上成功创建所有表")
    func setupSchema_createsAllTables() throws {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }

        try Schema.setupSchema(db: db!)

        let tables = ["items", "apps", "groups", "image_cache", "schema_version"]
        for table in tables {
            var stmt: OpaquePointer?
            let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'"
            sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            #expect(sqlite3_step(stmt) == SQLITE_ROW, "\(table) 表应存在")
        }
    }

    @Test("setupSchema 多次调用不报错（幂等）")
    func setupSchema_idempotent() throws {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }

        try Schema.setupSchema(db: db!)
        try Schema.setupSchema(db: db!)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM items", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
    }

    @Test("Schema 版本号正确")
    func schema_version() {
        #expect(Schema.currentVersion == 2)
    }

    @Test("v1 数据库事务迁移到 v2 并保留旧图标为 NULL 元数据")
    func setupSchema_migratesV1ToV2() throws {
        let db = try #require(openMemoryDB())
        defer { sqlite3_close(db) }
        createV1Schema(db: db)

        try Schema.setupSchema(db: db)

        #expect(storedVersion(db: db) == 2)
        #expect(columnNames(table: "image_cache", db: db).contains("source_modified_at"))
        #expect(legacyImageIsReadable(db: db))
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db,
            "SELECT source_modified_at FROM image_cache WHERE item_id = 1",
            -1,
            &statement,
            nil
        )
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_type(statement, 0) == SQLITE_NULL)
    }

    @Test("未知更高 schema 版本拒绝初始化")
    func setupSchema_rejectsUnknownHigherVersion() throws {
        let db = try #require(openMemoryDB())
        defer { sqlite3_close(db) }
        sqlite3_exec(db, Schema.createSchemaVersionTable, nil, nil, nil)
        sqlite3_exec(
            db,
            "INSERT INTO schema_version (version) VALUES (3)",
            nil,
            nil,
            nil
        )

        #expect(throws: SchemaError.unsupportedVersion(3)) {
            try Schema.setupSchema(db: db)
        }
    }

    @Test("v1 ALTER 失败回滚后重开仍为 v1 且旧图标可读")
    func setupSchema_alterFailureRollsBack() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("schema-alter-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: path) }
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        let database = try #require(db)
        createV1Schema(db: database)
        #expect(sqlite3_set_authorizer(
            database,
            { _, actionCode, _, _, _, _ in
                actionCode == SQLITE_ALTER_TABLE ? SQLITE_DENY : SQLITE_OK
            },
            nil
        ) == SQLITE_OK)

        #expect(throws: SchemaError.migrationStatementFailed(
            index: 0,
            code: SQLITE_AUTH
        )) {
            try Schema.setupSchema(db: database)
        }
        #expect(sqlite3_set_authorizer(database, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        db = nil

        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let reopened = try #require(db)
        #expect(storedVersion(db: reopened) == 1)
        #expect(!columnNames(table: "image_cache", db: reopened).contains("source_modified_at"))
        #expect(legacyImageIsReadable(db: reopened))
    }

    @Test("v1 版本更新失败回滚 ALTER，重开仍为 v1 且旧图标可读")
    func setupSchema_versionUpdateFailureRollsBack() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("schema-update-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: path) }
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        let database = try #require(db)
        createV1Schema(db: database)
        #expect(sqlite3_exec(
            database,
            """
            CREATE TRIGGER fail_schema_version_update
            BEFORE UPDATE ON schema_version
            BEGIN
                SELECT RAISE(ABORT, 'fail version update');
            END
            """,
            nil,
            nil,
            nil
        ) == SQLITE_OK)

        #expect(throws: SchemaError.migrationStatementFailed(
            index: 1,
            code: SQLITE_CONSTRAINT
        )) {
            try Schema.setupSchema(db: database)
        }
        sqlite3_close(db)
        db = nil

        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let reopened = try #require(db)
        #expect(storedVersion(db: reopened) == 1)
        #expect(!columnNames(table: "image_cache", db: reopened).contains("source_modified_at"))
        #expect(legacyImageIsReadable(db: reopened))
    }

    @Test("setupSchema 首次调用写入版本号")
    func setupSchema_writesVersionOnFirstCall() throws {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        try Schema.setupSchema(db: db!)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int(stmt, 0) == Int32(Schema.currentVersion))
    }

    @Test("setupSchema 多次调用不重复写入版本号")
    func setupSchema_doesNotDuplicateVersion() throws {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        try Schema.setupSchema(db: db!)
        try Schema.setupSchema(db: db!)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM schema_version", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_step(stmt)
        #expect(sqlite3_column_int(stmt, 0) == 1)
    }

    @Test("所有 CREATE TABLE 语句均使用 IF NOT EXISTS")
    func allCreateStatements_useIfNotExists() {
        #expect(Schema.createItemsTable.contains("IF NOT EXISTS"))
        #expect(Schema.createAppsTable.contains("IF NOT EXISTS"))
        #expect(Schema.createGroupsTable.contains("IF NOT EXISTS"))
        #expect(Schema.createImageCacheTable.contains("IF NOT EXISTS"))
        #expect(Schema.createSchemaVersionTable.contains("IF NOT EXISTS"))
    }

    @Test("setupSchema 遇无效 SQL 时抛出语句索引与 SQLite code")
    func setupSchema_invalidStatementThrows() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }

        #expect(throws: SchemaError.executeFailed(index: 0, code: SQLITE_ERROR)) {
            try Schema.setupSchema(
                db: db!,
                statements: ["THIS IS NOT A VALID SQL STATEMENT"]
            )
        }
    }

    @Test("setupSchema 在正常数据库上 INSERT prepare 成功（覆盖 insert 路径）")
    func setupSchema_insertPathSucceeds() throws {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        try Schema.setupSchema(db: db!)

        // 验证版本号已写入
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int(stmt, 0) == Int32(Schema.currentVersion))
    }

    @Test("setupSchema_itemsTableHasExpectedColumns")
    func setupSchema_itemsTableHasExpectedColumns() throws {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        try Schema.setupSchema(db: db!)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA table_info(items)", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        var columnNames: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                columnNames.append(String(cString: name))
            }
        }
        #expect(columnNames.contains("created_at"))
        #expect(columnNames.contains("uuid"))
        #expect(columnNames.contains("parent_id"))
    }

    // MARK: - ensureVersionRecord 错误路径

    @Test("ensureVersionRecord 在 checkSQL prepare 失败时抛错")
    func ensureVersionRecord_badCheckSQLThrows() throws {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        try Schema.setupSchema(db: db!)

        #expect(throws: SchemaError.versionCheckPrepareFailed(SQLITE_ERROR)) {
            try Schema.ensureVersionRecord(
                db: db!,
                checkSQL: "SELECT no_such_column_xyz FROM schema_version"
            )
        }
    }

    @Test("ensureVersionRecord 在 count step 失败时抛错")
    func ensureVersionRecord_countStepFailureThrows() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        sqlite3_exec(db, Schema.createSchemaVersionTable, nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO schema_version (version) VALUES (1)", nil, nil, nil)

        #expect(throws: SchemaError.versionCheckStepFailed(SQLITE_ERROR)) {
            try Schema.ensureVersionRecord(
                db: db!,
                checkSQL: "SELECT abs(-9223372036854775808) FROM schema_version"
            )
        }
    }

    @Test("ensureVersionRecord 在 insertSQL prepare 失败时抛错")
    func ensureVersionRecord_badInsertSQLThrows() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        sqlite3_exec(db, Schema.createSchemaVersionTable, nil, nil, nil)

        #expect(throws: SchemaError.versionInsertPrepareFailed(SQLITE_ERROR)) {
            try Schema.ensureVersionRecord(
                db: db!,
                insertSQL: "INSERT INTO no_such_table_xyz VALUES (1)"
            )
        }
    }

    @Test("ensureVersionRecord 在 version bind 失败时抛错")
    func ensureVersionRecord_bindFailureThrows() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        sqlite3_exec(db, Schema.createSchemaVersionTable, nil, nil, nil)

        #expect(throws: SchemaError.versionBindFailed(SQLITE_RANGE)) {
            try Schema.ensureVersionRecord(
                db: db!,
                insertSQL: "INSERT INTO schema_version (version) VALUES (1)"
            )
        }
    }

    @Test("ensureVersionRecord 在 version insert step 失败时抛错")
    func ensureVersionRecord_insertStepFailureThrows() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        sqlite3_exec(
            db,
            "CREATE TABLE schema_version (version INTEGER NOT NULL CHECK(version < 0))",
            nil,
            nil,
            nil
        )

        #expect(throws: SchemaError.versionInsertStepFailed(SQLITE_CONSTRAINT)) {
            try Schema.ensureVersionRecord(db: db!)
        }
    }
}
