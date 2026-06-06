import Foundation
import LaunchPadProtocols

/// 搜索引擎 — 提供基于评分的应用匹配算法
public struct SearchEngine {

    public init() {}

    /// 对单个 PageItem 与查询字符串进行匹配评分
    ///
    /// 评分规则:
    /// - 100: 标题前缀匹配（最高优先级）
    /// -  75: 标题中某个单词的前缀匹配
    /// -  50: 标题子串匹配（非前缀）
    /// -  25: bundleId 子串匹配
    /// -   0: 无匹配
    public func match(item: PageItem, query: String) -> Int {
        let title = item.app?.title.lowercased() ?? item.group?.title.lowercased() ?? ""
        let q = query.lowercased()

        guard !q.isEmpty else { return 100 }

        // 1. 词首前缀匹配（score=100）
        if title.hasPrefix(q) { return 100 }

        // 2. 单词前缀匹配（score=75）
        if title.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 75 }

        // 3. 子串匹配（score=50）
        if title.contains(q) { return 50 }

        // 4. bundleId 子串匹配（score=25）
        if item.app?.bundleId.lowercased().contains(q) == true { return 25 }

        // 5. 无匹配
        return 0
    }

    /// 搜索并排序所有 items
    public func search(items: [PageItem], query: String) -> [PageItem] {
        guard !query.isEmpty else { return items }

        let scored = items.compactMap { item -> (PageItem, Int)? in
            let score = match(item: item, query: query)
            return score > 0 ? (item, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                let lhsTitle = lhs.0.app?.title ?? lhs.0.group?.title ?? ""
                let rhsTitle = rhs.0.app?.title ?? rhs.0.group?.title ?? ""
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            .map { $0.0 }
    }
}
