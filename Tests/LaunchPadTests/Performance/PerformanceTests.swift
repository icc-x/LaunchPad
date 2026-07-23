import Foundation
import Testing
@testable import LaunchPad
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit
#endif

private let sampleCount = 11

private func durations<T>(
    warmupCount: Int = 3,
    operation: () -> T
) -> (samples: [Duration], last: T) {
    precondition(sampleCount > 0)

    for _ in 0..<warmupCount {
        _ = operation()
    }

    let clock = ContinuousClock()
    var samples: [Duration] = []

    let firstStart = clock.now
    var last = operation()
    samples.append(firstStart.duration(to: clock.now))

    for _ in 1..<sampleCount {
        let start = clock.now
        last = operation()
        samples.append(start.duration(to: clock.now))
    }

    return (samples.sorted(), last)
}

private func median(_ samples: [Duration]) -> Duration {
    samples[samples.count / 2]
}

private func percentile95(_ samples: [Duration]) -> Duration {
    let index = min(
        samples.count - 1,
        Int(ceil(Double(samples.count) * 0.95)) - 1
    )
    return samples[index]
}

private func deterministicIndices(
    count: Int,
    upperBound: Int,
    seed: UInt64 = 0x4C41554E43485041
) -> [Int] {
    precondition(upperBound > 0)

    var state = seed
    return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int(state % UInt64(upperBound))
    }
}

#if canImport(AppKit)
private struct IconCacheBitmapFixture {
    let image: NSImage
    let tiffData: Data
}

private enum PerformanceFixtureError: Error {
    case bitmapCreationFailed
    case tiffEncodingFailed
}

private func makeIconCacheBitmapFixture(size: Int = 16) throws -> IconCacheBitmapFixture {
    guard let bitmapRepresentation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    ) else {
        throw PerformanceFixtureError.bitmapCreationFailed
    }

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmapRepresentation)
    guard let tiffData = image.tiffRepresentation,
          !tiffData.isEmpty,
          NSBitmapImageRep(data: tiffData) != nil else {
        throw PerformanceFixtureError.tiffEncodingFailed
    }
    return IconCacheBitmapFixture(image: image, tiffData: tiffData)
}
#endif

@Suite("性能基准测试")
struct PerformanceTests {

    @Test("SearchEngine 1000 项无缓存 median/p95 < 50ms")
    func search_1000items_under50ms() {
        let items = (0..<1000).map { index in
            TestDataFactory.makePageItem(
                id: Int64(index),
                uuid: "perf-\(index)",
                ordering: index,
                app: TestDataFactory.makeAppInfo(
                    id: Int64(index),
                    title: "Application \(index)",
                    bundleId: "com.test.app\(index)"
                )
            )
        }
        let engine = SearchEngine()

        let measurement = durations {
            engine.search(items: items, query: "app")
        }

        #expect(measurement.last.count == 1000)
        #expect(median(measurement.samples) < .milliseconds(50))
        #expect(percentile95(measurement.samples) < .milliseconds(50))
    }

    @Test("SearchEngine 缓存命中 median/p95 < 1ms")
    func search_cached_under1ms() {
        let items = (0..<1000).map { index in
            TestDataFactory.makePageItem(
                id: Int64(index),
                uuid: "cache-\(index)",
                ordering: index,
                app: TestDataFactory.makeAppInfo(
                    id: Int64(index),
                    title: "App \(index)",
                    bundleId: "com.test.cache\(index)"
                )
            )
        }
        let counter = MatchCounter()
        let engine = SearchEngine(matchCounter: counter)

        _ = engine.cachedSearch(items: items, query: "test")
        #expect(counter.count == 1000)

        let measurement = durations {
            engine.cachedSearch(items: items, query: "test")
        }

        #expect(measurement.last.count == 1000)
        #expect(counter.count == 1000)
        #expect(median(measurement.samples) < .milliseconds(1))
        #expect(percentile95(measurement.samples) < .milliseconds(1))
    }

