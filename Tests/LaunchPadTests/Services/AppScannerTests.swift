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
            .scanDirectories([firstDirectory, secondDirectory])
        #expect(result.apps.map(\.bundleId) == ["com.test.good"])
        #expect(result.failedRootPaths == [firstDirectory.path])
        #expect(result.failedBundlePaths.isEmpty)
    }

    @Test("非应用、缺 plist、缺或空名称、LSUIElement、缺 ID 与 excluded 全部跳过")
    func allReadRejectionBranchesAreSkipped() {
        let fileSystem = MockFileSystemService()
        let nonApp = firstDirectory.appendingPathComponent("Readme.txt")
        let missingPlist = app("MissingPlist")
        let missingName = app("MissingName")
        let emptyName = app("EmptyName")
        let agent = app("Agent")
        let missingID = app("MissingID")
        let excluded = app("Excluded")
        let valid = app("Valid")
        fileSystem.directoryContentsMap[firstDirectory] = [nonApp, missingPlist, missingName, emptyName, agent, missingID, excluded, valid]
        fileSystem.unreadableBundleURLs = [missingPlist]
        fileSystem.bundleInfos[missingName] = ["CFBundleIdentifier": "com.test.missing-name"]
        fileSystem.bundleInfos[emptyName] = ["CFBundleName": "", "CFBundleIdentifier": "com.test.empty-name"]
        fileSystem.bundleInfos[agent] = ["CFBundleName": "Agent", "CFBundleIdentifier": "com.test.agent", "LSUIElement": true]
        fileSystem.bundleInfos[missingID] = ["CFBundleName": "Missing ID"]
        fileSystem.bundleInfos[excluded] = info("Excluded", "com.test.excluded")
        fileSystem.bundleInfos[valid] = info("Valid", "com.test.valid")
        let result = AppScanner(fileSystemService: fileSystem, excludedBundleIds: ["com.test.excluded"])
            .scanDirectories([firstDirectory])
        #expect(result.apps.map(\.bundleId) == ["com.test.valid"])
        #expect(result.failedRootPaths.isEmpty)
        #expect(result.failedBundlePaths == [missingPlist.path])
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
            .scanDirectories([firstDirectory, secondDirectory])
        #expect(result.apps.map(\.name) == ["First", "Other"])
        #expect(result.apps.map(\.bundleId) == ["com.test.same", "com.test.other"])
        #expect(result.isComplete)
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
