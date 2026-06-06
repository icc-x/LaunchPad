import Foundation
import LaunchPadProtocols
@testable import LaunchPad

enum TestDataFactory {
    static func makePageItem(
        id: Int64 = Int64.random(in: 1...Int64.max),
        uuid: String = UUID().uuidString,
        type: ItemType = .app,
        ordering: Int = 0,
        parentId: Int64? = nil,
        app: AppInfo? = nil,
        group: GroupInfo? = nil
    ) -> PageItem {
        PageItem(id: id, uuid: uuid, type: type, ordering: ordering,
                 parentId: parentId, app: app, group: group)
    }

    static func makeAppInfo(
        id: Int64 = Int64.random(in: 1...Int64.max),
        title: String = "TestApp",
        bundleId: String = "com.test.app",
        path: String = "/Applications/TestApp.app",
        storeId: String? = nil,
        category: String? = nil
    ) -> AppInfo {
        AppInfo(id: id, title: title, bundleId: bundleId, path: path,
                storeId: storeId, category: category)
    }

    static func makeGroupInfo(
        id: Int64 = Int64.random(in: 1...Int64.max),
        title: String = "New Folder"
    ) -> GroupInfo {
        GroupInfo(id: id, title: title)
    }

    static func makeAppItems(count: Int, titlePrefix: String = "App") -> [PageItem] {
        (0..<count).map { i in
            makePageItem(id: Int64(i + 1), uuid: "app-\(i)", ordering: i,
                         app: makeAppInfo(id: Int64(i + 1), title: "\(titlePrefix) \(i)",
                                          bundleId: "com.test.\(titlePrefix.lowercased())\(i)"))
        }
    }
}
