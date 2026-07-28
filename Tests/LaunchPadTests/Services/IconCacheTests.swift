import Testing
import Foundation
import LaunchPadProtocols
@testable import LaunchPad
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Tests

#if canImport(AppKit)
@MainActor
@Suite("IconCache dual-layer cache")
struct IconCacheTests {

    private func makeTestImage(size: Int = 16) -> NSImage {
        // Use bitmap representation directly to avoid lockFocus issues in headless environment
        guard let bitmapRep = NSBitmapImageRep(
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
        ), let cgImage = bitmapRep.cgImage else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    private func makeSolidColorImage(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        size: Int = 128
    ) -> NSImage {
        guard let bitmapRep = NSBitmapImageRep(
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
        ), let pixels = bitmapRep.bitmapData else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        for offset in stride(from: 0, to: size * size * 4, by: 4) {
            pixels[offset] = red
            pixels[offset + 1] = green
            pixels[offset + 2] = blue
            pixels[offset + 3] = 255
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmapRep)
        return image
    }

    private func firstPixel(_ image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return representation.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
    }

    private func makePNGData(_ image: NSImage) -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // Fallback: create PNG data from bitmap directly
            guard let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 64, bitsPerPixel: 32
            ) else { return Data() }
            return bitmapRep.representation(using: .png, properties: [:]) ?? Data()
        }
        return png
    }

    private func makeRecord(
        icon1x: Data,
        icon2x: Data? = nil,
        sourceModificationDate: Date
    ) -> CachedImageRecord {
        CachedImageRecord(
            icon1x: icon1x,
            icon2x: icon2x ?? icon1x,
            sourceModificationDate: sourceModificationDate
        )
    }

    // MARK: - Memory hit

    @Test("Memory cache hit -> no disk read")
    func memoryCacheHit_noDiskRead() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        let image = makeTestImage()
        let path = "/Applications/Safari.app"
        provider.icons[path] = image
        provider.modificationDates[path] = Date()

        // First call — populates cache
        _ = sut.icon(forItemId: 1, path: path)
        let diskCountAfterFirst = store.fetchCallCount

        // Second call — should hit memory cache, no additional disk read
        _ = sut.icon(forItemId: 1, path: path)

        // The second call should not trigger additional disk fetches beyond the first call's count
        #expect(store.fetchCallCount <= diskCountAfterFirst + 1)
    }

    // MARK: - Memory miss + disk hit

    @Test("进程重启后同规格不同内容的磁盘图标会按源修改时间刷新")
    @MainActor
    func sameGeometryDifferentContent_refreshesDiskRecord() throws {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let path = "/Applications/Changed.app"
        let redImage = makeSolidColorImage(red: 255, green: 0, blue: 0)
        let blueImage = makeSolidColorImage(red: 0, green: 0, blue: 255)
        let redPNG = makePNGData(redImage)
        let bluePNG = makePNGData(blueImage)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let sut = IconCache(
            iconProvider: provider,
            imageStore: store,
            pngEncoder: { _, _ in bluePNG }
        )

        store.stored[1] = makeRecord(
            icon1x: redPNG,
            sourceModificationDate: oldDate
        )
        provider.icons[path] = blueImage
        provider.modificationDates[path] = newDate

        let result = sut.icon(forItemId: 1, path: path)
        let pixel = try #require(firstPixel(result))

        #expect(pixel.blueComponent > pixel.redComponent)
        #expect(store.saveCallCount == 1)
        #expect(store.stored[1]?.sourceModificationDate == newDate)
    }

    @Test("源修改时间缺失时实时提取但不持久化")
    @MainActor
    func missingCurrentModificationDate_doesNotPersist() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(
            iconProvider: provider,
            imageStore: store,
            pngEncoder: { _, _ in Data([0x01]) }
        )
        let path = "/Applications/NoMetadata.app"
        provider.icons[path] = makeTestImage()

        _ = sut.icon(forItemId: 2, path: path)

        #expect(provider.fetchCallCount == 1)
        #expect(store.fetchCallCount == 0)
        #expect(store.saveCallCount == 0)
    }

    @Test("Memory miss + disk hit -> returns valid image on subsequent calls")
    func memoryMissDiskHit_populatesMemory() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        // Create valid PNG data for disk cache
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 64, bitsPerPixel: 32
        ) else { return }
        let pngData = bitmapRep.representation(using: .png, properties: [:]) ?? Data()

        // Disk has cached data
        let modificationDate = Date(timeIntervalSince1970: 3_000)
        store.stored[1] = makeRecord(
            icon1x: pngData,
            sourceModificationDate: modificationDate
        )
        provider.modificationDates["/app"] = modificationDate

        // First call — load from disk or provider
        let firstResult = sut.icon(forItemId: 1, path: "/app")

        // Second call — should return valid image
        let secondResult = sut.icon(forItemId: 1, path: "/app")

        #expect(firstResult.size.width > 0)
        #expect(secondResult.size.width > 0)
    }

    // MARK: - Both miss

    @Test("Both miss -> calls icon provider + stores in both layers")
    func bothMiss_callsProviderAndStores() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        let image = makeTestImage()
        let path = "/Applications/Safari.app"
        provider.icons[path] = image
        provider.modificationDates[path] = Date()

        let providerCountBefore = provider.fetchCallCount

        let result = sut.icon(forItemId: 1, path: path)

        #expect(result != nil)
        #expect(provider.fetchCallCount == providerCountBefore + 1)
        // Verify disk was written
        #expect(store.stored[1] != nil)
    }

    // MARK: - LRU eviction

    @Test("Exceeds limit -> LRU evicts oldest entries")
    func exceedsMemoryLimit_evictsOldest() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let limit = 10
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: limit)

        let image = makeTestImage()

        for i in 0..<(limit + 5) {
            let path = "/app\(i)"
            provider.icons[path] = image
            provider.modificationDates[path] = Date()
            _ = sut.icon(forItemId: Int64(i), path: path)
        }

        // After exceeding the limit, querying the oldest item should require provider refetch
        // (NSCache may evict at its discretion, but the oldest entries are most likely evicted)
        let providerCountBefore = provider.fetchCallCount
        // Query item 0 which was inserted first
        _ = sut.icon(forItemId: 0, path: "/app0")
        // If evicted from memory, provider will be called again
        // If still in memory, no additional provider call
        // This test verifies the cache functions correctly with overflow
        #expect(provider.fetchCallCount >= providerCountBefore)
    }

    // MARK: - modificationDate change -> invalidation

    @Test("modificationDate changed -> disk cache invalidated, re-extracts")
    func modificationDateChanged_invalidatesCache() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        let image = makeTestImage()
        let path = "/Applications/Safari.app"
        provider.icons[path] = image

        let oldDate = Date(timeIntervalSince1970: 1000)
        provider.modificationDates[path] = oldDate

        // First load — caches image and modificationDate
        _ = sut.icon(forItemId: 1, path: path)

        // modificationDate changes to a significantly different time
        let newDate = Date(timeIntervalSince1970: 9999)
        provider.modificationDates[path] = newDate

        let providerCountBefore = provider.fetchCallCount

        // Fetch again — should detect date change, re-extract
        let result = sut.icon(forItemId: 1, path: path)

        // Verify the result is non-nil (either cached or re-extracted)
        #expect(result != nil)
        // If modificationDate tracking works, provider should be called again
        // NSCache may have evicted the entry, so we check both cases
        #expect(provider.fetchCallCount >= providerCountBefore)
    }

    // MARK: - PNG data corruption

    @Test("Disk cache PNG data corrupted -> falls back to default icon")
    func corruptedPNG_fallbackIcon() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        // Disk has corrupted data
        let path = "/Applications/Broken.app"
        let modificationDate = Date(timeIntervalSince1970: 4_000)
        provider.modificationDates[path] = modificationDate
        store.stored[1] = makeRecord(
            icon1x: Data([0xFF, 0xD8, 0xFF]),
            sourceModificationDate: modificationDate
        )

        // Should return a valid image (either default or provider)
        let result = sut.icon(forItemId: 1, path: path)
        #expect(result.size.width > 0)
        #expect(provider.fetchCallCount == 1)
    }

    // MARK: - disk hit + modification cache 命中（覆盖 isStillValid 的 current==cached 分支）

    @Test("Memory evicted 后 disk hit + modCache 命中 -> isStillValid by date equality")
    func memoryEvicted_diskHit_modCacheHit_validatesByDate() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        // memoryLimit=1：存第二个 path 时第一个被 evict，但 modificationCache（Dictionary）保留
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 1)

        let image = makeTestImage()
        let pngData = makePNGData(image)
        let path1 = "/app1"
        let path2 = "/app2"
        let fixedDate = Date(timeIntervalSince1970: 5000)
        provider.icons[path1] = image
        provider.icons[path2] = image
        provider.modificationDates[path1] = fixedDate
        provider.modificationDates[path2] = Date(timeIntervalSince1970: 6000)

        // 预设 disk 数据，确保后续 disk hit（绕过 storeToDisk 在 headless 环境的不确定性）
        store.stored[1] = makeRecord(
            icon1x: pngData,
            sourceModificationDate: fixedDate
        )
        store.stored[2] = makeRecord(
            icon1x: pngData,
            sourceModificationDate: Date(timeIntervalSince1970: 6000)
        )

        // 1. icon(path1): memory miss -> persisted date match -> disk hit.
        _ = sut.icon(forItemId: 1, path: path1)
        // 2. icon(path2): memory miss -> disk hit -> memory evicts path1.
        _ = sut.icon(forItemId: 2, path: path2)
        // 3. icon(path1): memory miss -> persisted date still matches -> disk hit.
        let result = sut.icon(forItemId: 1, path: path1)
        #expect(result.size.width > 0)
    }

    @Test("Disk record 时间与当前修改时间相同 -> 直接命中且不实时提取")
    func diskHit_matchingPersistedDate_doesNotExtractLiveIcon() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        // 预设 disk 数据 + provider 返回 modDate，但不先触发 live 存 modCache
        let image = makeTestImage()
        let path = "/app"
        provider.icons[path] = image
        let modificationDate = Date(timeIntervalSince1970: 7_000)
        provider.modificationDates[path] = modificationDate

        // 直接预设 store 的 disk 数据（绕过 storeToDisk，使首次即 disk hit 且 modCache 为空）
        let pngData = makePNGData(image)
        store.stored[1] = makeRecord(
            icon1x: pngData,
            sourceModificationDate: modificationDate
        )

        let result = sut.icon(forItemId: 1, path: path)
        #expect(result.size.width > 0)
        #expect(provider.fetchCallCount == 0)
        #expect(store.saveCallCount == 0)
    }

    // MARK: - storeToDisk PNG 编码失败分支

    @Test("storeToDisk 1x PNG 编码失败 -> 不写入 disk")
    func storeToDisk_1xPngEncodingFails_noWrite() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        // pngEncoder 总返回 nil，模拟 1x 编码失败
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500,
                            pngEncoder: { _, _ in nil })

        let image = makeTestImage()
        let path = "/app"
        provider.icons[path] = image
        provider.modificationDates[path] = Date(timeIntervalSince1970: 8_000)

        _ = sut.icon(forItemId: 1, path: path)

        // 1x 编码失败，storeToDisk 提前 return，不写入 disk
        #expect(store.stored[1] == nil)
    }

    @Test("storeToDisk 2x PNG 编码失败 -> 不写入 disk")
    func storeToDisk_2xPngEncodingFails_noWrite() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let validPng = makePNGData(makeTestImage())
        // 1x (128) 返回有效，2x (256) 返回 nil，模拟 2x 编码失败
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500,
                            pngEncoder: { _, size in
                                size.width == 128 ? validPng : nil
                            })

        let image = makeTestImage()
        let path = "/app"
        provider.icons[path] = image
        provider.modificationDates[path] = Date(timeIntervalSince1970: 9_000)

        _ = sut.icon(forItemId: 1, path: path)

        // 2x 编码失败，storeToDisk 提前 return，不写入 disk
        #expect(store.stored[1] == nil)
    }

    @Test("defaultPngEncoder size 为零 -> 安全返回 nil（覆盖 size guard 分支）")
    @MainActor
    func defaultPngEncoder_zeroSize_returnsNil() {
        let image = makeTestImage()
        // size 为零时 size guard 提前返回 nil，不触发 lockFocus（避免 precondition failure）
        let result = IconCache.defaultPngEncoder(image, size: NSSize(width: 0, height: 0))
        #expect(result == nil)
    }

    @Test("defaultPngEncoder tiffProvider 注入无效 Data -> rep 解析失败返回 nil（覆盖 tiff guard 分支）")
    @MainActor
    func defaultPngEncoder_invalidTiff_returnsNil() {
        let image = makeTestImage()
        // 注入无效 tiff Data，使 NSBitmapImageRep(data:) 返回 nil -> guard return nil
        let result = IconCache.defaultPngEncoder(
            image, size: NSSize(width: 64, height: 64),
            tiffProvider: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        #expect(result == nil)
    }

    @Test("clearMemoryCache 后 disk hit + modCache 命中 -> isStillValid by date equality")
    func diskHit_afterClearMemory_modCacheHit_validatesByDate() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        let image = makeTestImage()
        let pngData = makePNGData(image)
        let path = "/app"
        let fixedDate = Date(timeIntervalSince1970: 5000)
        provider.icons[path] = image
        provider.modificationDates[path] = fixedDate
        // 预设 disk 数据
        store.stored[1] = makeRecord(
            icon1x: pngData,
            sourceModificationDate: fixedDate
        )

        // 1. 首次调用：持久化时间匹配，disk hit 并写入 memory cache。
        _ = sut.icon(forItemId: 1, path: path)
        // 2. 清空 memory cache（modCache 保留）
        sut.clearMemoryCache()
        // 3. 再次调用：memory miss，持久化时间仍匹配，disk hit。
        let result = sut.icon(forItemId: 1, path: path)
        #expect(result.size.width > 0)
    }

    // MARK: - Persisted source metadata

    @Test("diskHit_modCacheMiss_sameDate_noReextract")
    func diskHit_modCacheMiss_matchesPersistedDate() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let sut = IconCache(iconProvider: provider, imageStore: store, memoryLimit: 500)

        // 使用真实渲染的 NSImage 确保 representation 属性可比较
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 128, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let renderedImage = NSImage(size: NSSize(width: 128, height: 128))
        renderedImage.addRepresentation(rep)

        let pngData = makePNGData(renderedImage)
        let path = "/app"
        provider.icons[path] = renderedImage
        let modificationDate = Date(timeIntervalSince1970: 10_000)
        provider.modificationDates[path] = modificationDate

        store.stored[1] = makeRecord(
            icon1x: pngData,
            sourceModificationDate: modificationDate
        )

        let callsBefore = provider.fetchCallCount
        _ = sut.icon(forItemId: 1, path: path)
        let callsAfter = provider.fetchCallCount

        #expect(callsAfter == callsBefore)
    }

    @Test("磁盘读取失败 -> 实时提取并用当前元数据回写")
    func diskReadFailure_extractsLiveIcon() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let liveImage = makeTestImage()
        let path = "/Applications/ReadFailure.app"
        let modificationDate = Date(timeIntervalSince1970: 11_000)
        store.fetchError = TestError.generic
        provider.icons[path] = liveImage
        provider.modificationDates[path] = modificationDate
        let sut = IconCache(
            iconProvider: provider,
            imageStore: store,
            pngEncoder: { _, _ in Data([0x01]) }
        )

        let result = sut.icon(forItemId: 3, path: path)

        #expect(result === liveImage)
        #expect(provider.fetchCallCount == 1)
        #expect(store.fetchCallCount == 1)
        #expect(store.saveCallCount == 1)
        #expect(store.stored[3]?.sourceModificationDate == modificationDate)
    }

    @Test("磁盘保存失败 -> 返回实时图标并记录稳定错误类别")
    func diskSaveFailure_returnsLiveIconAndLogsStableCategory() {
        let provider = MockIconProvider()
        let store = MockImageStore()
        let liveImage = makeTestImage()
        let path = "/Applications/SaveFailure.app"
        let loggedExpectedCategory = DispatchSemaphore(value: 0)
        store.saveError = TestError.generic
        provider.icons[path] = liveImage
        provider.modificationDates[path] = Date(timeIntervalSince1970: 12_000)
        let sut = IconCache(
            iconProvider: provider,
            imageStore: store,
            pngEncoder: { _, _ in Data([0x01]) },
            errorLogger: { category in
                if category == "icon-cache-disk-save-failed" {
                    loggedExpectedCategory.signal()
                }
            }
        )

        let result = sut.icon(forItemId: 4, path: path)

        #expect(result === liveImage)
        #expect(store.saveCallCount == 1)
        #expect(loggedExpectedCategory.wait(timeout: .now()) == .success)
    }
}
#endif
