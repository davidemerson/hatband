import Foundation
import Testing
@testable import Hatband

/// The reveal button on a passphrase field is icon-only, so it carries a
/// VoiceOver label that says which way it will flip.
struct PassphraseFieldTests {
    @Test func revealButtonIsLabelledBothWays() {
        #expect(PassphraseField.toggleLabel(revealed: false) == "Show passphrase")
        #expect(PassphraseField.toggleLabel(revealed: true) == "Hide passphrase")
        #expect(PassphraseField.toggleLabel(revealed: false) != PassphraseField.toggleLabel(revealed: true))
    }
}
