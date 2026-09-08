import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The meter said "412 B 88 chars QR v8" when read aloud, and the only thing
/// separating a card near its limit from one nowhere near it was the colour
/// orange — which says nothing to a reader who cannot see it, and nothing at
/// all now the chrome is grey.
struct ByteMeterTests {
    private func budget(_ name: String) throws -> Budget {
        Budget(card: try Vectors.card(name))
    }

    @Test func aComfortableCardSaysItsVersionAndNothingMore() throws {
        let typical = try budget("typical-signed")
        #expect(ByteMeter.versionText(typical, form: .fullQR) == "QR v13")
        #expect(ByteMeter.spoken(typical, form: .fullQR).hasSuffix("QR version 13."))
        #expect(ByteMeter.spoken(typical, form: .fullQR).contains("bytes"))
        #expect(ByteMeter.spoken(typical, form: .fullQR).contains("characters"))
        #expect(ByteMeter.tone(typical, form: .fullQR) == Theme.tertiary)
    }

    /// Near the limit is words now, so the colour is reinforcement.
    @Test func nearTheLimitIsSaidNotOnlyColoured() throws {
        let big = try budget("file-with-photo-and-key")     // version 25
        #expect(ByteMeter.versionText(big, form: .fullQR).contains("near the limit"))
        #expect(ByteMeter.spoken(big, form: .fullQR).contains("near the limit"))
        #expect(ByteMeter.tone(big, form: .fullQR) == .orange)

        // The same card judged against the Lock Screen is past its limit.
        #expect(ByteMeter.versionText(big, form: .lockScreen) == "too big for the Lock Screen")
        #expect(ByteMeter.tone(big, form: .lockScreen) == .red)
        #expect(ByteMeter.spoken(big, form: .lockScreen).hasSuffix("Too big for the Lock Screen."))
    }

    /// A compact card is comfortable on the Lock Screen; the two forms judge
    /// the same card by different limits.
    @Test func eachFormJudgesByItsOwnLimit() throws {
        let compact = try budget("compact-name-only")       // version 5
        #expect(ByteMeter.versionText(compact, form: .lockScreen) == "QR v5")
        #expect(ByteMeter.tone(compact, form: .lockScreen) == Theme.tertiary)
        #expect(ByteMeter.limit(.lockScreen) == Budget.lockScreenMaxVersion)
        #expect(ByteMeter.limit(.fullQR) == Budget.fullQRMaxVersion)
    }

    /// Every spoken form is a sentence, whatever the card.
    @Test func everySpokenFormIsASentence() throws {
        for name in ["minimal", "compact-name-only", "typical-signed", "file-with-photo-and-key"] {
            for form in [CardForm.lockScreen, .fullQR] {
                let spoken = ByteMeter.spoken(try budget(name), form: form)
                #expect(spoken.hasSuffix("."), "\(name)/\(form) does not end in a full stop")
                #expect(!spoken.contains("  "))
            }
        }
    }
}
