import Testing
import Foundation
import SQLite3
import LaunchPadProtocols
@testable import LaunchPad

final class SQLiteFaultScript: @unchecked Sendable {
    private struct ScheduledFailure {
        var callsUntilFailure: Int
        let code: Int32
    }

    private let lock = NSLock()
    private var failures: [SQLiteFaultPoint: [ScheduledFailure]] = [:]
    private var invocations: [SQLiteFaultPoint: Int] = [:]

    func failNext(_ point: SQLiteFaultPoint, code: Int32) {
        fail(point, onOccurrence: 1, code: code)
    }

    func fail(
        _ point: SQLiteFaultPoint,
        onOccurrence: Int,
        code: Int32
    ) {
        precondition(onOccurrence > 0)
        lock.lock()
        failures[point, default: []].append(
            ScheduledFailure(
                callsUntilFailure: onOccurrence,
                code: code
            )
        )
        lock.unlock()
    }

    func result(for point: SQLiteFaultPoint) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        invocations[point, default: 0] += 1
        guard var scheduled = failures[point], !scheduled.isEmpty else {
            return nil
        }
        scheduled[0].callsUntilFailure -= 1
        if scheduled[0].callsUntilFailure == 0 {
            let code = scheduled.removeFirst().code
            failures[point] = scheduled
            return code
        }
        failures[point] = scheduled
        return nil
    }

    func invocationCount(for point: SQLiteFaultPoint) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return invocations[point, default: 0]
    }
}

private final class QueueObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func append(_ value: Bool) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var snapshot: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private func makeFaultableStorage(
    _ script: SQLiteFaultScript
) throws -> StorageManager {
    try StorageManager(
        dbPath: ":memory:",
        schemaSetup: { Schema.setupSchema(db: $0) },
        faultInjector: script.result(for:)
    )
}

private func withSQLiteDatabase<T>(
    _ body: (OpaquePointer) throws -> T
) throws -> T {
    var connection: OpaquePointer?
    guard sqlite3_open(":memory:", &connection) == SQLITE_OK,
          let database = connection else {
        throw StorageError.openFailed
    }
    defer { sqlite3_close_v2(database) }
    return try body(database)
}

@Suite("StorageManager 基础 CRUD")
struct StorageManagerTests {

    private func makeSUT() throws -> StorageManager {
        try StorageManager(dbPath: ":memory:")
    }

    @Test("插入 app item 后查询可返回")
    func insertAndFetch_appItem() throws {
        let sut = try makeSUT()
        let app = TestDataFactory.makeAppInfo(title: "Safari", bundleId: "com.apple.Safari")
        let item = TestDataFactory.makePageItem(type: .app, app: app)

        let insertedId = try sut.insertItem(item)
        #expect(insertedId > 0)

        let all = try sut.fetchAllItems(parentId: nil)
        #expect(all.count == 1)
        #expect(all.first?.app?.title == "Safari")
        #expect(all.first?.app?.bundleId == "com.apple.Safari")
    }

    @Test("插入 group item 后查询可返回")
    func insertAndFetch_groupItem() throws {
        let sut = try makeSUT()
        let group = TestDataFactory.makeGroupInfo(title: "Favorites")
        let item = TestDataFactory.makePageItem(type: .group, group: group)

        let insertedId = try sut.insertItem(item)
        #expect(insertedId > 0)

        let all = try sut.fetchAllItems(parentId: nil)
        #expect(all.count == 1)
        #expect(all.first?.group?.title == "Favorites")
    }

    @Test("插入 page item 后查询可返回")
    func insertAndFetch_pageItem() throws {
        let sut = try makeSUT()
        let item = TestDataFactory.makePageItem(type: .page, ordering: 0)

        let _ = try sut.insertItem(item)
        let all = try sut.fetchAllItems(parentId: nil)
        #expect(all.count == 1)
        #expect(all.first?.type == .page)
    }

    @Test("空表 fetchAllItems 返回空数组")
    func fetchAll_emptyTable() throws {
        let sut = try makeSUT()
        let all = try sut.fetchAllItems(parentId: nil)
        #expect(all.isEmpty)
    }

    @Test("不可打开的路径 -> init 抛出 openFailed")
    func init_unopenablePath_throwsOpenFailed() {
        #expect(throws: StorageError.self) {
            _ = try StorageManager(dbPath: "/nonexistent_directory_xyz/db.sqlite")
        }
    }

    @Test("重复 bundleId 插入抛出错误")
    func insert_duplicateBundleId_throws() throws {
        let sut = try makeSUT()
        let app1 = TestDataFactory.makeAppInfo(bundleId: "com.duplicate.app")
        let app2 = TestDataFactory.makeAppInfo(bundleId: "com.duplicate.app")
        let item1 = TestDataFactory.makePageItem(type: .app, app: app1)
        let item2 = TestDataFactory.makePageItem(type: .app, app: app2)

        try sut.insertItem(item1)
        #expect(throws: (any Error).self) {
            try sut.insertItem(item2)
        }
    }

    @Test("deleteItem 删除指定 item")
    func deleteItem_removesItem() throws {
        let sut = try makeSUT()
        let item = TestDataFactory.makePageItem(type: .app,
            app: TestDataFactory.makeAppInfo(title: "ToDelete"))
        let id = try sut.insertItem(item)

        try sut.deleteItem(id: id)

        let all = try sut.fetchAllItems(parentId: nil)
        #expect(all.isEmpty)
    }
}

