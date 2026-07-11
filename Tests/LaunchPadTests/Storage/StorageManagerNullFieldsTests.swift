import Testing
import Foundation
import SQLite3
import LaunchPadProtocols
@testable import LaunchPad

// MARK: - fetchAllItems with NULL fields (覆盖 ?? "" fallback 分支)

@Suite("StorageManager fetchAllItems NULL fields")
struct StorageManagerFetchAllItemsNullFieldsTests {

    @Test("fetchAllItems 中 uuid 为 NULL 时回退为 \"\"（覆盖 L204 ?? fallback）")
    func fetchAllItems_uuidNull_fallsBackToEmpty() throws {
        // 第一次建表时直接用可空 schema，让 uuid 列允许 NULL
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, type INTEGER NOT NULL, parent_id INTEGER, ordering INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title TEXT, bundle_id TEXT, store_id TEXT, category TEXT, path TEXT)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT DEFAULT 'New Folder')", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE image_cache (item_id INTEGER PRIMARY KEY, icon_1x BLOB, icon_2x BLOB, updated_at REAL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE schema_version (version INTEGER NOT NULL)", nil, nil, nil)
            // 插入 uuid=NULL
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES (NULL, 0, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES (1, 'T', 'com.x', '/x')", nil, nil, nil)
        })

        let items = try sut.fetchAllItems(parentId: nil)
        #expect(items.count == 1)
        #expect(items.first?.uuid == "")
    }

    @Test("fetchAllItems 中 app.title 为 NULL 时回退为 \"\"（覆盖 L215 ?? fallback）")
    func fetchAllItems_appTitleNull_fallsBackToEmpty() throws {
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, type INTEGER NOT NULL, parent_id INTEGER, ordering INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title TEXT, bundle_id TEXT, store_id TEXT, category TEXT, path TEXT)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT DEFAULT 'New Folder')", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE image_cache (item_id INTEGER PRIMARY KEY, icon_1x BLOB, icon_2x BLOB, updated_at REAL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE schema_version (version INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u1', 0, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES (1, NULL, 'com.x', '/x')", nil, nil, nil)
        })

        let items = try sut.fetchAllItems(parentId: nil)
        #expect(items.count == 1)
        #expect(items.first?.app?.title == "")
    }

    @Test("fetchAllItems 中 app.bundle_id 为 NULL 时回退为 \"\"（覆盖 L216 ?? fallback）")
    func fetchAllItems_bundleIdNull_fallsBackToEmpty() throws {
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, type INTEGER NOT NULL, parent_id INTEGER, ordering INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title TEXT, bundle_id TEXT, store_id TEXT, category TEXT, path TEXT)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT DEFAULT 'New Folder')", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE image_cache (item_id INTEGER PRIMARY KEY, icon_1x BLOB, icon_2x BLOB, updated_at REAL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE schema_version (version INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u1', 0, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES (1, 'T', NULL, '/p')", nil, nil, nil)
        })

        let items = try sut.fetchAllItems(parentId: nil)
        #expect(items.count == 1)
        #expect(items.first?.app?.bundleId == "")
    }

    @Test("fetchAllItems 中 app.path 为 NULL 时回退为 \"\"（覆盖 L217 ?? fallback）")
    func fetchAllItems_pathNull_fallsBackToEmpty() throws {
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, type INTEGER NOT NULL, parent_id INTEGER, ordering INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title TEXT, bundle_id TEXT, store_id TEXT, category TEXT, path TEXT)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT DEFAULT 'New Folder')", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE image_cache (item_id INTEGER PRIMARY KEY, icon_1x BLOB, icon_2x BLOB, updated_at REAL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE schema_version (version INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u1', 0, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES (1, 'T', 'com.x', NULL)", nil, nil, nil)
        })

        let items = try sut.fetchAllItems(parentId: nil)
        #expect(items.count == 1)
        #expect(items.first?.app?.path == "")
    }

    @Test("fetchAllItems 中 group.title 为 NULL 时回退为 \"New Folder\"（覆盖 L223 ?? fallback）")
    func fetchAllItems_groupTitleNull_fallsBackToNewFolder() throws {
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, type INTEGER NOT NULL, parent_id INTEGER, ordering INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title TEXT, bundle_id TEXT, store_id TEXT, category TEXT, path TEXT)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT DEFAULT 'New Folder')", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE image_cache (item_id INTEGER PRIMARY KEY, icon_1x BLOB, icon_2x BLOB, updated_at REAL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE schema_version (version INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u1', 7, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO groups (item_id, title) VALUES (1, NULL)", nil, nil, nil)
        })

        let items = try sut.fetchAllItems(parentId: nil)
        #expect(items.count == 1)
        #expect(items.first?.group?.title == "New Folder")
    }
}
