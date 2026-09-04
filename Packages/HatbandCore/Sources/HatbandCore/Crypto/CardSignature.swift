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

    /// 64 bytes over `domain || canonicalBytes`. Ed25519 signing in CryptoKit
    /// is randomized, so two signatures over the same bytes differ.
    public static func sign(_ canonicalBytes: [UInt8], with key: Curve25519.Signing.PrivateKey) throws -> [UInt8] {
        Array(try key.signature(for: domain + canonicalBytes))
    }

    /// False for any malformed key or signature; never throws, so a hostile
    /// card cannot make verification fail differently from a forged one.
    public static func verify(_ signature: [UInt8], for canonicalBytes: [UInt8], publicKey: [UInt8]) -> Bool {
        guard signature.count == length,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        else { return false }
        return key.isValidSignature(signature, for: domain + canonicalBytes)
    }
}
