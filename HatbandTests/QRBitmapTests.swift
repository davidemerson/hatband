import CoreGraphics
import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct QRBitmapTests {
    private let pixelsPerModule = 3

    private func code() throws -> QRCode {
        try #require(CardQR.code(for: try Vectors.url("compact-name-only"), form: .lockScreen))
    }

    private func gray(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let provider = try #require(image.dataProvider)
        let bytes = try #require(provider.data) as Data
        let index = y * image.bytesPerRow + x
        #expect(index < bytes.count)
        return bytes[index]
    }

    @Test func sizeIsModulesPlusQuietZone() throws {
        let code = try code()
        let image = try #require(QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule))
        #expect(image.width == (code.size + 8) * pixelsPerModule)
        #expect(image.height == (code.size + 8) * pixelsPerModule)
        #expect(image.bitsPerPixel == 8)
        #expect(image.bitsPerComponent == 8)

        let tight = try #require(QRBitmap.cgImage(code, pixelsPerModule: 2, quietZone: 0))
        #expect(tight.width == code.size * 2)
        #expect(QRBitmap.cgImage(code, pixelsPerModule: 0) == nil)
    }

    @Test func finderCornerIsBlack() throws {
        let code = try code()
        let image = try #require(QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule))
        let origin = 4 * pixelsPerModule
        // Top-left finder: dark corner, light ring, dark centre.
        #expect(try gray(image, x: origin, y: origin) == 0)
        #expect(try gray(image, x: origin + 1 * pixelsPerModule, y: origin + 1 * pixelsPerModule) == 255)
        #expect(try gray(image, x: origin + 3 * pixelsPerModule, y: origin + 3 * pixelsPerModule) == 0)
        // Top-right finder corner, which proves rows are not mirrored.
        let right = (4 + code.size - 1) * pixelsPerModule
        #expect(try gray(image, x: right, y: origin) == 0)
        // Bottom-left finder corner.
        let bottom = (4 + code.size - 1) * pixelsPerModule
        #expect(try gray(image, x: origin, y: bottom) == 0)
        // Bottom-right has no finder: its corner module is light.
        #expect(try gray(image, x: right, y: bottom) == 255)
    }

    @Test func quietZoneIsWhite() throws {
        let code = try code()
        let image = try #require(QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule))
        #expect(try gray(image, x: 0, y: 0) == 255)
        #expect(try gray(image, x: image.width - 1, y: image.height - 1) == 255)
        #expect(try gray(image, x: image.width - 1, y: 0) == 255)
        #expect(try gray(image, x: 0, y: image.height - 1) == 255)
        // The last quiet-zone pixel before the finder is still light.
        let edge = 4 * pixelsPerModule - 1
        #expect(try gray(image, x: edge, y: edge) == 255)
    }
}
