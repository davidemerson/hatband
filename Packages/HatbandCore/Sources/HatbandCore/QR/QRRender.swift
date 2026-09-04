/// Renderers. Every output is exact: integer module sizes give integer
/// coordinates, and dark modules in a row are merged into one rectangle.
extension QRCode {
    /// A self-contained SVG with a light background rect and one dark path.
    public func svg(moduleSize: Int = 4, quietZone: Int = 4, dark: String = "#000000", light: String = "#ffffff") -> String {
        let side = (size + 2 * quietZone) * moduleSize
        let path = pathData(moduleSize: Double(moduleSize), quietZone: quietZone)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(side)" height="\(side)" viewBox="0 0 \(side) \(side)" shape-rendering="crispEdges">\
        <rect width="\(side)" height="\(side)" fill="\(light)"/>\
        <path d="\(path)" fill="\(dark)"/>\
        </svg>
        """
    }

    /// The dark modules as an SVG path `d` string, one closed subpath per
    /// horizontal run, offset by the quiet zone. Suitable for CGPath too.
    public func pathData(moduleSize: Double, quietZone: Int) -> String {
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
