import CoreGraphics
import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The persona editor's colour swatches: 44 pt targets around a smaller
/// disc, each named for VoiceOver after its palette colour.
struct PersonaEditorViewTests {
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