@Suite("StorageManager 级联删除与高级操作")
struct StorageManagerAdvancedTests {

    private func makeSUT() throws -> StorageManager {
        try StorageManager(dbPath: ":memory:")
    }

    @Test("删除 group → 子 app 级联删除")
    func deleteGroup_cascadesToChildren() throws {
        let sut = try makeSUT()

        let group = TestDataFactory.makeGroupInfo(title: "TestGroup")
        let groupItem = TestDataFactory.makePageItem(type: .group, ordering: 0, group: group)
        let groupId = try sut.insertItem(groupItem)

        let app1 = TestDataFactory.makeAppInfo(title: "App1", bundleId: "com.test.app1")
        let app2 = TestDataFactory.makeAppInfo(title: "App2", bundleId: "com.test.app2")
        try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: 0,
                                                         parentId: groupId, app: app1))
        try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: 1,
                                                         parentId: groupId, app: app2))

        try sut.deleteItem(id: groupId)

        let topItems = try sut.fetchAllItems(parentId: nil)
        #expect(topItems.isEmpty)

        let childItems = try sut.fetchAllItems(parentId: groupId)
        #expect(childItems.isEmpty)
    }

    @Test("reorderItems 更新 ordering")
    func reorderItems_updatesOrdering() throws {
        let sut = try makeSUT()

        let pageItem = TestDataFactory.makePageItem(type: .page, ordering: 0)
        let pageId = try sut.insertItem(pageItem)

        let id1 = try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: 0,
            parentId: pageId, app: TestDataFactory.makeAppInfo(title: "First", bundleId: "com.first")))
        let id2 = try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: 1,
            parentId: pageId, app: TestDataFactory.makeAppInfo(title: "Second", bundleId: "com.second")))
        let id3 = try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: 2,
            parentId: pageId, app: TestDataFactory.makeAppInfo(title: "Third", bundleId: "com.third")))

        try sut.reorderItems(parentId: pageId, orderedIds: [id3, id2, id1])

        let all = try sut.fetchAllItems(parentId: pageId)
        #expect(all[0].app?.title == "Third")
        #expect(all[1].app?.title == "Second")
        #expect(all[2].app?.title == "First")
    }

    @Test("图标保存/读取往返")
    func imageStore_roundTrip() throws {
        let sut = try makeSUT()
        let item = TestDataFactory.makePageItem(type: .app,
            app: TestDataFactory.makeAppInfo(title: "IconApp", bundleId: "com.icon.app"))
        let itemId = try sut.insertItem(item)

        let icon1x = Data(repeating: 0xAA, count: 100)
        let icon2x = Data(repeating: 0xBB, count: 200)

        try sut.saveImage(itemId: itemId, icon1x: icon1x, icon2x: icon2x)

        let fetched = try sut.fetchImage(itemId: itemId)
        #expect(fetched != nil)
        #expect(fetched!.0 == icon1x)
        #expect(fetched!.1 == icon2x)
    }

    @Test("不存在的图标返回 nil")
    func imageStore_notFound() throws {
        let sut = try makeSUT()
        let result = try sut.fetchImage(itemId: 999)
        #expect(result == nil)
    }

    @Test("多层嵌套查询 — page → items")
    func fetchItems_nestedUnderPage() throws {
        let sut = try makeSUT()

        let pageItem = TestDataFactory.makePageItem(type: .page, ordering: 0)
        let pageId = try sut.insertItem(pageItem)

        for i in 0..<3 {
            let app = TestDataFactory.makeAppInfo(title: "App\(i)", bundleId: "com.test.nested\(i)")
            try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: i,
                                                             parentId: pageId, app: app))
        }

        let children = try sut.fetchAllItems(parentId: pageId)
        #expect(children.count == 3)
        #expect(children.allSatisfy { $0.parentId == pageId })
    }

    @Test("三层嵌套: page -> group -> items 正确解析")
    func fetchItems_threeLayerNested() throws {
        let sut = try makeSUT()

        // 创建 page
        let pageId = try sut.insertItem(TestDataFactory.makePageItem(type: .page, ordering: 0))

        // 创建 group（文件夹）
        let group = TestDataFactory.makeGroupInfo(title: "Utilities")
        let groupId = try sut.insertItem(TestDataFactory.makePageItem(type: .group, ordering: 0,
                                                                       parentId: pageId, group: group))

        // 创建 items 在 group 下
        let app1 = TestDataFactory.makeAppInfo(title: "Calculator", bundleId: "com.apple.calculator")
        let app2 = TestDataFactory.makeAppInfo(title: "Terminal", bundleId: "com.apple.Terminal")
        try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: 0, parentId: groupId, app: app1))
        try sut.insertItem(TestDataFactory.makePageItem(type: .app, ordering: 1, parentId: groupId, app: app2))

        // 验证 page 下有 group
        let pageChildren = try sut.fetchAllItems(parentId: pageId)
        #expect(pageChildren.count == 1)
        #expect(pageChildren.first?.type == .group)
        #expect(pageChildren.first?.group?.title == "Utilities")

        // 验证 group 下有 items
        let groupChildren = try sut.fetchAllItems(parentId: groupId)
        #expect(groupChildren.count == 2)
        #expect(groupChildren.allSatisfy { $0.type == .app })
        let titles = groupChildren.compactMap { $0.app?.title }.sorted()
        #expect(titles == ["Calculator", "Terminal"])
    }

    @Test("fetchAllItems 遇到无效 type 值时回退为 .app")
    func fetchAllItems_invalidType_fallsBackToApp() throws {
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, Schema.createItemsTable, nil, nil, nil)
            sqlite3_exec(db, Schema.createAppsTable, nil, nil, nil)
            sqlite3_exec(db, Schema.createGroupsTable, nil, nil, nil)
            sqlite3_exec(db, Schema.createImageCacheTable, nil, nil, nil)
            sqlite3_exec(db, Schema.createSchemaVersionTable, nil, nil, nil)
            // 插入 type=99（无效值），附带 apps 表数据
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u1', 99, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES (1, 'BadType', 'com.bad', '/p')", nil, nil, nil)
        })

        let items = try sut.fetchAllItems(parentId: nil)
        #expect(items.count == 1)
        #expect(items.first?.type == .app)
        #expect(items.first?.app?.title == "BadType")
    }
}

