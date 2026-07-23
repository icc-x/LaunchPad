import Foundation
import LaunchPadProtocols

/// 应用扫描器 — 从指定目录扫描已安装的 .app bundle
final class AppScanner: AppScanning {

    typealias ExcludedDataProvider = @Sendable () -> Data?

    private enum BundleMetadataError: Error {
        case invalidName
        case invalidBundleIdentifier
    }

    private let fileSystemService: FileSystemService
    private let excludedBundleIds: Set<String>

    init(
        fileSystemService: FileSystemService,
        excludedBundleIds: Set<String>? = nil,
        excludedDataProvider: @escaping ExcludedDataProvider = AppScanner.systemExcludedData
    ) {
        self.fileSystemService = fileSystemService
        self.excludedBundleIds = excludedBundleIds
            ?? Self.parseExcludedBundleIDs(from: excludedDataProvider())
    }

    static func systemExcludedData() -> Data? {
        let path = NSHomeDirectory()
            + "/Library/Application Support/Dock/LaunchPadLayout.plist"
        return FileManager.default.contents(atPath: path)
    }

    static func parseExcludedBundleIDs(from data: Data?) -> Set<String> {
        guard let data,
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ),
              let root = propertyList as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else {
            return []
        }

        var result = Set<String>()
        for page in pages {
            guard let items = page["items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                guard let id = item["bundleid"] as? String,
                      let visible = item["visible"] as? Bool,
                      visible == false else {
                    continue
                }
                result.insert(id)
            }
        }
        return result
    }

    func isExcluded(bundleId: String) -> Bool {
        return excludedBundleIds.contains(bundleId)
    }

    func scanDirectories(_ roots: [AppDiscoveryRoot]) -> AppDiscoveryResult {
        var apps: [ScannedApp] = []
        var failedRootPaths: [String] = []
        var failedBundlePaths: [String] = []

        for root in roots {
            let contents: [URL]
            do {
                contents = try fileSystemService.contentsOfDirectory(at: root.url)
            } catch let error as CocoaError
                where root.missingPolicy == .optional && Self.isMissingRoot(error) {
                continue
            } catch {
                failedRootPaths.append(root.url.path)
                continue
            }

            for url in contents {
                guard url.pathExtension == "app" else { continue }
                do {
                    if let app = try scanApp(at: url) {
                        apps.append(app)
                    }
                } catch {
                    failedBundlePaths.append(url.path)
                }
            }
        }

        return AppDiscoveryResult(
            apps: deduplicated(apps),
            failedRootPaths: failedRootPaths,
            failedBundlePaths: failedBundlePaths
        )
    }

    private static func isMissingRoot(_ error: CocoaError) -> Bool {
        error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
    }

    private func scanApp(at url: URL) throws -> ScannedApp? {
        let plist = try fileSystemService.bundleInfo(at: url)

        if let isUIElement = plist["LSUIElement"] as? Bool, isUIElement { return nil }

        guard let bundleId = plist["CFBundleIdentifier"] as? String,
              !bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BundleMetadataError.invalidBundleIdentifier
        }

        if excludedBundleIds.contains(bundleId) { return nil }

        guard let name = plist["CFBundleName"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BundleMetadataError.invalidName
        }

        return ScannedApp(name: name, bundleId: bundleId, path: url.path)
    }

    private func deduplicated(_ apps: [ScannedApp]) -> [ScannedApp] {
        var seen = Set<String>()
        return apps.filter { seen.insert($0.bundleId).inserted }
    }
}