    @Test("Diffable snapshot 1002 项 median/p95 < 10ms")
    func snapshot_1000items_under10ms() {
        let pages = (0..<3).map { pageIndex in
            (0..<334).map { itemIndex in
                let global = pageIndex * 334 + itemIndex
                return TestDataFactory.makePageItem(
                    id: Int64(global),
                    uuid: "snap-\(global)",
                    ordering: itemIndex,
                    app: TestDataFactory.makeAppInfo(
                        id: Int64(global),
                        title: "App \(global)",
                        bundleId: "com.test.snap\(global)"
                    )
                )
            }
        }

        let measurement = durations {
            DiffableDataSourceBuilder.buildSnapshot(
                pages: pages,
                searchResults: nil,
                searchQuery: nil
            )
        }

        #expect(measurement.last.numberOfItems == 1002)
        #expect(measurement.last.numberOfSections == 3)
        for pageIndex in pages.indices {
            #expect(
                measurement.last.itemIdentifiers(inSection: .page(pageIndex)).count == 334
            )
        }
        #expect(median(measurement.samples) < .milliseconds(10))
        #expect(percentile95(measurement.samples) < .milliseconds(10))
    }

    @Test("动态 GridMetrics 三种 viewport median/p95 < 1ms")
    func gridCalculation_under1ms() {
        let sizes = [
            CGSize(width: 1440, height: 620),
            CGSize(width: 1728, height: 620),
            CGSize(width: 2560, height: 620),
        ]
        let expected = [
            (columns: 7, rows: 5, itemsPerPage: 35),
            (columns: 9, rows: 5, itemsPerPage: 45),
            (columns: 10, rows: 5, itemsPerPage: 50),
        ]

        let measurement = durations {
            sizes.map { GridLayoutCalculator.calculate(viewportSize: $0) }
        }

        #expect(measurement.last.count == expected.count)
        for index in expected.indices {
            let metrics = measurement.last[index]
            let expectedMetrics = expected[index]
            #expect(metrics.columns == expectedMetrics.columns)
            #expect(metrics.rows == expectedMetrics.rows)
            #expect(metrics.itemsPerPage == expectedMetrics.itemsPerPage)
            #expect(metrics.pageWidth == sizes[index].width)
        }
        #expect(median(measurement.samples) < .milliseconds(1))
        #expect(percentile95(measurement.samples) < .milliseconds(1))
    }

    // MARK: - IconCache

    #if canImport(AppKit)
    @Test("IconCache 1000 次内存命中 median/p95 < 300ms")
    func iconCache_1000randomAccess_perf() throws {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let fixture = try makeIconCacheBitmapFixture()
        let itemCount = 50
        let fixedModificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let paths = (0..<itemCount).map { "/Applications/App-\($0).app" }

        provider.iconResult = fixture.image
        for (index, path) in paths.enumerated() {
            store.storedImages[Int64(index)] = (fixture.tiffData, fixture.tiffData)
            provider.modificationDates[path] = fixedModificationDate
        }

        let cache = IconCache(
            iconProvider: provider,
            imageStore: store,
            memoryLimit: 100
        )
        for (index, path) in paths.enumerated() {
            _ = cache.icon(forItemId: Int64(index), path: path)
        }

        let indices = deterministicIndices(
            count: 1000,
            upperBound: itemCount
        )
        let storeFetchCountBeforeMeasurement = store.fetchCallCount
        let storeSaveCountBeforeMeasurement = store.saveCallCount
        let providerFetchCountBeforeMeasurement = provider.fetchCallCount

        let measurement = durations {
            var last: NSImage?
            for index in indices {
                last = cache.icon(
                    forItemId: Int64(index),
                    path: paths[index]
                )
            }
            return last
        }

        #expect(measurement.last != nil)
        #expect(store.fetchCallCount == storeFetchCountBeforeMeasurement)
        #expect(store.saveCallCount == storeSaveCountBeforeMeasurement)
        #expect(provider.fetchCallCount == providerFetchCountBeforeMeasurement)
        #expect(median(measurement.samples) < .milliseconds(300))
        #expect(percentile95(measurement.samples) < .milliseconds(300))
    }

    @Test("IconCache 1000 次访问后无磁盘重复写入")
    func iconCache_1000access_noDiskWriteLeak() throws {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let fixture = try makeIconCacheBitmapFixture()
        let itemCount = 50
        let fixedModificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let paths = (0..<itemCount).map { "/Applications/App-\($0).app" }

        provider.iconResult = fixture.image
        for (index, path) in paths.enumerated() {
            store.storedImages[Int64(index)] = (fixture.tiffData, fixture.tiffData)
            provider.modificationDates[path] = fixedModificationDate
        }

        let cache = IconCache(
            iconProvider: provider,
            imageStore: store,
            memoryLimit: itemCount
        )
        for (index, path) in paths.enumerated() {
            _ = cache.icon(forItemId: Int64(index), path: path)
        }
        let saveCountAfterPrefill = store.saveCallCount
        let indices = deterministicIndices(count: 1000, upperBound: itemCount)

        #expect(indices.count == 1000)
        #expect(indices.allSatisfy { (0..<itemCount).contains($0) })
        for index in indices {
            _ = cache.icon(forItemId: Int64(index), path: paths[index])
        }

        #expect(store.saveCallCount == saveCountAfterPrefill)
    }
    #endif
}
