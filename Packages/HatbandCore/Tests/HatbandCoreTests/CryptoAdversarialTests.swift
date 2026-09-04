import Testing
@testable import HatbandCore

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Adversarial review of the Crypto area. Vectors marked "reference" come from
// a pure-Python Ed25519 after ed25519.cr.yp.to (checked against RFC 8032 §7.1
// TEST 1), Python's hmac/hashlib, and the EFF wordlist file itself, so they
// do not depend on swift-crypto or on the implementation under test.

private func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var iterator = hex.makeIterator()
    while let high = iterator.next(), let low = iterator.next() {
        out.append(UInt8(String([high, low]), radix: 16)!)
    }
    return out
}

private func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String($0, radix: 16).leftPadded() }.joined()
}

private extension String {
    func leftPadded() -> String { count == 1 ? "0" + self : self }
}

private let seed = Array(UInt8(0)...31)
private let iterations = ExportContainer.iterationRange.lowerBound

/// Replays a fixed sequence, then saturates. Never all-zero: `Int.random`
/// rejection-samples, and a generator stuck on zero would spin forever.
private struct ScriptedRNG: RandomNumberGenerator {
    var values: [UInt64]
    mutating func next() -> UInt64 { values.isEmpty ? .max : values.removeFirst() }
}

private func cborEntry(_ key: CBOR, _ value: CBOR) -> [UInt8] { key.encoded + value.encoded }

private func fields(_ container: [UInt8]) throws -> [CBOR: CBOR] {
    try #require(try CBOR.decode(container).mapValue)
}

// MARK: - Identity

@Test func identityIsHKDFExtractThenExpandWithTheHatbandSalt() throws {
    // RFC 5869 by hand on HMAC alone, so a silent change of salt, info or
    // the CryptoKit HKDF entry point would show.
    let identity = try Identity(seed: seed)
    let prk = SymmetricKey(data: HMAC<SHA256>.authenticationCode(for: seed, using: SymmetricKey(data: Array("hatband".utf8))))
    for index: UInt32 in [0, 5, 4_294_967_295] {
        let signing = Array(HMAC<SHA256>.authenticationCode(for: Array("hatband/v1/persona/\(index)".utf8) + [1], using: prk))
        let agreement = Array(HMAC<SHA256>.authenticationCode(for: Array("hatband/v1/persona-x25519/\(index)".utf8) + [1], using: prk))
        #expect(Array(identity.personaSigningKey(index: index).rawRepresentation) == signing)
        #expect(Array(identity.personaAgreementKey(index: index).rawRepresentation) == agreement)
    }
}

@Test func identityRejectsEverySeedLengthButThirtyTwo() {
    for count in 0...64 where count != 32 {
        #expect(throws: Identity.Error.invalidSeedLength, "\(count) bytes") {
            try Identity(seed: [UInt8](repeating: 0x5a, count: count))
        }
    }
    #expect(throws: Never.self) { try Identity(seed: [UInt8](repeating: 0x5a, count: 32)) }
}

@Test func everySeedBytePositionInfluencesTheDerivedKeys() throws {
    let base = try Identity(seed: seed)
    let signing = Array(base.personaSigningKey(index: 0).rawRepresentation)
    let agreement = Array(base.personaAgreementKey(index: 0).rawRepresentation)
    for position in 0..<32 {
        var other = seed
        other[position] ^= 0x80
        let identity = try Identity(seed: other)
        #expect(Array(identity.personaSigningKey(index: 0).rawRepresentation) != signing, "position \(position)")
        #expect(Array(identity.personaAgreementKey(index: 0).rawRepresentation) != agreement, "position \(position)")
    }
}

@Test func generatedSeedsVaryInEveryBytePosition() {
    // Catches a random source that returns constants or a stuck low byte.
    let seeds = (0..<256).map { _ in Identity.generate().seed }
    #expect(Set(seeds).count == 256)
    for position in 0..<32 {
        #expect(Set(seeds.map { $0[position] }).count >= 64, "position \(position)")
    }
}

// MARK: - Card signatures

