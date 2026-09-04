/// Named card colours. The payload carries the index, so order is frozen.
public enum Palette {
    public struct Color: Sendable, Hashable {
        public let name: String
        /// sRGB hex for light and dark appearance.
        public let light: String
        public let dark: String
    }

    public static let colors: [Color] = [
        Color(name: "ink", light: "#111111", dark: "#e6e6e6"),
        Color(name: "dark blue", light: "#00008b", dark: "#7f7fff"),
        Color(name: "bottle green", light: "#0b3d2e", dark: "#5fae8c"),
        Color(name: "brass", light: "#8a6d00", dark: "#d4b64a"),
        Color(name: "rust", light: "#8a3324", dark: "#d97a63"),
        Color(name: "slate", light: "#4a5560", dark: "#a3adb8"),
        Color(name: "bog", light: "#4b4a2a", dark: "#b8b47a"),
        Color(name: "peat", light: "#4a3728", dark: "#b89078"),
        Color(name: "heather", light: "#5b4b7a", dark: "#b6a3d6"),
        Color(name: "tram cream", light: "#8c7f4d", dark: "#e8dcb5"),
    ]

    public static func color(at index: UInt8) -> Color {
        colors[Int(index) < colors.count ? Int(index) : 0]
    }
}
