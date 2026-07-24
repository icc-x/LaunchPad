import Foundation
import LaunchPadProtocols

/// LRU 缓存 — 基于双向链表 + 字典实现，线程安全
final class LRUCache<Key: Hashable, Value>: @unchecked Sendable {
    private let capacity: Int
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let lock = NSLock()

    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let node = cache[key] else { return nil }
        moveToHeadLocked(node)
        return node.value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }
        if let node = cache[key] {
            node.value = value
            moveToHeadLocked(node)
            return
        }

        let node = Node(key: key, value: value)
        cache[key] = node
        addToHeadLocked(node)

        if cache.count > capacity {
            evictOldestLocked()
        }
    }

    private func moveToHeadLocked(_ node: Node) {
        guard node !== head else { return }
        removeNodeLocked(node)
        addToHeadLocked(node)
    }

    private func addToHeadLocked(_ node: Node) {
        node.next = head
        node.prev = nil
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func removeNodeLocked(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if node === head { head = node.next }
        if node === tail { tail = node.prev }
        node.prev = nil
        node.next = nil
    }

    private func evictOldestLocked() {
        guard let oldTail = tail else { return }
        cache.removeValue(forKey: oldTail.key)
        removeNodeLocked(oldTail)
    }
}

/// 线程安全的匹配调用计数器（测试辅助）
final class MatchCounter: @unchecked Sendable {
    private var _count: Int = 0
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}

/// 搜索引擎 — 提供基于评分的应用匹配与搜索，支持结果缓存
public struct SearchEngine: @unchecked Sendable {

    private let cache: LRUCache<String, [PageItem]>
    private let matchCounter: MatchCounter?
    private var generation: UInt64 = 0

    public init(cacheSize: Int = 50) {
        self.cache = LRUCache(capacity: cacheSize)
        self.matchCounter = nil
    }

    init(cacheSize: Int = 50, matchCounter: MatchCounter) {
        self.cache = LRUCache(capacity: cacheSize)
        self.matchCounter = matchCounter
    }

    /// 对单个 PageItem 与查询字符串进行匹配评分
    public func match(item: PageItem, query: String) -> Int {
        matchCounter?.increment()

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

    /// 使所有缓存结果失效，下次搜索将重新计算
    public mutating func invalidateCache() {
        generation &+= 1
    }

    /// 带 LRU 缓存的搜索 — 相同 (query, data version) 组合直接返回缓存结果
    public func cachedSearch(items: [PageItem], query: String) -> [PageItem] {
        let cacheKey = "\(generation):\(query.lowercased())"

        if let cached = cache.get(cacheKey) {
            return cached
        }

        let results = search(items: items, query: query)
        cache.set(cacheKey, value: results)
        return results
    }
}