/// Reference Ed25519 over `"hatband-card-v1" || message` under persona 0 of
/// seed 00..1f (public key dc5b87a3…, matching IdentityTests). Deterministic
/// per RFC 8032 §5.1.6; CryptoKit on Apple randomizes, BoringSSL does not.
private let referencePublicKey = bytes("dc5b87a3de54d883016d5e5519d11431c20b97ad4a9a1d3ef1802cdd9a2c6140")
private let referenceSignatures: [(message: [UInt8], signature: String)] = [
    ([], "d2e4f1da1059785dc98cd053a1b897f37df39c0571b8767a6593b7b6a3945c7185a1fad22e9f6635d120566f97ca20d4cb0f6a7d46d3695511266694f3423804"),
    (Array("Henry Flower".utf8),
     "57a481348d5c60d86235c07bc8e0e1b0a4fb943ee90a3f324d8b86a3e52b8c0f78ab9ea7a6a5aae29d8d2aba1c2bdc94cbd96a7b322fc6569c1ac3b1367cce0a"),
    (Array(UInt8(0)...63),
     "c0119a8c48ae9538016c527080935dde491c0ba08772e7e0742e6d3ecc8c4f014cd48903c6a5f460d0b2608f2b2ea4f98256cf5dab4e69dcec20c69cdc97ae02"),
]

@Test(arguments: referenceSignatures)
func referenceSignaturesVerifyAsCardSignatures(message: [UInt8], signature: String) throws {
    let key = try Identity(seed: seed).personaSigningKey(index: 0)
    #expect(Array(key.publicKey.rawRepresentation) == referencePublicKey)
    #expect(CardSignature.verify(bytes(signature), for: message, publicKey: referencePublicKey))
    #expect(!CardSignature.verify(bytes(signature), for: message + [0], publicKey: referencePublicKey))
    #if !canImport(CryptoKit)
    #expect(try CardSignature.sign(message, with: key) == bytes(signature), "BoringSSL Ed25519 is deterministic")
    #endif
}

/// The group order L, little-endian: S + L encodes the same residue.
private let groupOrder = bytes("edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010")

@Test func signatureWithSPlusGroupOrderIsRejected() throws {
    // RFC 8032 §5.1.7 requires S < L; accepting S + L would make every card
    // signature malleable without the key.
    let key = Curve25519.Signing.PrivateKey()
    let message = Array("Bloomsday".utf8)
    let signature = try CardSignature.sign(message, with: key)
    var s = Array(signature[32...])
    var carry: UInt16 = 0
    for i in 0..<32 {
        let sum = UInt16(s[i]) + UInt16(groupOrder[i]) + carry
        s[i] = UInt8(sum & 0xff)
        carry = sum >> 8
    }
    #expect(carry == 0, "S + L fits in 32 bytes because S < L < 2^253")
    let malleated = Array(signature[..<32]) + s
    #expect(malleated != signature)
    #expect(!CardSignature.verify(malleated, for: message, publicKey: Array(key.publicKey.rawRepresentation)))
    for bit: UInt8 in [0x20, 0x40, 0x80] {
        var high = signature
        high[63] |= bit
        #expect(!CardSignature.verify(high, for: message, publicKey: Array(key.publicKey.rawRepresentation)))
    }
}

/// The eight canonical encodings of the points whose order divides 8: the
/// identity, the point of order 2, both of order 4 and the four of order 8.
/// Derived in Tests/Fixtures/ed25519_small_order.py by multiplying a random
/// curve point by L and enumerating the multiples of the result; they match
/// libsodium's blocklist. Random keys there have order L, never dividing 8.
private let smallOrderPoints: [[UInt8]] = [
    [1] + [UInt8](repeating: 0, count: 31),
    [0xec] + [UInt8](repeating: 0xff, count: 30) + [0x7f],
    [UInt8](repeating: 0, count: 32),
    [UInt8](repeating: 0, count: 31) + [0x80],
    bytes("26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05"),
    bytes("26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85"),
    bytes("c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a"),
    bytes("c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa"),
]
private let zeroS = [UInt8](repeating: 0, count: 32)

