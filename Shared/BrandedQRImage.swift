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

    /// How much of the finished image's width must be blank down the leading
    /// edge, quiet zone included. Messages draws the app's icon over the
    /// top-left corner of a balloon, onto the finder pattern — the mark a
    /// scanner looks for first, and not something error correction recovers.
    ///
    /// The badge is a disc in that corner, so a leading margin wider than the
    /// badge clears it whatever its height, and the symbol needs no downward
    /// push at all: the image grows sideways and keeps every module of its
    /// height. Top, bottom and trailing keep the plain quiet zone.
    ///
    /// A fraction rather than a module count, because the badge is a fraction
    /// of the balloon while a card is anywhere from version 5 to 25.
    /// Everything but the balloon passes zero and gets a square, as before.
    static func cgImage(
        _ code: QRCode,
        pixelsPerModule: Int,
        quietZone: Int = 4,
        leadingInset: Double = 0
    ) -> CGImage? {
        guard let symbol = QRBitmap.cgImage(code, pixelsPerModule: pixelsPerModule, quietZone: quietZone) else {
            return nil
        }
        // The blank at the leading edge is the added modules plus the quiet
        // zone already there, over the finished width: f = (m + q) / (t + m),
        // so m = (f·t - q) / (1 - f).
        let fraction = min(max(leadingInset, 0), 0.5)
        let total = Double(code.size + 2 * quietZone)
        let modules = fraction > 0
            // Up, never down: the caller is promised a clear corner, and
            // half a module short of one is a symbol that does not scan.
            ? max(Int(((fraction * total - Double(quietZone)) / (1 - fraction)).rounded(.up)), 0)
            : 0
        guard modules > 0 else {
            return composite(code, onto: symbol, pixelsPerModule: pixelsPerModule, quietZone: quietZone,
                             offsetX: 0)
        }
        return inset(symbol, by: modules * pixelsPerModule).flatMap {
            composite(code, onto: $0, pixelsPerModule: pixelsPerModule, quietZone: quietZone,
                      offsetX: modules * pixelsPerModule)
        }
    }

    /// The symbol on a wider white canvas, pushed to the trailing edge so the
    /// blank is all down the leading one. The height does not change.
    private static func inset(_ symbol: CGImage, by pixels: Int) -> CGImage? {
        let width = symbol.width + pixels
        guard let context = context(width: width, height: symbol.height) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: symbol.height))
        context.draw(symbol, in: CGRect(x: pixels, y: 0, width: symbol.width, height: symbol.height))
        return context.makeImage()
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
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
        offsetX: Int
    ) -> CGImage? {
        guard let hole = QRLogo.hole(size: code.size) else { return symbol }
        guard let context = context(width: symbol.width, height: symbol.height) else { return symbol }
        context.draw(symbol, in: CGRect(x: 0, y: 0, width: symbol.width, height: symbol.height))

        // The hole in pixels, taken from the module range rather than from the
        // image's width: reading the module count back out of a bitmap needs
        // the scale and quiet zone it was drawn with, and gets it wrong the
        // moment either changes.
        let total = code.size + 2 * quietZone
        let clearedSide = hole.count * pixelsPerModule
        let left = (hole.lowerBound + quietZone) * pixelsPerModule + offsetX
        // Core Graphics counts from the bottom; the hole's top row is
        // `hole.lowerBound` from the top.
        let bottom = (total - hole.upperBound - quietZone) * pixelsPerModule

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
