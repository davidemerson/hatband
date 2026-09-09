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

    /// What the Messages balloon actually draws. Twice the modules of the
    /// Lock Screen form, and the size every one of these tests missed.
    private func fullCode() throws -> QRCode {
        try #require(CardQR.code(for: try Vectors.url("typical-signed"), form: .fullQR))
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

    /// The balloon's own form and scale, which nothing covered before.
    @Test func theBalloonsFormComposites() throws {
        let code = try fullCode()
        let pixelsPerModule = 8
        let quietZone = 4
        let hole = try #require(QRLogo.hole(size: code.size))
        let bare = try #require(QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        let branded = try #require(BrandedQRImage.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        #expect(branded.width == bare.width)
        // Same format as the bitmap it replaces: Messages was handed one of
        // these before and must be handed the same kind now.
        #expect(branded.bitsPerComponent == bare.bitsPerComponent)
        #expect(branded.bitsPerPixel == bare.bitsPerPixel)
        #expect(branded.bytesPerRow == bare.bytesPerRow)
        #expect(branded.alphaInfo == bare.alphaInfo)
        #expect(branded.colorSpace?.model == bare.colorSpace?.model)
        let total = code.size + 2 * quietZone
        var ink = 0
        for row in hole {
            for column in hole {
                let x = (column + quietZone) * pixelsPerModule + pixelsPerModule / 2
                let y = (total - 1 - (row + quietZone)) * pixelsPerModule + pixelsPerModule / 2
                if try gray(branded, x: x, y: y) < 128 { ink += 1 }
            }
        }
        #expect(ink > 0, "no hat at the balloon's own size")
    }

    /// Messages draws its app-icon badge over the top-left corner of a
    /// balloon's image, straight onto the finder pattern, and a covered finder
    /// is not something error correction recovers: the symbol simply will not
    /// scan. The badge is a disc in that corner, so a leading margin wider
    /// than it clears it at any height and the symbol keeps its full height.
    @Test func theLeadingMarginClearsTheBadgeAndKeepsTheHeight() throws {
        let code = try fullCode()
        let pixelsPerModule = 8
        let quietZone = 4
        let fraction = 0.20
        let plain = try #require(BrandedQRImage.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone))
        let inset = try #require(BrandedQRImage.cgImage(
            code, pixelsPerModule: pixelsPerModule, quietZone: quietZone, leadingInset: fraction))
        // Wider, and not one pixel shorter: the whole point of a margin on one
        // side is that the symbol gives up nothing in the other direction.
        #expect(inset.height == plain.height)
        #expect(inset.width > plain.width)

        // The leading edge is blank for the whole fraction asked for, top to
        // bottom, quiet zone included.
        let margin = Int(Double(inset.width) * fraction)
        for x in stride(from: 0, to: margin, by: pixelsPerModule) {
            for y in stride(from: 0, to: inset.height, by: pixelsPerModule * 4) {
                #expect(try gray(inset, x: x, y: y) == 255, "ink at \(x),\(y) under the badge")
            }
        }

        // And every module still says what it said, moved sideways only.
        let shift = inset.width - plain.width
        let total = code.size + 2 * quietZone
        for row in stride(from: 0, to: total, by: 3) {
            for column in stride(from: 0, to: total, by: 3) {
                let x = column * pixelsPerModule + pixelsPerModule / 2
                let y = row * pixelsPerModule + pixelsPerModule / 2
                #expect(try gray(inset, x: x + shift, y: y) == (try gray(plain, x: x, y: y)),
                        "module \(column),\(row) changed")
            }
        }
    }

    /// The default is no inset, so the Lock Screen and the widget are untouched.
    @Test func nothingElseGainsAnInset() throws {
        let code = try code()
        let plain = try #require(BrandedQRImage.cgImage(code, pixelsPerModule: 4))
        let zero = try #require(BrandedQRImage.cgImage(code, pixelsPerModule: 4, leadingInset: 0))
        #expect(plain.width == zero.width)
        #expect(plain.width == (code.size + 8) * 4)
        #expect(plain.width == plain.height, "still square")
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
