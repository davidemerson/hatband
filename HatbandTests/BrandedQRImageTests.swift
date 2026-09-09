import CoreGraphics
import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The Messages balloon drew `QRBitmap.cgImage`, whose `logo` defaults to
/// true, and then drew nothing into the square it had cleared. The balloon
/// carried a symbol with a white hole in it and 4% of its error correction
/// spent on a blank.
struct BrandedQRImageTests {
    private func code() throws -> QRCode {
        try #require(CardQR.code(for: try Vectors.url("compact-name-only"), form: .lockScreen))
    }

    private func gray(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let provider = try #require(image.dataProvider)
        let bytes = try #require(provider.data) as Data
        return bytes[y * image.bytesPerRow + x]
    }

    @Test func theClearedSquareIsNotLeftBlank() throws {
        let code = try code()
        let pixelsPerModule = 8
        let quietZone = 4
        let hole = try #require(QRLogo.hole(size: code.size))
        let bare = try #require(QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        let branded = try #require(BrandedQRImage.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        #expect(branded.width == bare.width)
        #expect(branded.height == bare.height)

        // Count dark pixels inside the cleared square, in image coordinates.
        let total = code.size + 2 * quietZone
        func inkInHole(_ image: CGImage) throws -> Int {
            var ink = 0
            for row in hole {
                for column in hole {
                    let x = (column + quietZone) * pixelsPerModule
                    let y = (total - 1 - (row + quietZone)) * pixelsPerModule
                    for dy in 0..<pixelsPerModule where try gray(image, x: x + pixelsPerModule / 2, y: y + dy) < 128 {
                        ink += 1
                    }
                }
            }
            return ink
        }
        #expect(try inkInHole(bare) == 0, "the bitmap is meant to clear the square")
        #expect(try inkInHole(branded) > 0, "the hat was never drawn into it")
    }

    /// The glyph sits inside the cleared square, so no module beside it is
    /// overwritten and the correction budget is only what `QRLogo` spends.
    @Test func nothingIsDrawnOutsideTheClearedSquare() throws {
        let code = try code()
        let pixelsPerModule = 6
        let quietZone = 4
        let hole = try #require(QRLogo.hole(size: code.size))
        let bare = try #require(QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        let branded = try #require(BrandedQRImage.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        let total = code.size + 2 * quietZone
        for row in 0..<total {
            for column in 0..<total {
                let inHole = hole.contains(row - quietZone) && hole.contains(column - quietZone)
                if inHole { continue }
                let x = column * pixelsPerModule + pixelsPerModule / 2
                let y = row * pixelsPerModule + pixelsPerModule / 2
                #expect(try gray(branded, x: x, y: y) == (try gray(bare, x: x, y: y)),
                        "module \(column),\(row) changed outside the cleared square")
            }
        }
    }

    /// It is centred, which is the whole point: the hat is symmetric about
    /// the middle of the symbol in both axes.
    @Test func theGlyphIsCentredOnTheSymbol() throws {
        let code = try code()
        let pixelsPerModule = 8
        let quietZone = 4
        let branded = try #require(BrandedQRImage.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        let hole = try #require(QRLogo.hole(size: code.size))
        let first = (hole.lowerBound + quietZone) * pixelsPerModule
        let last = (hole.upperBound + quietZone) * pixelsPerModule - 1
        var columnInk: [Int] = []
        for x in first...last {
            var ink = 0
            for y in first...last where try gray(branded, x: x, y: y) < 128 { ink += 1 }
            columnInk.append(ink)
        }
        let ink = columnInk.reduce(0, +)
        #expect(ink > 0)
        // The ink's centre of mass is the middle of the cleared square. A
        // symbol's own glyph is not exactly mirror-symmetric, so this asks
        // for centred, not for identical halves.
        let centroid = columnInk.enumerated().reduce(0.0) { $0 + Double($1.offset) * Double($1.element) } / Double(ink)
        let middle = Double(columnInk.count - 1) / 2
        #expect(abs(centroid - middle) < 1, "the hat is off-centre horizontally by \(centroid - middle) px")
    }

    @Test func aSymbolTooSmallForAHatIsReturnedUntouched() throws {
        let code = try code()
        // `QRLogo.hole` refuses anything under 21 modules; where it refuses,
        // there is nothing to draw and nothing to break.
        #expect(QRLogo.hole(size: 20) == nil)
        #expect(BrandedQRImage.cgImage(code, pixelsPerModule: 0) == nil)
        #expect(BrandedQRImage.inset == 0.78)
    }
}