@Test func smallOrderPublicKeysAreRejected() {
    // With A of small order and S = 0, [S]B = 0 = R + [k]A for some R in the
    // same subgroup whatever the message, so anyone could "sign" for such a
    // key: a card carrying one would show as verified and anyone could issue
    // signed updates for it. RFC 8032 does not require rejecting these keys
    // and BoringSSL does not; `verify` does, before the library sees the key,
    // on every platform. Fingerprints stay indifferent: key 19 hashes bytes.
    let messages = [Array("Henry Flower".utf8), Array("Leopold Bloom".utf8), [], [0xff]]
    for publicKey in smallOrderPoints {
        #expect(!CardSignature.isAcceptablePublicKey(publicKey), "\(hex(publicKey))")
        #expect(KeyFingerprint(publicKey: publicKey) != nil, "\(hex(publicKey))")
        for message in messages {
            let forgeries = smallOrderPoints.filter {
                CardSignature.verify($0 + zeroS, for: message, publicKey: publicKey)
            }
            #expect(forgeries.isEmpty, "key \(hex(publicKey.prefix(2))) forged with R \(forgeries.map { hex($0.prefix(2)) })")
        }
    }
}

@Test func nonCanonicalPublicKeysAreRejected() {
    // RFC 8032 §5.1.3 step 1: y, the low 255 bits, must be below p. Values
    // p...p + 18 and 2^255 - 1 still fit, and BoringSSL reduces rather than
    // fails, so p + 1 would decode as the identity and p + 2 as y = 2.
    let message = Array("Bloomsday".utf8)
    for offset: UInt8 in 0...18 {
        for sign: UInt8 in [0, 0x80] {
            var key = CardSignature.fieldPrime
            key[0] += offset
            key[31] |= sign
            #expect(!CardSignature.isAcceptablePublicKey(key), "\(hex(key))")
            #expect(!CardSignature.verify(smallOrderPoints[0] + zeroS, for: message, publicKey: key), "\(hex(key))")
        }
    }
    let top = [UInt8](repeating: 0xff, count: 31) + [0x7f]
    #expect(!CardSignature.isAcceptablePublicKey(top))
    #expect(!CardSignature.isAcceptablePublicKey(top.dropLast() + [0xff]))
    #expect(CardSignature.fieldPrime == bytes("edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"))
}

@Test func honestPublicKeysAreAccepted() throws {
    // The key check must never turn away a key anyone can actually hold.
    let identity = try Identity(seed: seed)
    for index: UInt32 in 0..<8 {
        let publicKey = Array(identity.personaSigningKey(index: index).publicKey.rawRepresentation)
        #expect(CardSignature.isAcceptablePublicKey(publicKey), "persona \(index)")
    }
    for _ in 0..<64 {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = Array(key.publicKey.rawRepresentation)
        #expect(CardSignature.isAcceptablePublicKey(publicKey))
        let signature = try CardSignature.sign([1, 2, 3], with: key)
        #expect(CardSignature.verify(signature, for: [1, 2, 3], publicKey: publicKey))
    }
    #expect(CardSignature.isAcceptablePublicKey(referencePublicKey))
}

@Test func verifyRejectsEveryPublicKeyLengthButThirtyTwo() throws {
    let key = Curve25519.Signing.PrivateKey()
    let message = Array("m".utf8)
    let signature = try CardSignature.sign(message, with: key)
    let publicKey = Array(key.publicKey.rawRepresentation)
    for count in 0...64 where count != 32 {
        let bad = Array((publicKey + publicKey).prefix(count))
        #expect(!CardSignature.verify(signature, for: message, publicKey: bad), "\(count) bytes")
    }
}

@Test func verifyRejectsEverySignatureLengthButSixtyFour() throws {
    let key = Curve25519.Signing.PrivateKey()
    let message = Array("m".utf8)
    let signature = try CardSignature.sign(message, with: key)
    let publicKey = Array(key.publicKey.rawRepresentation)
    for count in 0...128 where count != 64 {
        let bad = Array((signature + signature + signature).prefix(count))
        #expect(!CardSignature.verify(bad, for: message, publicKey: publicKey), "\(count) bytes")
    }
}

@Test func randomKeysAndMessagesRoundTripAndNeverCrossVerify() throws {
    var rng = SystemRandomNumberGenerator()
    var previous: (signature: [UInt8], message: [UInt8], publicKey: [UInt8])?
    for _ in 0..<32 {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = Array(key.publicKey.rawRepresentation)
        let message = (0..<Int.random(in: 0...300, using: &rng)).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        let signature = try CardSignature.sign(message, with: key)
        #expect(CardSignature.verify(signature, for: message, publicKey: publicKey))
        if let previous {
            #expect(!CardSignature.verify(previous.signature, for: message, publicKey: publicKey))
            #expect(!CardSignature.verify(signature, for: previous.message, publicKey: publicKey))
            #expect(!CardSignature.verify(signature, for: message, publicKey: previous.publicKey))
        }
        previous = (signature, message, publicKey)
    }
}

