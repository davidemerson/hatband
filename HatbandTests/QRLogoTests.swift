import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The square the hat stands on. Codes are drawn at medium error correction,
/// which recovers about 15% of a symbol; what is cleared here has to stay
/// well under that, because the Lock Screen code was measured reading at
/// 10 cm and not at 20 before any of it was covered.
struct QRLogoTests {
    private func versions() -> [Int] { Array(1...40) }

    /// No version gives up more than a sixteenth of itself, against the 15%
    /// medium correction can recover. Rounding and parity cost the smallest
    /// symbols proportionally more, which is why the bound is not tighter.
    @Test func theHatNeverCoversMoreThanErrorCorrectionCanSpare() {
        for version in versions() {
            let size = 17 + 4 * version
            guard let hole = QRLogo.hole(size: size) else { continue }
            let covered = Double(hole.count * hole.count) / Double(size * size)
            #expect(covered < 0.06, "version \(version) covers \(covered)")
            #expect(hole.count >= 3)
            #expect(hole.lowerBound > 0 && hole.upperBound < size)
        }
    }

    /// The versions Hatband actually makes: 5 and 8 are the Lock Screen's
    /// real cards, 10 its ceiling, 25 the largest in-app code. These are the
    /// ones scannability was measured on, and they stay under a twentieth.
    @Test func theVersionsHatbandMakesGiveUpVeryLittle() {
        for version in [5, 8, 10, 13, 25] {
            let size = 17 + 4 * version
            let hole = QRLogo.hole(size: size)
            let covered = Double((hole?.count ?? 0) * (hole?.count ?? 0)) / Double(size * size)
            #expect(covered < 0.05, "version \(version) covers \(covered)")
        }
    }

    /// Centred on the middle module rather than straddling it, so the glyph
    /// sits square: the cleared side takes the symbol's parity, and every QR
    /// version is odd.
    @Test func theSquareIsCentred() {
        for version in versions() {
            let size = 17 + 4 * version
            guard let hole = QRLogo.hole(size: size) else { continue }
            #expect(size - hole.upperBound == hole.lowerBound, "version \(version) is off centre")
            #expect(hole.count % 2 == size % 2)
        }
    }

    /// The three finder patterns live in the corners and are what a reader
    /// locks on to first; a centre square must come nowhere near them.
    @Test func theFindersAreUntouched() {
        for version in versions() {
            let size = 17 + 4 * version
            guard QRLogo.hole(size: size) != nil else { continue }
            for corner in [(0, 0), (size - 7, 0), (0, size - 7)] {
                for x in corner.0..<(corner.0 + 7) {
                    for y in corner.1..<(corner.1 + 7) {
                        #expect(!QRLogo.covers(x: x, y: y, size: size))
                    }
                }
            }
        }
    }

    @Test func aSymbolTooSmallToSpareAnythingGetsNoHat() {
        #expect(QRLogo.hole(size: 20) == nil)
        #expect(!QRLogo.covers(x: 5, y: 5, size: 20))
        #expect(QRLogo.fraction(size: 20) == nil)
    }
}
