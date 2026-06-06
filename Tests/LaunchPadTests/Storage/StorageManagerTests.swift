import Testing
import Foundation
@testable import LaunchPad

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
}
