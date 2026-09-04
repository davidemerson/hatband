#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// SHA-256 of a persona's raw 32-byte Ed25519 public key. The first 8 bytes
/// ride in the compact tier (key 19); the full 32 are what two people
/// compare out of band.
public struct KeyFingerprint: Sendable, Hashable {
    public static let publicKeyLength = 32
    public static let shortLength = 8

    /// All 32 bytes.
    public let full: [UInt8]

    /// Nil unless `publicKey` is 32 bytes.
    public init?(publicKey: [UInt8]) {
        guard publicKey.count == KeyFingerprint.publicKeyLength else { return nil }
        full = Array(SHA256.hash(data: publicKey))
    }

    public init(publicKey: Curve25519.Signing.PublicKey) {
        full = Array(SHA256.hash(data: publicKey.rawRepresentation))
    }

    /// The first 8 bytes, as carried in the compact tier.
    public var short: [UInt8] { Array(full.prefix(KeyFingerprint.shortLength)) }

    /// Lowercase hex of the full fingerprint.
    public var hex: String {
        var out: [UInt8] = []
        out.reserveCapacity(full.count * 2)
        for byte in full {
            out.append(KeyFingerprint.hexDigits[Int(byte >> 4)])
            out.append(KeyFingerprint.hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Uppercase hex in groups of four, eight groups per line, two lines:
    /// the form shown in SF Mono and read aloud.
    public var display: String {
        let digits = Array(hex.uppercased().utf8)
        let groups = stride(from: 0, to: digits.count, by: 4).map {
            String(decoding: digits[$0..<$0 + 4], as: UTF8.self)
        }
        return stride(from: 0, to: groups.count, by: 8)
            .map { groups[$0..<$0 + 8].joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// Whether `short` is the compact-tier fingerprint of `publicKey`.
    public static func matches(short: [UInt8], publicKey: [UInt8]) -> Bool {
        short.count == shortLength && KeyFingerprint(publicKey: publicKey)?.short == short
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)
}
