import CoreGraphics
import Foundation
import HatbandCore

/// A QR symbol as an 8-bit gray bitmap, one byte per pixel, for the Home
/// Screen widget. Row 0 of the symbol is the top row of the image.
nonisolated enum QRBitmap {
    static func cgImage(_ code: QRCode, pixelsPerModule: Int, quietZone: Int = 4) -> CGImage? {
        guard pixelsPerModule > 0, quietZone >= 0 else { return nil }
        let total = code.size + 2 * quietZone
        let side = total * pixelsPerModule
        guard side > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: 0, alpha: 1)
        // Core Graphics puts the origin at the bottom-left, so symbol row y
        // is drawn at the mirrored row.
        for y in 0..<code.size {
            for x in 0..<code.size where code.module(x: x, y: y) {
                let left = (x + quietZone) * pixelsPerModule
                let bottom = (total - 1 - (y + quietZone)) * pixelsPerModule
                context.fill(CGRect(x: left, y: bottom, width: pixelsPerModule, height: pixelsPerModule))
            }
        }
        return context.makeImage()
    }
}
