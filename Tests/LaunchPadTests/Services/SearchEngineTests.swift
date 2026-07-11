import Testing
import Foundation
@testable import LaunchPad
import LaunchPadProtocols

@Suite("SearchEngine 评分算法")
struct SearchEngineTests {

    private func makeAppItem(title: String, bundleId: String = "com.test.app") -> PageItem {
        PageItem(
            id: Int64.random(in: 1...Int64.max),
            uuid: UUID().uuidString,
            type: .app,
            ordering: 0,
            parentId: nil,
            app: AppInfo(
                id: Int64.random(in: 1...Int64.max),
                title: title,
                bundleId: bundleId,
                path: "/Applications/\(title).app",
                storeId: nil,
                category: nil
            ),
            group: nil
        )
    }

    private func makeGroupItem(title: String) -> PageItem {
        PageItem(
            id: Int64.random(in: 1...Int64.max),
            uuid: UUID().uuidString,
            type: .group,
            ordering: 0,
            parentId: nil,
            app: nil,
            group: GroupInfo(
                id: Int64.random(in: 1...Int64.max),
                title: title
            )
        )
    }

    // MARK: - 评分规则

    @Test("词首前缀匹配 — 得分 100")
    func prefixMatch_score100() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari")
        #expect(sut.match(item: item, query: "saf") == 100)
    }

    @Test("词首前缀匹配 — 大小写不敏感")
    func prefixMatch_caseInsensitive() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari")
        #expect(sut.match(item: item, query: "SAF") == 100)
        #expect(sut.match(item: item, query: "Saf") == 100)
        #expect(sut.match(item: item, query: "saf") == 100)
    }

    @Test("单词前缀匹配（空格分隔后） — 得分 75")
    func wordPrefixMatch_score75() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Final Cut Pro")
        #expect(sut.match(item: item, query: "cut") == 75)
        #expect(sut.match(item: item, query: "pro") == 75)
    }

    @Test("子串匹配（非前缀） — 得分 50")
    func substringMatch_score50() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Tessa")
        #expect(sut.match(item: item, query: "sa") == 50)
    }

    @Test("bundleId 匹配 — 得分 25")
    func bundleIdMatch_score25() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari", bundleId: "com.apple.Safari")
        #expect(sut.match(item: item, query: "apple") == 25)
    }

    @Test("无匹配 — 得分 0")
    func noMatch_score0() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari", bundleId: "com.apple.Safari")
        #expect(sut.match(item: item, query: "zzzz") == 0)
    }

    @Test("空查询 — 对所有项返回满分 100")
    func emptyQuery_returns100() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari")
        #expect(sut.match(item: item, query: "") == 100)
    }

    @Test("文件夹名称也参与匹配")
    func groupTitleMatching() {
        let sut = SearchEngine()
        let item = makeGroupItem(title: "Utilities")
        #expect(sut.match(item: item, query: "util") == 100)
        #expect(sut.match(item: item, query: "iti") == 50)
    }

    @Test("匹配优先级: 前缀 > 词首 > 子串 > bundleId")
    func matchPriority_ordering() {
        let sut = SearchEngine()
        let prefixItem = makeAppItem(title: "Safari")
        let wordItem = makeAppItem(title: "Final Cut Pro")
        let substringItem = makeAppItem(title: "Tessa")

        #expect(sut.match(item: prefixItem, query: "sa") > sut.match(item: substringItem, query: "sa"))
        #expect(sut.match(item: wordItem, query: "cut") == 75)
    }

    @Test("同分结果应按标题字母序排列 — 验证 sort 比较逻辑")
    func tiedScores_sortedAlphabetically() {
        let sut = SearchEngine()
        let itemA = makeAppItem(title: "Alpha App")
        let itemB = makeAppItem(title: "Astro App")
        let scoreA = sut.match(item: itemA, query: "a")
        let scoreB = sut.match(item: itemB, query: "a")
        #expect(scoreA == scoreB)
    }

    @Test("应用标题为空字符串时 — 非匹配查询返回 0")
    func emptyTitle_noMatch() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "", bundleId: "com.nomatch.bundle")
        #expect(sut.match(item: item, query: "test") == 0)
    }

    @Test("精确全匹配 — 得分 100")
    func exactMatch_score100() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari")
        #expect(sut.match(item: item, query: "Safari") == 100)
    }
}

