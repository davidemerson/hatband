import Testing
@testable import HatbandCore

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Review of the Crypto hardening. Pins the small-order list to the fixture's
// derivation, probes the sign-bit and y < p edges the key check rests on,
// takes a forged small-order card through the URL form, and records the
// container-length caveat.

private func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var iterator = hex.makeIterator()
    while let high = iterator.next(), let low = iterator.next() {
        out.append(UInt8(String([high, low]), radix: 16)!)
    }
    return out
}

private func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { let s = String($0, radix: 16); return s.count == 1 ? "0" + s : s }.joined()
}

private let zeroS = [UInt8](repeating: 0, count: 32)
private let identityPoint = [1] + [UInt8](repeating: 0, count: 31)
private let personaID: [UInt8] = [8, 7, 6, 5, 4, 3, 2, 1]

/// Tests/Fixtures/ed25519_small_order.py, verbatim: the eight canonical
/// encodings of the points whose order divides 8.
private let derivedTorsion = [
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000080",
    "0100000000000000000000000000000000000000000000000000000000000000",
    "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
    "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
    "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
    "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
    "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
].map(bytes)

/// libsodium's blocklist, ed25519_ref10.c, all seven entries in order.
private let libsodiumBlocklist = [
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0100000000000000000000000000000000000000000000000000000000000000",
    "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
    "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
    "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
    "edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
    "eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
].map(bytes)

private func masked(_ key: [UInt8]) -> [UInt8] {
    var y = key
    y[31] &= 0x7f
    return y
}

private func negated(_ key: [UInt8]) -> [UInt8] {
    var flipped = key
    flipped[31] ^= 0x80
    return flipped
}

// MARK: - Small-order and non-canonical keys

@Test func smallOrderListIsExactlyTheFixturesDerivation() {
    // A typo in the list would turn away one honest key in 2^255, which no
    // random test would ever see; pin it to the independent derivation.
    #expect(Set(CardSignature.smallOrderY) == Set(derivedTorsion.map(masked)))
    #expect(CardSignature.smallOrderY.count == 5)
    #expect(Set(libsodiumBlocklist.prefix(5)) == Set(CardSignature.smallOrderY))
    // The two entries left out are p and p + 1, which y < p already refuses.
    #expect(libsodiumBlocklist[5] == CardSignature.fieldPrime)
    var pPlusOne = CardSignature.fieldPrime
    pPlusOne[0] += 1
    #expect(libsodiumBlocklist[6] == pPlusOne)
    #expect(Set(derivedTorsion).count == 8)
}

@Test func everyBlocklistEntryIsRejectedWithEitherSignBit() {
    // libsodium compares with the sign bit masked; so must this check, since
    // 0100..80 and ecff..ff are not in the fixture's canonical list yet
    // decode (in BoringSSL) to the identity and the point of order 2.
    let message = Array("Bloomsday".utf8)
    var seen: Set<[UInt8]> = []
    for entry in libsodiumBlocklist + derivedTorsion {
        for sign: UInt8 in [0, 0x80] {
            var key = masked(entry)
            key[31] |= sign
            seen.insert(key)
            #expect(!CardSignature.isAcceptablePublicKey(key), "\(hex(key))")
            for r in derivedTorsion {
                #expect(!CardSignature.verify(r + zeroS, for: message, publicKey: key), "key \(hex(key)) R \(hex(r))")
            }
        }
    }
    #expect(seen.count == 14)
    #expect(seen.contains(negated(identityPoint)))
    #expect(seen.contains([0xec] + [UInt8](repeating: 0xff, count: 31)))
}

#if !canImport(CryptoKit)
@Test func boringSSLAloneAcceptsTheForgeryTheCheckRefuses() throws {
    // Why the check precedes the library, recorded where it reproduces:
    // swift-crypto verifies R = identity, S = 0 under the identity key,
    // with either sign bit, over any message.
    let message = CardSignature.domain + Array("anything at all".utf8)
    for key in [identityPoint, negated(identityPoint)] {
        let library = try Curve25519.Signing.PublicKey(rawRepresentation: key)
        #expect(library.isValidSignature(identityPoint + zeroS, for: message), "\(hex(key))")
        #expect(!CardSignature.verify(identityPoint + zeroS, for: Array("anything at all".utf8), publicKey: key), "\(hex(key))")
    }
}
#endif

@Test func theLargestCanonicalKeyBelowPIsAccepted() {
    // y = p - 2 is the largest canonical y on the curve outside the torsion
    // subgroup (p - 1 is the point of order 2), per the fixture's decode: the
    // y < p test must be a strict comparison of all 255 bits, not of a prefix.
    let key = bytes("eaffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f")
    #expect(CardSignature.isAcceptablePublicKey(key))
    #expect(CardSignature.isAcceptablePublicKey(negated(key)))
    let orderTwo = bytes("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f")
    #expect(!CardSignature.isAcceptablePublicKey(orderTwo))
    #expect(!CardSignature.isAcceptablePublicKey(CardSignature.fieldPrime))
    // Nobody holds the key, so no torsion R forges under it either.
    for r in derivedTorsion {
        #expect(!CardSignature.verify(r + zeroS, for: [], publicKey: key), "\(hex(r))")
    }
    // The comparison is little-endian aware: p's low byte with a zero high
    // byte is tiny, and p's high byte with a zero low byte is still below p.
    var lowByteOfP = CardSignature.fieldPrime
    lowByteOfP[31] = 0
    #expect(CardSignature.isAcceptablePublicKey(lowByteOfP))
    var highBytesOfP = CardSignature.fieldPrime
    highBytesOfP[0] = 0
    #expect(CardSignature.isAcceptablePublicKey(highBytesOfP))
}

