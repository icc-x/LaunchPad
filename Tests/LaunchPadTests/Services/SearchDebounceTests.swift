import Foundation
import Testing
import LaunchPadProtocols
@testable import LaunchPad

@Suite("搜索防抖 100ms")
@MainActor
struct SearchDebounceTests {

    // MARK: - 基础防抖

    @Test("输入间隔 < 100ms → 仅触发 1 次搜索")
    func debounce_mergesRapidInputs() {
        let scheduler = MockScheduler()
        var searchCallCount = 0
        var lastQuery = ""
        let debouncer = SearchDebouncer(scheduler: scheduler) { query in
            searchCallCount += 1
            lastQuery = query
        }

        debouncer.search(query: "s")
        debouncer.search(query: "sa")
        debouncer.search(query: "saf")
        debouncer.search(query: "safa")
        debouncer.search(query: "safar")
        debouncer.search(query: "safari")

        #expect(searchCallCount == 0) // 被 debounce，尚未触发

        scheduler.fireLatest() // 模拟 100ms 后触发

        #expect(searchCallCount == 1)
        #expect(lastQuery == "safari")
    }

    @Test("空查询立即触发，不防抖")
    func emptyQuery_firesImmediately() {
        let scheduler = MockScheduler()
        var searchCallCount = 0
        let debouncer = SearchDebouncer(scheduler: scheduler) { _ in
            searchCallCount += 1
        }

        debouncer.search(query: "test")
        debouncer.search(query: "")

        #expect(searchCallCount == 1) // 空查询立即触发
        #expect(scheduler.scheduledActions.count == 0) // 无 pending
    }

    @Test("Backspace（查询变短）立即触发，不防抖")
    func backspace_firesImmediately() {
        let scheduler = MockScheduler()
        var queries: [String] = []
        let debouncer = SearchDebouncer(scheduler: scheduler) { query in
            queries.append(query)
        }

        debouncer.search(query: "safari")
        #expect(queries.count == 0) // 被 debounce

        debouncer.search(query: "safar") // Backspace: 6→5 字符
        #expect(queries.count == 1)
        #expect(queries.last == "safar")
        // cancel 被调用 2 次：debounce 路径 1 次 + backspace 路径 1 次
        #expect(scheduler.cancelCallCount == 2)
    }

    @Test("快速输入 5 个字符 → 防抖结束后仅触发 1 次搜索")
    func rapidTyping_singleSearchAfterDebounce() {
        let scheduler = MockScheduler()
        var searchCount = 0
        let debouncer = SearchDebouncer(scheduler: scheduler) { _ in
            searchCount += 1
        }

        for char in "safer" {
            debouncer.search(query: String(char))
        }

        #expect(searchCount == 0)

        scheduler.fireLatest()
        #expect(searchCount == 1)
    }

    // MARK: - 缓存验证（SearchEngine 层面）

    @Test("相同查询第二次命中缓存，不重复计算")
    func cachedSearch_sameQueryHitsCache() {
        let items = [
            TestDataFactory.makePageItem(id: 1, app: TestDataFactory.makeAppInfo(id: 1, title: "Safari")),
            TestDataFactory.makePageItem(id: 2, app: TestDataFactory.makeAppInfo(id: 2, title: "Settings")),
        ]

        let counter = MatchCounter()
        let engineWithCounter = SearchEngine(cacheSize: 50, matchCounter: counter)

        _ = engineWithCounter.cachedSearch(items: items, query: "sa")
        let countAfterFirst = counter.count

        _ = engineWithCounter.cachedSearch(items: items, query: "sa")
        let countAfterSecond = counter.count

        #expect(countAfterSecond == countAfterFirst) // 缓存命中，没有重新匹配
    }

    // MARK: - cancelPending

    @Test("cancelPending 取消所有待执行搜索")
    func cancelPending_cancelsAllScheduled() {
        let scheduler = MockScheduler()
        var searchCount = 0
        let debouncer = SearchDebouncer(scheduler: scheduler) { _ in
            searchCount += 1
        }

        debouncer.search(query: "safari")
        debouncer.cancelPending()

        scheduler.fireLatest()
        #expect(searchCount == 0)
    }
}