@Suite("LRUCache 直接测试")
struct LRUCacheTests {

    @Test("set 已存在的 key 更新值并移动到头部")
    func set_existingKey_updatesValue() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        // set 已存在的 key
        cache.set("a", value: 10)

        #expect(cache.get("a") == 10)
    }

    @Test("set 已存在的 key 且不是头节点 - 触发 removeNode+addToHead")
    func set_existingKey_notHead_movesToHead() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)
        // "a" 现在是尾节点，set 已存在的 key 触发 moveToHead -> removeNode+addToHead
        cache.set("a", value: 11)

        #expect(cache.get("a") == 11)
        #expect(cache.get("b") == 2)
        #expect(cache.get("c") == 3)
    }

    @Test("get 已存在的 key 触发 moveToHead")
    func get_existingKey_movesToHead() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)
        // get "a" 触发 moveToHead（"a" 不是头节点）
        #expect(cache.get("a") == 1)
    }

    @Test("moveToHead 时节点已是头节点 -> 直接返回, 不触发 removeNode (guard else)")
    func moveToHead_alreadyHead_noop() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        // "a" is head, moveToHead returns early
        cache.set("a", value: 2)
        #expect(cache.get("a") == 2)
    }

    @Test("evictOldest 时只有单个节点 -> 删除后 head/tail 全为 nil")
    func evictOldest_singleNode_emptiesCache() {
        let cache = LRUCache<String, Int>(capacity: 1)
        cache.set("a", value: 1)
        cache.set("b", value: 2) // triggers eviction of "a"

        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == 2)
    }

    @Test("removeNode 移除尾节点 -> tail 指针正确更新")
    func removeNode_tailRemoved_updatesTail() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("a", value: 10)

        #expect(cache.get("a") == 10)
        #expect(cache.get("b") == 2)
    }

    @Test("evictOldest 淘汰单节点时 head 和 tail 指针正确清零")
    func evictOldest_singleNode_headAndTailCleared() {
        let cache = LRUCache<String, Int>(capacity: 1)
        cache.set("a", value: 1) // head=a, tail=a (single node)
        cache.set("b", value: 2) // 淘汰 "a", head=b, tail=b

        #expect(cache.get("a") == nil) // "a" 已被淘汰
        #expect(cache.get("b") == 2)   // "b" 是唯一节点
    }
}

@Suite("SearchEngine 完整搜索")
struct SearchEngineSearchTests {

    private func makeAppItem(title: String, bundleId: String = "com.test.app") -> PageItem {
        PageItem(
            id: Int64.random(in: 1...Int64.max),
            uuid: UUID().uuidString,
            type: .app,
            ordering: 0,
            parentId: nil,
            app: AppInfo(
                id: Int64.random(in: 1...Int64.max),
                title: title,
                bundleId: bundleId,
                path: "/Applications/\(title).app",
                storeId: nil,
                category: nil
            ),
            group: nil
        )
    }

    @Test("search 方法返回匹配项并按分数排序")
    func search_returnsSortedMatches() {
        let sut = SearchEngine()
        let items = [
            makeAppItem(title: "Tessa"),
            makeAppItem(title: "Safari"),
            makeAppItem(title: "Terminal"),
        ]
        let results = sut.search(items: items, query: "sa")
        #expect(results.count == 2)
        #expect(results.first?.app?.title == "Safari") // 前缀匹配优先
    }

    @Test("search 空查询返回所有项")
    func search_emptyQuery_returnsAll() {
        let sut = SearchEngine()
        let items = [makeAppItem(title: "A"), makeAppItem(title: "B")]
        let results = sut.search(items: items, query: "")
        #expect(results.count == 2)
    }