@Test func signsAndVerifiesOneMegabyte() throws {
    let key = Curve25519.Signing.PrivateKey()
    var message = (0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 131) }
    let signature = try CardSignature.sign(message, with: key)
    #expect(CardSignature.verify(signature, for: message, publicKey: Array(key.publicKey.rawRepresentation)))
    message[message.count - 1] ^= 1
    #expect(!CardSignature.verify(signature, for: message, publicKey: Array(key.publicKey.rawRepresentation)))
}

// MARK: - Key fingerprints

@Test func fingerprintOfPersonaZeroMatchesTheReference() throws {
    // SHA-256 of the reference public key, from hashlib.
    let fingerprint = try #require(KeyFingerprint(publicKey: referencePublicKey))
    #expect(fingerprint.hex == "0d3311678b3d4d4c03fb3c79cb3ee3c05f84dee07785c3d1bc532b0f1f9419a9")
    #expect(fingerprint.display == "0D33 1167 8B3D 4D4C 03FB 3C79 CB3E E3C0\n5F84 DEE0 7785 C3D1 BC53 2B0F 1F94 19A9")
    #expect(fingerprint.short == bytes("0d3311678b3d4d4c"))
    #expect(KeyFingerprint(publicKey: try Identity(seed: seed).personaSigningKey(index: 0).publicKey) == fingerprint)
}

@Test func displayIsExactlyHexRegroupedForRandomKeys() {
    let allowed = Set("0123456789ABCDEF \n")
    for _ in 0..<50 {
        let fingerprint = KeyFingerprint(publicKey: Curve25519.Signing.PrivateKey().publicKey)
        let display = fingerprint.display
        #expect(display.count == 64 + 14 + 1)
        #expect(display.allSatisfy { allowed.contains($0) })
        #expect(display.filter { $0 != " " && $0 != "\n" }.lowercased() == fingerprint.hex)
        #expect(display.split(separator: "\n").allSatisfy { $0.count == 39 })
    }
}

@Test func matchesRejectsEveryShortLengthButEight() {
    let publicKey = Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
    let full = KeyFingerprint(publicKey: publicKey)!.full
    for count in 0...32 where count != 8 {
        #expect(!KeyFingerprint.matches(short: Array(full.prefix(count)), publicKey: publicKey), "\(count) bytes")
    }
    #expect(KeyFingerprint.matches(short: Array(full.prefix(8)), publicKey: publicKey))
    #expect(!KeyFingerprint.matches(short: Array(full[1..<9]), publicKey: publicKey), "an offset window")
}

// MARK: - PBKDF2

/// hashlib.pbkdf2_hmac at the HMAC key boundary (64-byte block, RFC 2104 §2),
/// over long inputs spanning three output blocks, and at odd lengths.
private let boundaryVectors: [(password: [UInt8], salt: [UInt8], iterations: Int, keyLength: Int, expected: String)] = [
    ([UInt8](repeating: 0x61, count: 64), Array("salt".utf8), 2, 32,
     "9deb671f3cea57338c2909d9accd07f6fc5b5c5ac6f7f4be99361aa5d70306a5"),
    ([UInt8](repeating: 0x61, count: 65), Array("salt".utf8), 2, 32,
     "9f3e73a7a18ef815e92cfde43cccc37df2e505e2e62cad65b1ccd33521fc680d"),
    (Array(UInt8(0)...99), Array((1...200).reversed().map { UInt8($0) }), 5, 65,
     "20af94c2d3f2cc2e2b7b932e9bcacb96d84ba9232a1c0e99960b539b396ee746bb0ba375dde70911c6e21226695e0f05ef6c48bd25e90ec78e31c69c8adf9beaf9"),
    ([], [], 1, 32, "f7ce0b653d2d72a4108cf5abe912ffdd777616dbbb27a70e8204f3ae2d0f6fad"),
    (Array("Leopold".utf8), Array("Bloom".utf8), 7, 96,
     "b955bd01e79bfe6ad206b81353341e18275d362bc62521750e3962d62dc4d08218b3bf1f31cdb5740dd6a46feae3a01d173fc73b1dcc3e16f4cdcf39a63c75d82661cdb70053ecd371087c9837cb91935406bd03c12f76bdcfbfb900d8f10ee9"),
    ([0], [0xff], 1000, 20, "d072a96ad421f63344b15dc130523f53f4d85afa"),
]

