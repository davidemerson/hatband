import CoreGraphics
import HatbandCore
import UIKit

/// A symbol as a bitmap with the hat drawn into the square `QRBitmap` clears
/// for it. `BrandedQR` does the same thing as a view; anything that needs
/// pixels — a Messages balloon, a widget — needs this instead, because a
/// bitmap with the hole punched and nothing in it is a symbol that has given
/// up 4% of its error correction for a blank.
nonisolated enum BrandedQRImage {
    /// How much of the cleared square the glyph takes, leaving white around
    /// it so the modules beside it are not crowded. `BrandedQR` uses the same.
    static let inset = 0.78

    /// Blank space at the top and the leading edge, as a fraction of the
    /// finished image, on top of the quiet zone. Messages draws the app's icon
    /// over the top-left corner of a balloon's image and it lands on the finder
    /// pattern — the one part of a symbol a scanner cannot do without, and not
    /// something error correction recovers. A fraction rather than a module
    /// count because the badge is a fraction of the balloon and a card is
    /// anywhere from version 5 to 25. Everything else passes zero and gets the
    /// symbol centred, as before.
    static func cgImage(
        _ code: QRCode,
        pixelsPerModule: Int,
        quietZone: Int = 4,
        topLeadingInset: Double = 0
    ) -> CGImage? {
        guard let symbol = QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone) else {
            return nil
        }
        // The inset is a fraction of the finished side, and the symbol is the
        // rest of it: f = d / (q + d), so d = q · f / (1 - f).
        let fraction = min(max(topLeadingInset, 0), 0.5)
        let modules = fraction > 0
            ? Int((Double(code.size + 2 * quietZone) * fraction / (1 - fraction)).rounded())
            : 0
        guard modules > 0 else {
            return composite(code, onto: symbol, pixelsPerModule: pixelsPerModule, quietZone: quietZone,
                             offsetX: 0, offsetY: 0)
        }
        return inset(symbol, by: modules * pixelsPerModule).flatMap {
            composite(code, onto: $0, pixelsPerModule: pixelsPerModule, quietZone: quietZone,
                      offsetX: modules * pixelsPerModule, offsetY: 0)
        }
    }

    /// The symbol on a larger white square, pushed to the bottom-right so the
    /// blank is at the top and the leading edge. Core Graphics counts from the
    /// bottom, so "top" is the far end of y.
    private static func inset(_ symbol: CGImage, by pixels: Int) -> CGImage? {
        let side = symbol.width + pixels
        guard let context = context(side: side) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(symbol, in: CGRect(x: pixels, y: 0, width: symbol.width, height: symbol.height))
        return context.makeImage()
    }

    private static func context(side: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
    }

    private static func composite(
        _ code: QRCode,
        onto symbol: CGImage,
        pixelsPerModule: Int,
        quietZone: Int,
        offsetX: Int,
        offsetY: Int
    ) -> CGImage? {
        guard let hole = QRLogo.hole(size: code.size) else { return symbol }
        let side = symbol.width
        guard let context = context(side: side) else { return symbol }
        context.draw(symbol, in: CGRect(x: 0, y: 0, width: side, height: side))

        // The hole in pixels, taken from the module range rather than from the
        // image's width: reading the module count back out of a bitmap needs
        // the scale and quiet zone it was drawn with, and gets it wrong the
        // moment either changes.
        let total = code.size + 2 * quietZone
        let clearedSide = hole.count * pixelsPerModule
        let left = (hole.lowerBound + quietZone) * pixelsPerModule + offsetX
        // Core Graphics counts from the bottom; the hole's top row is
        // `hole.lowerBound` from the top.
        let bottom = (total - hole.upperBound - quietZone) * pixelsPerModule + offsetY

        // Whole pixels, and a side of the same parity as the square it sits
        // in, so the margin is the same integer on both sides. A fractional
        // rect lands the glyph half a pixel off and the hat reads as crooked.
        var boxSide = Int(Double(clearedSide) * inset)
        if boxSide % 2 != clearedSide % 2 { boxSide -= 1 }
        guard boxSide > 0 else { return symbol }
        let margin = (clearedSide - boxSide) / 2
        let glyph = CGRect(x: left + margin, y: bottom + margin, width: boxSide, height: boxSide)
        let box = CGFloat(boxSide)

        guard let hat = hatImage(side: box) else { return symbol }
        context.draw(hat, in: glyph)
        return context.makeImage() ?? symbol
    }

    /// The symbol as black pixels on white, at the size it will be drawn.
    private static func hatImage(side: CGFloat) -> CGImage? {
        guard side > 0, let hat = UIImage(systemName: Theme.hat) else { return nil }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side, height: side)
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, width: side, height: side))
            let fitted = hat.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: side, weight: .regular))
            let aspect = fitted.size.width > 0 ? fitted.size.height / fitted.size.width : 1
            let width = aspect > 1 ? side / aspect : side
            let height = aspect > 1 ? side : side * aspect
            fitted.withTintColor(.black, renderingMode: .alwaysOriginal).draw(
                in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        }
        return drawn.cgImage
    }
}

private extension CGRect {
    init(origin: CGPoint, width: CGFloat, height: CGFloat) {
        self.init(origin: origin, size: CGSize(width: width, height: height))
    }
}
