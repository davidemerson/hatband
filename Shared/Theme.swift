import HatbandCore
import SwiftUI
import UIKit

/// The nnix tokens on iOS. Light first, dark second.
nonisolated enum Theme {
    static let ground = Color(light: 0xF2F2F2, dark: 0x0D0D0D)
    static let secondary = Color(light: 0xD9D9D9, dark: 0x262626)
    static let ink = Color(light: 0x111111, dark: 0xE6E6E6)
    static let accent = Color(light: 0x00008B, dark: 0x7F7FFF)
    /// "Subtle mono".
    static let tertiary = Color(light: 0x6E6E6E, dark: 0x9A9A9A)

    /// `Palette.color(at:)` in light and dark.
    static func personaColor(_ index: UInt8) -> Color {
        let entry = Palette.color(at: index)
        return Color(light: rgb(entry.light), dark: rgb(entry.dark))
    }

    static let mono = Font.system(.subheadline, design: .monospaced)
    static let radius: CGFloat = 15
    /// SF Symbol; one edit if absent.
    static let hat = "hat.widebrim"
    static let flower = "camera.macro"

    /// `#rrggbb` to a packed value; 0 for anything else.
    private static func rgb(_ hex: String) -> UInt32 {
        Color.packed(hex: hex) ?? 0
    }
}

nonisolated extension Color {
    /// A dynamic colour from two packed `0xRRGGBB` values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(packed: dark) : UIColor(packed: light)
        })
    }

    /// `#rrggbb`, either case. Nil for anything else.
    init?(hex: String) {
        guard let packed = Color.packed(hex: hex) else { return nil }
        self.init(light: packed, dark: packed)
    }

    static func packed(hex: String) -> UInt32? {
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt32(digits, radix: 16)
    }
}

nonisolated extension UIColor {
    convenience init(packed: UInt32) {
        let red = CGFloat((packed >> 16) & 0xFF) / 255
        let green = CGFloat((packed >> 8) & 0xFF) / 255
        let blue = CGFloat(packed & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
