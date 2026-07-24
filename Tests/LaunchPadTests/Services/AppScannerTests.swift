import Foundation
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("AppScanner discovery branches")
struct AppScannerTests {
    private let firstDirectory = URL(fileURLWithPath: "/Applications")
    private let secondDirectory = URL(fileURLWithPath: "/Users/test/Applications")

    private func app(_ name: String, in directory: URL? = nil) -> URL {
        (directory ?? firstDirectory).appendingPathComponent("\(name).app")
    }

    private func info(_ name: String, _ bundleID: String) -> [String: any Sendable] {
        ["CFBundleName": name, "CFBundleIdentifier": bundleID]
    }

    private func root(
        _ url: URL,
        missingPolicy: AppDiscoveryRoot.MissingPolicy = .required
    ) -> AppDiscoveryRoot {
        AppDiscoveryRoot(url: url, missingPolicy: missingPolicy)
    }

    private struct FirstDirectoryFailsFileSystem: FileSystemService {
        let firstDirectory: URL
        let secondDirectory: URL
        let validApp: URL

        func contentsOfDirectory(at url: URL) throws -> [URL] {
            if url == firstDirectory { throw TestError.generic }
            return url == secondDirectory ? [validApp] : []
        }

        func fileExists(at url: URL) -> Bool { url == validApp }

        func bundleInfo(at bundleURL: URL) throws -> [String: any Sendable] {
            bundleURL == validApp ? [
                "CFBundleName": "Good",
                "CFBundleIdentifier": "com.test.good",
            ] : [:]
        }

        func enumerateAppBundles(
            at url: URL, maxDepth: Int,
            options: FileManager.DirectoryEnumerationOptions
        ) throws -> [URL] {
            try contentsOfDirectory(at: url).filter { $0.pathExtension == "app" }
        }
    }

    @Test("目录读取失败后继续下一目录")
    func directoryErrorContinues() {
        let valid = app("Good", in: secondDirectory)
        let fileSystem = FirstDirectoryFailsFileSystem(
            firstDirectory: firstDirectory,
            secondDirectory: secondDirectory,
            validApp: valid
        )
        let result = AppScanner(fileSystemService: fileSystem, excludedBundleIds: [])
            .scanDirectories([root(firstDirectory), root(secondDirectory)])
        #expect(result.apps.map(\.bundleId) == ["com.test.good"])
        #expect(result.failedRootPaths == [firstDirectory.path])
        #expect(result.failedBundlePaths.isEmpty)
    }