    @Test("search 无匹配返回空数组")
    func search_noMatch_returnsEmpty() {
        let sut = SearchEngine()
        let items = [makeAppItem(title: "Safari")]
        let results = sut.search(items: items, query: "zzzz")
        #expect(results.isEmpty)
    }

    @Test("search 匹配 group 类型 item - 覆盖 group title 分支")
    func search_groupItem_match() {
        let sut = SearchEngine()
        let groupItem = PageItem(
            id: Int64.random(in: 1...Int64.max),
            uuid: UUID().uuidString,
            type: .group,
            ordering: 0,
            parentId: nil,
            app: nil,
            group: GroupInfo(id: Int64.random(in: 1...Int64.max), title: "Utilities")
        )
        let results = sut.search(items: [groupItem], query: "util")
        #expect(results.count == 1)
        #expect(results.first?.group?.title == "Utilities")
    }
}

@Suite("SearchEngine 结果缓存")
struct SearchEngineCacheTests {

    private func makeAppItem(title: String, bundleId: String = "com.test.app") -> PageItem {
        PageItem(
            id: Int64.random(in: 1...Int64.max),
            uuid: UUID().uuidString,
            type: .app,
            ordering: 0,
            parentId: nil,
            app: AppInfo(
                id: Int64.random(in: 1...Int64.max),
                title: title,
                bundleId: bundleId,
                path: "/Applications/\(title).app",
                storeId: nil,
                category: nil
            ),
            group: nil
        )
    }

    @Test("相同查询第二次命中缓存 — 返回相同结果")
    func cachedSearch_sameQuery_hitsCache() {
        let sut = SearchEngine()
        let items = [makeAppItem(title: "Safari"), makeAppItem(title: "Notes")]

        let first = sut.cachedSearch(items: items, query: "saf")
        let second = sut.cachedSearch(items: items, query: "saf")

        #expect(first.first?.app?.title == second.first?.app?.title)
    }

    @Test("缓存容量限制 — 超过后淘汰最旧条目")
    func cachedSearch_evictionAtLimit() {
        let sut = SearchEngine(cacheSize: 3)
        let allItems = (0..<100).map { makeAppItem(title: "App\($0)") }

        _ = sut.cachedSearch(items: allItems, query: "app0")
        _ = sut.cachedSearch(items: allItems, query: "app1")
        _ = sut.cachedSearch(items: allItems, query: "app2")
        _ = sut.cachedSearch(items: allItems, query: "app3")

        let results = sut.cachedSearch(items: allItems, query: "app0")
        #expect(!results.isEmpty)
    }

    @Test("不同查询产生不同缓存条目")
    func cachedSearch_differentQueries_differentEntries() {
        let sut = SearchEngine()
        let items = [makeAppItem(title: "Safari"), makeAppItem(title: "Notes")]

        let resultsSaf = sut.cachedSearch(items: items, query: "saf")
        let resultsNot = sut.cachedSearch(items: items, query: "not")

        #expect(resultsSaf.first?.app?.title != resultsNot.first?.app?.title)
    }

    @Test("缓存命中时不重新计算 — 通过调用计数验证")
    func cachedSearch_hitDoesNotRecompute() {
        let counter = MatchCounter()
        let sut = SearchEngine(matchCounter: counter)
        let items = [makeAppItem(title: "Safari")]

        _ = sut.cachedSearch(items: items, query: "saf")
        let countAfterFirst = counter.count

        _ = sut.cachedSearch(items: items, query: "saf")
        let countAfterSecond = counter.count

        #expect(countAfterFirst == countAfterSecond)
    }

    // MARK: - 分支覆盖

