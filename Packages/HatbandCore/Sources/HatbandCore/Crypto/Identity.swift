#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// The master secret: 32 random bytes from which every persona key is
/// derived on demand. The app keeps it in the Keychain and carries it in
/// the encrypted export, so a restored phone keeps its identity.
public struct Identity: Sendable, Equatable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidSeedLength
    }

    public static let seedLength = 32

    public let seed: [UInt8]

    /// Exactly 32 bytes.
    public init(seed: [UInt8]) throws {
        guard seed.count == Identity.seedLength else { throw Error.invalidSeedLength }
        self.seed = seed
    }

    /// A fresh identity from the system's cryptographic random source.
    public static func generate() -> Identity {
        Identity(validated: randomBytes(count: seedLength))
    }

    /// Ed25519 key for persona `index`. Deterministic: the same seed and
    /// index always give the same key, so keys are never stored, only
    /// re-derived. HKDF-SHA256 (RFC 5869) with salt "hatband" and info
    /// "hatband/v1/persona/<index>", index in decimal.
    public func personaSigningKey(index: UInt32) -> Curve25519.Signing.PrivateKey {
        // Any 32 bytes are a valid Ed25519 seed.
        try! Curve25519.Signing.PrivateKey(rawRepresentation: derive(info: "hatband/v1/persona/\(index)"))
    }

    /// X25519 key for persona `index`, derived like the signing key but with
    /// info "hatband/v1/persona-x25519/<index>", so the two never coincide.
    public func personaAgreementKey(index: UInt32) -> Curve25519.KeyAgreement.PrivateKey {
        try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: derive(info: "hatband/v1/persona-x25519/\(index)"))
    }

    static let salt = Array("hatband".utf8)

    /// Constant time: every byte is compared and the result accumulated, so
    /// the time taken never depends on where two seeds first differ.
    public static func == (lhs: Identity, rhs: Identity) -> Bool {
        var difference: UInt8 = 0
        for i in 0..<seedLength {
            difference |= lhs.seed[i] ^ rhs.seed[i]
        }
        return difference == 0
    }

    private init(validated seed: [UInt8]) {
        self.seed = seed
    }

    private func derive(info: String) -> [UInt8] {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: seed), salt: Identity.salt,
                               info: Array(info.utf8), outputByteCount: 32)
            .withUnsafeBytes { Array($0) }
    }
}
