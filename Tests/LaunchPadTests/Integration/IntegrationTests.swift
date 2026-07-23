import Testing
import Foundation
import SQLite3
@testable import LaunchPad
import LaunchPadProtocols

@Suite("Integration Tests — 跨模块集成验证")
struct IntegrationTests {

    private struct FolderCardinalityFixture {
        let pageID: Int64
        let leftID: Int64
        let folderID: Int64
        let childID: Int64?
        let rightID: Int64

        init(
            storage: StorageManager,
            prefix: String,
            hasChild: Bool
        ) throws {
            pageID = try storage.insertItem(
                TestDataFactory.makePageItem(uuid: "\(prefix)-page", type: .page)
            )
            leftID = try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "\(prefix)-left",
                type: .app,
                ordering: 0,
                parentId: pageID,
                app: TestDataFactory.makeAppInfo(
                    bundleId: "com.test.\(prefix).left"
                )
            ))
            folderID = try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "\(prefix)-folder",
                type: .group,
                ordering: 1,
                parentId: pageID,
                group: TestDataFactory.makeGroupInfo(title: prefix)
            ))
            childID = hasChild ? try storage.insertItem(
                TestDataFactory.makePageItem(
                    uuid: "\(prefix)-child",
                    type: .app,
                    ordering: 0,
                    parentId: folderID,
                    app: TestDataFactory.makeAppInfo(
                        bundleId: "com.test.\(prefix).child"
                    )
                )
            ) : nil
            rightID = try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "\(prefix)-right",
                type: .app,
                ordering: 2,
                parentId: pageID,
                app: TestDataFactory.makeAppInfo(
                    bundleId: "com.test.\(prefix).right"
                )
            ))
        }
    }

    private func temporaryLayoutDirectory(_ prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    // MARK: - 首次启动流程

    @Test("首次启动 — 空扫描后分页查询返回正确数量")
    func firstLaunch_emptyScan_pagination_correctItemCount() throws {
        let mockFS = MockFileSystemService()
        mockFS.directoryContents = []
        let storage = try StorageManager(dbPath: ":memory:")

        let scanned: [ScannedApp] = []
        _ = try storage.synchronizeInstalledApps(scanned, initialPageCapacity: 20)

        let allItems = try storage.fetchAllItems(parentId: nil)
        #expect(allItems.count == 1, "空扫描后保留唯一空页")
    }

    // MARK: - 搜索过滤流程

    @Test("搜索 — 输入关键词后过滤出匹配结果")
    func search_filter_verifyResults() throws {
        let safari = TestDataFactory.makeAppItems(count: 1, titlePrefix: "Safari")[0]
        let mail = TestDataFactory.makeAppItems(count: 1, titlePrefix: "Mail")[0]
        let terminal = TestDataFactory.makeAppItems(count: 1, titlePrefix: "Terminal")[0]
        let items = [safari, mail, terminal]

        let results = SearchEngine().search(items: items, query: "Saf")

        #expect(results.count == 1)
        #expect(results.first?.app?.title.contains("Safari") == true)
    }

    // MARK: - 错误恢复流程

    @Test("错误恢复 — 数据库损坏后删除重建并重新扫描")
    func errorRecovery_corruptedDB_delete_rescan_functional() throws {
        let tmpDir = NSTemporaryDirectory()
            .appending("LaunchPadIntegrationTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tmpDir,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let dbPath = tmpDir + "/launchpad.db"

        let corruptData = Data(repeating: 0xFF, count: 1024)
        FileManager.default.createFile(atPath: dbPath, contents: corruptData)

        let strategy = ErrorRecovery.handleSQLiteCorruption(dbPath: dbPath)
        #expect(strategy == .deleteAndRescan)

        try FileManager.default.removeItem(atPath: dbPath)

        #expect(!FileManager.default.fileExists(atPath: dbPath))

        let storage = try StorageManager(dbPath: dbPath)
        let count = try storage.fetchAllItems(parentId: nil).count
        #expect(count == 0, "新建数据库应为空")
    }

    // MARK: - 完整流程：扫描 → 存储 → 搜索

    @Test("完整流程 — 扫描应用写入存储后可搜索")
    func fullFlow_scanStoreSearch() throws {
        let mockFS = MockFileSystemService()
        let appDir = URL(fileURLWithPath: "/Applications")
        let safariURL = appDir.appendingPathComponent("Safari.app")
        let mailURL = appDir.appendingPathComponent("Mail.app")

        mockFS.directoryContentsMap[appDir] = [safariURL, mailURL]
        mockFS.existingFiles = [safariURL, mailURL]
        mockFS.bundleInfos[safariURL] = [
            "CFBundleName": "Safari",
            "CFBundleIdentifier": "com.apple.Safari"
        ]
        mockFS.bundleInfos[mailURL] = [
            "CFBundleName": "Mail",
            "CFBundleIdentifier": "com.apple.Mail"
        ]

        let scanner = AppScanner(fileSystemService: mockFS)
        let storage = try StorageManager(dbPath: ":memory:")

        let discovery = scanner.scanDirectories([appDir])
        #expect(discovery.apps.count == 2)
        #expect(discovery.isComplete)

        _ = try storage.synchronizeInstalledApps(discovery.apps, initialPageCapacity: 35)

        let allItems = try storage.fetchAllItems(parentId: nil)
        // 应有 1 个 page + 2 个 app = 3 个 items（但 app 在 page 下，所以顶层只有 page）
        let pages = allItems.filter { $0.type == .page }
        #expect(pages.count == 1)

        // 查询 page 下的 apps
        let pageId = pages[0].id
        let apps = try storage.fetchAllItems(parentId: pageId)
        #expect(apps.count == 2)

        // 搜索
        let searchResults = SearchEngine().search(items: apps, query: "saf")
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.app?.title == "Safari")
    }

    // MARK: - 布局计算集成

    @Test("布局计算 — 网格参数与分页数量一致")
    func layout_gridParamsMatchPagination() {
        let params = GridLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1440, height: 620)
        )
        #expect(params.columns == 7)
        #expect(params.rows == 5)
        #expect(params.itemsPerPage == 35)
    }

    // MARK: - 首次启动分页（100 个应用）

    @Test("首次启动 — 100 个应用 + 35 每页 → 创建 3 页，最后一页 30 项")
    func firstLaunch_100apps_pagination() throws {
        let storage = try StorageManager(dbPath: ":memory:")

        // 创建 100 个扫描结果
        let apps = (0..<100).map { i in
            ScannedApp(name: "App\(String(format: "%03d", i))",
                       bundleId: "com.test.app\(i)",
                       path: "/Applications/App\(i).app")
        }

        _ = try storage.synchronizeInstalledApps(apps, initialPageCapacity: 35)

        let pages = try storage.fetchAllItems(parentId: nil).filter { $0.type == .page }.sorted { $0.ordering < $1.ordering }
        #expect(pages.count == 3, "100/35 应创建 3 页")

        let page1Apps = try storage.fetchAllItems(parentId: pages[0].id)
        let page2Apps = try storage.fetchAllItems(parentId: pages[1].id)
        let page3Apps = try storage.fetchAllItems(parentId: pages[2].id)

        #expect(page1Apps.count == 35, "第一页应有 35 项")
        #expect(page2Apps.count == 35, "第二页应有 35 项")
        #expect(page3Apps.count == 30, "最后一页应有 30 项")
    }

    @Test("首次启动 — 应用按字母顺序排列，跨页连续")
    func firstLaunch_alphabetical_order() throws {
        let storage = try StorageManager(dbPath: ":memory:")

        // 创建乱序应用名
        let names = ["Zulu", "Alpha", "Mike", "Bravo", "Echo", "Charlie", "Delta", "Foxtrot",
                     "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima", "November",
                     "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
                     "Victor", "Whiskey", "Xray", "Yankee", "Alpha2", "Bravo2", "Charlie2", "Delta2",
                     "Echo2", "Foxtrot2", "Golf2", "Hotel2", "India2", "Juliet2"]
        let apps = names.enumerated().map { i, name in
            ScannedApp(name: name, bundleId: "com.test.\(name.lowercased())", path: "/Applications/\(name).app")
        }

        _ = try storage.synchronizeInstalledApps(apps, initialPageCapacity: 35)

        let pages = try storage.fetchAllItems(parentId: nil).filter { $0.type == .page }.sorted { $0.ordering < $1.ordering }
        let page1Apps = try storage.fetchAllItems(parentId: pages[0].id).sorted { $0.ordering < $1.ordering }

        // 第一个应用应该是按字母序排列的
        let titles = page1Apps.compactMap { $0.app?.title }
        let sortedTitles = titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        #expect(titles == sortedTitles, "应用应按字母顺序排列")
    }

    @Test("真实增量扫描从完整快照更新删除插入")
    func incrementalScanRoundTripUsesAllPersistedItems() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        _ = try storage.synchronizeInstalledApps([
            ScannedApp(name: "A", bundleId: "com.test.a", path: "/A.app"),
            ScannedApp(name: "B", bundleId: "com.test.b", path: "/B.app"),
        ], initialPageCapacity: 28)

        _ = try storage.synchronizeInstalledApps([
            ScannedApp(name: "A changed", bundleId: "com.test.a", path: "/A2.app"),
            ScannedApp(name: "C", bundleId: "com.test.c", path: "/C.app"),
        ], initialPageCapacity: 28)

        let apps = try storage.persistedLayoutSnapshot().allItems.compactMap(\.app)
        #expect(Set(apps.map(\.bundleId)) == ["com.test.a", "com.test.c"])
        #expect(apps.first(where: { $0.bundleId == "com.test.a" })?.title == "A changed")
    }

    // MARK: - 被过滤应用不出现在网格中

    @Test("被过滤应用不出现在网格中")
    func excludedApps_notInGrid() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        let mockFS = MockFileSystemService()
        let appDirectory = URL(fileURLWithPath: "/Applications")
        let visibleURL = appDirectory.appendingPathComponent("Visible.app")
        let excludedURL = appDirectory.appendingPathComponent("Excluded.app")
        let excludedBundleIds: Set<String> = ["com.test.excluded"]
        let scanner = AppScanner(fileSystemService: mockFS, excludedBundleIds: excludedBundleIds)

        mockFS.directoryContentsMap[appDirectory] = [visibleURL, excludedURL]
        mockFS.bundleInfos[visibleURL] = [
            "CFBundleName": "Visible",
            "CFBundleIdentifier": "com.test.visible",
        ]
        mockFS.bundleInfos[excludedURL] = [
            "CFBundleName": "Excluded",
            "CFBundleIdentifier": "com.test.excluded",
        ]

        let discovery = scanner.scanDirectories([appDirectory])
        #expect(discovery.apps.map(\.bundleId) == ["com.test.visible"])
        #expect(discovery.isComplete)

        _ = try storage.synchronizeInstalledApps(discovery.apps, initialPageCapacity: 35)

        let pages = try storage.fetchAllItems(parentId: nil)
            .filter { $0.type == .page }
        #expect(pages.count == 1)
        let gridItems = try storage.fetchAllItems(parentId: pages[0].id)
        #expect(gridItems.map(\.app?.bundleId) == ["com.test.visible"])
        #expect(gridItems.contains { $0.app?.bundleId == "com.test.excluded" } == false)
    }

    // MARK: - StorageManager 三层嵌套

    @Test("StorageManager — page → group → items 正确解析")
    func storageManager_threeLevelNesting() throws {
        let storage = try StorageManager(dbPath: ":memory:")

        let page = PageItem(id: 0, uuid: UUID().uuidString, type: .page, ordering: 0, parentId: nil, app: nil, group: nil)
        let pageId = try storage.insertItem(page)

        let group = PageItem(id: 0, uuid: UUID().uuidString, type: .group, ordering: 0, parentId: pageId, app: nil, group: GroupInfo(id: 0, title: "Utilities"))
        let groupId = try storage.insertItem(group)

        let app1 = PageItem(id: 0, uuid: UUID().uuidString, type: .app, ordering: 0, parentId: groupId, app: AppInfo(id: 0, title: "Calculator", bundleId: "com.test.calc", path: "/Applications/Calculator.app", storeId: nil, category: nil), group: nil)
        let app2 = PageItem(id: 0, uuid: UUID().uuidString, type: .app, ordering: 1, parentId: groupId, app: AppInfo(id: 0, title: "Terminal", bundleId: "com.test.term", path: "/Applications/Terminal.app", storeId: nil, category: nil), group: nil)
        try storage.insertItem(app1)
        try storage.insertItem(app2)

        let topLevel = try storage.fetchAllItems(parentId: nil)
        #expect(topLevel.count == 1)
        #expect(topLevel[0].type == .page)

        let groupItems = try storage.fetchAllItems(parentId: pageId)
        #expect(groupItems.count == 1)
        #expect(groupItems[0].type == .group)
        #expect(groupItems[0].group?.title == "Utilities")

        let childItems = try storage.fetchAllItems(parentId: groupId)
        #expect(childItems.count == 2)
    }

    @Test("StorageManager — 删除 group 后子项级联删除")
    func storageManager_deleteGroup_cascadeDelete() throws {
        let storage = try StorageManager(dbPath: ":memory:")

        let page = PageItem(id: 0, uuid: UUID().uuidString, type: .page, ordering: 0, parentId: nil, app: nil, group: nil)
        let pageId = try storage.insertItem(page)

        let group = PageItem(id: 0, uuid: UUID().uuidString, type: .group, ordering: 0, parentId: pageId, app: nil, group: GroupInfo(id: 0, title: "Folder"))
        let groupId = try storage.insertItem(group)

        let app1 = PageItem(id: 0, uuid: UUID().uuidString, type: .app, ordering: 0, parentId: groupId, app: AppInfo(id: 0, title: "App1", bundleId: "com.test.app1", path: "/Applications/App1.app", storeId: nil, category: nil), group: nil)
        let app2 = PageItem(id: 0, uuid: UUID().uuidString, type: .app, ordering: 1, parentId: groupId, app: AppInfo(id: 0, title: "App2", bundleId: "com.test.app2", path: "/Applications/App2.app", storeId: nil, category: nil), group: nil)
        try storage.insertItem(app1)
        try storage.insertItem(app2)

        let childrenBefore = try storage.fetchAllItems(parentId: groupId)
        #expect(childrenBefore.count == 2)

        try storage.deleteItem(id: groupId)

        let pageItems = try storage.fetchAllItems(parentId: pageId)
        #expect(pageItems.count == 0, "group 删除后 page 下应为空")

        let childrenAfter = try storage.fetchAllItems(parentId: groupId)
        #expect(childrenAfter.count == 0, "group 删除后子项应被级联删除")
    }

    // MARK: - 原子布局事务重开证明

    @Test("folder layout COMMIT 后完整快照关闭重开不变")
    func folderLayoutCommitSurvivesReopen() throws {
        let directory = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("LaunchPadLayout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("layout.sqlite").path
        var committed: PersistedLayoutSnapshot?

        do {
            let storage = try StorageManager(dbPath: path)
            let pageID = try storage.insertItem(
                TestDataFactory.makePageItem(uuid: "commit-page", type: .page)
            )
            let firstID = try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "commit-first",
                type: .app,
                ordering: 0,
                parentId: pageID,
                app: TestDataFactory.makeAppInfo(
                    bundleId: "com.test.commit.first"
                )
            ))
            let secondID = try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "commit-second",
                type: .app,
                ordering: 1,
                parentId: pageID,
                app: TestDataFactory.makeAppInfo(
                    bundleId: "com.test.commit.second"
                )
            ))
            try storage.apply(
                .createFolder(
                    itemID: secondID,
                    targetItemID: firstID,
                    title: "Committed"
                ),
                pageCapacity: 35
            )
            committed = try storage.persistedLayoutSnapshot()
        }

        let reopened = try StorageManager(dbPath: path)
        let expected = try #require(committed)
        #expect(try reopened.persistedLayoutSnapshot() == expected)
    }

    @Test("真实 folder ROLLBACK failure 关闭连接后重开无部分事务")
    func folderRollbackFailureInvalidatesAndReopenRestoresState() throws {
        let directory = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("LaunchPadRollback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("layout.sqlite").path
        let script = SQLiteFaultScript()
        let storage = try StorageManager(
            dbPath: path,
            schemaSetup: { Schema.setupSchema(db: $0) },
            faultInjector: script.result(for:)
        )
        let pageID = try storage.insertItem(
            TestDataFactory.makePageItem(uuid: "rollback-page", type: .page)
        )
        let sourceID = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "rollback-source",
            type: .app,
            ordering: 0,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(
                bundleId: "com.test.rollback.source"
            )
        ))
        let folderID = try storage.insertItem(TestDataFactory.makePageItem(
            uuid: "rollback-folder",
            type: .group,
            ordering: 1,
            parentId: pageID,
            group: TestDataFactory.makeGroupInfo(title: "Rollback")
        ))
        for index in 0..<2 {
            _ = try storage.insertItem(TestDataFactory.makePageItem(
                uuid: "rollback-child-\(index)",
                type: .app,
                ordering: index,
                parentId: folderID,
                app: TestDataFactory.makeAppInfo(
                    bundleId: "com.test.rollback.child.\(index)"
                )
            ))
        }
        let before = try storage.persistedLayoutSnapshot()
        script.fail(
            .step(.updateLayoutItem),
            onOccurrence: 4,
            code: SQLITE_IOERR
        )
        script.failNext(.rollback, code: SQLITE_IOERR)

        do {
            try storage.apply(
                .addToFolder(itemID: sourceID, folderID: folderID),
                pageCapacity: 35
            )
            Issue.record("expected SQLiteRollbackFailure")
        } catch let error as SQLiteRollbackFailure {
            #expect(error.primaryError as? StorageError == .updateFailed)
            #expect(error.rollbackCode == SQLITE_IOERR)
        }
        #expect(script.invocationCount(for: .step(.updateLayoutItem)) == 4)
        #expect(script.invocationCount(for: .changes(.updateLayoutItem)) == 3)
        #expect(throws: StorageError.storageUnavailable) {
            _ = try storage.fetchAllItems(parentId: nil)
        }

        let reopened = try StorageManager(dbPath: path)
        #expect(try reopened.persistedLayoutSnapshot() == before)
    }

    @Test("同页移动再跨页空白尾部 append 关闭重开保持稠密顺序")
    func crossPageBlankAppendSurvivesFileReopen() throws {
        let directory = try temporaryLayoutDirectory("LaunchPadCrossPage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("layout.sqlite").path
        var firstPageID: Int64 = 0
        var secondPageID: Int64 = 0
        var firstID: Int64 = 0
        var secondID: Int64 = 0
        var thirdID: Int64 = 0
        var fourthID: Int64 = 0

        var storage: StorageManager? = try StorageManager(dbPath: path)
        firstPageID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-0",
            type: .page,
            ordering: 0
        ))
        secondPageID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-1",
            type: .page,
            ordering: 1
        ))
        firstID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-a",
            type: .app,
            ordering: 0,
            parentId: firstPageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.cross.a")
        ))
        secondID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-b",
            type: .app,
            ordering: 1,
            parentId: firstPageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.cross.b")
        ))
        thirdID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-c",
            type: .app,
            ordering: 2,
            parentId: firstPageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.cross.c")
        ))
        fourthID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "cross-page-d",
            type: .app,
            ordering: 0,
            parentId: secondPageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.cross.d")
        ))
        try storage!.apply(
            .moveTopLevel(
                itemID: thirdID,
                placement: .beforeItem(itemID: firstID)
            ),
            pageCapacity: 3
        )
        weak let previousBeforeItemManager = storage
        storage = nil
        #expect(
            previousBeforeItemManager == nil,
            "cross-page before-item manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [firstPageID, secondPageID])
            #expect(snapshot.pages.map(\.ordering) == [0, 1])
            #expect(snapshot.flattenedTopLevelIDs == [
                thirdID, firstID, secondID, fourthID,
            ])
            #expect(snapshot.pageChildren[firstPageID]?.map(\.id) == [
                thirdID, firstID, secondID,
            ])
            #expect(snapshot.pageChildren[firstPageID]?.map(\.ordering) == [0, 1, 2])
            #expect(snapshot.pageChildren[secondPageID]?.map(\.id) == [fourthID])
            #expect(snapshot.pageChildren[secondPageID]?.map(\.ordering) == [0])
        }
        try storage!.apply(
            .moveTopLevel(
                itemID: thirdID,
                placement: .afterItem(itemID: fourthID)
            ),
            pageCapacity: 3
        )
        weak let previousBlankAppendManager = storage
        storage = nil
        #expect(
            previousBlankAppendManager == nil,
            "cross-page blank-append manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [firstPageID, secondPageID])
            #expect(snapshot.pages.map(\.ordering) == [0, 1])
            #expect(snapshot.flattenedTopLevelIDs == [
                firstID, secondID, fourthID, thirdID,
            ])
            #expect(snapshot.pageChildren[firstPageID]?.map(\.id) == [
                firstID, secondID, fourthID,
            ])
            #expect(snapshot.pageChildren[firstPageID]?.map(\.ordering) == [0, 1, 2])
            #expect(snapshot.pageChildren[secondPageID]?.map(\.id) == [thirdID])
            #expect(snapshot.pageChildren[secondPageID]?.map(\.ordering) == [0])
        }
        storage = nil
    }

    @Test("create folder 与 N-child safe delete 分别跨关闭重开持久化")
    func createFolderAndSafeDeleteSurviveFileReopen() throws {
        let directory = try temporaryLayoutDirectory("LaunchPadFolder")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("layout.sqlite").path
        var pageID: Int64 = 0
        var firstID: Int64 = 0
        var secondID: Int64 = 0
        var folderID: Int64 = 0

        var storage: StorageManager? = try StorageManager(dbPath: path)
        pageID = try storage!.insertItem(
            TestDataFactory.makePageItem(uuid: "folder-page", type: .page)
        )
        firstID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "folder-a",
            type: .app,
            ordering: 0,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.folder.a")
        ))
        secondID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "folder-b",
            type: .app,
            ordering: 1,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.folder.b")
        ))
        try storage!.apply(
            .createFolder(
                itemID: secondID,
                targetItemID: firstID,
                title: "Work"
            ),
            pageCapacity: 2
        )
        folderID = try #require(
            storage!.persistedLayoutSnapshot().allItems.first {
                $0.group?.title == "Work"
            }?.id
        )
        weak let previousCreateFolderManager = storage
        storage = nil
        #expect(
            previousCreateFolderManager == nil,
            "create-folder manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [pageID])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [folderID])
            #expect(snapshot.pageChildren[pageID]?.map(\.id) == [folderID])
            #expect(snapshot.pageChildren[pageID]?.map(\.ordering) == [0])
            #expect(snapshot.folderChildren[folderID]?.map(\.id) == [firstID, secondID])
            #expect(snapshot.folderChildren[folderID]?.map(\.ordering) == [0, 1])
        }
        try storage!.apply(.deleteFolder(folderID: folderID), pageCapacity: 2)
        weak let previousNChildDeleteManager = storage
        storage = nil
        #expect(
            previousNChildDeleteManager == nil,
            "N-child safe-delete manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [pageID])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [firstID, secondID])
            #expect(snapshot.pageChildren[pageID]?.map(\.id) == [firstID, secondID])
            #expect(snapshot.pageChildren[pageID]?.map(\.ordering) == [0, 1])
            #expect(snapshot.allItems.contains { $0.id == folderID } == false)
            #expect(snapshot.folderChildren[folderID] == nil)
        }
        storage = nil
    }

    @Test("folder add/reorder/remove 每步关闭重开仍持久化")
    func folderMutationSequenceSurvivesEveryFileReopen() throws {
        let directory = try temporaryLayoutDirectory("LaunchPadFolderSequence")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("layout.sqlite").path
        var pageID: Int64 = 0
        var folderID: Int64 = 0
        var firstID: Int64 = 0
        var secondID: Int64 = 0
        var thirdID: Int64 = 0
        var fourthID: Int64 = 0

        var storage: StorageManager? = try StorageManager(dbPath: path)
        pageID = try storage!.insertItem(
            TestDataFactory.makePageItem(uuid: "sequence-page", type: .page)
        )
        folderID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "sequence-folder",
            type: .group,
            ordering: 0,
            parentId: pageID,
            group: TestDataFactory.makeGroupInfo(title: "Sequence")
        ))
        thirdID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "sequence-c",
            type: .app,
            ordering: 1,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.sequence.c")
        ))
        fourthID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "sequence-d",
            type: .app,
            ordering: 2,
            parentId: pageID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.sequence.d")
        ))
        firstID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "sequence-a",
            type: .app,
            ordering: 0,
            parentId: folderID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.sequence.a")
        ))
        secondID = try storage!.insertItem(TestDataFactory.makePageItem(
            uuid: "sequence-b",
            type: .app,
            ordering: 1,
            parentId: folderID,
            app: TestDataFactory.makeAppInfo(bundleId: "com.test.sequence.b")
        ))
        try storage!.apply(
            .addToFolder(itemID: thirdID, folderID: folderID),
            pageCapacity: 4
        )
        weak let previousAddToFolderManager = storage
        storage = nil
        #expect(
            previousAddToFolderManager == nil,
            "add-to-folder manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [pageID])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [folderID, fourthID])
            #expect(snapshot.pageChildren[pageID]?.map(\.id) == [folderID, fourthID])
            #expect(snapshot.pageChildren[pageID]?.map(\.ordering) == [0, 1])
            #expect(snapshot.folderChildren[folderID]?.map(\.id) == [
                firstID, secondID, thirdID,
            ])
            #expect(snapshot.folderChildren[folderID]?.map(\.ordering) == [0, 1, 2])
        }
        try storage!.apply(
            .reorderFolderItem(
                itemID: thirdID,
                folderID: folderID,
                placement: .beforeItem(itemID: firstID)
            ),
            pageCapacity: 4
        )
        weak let previousReorderFolderManager = storage
        storage = nil
        #expect(
            previousReorderFolderManager == nil,
            "reorder-folder-item manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [pageID])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [folderID, fourthID])
            #expect(snapshot.pageChildren[pageID]?.map(\.id) == [folderID, fourthID])
            #expect(snapshot.pageChildren[pageID]?.map(\.ordering) == [0, 1])
            #expect(snapshot.folderChildren[folderID]?.map(\.id) == [
                thirdID, firstID, secondID,
            ])
            #expect(snapshot.folderChildren[folderID]?.map(\.ordering) == [0, 1, 2])
        }
        try storage!.apply(
            .removeFromFolder(
                itemID: thirdID,
                folderID: folderID,
                placement: .afterItem(itemID: folderID)
            ),
            pageCapacity: 4
        )
        weak let previousRemoveFromFolderManager = storage
        storage = nil
        #expect(
            previousRemoveFromFolderManager == nil,
            "remove-from-folder manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [pageID])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [folderID, thirdID, fourthID])
            #expect(snapshot.pageChildren[pageID]?.map(\.id) == [
                folderID, thirdID, fourthID,
            ])
            #expect(snapshot.pageChildren[pageID]?.map(\.ordering) == [0, 1, 2])
            #expect(snapshot.folderChildren[folderID]?.map(\.id) == [firstID, secondID])
            #expect(snapshot.folderChildren[folderID]?.map(\.ordering) == [0, 1])
        }
        try storage!.apply(
            .removeFromFolder(
                itemID: secondID,
                folderID: folderID,
                placement: .afterItem(itemID: folderID)
            ),
            pageCapacity: 4
        )
        weak let previousAutoDissolveManager = storage
        storage = nil
        #expect(
            previousAutoDissolveManager == nil,
            "auto-dissolve manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [pageID])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [
                firstID, secondID, thirdID, fourthID,
            ])
            #expect(snapshot.pageChildren[pageID]?.map(\.id) == [
                firstID, secondID, thirdID, fourthID,
            ])
            #expect(snapshot.pageChildren[pageID]?.map(\.ordering) == [0, 1, 2, 3])
            #expect(snapshot.allItems.contains { $0.id == folderID } == false)
            #expect(snapshot.folderChildren[folderID] == nil)
        }
        storage = nil
    }

    @Test("zero 和 one child safe delete 关闭重开保持拓扑")
    func safeDeleteZeroAndOneChildSurviveFileReopen() throws {
        do {
            let directory = try temporaryLayoutDirectory("LaunchPadSafeDeleteZero")
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("layout.sqlite").path

            var storage: StorageManager? = try StorageManager(dbPath: path)
            let fixture = try FolderCardinalityFixture(
                storage: storage!,
                prefix: "safe-zero",
                hasChild: false
            )
            try storage!.apply(.deleteFolder(folderID: fixture.folderID), pageCapacity: 3)
            weak let previousZeroChildDeleteManager = storage
            storage = nil
            #expect(
                previousZeroChildDeleteManager == nil,
                "zero-child safe-delete manager must release before reopen"
            )

            storage = try StorageManager(dbPath: path)
            do {
                let snapshot = try storage!.persistedLayoutSnapshot()
                #expect(snapshot.pages.map(\.id) == [fixture.pageID])
                #expect(snapshot.pages.map(\.ordering) == [0])
                #expect(snapshot.flattenedTopLevelIDs == [fixture.leftID, fixture.rightID])
                #expect(snapshot.pageChildren[fixture.pageID]?.map(\.id) == [
                    fixture.leftID, fixture.rightID,
                ])
                #expect(snapshot.pageChildren[fixture.pageID]?.map(\.ordering) == [0, 1])
                #expect(snapshot.allItems.contains { $0.id == fixture.folderID } == false)
                #expect(snapshot.folderChildren[fixture.folderID] == nil)
            }
            storage = nil
        }

        do {
            let directory = try temporaryLayoutDirectory("LaunchPadSafeDeleteOne")
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("layout.sqlite").path

            var storage: StorageManager? = try StorageManager(dbPath: path)
            let fixture = try FolderCardinalityFixture(
                storage: storage!,
                prefix: "safe-one",
                hasChild: true
            )
            let childID = try #require(fixture.childID)
            try storage!.apply(.deleteFolder(folderID: fixture.folderID), pageCapacity: 3)
            weak let previousOneChildDeleteManager = storage
            storage = nil
            #expect(
                previousOneChildDeleteManager == nil,
                "one-child safe-delete manager must release before reopen"
            )

            storage = try StorageManager(dbPath: path)
            do {
                let snapshot = try storage!.persistedLayoutSnapshot()
                #expect(snapshot.pages.map(\.id) == [fixture.pageID])
                #expect(snapshot.pages.map(\.ordering) == [0])
                #expect(snapshot.flattenedTopLevelIDs == [
                    fixture.leftID, childID, fixture.rightID,
                ])
                #expect(snapshot.pageChildren[fixture.pageID]?.map(\.id) == [
                    fixture.leftID, childID, fixture.rightID,
                ])
                #expect(snapshot.pageChildren[fixture.pageID]?.map(\.ordering) == [0, 1, 2])
                #expect(snapshot.allItems.contains { $0.id == fixture.folderID } == false)
                #expect(snapshot.folderChildren[fixture.folderID] == nil)
            }
            storage = nil
        }
    }

    @Test("移出 only child 后 folder 关闭重开已删除")
    func removeOnlyChildSurvivesFileReopen() throws {
        let directory = try temporaryLayoutDirectory("LaunchPadRemoveOnly")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("layout.sqlite").path

        var storage: StorageManager? = try StorageManager(dbPath: path)
        let fixture = try FolderCardinalityFixture(
            storage: storage!,
            prefix: "only",
            hasChild: true
        )
        let childID = try #require(fixture.childID)
        try storage!.apply(
            .removeFromFolder(
                itemID: childID,
                folderID: fixture.folderID,
                placement: .afterItem(itemID: fixture.folderID)
            ),
            pageCapacity: 3
        )
        weak let previousOnlyChildRemovalManager = storage
        storage = nil
        #expect(
            previousOnlyChildRemovalManager == nil,
            "only-child removal manager must release before reopen"
        )

        storage = try StorageManager(dbPath: path)
        do {
            let snapshot = try storage!.persistedLayoutSnapshot()
            #expect(snapshot.pages.map(\.id) == [fixture.pageID])
            #expect(snapshot.pages.map(\.ordering) == [0])
            #expect(snapshot.flattenedTopLevelIDs == [
                fixture.leftID, childID, fixture.rightID,
            ])
            #expect(snapshot.pageChildren[fixture.pageID]?.map(\.id) == [
                fixture.leftID, childID, fixture.rightID,
            ])
            #expect(snapshot.pageChildren[fixture.pageID]?.map(\.ordering) == [0, 1, 2])
            #expect(snapshot.allItems.contains { $0.id == fixture.folderID } == false)
            #expect(snapshot.folderChildren[fixture.folderID] == nil)
        }
        storage = nil
    }
}