@Test(arguments: boundaryVectors)
func matchesHashlibAtBoundaries(password: [UInt8], salt: [UInt8], iterations: Int, keyLength: Int, expected: String) {
    let key = PBKDF2.deriveKey(password: password, salt: salt, iterations: iterations, keyLength: keyLength)
    #expect(hex(key) == expected)
}

@Test func hmacKeyBoundaryIsSixtyFourBytes() {
    // A 65-byte password is HMAC-keyed by its SHA-256; a 64-byte one is not.
    let salt = Array("salt".utf8)
    let sixtyFour = [UInt8](repeating: 0x61, count: 64)
    let sixtyFive = [UInt8](repeating: 0x61, count: 65)
    #expect(PBKDF2.deriveKey(password: sixtyFour, salt: salt, iterations: 2, keyLength: 32)
            != PBKDF2.deriveKey(password: Array(SHA256.hash(data: sixtyFour)), salt: salt, iterations: 2, keyLength: 32))
    #expect(PBKDF2.deriveKey(password: sixtyFive, salt: salt, iterations: 2, keyLength: 32)
            == PBKDF2.deriveKey(password: Array(SHA256.hash(data: sixtyFive)), salt: salt, iterations: 2, keyLength: 32))
}

@Test func zeroKeyLengthDerivesNothing() {
    #expect(PBKDF2.deriveKey(password: [1], salt: [2], iterations: 1, keyLength: 0) == [])
}

@Test func nonPositiveIterationsTrap() async {
    await #expect(processExitsWith: .failure) {
        _ = PBKDF2.deriveKey(password: [1], salt: [2], iterations: 0, keyLength: 32)
    }
    await #expect(processExitsWith: .failure) {
        _ = PBKDF2.deriveKey(password: [1], salt: [2], iterations: 1, keyLength: -1)
    }
}

// MARK: - Export container

@Test func compatibilityEquivalentPassphrasesOpenTheSameContainer() throws {
    // NFKD, not NFD: compatibility characters fold to their plain forms.
    let container = try ExportContainer.seal([1], passphrase: "1 ffi e\u{0301}", iterations: iterations)
    #expect(try ExportContainer.open(container, passphrase: "\u{2460} \u{FB03} \u{00E9}") == [1], "① ﬃ é")
    #expect(throws: ExportError.wrongPassphraseOrTampered) {
        try ExportContainer.open(container, passphrase: "1 ffl e\u{0301}")
    }
}

@Test func trailingNULsInAPassphraseAreInvisible() throws {
    // HMAC zero-pads keys shorter than its block (RFC 2104 §2), so PBKDF2
    // cannot tell "a" from "a\0"; nor "" from "\0". Inherent to the KDF,
    // recorded so the behaviour is a decision rather than a surprise.
    let container = try ExportContainer.seal([7], passphrase: "a", iterations: iterations)
    #expect(try ExportContainer.open(container, passphrase: "a\u{0}") == [7])
    #expect(try ExportContainer.open(container, passphrase: "a\u{0}\u{0}") == [7])
    #expect(throws: ExportError.wrongPassphraseOrTampered) { try ExportContainer.open(container, passphrase: "\u{0}a") }
}

@Test func headersAndBodiesFromDifferentContainersDoNotMix() throws {
    let a = try fields(try ExportContainer.seal([1], passphrase: "p", iterations: iterations))
    let b = try fields(try ExportContainer.seal([1], passphrase: "p", iterations: iterations))
    var bodySwapped = a
    bodySwapped[5] = b[5]
    var saltSwapped = a
    saltSwapped[3] = b[3]
    var nonceSwapped = a
    nonceSwapped[4] = b[4]
    for (label, map) in [("body", bodySwapped), ("salt", saltSwapped), ("nonce", nonceSwapped)] {
        #expect(throws: ExportError.wrongPassphraseOrTampered, "\(label)") {
            try ExportContainer.open(CBOR.map(map).encoded, passphrase: "p")
        }
    }
}

