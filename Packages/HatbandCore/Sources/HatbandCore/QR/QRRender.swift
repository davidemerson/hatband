/// Renderers. Every output is exact: integer module sizes give integer
/// coordinates, and dark modules in a row are merged into one rectangle.
/// Module sizes below 1 are rendered as 1 and negative quiet zones as 0.
extension QRCode {
    /// A self-contained SVG with a light background rect and one dark path.
    /// Colours are interpolated into attributes, so only `#rgb` and `#rrggbb`
    /// (either case) are accepted; anything else falls back to the default.
    public func svg(moduleSize: Int = 4, quietZone: Int = 4, dark: String = "#000000", light: String = "#ffffff") -> String {
        let moduleSize = max(moduleSize, 1), quietZone = max(quietZone, 0)
        let side = (size + 2 * quietZone) * moduleSize
        let path = pathData(moduleSize: Double(moduleSize), quietZone: quietZone)
        let dark = Self.hexColour(dark) ?? "#000000", light = Self.hexColour(light) ?? "#ffffff"
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(side)" height="\(side)" viewBox="0 0 \(side) \(side)" shape-rendering="crispEdges">\
        <rect width="\(side)" height="\(side)" fill="\(light)"/>\
        <path d="\(path)" fill="\(dark)"/>\
        </svg>
        """
    }

    /// `value` when it is `#` followed by exactly three or six ASCII hex
    /// digits, otherwise nil.
    static func hexColour(_ value: String) -> String? {
        let utf8 = Array(value.utf8)
        guard utf8.first == UInt8(ascii: "#"), utf8.count == 4 || utf8.count == 7 else { return nil }
        let hex = utf8.dropFirst().allSatisfy {
            switch $0 {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "f"), UInt8(ascii: "A")...UInt8(ascii: "F"): true
            default: false
            }
        }
        return hex ? value : nil
    }

    /// The dark modules as an SVG path `d` string, one closed subpath per
    /// horizontal run, offset by the quiet zone. Suitable for CGPath too. A
    /// module size that is not positive and finite is rendered as 1.
    public func pathData(moduleSize: Double, quietZone: Int) -> String {
        let moduleSize = moduleSize.isFinite && moduleSize > 0 ? moduleSize : 1, quietZone = max(quietZone, 0)
        var d = ""
        for y in 0..<size {
            var x = 0
            while x < size {
                guard module(x: x, y: y) else { x += 1; continue }
                var end = x
                while end < size, module(x: end, y: y) { end += 1 }
                let left = Double(x + quietZone) * moduleSize
                let top = Double(y + quietZone) * moduleSize
                let width = Double(end - x) * moduleSize
                d += "M\(Self.number(left)) \(Self.number(top))h\(Self.number(width))v\(Self.number(moduleSize))h-\(Self.number(width))z"
                x = end
            }
        }
        return d
    }

    /// Portable bitmap, plain ASCII (P1): one character per pixel, 1 dark.
    public func pbm(scale: Int = 4, quietZone: Int = 4) -> String {
        let scale = max(scale, 1), quietZone = max(quietZone, 0)
        let side = (size + 2 * quietZone) * scale
        var out = "P1\n\(side) \(side)\n"
        out.reserveCapacity(out.utf8.count + side * (side + 1))
        for py in 0..<side {
            let y = py / scale - quietZone
            for px in 0..<side {
                out.append(module(x: px / scale - quietZone, y: y) ? "1" : "0")
            }
            out.append("\n")
        }
        return out
    }

    /// The matrix as text, two characters per module, for eyeballing.
    var debugDescription: String {
        var out = ""
        for y in 0..<size {
            for x in 0..<size { out += module(x: x, y: y) ? "##" : "  " }
            out += "\n"
        }
        return out
    }

    /// Integral values print without a fraction so SVG geometry stays exact.
    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
