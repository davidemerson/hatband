import SwiftUI
import Testing
@testable import Hatband

struct ThemeTests {
    @Test func hexParsesEitherCase() {
        #expect(Color(hex: "#00008B") != nil)
        #expect(Color(hex: "#00008b") != nil)
        #expect(Color.packed(hex: "#00008B") == 0x00008B)
        #expect(Color.packed(hex: "#00008b") == 0x00008B)
    }

    @Test func hexRejectsMalformed() {
        #expect(Color(hex: "00008b") == nil)
        #expect(Color(hex: "#00008") == nil)
        #expect(Color(hex: "#00008G") == nil)
        #expect(Color(hex: "#+00008") == nil)
        #expect(Color(hex: "") == nil)
    }

    @Test func personaColorsResolve() {
        for index in UInt8(0)...UInt8(12) {
            _ = Theme.personaColor(index)
        }
    }
}