@Suite("StorageManager 更新操作")
struct StorageManagerUpdateTests {

    private func makeSUT() throws -> StorageManager {
        try StorageManager(dbPath: ":memory:")
    }

    @Test("updateItem 更新 app 的 title/path（storeId/category 为 nil）")
    func updateItem_app_updatesTitleAndPath() throws {
        let sut = try makeSUT()
        let app = TestDataFactory.makeAppInfo(title: "OldName", bundleId: "com.update.app", path: "/old/path")
        let item = TestDataFactory.makePageItem(type: .app, app: app)
        let id = try sut.insertItem(item)

        let updatedApp = AppInfo(id: id, title: "NewName", bundleId: "com.update.app",
                                 path: "/new/path", storeId: nil, category: nil)
        let updatedItem = PageItem(id: id, uuid: item.uuid, type: .app, ordering: 5,
                                   parentId: nil, app: updatedApp, group: nil)
        try sut.updateItem(updatedItem)

        let fetched = try sut.fetchAllItems(parentId: nil).first
        #expect(fetched?.app?.title == "NewName")
        #expect(fetched?.app?.path == "/new/path")
        #expect(fetched?.ordering == 5)
    }

    @Test("updateItem 更新 app 的 storeId 和 category（非 nil）")
    func updateItem_app_updatesStoreIdAndCategory() throws {
        let sut = try makeSUT()
        let app = TestDataFactory.makeAppInfo(title: "App", bundleId: "com.sc.app", path: "/p")
        let item = TestDataFactory.makePageItem(type: .app, app: app)
        let id = try sut.insertItem(item)

        let updatedApp = AppInfo(id: id, title: "App", bundleId: "com.sc.app",
                                 path: "/p2", storeId: "store123", category: "Games")
        let updatedItem = PageItem(id: id, uuid: item.uuid, type: .app, ordering: 0,
                                   parentId: nil, app: updatedApp, group: nil)
        try sut.updateItem(updatedItem)

        let fetched = try sut.fetchAllItems(parentId: nil).first
        #expect(fetched?.app?.storeId == "store123")
        #expect(fetched?.app?.category == "Games")
    }

    @Test("updateItem 更新 group 的 title")
    func updateItem_group_updatesTitle() throws {
        let sut = try makeSUT()
        let group = TestDataFactory.makeGroupInfo(title: "OldFolder")
        let item = TestDataFactory.makePageItem(type: .group, group: group)
        let id = try sut.insertItem(item)

        let updatedGroup = GroupInfo(id: id, title: "NewFolder")
        let updatedItem = PageItem(id: id, uuid: item.uuid, type: .group, ordering: 1,
                                   parentId: nil, app: nil, group: updatedGroup)
        try sut.updateItem(updatedItem)

        let fetched = try sut.fetchAllItems(parentId: nil).first
        #expect(fetched?.group?.title == "NewFolder")
    }

    @Test("updateItem 更新 ordering 和 parent_id")
    func updateItem_changesOrderingAndParent() throws {
        let sut = try makeSUT()
        let pageId = try sut.insertItem(TestDataFactory.makePageItem(type: .page, ordering: 0))
        let app = TestDataFactory.makeAppInfo(title: "MoveMe", bundleId: "com.move.app")
        let item = TestDataFactory.makePageItem(type: .app, app: app)
        let id = try sut.insertItem(item)

        // 移动到 page 下并改 ordering
        let updatedItem = PageItem(id: id, uuid: item.uuid, type: .app, ordering: 9,
                                   parentId: pageId, app: app, group: nil)
        try sut.updateItem(updatedItem)

        let topItems = try sut.fetchAllItems(parentId: nil)
        #expect(topItems.count == 1)  // 只剩 page
        let children = try sut.fetchAllItems(parentId: pageId)
        #expect(children.first?.app?.title == "MoveMe")
        #expect(children.first?.ordering == 9)
    }

