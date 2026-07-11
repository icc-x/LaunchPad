import Testing
import Foundation
@testable import LaunchPad
import LaunchPadProtocols

@Suite("AppScanner 协议扫描")
struct AppScannerTests {

    private let appDir = URL(fileURLWithPath: "/Applications")
    private let userAppDir = URL(fileURLWithPath: "/Users/test/Applications")

    private func appURL(_ name: String) -> URL {
        appDir.appendingPathComponent("\(name).app")
    }

    private func makePlist(name: String, bundleId: String, isUIElement: Bool = false) -> [String: any Sendable] {
        var plist: [String: any Sendable] = [
            "CFBundleName": name,
            "CFBundleIdentifier": bundleId,
        ]
        if isUIElement { plist["LSUIElement"] = true }
        return plist
    }

    @Test("扫描返回 .app bundle 列表")
    func scan_returnsAppBundles() {
        let fs = MockFileSystemService()
        let safariURL = appURL("Safari")
        let notesURL = appURL("Notes")

        fs.directoryContentsMap[appDir] = [safariURL, notesURL]
        fs.existingFiles = [safariURL, notesURL]
        fs.bundleInfos[safariURL] = makePlist(name: "Safari", bundleId: "com.apple.Safari")
        fs.bundleInfos[notesURL] = makePlist(name: "Notes", bundleId: "com.apple.Notes")

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir])

        #expect(result.count == 2)
        #expect(result.contains(where: { $0.bundleId == "com.apple.Safari" }))
    }

    @Test("过滤无 CFBundleName 的应用")
    func scan_filtersNoBundleName() {
        let fs = MockFileSystemService()
        let goodURL = appURL("Safari")
        let badURL = appURL("NoName")

        fs.directoryContentsMap[appDir] = [goodURL, badURL]
        fs.existingFiles = [goodURL, badURL]
        fs.bundleInfos[goodURL] = makePlist(name: "Safari", bundleId: "com.apple.Safari")
        fs.bundleInfos[badURL] = ["CFBundleIdentifier": "com.test.noname"]

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir])

        #expect(result.count == 1)
        #expect(result.first?.bundleId == "com.apple.Safari")
    }

    @Test("过滤 LSUIElement=YES 的后台应用")
    func scan_filtersUIElement() {
        let fs = MockFileSystemService()
        let safariURL = appURL("Safari")
        let daemonURL = appURL("BackgroundDaemon")

        fs.directoryContentsMap[appDir] = [safariURL, daemonURL]
        fs.existingFiles = [safariURL, daemonURL]
        fs.bundleInfos[safariURL] = makePlist(name: "Safari", bundleId: "com.apple.Safari")
        fs.bundleInfos[daemonURL] = makePlist(name: "BackgroundDaemon", bundleId: "com.test.daemon", isUIElement: true)

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir])

        #expect(result.count == 1)
        #expect(result.first?.bundleId == "com.apple.Safari")
    }

    @Test("过滤排除列表中的 bundleId")
    func scan_filtersExcludedBundleIds() {
        let fs = MockFileSystemService()
        let safariURL = appURL("Safari")
        let installerURL = appURL("Installer")

        fs.directoryContentsMap[appDir] = [safariURL, installerURL]
        fs.existingFiles = [safariURL, installerURL]
        fs.bundleInfos[safariURL] = makePlist(name: "Safari", bundleId: "com.apple.Safari")
        fs.bundleInfos[installerURL] = makePlist(name: "Installer", bundleId: "com.apple.Installer")

        let scanner = AppScanner(fileSystemService: fs, excludedBundleIds: ["com.apple.Installer"])
        let result = scanner.scanDirectories([appDir])

        #expect(result.count == 1)
        #expect(result.first?.bundleId == "com.apple.Safari")
    }

    @Test("扫描多个目录合并结果")
    func scan_multipleDirectories() {
        let fs = MockFileSystemService()
        let safariURL = appURL("Safari")
        let myAppURL = userAppDir.appendingPathComponent("MyApp.app")

        fs.directoryContentsMap[appDir] = [safariURL]
        fs.directoryContentsMap[userAppDir] = [myAppURL]
        fs.existingFiles = [safariURL, myAppURL]
        fs.bundleInfos[safariURL] = makePlist(name: "Safari", bundleId: "com.apple.Safari")
        fs.bundleInfos[myAppURL] = makePlist(name: "MyApp", bundleId: "com.test.myapp")

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir, userAppDir])

        #expect(result.count == 2)
    }

    @Test("Info.plist 读取失败的应用被跳过")
    func scan_skipsUnreadablePlist() {
        let fs = MockFileSystemService()
        let goodURL = appURL("Safari")
        let brokenURL = appURL("Broken")

        fs.directoryContentsMap[appDir] = [goodURL, brokenURL]
        fs.existingFiles = [goodURL, brokenURL]
        fs.bundleInfos[goodURL] = makePlist(name: "Safari", bundleId: "com.apple.Safari")

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir])

        #expect(result.count == 1)
        #expect(result.first?.bundleId == "com.apple.Safari")
    }

    @Test("目录读取失败时跳过该目录")
    func scan_directoryReadError_continues() {
        let fs = MockFileSystemService()
        fs.shouldThrowOnContentsOfDirectory = true

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir])

        #expect(result.isEmpty)
    }

    @Test("从系统 LaunchPadLayout.plist 读取排除列表")
    func scan_loadsSystemExcludedBundleIds() {
        let dir = NSHomeDirectory() + "/Library/Application Support/Dock"
        let plistPath = dir + "/LaunchPadLayout.plist"
        let fm = FileManager.default

        // 备份已有文件
        let backupURL = URL(fileURLWithPath: plistPath + ".backup_test")
        var hadOriginal = false
        if fm.fileExists(atPath: plistPath) {
            try? fm.copyItem(atPath: plistPath, toPath: backupURL.path)
            try? fm.removeItem(atPath: plistPath)
            hadOriginal = true
        }
        defer {
            // 清理测试文件
            try? fm.removeItem(atPath: plistPath)
            if hadOriginal {
                try? fm.moveItem(atPath: backupURL.path, toPath: plistPath)
            }
        }

        // 创建目录和测试 plist
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "pages": [
                ["items": [
                    ["bundleid": "com.apple.hidden1", "visible": false],
                    ["bundleid": "com.apple.visible1", "visible": true],
                ]],
                ["items": [
                    ["bundleid": "com.apple.hidden2", "visible": false],
                ]],
            ]
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try! data.write(to: URL(fileURLWithPath: plistPath))

        let fs = MockFileSystemService()
        let appURL = self.appURL("HiddenApp")
        fs.directoryContentsMap[appDir] = [appURL]
        fs.existingFiles = [appURL]
        fs.bundleInfos[appURL] = makePlist(name: "HiddenApp", bundleId: "com.apple.hidden1")

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir])

        // com.apple.hidden1 应被排除
        #expect(result.isEmpty)
    }
}

