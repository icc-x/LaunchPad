import Foundation
import Testing
@testable import LaunchPad
import LaunchPadProtocols

// MARK: - ItemType Tests

@Suite("ItemType 枚举")
struct ItemTypeTests {

    @Test("ItemType 包含 page/app/group 三种类型")
    func itemType_hasThreeTypes() {
        #expect(ItemType.allCases.count == 3)
    }

    @Test("ItemType 的 rawValue 与设计文档一致")
    func itemType_rawValues() {
        #expect(ItemType.page.rawValue == 1)
        #expect(ItemType.app.rawValue == 4)
        #expect(ItemType.group.rawValue == 7)
    }

    @Test("ItemType 可从 rawValue 还原")
    func itemType_fromRawValue() {
        #expect(ItemType(rawValue: 1) == .page)
        #expect(ItemType(rawValue: 4) == .app)
        #expect(ItemType(rawValue: 7) == .group)
        #expect(ItemType(rawValue: 99) == nil)
    }
}

// MARK: - AppInfo Tests

@Suite("AppInfo 结构体")
struct AppInfoTests {

    @Test("AppInfo 可创建并正确存储所有属性")
    func appInfo_properties() {
        let app = AppInfo(
            id: 42,
            title: "Safari",
            bundleId: "com.apple.Safari",
            path: "/Applications/Safari.app",
            storeId: "12345",
            category: "Productivity"
        )
        #expect(app.id == 42)
        #expect(app.title == "Safari")
        #expect(app.bundleId == "com.apple.Safari")
        #expect(app.path == "/Applications/Safari.app")
        #expect(app.storeId == "12345")
        #expect(app.category == "Productivity")
    }

    @Test("AppInfo storeId 和 category 可选")
    func appInfo_optionalFields() {
        let app = AppInfo(
            id: 1,
            title: "Test",
            bundleId: "com.test.app",
            path: "/Applications/Test.app",
            storeId: nil,
            category: nil
        )
        #expect(app.storeId == nil)
        #expect(app.category == nil)
    }

    @Test("AppInfo 遵循 Hashable")
    func appInfo_hashable() {
        let a = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let b = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("不同 bundleId 的 AppInfo 不相等")
    func appInfo_notEqual() {
        let a = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let b = AppInfo(id: 1, title: "A", bundleId: "com.b", path: "/a", storeId: nil, category: nil)
        #expect(a != b)
    }
}

// MARK: - GroupInfo Tests

@Suite("GroupInfo 结构体")
struct GroupInfoTests {

    @Test("GroupInfo 默认标题为 'New Folder'")
    func groupInfo_defaultTitle() {
        let group = GroupInfo(id: 1, title: "New Folder")
        #expect(group.title == "New Folder")
    }

    @Test("GroupInfo title 可变")
    func groupInfo_mutableTitle() {
        var group = GroupInfo(id: 1, title: "New Folder")
        group.title = "Favorites"
        #expect(group.title == "Favorites")
    }

    @Test("GroupInfo 遵循 Hashable")
    func groupInfo_hashable() {
        let a = GroupInfo(id: 1, title: "A")
        let b = GroupInfo(id: 1, title: "A")
        #expect(a == b)
    }
}

// MARK: - PageItem Tests

@Suite("PageItem 结构体")
struct PageItemTests {

    @Test("PageItem 包含 app 类型时有 app 属性")
    func pageItem_withApp() {
        let app = AppInfo(id: 1, title: "Safari", bundleId: "com.apple.Safari",
                          path: "/Applications/Safari.app", storeId: nil, category: nil)
        let item = PageItem.app(id: 10, uuid: "uuid-10", ordering: 0, parentId: nil, app: app)
        #expect(item.type == .app)
        #expect(item.app?.title == "Safari")
        #expect(item.group == nil)
    }

    @Test("PageItem 包含 group 类型时有 group 属性")
    func pageItem_withGroup() {
        let group = GroupInfo(id: 2, title: "Favorites")
        let item = PageItem.group(id: 20, uuid: "uuid-20", ordering: 1, parentId: nil, group: group)
        #expect(item.type == .group)
        #expect(item.group?.title == "Favorites")
        #expect(item.app == nil)
    }

