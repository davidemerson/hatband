#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Signing and fingerprinting a `Card`. `signingBytes` covers key 14, so the
/// public key must be in the card before the signature is computed;
/// `signed(with:)` is the one place that order is fixed. The Model's
/// `withSignature(_:publicKey:)` sets both after the fact and trusts the
/// caller to have signed a card that already carried that key: sign first
/// and set the key afterwards and the result never verifies.
extension Card {
    /// The card with `publicKey` set from `key` and `signature` over the
    /// resulting `signingBytes`. Replaces any key or signature already there.
    public func signed(with key: Curve25519.Signing.PrivateKey) throws -> Card {
        var copy = self
        copy.publicKey = Array(key.publicKey.rawRepresentation)
        copy.signature = try CardSignature.sign(copy.signingBytes, with: key)
        return copy
    }

    /// Whether `signature` verifies over `signingBytes` under `publicKey`.
    /// False when either is absent: an unsigned card is never valid, only
    /// unsigned.
    public var signatureIsValid: Bool {
        guard let publicKey, let signature else { return false }
        return CardSignature.verify(signature, for: signingBytes, publicKey: publicKey)
    }

    /// Key 19 for `publicKey`: the first 8 bytes of its SHA-256. Nil unless
    /// the key is 32 bytes.
    public static func keyFingerprint(for publicKey: [UInt8]) -> [UInt8]? {
        KeyFingerprint(publicKey: publicKey)?.short
    }

    /// The card with key 19 set to the fingerprint of `publicKey`, for the
    /// compact tier, which carries no key or signature. A key that is not
    /// 32 bytes clears the field rather than leaving a stale one.
    public func withKeyFingerprint(of publicKey: [UInt8]) -> Card {
        var copy = self
        copy.keyFingerprint = Card.keyFingerprint(for: publicKey)
        return copy
    }
}