@Suite("AppScanner 首次启动分页")
struct AppScannerPaginationTests {

    private let appDir = URL(fileURLWithPath: "/Applications")

    private func makePlist(name: String, bundleId: String) -> [String: any Sendable] {
        ["CFBundleName": name, "CFBundleIdentifier": bundleId]
    }

    private func appURL(_ name: String) -> URL {
        appDir.appendingPathComponent("\(name).app")
    }

    private func makeMockFS(count: Int) -> MockFileSystemService {
        let fs = MockFileSystemService()
        var urls: [URL] = []
        for i in 0..<count {
            let url = appURL("App\(String(format: "%03d", i))")
            urls.append(url)
            fs.existingFiles.insert(url)
            fs.bundleInfos[url] = makePlist(
                name: "App\(String(format: "%03d", i))",
                bundleId: "com.test.app\(i)"
            )
        }
        fs.directoryContentsMap[appDir] = urls
        return fs
    }

    @Test("100 个应用 + 每页 35 个 → 3 页")
    func paginate_100apps_3pages() {
        let fs = makeMockFS(count: 100)
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: fs)

        let scanned = scanner.scanDirectories([appDir])
        scanner.firstLaunchPaginate(scannedApps: scanned, maxPerPage: 35, writer: writer)

        let pages = writer.insertedItems.filter { $0.type == .page }
        let apps = writer.insertedItems.filter { $0.type == .app }

