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

@Test func repeatedSignaturesAllVerify() throws {
    // CryptoKit randomizes Ed25519, BoringSSL does not; neither is asserted.
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

// MARK: - Card signing

private let personaID: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
private let identity = try! Identity(seed: Array(UInt8(0)...31))

/// Every field, no key or signature: what `signed(with:)` starts from.
private func fullCard() -> Card {
    var card = Card(personaID: personaID, issuedDay: 2438)
    card.name = "Henry Flower"
    card.company = "Freeman's Journal"
    card.phone = "+353871234567"
    card.email = "henry.flower@example.ie"
    card.website = Website(address: "nnix.com/~bloom", insecure: true)
    card.github = "lbloom"
    card.linkedin = "leopold-bloom"
    card.mastodon = "bloom@merveilles.town"
    card.signal = .username([UInt8](repeating: 7, count: 48))
    card.calendly = "bloom/coffee"
    card.ssh = SSHKeyField(kind: 1, bytes: [UInt8](repeating: 9, count: 32))
    card.gpgFingerprint = [UInt8](repeating: 0xab, count: 20)
    card.custom = [CustomField(label: "Pub", value: "Davy Byrne's", kind: .text)]
    card.color = 4
    card.seq = 12
    card.minReader = 1
    card.photo = [0xff, 0xd8, 0xff, 0xe0]
    card.gpgKey = [0x98, 0x33, 0x04]
    return card
}

@Test func signedCardRoundTripsThroughAURL() throws {
    let key = identity.personaSigningKey(index: 2)
    var card = fullCard()
    card.photo = nil
    card.gpgKey = nil
    let signed = try card.signed(with: key)
    #expect(signed.isSigned && signed.signatureIsValid)
    #expect(signed.publicKey == publicBytes(key))
    let decoded = try HB1.decode(url: HB1.url(for: signed))
    #expect(decoded == signed)
    #expect(decoded.signatureIsValid)
    #expect(decoded.signingBytes == signed.signingBytes)
}

@Test func signedCardRoundTripsThroughAFile() throws {
    let key = identity.personaSigningKey(index: 2)
    let signed = try fullCard().signed(with: key)
    let decoded = try HB1.decode(file: HB1.fileBytes(for: signed))
    #expect(decoded == signed)
    #expect(decoded.signatureIsValid)
    #expect(decoded.photo == signed.photo && decoded.gpgKey == signed.gpgKey, "heavy fields are under the signature")
}

@Test func tamperingWithAnyFieldInvalidatesTheSignature() throws {
    let key = identity.personaSigningKey(index: 2)
    let signed = try fullCard().signed(with: key)
    let other = publicBytes(identity.personaSigningKey(index: 3))
    let edits: [(String, (inout Card) -> Void)] = [
        ("flags", { $0.flags.insert(.alias) }),
        ("name", { $0.name = "Leopold Bloom" }),
        ("name removed", { $0.name = nil }),
        ("company", { $0.company = "Evening Telegraph" }),
        ("phone", { $0.phone = "+353871234568" }),
        ("email", { $0.email = "leopold.bloom@example.ie" }),
        ("website address", { $0.website?.address = "nnix.com" }),
        ("website scheme", { $0.website?.insecure = false }),
        ("github", { $0.github = "hflower" }),
        ("linkedin", { $0.linkedin = nil }),
        ("mastodon", { $0.mastodon = "flower@merveilles.town" }),
        ("signal", { $0.signal = .phone("+353871234567") }),
        ("calendly", { $0.calendly = "flower/tea" }),
        ("ssh kind", { $0.ssh?.kind = 2 }),
        ("ssh bytes", { $0.ssh?.bytes[0] ^= 1 }),
        ("gpg fingerprint", { $0.gpgFingerprint?[19] ^= 1 }),
        ("custom value", { $0.custom[0].value = "Barney Kiernan's" }),
        ("custom kind", { $0.custom[0].kind = .url }),
        ("custom added", { $0.custom.append(CustomField(label: "Cat", value: "Pussens")) }),
        ("public key", { $0.publicKey = other }),
        ("signature", { $0.signature?[0] ^= 1 }),
        ("persona id", { $0.personaID[7] ^= 1 }),
        ("issued day", { $0.issuedDay += 1 }),
        ("color", { $0.color = 5 }),
        ("key fingerprint", { $0.keyFingerprint = [UInt8](repeating: 1, count: 8) }),
        ("photo", { $0.photo?[3] ^= 1 }),
        ("seq", { $0.seq += 1 }),
        ("seq zeroed", { $0.seq = 0 }),
        ("min reader", { $0.minReader = nil }),
        ("gpg key", { $0.gpgKey?.append(0) }),
    ]
    for (label, edit) in edits {
        var card = signed
        edit(&card)
        #expect(card != signed, "\(label)")
        #expect(!card.signatureIsValid, "\(label)")
        #expect(try card.signed(with: key).signatureIsValid, "\(label), re-signed")
    }
}

@Test func compactTierFingerprintMatchesThePersonaKey() throws {
    var profile = Profile()
    profile.name = "Henry Flower"
    profile.email = "henry.flower@example.ie"
    let persona = Persona(id: personaID, label: "Flower", keyIndex: 5, channels: [.email], lockScreenChannels: [.email])
    let publicKey = publicBytes(identity.personaSigningKey(index: persona.keyIndex))
    let card = CardBuilder.card(profile: profile, persona: persona, form: .lockScreen, issuedDay: 2438)
        .withKeyFingerprint(of: publicKey)
    #expect(card.isCompact && !card.isSigned && !card.signatureIsValid)
    let short = try #require(card.keyFingerprint)
    #expect(short == KeyFingerprint(publicKey: publicKey)!.short)
    #expect(short == Card.keyFingerprint(for: publicKey))
    #expect(KeyFingerprint.matches(short: short, publicKey: publicKey))
    #expect(!KeyFingerprint.matches(short: short, publicKey: publicBytes(identity.personaSigningKey(index: 6))))
    let decoded = try HB1.decode(url: HB1.url(for: card))
    #expect(decoded.keyFingerprint == short)
    #expect(decoded.publicKey == nil && decoded.signature == nil)
}

@Test func keyFingerprintForRejectsEveryLengthButThirtyTwo() {
    let publicKey = publicBytes(identity.personaSigningKey(index: 0))
    #expect(Card.keyFingerprint(for: publicKey)?.count == 8)
    for count in [0, 1, 8, 31, 33, 64] {
        let bad = Array((publicKey + publicKey).prefix(count))
        #expect(Card.keyFingerprint(for: bad) == nil, "\(count) bytes")
        let cleared = fullCard().withKeyFingerprint(of: publicKey).withKeyFingerprint(of: bad)
        #expect(cleared.keyFingerprint == nil, "\(count) bytes clears a stale fingerprint")
    }
}

@Test func signedReplacesAStaleKeyAndSignature() throws {
    let key = identity.personaSigningKey(index: 2)
    var stale = try fullCard().signed(with: identity.personaSigningKey(index: 3))
    stale.name = "Leopold Bloom"
    #expect(!stale.signatureIsValid)
    let signed = try stale.signed(with: key)
    #expect(signed.publicKey == publicBytes(key))
    #expect(signed.signatureIsValid)
    #expect(try signed.signed(with: key).signatureIsValid, "signing a signed card is fine")
}

@Test func signatureIsValidNeedsBothKeyAndSignature() throws {
    let key = identity.personaSigningKey(index: 2)
    let signed = try fullCard().signed(with: key)
    #expect(!fullCard().signatureIsValid)
    var keyOnly = signed
    keyOnly.signature = nil
    #expect(!keyOnly.signatureIsValid && !keyOnly.isSigned)
    var signatureOnly = signed
    signatureOnly.publicKey = nil
    #expect(!signatureOnly.signatureIsValid && !signatureOnly.isSigned)
    var garbage = signed
    garbage.signature = [UInt8](repeating: 3, count: 64)
    #expect(garbage.isSigned && !garbage.signatureIsValid)
    var smallOrder = signed
    smallOrder.publicKey = [1] + [UInt8](repeating: 0, count: 31)
    smallOrder.signature = [UInt8](repeating: 0, count: 64)
    #expect(smallOrder.isSigned && !smallOrder.signatureIsValid)
}


/// A newer card may carry keys this reader does not know; its signature
/// covers them, and verification must still succeed after a round trip.
@Test func signedCardWithUnknownKeyVerifiesAfterDecode() throws {
    let identity = try Identity(seed: (0..<32).map { UInt8($0) })
    var card = Card(personaID: [1, 2, 3, 4, 5, 6, 7, 8], issuedDay: 2438)
    card.name = "Leopold Bloom"
    card.unknown = [30: .text("v2 field"), .unsigned(31): .unsigned(7)]
    let signed = try card.signed(with: identity.personaSigningKey(index: 1))
    #expect(signed.signatureIsValid)
    let decoded = try HB1.decode(url: HB1.url(for: signed))
    #expect(decoded.unknown.count == 2)
    #expect(decoded.signatureIsValid)
    #expect(try HB1.decode(file: HB1.fileBytes(for: signed)).signatureIsValid)
}