    @Test("saveImage 覆盖已存在的图标")
    func saveImage_replacesExistingImage() throws {
        let sut = try makeSUT()
        let id = try sut.insertItem(TestDataFactory.makePageItem(type: .app, app: TestDataFactory.makeAppInfo()))

        try sut.saveImage(itemId: id, icon1x: Data(repeating: 0xAA, count: 10), icon2x: Data(repeating: 0xBB, count: 20))
        // 再次保存覆盖
        try sut.saveImage(itemId: id, icon1x: Data(repeating: 0xCC, count: 30), icon2x: Data(repeating: 0xDD, count: 40))

        let fetched = try sut.fetchImage(itemId: id)
        #expect(fetched != nil)
        #expect(fetched!.0 == Data(repeating: 0xCC, count: 30))
        #expect(fetched!.1 == Data(repeating: 0xDD, count: 40))
    }

    // MARK: - 错误分支覆盖（prepare 失败 + step 失败）

    private func makeNoSchemaSUT() throws -> StorageManager {
        try StorageManager(dbPath: ":memory:", schemaSetup: { _ in })
    }

    private func makeItemsOnlySUT(
        seedID: Int64? = nil,
        seedType: ItemType = .app
    ) throws -> StorageManager {
        try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, Schema.createItemsTable, nil, nil, nil)
            if let seedID {
                let sql = """
                    INSERT INTO items (id, uuid, type, ordering)
                    VALUES (\(seedID), 'seed-\(seedID)', \(seedType.rawValue), 0)
                    """
                precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
            }
        })
    }

    @Test("无表 db -> insertItem prepare 失败抛 prepareFailed")
    func noSchema_insertItem_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        #expect(throws: StorageError.self) {
            _ = try sut.insertItem(TestDataFactory.makePageItem(type: .app, app: TestDataFactory.makeAppInfo()))
        }
    }

    @Test("无表 db -> updateItem prepare 失败抛 prepareFailed")
    func noSchema_updateItem_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        do {
            try sut.updateItem(TestDataFactory.makePageItem(type: .app, app: TestDataFactory.makeAppInfo()))
            Issue.record("应抛出 StorageError")
        } catch {
            #expect(error is StorageError)
        }
    }

    @Test("无表 db -> deleteItem prepare 失败抛 prepareFailed")
    func noSchema_deleteItem_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        #expect(throws: StorageError.self) {
            try sut.deleteItem(id: 1)
        }
    }

    @Test("无表 db -> fetchAllItems prepare 失败抛 prepareFailed")
    func noSchema_fetchAllItems_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        #expect(throws: StorageError.self) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("无表 db -> reorderItems prepare 失败抛 prepareFailed")
    func noSchema_reorderItems_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        #expect(throws: StorageError.self) {
            try sut.reorderItems(parentId: 1, orderedIds: [1, 2])
        }
    }

    @Test("无表 db -> saveImage prepare 失败抛 prepareFailed")
    func noSchema_saveImage_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        #expect(throws: StorageError.self) {
            try sut.saveImage(itemId: 1, icon1x: Data([1]), icon2x: Data([2]))
        }
    }

    @Test("无表 db -> fetchImage prepare 失败抛 prepareFailed")
    func noSchema_fetchImage_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        #expect(throws: StorageError.self) {
            _ = try sut.fetchImage(itemId: 1)
        }
    }

    @Test("items 表存在但 apps 表不存在 -> insertApp prepare 失败")
    func itemsOnly_insertApp_prepareFails() throws {
        let sut = try makeItemsOnlySUT()
        #expect(throws: StorageError.self) {
            _ = try sut.insertItem(TestDataFactory.makePageItem(type: .app, app: TestDataFactory.makeAppInfo()))
        }
    }

    @Test("items 表存在但 groups 表不存在 -> insertGroup prepare 失败")
    func itemsOnly_insertGroup_prepareFails() throws {
        let sut = try makeItemsOnlySUT()
        #expect(throws: StorageError.self) {
            _ = try sut.insertItem(TestDataFactory.makePageItem(type: .group, group: TestDataFactory.makeGroupInfo()))
        }
    }

    @Test("重复 uuid -> insertItem step 失败抛 insertFailed")
    func duplicateUuid_insertItem_stepFails() throws {
        let sut = try makeSUT()
        let uuid = "duplicate-uuid"
        let item1 = TestDataFactory.makePageItem(uuid: uuid, type: .app, app: TestDataFactory.makeAppInfo())
        _ = try sut.insertItem(item1)
        let item2 = TestDataFactory.makePageItem(uuid: uuid, type: .app, app: TestDataFactory.makeAppInfo())
        #expect(throws: StorageError.self) {
            _ = try sut.insertItem(item2)
        }
    }

    @Test("带 storeId 和 category 的 app -> 覆盖 bind 分支")
    func insertApp_withStoreIdAndCategory_bindsNonNil() throws {
        let sut = try makeSUT()
        let app = TestDataFactory.makeAppInfo(
            title: "AppStore", bundleId: "com.app.store",
            storeId: "123456", category: "Games"
        )
        let item = TestDataFactory.makePageItem(type: .app, app: app)
        let id = try sut.insertItem(item)
        #expect(id > 0)

        let fetched = try sut.fetchAllItems(parentId: nil)
        #expect(fetched.first?.app?.storeId == "123456")
        #expect(fetched.first?.app?.category == "Games")
    }

    @Test("items 表存在但 apps 表不存在 -> updateItem apps prepare 失败")
    func itemsOnly_updateApp_prepareFails() throws {
        let sut = try makeItemsOnlySUT(seedID: 1, seedType: .app)
        #expect(throws: StorageError.prepareFailed) {
            try sut.updateItem(TestDataFactory.makePageItem(
                id: 1,
                type: .app,
                app: TestDataFactory.makeAppInfo()
            ))
        }
    }

    @Test("items 表存在但 groups 表不存在 -> updateItem groups prepare 失败")
    func itemsOnly_updateGroup_prepareFails() throws {
        let sut = try makeItemsOnlySUT(seedID: 2, seedType: .group)
        #expect(throws: StorageError.prepareFailed) {
            try sut.updateItem(TestDataFactory.makePageItem(
                id: 2,
                type: .group,
                group: TestDataFactory.makeGroupInfo()
            ))
        }
    }

    @Test("无表 db + parentId 非 nil -> fetchAllItems prepare 失败")
    func noSchema_fetchAllItemsWithParent_prepareFails() throws {
        let sut = try makeNoSchemaSUT()
        #expect(throws: StorageError.self) {
            _ = try sut.fetchAllItems(parentId: 1)
        }
    }

    @Test("saveImage 不存在 itemId -> 外键约束 step 失败")
    func saveImage_nonexistentItemId_stepFails() throws {
        let sut = try makeSUT()
        // itemId 不存在，image_cache.item_id 外键约束 -> step 失败
        #expect(throws: StorageError.self) {
            try sut.saveImage(itemId: 999999, icon1x: Data([1]), icon2x: Data([2]))
        }
    }

    @Test("只读 db -> 所有写操作 step 失败（覆盖 UPDATE/DELETE/INSERT step 分支）")
    func readonlyDb_writeOperations_stepFails() throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("ro_\(UUID().uuidString).db")
        defer { chmod(path, 0o644); try? FileManager.default.removeItem(atPath: path) }

        // 1. 正常建表 + 插入基础数据
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        if let db {
            Schema.setupSchema(db: db)
            // 插入一个 app item 供 update/delete 使用
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u1', 0, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES (1, 'A', 'com.a', '/a')", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u2', 2, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO groups (item_id, title) VALUES (2, 'G')", nil, nil, nil)
        }
        sqlite3_close(db)

        // 2. 设文件只读
        chmod(path, 0o444)

        // 3. 打开只读 db（跳过建表，表已存在）
        let sut = try StorageManager(dbPath: path, schemaSetup: { _ in })

        // 4. 各写操作 step 失败
        #expect(throws: StorageError.self) {
            _ = try sut.insertItem(TestDataFactory.makePageItem(uuid: "ro", type: .group, group: TestDataFactory.makeGroupInfo()))
        }
        #expect(throws: StorageError.self) {
            try sut.updateItem(TestDataFactory.makePageItem(id: 1, uuid: "u1", type: .app, app: TestDataFactory.makeAppInfo()))
        }
        #expect(throws: StorageError.self) {
            try sut.deleteItem(id: 1)
        }
        #expect(throws: StorageError.self) {
            try sut.reorderItems(parentId: 0, orderedIds: [1, 2])
        }
    }

    @Test("触发器使 apps/groups UPDATE+INSERT 失败 -> 覆盖 apps/groups step 分支")
    func triggerFail_appsGroups_stepFails() throws {
        // 建 items+apps+groups 表，插入基础数据，加触发器使 apps UPDATE、groups UPDATE/INSERT 失败
        // items 操作成功，apps/groups 操作 step 失败
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            sqlite3_exec(db, Schema.createItemsTable, nil, nil, nil)
            sqlite3_exec(db, Schema.createAppsTable, nil, nil, nil)
            sqlite3_exec(db, Schema.createGroupsTable, nil, nil, nil)
            // 基础数据
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u1', 0, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO apps (item_id, title, bundle_id, path) VALUES (1, 'A', 'com.a', '/a')", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO items (uuid, type, ordering) VALUES ('u2', 2, 0)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO groups (item_id, title) VALUES (2, 'G')", nil, nil, nil)
            // 触发器
            sqlite3_exec(db, "CREATE TRIGGER fail_apps_update BEFORE UPDATE ON apps BEGIN SELECT RAISE(ABORT, 'fail'); END", nil, nil, nil)
            sqlite3_exec(db, "CREATE TRIGGER fail_groups_update BEFORE UPDATE ON groups BEGIN SELECT RAISE(ABORT, 'fail'); END", nil, nil, nil)
            sqlite3_exec(db, "CREATE TRIGGER fail_groups_insert BEFORE INSERT ON groups BEGIN SELECT RAISE(ABORT, 'fail'); END", nil, nil, nil)
        })

        // updateItem(type:.app): items step 成功 -> apps step 失败（触发器）-> L133
        #expect(throws: StorageError.self) {
            try sut.updateItem(TestDataFactory.makePageItem(id: 1, uuid: "u1", type: .app, app: TestDataFactory.makeAppInfo()))
        }
        // updateItem(type:.group): items step 成功 -> groups step 失败（触发器）-> L148
        #expect(throws: StorageError.self) {
            try sut.updateItem(TestDataFactory.makePageItem(id: 2, uuid: "u2", type: .group, group: TestDataFactory.makeGroupInfo()))
        }
        // insertItem(type:.group): items step 成功 -> insertGroup step 失败（触发器）-> L347
        #expect(throws: StorageError.self) {
            _ = try sut.insertItem(TestDataFactory.makePageItem(uuid: "u3", type: .group, group: TestDataFactory.makeGroupInfo()))
        }
    }
}

