import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

protocol IconRasterEncoding: Sendable {
    func pngData(fromTIFF data: Data, pixelSize: Int) async -> Data?
}

/// Converts immutable TIFF bytes into a fixed-size PNG without using AppKit.
actor IconRasterEncoder: IconRasterEncoding {
    private let threadObserver: @Sendable (Bool) -> Void

    init(threadObserver: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.threadObserver = threadObserver
    }

    func pngData(fromTIFF data: Data, pixelSize: Int) -> Data? {
        threadObserver(Thread.isMainThread)
        guard pixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        )
        guard let scaledImage = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaledImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
