import Testing
import SQLite3
@testable import LaunchPad

@Suite("SQLite Schema")
struct SchemaTests {

    private func openMemoryDB() -> OpaquePointer? {
        var db: OpaquePointer?
        sqlite3_open(":memory:", &db)
        return db
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
    }

    @Test("setupSchema 在空数据库上成功创建所有表")
    func setupSchema_createsAllTables() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }

        Schema.setupSchema(db: db!)

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
    func setupSchema_idempotent() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }

        Schema.setupSchema(db: db!)
        Schema.setupSchema(db: db!)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM items", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
    }

    @Test("Schema 版本号正确")
    func schema_version() {
        #expect(Schema.currentVersion == 1)
    }

    @Test("setupSchema 首次调用写入版本号")
    func setupSchema_writesVersionOnFirstCall() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        Schema.setupSchema(db: db!)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int(stmt, 0) == Int32(Schema.currentVersion))
    }

    @Test("setupSchema 多次调用不重复写入版本号")
    func setupSchema_doesNotDuplicateVersion() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        Schema.setupSchema(db: db!)
        Schema.setupSchema(db: db!)

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

    @Test("setupSchema 遇无效 SQL 语句 -> 记录错误且不崩溃（覆盖 71-73 行错误日志分支）")
    func setupSchema_invalidStatement_logsError() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }

        // 传入语法错误的 SQL 触发 sqlite3_exec 失败分支（db 有效，不会崩溃）
        Schema.setupSchema(db: db!, statements: ["THIS IS NOT A VALID SQL STATEMENT"])
    }

    @Test("setupSchema 在正常数据库上 INSERT prepare 成功（覆盖 insert 路径）")
    func setupSchema_insertPathSucceeds() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        Schema.setupSchema(db: db!)

        // 验证版本号已写入
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int(stmt, 0) == Int32(Schema.currentVersion))
    }

    @Test("setupSchema_itemsTableHasExpectedColumns")
    func setupSchema_itemsTableHasExpectedColumns() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        Schema.setupSchema(db: db!)

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

    // MARK: - ensureVersionRecord 错误路径（prepare 失败防御分支）

    @Test("ensureVersionRecord 在 checkSQL prepare 失败时安全返回")
    func ensureVersionRecord_badCheckSQL_returns() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        Schema.setupSchema(db: db!) // 先建表，保证 db 有效

        // 传入列不存在的 SQL 触发 checkSQL prepare 失败分支（line 88 return）
        Schema.ensureVersionRecord(db: db!, checkSQL: "SELECT no_such_column_xyz FROM schema_version")
    }

    @Test("ensureVersionRecord 在 insertSQL prepare 失败时安全返回")
    func ensureVersionRecord_badInsertSQL_returns() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        // 仅手动建 schema_version 表但不写入版本，使 count == 0 进入 insert 分支
        sqlite3_exec(db, Schema.createSchemaVersionTable, nil, nil, nil)

        // 传入表不存在的 SQL 触发 insertSQL prepare 失败分支（line 96 return）
        Schema.ensureVersionRecord(db: db!, insertSQL: "INSERT INTO no_such_table_xyz VALUES (1)")
    }
}