// MARK: - Branch coverage: fetchImage with NULL blobs

@Suite("StorageManager fetchImage NULL blob")
struct StorageManagerFetchImageNullBlobTests {

    @Test("fetchImage 中 icon_1x 为 NULL 时返回 nil")
    func fetchImage_icon1xNull_returnsNil() throws {
        var capturedDB: OpaquePointer?
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            Schema.setupSchema(db: db)
            capturedDB = db
        })
        let db = try #require(capturedDB)

        // 直接插入一条 icon_1x=NULL 的记录（绕过 saveImage 的 blob 绑定方式）
        let insertSQL = "INSERT INTO image_cache (item_id, icon_1x, icon_2x) VALUES (1, NULL, x'010203')"
        sqlite3_exec(db, insertSQL, nil, nil, nil)

        let result = try sut.fetchImage(itemId: 1)
        #expect(result == nil)
    }

    @Test("fetchImage 中 icon_2x 为 NULL 时返回 nil")
    func fetchImage_icon2xNull_returnsNil() throws {
        var capturedDB: OpaquePointer?
        let sut = try StorageManager(dbPath: ":memory:", schemaSetup: { db in
            Schema.setupSchema(db: db)
            capturedDB = db
        })
        let db = try #require(capturedDB)

        // 直接插入一条 icon_2x=NULL 的记录
        let insertSQL = "INSERT INTO image_cache (item_id, icon_1x, icon_2x) VALUES (2, x'010203', NULL)"
        sqlite3_exec(db, insertSQL, nil, nil, nil)

        let result = try sut.fetchImage(itemId: 2)
        #expect(result == nil)
    }
}