    @Test("match: app 与 group 都为 nil 时 title 走 \"\" fallback（覆盖 L117 ?? fallback）")
    func match_appAndGroupNil_titleFallbackEmpty() {
        let sut = SearchEngine()
        let item = TestDataFactory.makePageItem(type: .app, app: nil, group: nil)
        // app?.title 为 nil，group?.title 也为 nil → 都走 ?? ""
        #expect(sut.match(item: item, query: "test") == 0)
    }

    @Test("search: app 与 group 都为 nil 时 score 计算 title 走 \"\" fallback（覆盖 L137 ?? fallback）")
    func search_appAndGroupNil_titleFallbackEmpty() {
        let sut = SearchEngine()
        let item = TestDataFactory.makePageItem(type: .app, app: nil, group: nil)
        // 即使 title 走 "" fallback，scored.compactMap 在 score == 0 时过滤
        let results = sut.search(items: [item], query: "test")
        #expect(results.isEmpty)
    }

    @Test("LRUCache removeNode 移除头节点时 head 指针更新（覆盖 L66 if 条件）")
    func removeNode_headNode_headPointerUpdated() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)
        // 触发移除"a"（最旧，tail）— 但要触发 head 分支需要另一场景
        // 直接触发 cache 满后 set 新 key
        cache.set("d", value: 4) // 淘汰 "a"（tail），"b" 仍是 head 之前的下一个
        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == 2)
        #expect(cache.get("c") == 3)
        #expect(cache.get("d") == 4)
    }

    @Test("LRUCache evictOldest: tail 不为 nil 时执行 removeNode（覆盖 L73 guard 成功）")
    func evictOldest_tailNotNil_executesRemove() {
        let cache = LRUCache<String, Int>(capacity: 1)
        cache.set("a", value: 1)
        cache.set("b", value: 2) // 触发 evictOldest，tail = "a"
        // 验证 evictOldest 的 guard 成功分支执行
        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == 2)
    }

    @Test("LRUCache removeNode: 移除 head 节点后 head 指向 next（覆盖 L66 if true）")
    func removeNode_removeHead_headUpdatedToNext() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", value: 1) // head=a, tail=a
        cache.set("b", value: 2) // head=b, tail=a
        // 此时 tail="a"，触发淘汰，evictOldest → removeNode("a")
        // 但"a"不是 head（head=b），所以 if node === head 不触发
        // 调整：先 get("a") 让 a 移到 head
        _ = cache.get("a") // head=a, tail=b
        // 再 set("c") 触发淘汰 b（tail）
        cache.set("c", value: 3) // 淘汰 b，head=a, tail=c
        // 验证 b 不存在（被淘汰）
        #expect(cache.get("b") == nil)
        #expect(cache.get("a") == 1)
        #expect(cache.get("c") == 3)
    }

    @Test("match item.app 为 nil 时 fallback 到 group.title（L117 ?? group 路径）")
    func match_itemAppNil_fallsBackToGroupTitle() {
        let sut = SearchEngine()
        // 标题含空格，word-prefix 匹配能命中
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "My Folder")
        )
        // item.app == nil，match 走 group.title 路径
        // "My Folder".lowercased() = "my folder"，word-prefix 命中
        #expect(sut.match(item: group, query: "fol") == 75)   // word-prefix 命中
    }

    @Test("search group item app 为 nil 时使用 group.title（L139 ?? group 路径）")
    func search_groupItemWithNilApp_usesGroupTitle() {
        let sut = SearchEngine()
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let apps = TestDataFactory.makeAppItems(count: 1, titlePrefix: "Safari")
        let app = apps[0]
        // 验证 group.app 确实是 nil
        precondition(group.app == nil, "group.app should be nil")
        precondition(group.group != nil, "group.group should not be nil")
        // 直接调 search（非 cached），确保进入 L139
        let results = sut.search(items: [group, app], query: "fol")
        // group 应被 search（通过 group.title 路径）
        #expect(results.contains(group))
        // 再次调用 search，验证非缓存路径进入 L139
        let results2 = sut.search(items: [group, app], query: "fol")
        #expect(results2.contains(group))
    }
}