    @Test("只有明确的 UIElement 与 excluded 正常过滤，所有 malformed identity 都报告失败")
    func malformedIdentityFailsWhileExplicitFiltersAreSkipped() {
        let fileSystem = MockFileSystemService()
        let nonApp = firstDirectory.appendingPathComponent("Readme.txt")
        let missingPlist = app("MissingPlist")
        let missingName = app("MissingName")
        let nonStringName = app("NonStringName")
        let emptyName = app("EmptyName")
        let whitespaceName = app("WhitespaceName")
        let agent = app("Agent")
        let missingID = app("MissingID")
        let nonStringID = app("NonStringID")
        let emptyID = app("EmptyID")
        let whitespaceID = app("WhitespaceID")
        let excluded = app("Excluded")
        let valid = app("Valid")
        fileSystem.directoryContentsMap[firstDirectory] = [
            nonApp,
            missingPlist,
            missingName,
            nonStringName,
            emptyName,
            whitespaceName,
            agent,
            missingID,
            nonStringID,
            emptyID,
            whitespaceID,
            excluded,
            valid,
        ]
        fileSystem.unreadableBundleURLs = [missingPlist]
        fileSystem.bundleInfos[missingName] = ["CFBundleIdentifier": "com.test.missing-name"]
        fileSystem.bundleInfos[nonStringName] = [
            "CFBundleName": 42,
            "CFBundleIdentifier": "com.test.non-string-name",
        ]
        fileSystem.bundleInfos[emptyName] = ["CFBundleName": "", "CFBundleIdentifier": "com.test.empty-name"]
        fileSystem.bundleInfos[whitespaceName] = [
            "CFBundleName": " \n\t",
            "CFBundleIdentifier": "com.test.whitespace-name",
        ]
        fileSystem.bundleInfos[agent] = ["CFBundleName": "Agent", "CFBundleIdentifier": "com.test.agent", "LSUIElement": true]
        fileSystem.bundleInfos[missingID] = ["CFBundleName": "Missing ID"]
        fileSystem.bundleInfos[nonStringID] = [
            "CFBundleName": "Non-string ID",
            "CFBundleIdentifier": 42,
        ]
        fileSystem.bundleInfos[emptyID] = [
            "CFBundleName": "Empty ID",
            "CFBundleIdentifier": "",
        ]
        fileSystem.bundleInfos[whitespaceID] = [
            "CFBundleName": "Whitespace ID",
            "CFBundleIdentifier": " \n\t",
        ]
        fileSystem.bundleInfos[excluded] = info("Excluded", "com.test.excluded")
        fileSystem.bundleInfos[valid] = info("Valid", "com.test.valid")
        let result = AppScanner(fileSystemService: fileSystem, excludedBundleIds: ["com.test.excluded"])
            .scanDirectories([root(firstDirectory)])
        #expect(result.apps.map(\.bundleId) == ["com.test.valid"])
        #expect(result.failedRootPaths.isEmpty)
        #expect(result.failedBundlePaths == [
            missingPlist.path,
            missingName.path,
            nonStringName.path,
            emptyName.path,
            whitespaceName.path,
            missingID.path,
            nonStringID.path,
            emptyID.path,
            whitespaceID.path,
        ])
        #expect(!result.isComplete)
    }

    @Test("有效 bundle 与跨目录重复 ID 保持第一个稳定出现")
    func validAndCrossDirectoryDuplicateAreStableFirstWins() {
        let fileSystem = MockFileSystemService()
        let first = app("First")
        let duplicate = app("Duplicate", in: secondDirectory)
        let other = app("Other", in: secondDirectory)
        fileSystem.directoryContentsMap[firstDirectory] = [first]
        fileSystem.directoryContentsMap[secondDirectory] = [duplicate, other]
        fileSystem.bundleInfos[first] = info("First", "com.test.same")
        fileSystem.bundleInfos[duplicate] = info("Duplicate", "com.test.same")
        fileSystem.bundleInfos[other] = info("Other", "com.test.other")
        let result = AppScanner(fileSystemService: fileSystem, excludedBundleIds: [])
            .scanDirectories([root(firstDirectory), root(secondDirectory)])
        #expect(result.apps.map(\.name) == ["First", "Other"])
        #expect(result.apps.map(\.bundleId) == ["com.test.same", "com.test.other"])
        #expect(result.isComplete)
    }

    @Test("只有 optional root 的 fileNoSuchFile 是权威空根")
    func optionalMissingRootIsCompleteButEveryOtherRootErrorIsIncomplete() {
        let fileSystem = MockFileSystemService()
        let optionalMissing = URL(fileURLWithPath: "/Users/test/Applications")
        let optionalPermissionDenied = URL(fileURLWithPath: "/Volumes/Denied")
        let optionalIOFailure = URL(fileURLWithPath: "/Volumes/Broken")
        let requiredMissing = URL(fileURLWithPath: "/Required")
        fileSystem.directoryErrors[optionalMissing] = CocoaError(.fileNoSuchFile)
        fileSystem.directoryErrors[optionalPermissionDenied] = CocoaError(.fileReadNoPermission)
        fileSystem.directoryErrors[optionalIOFailure] = CocoaError(.fileReadUnknown)
        fileSystem.directoryErrors[requiredMissing] = CocoaError(.fileNoSuchFile)

        let optionalMissingResult = AppScanner(
            fileSystemService: fileSystem,
            excludedBundleIds: []
        ).scanDirectories([root(optionalMissing, missingPolicy: .optional)])
        #expect(optionalMissingResult.isComplete)
        #expect(optionalMissingResult.failedRootPaths.isEmpty)

        let incompleteResult = AppScanner(
            fileSystemService: fileSystem,
            excludedBundleIds: []
        ).scanDirectories([
            root(optionalPermissionDenied, missingPolicy: .optional),
            root(optionalIOFailure, missingPolicy: .optional),
            root(requiredMissing),
        ])
        #expect(!incompleteResult.isComplete)
        #expect(incompleteResult.failedRootPaths == [
            optionalPermissionDenied.path,
            optionalIOFailure.path,
            requiredMissing.path,
        ])
    }

    @Test("系统目录枚举的 fileReadNoSuchFile 也把 optional root 视为权威空根")
    func systemFileSystemMissingOptionalRootIsComplete() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchPadMissingRoot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let missingRoot = parent.appendingPathComponent("Applications")
        let fileSystem = SystemFileSystemService()

        do {
            _ = try fileSystem.contentsOfDirectory(at: missingRoot)
            Issue.record("expected the real filesystem adapter to report a missing root")
        } catch let error as CocoaError {
            #expect(error.code == .fileReadNoSuchFile)
        }

        let result = AppScanner(
            fileSystemService: fileSystem,
            excludedBundleIds: []
        ).scanDirectories([root(missingRoot, missingPolicy: .optional)])

        #expect(result.isComplete)
        #expect(result.failedRootPaths.isEmpty)
    }

    @Test("排除清单只解析 hidden string bundle ID")
    func parsesExcludedBundleIDs() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["pages": [["items": [["bundleid": "com.test.hidden", "visible": false], ["bundleid": "com.test.visible", "visible": true]]]]],
            format: .xml,
            options: 0
        )
        #expect(AppScanner.parseExcludedBundleIDs(from: data) == ["com.test.hidden"])
        #expect(AppScanner.parseExcludedBundleIDs(from: nil).isEmpty)
    }
}

