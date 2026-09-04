/// RFC 3492 decoding, enough to see what an `xn--` label spells. Encoding
/// is never needed: a card stores the A-label it was given.
enum Punycode {
    private static let base = 36, tmin = 1, tmax = 26, skew = 38, damp = 700
    private static let initialBias = 72, initialN = 128

    /// The text for the bytes after `xn--`, or nil when they are not
    /// punycode: a byte outside the digit alphabet, input ending inside a
    /// number, arithmetic overflow, or a code point that is not a scalar.
    static func decode(_ input: some BidirectionalCollection<UInt8>) -> String? {
        var output: [Unicode.Scalar] = []
        var index = input.startIndex
        if let delimiter = input.lastIndex(of: UInt8(ascii: "-")) {
            for byte in input[..<delimiter] {
                guard byte < 0x80 else { return nil }
                output.append(Unicode.Scalar(byte))
            }
            index = input.index(after: delimiter)
        }
        var n = initialN, i = 0, bias = initialBias
        while index < input.endIndex {
            let oldi = i
            var w = 1
            var k = base
            while true {
                guard index < input.endIndex, let digit = digit(input[index]) else { return nil }
                index = input.index(after: index)
                let (scaled, o1) = digit.multipliedReportingOverflow(by: w)
                let (sum, o2) = i.addingReportingOverflow(scaled)
                guard !o1, !o2 else { return nil }
                i = sum
                let t = k <= bias ? tmin : k >= bias + tmax ? tmax : k - bias
                if digit < t { break }
                let (grown, o3) = w.multipliedReportingOverflow(by: base - t)
                guard !o3 else { return nil }
                w = grown
                k += base
            }
            let count = output.count + 1
            bias = adapt(delta: i - oldi, count: count, firstTime: oldi == 0)
            let (advanced, o4) = n.addingReportingOverflow(i / count)
            guard !o4, let value = UInt32(exactly: advanced), let scalar = Unicode.Scalar(value) else { return nil }
            n = advanced
            i %= count
            output.insert(scalar, at: i)
            i += 1
        }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: output)
        return String(text)
    }

    /// §6.1.
    private static func adapt(delta: Int, count: Int, firstTime: Bool) -> Int {
        var delta = firstTime ? delta / damp : delta / 2
        delta += delta / count
        var k = 0
        while delta > ((base - tmin) * tmax) / 2 {
            delta /= base - tmin
            k += base
        }
        return k + (base - tmin + 1) * delta / (delta + skew)
    }

    /// §5: `a-z` are 0–25 and `0-9` are 26–35, in either letter case.
    private static func digit(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return Int(byte - UInt8(ascii: "a"))
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return Int(byte - UInt8(ascii: "A"))
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(byte - UInt8(ascii: "0")) + base - 10
        default: return nil
        }
    }
}
