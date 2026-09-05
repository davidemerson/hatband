import Foundation
import HatbandCore
import SwiftUI
import Testing
@testable import Hatband

struct ThemeTests {
    /// The grounds and text tokens as `Theme.swift` declares them.
    private static let groundLight: UInt32 = 0xF2F2F2
    private static let groundDark: UInt32 = 0x0D0D0D
    private static let textTokens: [(name: String, light: UInt32, dark: UInt32)] = [
        ("ink", 0x111111, 0xE6E6E6),
        ("accent", 0x00008B, 0x7F7FFF),
        ("tertiary", 0x6E6E6E, 0x9A9A9A),
    ]

    /// Every persona colour clears WCAG 3:1 (glyphs, circles, bands) on
    /// both grounds; every text token clears 4.5:1.
    @Test func paletteAndTextTokensContrastWithBothGrounds() throws {
        for entry in Palette.colors {
            let light = try #require(Color.packed(hex: entry.light), "\(entry.name) light hex")
            let dark = try #require(Color.packed(hex: entry.dark), "\(entry.name) dark hex")
            #expect(ThemeTests.contrast(light, ThemeTests.groundLight) >= 3, "\(entry.name) on the light ground")
            #expect(ThemeTests.contrast(dark, ThemeTests.groundDark) >= 3, "\(entry.name) on the dark ground")
        }
        for token in ThemeTests.textTokens {
            #expect(ThemeTests.contrast(token.light, ThemeTests.groundLight) >= 4.5, "\(token.name) light")
            #expect(ThemeTests.contrast(token.dark, ThemeTests.groundDark) >= 4.5, "\(token.name) dark")
        }
    }

    private static let secondaryLight: UInt32 = 0xD9D9D9
    private static let secondaryDark: UInt32 = 0x262626

    /// `Theme.secondary` is the one text surface besides the grounds (the
    /// undo banner). Ink and the accent clear 4.5:1 on it in both
    /// appearances. The tertiary token reaches only 3.6:1 on the light
    /// one, the floor for glyphs but not for text, so mono metadata never
    /// sits on that surface; on the dark one it clears 4.5:1.
    @Test func inkAndAccentContrastWithSecondary() {
        for token in ThemeTests.textTokens {
            let floor: Double = token.name == "tertiary" ? 3 : 4.5
            #expect(ThemeTests.contrast(token.light, ThemeTests.secondaryLight) >= floor, "\(token.name) light")
            #expect(ThemeTests.contrast(token.dark, ThemeTests.secondaryDark) >= floor, "\(token.name) dark")
        }
        #expect(ThemeTests.contrast(0x9A9A9A, ThemeTests.secondaryDark) >= 4.5)
        // The surface itself stands off the ground it sits on.
        #expect(ThemeTests.contrast(ThemeTests.secondaryLight, ThemeTests.groundLight) > 1.2)
        #expect(ThemeTests.contrast(ThemeTests.secondaryDark, ThemeTests.groundDark) > 1.2)
    }

    /// WCAG 2 relative luminance and contrast ratio over packed sRGB.
    private static func luminance(_ packed: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((packed >> 16) & 0xFF) + 0.7152 * channel((packed >> 8) & 0xFF)
            + 0.0722 * channel(packed & 0xFF)
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

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