@Test func nonDeterministicEncodingsOfAValidContainerAreMalformed() throws {
    let sealed = try ExportContainer.seal([1], passphrase: "p", iterations: iterations)
    let map = try fields(sealed)
    let entries = (0...5).map { cborEntry(.unsigned(UInt64($0)), map[.unsigned(UInt64($0))]!) }
    let salt = try #require(map[3]?.bytesValue)
    let cases: [(String, [UInt8])] = [
        ("keys out of order", [0xa6] + entries[1] + entries[0] + entries[2...].joined()),
        ("duplicate key", [0xa7] + entries[0] + entries.joined()),
        ("iterations in 8 bytes", [0xa6] + entries[0] + entries[1] + [0x02, 0x1b, 0, 0, 0, 0, 0, 0x01, 0x86, 0xa0] + entries[3...].joined()),
        ("indefinite map", [0xbf] + entries.joined() + [0xff]),
        ("indefinite salt", [0xa6] + entries[0...2].joined() + [0x03, 0x5f, 0x50] + salt + [0xff] + entries[4...].joined()),
        ("tagged", [0xd8, 0x2a] + sealed),
        ("version key as text", [0xa6] + entries[1...].joined() + [0x61, 0x30, 0x01]),
        ("version key negative", [0xa6] + entries[1...].joined() + [0x20, 0x01]),
        ("float", [0xfa, 0x3f, 0x80, 0x00, 0x00]),
        ("six keys, nonce missing", [0xa6] + entries[0...3].joined() + entries[5] + [0x06, 0x00]),
    ]
    for (label, container) in cases {
        #expect(throws: ExportError.malformed, "\(label)") {
            try ExportContainer.open(container, passphrase: "p")
        }
    }
    #expect(try ExportContainer.open([0xa6] + entries.joined(), passphrase: "p") == [1], "the same entries in order")
}

@Test func hostileShapesUnderTheSizeCapAreRejectedWithoutTheKDF() {
    // The cap admits 32 MB; what the CBOR decoder does with it must stay
    // cheap. None of these reach PBKDF2, so all are well under one KDF.
    // Sizes kept modest so this does not starve the suite's timing tests:
    // 16M nulls and a 1M-entry map were measured at 1.2 s and 1.6 s alone.
    let clock = ContinuousClock()
    let nulls = 1 << 20
    let array: [UInt8] = [0x9a, UInt8(nulls >> 24), UInt8((nulls >> 16) & 0xff), UInt8((nulls >> 8) & 0xff), UInt8(nulls & 0xff)]
        + [UInt8](repeating: 0xf6, count: nulls)
    let nested = [UInt8](repeating: 0x81, count: ExportContainer.maxContainerSize - 1) + [0x00]
    let byteString: [UInt8] = [0x5a, 0x01, 0xff, 0xff, 0xfb] + [UInt8](repeating: 0, count: ExportContainer.maxContainerSize - 5)
    var wideMap: [UInt8] = [0xba, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01]
    for key in 1..<(1 << 18) {
        wideMap += CBOR.unsigned(UInt64(key)).encoded
        wideMap.append(0x00)
    }
    for (label, container, limit) in [("1M-element array", array, Duration.seconds(2)),
                                      ("32 MB nesting", nested, .seconds(1)),
                                      ("32 MB byte string", byteString, .seconds(1)),
                                      ("256K-entry map", wideMap, .seconds(3))] {
        let elapsed = clock.measure {
            #expect(throws: ExportError.malformed, "\(label)") { try ExportContainer.open(container, passphrase: "p") }
        }
        #expect(elapsed < limit, "\(label) took \(elapsed)")
    }
}

@Test func neitherPlaintextNorPassphraseAppearsInTheContainer() throws {
    let plaintext = Array("No fixed abode. Henry Flower, c/o P.O. Westland Row.".utf8)
    let passphrase = "correct horse battery staple"
    let container = try ExportContainer.seal(plaintext, passphrase: passphrase, iterations: iterations)
    func contains(_ needle: [UInt8]) -> Bool {
        guard needle.count <= container.count else { return false }
        return (0...(container.count - needle.count)).contains { container[$0..<$0 + needle.count].elementsEqual(needle) }
    }
    #expect(!contains(Array(plaintext.prefix(8))))
    #expect(!contains(Array(plaintext.suffix(8))))
    #expect(!contains(Array(passphrase.utf8.prefix(8))))
    #expect(container.count == plaintext.count + 16 + 46, "no padding: the length is public")
}

// MARK: - Passphrases

