import Foundation
import HatbandCore
import SwiftUI
import Testing
@testable import Hatband

/// The screen's backlight follows the scene while the Card tab is on
/// screen: raised again on every return to the foreground, not only on
/// the first appearance, and let go in the background.
struct CardViewTests {
    @Test func backlightFollowsTheSceneWhileVisible() {
        #expect(CardView.backlight(for: .active, visible: true) == .raise)
        #expect(CardView.backlight(for: .background, visible: true) == .restore)
        #expect(CardView.backlight(for: .inactive, visible: true) == nil)
    }

    /// "Share as link" must hand the share sheet a `URL`. A string is shared
    /// as text, and the receiving app's data detectors linkify `hatband.link`
    /// and drop the fragment, so the recipient gets the bare site. Every card
    /// form has to survive `URL(string:)` byte for byte, including the 32 KB
    /// ceiling, whose URL runs past fifty thousand characters.
    @Test func everyCardURLSurvivesAsAURL() throws {
        for name in ["minimal", "compact-name-only", "typical-signed", "maximal-qr-signed",
                     "file-with-photo-and-key", "unicode-nfc"] {
            let text = try Vectors.url(name)
            let url = try #require(URL(string: text), "\(name) does not parse as a URL")
            #expect(url.absoluteString == text)
            #expect(url.scheme == "https")
            #expect(url.host() == HB1.host)
        }
    }

    /// The ceiling case, built rather than pinned: 32 KB of CBOR is Base32'd
    /// 8/5 into a fragment, and a URL has to carry all of it.
    @Test func theCeilingURLSurvivesTooAndIsEnormous() throws {
        let fragment = String(repeating: "A", count: (HB1.maxBytes * 8) / 5)
        let text = HB1.urlPrefix + String(HB1.formatTag) + fragment
        let url = try #require(URL(string: text))
        #expect(url.absoluteString == text)
        #expect(text.count > 52_000)
    }

    @Test func backlightLeftAloneWhileAnotherTabShows() {
        for phase in [ScenePhase.active, .inactive, .background] {
            #expect(CardView.backlight(for: phase, visible: false) == nil)
        }
    }
}
