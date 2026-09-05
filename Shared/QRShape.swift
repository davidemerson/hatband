import CoreGraphics
import HatbandCore
import SwiftUI

/// A QR symbol as a SwiftUI shape: one rectangle per horizontal run of
/// dark modules, scaled so that `size + 2 * quietZone` modules fit the
/// shorter side of the rect. Fill it with black on a white panel.
nonisolated struct QRShape: Shape {
    let code: QRCode
    var quietZone: Int = 2

    func path(in rect: CGRect) -> Path {
        let zone = max(quietZone, 0)
        let total = code.size + 2 * zone
        guard total > 0 else { return Path() }
        let module = min(rect.width, rect.height) / CGFloat(total)
        var path = Path()
        for y in 0..<code.size {
            var x = 0
            while x < code.size {
                if !code.module(x: x, y: y) {
                    x += 1
                    continue
                }
                var end = x
                while end < code.size, code.module(x: end, y: y) {
                    end += 1
                }
                let run = CGRect(
                    x: rect.minX + CGFloat(x + zone) * module,
                    y: rect.minY + CGFloat(y + zone) * module,
                    width: CGFloat(end - x) * module,
                    height: module)
                path.addRect(run)
                x = end
            }
        }
        return path
    }
}
