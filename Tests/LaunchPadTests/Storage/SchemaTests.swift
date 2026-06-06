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
}
