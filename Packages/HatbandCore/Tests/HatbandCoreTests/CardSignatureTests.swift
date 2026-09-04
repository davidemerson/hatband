import Testing
@testable import HatbandCore

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

private let message = Array("Leopold Bloom, 7 Eccles Street".utf8)

private func publicBytes(_ key: Curve25519.Signing.PrivateKey) -> [UInt8] {
    Array(key.publicKey.rawRepresentation)
}

@Test func domainIsTheDocumentedString() {
    #expect(CardSignature.domain == Array("hatband-card-v1".utf8))
    #expect(CardSignature.length == 64)
}

@Test func signsAndVerifies() throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    #expect(signature.count == 64)
    #expect(CardSignature.verify(signature, for: message, publicKey: publicBytes(key)))
}

@Test func signsAndVerifiesEmptyMessage() throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign([], with: key)
    #expect(CardSignature.verify(signature, for: [], publicKey: publicBytes(key)))
    #expect(!CardSignature.verify(signature, for: [0], publicKey: publicBytes(key)))
}

@Test func signaturesAreRandomizedButAllVerify() throws {
    let key = Curve25519.Signing.PrivateKey()
    let a = try CardSignature.sign(message, with: key)
    let b = try CardSignature.sign(message, with: key)
    #expect(CardSignature.verify(a, for: message, publicKey: publicBytes(key)))
    #expect(CardSignature.verify(b, for: message, publicKey: publicBytes(key)))
}

@Test func flippingAnyMessageBitFailsVerification() throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    for i in message.indices {
        for mask: UInt8 in [0x01, 0x10, 0x80] {
            var tampered = message
            tampered[i] ^= mask
            #expect(!CardSignature.verify(signature, for: tampered, publicKey: publicBytes(key)))
        }
    }
}

@Test func flippingAnySignatureBitFailsVerification() throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    for i in signature.indices {
        for mask: UInt8 in [0x01, 0x80] {
            var tampered = signature
            tampered[i] ^= mask
            #expect(!CardSignature.verify(tampered, for: message, publicKey: publicBytes(key)))
        }
    }
}

@Test func truncatedOrExtendedMessageFailsVerification() throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    #expect(!CardSignature.verify(signature, for: Array(message.dropLast()), publicKey: publicBytes(key)))
    #expect(!CardSignature.verify(signature, for: message + [0], publicKey: publicBytes(key)))
    #expect(!CardSignature.verify(signature, for: [0] + message, publicKey: publicBytes(key)))
}

@Test func wrongKeyFailsVerification() throws {
    let key = Curve25519.Signing.PrivateKey()
    let other = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    #expect(!CardSignature.verify(signature, for: message, publicKey: publicBytes(other)))
}

@Test(arguments: [0, 1, 31, 33, 64])
func malformedPublicKeyLengthsFail(count: Int) throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    let bad = Array(publicBytes(key).prefix(count)) + [UInt8](repeating: 0xab, count: max(0, count - 32))
    #expect(bad.count == count)
    #expect(!CardSignature.verify(signature, for: message, publicKey: bad))
}

@Test(arguments: [[UInt8](repeating: 0x00, count: 32), [UInt8](repeating: 0xff, count: 32)])
func degeneratePublicKeysFail(publicKey: [UInt8]) throws {
    let signature = try CardSignature.sign(message, with: Curve25519.Signing.PrivateKey())
    #expect(!CardSignature.verify(signature, for: message, publicKey: publicKey))
}

@Test(arguments: [0, 1, 32, 63, 65, 128])
func malformedSignatureLengthsFail(count: Int) throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    let bad = Array(signature.prefix(count)) + [UInt8](repeating: 0, count: max(0, count - 64))
    #expect(bad.count == count)
    #expect(!CardSignature.verify(bad, for: message, publicKey: publicBytes(key)))
}

@Test func signatureWithoutDomainDoesNotVerifyAsCardSignature() throws {
    let key = Curve25519.Signing.PrivateKey()
    let raw = Array(try key.signature(for: message))
    #expect(key.publicKey.isValidSignature(raw, for: message))
    #expect(!CardSignature.verify(raw, for: message, publicKey: publicBytes(key)))
}

@Test func cardSignatureIsEd25519OverDomainAndMessage() throws {
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(message, with: key)
    #expect(!key.publicKey.isValidSignature(signature, for: message))
    #expect(key.publicKey.isValidSignature(signature, for: CardSignature.domain + message))
}

@Test func messageCarryingTheDomainItselfIsStillSeparated() throws {
    // Signing `domain || m` as a card must not verify as a card over `domain || domain || m` or `m`.
    let key = Curve25519.Signing.PrivateKey()
    let signature = try CardSignature.sign(CardSignature.domain + message, with: key)
    #expect(CardSignature.verify(signature, for: CardSignature.domain + message, publicKey: publicBytes(key)))
    #expect(!CardSignature.verify(signature, for: message, publicKey: publicBytes(key)))
}

@Test func personaKeysFromIdentityInteroperate() throws {
    let identity = Identity.generate()
    let signature = try CardSignature.sign(message, with: identity.personaSigningKey(index: 0))
    #expect(CardSignature.verify(signature, for: message, publicKey: Array(identity.personaSigningKey(index: 0).publicKey.rawRepresentation)))
    #expect(!CardSignature.verify(signature, for: message, publicKey: Array(identity.personaSigningKey(index: 1).publicKey.rawRepresentation)))
}

@Test func verifyNeverThrowsOnGarbage() {
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<200 {
        let signature = (0..<Int.random(in: 0...80, using: &rng)).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        let publicKey = (0..<Int.random(in: 0...40, using: &rng)).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        let bytes = (0..<Int.random(in: 0...40, using: &rng)).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        #expect(!CardSignature.verify(signature, for: bytes, publicKey: publicKey))
    }
}
