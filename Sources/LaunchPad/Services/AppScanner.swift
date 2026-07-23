import Foundation
import LaunchPadProtocols

/// 应用扫描器 — 从指定目录扫描已安装的 .app bundle
final class AppScanner: AppScanning {

    typealias ExcludedDataProvider = @Sendable () -> Data?

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

    func scanDirectories(_ directories: [URL]) -> [ScannedApp] {
        var apps: [ScannedApp] = []

        for directory in directories {
            let contents: [URL]
            do {
                contents = try fileSystemService.contentsOfDirectory(at: directory)
            } catch {
                continue
            }

            for url in contents {
                guard url.pathExtension == "app" else { continue }
                if let app = scanApp(at: url) {
                    apps.append(app)
                }
            }
        }

        return deduplicated(apps)
    }

    private func scanApp(at url: URL) -> ScannedApp? {
        guard let plist = fileSystemService.bundleInfo(at: url) else { return nil }

        guard let name = plist["CFBundleName"] as? String, !name.isEmpty else { return nil }

        if let isUIElement = plist["LSUIElement"] as? Bool, isUIElement { return nil }

        guard let bundleId = plist["CFBundleIdentifier"] as? String else { return nil }

        if excludedBundleIds.contains(bundleId) { return nil }

        return ScannedApp(name: name, bundleId: bundleId, path: url.path)
    }

    private func deduplicated(_ apps: [ScannedApp]) -> [ScannedApp] {
        var seen = Set<String>()
        return apps.filter { seen.insert($0.bundleId).inserted }
    }
}
