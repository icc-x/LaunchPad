import AppKit
import Foundation
import os
import Testing
@testable import LaunchPad

@MainActor
@Suite("IconRasterEncoder")
struct IconRasterEncoderTests {
    private func makeTIFFData(size: Int = 24) throws -> Data {
        let representation = try #require(NSBitmapImageRep(
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
        ))
        let bitmap = try #require(representation.bitmapData)
        for y in 0..<size {
            for x in 0..<size {
                let offset = y * representation.bytesPerRow + x * 4
                bitmap[offset] = 255
                bitmap[offset + 1] = 0
                bitmap[offset + 2] = 0
                bitmap[offset + 3] = 255
            }
        }
        return try #require(representation.tiffRepresentation)
    }

    @Test("TIFF 解码、缩放和 PNG 编码均在非主线程并生成精确尺寸")
    func encodingRunsOffMainThreadAndProducesRequestedSize() async throws {
        let flags = OSAllocatedUnfairLock(initialState: [Bool]())
        let encoder = IconRasterEncoder { isMainThread in
            flags.withLock { $0.append(isMainThread) }
        }

        let png = try #require(await encoder.pngData(
            fromTIFF: makeTIFFData(),
            pixelSize: 128
        ))
        let representation = try #require(NSBitmapImageRep(data: png))

        #expect(flags.withLock { $0 } == [false])
        #expect(representation.pixelsWide == 128)
        #expect(representation.pixelsHigh == 128)
    }

    @Test("无效 TIFF 与非正尺寸均返回 nil")
    func invalidInputsReturnNil() async {
        let encoder = IconRasterEncoder()

        #expect(await encoder.pngData(fromTIFF: Data([0x00]), pixelSize: 128) == nil)
        #expect(await encoder.pngData(fromTIFF: Data(), pixelSize: 0) == nil)
    }

    @Test("缩放后保留输入像素颜色")
    func encodingPreservesPixelContent() async throws {
        let encoder = IconRasterEncoder()
        let tiff = try makeTIFFData(size: 8)
        let source = try #require(NSBitmapImageRep(data: tiff))
        let sourceColor = try #require(
            source.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB)
        )

        let png = try #require(await encoder.pngData(
            fromTIFF: tiff,
            pixelSize: 64
        ))
        let representation = try #require(NSBitmapImageRep(data: png))
        let color = try #require(
            representation.colorAt(x: 32, y: 32)?.usingColorSpace(.sRGB)
        )

        #expect(abs(color.redComponent - sourceColor.redComponent) < 0.01)
        #expect(abs(color.greenComponent - sourceColor.greenComponent) < 0.01)
        #expect(abs(color.blueComponent - sourceColor.blueComponent) < 0.01)
        #expect(abs(color.alphaComponent - sourceColor.alphaComponent) < 0.01)
    }
}