        #expect(pages.count == 3)
        #expect(apps.count == 100)
    }

    @Test("应用按字母顺序排列且跨页连续")
    func paginate_alphabeticalOrder_acrossPages() {
        let fs = MockFileSystemService()
        let names = ["Zebra", "Alpha", "Middle", "Beta", "Gamma"]
        var urls: [URL] = []
        for name in names {
            let url = appURL(name)
            urls.append(url)
            fs.existingFiles.insert(url)
            fs.bundleInfos[url] = makePlist(name: name, bundleId: "com.test.\(name.lowercased())")
        }
        fs.directoryContentsMap[appDir] = urls

        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: fs)

        let scanned = scanner.scanDirectories([appDir])
        scanner.firstLaunchPaginate(scannedApps: scanned, maxPerPage: 3, writer: writer)

        let apps = writer.insertedItems.filter { $0.type == .app }

        #expect(apps[0].app?.title == "Alpha")
        #expect(apps[1].app?.title == "Beta")
        #expect(apps[2].app?.title == "Gamma")
        #expect(apps[3].app?.title == "Middle")
    }
}

@Suite("AppScanner 增量同步")
struct AppScannerSyncTests {

    private let appDir = URL(fileURLWithPath: "/Applications")

    private func makePlist(name: String, bundleId: String) -> [String: any Sendable] {
        ["CFBundleName": name, "CFBundleIdentifier": bundleId]
    }

    private func appURL(_ name: String) -> URL {
        appDir.appendingPathComponent("\(name).app")
    }

    @Test("新应用被插入")
    func sync_insertsNewApps() {
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let scanned = [
            ScannedApp(name: "NewApp", bundleId: "com.new.app", path: "/Applications/NewApp.app")
        ]

        scanner.incrementalSync(scannedApps: scanned, existingItems: [], lastPageId: nil, writer: writer)

        #expect(writer.insertedItems.count == 1)
        #expect(writer.insertedItems.first?.app?.bundleId == "com.new.app")
    }

    @Test("已删除应用被删除")
    func sync_deletesRemovedApps() {
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let existing = TestDataFactory.makePageItem(
            type: .app,
            app: TestDataFactory.makeAppInfo(title: "OldApp", bundleId: "com.old.app")
        )

        scanner.incrementalSync(scannedApps: [], existingItems: [existing], lastPageId: nil, writer: writer)

        #expect(writer.deletedIds.count == 1)
        #expect(writer.deletedIds.first == existing.id)
    }

    @Test("已变更应用被更新")
    func sync_updatesChangedApps() {
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let existing = TestDataFactory.makePageItem(
            type: .app,
            app: TestDataFactory.makeAppInfo(title: "OldName", bundleId: "com.changed.app", path: "/old/path")
        )
        let scanned = [
            ScannedApp(name: "NewName", bundleId: "com.changed.app", path: "/new/path")
        ]

        scanner.incrementalSync(scannedApps: scanned, existingItems: [existing], lastPageId: nil, writer: writer)

        #expect(writer.updatedItems.count == 1)
        #expect(writer.updatedItems.first?.app?.title == "NewName")
    }

    @Test("未变更应用不操作")
    func sync_noChange_noop() {
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let existing = TestDataFactory.makePageItem(
            type: .app,
            app: TestDataFactory.makeAppInfo(title: "SameApp", bundleId: "com.same.app", path: "/same/path")
        )
        let scanned = [
            ScannedApp(name: "SameApp", bundleId: "com.same.app", path: "/same/path")
        ]

        scanner.incrementalSync(scannedApps: scanned, existingItems: [existing], lastPageId: nil, writer: writer)

        #expect(writer.insertedItems.isEmpty)
        #expect(writer.updatedItems.isEmpty)
        #expect(writer.deletedIds.isEmpty)
    }

    @Test("插入失败时记录日志不崩溃")
    func sync_insertError_logsAndContinues() {
        let writer = MockItemWriter()
        writer.insertError = TestError.generic
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let scanned = [
            ScannedApp(name: "NewApp", bundleId: "com.new.app", path: "/Applications/NewApp.app")
        ]

        scanner.incrementalSync(scannedApps: scanned, existingItems: [], lastPageId: nil, writer: writer)

        #expect(writer.insertedItems.isEmpty)
    }

    @Test("更新失败时记录日志不崩溃")
    func sync_updateError_logsAndContinues() {
        let writer = MockItemWriter()
        writer.updateError = TestError.generic
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let existing = TestDataFactory.makePageItem(
            type: .app,
            app: TestDataFactory.makeAppInfo(title: "OldName", bundleId: "com.changed.app", path: "/old/path")
        )
        let scanned = [
            ScannedApp(name: "NewName", bundleId: "com.changed.app", path: "/new/path")
        ]

        scanner.incrementalSync(scannedApps: scanned, existingItems: [existing], lastPageId: nil, writer: writer)

        #expect(writer.updatedItems.isEmpty)
    }

