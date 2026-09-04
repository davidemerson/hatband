/// RFC 4648 Base64 in both alphabets: the standard one with `=` padding for
/// OpenSSH lines and vCard photos, and the URL-safe one without padding for
/// `signal.me` links. Decoding is strict so a byte string has one spelling.
public enum Base64 {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidCharacter
        case invalidLength
        case invalidPadding
        case nonZeroPadding
    }

    private static let standard: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let urlSafe: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    /// Standard alphabet, padded; or with `url`, the URL-safe alphabet, unpadded.
    public static func encode(_ bytes: some Collection<UInt8>, url: Bool = false) -> String {
        let alphabet = url ? urlSafe : standard
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count + 2) / 3 * 4)
        var buffer: UInt32 = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 6 {
                bits -= 6
                out.append(alphabet[Int((buffer >> UInt32(bits)) & 0x3f)])
            }
            buffer &= (1 << UInt32(bits)) - 1
        }
        if bits > 0 {
            out.append(alphabet[Int((buffer << UInt32(6 - bits)) & 0x3f)])
        }
        if !url {
            while out.count % 4 != 0 { out.append(UInt8(ascii: "=")) }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Padding is optional but, when present, must be exactly what the length
    /// calls for. Rejects the other alphabet, whitespace, and non-zero
    /// trailing bits.
    public static func decode(_ text: some StringProtocol, url: Bool = false) throws -> [UInt8] {
        var chars = Array(text.utf8)
        var padding = 0
        while chars.last == UInt8(ascii: "=") {
            chars.removeLast()
            padding += 1
        }
        if padding > 0, padding > 2 || (chars.count + padding) % 4 != 0 { throw Error.invalidPadding }
        let values = try chars.map { char -> UInt32 in
            switch char {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): return UInt32(char - UInt8(ascii: "A"))
            case UInt8(ascii: "a")...UInt8(ascii: "z"): return UInt32(char - UInt8(ascii: "a")) + 26
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(char - UInt8(ascii: "0")) + 52
            case UInt8(ascii: "+") where !url, UInt8(ascii: "-") where url: return 62
            case UInt8(ascii: "/") where !url, UInt8(ascii: "_") where url: return 63
            default: throw Error.invalidCharacter
            }
        }
        guard values.count % 4 != 1 else { throw Error.invalidLength }
        var out: [UInt8] = []
        out.reserveCapacity(values.count * 3 / 4)
        var buffer: UInt32 = 0
        var bits = 0
        for value in values {
            buffer = (buffer << 6) | value
            bits += 6
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
