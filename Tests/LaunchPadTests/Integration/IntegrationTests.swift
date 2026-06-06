import Testing
import Foundation
@testable import LaunchPad
import LaunchPadProtocols

@Suite("Integration Tests — 跨模块集成验证")
struct IntegrationTests {

    // MARK: - 首次启动流程

    @Test("首次启动 — 空扫描后分页查询返回正确数量")
    func firstLaunch_emptyScan_pagination_correctItemCount() throws {
        let mockFS = MockFileSystemService()
        mockFS.directoryContents = []
        let scanner = AppScanner(fileSystemService: mockFS, excludedBundleIds: [])
        let storage = try StorageManager(dbPath: ":memory:")

        let scanned: [ScannedApp] = []
        scanner.firstLaunchPaginate(scannedApps: scanned, maxPerPage: 20, writer: storage)

        let allItems = try storage.fetchAllItems(parentId: nil)
        #expect(allItems.count == 0, "空扫描后存储应为空")
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

        let scanned = scanner.scanDirectories([appDir])
        #expect(scanned.count == 2)

        scanner.firstLaunchPaginate(scannedApps: scanned, maxPerPage: 35, writer: storage)

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
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        #expect(params.columns == 7)
        #expect(params.rows == 5)
        #expect(params.itemsPerPage == 35)
    }
}
