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

    @Test func backlightLeftAloneWhileAnotherTabShows() {
        for phase in [ScenePhase.active, .inactive, .background] {
            #expect(CardView.backlight(for: phase, visible: false) == nil)
        }
    }
}