@Test func wordlistHashesLikeTheEFFFile() {
    // SHA-256 of the words column of eff_large_wordlist.txt joined by "\n".
    let joined = Array(Passphrase.wordlist.joined(separator: "\n").utf8)
    #expect(hex(SHA256.hash(data: joined)) == "abae49761b88f3f1ba31ef944bea1f61b795a3cd7e1cfb7d276ed45bf77967ba")
    #expect(Passphrase.wordlist.reduce(0) { $0 + $1.utf8.count } == 54368)
}

@Test func noWordIsAPrefixOfAnother() {
    let words = Set(Passphrase.wordlist)
    for word in Passphrase.wordlist {
        for length in 1..<word.count {
            #expect(!words.contains(String(word.prefix(length))), "\(word)")
        }
    }
}

@Test func drawsAreUniformNotModular() {
    // Int.random rejection-samples: 1 maps to the first word and UInt64.max
    // to the last. A modulo draw would give "abdomen" and index 6207.
    var low = ScriptedRNG(values: [1])
    #expect(Passphrase.generate(words: 1, using: &low) == "abacus")
    var high = ScriptedRNG(values: [.max])
    #expect(Passphrase.generate(words: 1, using: &high) == "zoom")
    var both = ScriptedRNG(values: [1, .max, 1])
    #expect(Passphrase.generate(words: 3, using: &both) == "abacus zoom abacus")
}

@Test func zeroWordsIsTheEmptyPassphrase() {
    var rng = ScriptedRNG(values: [])
    #expect(Passphrase.generate(words: 0, using: &rng) == "")
    #expect(Passphrase.generate(words: 0) == "")
}

@Test func negativeWordsTrap() async {
    await #expect(processExitsWith: .failure) {
        _ = Passphrase.generate(words: -1)
    }
}

// MARK: - Cards end to end

@Test func signedCardSurvivesURLAndFileForms() throws {
    let identity = try Identity(seed: seed)
    let key = identity.personaSigningKey(index: 2)
    let publicKey = Array(key.publicKey.rawRepresentation)
    var card = Card(personaID: [1, 2, 3, 4, 5, 6, 7, 8], issuedDay: 2438)
    card.name = "Henry Flower"
    card.email = "henry.flower@example.ie"
    card.seq = 3
    card.publicKey = publicKey
    let signed = card.withSignature(try CardSignature.sign(card.signingBytes, with: key), publicKey: publicKey)
    for decoded in [try HB1.decode(url: HB1.url(for: signed)), try HB1.decode(file: HB1.fileBytes(for: signed))] {
        #expect(decoded == signed)
        let signature = try #require(decoded.signature)
        let key = try #require(decoded.publicKey)
        #expect(CardSignature.verify(signature, for: decoded.signingBytes, publicKey: key))
        #expect(KeyFingerprint.matches(short: KeyFingerprint(publicKey: key)!.short, publicKey: key))
        var renamed = decoded
        renamed.name = "Leopold Bloom"
        #expect(!CardSignature.verify(signature, for: renamed.signingBytes, publicKey: key))
        var bumped = decoded
        bumped.seq += 1
        #expect(!CardSignature.verify(signature, for: bumped.signingBytes, publicKey: key))
        var rekeyed = decoded
        rekeyed.publicKey = Array(identity.personaSigningKey(index: 3).publicKey.rawRepresentation)
        #expect(!CardSignature.verify(signature, for: rekeyed.signingBytes, publicKey: rekeyed.publicKey!))
    }
}

@Test func signingBeforeSettingThePublicKeyDoesNotVerify() throws {
    // `signingBytes` covers key 14 and `withSignature` sets it, so a card
    // signed before it carried the key never verifies. `signed(with:)` fixes
    // the order; `withSignature` only re-attaches a signature to the bytes
    // it was made over.
    let key = try Identity(seed: seed).personaSigningKey(index: 2)
    let publicKey = Array(key.publicKey.rawRepresentation)
    let card = Card(personaID: [1, 2, 3, 4, 5, 6, 7, 8], issuedDay: 2438)
    let trap = card.withSignature(try CardSignature.sign(card.signingBytes, with: key), publicKey: publicKey)
    #expect(!trap.signatureIsValid)
    let signed = try card.signed(with: key)
    #expect(signed.signatureIsValid)
    #expect(signed.publicKey == publicKey)
    #expect(signed.signingBytes != card.signingBytes, "the key is under the signature")
    #expect(signed.withSignature(try #require(signed.signature), publicKey: publicKey) == signed)
}
