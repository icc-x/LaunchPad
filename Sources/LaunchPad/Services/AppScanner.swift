import Foundation
import LaunchPadProtocols

/// 应用扫描器 — 从指定目录扫描已安装的 .app bundle
final class AppScanner: AppScanning {

    private let fileSystemService: FileSystemService
    private let excludedBundleIds: Set<String>

    init(
        fileSystemService: FileSystemService,
        excludedBundleIds: Set<String>? = nil
    ) {
        self.fileSystemService = fileSystemService
        // 如果未提供排除列表，从系统 LaunchPadLayout.plist 读取
        self.excludedBundleIds = excludedBundleIds ?? Self.loadSystemExcludedBundleIds()
    }

    /// 从系统 LaunchPadLayout.plist 读取排除的 bundle ID 列表
    private static func loadSystemExcludedBundleIds() -> Set<String> {
        let plistPath = NSHomeDirectory() + "/Library/Application Support/Dock/LaunchPadLayout.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let pages = plist["pages"] as? [[String: Any]] else {
            return []
        }

        var excluded = Set<String>()
        for page in pages {
            if let items = page["items"] as? [[String: Any]] {
                for item in items {
                    if let bundleId = item["bundleid"] as? String,
                       let visible = item["visible"] as? Bool, !visible {
                        excluded.insert(bundleId)
                    }
                }
            }
        }
        return excluded
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

        return apps
    }

    /// 首次启动分页 — 按字母序排列，分页写入数据库
    func firstLaunchPaginate(
        scannedApps: [ScannedApp],
        maxPerPage: Int,
        writer: ItemWriting
    ) {
        let sorted = scannedApps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let pageCount = Int(ceil(Double(sorted.count) / Double(maxPerPage)))

        for pageIndex in 0..<pageCount {
            let pageItem = PageItem(
                id: Int64(pageIndex + 1),
                uuid: UUID().uuidString,
                type: .page,
                ordering: pageIndex,
                parentId: nil,
                app: nil,
                group: nil
            )
            guard let pageId = try? writer.insertItem(pageItem) else { continue }

            let start = pageIndex * maxPerPage
            let end = min(start + maxPerPage, sorted.count)

            for (index, scanned) in sorted[start..<end].enumerated() {
                let appInfo = AppInfo(
                    id: 0,
                    title: scanned.name,
                    bundleId: scanned.bundleId,
                    path: scanned.path,
                    storeId: nil,
                    category: nil
                )
                let appItem = PageItem(
                    id: 0,
                    uuid: UUID().uuidString,
                    type: .app,
                    ordering: index,
                    parentId: pageId,
                    app: appInfo,
                    group: nil
                )
                _ = try? writer.insertItem(appItem)
            }
        }
    }

    /// 增量同步 — 对比扫描结果与现有数据库
    func incrementalSync(
        scannedApps: [ScannedApp],
        existingItems: [PageItem],
        lastPageId: Int64?,
        writer: ItemWriting
    ) {
        let existingApps = existingItems.filter { $0.type == .app }
        let existingByBundleId = Dictionary(
            existingApps.compactMap { item -> (String, PageItem)? in
                guard let bundleId = item.app?.bundleId else { return nil }
                return (bundleId, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let scannedByBundleId = Dictionary(uniqueKeysWithValues: scannedApps.map { ($0.bundleId, $0) })

        // INSERT new apps (with incrementing ordering)
        var newAppOrdering = existingApps.filter { $0.parentId == lastPageId }.count
        for scanned in scannedApps where existingByBundleId[scanned.bundleId] == nil {
            let appInfo = AppInfo(
                id: 0, title: scanned.name, bundleId: scanned.bundleId,
                path: scanned.path, storeId: nil, category: nil
            )
            let item = PageItem(
                id: 0, uuid: UUID().uuidString, type: .app,
                ordering: newAppOrdering, parentId: lastPageId, app: appInfo, group: nil
            )
            do {
                _ = try writer.insertItem(item)
                newAppOrdering += 1
            } catch {
                NSLog("[AppScanner] Failed to insert app \(scanned.bundleId): \(error)")
            }
        }

        // UPDATE changed apps
        for existing in existingApps {
            guard let bundleId = existing.app?.bundleId,
                  let scanned = scannedByBundleId[bundleId] else { continue }
            if existing.app?.title != scanned.name || existing.app?.path != scanned.path {
                let updated = AppInfo(
                    id: existing.app!.id, title: scanned.name, bundleId: bundleId,
                    path: scanned.path, storeId: existing.app?.storeId, category: existing.app?.category
                )
                var updatedItem = existing
                updatedItem.app = updated
                do {
                    try writer.updateItem(updatedItem)
                } catch {
                    NSLog("[AppScanner] Failed to update app \(bundleId): \(error)")
                }
            }
        }

        // DELETE removed apps
        for existing in existingApps {
            guard let bundleId = existing.app?.bundleId else { continue }
            if scannedByBundleId[bundleId] == nil {
                do {
                    try writer.deleteItem(id: existing.id)
                } catch {
                    NSLog("[AppScanner] Failed to delete app \(bundleId): \(error)")
                }
            }
        }
    }

    private func scanApp(at url: URL) -> ScannedApp? {
        guard let plist = fileSystemService.bundleInfo(at: url) else { return nil }

        guard let name = plist["CFBundleName"] as? String, !name.isEmpty else { return nil }

        if let isUIElement = plist["LSUIElement"] as? Bool, isUIElement { return nil }

        guard let bundleId = plist["CFBundleIdentifier"] as? String else { return nil }

        if excludedBundleIds.contains(bundleId) { return nil }

        return ScannedApp(name: name, bundleId: bundleId, path: url.path)
    }
}