    @Test("PageItem 是 page 类型时无 app 和 group")
    func pageItem_pageType() {
        let item = PageItem.page(id: 1, uuid: "page-1", ordering: 0)
        #expect(item.type == .page)
        #expect(item.app == nil)
        #expect(item.group == nil)
    }

    @Test("PageItem 遵循 Hashable — 相同 id 和 uuid 相等")
    func pageItem_hashable() {
        let app = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let a = PageItem.app(id: 1, uuid: "u1", ordering: 0, parentId: nil, app: app)
        let b = PageItem.app(id: 1, uuid: "u1", ordering: 0, parentId: nil, app: app)
        #expect(a == b)
        let s: Set<PageItem> = [a, b]
        #expect(s.count == 1)
    }

    @Test("PageItem 遵循 Identifiable")
    func pageItem_identifiable() {
        let app = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let item = PageItem.app(id: 42, uuid: "u42", ordering: 0, parentId: nil, app: app)
        #expect(item.id == 42)
    }

    @Test("PageItem parentId 可选 — 顶层 item 为 nil")
    func pageItem_parentIdOptional() {
        let app = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let item = PageItem.app(id: 1, uuid: "u1", ordering: 0, parentId: nil, app: app)
        #expect(item.parentId == nil)
    }

    @Test("PageItem parentId 有值 — 子 item 属于文件夹")
    func pageItem_withParentId() {
        let app = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let item = PageItem.app(id: 2, uuid: "u2", ordering: 0, parentId: 1, app: app)
        #expect(item.parentId == 1)
    }

    // MARK: - Invariants

    @Test("类型化工厂只产出合法状态")
    func factories_produceOnlyLegalStates() {
        let app = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let group = GroupInfo(id: 2, title: "F")
        let page = PageItem.page(id: 1, uuid: "p", ordering: 0)
        let appItem = PageItem.app(id: 2, uuid: "a", ordering: 0, parentId: nil, app: app)
        let groupItem = PageItem.group(id: 3, uuid: "g", ordering: 0, parentId: nil, group: group)
        #expect(page.type == .page && page.app == nil && page.group == nil)
        #expect(appItem.type == .app && appItem.app != nil && appItem.group == nil)
        #expect(groupItem.type == .group && groupItem.app == nil && groupItem.group != nil)
    }

    @Test("合法 Codable round-trip 保留全部字段")
    func codable_roundTrip() throws {
        let app = AppInfo(id: 1, title: "A", bundleId: "com.a", path: "/a", storeId: nil, category: nil)
        let original = PageItem.app(id: 7, uuid: "u7", ordering: 3, parentId: 2, app: app)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageItem.self, from: data)
        #expect(decoded == original)
    }

    @Test("非法 metadata 组合全部被 JSON 解码拒绝")
    func codable_rejectsIllegalCombinations() throws {
        let appJSON = """
            {"id":1,"title":"A","bundleId":"com.a","path":"/a","storeId":null,"category":null}
            """
        let groupJSON = """
            {"id":2,"title":"F"}
            """
        let base = """
            {"id":9,"uuid":"u","type":%d,"ordering":0,"parentId":null,"app":%@,"group":%@}
            """
        let cases: [(Int, String, String)] = [
            (1, appJSON, "null"),
            (1, "null", groupJSON),
            (4, "null", "null"),
            (4, "null", groupJSON),
            (7, appJSON, "null"),
            (7, "null", "null"),
        ]
        for (rawType, appValue, groupValue) in cases {
            let json = String(format: base, rawType, appValue, groupValue)
            let data = Data(json.utf8)
            #expect(throws: ValidationError.self) {
                _ = try JSONDecoder().decode(PageItem.self, from: data)
            }
        }
    }

    @Test("未知 type 的 JSON 被拒绝")
    func codable_rejectsUnknownType() throws {
        let json = """
            {"id":9,"uuid":"u","type":99,"ordering":0,"parentId":null,"app":null,"group":null}
            """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(PageItem.self, from: Data(json.utf8))
        }
    }
}
