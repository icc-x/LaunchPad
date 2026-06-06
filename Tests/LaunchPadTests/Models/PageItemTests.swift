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
        let item = PageItem(id: 10, uuid: "uuid-10", type: .app, ordering: 0,
                            parentId: nil, app: app, group: nil)
        #expect(item.type == .app)
        #expect(item.app?.title == "Safari")
        #expect(item.group == nil)
    }

    @Test("PageItem 包含 group 类型时有 group 属性")
    func pageItem_withGroup() {
        let group = GroupInfo(id: 2, title: "Favorites")
        let item = PageItem(id: 20, uuid: "uuid-20", type: .group, ordering: 1,
                            parentId: nil, app: nil, group: group)
        #expect(item.type == .group)
        #expect(item.group?.title == "Favorites")
        #expect(item.app == nil)
    }

    @Test("PageItem 是 page 类型时无 app 和 group")
    func pageItem_pageType() {
        let item = PageItem(id: 1, uuid: "page-1", type: .page, ordering: 0,
                            parentId: nil, app: nil, group: nil)
        #expect(item.type == .page)
        #expect(item.app == nil)
        #expect(item.group == nil)
    }

    @Test("PageItem 遵循 Hashable — 相同 id 和 uuid 相等")
    func pageItem_hashable() {
        let a = PageItem(id: 1, uuid: "u1", type: .app, ordering: 0,
                         parentId: nil, app: nil, group: nil)
        let b = PageItem(id: 1, uuid: "u1", type: .app, ordering: 0,
                         parentId: nil, app: nil, group: nil)
        #expect(a == b)
        let s: Set<PageItem> = [a, b]
        #expect(s.count == 1)
    }

    @Test("PageItem 遵循 Identifiable")
    func pageItem_identifiable() {
        let item = PageItem(id: 42, uuid: "u42", type: .app, ordering: 0,
                            parentId: nil, app: nil, group: nil)
        #expect(item.id == 42)
    }

    @Test("PageItem parentId 可选 — 顶层 item 为 nil")
    func pageItem_parentIdOptional() {
        let item = PageItem(id: 1, uuid: "u1", type: .app, ordering: 0,
                            parentId: nil, app: nil, group: nil)
        #expect(item.parentId == nil)
    }

    @Test("PageItem parentId 有值 — 子 item 属于文件夹")
    func pageItem_withParentId() {
        let item = PageItem(id: 2, uuid: "u2", type: .app, ordering: 0,
                            parentId: 1, app: nil, group: nil)
        #expect(item.parentId == 1)
    }
}
