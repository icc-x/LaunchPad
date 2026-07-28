import Foundation
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit

/// Two-layer icon cache with MainActor AppKit access and background disk work.
@MainActor
public final class IconCache: IconCaching {
    private enum DiskFetchResult: Sendable {
        case value(CachedImageRecord?)
        case failure
    }

    private let iconProvider: any IconProviding
    private let imageStore: any ImageStoring
    private let rasterEncoder: any IconRasterEncoding
    private let memoryCache: NSCache<NSString, NSImage>
    private var modificationDates: [String: Date] = [:]
    private let errorLogger: @Sendable (String) -> Void

    static let diskSaveFailureCategory = "icon-cache-disk-save-failed"

    public convenience init(
        iconProvider: any IconProviding,
        imageStore: any ImageStoring,
        memoryLimit: Int = 500,
        errorLogger: @escaping @Sendable (String) -> Void = {
            NSLog("[IconCache] %@", $0)
        }
    ) {
        self.init(
            iconProvider: iconProvider,
            imageStore: imageStore,
            memoryLimit: memoryLimit,
            rasterEncoder: IconRasterEncoder(),
            errorLogger: errorLogger
        )
    }

    init(
        iconProvider: any IconProviding,
        imageStore: any ImageStoring,
        memoryLimit: Int = 500,
        rasterEncoder: any IconRasterEncoding,
        errorLogger: @escaping @Sendable (String) -> Void = {
            NSLog("[IconCache] %@", $0)
        }
    ) {
        self.iconProvider = iconProvider
        self.imageStore = imageStore
        self.rasterEncoder = rasterEncoder
        self.memoryCache = NSCache<NSString, NSImage>()
        self.memoryCache.countLimit = memoryLimit
        self.errorLogger = errorLogger
    }

    internal func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    @discardableResult
    public func loadIcon(
        forItemId itemId: Int64,
        path: String,
        completion: @escaping @MainActor @Sendable (Int64, NSImage) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let cacheKey = NSString(string: path)
            let iconProvider = self.iconProvider
            let currentModificationDate = await Task.detached(
                priority: .userInitiated
            ) {
                iconProvider.modificationDate(forPath: path)
            }.value
            guard !Task.isCancelled else { return }

            if let cachedImage = memoryCache.object(forKey: cacheKey) {
                if let currentModificationDate,
                   modificationDates[path] == currentModificationDate {
                    guard !Task.isCancelled else { return }
                    completion(itemId, cachedImage)
                    return
                }
                memoryCache.removeObject(forKey: cacheKey)
                modificationDates.removeValue(forKey: path)
            }

            if let currentModificationDate {
                let imageStore = self.imageStore
                let diskResult = await Task.detached(priority: .userInitiated) {
                    do {
                        return DiskFetchResult.value(
                            try imageStore.fetchImage(itemId: itemId)
                        )
                    } catch {
                        return DiskFetchResult.failure
                    }
                }.value
                guard !Task.isCancelled else { return }
                if case .value(let record) = diskResult,
                   let record,
                   record.sourceModificationDate == currentModificationDate,
                   let image = NSImage(data: record.icon1x) {
                    memoryCache.setObject(image, forKey: cacheKey)
                    modificationDates[path] = currentModificationDate
                    completion(itemId, image)
                    return
                }
            }

            guard !Task.isCancelled else { return }
            let image = iconProvider.icon(forPath: path)
            guard !Task.isCancelled else { return }
            memoryCache.setObject(image, forKey: cacheKey)
            if let currentModificationDate {
                modificationDates[path] = currentModificationDate
            }
            completion(itemId, image)

            guard let currentModificationDate,
                  !Task.isCancelled,
                  let tiffData = image.tiffRepresentation else {
                return
            }
            guard let png1x = await rasterEncoder.pngData(
                fromTIFF: tiffData,
                pixelSize: 128
            ), !Task.isCancelled else {
                return
            }
            guard let png2x = await rasterEncoder.pngData(
                fromTIFF: tiffData,
                pixelSize: 256
            ), !Task.isCancelled else {
                return
            }

            let record = CachedImageRecord(
                icon1x: png1x,
                icon2x: png2x,
                sourceModificationDate: currentModificationDate
            )
            let imageStore = self.imageStore
            let saved = await Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return true }
                do {
                    try imageStore.saveImage(itemId: itemId, record: record)
                    return true
                } catch {
                    return false
                }
            }.value
            guard !Task.isCancelled else { return }
            if !saved {
                errorLogger(Self.diskSaveFailureCategory)
            }
        }
    }
}
#endif
