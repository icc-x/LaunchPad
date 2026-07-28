import Foundation

/// A disk-cached icon and the source timestamp used to validate it.
public struct CachedImageRecord: Sendable, Equatable {
    public let icon1x: Data
    public let icon2x: Data
    public let sourceModificationDate: Date

    public init(
        icon1x: Data,
        icon2x: Data,
        sourceModificationDate: Date
    ) {
        self.icon1x = icon1x
        self.icon2x = icon2x
        self.sourceModificationDate = sourceModificationDate
    }
}
