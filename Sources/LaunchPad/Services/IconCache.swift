import Foundation
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit
#endif

/// Two-layer icon cache — memory NSCache + disk SQLite
///
/// Lookup order: memory -> disk -> IconProvider (live extraction).
/// After extraction, stores in both layers simultaneously.
///
/// Thread safety: This class is marked `@unchecked Sendable` because NSCache
/// does not declare Sendable conformance but is internally thread-safe (uses locks).
#if canImport(AppKit)
public final class IconCache: IconCaching, @unchecked Sendable {

    private let iconProvider: IconProviding
    private let imageStore: ImageStoring
    private let memoryCache: NSCache<NSString, NSImage>
    // modification date 是小对象，用带锁 Dictionary 保证行为确定（NSCache 在测试环境会积极 evict，导致缓存命中分支不可测）
    private var modificationDates: [String: Date] = [:]
    private let modLock = NSLock()
    /// PNG 编码器（可注入，测试用于模拟编码失败覆盖 guard return 分支）
    private let pngEncoder: (NSImage, NSSize) -> Data?

    /// Create icon cache
    ///
    /// - Parameters:
    ///   - iconProvider: Icon extraction provider
    ///   - imageStore: Disk storage
    ///   - memoryLimit: Memory cache entry limit, default 500
    ///   - pngEncoder: PNG 编码器（测试注入 nil 模拟编码失败）
    public init(
        iconProvider: IconProviding,
        imageStore: ImageStoring,
        memoryLimit: Int = 500,
        pngEncoder: ((NSImage, NSSize) -> Data?)? = nil
    ) {
        self.iconProvider = iconProvider
        self.imageStore = imageStore
        self.memoryCache = NSCache<NSString, NSImage>()
        self.memoryCache.countLimit = memoryLimit
        self.pngEncoder = pngEncoder ?? { image, size in
            IconCache.defaultPngEncoder(image, size: size)
        }
    }

    /// 默认 PNG 编码：lockFocus 缩放后转 PNG（internal 以便测试覆盖 guard 失败分支）
    /// - Parameter tiffProvider: 测试注入，返回 nil 模拟 tiff 转换失败
    static func defaultPngEncoder(
        _ image: NSImage,
        size: NSSize,
        tiffProvider: ((NSImage) -> Data?)? = nil
    ) -> Data? {
        // size 为零时 lockFocus 会 precondition failure，提前返回
        guard size.width > 0, size.height > 0 else { return nil }
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        scaled.unlockFocus()
        let tiff = tiffProvider?(scaled) ?? scaled.tiffRepresentation
        guard let tiff,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
    }

    // MARK: - Modification date cache helpers

    private func cachedModDate(for path: String) -> Date? {
        modLock.lock()
        defer { modLock.unlock() }
        return modificationDates[path]
    }

    private func setCachedModDate(_ date: Date, for path: String) {
        modLock.lock()
        defer { modLock.unlock() }
        modificationDates[path] = date
    }

    private func removeCachedModDate(for path: String) {
        modLock.lock()
        defer { modLock.unlock() }
        modificationDates.removeValue(forKey: path)
    }

    /// 测试用：清空 memory cache 但保留 modification cache，以触发 disk hit + modCache 命中分支
    internal func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// Fetch icon — memory cache first, then disk cache, then live extraction
    ///
    /// - Parameters:
    ///   - itemId: Database item ID
    ///   - path: Application path
    /// - Returns: Icon image, returns default NSApplicationIcon on failure
    public func icon(forItemId itemId: Int64, path: String) -> NSImage {
        let cacheKey = NSString(string: path)

        // 1. Check memory cache
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            // Verify modificationDate hasn't changed
            let currentModDate = iconProvider.modificationDate(forPath: path)
            let cachedModDate = self.cachedModDate(for: path)

            if let current = currentModDate, let cached = cachedModDate, current == cached {
                return cachedImage
            }
            // modificationDate changed, evict cache
            memoryCache.removeObject(forKey: cacheKey)
            removeCachedModDate(for: path)
        }

        // 2. Check disk cache
        if let diskData = try? imageStore.fetchImage(itemId: itemId) {
            let currentModDate = iconProvider.modificationDate(forPath: path)
            if let image = NSImage(data: diskData.0) {
                // Check if disk cache is still valid
                let cachedModDate = self.cachedModDate(for: path)
                let isStillValid: Bool
                if let current = currentModDate {
                    if let cached = cachedModDate {
                        isStillValid = (current == cached)
                    } else {
                        // Modification cache evicted — compare disk icon against live icon
                        // Both go through tiffRepresentation for format consistency (fixes P2-5)
                        let liveIcon = iconProvider.icon(forPath: path)
                        if let decodedDiskImage = NSImage(data: diskData.0) {
                            let diskRep = decodedDiskImage.representations.first
                            let liveRep = liveIcon.representations.first
                            isStillValid = (diskRep?.pixelsWide == liveRep?.pixelsWide
                                && diskRep?.pixelsHigh == liveRep?.pixelsHigh
                                && diskRep?.bitsPerSample == liveRep?.bitsPerSample)
                        } else {
                            isStillValid = false
                        }
                    }
                } else {
                    // No current modification date available, assume disk data is valid
                    isStillValid = true
                }

                if isStillValid {
                    // Disk data valid, populate memory cache and return
                    memoryCache.setObject(image, forKey: cacheKey)
                    if let modDate = currentModDate {
                        setCachedModDate(modDate, for: path)
                    }
                    return image
                }
                // Disk data invalid (modificationDate changed), continue to provider
            }
            // PNG corrupted, continue to provider
        }

        // 3. Live extraction from provider
        let image = iconProvider.icon(forPath: path)

        // Store in memory cache
        memoryCache.setObject(image, forKey: cacheKey)
        if let modDate = iconProvider.modificationDate(forPath: path) {
            setCachedModDate(modDate, for: path)
        }

        // Store in disk cache
        storeToDisk(image: image, itemId: itemId)

        return image
    }

    /// Write image to disk cache
    private func storeToDisk(image: NSImage, itemId: Int64) {
        // @1x: 128×128pt
        guard let png1x = pngEncoder(image, NSSize(width: 128, height: 128)) else {
            return
        }

        // @2x: 256×256px
        guard let png2x = pngEncoder(image, NSSize(width: 256, height: 256)) else {
            return
        }

        try? imageStore.saveImage(itemId: itemId, icon1x: png1x, icon2x: png2x)
    }
}
#endif
