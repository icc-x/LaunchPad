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
}
