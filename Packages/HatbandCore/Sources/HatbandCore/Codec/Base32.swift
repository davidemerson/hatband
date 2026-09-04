/// RFC 4648 Base32, uppercase, unpadded. The alphabet A–Z 2–7 lies inside the
/// QR alphanumeric set and needs no escaping in a URL fragment.
public enum Base32 {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidCharacter
        case invalidLength
        case nonZeroPadding
    }

    private static let alphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

    public static func encode(_ bytes: some Collection<UInt8>) -> String {
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count * 8 + 4) / 5)
        var buffer: UInt32 = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[Int((buffer >> UInt32(bits)) & 0x1f)])
            }
            buffer &= (1 << UInt32(bits)) - 1
        }
        if bits > 0 {
            out.append(alphabet[Int((buffer << UInt32(5 - bits)) & 0x1f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Accepts either case and tolerates any run of trailing `=`. Rejects any
    /// other character, impossible lengths, and non-zero trailing bits, so
    /// every accepted spelling re-encodes to itself once upper-cased and
    /// stripped of padding.
    public static func decode(_ text: some StringProtocol) throws -> [UInt8] {
        var chars = Array(text.utf8)
        while chars.last == UInt8(ascii: "=") { chars.removeLast() }
        let values = try chars.map { char -> UInt32 in
            switch char {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): return UInt32(char - UInt8(ascii: "A"))
            case UInt8(ascii: "a")...UInt8(ascii: "z"): return UInt32(char - UInt8(ascii: "a"))
            case UInt8(ascii: "2")...UInt8(ascii: "7"): return UInt32(char - UInt8(ascii: "2")) + 26
            default: throw Error.invalidCharacter
            }
        }
        switch values.count % 8 {
        case 1, 3, 6: throw Error.invalidLength
        default: break
        }
        var out: [UInt8] = []
        out.reserveCapacity(values.count * 5 / 8)
        var buffer: UInt32 = 0
        var bits = 0
        for value in values {
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> UInt32(bits)) & 0xff))
                buffer &= (1 << UInt32(bits)) - 1
            }
        }
        guard buffer == 0 else { throw Error.nonZeroPadding }
        return out
    }
}
