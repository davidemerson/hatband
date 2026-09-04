#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Ed25519 over a fixed prefix and the canonical card bytes. The prefix
/// binds every signature to this purpose, so a card signature can never
/// be presented as a signature over anything else and vice versa.
public enum CardSignature {
    public static let domain = Array("hatband-card-v1".utf8)
    public static let length = 64

    /// 64 bytes over `domain || canonicalBytes`. Two calls over the same
    /// bytes may differ: CryptoKit randomizes Ed25519 signing, BoringSSL on
    /// Linux is deterministic (RFC 8032 §5.1.6). Both verify; compare
    /// signatures only by verifying them.
    public static func sign(_ canonicalBytes: [UInt8], with key: Curve25519.Signing.PrivateKey) throws -> [UInt8] {
        Array(try key.signature(for: domain + canonicalBytes))
    }

    /// False for any malformed key or signature; never throws, so a hostile
    /// card cannot make verification fail differently from a forged one.
    public static func verify(_ signature: [UInt8], for canonicalBytes: [UInt8], publicKey: [UInt8]) -> Bool {
        guard signature.count == length, isAcceptablePublicKey(publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        else { return false }
        return key.isValidSignature(signature, for: domain + canonicalBytes)
    }

    /// A canonical encoding of a point outside the torsion subgroup. RFC 8032
    /// §5.1.3 requires y < p but leaves small-order keys to the caller, and
    /// BoringSSL (hence swift-crypto) accepts them; under such a key
    /// `[S]B = R + [k]A` holds for every message with S = 0 and R in the same
    /// subgroup, so anyone could sign for it. Keys are bytes off a QR code,
    /// so the check is here rather than in `Identity`, which never makes one.
    static func isAcceptablePublicKey(_ publicKey: [UInt8]) -> Bool {
        guard publicKey.count == 32 else { return false }
        var y = publicKey
        y[31] &= 0x7f
        return y.reversed().lexicographicallyPrecedes(fieldPrime.reversed()) && !smallOrderY.contains(y)
    }

    /// p = 2^255 - 19, little-endian.
    static let fieldPrime: [UInt8] = [0xed] + [UInt8](repeating: 0xff, count: 30) + [0x7f]

    /// y-coordinates of the eight points of order dividing 8, sign bit clear:
    /// libsodium's blocklist (ed25519_ref10.c) less its two non-canonical
    /// entries p and p + 1, which fail the y < p test. Re-derived from a
    /// pure-Python edwards25519 in Tests/Fixtures/ed25519_small_order.py.
    static let smallOrderY: [[UInt8]] = [
        // Order 4, x = ±sqrt(-1).
        [UInt8](repeating: 0, count: 32),
        // The identity.
        [1] + [UInt8](repeating: 0, count: 31),
        // Order 8.
        [0x26, 0xe8, 0x95, 0x8f, 0xc2, 0xb2, 0x27, 0xb0, 0x45, 0xc3, 0xf4, 0x89, 0xf2, 0xef, 0x98, 0xf0,
         0xd5, 0xdf, 0xac, 0x05, 0xd3, 0xc6, 0x33, 0x39, 0xb1, 0x38, 0x02, 0x88, 0x6d, 0x53, 0xfc, 0x05],
        [0xc7, 0x17, 0x6a, 0x70, 0x3d, 0x4d, 0xd8, 0x4f, 0xba, 0x3c, 0x0b, 0x76, 0x0d, 0x10, 0x67, 0x0f,
         0x2a, 0x20, 0x53, 0xfa, 0x2c, 0x39, 0xcc, 0xc6, 0x4e, 0xc7, 0xfd, 0x77, 0x92, 0xac, 0x03, 0x7a],
        // Order 2: y = -1.
        [0xec] + [UInt8](repeating: 0xff, count: 30) + [0x7f],
    ]
}
