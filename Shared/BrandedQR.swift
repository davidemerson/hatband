import HatbandCore
import SwiftUI

/// A symbol with the hat standing in the square `QRShape` cleared for it.
/// Black on whatever is behind: a coloured hat would cost contrast, and
/// contrast is the whole of whether a code reads.
nonisolated struct BrandedQR: View {
    let code: QRCode
    var quietZone: Int = 2
    var fill: Color = .black

    var body: some View {
        QRShape(code: code, quietZone: quietZone)
            .fill(fill)
            .overlay { hat }
    }

    /// Sized to the cleared square and inset, so white is left around the
    /// glyph and the modules beside it are not crowded. Centred on the symbol
    /// rather than on the container: `QRShape` scales by the shorter side but
    /// anchors at `rect.minX/minY`, so in an oblong the symbol sits in the
    /// leading square and the container's centre is somewhere else.
    @ViewBuilder private var hat: some View {
        if let fraction = QRLogo.fraction(size: code.size) {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let symbol = side * CGFloat(code.size) / CGFloat(code.size + 2 * quietZone)
                let box = symbol * fraction * CGFloat(BrandedQRImage.inset)
                Image(systemName: Theme.hat)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(fill)
                    .frame(width: box, height: box)
                    .position(x: side / 2, y: side / 2)
                    .accessibilityHidden(true)
            }
        }
    }
}