@Suite("StorageManager checked SQLite boundaries")
struct StorageManagerSQLiteBoundaryTests {
    @Test("deferred 与 immediate 使用对应 SQLite transaction mode")
    func transactionModesEnterExpectedSQLiteState() throws {
        try withSQLiteDatabase { database in
            let transaction = SQLiteTransaction(
                database: database,
                driver: SQLiteDriver(faultInjector: nil)
            )

            let deferredState = try transaction.run(mode: .deferred) {
                sqlite3_txn_state(database, nil)
            }
            let immediateState = try transaction.run(mode: .immediate) {
                sqlite3_txn_state(database, nil)
            }

            #expect(deferredState == SQLITE_TXN_NONE)
            #expect(immediateState == SQLITE_TXN_WRITE)
        }
    }

    @Test("BEGIN 失败不执行事务 body")
    func beginFailureDoesNotWrite() throws {
        let script = SQLiteFaultScript()
        let sut = try makeFaultableStorage(script)
        script.failNext(.begin, code: SQLITE_BUSY)

        #expect(throws: StorageError.beginFailed) {
            _ = try sut.insertItem(
                TestDataFactory.makePageItem(
                    uuid: "begin-failure",
                    type: .page
                )
            )
        }
        #expect(script.invocationCount(for: .rollback) == 0)
        #expect(try sut.fetchAllItems(parentId: nil).isEmpty)
    }

    @Test("COMMIT 失败回滚 insert")
    func commitFailureRollsBackInsert() throws {
        let script = SQLiteFaultScript()
        let sut = try makeFaultableStorage(script)
        script.failNext(.commit, code: SQLITE_IOERR)

        #expect(throws: StorageError.commitFailed) {
            _ = try sut.insertItem(
                TestDataFactory.makePageItem(
                    uuid: "commit-failure",
                    type: .page
                )
            )
        }
        #expect(script.invocationCount(for: .rollback) == 1)
        #expect(try sut.fetchAllItems(parentId: nil).isEmpty)
    }

    @Test("ROLLBACK 失败保留 primary error 并使 storage 不可用")
    func rollbackFailureInvalidatesStorage() throws {
        let script = SQLiteFaultScript()
        let sut = try makeFaultableStorage(script)
        _ = try sut.insertItem(
            TestDataFactory.makePageItem(uuid: "duplicate", type: .page)
        )
        script.failNext(.rollback, code: SQLITE_IOERR)

        do {
            _ = try sut.insertItem(
                TestDataFactory.makePageItem(uuid: "duplicate", type: .page)
            )
            Issue.record("expected SQLiteRollbackFailure")
        } catch let error as SQLiteRollbackFailure {
            #expect(error.primaryError as? StorageError == .insertFailed)
            #expect(error.rollbackCode == SQLITE_IOERR)
        }
        #expect(throws: StorageError.storageUnavailable) {
            _ = try sut.fetchAllItems(parentId: nil)
        }
    }

    @Test("SQLite 已进入 autocommit 时保留 primary error 且不执行 synthetic rollback")
    func alreadyAutocommitDoesNotRollback() throws {
        try withSQLiteDatabase { database in
            let script = SQLiteFaultScript()
            script.failNext(.rollback, code: SQLITE_IOERR)
            let transaction = SQLiteTransaction(
                database: database,
                driver: SQLiteDriver(faultInjector: script.result(for:))
            )

            #expect(throws: StorageError.updateFailed) {
                try transaction.run(mode: .deferred) {
                    #expect(sqlite3_exec(
                        database,
                        "ROLLBACK",
                        nil,
                        nil,
                        nil
                    ) == SQLITE_OK)
                    throw StorageError.updateFailed
                }
            }
            #expect(script.invocationCount(for: .rollback) == 0)

            do {
                try transaction.run(mode: .deferred) {
                    throw StorageError.deleteFailed
                }
                Issue.record("expected SQLiteRollbackFailure")
            } catch let error as SQLiteRollbackFailure {
                #expect(error.primaryError as? StorageError == .deleteFailed)
                #expect(error.rollbackCode == SQLITE_IOERR)
            }
        }
    }

    @Test("driver prepare/bind/step/changes 故障精确映射并回滚")
    func driverWriteFaultsMapAndRollback() throws {
        let cases: [(SQLiteFaultPoint, Int32, StorageError)] = [
            (.prepare(.insertItem), SQLITE_IOERR, .prepareFailed),
            (.bind(.insertItem, index: 1), SQLITE_RANGE, .bindFailed),
            (.step(.insertItem), SQLITE_IOERR, .insertFailed),
            (.changes(.insertItem), 0, .insertFailed),
        ]

        for (index, testCase) in cases.enumerated() {
            let (point, code, expectedError) = testCase
            let script = SQLiteFaultScript()
            let sut = try makeFaultableStorage(script)
            script.failNext(point, code: code)

            do {
                _ = try sut.insertItem(
                    TestDataFactory.makePageItem(
                        uuid: "driver-fault-\(index)",
                        type: .page
                    )
                )
                Issue.record("expected \(expectedError)")
            } catch let error as StorageError {
                #expect(error == expectedError)
            }
            #expect(script.invocationCount(for: .rollback) == 1)
            #expect(try sut.fetchAllItems(parentId: nil).isEmpty)
        }
    }

    @Test("driver bind fault 短路底层表达式")
    func driverBindFaultDoesNotEvaluateOperation() {
        let script = SQLiteFaultScript()
        let point = SQLiteFaultPoint.bind(.insertItem, index: 1)
        script.failNext(point, code: SQLITE_RANGE)
        let driver = SQLiteDriver(faultInjector: script.result(for:))
        var evaluationCount = 0

        let code = driver.bind({
            evaluationCount += 1
            return SQLITE_OK
        }(), kind: .insertItem, index: 1)

        #expect(code == SQLITE_RANGE)
        #expect(evaluationCount == 0)
        #expect(script.invocationCount(for: point) == 1)
    }

    @Test("metadata helper 故障精确映射并回滚")
    func metadataFaultsMapAndRollback() throws {
        let insertScript = SQLiteFaultScript()
        let insertSUT = try makeFaultableStorage(insertScript)
        insertScript.failNext(.bind(.insertAppMetadata, index: 6), code: SQLITE_RANGE)
        #expect(throws: StorageError.bindFailed) {
            _ = try insertSUT.insertItem(TestDataFactory.makePageItem(
                uuid: "metadata-insert",
                type: .app,
                app: TestDataFactory.makeAppInfo(bundleId: "metadata.insert")
            ))
        }
        #expect(insertScript.invocationCount(for: .rollback) == 1)
        #expect(try insertSUT.fetchAllItems(parentId: nil).isEmpty)

        let updateScript = SQLiteFaultScript()
        let updateSUT = try makeFaultableStorage(updateScript)
        let item = TestDataFactory.makePageItem(
            uuid: "metadata-update",
            type: .group,
            group: TestDataFactory.makeGroupInfo(title: "Before")
        )
        let itemID = try updateSUT.insertItem(item)
        updateScript.failNext(.changes(.updateGroupMetadata), code: 0)
        #expect(throws: StorageError.updateFailed) {
            try updateSUT.updateItem(PageItem(
                id: itemID,
                uuid: item.uuid,
                type: .group,
                ordering: 5,
                parentId: nil,
                app: nil,
                group: GroupInfo(id: itemID, title: "After")
            ))
        }
        #expect(updateScript.invocationCount(for: .rollback) == 1)
        let stored = try #require(updateSUT.fetchAllItems(parentId: nil).first)
        #expect(stored.ordering == 0)
        #expect(stored.group?.title == "Before")
    }

    @Test("fetchItems 首次与 terminal step 错误均抛 queryFailed")
    func fetchItemsStepErrorsAreNotEndOfData() throws {
        let firstScript = SQLiteFaultScript()
        let firstSUT = try makeFaultableStorage(firstScript)
        firstScript.failNext(.step(.fetchItems), code: SQLITE_IOERR)
        #expect(throws: StorageError.queryFailed) {
            _ = try firstSUT.fetchAllItems(parentId: nil)
        }

        let terminalScript = SQLiteFaultScript()
        let terminalSUT = try makeFaultableStorage(terminalScript)
        _ = try terminalSUT.insertItem(
            TestDataFactory.makePageItem(uuid: "fetch-terminal", type: .page)
        )
        terminalScript.fail(
            .step(.fetchItems),
            onOccurrence: 2,
            code: SQLITE_IOERR
        )
        #expect(throws: StorageError.queryFailed) {
            _ = try terminalSUT.fetchAllItems(parentId: nil)
        }
    }

    @Test("fetchImage 首次与 terminal step 错误均抛 queryFailed")
    func fetchImageStepErrorsAreNotMissingData() throws {
        let firstScript = SQLiteFaultScript()
        let firstSUT = try makeFaultableStorage(firstScript)
        firstScript.failNext(.step(.fetchImage), code: SQLITE_IOERR)
        #expect(throws: StorageError.queryFailed) {
            _ = try firstSUT.fetchImage(itemId: 1)
        }

        let terminalScript = SQLiteFaultScript()
        let terminalSUT = try makeFaultableStorage(terminalScript)
        let itemID = try terminalSUT.insertItem(
            TestDataFactory.makePageItem(uuid: "image-terminal", type: .page)
        )
        try terminalSUT.saveImage(
            itemId: itemID,
            icon1x: Data([1]),
            icon2x: Data([2])
        )
        terminalScript.fail(
            .step(.fetchImage),
            onOccurrence: 2,
            code: SQLITE_IOERR
        )
        #expect(throws: StorageError.queryFailed) {
            _ = try terminalSUT.fetchImage(itemId: itemID)
        }
    }

    @Test("stale update/delete/reorder ID 均严格失败且 reorder 回滚")
    func staleWriteIDsFailStrictly() throws {
        let sut = try StorageManager(dbPath: ":memory:")
        #expect(throws: StorageError.updateFailed) {
            try sut.updateItem(TestDataFactory.makePageItem(
                id: 999,
                uuid: "stale-update",
                type: .page
            ))
        }
        #expect(throws: StorageError.deleteFailed) {
            try sut.deleteItem(id: 999)
        }

        let pageID = try sut.insertItem(
            TestDataFactory.makePageItem(uuid: "stale-page", type: .page)
        )
        let firstID = try sut.insertItem(TestDataFactory.makePageItem(
            uuid: "stale-first",
            type: .app,
            ordering: 0,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "stale.first")
        ))
        let secondID = try sut.insertItem(TestDataFactory.makePageItem(
            uuid: "stale-second",
            type: .app,
            ordering: 1,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "stale.second")
        ))
        #expect(throws: StorageError.updateFailed) {
            try sut.reorderItems(
                parentId: pageID,
                orderedIds: [secondID, 999]
            )
        }
        let storedItems = try sut.fetchAllItems(parentId: pageID)
        #expect(storedItems.map(\.id) == [firstID, secondID])
        let storedFirst = try #require(storedItems.first { $0.id == firstID })
        let storedSecond = try #require(storedItems.first { $0.id == secondID })
        #expect(storedFirst.ordering == 0)
        #expect(storedSecond.ordering == 1)
    }

    @Test("全部 7 个 public API 精确进入同一 databaseQueue")
    func everyPublicMethodUsesDatabaseQueue() throws {
        let sut = try StorageManager(dbPath: ":memory:")
        let pageID = try sut.insertItem(
            TestDataFactory.makePageItem(uuid: "queue-page", type: .page)
        )
        let app = TestDataFactory.makeAppInfo(
            title: "Queue",
            bundleId: "com.test.queue"
        )
        let appID = try sut.insertItem(TestDataFactory.makePageItem(
            uuid: "queue-app",
            type: .app,
            parentId: pageID,
            app: app
        ))
        let recorder = QueueObservationRecorder()
        sut.databaseAccessObserver = { recorder.append($0) }

        let removableID = try sut.insertItem(
            TestDataFactory.makePageItem(uuid: "queue-removable", type: .page)
        )
        try sut.updateItem(PageItem(
            id: appID,
            uuid: "queue-app",
            type: .app,
            ordering: 0,
            parentId: pageID,
            app: AppInfo(
                id: appID,
                title: "Queue Updated",
                bundleId: "com.test.queue",
                path: app.path,
                storeId: nil,
                category: nil
            ),
            group: nil
        ))
        try sut.deleteItem(id: removableID)
        _ = try sut.fetchAllItems(parentId: pageID)
        try sut.reorderItems(parentId: pageID, orderedIds: [appID])
        try sut.saveImage(itemId: appID, icon1x: Data([1]), icon2x: Data([2]))
        _ = try sut.fetchImage(itemId: appID)

        #expect(recorder.snapshot.count == 7)
        #expect(recorder.snapshot.allSatisfy { $0 })
    }
}