// MARK: - P1-8: Recursive scan

@Suite("AppScanner recursive enumeration")
struct AppScannerRecursiveScanTests {
    private let firstDirectory = URL(fileURLWithPath: "/Applications")

    private func appURL(_ name: String, relativeTo base: URL = URL(fileURLWithPath: "/Applications")) -> URL {
        base.appendingPathComponent("\(name).app")
    }

    private func root(_ url: URL, missingPolicy: AppDiscoveryRoot.MissingPolicy = .required) -> AppDiscoveryRoot {
        AppDiscoveryRoot(url: url, missingPolicy: missingPolicy)
    }

    @Test("递归枚举发现嵌套在子目录中的 app")
    func recursiveScan_findsNestedApps() throws {
        let fileSystem = MockFileSystemService()

        // 构造嵌套目录：/Applications/Safari.app + /Applications/Utilities/Terminal.app
        let safariURL = appURL("Safari")
        let utilitiesURL = firstDirectory.appendingPathComponent("Utilities")
        let terminalURL = appURL("Terminal", relativeTo: utilitiesURL)

        fileSystem.enumerateAppBundlesResult = [safariURL, terminalURL]

        // 预设 bundle 信息
        let safariBundle: [String: any Sendable] = [
            "CFBundleIdentifier": "com.apple.Safari",
            "CFBundleName": "Safari",
        ]
        let terminalBundle: [String: any Sendable] = [
            "CFBundleIdentifier": "com.apple.Terminal",
            "CFBundleName": "Terminal",
        ]
        fileSystem.bundleInfos = [safariURL: safariBundle, terminalURL: terminalBundle]

        let scanner = AppScanner(fileSystemService: fileSystem)
        let result = scanner.scanDirectories([root(firstDirectory)])

        // RED: scanDirectories 仍使用 contentsOfDirectory，不会调用 enumerateAppBundles
        // 因此 nested apps 不会被发现
        #expect(result.apps.count == 2)
        let bundleIds = result.apps.map(\.bundleId)
        #expect(bundleIds.contains("com.apple.Safari"))
        #expect(bundleIds.contains("com.apple.Terminal"))
    }

    @Test("递归枚举遵守深度限制")
    func recursiveScan_respectsDepthLimit() throws {
        let fileSystem = MockFileSystemService()

        // 三层目录，maxDepth=1 只到第一层
        let safariURL = appURL("Safari")
        fileSystem.enumerateAppBundlesResult = [safariURL]

        let safariBundle: [String: any Sendable] = [
            "CFBundleIdentifier": "com.apple.Safari",
            "CFBundleName": "Safari",
        ]
        fileSystem.bundleInfos = [safariURL: safariBundle]

        let scanner = AppScanner(fileSystemService: fileSystem)
        let result = scanner.scanDirectories([root(firstDirectory)])

        #expect(result.apps.count == 1)
    }

    @Test("递归枚举跳过隐藏目录")
    func recursiveScan_skipsHiddenDirectories() throws {
        let fileSystem = MockFileSystemService()

        let safariURL = appURL("Safari")
        // 隐藏目录中的 app 不在 enumerateAppBundlesResult 中
        fileSystem.enumerateAppBundlesResult = [safariURL]

        let safariBundle: [String: any Sendable] = [
            "CFBundleIdentifier": "com.apple.Safari",
            "CFBundleName": "Safari",
        ]
        fileSystem.bundleInfos = [safariURL: safariBundle]

        let scanner = AppScanner(fileSystemService: fileSystem)
        let result = scanner.scanDirectories([root(firstDirectory)])

        // 隐藏目录中的 app 未被枚举 → 只返回 Safari
        #expect(result.apps.count == 1)
        #expect(result.apps.first?.bundleId == "com.apple.Safari")
    }
}
