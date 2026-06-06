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
final class IconCache: @unchecked Sendable {

    private let iconProvider: IconProviding
    private let imageStore: ImageStoring
    private let memoryCache: NSCache<NSString, NSImage>
    private let modificationCache: NSCache<NSString, NSDate>

    /// Create icon cache
    ///
    /// - Parameters:
    ///   - iconProvider: Icon extraction provider
    ///   - imageStore: Disk storage
    ///   - memoryLimit: Memory cache entry limit, default 500
    init(
        iconProvider: IconProviding,
        imageStore: ImageStoring,
        memoryLimit: Int = 500
    ) {
        self.iconProvider = iconProvider
        self.imageStore = imageStore
        self.memoryCache = NSCache<NSString, NSImage>()
        self.memoryCache.countLimit = memoryLimit
        self.modificationCache = NSCache<NSString, NSDate>()
        self.modificationCache.countLimit = memoryLimit
    }

    /// Fetch icon — memory cache first, then disk cache, then live extraction
    ///
    /// - Parameters:
    ///   - itemId: Database item ID
    ///   - path: Application path
    /// - Returns: Icon image, returns default NSApplicationIcon on failure
    func icon(forItemId itemId: Int64, path: String) -> NSImage {
        let cacheKey = NSString(string: path)

        // 1. Check memory cache
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            // Verify modificationDate hasn't changed
            let currentModDate = iconProvider.modificationDate(forPath: path)
            let cachedModDate = modificationCache.object(forKey: cacheKey) as Date?

            if let current = currentModDate, let cached = cachedModDate, current == cached {
                return cachedImage
            }
            // modificationDate changed, evict cache
            memoryCache.removeObject(forKey: cacheKey)
            modificationCache.removeObject(forKey: cacheKey)
        }

        // 2. Check disk cache
        if let diskData = try? imageStore.fetchImage(itemId: itemId) {
            let currentModDate = iconProvider.modificationDate(forPath: path)
            if let image = NSImage(data: diskData.0) {
                // Check if disk cache is still valid
                let cachedModDate = modificationCache.object(forKey: cacheKey) as Date?
                let isStillValid: Bool
                if let current = currentModDate {
                    if let cached = cachedModDate {
                        isStillValid = (current == cached)
                    } else {
                        // Modification cache evicted — compare disk icon against live icon
                        let liveIcon = iconProvider.icon(forPath: path)
                        let liveData = liveIcon.tiffRepresentation ?? Data()
                        isStillValid = (diskData.0 == liveData)
                    }
                } else {
                    // No current modification date available, assume disk data is valid
                    isStillValid = true
                }

                if isStillValid {
                    // Disk data valid, populate memory cache and return
                    memoryCache.setObject(image, forKey: cacheKey)
                    if let modDate = currentModDate {
                        modificationCache.setObject(
                            NSDate(timeIntervalSince1970: modDate.timeIntervalSince1970),
                            forKey: cacheKey
                        )
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
            modificationCache.setObject(NSDate(timeIntervalSince1970: modDate.timeIntervalSince1970), forKey: cacheKey)
        }

        // Store in disk cache
        storeToDisk(image: image, itemId: itemId)

        return image
    }

    /// Write image to disk cache
    private func storeToDisk(image: NSImage, itemId: Int64) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png1x = rep.representation(using: .png, properties: [:]) else {
            return
        }

        // @2x: 256x256px
        let size2x = NSSize(width: 256, height: 256)
        let image2x = NSImage(size: size2x)
        image2x.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size2x),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        image2x.unlockFocus()

        guard let tiff2x = image2x.tiffRepresentation,
              let rep2x = NSBitmapImageRep(data: tiff2x),
              let png2x = rep2x.representation(using: .png, properties: [:]) else {
            return
        }

        try? imageStore.saveImage(itemId: itemId, icon1x: png1x, icon2x: png2x)
    }
}
#endif
