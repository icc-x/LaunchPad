import Foundation
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("SearchEngine 评分算法")
struct SearchEngineTests {

    private func makeAppItem(
        title: String,
        bundleId: String = "com.test.app"
    ) -> PageItem {
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

    @Test("词首前缀匹配 - 得分 100")
    func prefixMatch_score100() {
        let sut = SearchEngine()
        #expect(sut.match(item: makeAppItem(title: "Safari"), query: "saf") == 100)
    }

    @Test("词首前缀匹配 - 大小写不敏感")
    func prefixMatch_caseInsensitive() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari")
        #expect(sut.match(item: item, query: "SAF") == 100)
        #expect(sut.match(item: item, query: "Saf") == 100)
        #expect(sut.match(item: item, query: "saf") == 100)
    }

    @Test("单词前缀匹配 - 得分 75")
    func wordPrefixMatch_score75() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Final Cut Pro")
        #expect(sut.match(item: item, query: "cut") == 75)
        #expect(sut.match(item: item, query: "pro") == 75)
    }

    @Test("子串匹配 - 得分 50")
    func substringMatch_score50() {
        let sut = SearchEngine()
        #expect(sut.match(item: makeAppItem(title: "Tessa"), query: "sa") == 50)
    }

    @Test("bundleId 匹配 - 得分 25")
    func bundleIdMatch_score25() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari", bundleId: "com.apple.Safari")
        #expect(sut.match(item: item, query: "apple") == 25)
    }

    @Test("无匹配 - 得分 0")
    func noMatch_score0() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "Safari", bundleId: "com.apple.Safari")
        #expect(sut.match(item: item, query: "zzzz") == 0)
    }

    @Test("空查询对所有项返回满分 100")
    func emptyQuery_returns100() {
        let sut = SearchEngine()
        #expect(sut.match(item: makeAppItem(title: "Safari"), query: "") == 100)
    }

    @Test("文件夹名称参与匹配")
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

        #expect(
            sut.match(item: prefixItem, query: "sa")
                > sut.match(item: substringItem, query: "sa")
        )
        #expect(sut.match(item: wordItem, query: "cut") == 75)
    }

    @Test("同分结果按标题字母序排列")
    func tiedScores_sortedAlphabetically() {
        let sut = SearchEngine()
        let items = [makeAppItem(title: "Astro App"), makeAppItem(title: "Alpha App")]

        let results = sut.search(items: items, query: "a")

        #expect(results.map(\.app?.title) == ["Alpha App", "Astro App"])
    }

    @Test("应用标题为空时非匹配查询返回 0")
    func emptyTitle_noMatch() {
        let sut = SearchEngine()
        let item = makeAppItem(title: "", bundleId: "com.nomatch.bundle")
        #expect(sut.match(item: item, query: "test") == 0)
    }

    @Test("精确全匹配 - 得分 100")
    func exactMatch_score100() {
        let sut = SearchEngine()
        #expect(sut.match(item: makeAppItem(title: "Safari"), query: "Safari") == 100)
    }
}

@Suite("SearchEngine 完整搜索")
struct SearchEngineSearchTests {

    private func makeAppItem(
        title: String,
        bundleId: String = "com.test.app"
    ) -> PageItem {
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

    @Test("search 返回匹配项并按分数排序")
    func search_returnsSortedMatches() {
        let sut = SearchEngine()
        let items = [
            makeAppItem(title: "Tessa"),
            makeAppItem(title: "Safari"),
            makeAppItem(title: "Terminal"),
        ]

        let results = sut.search(items: items, query: "sa")

        #expect(results.count == 2)
        #expect(results.first?.app?.title == "Safari")
    }

    @Test("search 空查询返回所有项")
    func search_emptyQuery_returnsAll() {
        let sut = SearchEngine()
        let items = [makeAppItem(title: "A"), makeAppItem(title: "B")]
        #expect(sut.search(items: items, query: "") == items)
    }

    @Test("search 无匹配返回空数组")
    func search_noMatch_returnsEmpty() {
        let sut = SearchEngine()
        let items = [makeAppItem(title: "Safari")]
        #expect(sut.search(items: items, query: "zzzz").isEmpty)
    }

    @Test("search 匹配 group 类型 item")
    func search_groupItem_match() {
        let sut = SearchEngine()
        let groupItem = TestDataFactory.makePageItem(
            type: .group,
            group: TestDataFactory.makeGroupInfo(title: "Utilities")
        )

        let results = sut.search(items: [groupItem], query: "util")

        #expect(results == [groupItem])
    }

    @Test("相同 query 对不同数据集分别计算结果")
    func sameQueryUsesCurrentDataset() {
        let sut = SearchEngine()
        let firstDataset = [makeAppItem(title: "Safari")]
        let secondDataset = [makeAppItem(title: "Notes")]

        let first = sut.search(items: firstDataset, query: "saf")
        let second = sut.search(items: secondDataset, query: "saf")

        #expect(first.map(\.app?.title) == ["Safari"])
        #expect(second.isEmpty)
    }
}

@Suite("SearchEngine 分支覆盖")
struct SearchEngineBranchTests {

    @Test("match 在 app 与 group 均为空时返回 0")
    func match_appAndGroupNil_returnsZero() {
        let sut = SearchEngine()
        let item = TestDataFactory.makePageItem(type: .app, app: nil, group: nil)
        #expect(sut.match(item: item, query: "test") == 0)
    }

    @Test("search 在 app 与 group 均为空时过滤该项")
    func search_appAndGroupNil_returnsEmpty() {
        let sut = SearchEngine()
        let item = TestDataFactory.makePageItem(type: .app, app: nil, group: nil)
        #expect(sut.search(items: [item], query: "test").isEmpty)
    }

    @Test("match 在 app 为空时使用 group title")
    func match_itemAppNil_fallsBackToGroupTitle() {
        let sut = SearchEngine()
        let group = TestDataFactory.makePageItem(
            id: 1,
            type: .group,
            ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "My Folder")
        )
        #expect(sut.match(item: group, query: "fol") == 75)
    }

    @Test("search 使用 group title")
    func search_groupItemWithNilApp_usesGroupTitle() {
        let sut = SearchEngine()
        let group = TestDataFactory.makePageItem(
            id: 1,
            type: .group,
            ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let app = TestDataFactory.makeAppItems(count: 1, titlePrefix: "Safari")[0]

        let results = sut.search(items: [group, app], query: "fol")

        #expect(results.contains(group))
    }
}
