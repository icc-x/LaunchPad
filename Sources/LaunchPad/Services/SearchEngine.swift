import Foundation
import LaunchPadProtocols

/// 无状态搜索引擎，提供基于评分的应用匹配与排序。
public struct SearchEngine: Sendable {

    public init() {}

    /// 对单个 PageItem 与查询字符串进行匹配评分
    public func match(item: PageItem, query: String) -> Int {
        // 显式分支替代链式 ??，避免 LLVM 误报
        // AppInfo.title/GroupInfo.title 都是非 optional，nil 仅来自 item.app/item.group
        let title: String
        if let app = item.app {
            title = app.title.lowercased()
        } else if let group = item.group {
            title = group.title.lowercased()
        } else {
            title = ""
        }
        let q = query.lowercased()

        guard !q.isEmpty else { return 100 }

        if title.hasPrefix(q) { return 100 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 75 }
        if title.contains(q) { return 50 }
        if item.app?.bundleId.lowercased().contains(q) == true { return 25 }

        return 0
    }

    /// 搜索并排序所有 items（无缓存）
    public func search(items: [PageItem], query: String) -> [PageItem] {
        guard !query.isEmpty else { return items }

        let scored = items.compactMap { item -> (item: PageItem, score: Int, title: String)? in
            let score = match(item: item, query: query)
            guard score > 0 else { return nil }
            // 显式分支：item.app 优先，否则取 item.group.title，否则空串
            // AppInfo.title/GroupInfo.title 都是非 optional。
            let title: String
            if let app = item.app {
                title = app.title
            } else if let group = item.group {
                title = group.title
            } else {
                title = ""
            }
            return (item, score, title)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map(\.item)
    }

}
