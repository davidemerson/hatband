/// Reed–Solomon error correction over GF(2⁸) with the QR Code field
/// polynomial x⁸ + x⁴ + x³ + x² + 1 (0x11D), ISO/IEC 18004 §7.5.2.
enum ReedSolomon {
    /// Product in GF(2⁸) by shift-and-add, reduced by 0x11D. Small enough
    /// that a log table would not pay for itself.
    static func multiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var product = 0
        for shift in stride(from: 7, through: 0, by: -1) {
            product <<= 1
            if product & 0x100 != 0 { product ^= 0x11D }
            if (Int(b) >> shift) & 1 == 1 { product ^= Int(a) }
        }
        return UInt8(product)
    }

    /// The monic generator ∏(x − αⁱ) for i in 0..<degree, coefficients from
    /// the highest power down; `degree + 1` of them, the first always 1.
    static func generator(degree: Int) -> [UInt8] {
        var g: [UInt8] = [1]
        var root: UInt8 = 1
        for _ in 0..<degree {
            var next = [UInt8](repeating: 0, count: g.count + 1)
            for (i, c) in g.enumerated() {
                next[i] ^= c
                next[i + 1] ^= multiply(c, root)
            }
            g = next
            root = multiply(root, 2)
        }
        return g
    }

    /// The error correction codewords for `data`: the remainder of
    /// data·x^degree divided by the generator, by synthetic division.
    static func remainder(of data: [UInt8], generator: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: generator.count - 1)
        for byte in data {
            let factor = byte ^ result[0]
            result.removeFirst()
            result.append(0)
            for (i, c) in generator.dropFirst().enumerated() {
                result[i] ^= multiply(c, factor)
            }
        }
        return result
    }
}
