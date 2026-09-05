import Foundation
import HatbandCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// The little OpenPGP the app needs: the fingerprint of a certificate's
/// primary key (RFC 9580 §5.5.4), ASCII armor (§6) and the Web Key
/// Directory hash of a local part. Only the first packet is ever read.
nonisolated enum OpenPGP {
    /// The fingerprint of the first packet, which must be a public-key
    /// packet (tag 6): version 4 hashes `0x99`, a two-octet length and the
    /// body with SHA-1; version 6 hashes `0x9B`, a four-octet length and
    /// the body with SHA-256. Nil for any other packet or version, a
    /// partial or indeterminate length, or a truncated body.
    static func fingerprint(ofCertificate bytes: [UInt8]) -> [UInt8]? {
        guard let packet = firstPacket(bytes), packet.tag == 6, let version = packet.body.first else { return nil }
        let body = packet.body
        switch version {
        case 4:
            guard body.count <= 0xFFFF else { return nil }
            var framed: [UInt8] = [0x99, UInt8(body.count >> 8), UInt8(body.count & 0xFF)]
            framed.append(contentsOf: body)
            return Array(Insecure.SHA1.hash(data: framed))
        case 6:
            var framed: [UInt8] = [0x9B]
            framed.append(contentsOf: fourOctets(body.count))
            framed.append(contentsOf: body)
            return Array(SHA256.hash(data: framed))
        default:
            return nil
        }
    }

    /// The binary body of an ASCII-armored block: the base64 between the
    /// BEGIN and END lines, after any `Name: value` headers and the blank
    /// line. A CRC-24 line, when present, must match. Nil for anything else.
    static func dearmor(_ text: String) -> [UInt8]? {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let begin = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN PGP ") && $0.hasSuffix("-----") }) else {
            return nil
        }
        var index = begin + 1
        while index < lines.count, lines[index].contains(":") {
            index += 1
        }
        while index < lines.count, lines[index].isEmpty {
            index += 1
        }
        var base64 = ""
        var crc: [UInt8]?
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.hasPrefix("-----END PGP ") {
                guard let bytes = try? Base64.decode(base64), !bytes.isEmpty else { return nil }
                if let crc, crc != crc24(bytes) {
                    return nil
                }
                return bytes
            }
            if line.hasPrefix("=") {
                guard crc == nil, let check = try? Base64.decode(line.dropFirst()), check.count == 3 else { return nil }
                crc = check
                continue
            }
            base64 += line.filter { !$0.isWhitespace }
        }
        return nil
    }

    /// The Web Key Directory hash: z-base-32 of the SHA-1 of the local
    /// part with its ASCII letters lowercased.
    static func wkdHash(local: String) -> String {
        var lowered: [UInt8] = []
        for byte in local.utf8 {
            if byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") {
                lowered.append(byte + 32)
            } else {
                lowered.append(byte)
            }
        }
        return zBase32(Array(Insecure.SHA1.hash(data: lowered)))
    }

    // MARK: - Pieces

    /// RFC 9580 §6.1.1: polynomial 0x1864CFB, initial value 0xB704CE.
    static func crc24(_ bytes: [UInt8]) -> [UInt8] {
        var crc: UInt32 = 0xB704CE
        for byte in bytes {
            crc ^= UInt32(byte) << 16
            for _ in 0..<8 {
                crc <<= 1
                if crc & 0x1000000 != 0 {
                    crc ^= 0x1864CFB
                }
            }
        }
        return [UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
    }

    private static let zBase32Alphabet = Array("ybndrfg8ejkmcpqxot1uwisza345h769")

    /// Five bits per character, most significant first, no padding.
    static func zBase32(_ bytes: [UInt8]) -> String {
        var out = ""
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(zBase32Alphabet[(buffer >> bits) & 0x1F])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 {
            out.append(zBase32Alphabet[(buffer << (5 - bits)) & 0x1F])
        }
        return out
    }

    /// The first packet's tag and body. Old-format headers carry the tag
    /// in bits 2 to 5 and a one-, two- or four-octet length (an
    /// indeterminate length is refused); new-format headers carry it in
    /// the low six bits and a one-, two- or five-octet length (a partial
    /// body length is refused).
    private static func firstPacket(_ bytes: [UInt8]) -> (tag: Int, body: [UInt8])? {
        guard let first = bytes.first, first & 0x80 != 0 else { return nil }
        let tag: Int
        var offset = 1
        let length: Int
        if first & 0x40 != 0 {
            tag = Int(first & 0x3F)
            guard offset < bytes.count else { return nil }
            let head = Int(bytes[offset])
            if head < 192 {
                length = head
                offset += 1
            } else if head < 224 {
                guard offset + 1 < bytes.count else { return nil }
                length = ((head - 192) << 8) + Int(bytes[offset + 1]) + 192
                offset += 2
            } else if head == 255 {
                guard offset + 4 < bytes.count else { return nil }
                length = bigEndian(bytes[(offset + 1)...(offset + 4)])
                offset += 5
            } else {
                return nil
            }
        } else {
            tag = Int((first >> 2) & 0x0F)
            let octets: Int
            switch first & 0x03 {
            case 0: octets = 1
            case 1: octets = 2
            case 2: octets = 4
            default: return nil
            }
            guard offset + octets <= bytes.count else { return nil }
            length = bigEndian(bytes[offset..<(offset + octets)])
            offset += octets
        }
        guard length >= 1, offset + length <= bytes.count else { return nil }
        return (tag, Array(bytes[offset..<(offset + length)]))
    }

    private static func bigEndian(_ slice: ArraySlice<UInt8>) -> Int {
        var value = 0
        for byte in slice {
            value = (value << 8) | Int(byte)
        }
        return value
    }

    private static func fourOctets(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
