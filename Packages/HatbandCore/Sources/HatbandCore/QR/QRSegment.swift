/// One data segment of a QR Code (ISO/IEC 18004 §7.4): a mode and the bits it
/// contributes before the mode indicator and character count are prepended.
/// Numeric, alphanumeric and byte only; Kanji and ECI are not needed.
public struct QRSegment: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case numeric
        case alphanumeric
        case byte

        /// Mode indicator, Table 2.
        var indicator: Int {
            switch self {
            case .numeric: 1
            case .alphanumeric: 2
            case .byte: 4
            }
        }

        /// Width of the character count field for a version, Table 3.
        func characterCountBits(version: Int) -> Int {
            let group = (version + 7) / 17
            switch self {
            case .numeric: return [10, 12, 14][group]
            case .alphanumeric: return [9, 11, 13][group]
            case .byte: return [8, 16, 16][group]
            }
        }
    }

    public let mode: Mode
    /// Digits, alphanumeric characters or bytes, as the count field reports.
    public let characterCount: Int
    /// Data bits, most significant first.
    let bits: [Bool]

    public static func bytes(_ data: [UInt8]) -> QRSegment {
        var buffer = BitBuffer()
        for byte in data { buffer.append(Int(byte), count: 8) }
        return QRSegment(mode: .byte, characterCount: data.count, bits: buffer.bits)
    }

    /// Digits only. Three digits per 10 bits, then 7 or 4 for the remainder.
    public static func numeric(_ digits: String) throws -> QRSegment {
        let values = try Array(digits.utf8).map { c -> Int in
            guard case UInt8(ascii: "0")...UInt8(ascii: "9") = c else { throw QRError.invalidCharacter }
            return Int(c - UInt8(ascii: "0"))
        }
        var buffer = BitBuffer()
        var i = 0
        while i < values.count {
            let n = min(3, values.count - i)
            let group = values[i..<i + n].reduce(0) { $0 * 10 + $1 }
            buffer.append(group, count: n * 3 + 1)
            i += n
        }
        return QRSegment(mode: .numeric, characterCount: values.count, bits: buffer.bits)
    }

    /// The 45-character set 0–9 A–Z space $ % * + - . / :. Two characters
    /// per 11 bits, then 6 for an odd last one.
    public static func alphanumeric(_ text: String) throws -> QRSegment {
        let values = try Array(text.utf8).map { c -> Int in
            guard let v = alphanumericValue(c) else { throw QRError.invalidCharacter }
            return v
        }
        var buffer = BitBuffer()
        var i = 0
        while i < values.count {
            if i + 1 < values.count {
                buffer.append(values[i] * 45 + values[i + 1], count: 11)
                i += 2
            } else {
                buffer.append(values[i], count: 6)
                i += 1
            }
        }
        return QRSegment(mode: .alphanumeric, characterCount: values.count, bits: buffer.bits)
    }

    /// The densest single mode that can carry the whole string; empty for "".
    public static func optimal(for text: String) -> [QRSegment] {
        if text.isEmpty { return [] }
        if let s = try? numeric(text) { return [s] }
        if let s = try? alphanumeric(text) { return [s] }
        return [.bytes(Array(text.utf8))]
    }

    /// Hatband's URL shape: a byte segment through the first `#`, then an
    /// alphanumeric segment for the fragment when it is entirely in that set.
    /// Base32 is, so a card costs 5.5 bits per character instead of 8.
    public static func segments(forURL url: String) -> [QRSegment] {
        let utf8 = Array(url.utf8)
        guard let hash = utf8.firstIndex(of: UInt8(ascii: "#")), hash + 1 < utf8.count,
              let fragment = try? alphanumeric(String(decoding: utf8[(hash + 1)...], as: UTF8.self))
        else { return [.bytes(utf8)] }
        return [.bytes(Array(utf8[...hash])), fragment]
    }

    /// Bits for a segment list at a version including indicators and counts,
    /// or nil when a count does not fit its field at that version.
    static func totalBits(_ segments: [QRSegment], version: Int) -> Int? {
        var total = 0
        for segment in segments {
            let countBits = segment.mode.characterCountBits(version: version)
            guard segment.characterCount < 1 << countBits else { return nil }
            total += 4 + countBits + segment.bits.count
        }
        return total
    }

    private static let alphanumericValues: [Int] = {
        var table = [Int](repeating: -1, count: 128)
        for (i, c) in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8.enumerated() {
            table[Int(c)] = i
        }
        return table
    }()

    static func alphanumericValue(_ c: UInt8) -> Int? {
        guard c < 128, alphanumericValues[Int(c)] >= 0 else { return nil }
        return alphanumericValues[Int(c)]
    }
}

/// Bits appended most significant first, packed to bytes on demand.
struct BitBuffer: Sendable, Equatable {
    private(set) var bits: [Bool] = []

    var count: Int { bits.count }

    /// The low `count` bits of `value`, high bit first.
    mutating func append(_ value: Int, count: Int) {
        for shift in stride(from: count - 1, through: 0, by: -1) {
            bits.append((value >> shift) & 1 == 1)
        }
    }

    mutating func append(contentsOf other: [Bool]) {
        bits.append(contentsOf: other)
    }

    /// Bytes with a trailing partial byte zero-filled.
    var bytes: [UInt8] {
        var out = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (i, bit) in bits.enumerated() where bit {
            out[i >> 3] |= 0x80 >> UInt8(i & 7)
        }
        return out
    }
}
