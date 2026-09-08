import Foundation
import HatbandCore

/// The hat in the middle of a symbol, and the modules it stands on.
///
/// Codes are drawn at medium error correction, which recovers about 15% of a
/// symbol. A square of this side covers about 4% of one, leaving the rest for
/// glare, a camera at arm's length and a screen at half brightness — which
/// matters, because the Lock Screen code was measured reading at 10 cm and
/// not at 20 before any of it was covered.
nonisolated enum QRLogo {
    /// Fraction of the symbol's side the cleared square takes. Four percent
    /// of the area; a quarter of what the error correction could stand.
    static let sideFraction = 0.20

    /// The cleared square in module coordinates, or nil for a symbol too
    /// small to give any of itself up. The side takes the symbol's parity so
    /// the square sits on the middle module instead of straddling it.
    static func hole(size: Int) -> Range<Int>? {
        guard size >= 21 else { return nil }
        var side = Int((Double(size) * sideFraction).rounded())
        // Down, never up, when the parity is wrong: giving a module back is
        // always the safer direction on a code that has to survive a camera.
        if side % 2 != size % 2 { side -= 1 }
        guard side >= 3, side < size / 2 else { return nil }
        let start = (size - side) / 2
        return start..<(start + side)
    }

    /// Whether the hat stands on this module, so a renderer can leave it out.
    static func covers(x: Int, y: Int, size: Int) -> Bool {
        guard let hole = hole(size: size) else { return false }
        return hole.contains(x) && hole.contains(y)
    }

    /// The cleared square as a fraction of the drawn symbol, for placing the
    /// glyph over it. Nil when nothing was cleared.
    static func fraction(size: Int) -> Double? {
        guard let hole = hole(size: size) else { return nil }
        return Double(hole.count) / Double(size)
    }
}
