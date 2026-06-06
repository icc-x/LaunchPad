import Foundation
import LaunchPadProtocols

/// 应用扫描器 — 从指定目录扫描已安装的 .app bundle
final class AppScanner: AppScanning {

    private let fileSystemService: FileSystemService
    private let excludedBundleIds: Set<String>

    init(
        fileSystemService: FileSystemService,
        excludedBundleIds: Set<String> = []
    ) {
        self.fileSystemService = fileSystemService
        self.excludedBundleIds = excludedBundleIds
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
                try? writer.insertItem(appItem)
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
        let existingByBundleId = Dictionary(uniqueKeysWithValues: existingApps.compactMap { item -> (String, PageItem)? in
            guard let bundleId = item.app?.bundleId else { return nil }
            return (bundleId, item)
        })
        let scannedByBundleId = Dictionary(uniqueKeysWithValues: scannedApps.map { ($0.bundleId, $0) })

        // INSERT new apps
        for scanned in scannedApps where existingByBundleId[scanned.bundleId] == nil {
            let appInfo = AppInfo(
                id: 0, title: scanned.name, bundleId: scanned.bundleId,
                path: scanned.path, storeId: nil, category: nil
            )
            let item = PageItem(
                id: 0, uuid: UUID().uuidString, type: .app,
                ordering: 0, parentId: lastPageId, app: appInfo, group: nil
            )
            try? writer.insertItem(item)
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
                try? writer.updateItem(updatedItem)
            }
        }

        // DELETE removed apps
        for existing in existingApps {
            guard let bundleId = existing.app?.bundleId else { continue }
            if scannedByBundleId[bundleId] == nil {
                try? writer.deleteItem(id: existing.id)
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
