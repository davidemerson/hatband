import CoreGraphics
import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The persona editor's colour swatches: 44 pt targets around a smaller
/// disc, each named for VoiceOver after its palette colour.
struct PersonaEditorViewTests {
    /// Turning the Alias toggle off used to discard the alias profile on the
    /// spot, so one tap taken to see what it does lost a name, an email and a
    /// website with no confirmation and no undo. What was there is put aside.
    @Test func theAliasToggleDoesNotDestroyWhatWasTyped() {
        var typed = Profile()
        typed.name = "Henry Flower"
        typed.email = "henry@flower.ie"

        // Off: nothing is an alias any more, and the caller stashes what was there.
        #expect(PersonaEditorView.alias(turningOn: false, current: typed, stashed: nil) == nil)
        // On again: what was put aside comes back, not an empty profile.
        #expect(PersonaEditorView.alias(turningOn: true, current: nil, stashed: typed) == typed)
    }

    @Test func aFirstAliasStartsEmptyAndAnExistingOneIsKept() {
        var existing = Profile()
        existing.name = "Henry Flower"
        #expect(PersonaEditorView.alias(turningOn: true, current: nil, stashed: nil) == Profile())
        #expect(PersonaEditorView.alias(turningOn: true, current: existing, stashed: Profile()) == existing)
    }

    @Test func swatchesAreFortyFourPointTargets() {
        #expect(PersonaEditorView.swatchTarget >= 44)
        #expect(PersonaEditorView.swatchDiameter <= PersonaEditorView.swatchTarget)
        #expect(PersonaEditorView.swatchDiameter >= 20)
    }

    @Test func everySwatchNamesItsColour() {
        var seen: Set<String> = []
        for index in Palette.colors.indices {
            let label = PersonaEditorView.swatchLabel(index)
            #expect(label == Palette.colors[index].name)
            #expect(!label.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(seen.insert(label).inserted, "\(label) names two colours")
        }
        // Out of range never traps; it names the first colour, as `Palette.color(at:)` does.
        #expect(PersonaEditorView.swatchLabel(Palette.colors.count) == Palette.colors[0].name)
        #expect(PersonaEditorView.swatchLabel(1_000) == Palette.colors[0].name)
    }
}
