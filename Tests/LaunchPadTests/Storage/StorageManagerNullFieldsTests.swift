import Testing
import Foundation
import SQLite3
import LaunchPadProtocols
@testable import LaunchPad

// MARK: - fetchAllItems rejects invalid rows (strict decoding)

@Suite("StorageManager fetchAllItems rejects invalid rows")
struct StorageManagerFetchAllItemsRejectsInvalidRowsTests {

    private func makeSUT(
        itemsRow: String,
        appsRow: String? = nil,
        groupsRow: String? = nil
    ) throws -> StorageManager {
        try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, type INTEGER NOT NULL, parent_id INTEGER, ordering INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title TEXT, bundle_id TEXT, store_id TEXT, category TEXT, path TEXT)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT DEFAULT 'New Folder')", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE image_cache (item_id INTEGER PRIMARY KEY, icon_1x BLOB, icon_2x BLOB, updated_at REAL)", nil, nil, nil)
            sqlite3_exec(db, "CREATE TABLE schema_version (version INTEGER NOT NULL)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES \(itemsRow)", nil, nil, nil)
            if let appsRow {
                sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES \(appsRow)", nil, nil, nil)
            }
            if let groupsRow {
                sqlite3_exec(db, "INSERT INTO groups (item_id, title) VALUES \(groupsRow)", nil, nil, nil)
            }
        })
    }

    @Test("fetchAllItems 遇到未知 type 值时报 invalidItem")
    func fetchAllItems_unknownType_rejects() throws {
        let sut = try makeSUT(itemsRow: "('u1', 0, 0)")
        #expect(throws: StorageError.invalidItem) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("fetchAllItems 中 app 类型缺 apps 行时报 invalidItem")
    func fetchAllItems_appWithoutRow_rejects() throws {
        let sut = try makeSUT(itemsRow: "('u1', 4, 0)")
        #expect(throws: StorageError.invalidItem) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("fetchAllItems 中 app.title 为 NULL 时报 invalidItem")
    func fetchAllItems_appTitleNull_rejects() throws {
        let sut = try makeSUT(
            itemsRow: "('u1', 4, 0)",
            appsRow: "(1, NULL, 'com.x', '/x')"
        )
        #expect(throws: StorageError.invalidItem) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("fetchAllItems 中 app.bundle_id 为 NULL 时报 invalidItem")
    func fetchAllItems_bundleIdNull_rejects() throws {
        let sut = try makeSUT(
            itemsRow: "('u1', 4, 0)",
            appsRow: "(1, 'T', NULL, '/p')"
        )
        #expect(throws: StorageError.invalidItem) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("fetchAllItems 中 app.path 为 NULL 时报 invalidItem")
    func fetchAllItems_pathNull_rejects() throws {
        let sut = try makeSUT(
            itemsRow: "('u1', 4, 0)",
            appsRow: "(1, 'T', 'com.x', NULL)"
        )
        #expect(throws: StorageError.invalidItem) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("fetchAllItems 中 group 类型缺 groups 行时报 invalidItem")
    func fetchAllItems_groupWithoutRow_rejects() throws {
        let sut = try makeSUT(itemsRow: "('u1', 7, 0)")
        #expect(throws: StorageError.invalidItem) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("fetchAllItems 中 group.title 为 NULL 时报 invalidItem")
    func fetchAllItems_groupTitleNull_rejects() throws {
        let sut = try makeSUT(
            itemsRow: "('u1', 7, 0)",
            groupsRow: "(1, NULL)"
        )
        #expect(throws: StorageError.invalidItem) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }
}
