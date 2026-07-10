import Foundation
import LaunchPadProtocols

/// LRU 缓存 — 基于双向链表 + 字典实现
final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?

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
        guard let node = cache[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    func set(_ key: Key, value: Value) {
        if let node = cache[key] {
            node.value = value
            moveToHead(node)
            return
        }

        let node = Node(key: key, value: value)
        cache[key] = node
        addToHead(node)

        if cache.count > capacity {
            evictOldest()
        }
    }

    private func moveToHead(_ node: Node) {
        guard node !== head else { return }
        removeNode(node)
        addToHead(node)
    }

    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func removeNode(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if node === head { head = node.next }
        if node === tail { tail = node.prev }
        node.prev = nil
        node.next = nil
    }

    private func evictOldest() {
        guard let oldTail = tail else { return }
        cache.removeValue(forKey: oldTail.key)
        removeNode(oldTail)
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

        let title = item.app?.title.lowercased() ?? item.group?.title.lowercased() ?? ""
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
            let title = item.app?.title ?? item.group?.title ?? ""
            return (item, score, title)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map(\.item)
    }

    /// 带 LRU 缓存的搜索 — 相同查询直接返回缓存结果
    public func cachedSearch(items: [PageItem], query: String) -> [PageItem] {
        let cacheKey = query.lowercased()

        if let cached = cache.get(cacheKey) {
            return cached
        }

        let results = search(items: items, query: query)
        cache.set(cacheKey, value: results)
        return results
    }
}
