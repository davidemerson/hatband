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
    /// Done and the Back chevron judge a draft the same way, because they ask
    /// the same function. The chevron used to discard everything instead.
    @Test func aDraftCommitsOrSaysWhyNot() throws {
        var persona = Persona(id: Array(repeating: 7, count: 8), label: "  Work  ", keyIndex: 0)
        // A label is trimmed on the way in.
        guard case .ready(let committed) = PersonaEditorView.committed(persona) else {
            Issue.record("a labelled persona should commit"); return
        }
        #expect(committed.label == "Work")

        persona.label = "   "
        guard case .refused(let blank) = PersonaEditorView.committed(persona) else {
            Issue.record("a blank label should be refused"); return
        }
        #expect(blank == "Give the persona a label.")

        persona.label = "Work"
        persona.displayName = String(repeating: "x", count: 200)
        guard case .refused(let long) = PersonaEditorView.committed(persona) else {
            Issue.record("an oversized name should be refused"); return
        }
        #expect(long.contains("too long"))
    }

    /// An alias with no name cannot make a card, so it is refused rather than
    /// saved empty and shown from the Card tab.
    @Test func anAliasNeedsAName() {
        var persona = Persona(id: Array(repeating: 7, count: 8), label: "Henry", keyIndex: 1)
        persona.aliasProfile = Profile()
        guard case .refused(let reason) = PersonaEditorView.committed(persona) else {
            Issue.record("a nameless alias should be refused"); return
        }
        #expect(reason.contains("Alias details"))

        var named = Profile()
        named.name = "Henry Flower"
        persona.aliasProfile = named
        guard case .ready = PersonaEditorView.committed(persona) else {
            Issue.record("a named alias should commit"); return
        }
    }

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
