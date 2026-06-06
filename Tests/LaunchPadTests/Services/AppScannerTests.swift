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

    private func makePlist(name: String, bundleId: String, isUIElement: Bool = false) -> [String: Any] {
        var plist: [String: Any] = [
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
}

@Suite("AppScanner 首次启动分页")
struct AppScannerPaginationTests {

    private let appDir = URL(fileURLWithPath: "/Applications")

    private func makePlist(name: String, bundleId: String) -> [String: Any] {
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

    private func makePlist(name: String, bundleId: String) -> [String: Any] {
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
}
