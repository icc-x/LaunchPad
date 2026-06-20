import Foundation
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("性能基准测试")
struct PerformanceTests {

    @Test("1000 个 PageItem 生成 + SearchEngine 搜索 < 50ms")
    func search_1000items_under50ms() {
        let items = (0..<1000).map { i in
            TestDataFactory.makePageItem(
                id: Int64(i),
                uuid: "perf-\(i)",
                ordering: i,
                app: TestDataFactory.makeAppInfo(
                    id: Int64(i),
                    title: "Application \(i)",
                    bundleId: "com.test.app\(i)"
                )
            )
        }

        let engine = SearchEngine()

        let start = Date()
        let results = engine.cachedSearch(items: items, query: "app")
        let elapsed = Date().timeIntervalSince(start)

        #expect(results.count > 0)
        #expect(elapsed < 0.05) // < 50ms
    }

    @Test("SearchEngine 重复搜索命中缓存 < 1ms")
    func search_cached_under1ms() {
        let items = (0..<1000).map { i in
            TestDataFactory.makePageItem(
                id: Int64(i),
                uuid: "cache-\(i)",
                ordering: i,
                app: TestDataFactory.makeAppInfo(
                    id: Int64(i),
                    title: "App \(i)",
                    bundleId: "com.test.cache\(i)"
                )
            )
        }

        let engine = SearchEngine()

        // 第一次搜索（填充缓存）
        _ = engine.cachedSearch(items: items, query: "test")

        // 第二次搜索（命中缓存）
        let start = Date()
        let results = engine.cachedSearch(items: items, query: "test")
        let elapsed = Date().timeIntervalSince(start)

        #expect(results.count > 0)
        #expect(elapsed < 0.001) // < 1ms（缓存命中）
    }

    @Test("DiffableDataSource Snapshot 构建 1000 项 < 10ms")
    func snapshot_1000items_under10ms() {
        let pages = (0..<3).map { pageIdx in
            (0..<334).map { i in
                let globalIdx = pageIdx * 334 + i
                return TestDataFactory.makePageItem(
                    id: Int64(globalIdx),
                    uuid: "snap-\(globalIdx)",
                    ordering: i,
                    app: TestDataFactory.makeAppInfo(
                        id: Int64(globalIdx),
                        title: "App \(globalIdx)",
                        bundleId: "com.test.snap\(globalIdx)"
                    )
                )
            }
        }

        let start = Date()
        let snapshot = DiffableDataSourceBuilder.buildSnapshot(
            pages: pages,
            searchResults: nil,
            searchQuery: nil
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(snapshot.numberOfItems > 900)
        #expect(elapsed < 0.01) // < 10ms
    }

    @Test("GridLayoutCalculator 三种屏幕宽度计算 < 1ms")
    func gridCalculation_under1ms() {
        let widths: [CGFloat] = [1440, 1728, 2560]

        let start = Date()
        for width in widths {
            let params = GridLayoutCalculator.calculate(screenWidth: width)
            #expect(params.itemsPerPage > 0)
        }
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 0.001)
    }
}