    @Test("删除失败时记录日志不崩溃")
    func sync_deleteError_logsAndContinues() {
        let writer = MockItemWriter()
        writer.deleteError = TestError.generic
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let existing = TestDataFactory.makePageItem(
            type: .app,
            app: TestDataFactory.makeAppInfo(title: "OldApp", bundleId: "com.old.app")
        )

        scanner.incrementalSync(scannedApps: [], existingItems: [existing], lastPageId: nil, writer: writer)

        #expect(writer.deletedIds.isEmpty)
    }

    @Test("existingItems 含重复 bundleId 时去重保留首个")
    func sync_duplicateBundleId_deduplicates() {
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let app1 = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(title: "App1", bundleId: "com.dup.app", path: "/Applications/App1.app"))
        let app2 = TestDataFactory.makePageItem(id: 20, type: .app, ordering: 1,
            app: TestDataFactory.makeAppInfo(title: "App2", bundleId: "com.dup.app", path: "/Applications/App1.app"))
        let scanned = [
            ScannedApp(name: "App1", bundleId: "com.dup.app", path: "/Applications/App1.app")
        ]

        scanner.incrementalSync(scannedApps: scanned, existingItems: [app1, app2], lastPageId: nil, writer: writer)

        // 重复 bundleId 去重后保留首个；app2 title 不同会触发 update（正常行为）
        #expect(writer.insertedItems.isEmpty)
        #expect(writer.deletedIds.isEmpty)
    }

    // MARK: - 分支覆盖

    @Test("firstLaunchPaginate: insertItem 抛错时 continue（覆盖 L88 try? fallback）")
    func firstLaunchPaginate_insertError_continues() {
        let writer = MockItemWriter()
        writer.insertError = TestError.generic
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let scanned = [
            ScannedApp(name: "App1", bundleId: "com.test.app1", path: "/Applications/App1.app")
        ]

        // 不会崩溃，写入失败时跳过该 page
        scanner.firstLaunchPaginate(scannedApps: scanned, maxPerPage: 10, writer: writer)
        #expect(writer.insertedItems.isEmpty)
    }

    @Test("incrementalSync: existingItems 含 bundleId 为 nil 的 app 时跳过（覆盖 L126 guard else）")
    func incrementalSync_existingAppMissingBundleId_skipped() {
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        // app.bundleId 为空字符串 ""，guard let bundleId = item.app?.bundleId 应成功（空字符串非 nil）
        // 需要 app 本身为 nil 才能触发 nil 分支
        let appNoBundle = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0, app: nil)
        let scanned: [ScannedApp] = []
        scanner.incrementalSync(scannedApps: scanned, existingItems: [appNoBundle], lastPageId: nil, writer: writer)
        // app.bundleId 为 nil → 跳过，不会触发 delete
        #expect(writer.deletedIds.isEmpty)
    }

    @Test("incrementalSync: delete loop 中 existing app 缺 bundleId 时跳过（覆盖 L173 guard else）")
    func incrementalSync_deleteLoopAppMissingBundleId_skipped() {
        let writer = MockItemWriter()
        let scanner = AppScanner(fileSystemService: MockFileSystemService())
        let appNoBundle = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0, app: nil)
        // scannedApps 为空 → 走 DELETE 分支 → L173 guard let bundleId else { continue }
        scanner.incrementalSync(scannedApps: [], existingItems: [appNoBundle], lastPageId: nil, writer: writer)
        #expect(writer.deletedIds.isEmpty)
    }

    @Test("scanApp: Info.plist 缺 CFBundleIdentifier 时跳过（覆盖 L191 guard else）")
    func scan_plistMissingBundleId_skipped() {
        let fs = MockFileSystemService()
        let appURL = appURL("NoBundleId")
        fs.directoryContentsMap[appDir] = [appURL]
        fs.existingFiles = [appURL]
        // plist 有 CFBundleName 但缺 CFBundleIdentifier
        fs.bundleInfos[appURL] = ["CFBundleName": "NoBundleId"]

        let scanner = AppScanner(fileSystemService: fs)
        let result = scanner.scanDirectories([appDir])

        // 没有 CFBundleIdentifier 的应用被跳过
        #expect(result.isEmpty)
    }
}