@Test func forgedSmallOrderCardNeverReadsAsValidOffAURL() throws {
    // The attack path: a card off a QR code carrying a torsion key and a
    // torsion R with S = 0. The codec checks only lengths, so it decodes,
    // reads as signed, and must never read as valid, whatever R is.
    var card = Card(personaID: personaID, issuedDay: 2438)
    card.name = "Nobody"
    for key in derivedTorsion {
        for r in derivedTorsion {
            let forged = card.withSignature(r + zeroS, publicKey: key)
            let decoded = try HB1.decode(url: HB1.url(for: forged))
            #expect(decoded.isSigned, "key \(hex(key.prefix(2))) R \(hex(r.prefix(2)))")
            #expect(!decoded.signatureIsValid, "key \(hex(key.prefix(2))) R \(hex(r.prefix(2)))")
            #expect(!CardSignature.verify(r + zeroS, for: decoded.signingBytes, publicKey: key))
        }
    }
    // And the same card honestly signed is fine, so the codec is not what refused it.
    let honest = try card.signed(with: Curve25519.Signing.PrivateKey())
    #expect(try HB1.decode(url: HB1.url(for: honest)).signatureIsValid)
}

// MARK: - Identity equality

@Test func identityEqualityAgreesWithSeedEqualityOnRandomPairs() {
    for _ in 0..<64 {
        let a = Identity.generate()
        let b = Identity.generate()
        #expect((a == b) == (a.seed == b.seed))
        #expect(a == a && b == b)
        #expect((try? Identity(seed: a.seed)) == a)
    }
    // Two seeds differing in every byte, and in only the last bit of the last byte.
    let low = [UInt8](repeating: 0x00, count: 32)
    let high = [UInt8](repeating: 0xff, count: 32)
    #expect((try? Identity(seed: low)) != (try? Identity(seed: high)))
    #expect((try? Identity(seed: low)) != (try? Identity(seed: Array(low.dropLast()) + [0x01])))
}

// MARK: - Export container

private let passphrase = "correct horse battery staple"
private let iterations = ExportContainer.iterationRange.lowerBound

@Test func containerLengthIsThePlaintextLengthPlusAConstant() throws {
    // README caveat: the container hides the plaintext, not its length. It
    // is 44 header bytes, the body's CBOR length prefix, the plaintext and
    // the 16-byte tag; the prefix widens at bodies of 24, 256 and 65536.
    for (count, prefix) in [(0, 1), (7, 1), (8, 2), (240, 3), (65_519, 3), (65_520, 5)] {
        let plaintext = [UInt8](repeating: 0x42, count: count)
        let container = try ExportContainer.seal(plaintext, passphrase: passphrase, iterations: iterations)
        #expect(container.count == 44 + prefix + count + 16, "\(count) bytes")
    }
    #expect(ExportContainer.headerLength == 44 + 5)
    // The 49-byte header assumes a four-byte iteration count at both ends of the range.
    #expect(CBOR.unsigned(UInt64(ExportContainer.iterationRange.lowerBound)).encoded.count == 5)
    #expect(CBOR.unsigned(UInt64(ExportContainer.iterationRange.upperBound)).encoded.count == 5)
}

@Test func mapShapeCheckStopsAtTwentyThreeEntries() throws {
    // The initial-byte check admits any definite map of up to 23 entries so
    // a later version can still be answered `unsupportedVersion`; at 24 the
    // map header changes width and the input is refused before decoding.
    var map = try #require(try CBOR.decode(try ExportContainer.seal([1], passphrase: passphrase, iterations: iterations)).mapValue)
    map[0] = .unsigned(2)
    for key in 6..<23 { map[.unsigned(UInt64(key))] = .null }
    let twentyThree = CBOR.map(map).encoded
    #expect(twentyThree.first == 0xb7)
    #expect(throws: ExportError.unsupportedVersion) { try ExportContainer.open(twentyThree, passphrase: passphrase) }
    map[23] = .null
    let twentyFour = CBOR.map(map).encoded
    #expect(twentyFour.first == 0xb8)
    #expect(throws: ExportError.malformed) { try ExportContainer.open(twentyFour, passphrase: passphrase) }
    // An empty map passes the byte check and is refused by the decoder for want of a version.
    #expect(throws: ExportError.malformed) { try ExportContainer.open([0xa0], passphrase: passphrase) }
    // A version-1 map with a seventh key still fails the entry count, not the version.
    var seven = map
    seven[0] = .unsigned(1)
    for key in 7..<24 { seven[.unsigned(UInt64(key))] = nil }
    #expect(seven.count == 7)
    #expect(throws: ExportError.malformed) { try ExportContainer.open(CBOR.map(seven).encoded, passphrase: passphrase) }
}

@Test func sealBoundIsCheckedOnPlaintextNotOnTheContainer() throws {
    // One byte over the bound throws before any work; the bound itself is
    // documented in terms of what `open` will take back.
    #expect(ExportContainer.maxPlaintextSize == ExportContainer.maxContainerSize - 49 - 16)
    #expect(throws: ExportError.tooLarge) {
        try ExportContainer.seal([UInt8](repeating: 0, count: ExportContainer.maxPlaintextSize + 1),
                                 passphrase: passphrase, iterations: iterations)
    }
    #expect(throws: ExportError.tooLarge) {
        try ExportContainer.seal([UInt8](repeating: 0, count: ExportContainer.maxContainerSize),
                                 passphrase: passphrase, iterations: iterations)
    }
}
