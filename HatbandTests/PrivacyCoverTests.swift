import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Hatband

/// `privacyCovered()` is what every presented sheet wears, since a sheet
/// sits above `RootView` and its cover. Rendered through `ImageRenderer`,
/// a red square must vanish under the cover while the scene is inactive
/// and show through otherwise.
@MainActor struct PrivacyCoverTests {
    private struct Pixel {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    private func centrePixel(covered: Bool) throws -> Pixel {
        let model = try AppModel.inMemory()
        model.covered = covered
        let view = Color.red
            .frame(width: 60, height: 60)
            .privacyCovered()
            .environment(model)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return try PrivacyCoverTests.pixel(of: image, x: image.width / 2, y: image.height / 2)
    }

    /// Draws the image so that pixel (x, y), counted from the top left,
    /// lands on a one-pixel RGBA context.
    private static func pixel(of image: CGImage, x: Int, y: Int) throws -> Pixel {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        let origin = CGPoint(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y))
        context.draw(image, in: CGRect(origin: origin, size: CGSize(width: image.width, height: image.height)))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Pixel(red: bytes[0], green: bytes[1], blue: bytes[2])
    }

    @Test func coveredHidesContent() throws {
        let pixel = try centrePixel(covered: true)
        // The cover is neutral: the ground grey, or the grey glyph on it.
        #expect(abs(Int(pixel.red) - Int(pixel.green)) < 24)
        #expect(abs(Int(pixel.green) - Int(pixel.blue)) < 24)
        #expect(pixel.red < 250)
    }

    @Test func uncoveredShowsContent() throws {
        let pixel = try centrePixel(covered: false)
        #expect(pixel.red > 200)
        #expect(pixel.green < 120)
        #expect(pixel.blue < 120)
    }
}
