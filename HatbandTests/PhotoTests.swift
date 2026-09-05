import CoreGraphics
import Foundation
import HatbandCore
import Testing
import UIKit
@testable import Hatband

@MainActor struct PhotoTests {
    /// A red-to-blue diagonal gradient, `side` pixels square, as PNG.
    private func gradientPNG(side: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { context in
            let colors = [UIColor.red.cgColor, UIColor.blue.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
        }
    }

    /// Whether `FF xx` appears as a marker. Inside entropy-coded data every
    /// `FF` is followed by `00` or a restart marker, so a plain scan is exact.
    private func containsMarker(_ marker: UInt8, in bytes: [UInt8]) -> Bool {
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 0xFF, bytes[index + 1] == marker {
                return true
            }
            index += 1
        }
        return false
    }

    @Test func thumbnailWithinLimits() throws {
        let source = gradientPNG(side: 1000)
        #expect(UIImage(data: source)?.size.width == 1000)
        let bytes = try #require(Photo.thumbnailJPEG(from: source))
        #expect(bytes.count <= 12_288)
        #expect(bytes.count <= Photo.maxBytes)
        #expect(bytes.prefix(2) == [0xFF, 0xD8])
        #expect(bytes.suffix(2) == [0xFF, 0xD9])
        let image = try #require(UIImage(data: Data(bytes)))
        #expect(image.size.width <= 256)
        #expect(image.size.height <= 256)
        #expect(image.size.width >= 32)
        #expect(FieldValidator.photo(byteCount: bytes.count, limits: .file).isAccepted)
        #expect(Photo.thumbnailJPEG(from: Data([1, 2, 3])) == nil)
        #expect(Photo.thumbnailJPEG(from: Data()) == nil)
    }

    @Test func noAPP1Segment() throws {
        let bytes = try #require(Photo.thumbnailJPEG(from: gradientPNG(side: 1000)))
        #expect(!containsMarker(0xE1, in: bytes))
        #expect(!containsMarker(0xFE, in: bytes))
        // The stripper itself: APP0 and DQT stay, APP1 and COM go, the scan is untouched.
        let synthetic: [UInt8] = [
            0xFF, 0xD8,
            0xFF, 0xE0, 0, 4, 1, 2,
            0xFF, 0xE1, 0, 5, 0x45, 0x78, 0x69,
            0xFF, 0xFE, 0, 3, 0x41,
            0xFF, 0xDB, 0, 3, 9,
            0xFF, 0xDA, 0, 2,
            0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD9,
        ]
        let expected: [UInt8] = [
            0xFF, 0xD8,
            0xFF, 0xE0, 0, 4, 1, 2,
            0xFF, 0xDB, 0, 3, 9,
            0xFF, 0xDA, 0, 2,
            0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD9,
        ]
        #expect(Photo.strippingMetadata(synthetic) == expected)
        #expect(Photo.strippingMetadata(expected) == expected)
        #expect(Photo.strippingMetadata([1, 2, 3]) == [1, 2, 3])
        // A segment whose length overruns the data is left alone rather than truncated.
        let overrun: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 1]
        #expect(Photo.strippingMetadata(overrun) == overrun)
    }
}
