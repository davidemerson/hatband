import Testing
@testable import HatbandCore

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

private func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var iterator = hex.makeIterator()
    while let high = iterator.next(), let low = iterator.next() {
        out.append(UInt8(String([high, low]), radix: 16)!)
    }
    return out
}

/// SHA-256 of 32 zero bytes and of 00..1f, from Python's hashlib.
private let zeroKeyHex = "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925"
private let sequentialKeyHex = "630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd"

@Test func matchesSHA256Vectors() throws {
    let zero = try #require(KeyFingerprint(publicKey: [UInt8](repeating: 0, count: 32)))
    #expect(zero.hex == zeroKeyHex)
    #expect(zero.full == bytes(zeroKeyHex))
    let sequential = try #require(KeyFingerprint(publicKey: Array(UInt8(0)...31)))
    #expect(sequential.hex == sequentialKeyHex)
}

@Test func shortIsFirstEightBytes() throws {
    let fingerprint = try #require(KeyFingerprint(publicKey: [UInt8](repeating: 0, count: 32)))
    #expect(fingerprint.full.count == 32)
    #expect(fingerprint.short.count == 8)
    #expect(fingerprint.short == Array(fingerprint.full.prefix(8)))
    #expect(fingerprint.short == bytes("66687aadf862bd77"))
}

@Test(arguments: [0, 1, 31, 33, 64])
func rejectsKeysThatAreNot32Bytes(count: Int) {
    #expect(KeyFingerprint(publicKey: [UInt8](repeating: 1, count: count)) == nil)
}

@Test func typedAndRawKeysAgree() {
    let key = Curve25519.Signing.PrivateKey().publicKey
    let typed = KeyFingerprint(publicKey: key)
    let raw = KeyFingerprint(publicKey: Array(key.rawRepresentation))
    #expect(typed == raw)
    #expect(typed.hashValue == raw?.hashValue)
}

@Test func hexIsLowercaseAndSixtyFourCharacters() {
    let fingerprint = KeyFingerprint(publicKey: Curve25519.Signing.PrivateKey().publicKey)
    #expect(fingerprint.hex.count == 64)
    #expect(fingerprint.hex.allSatisfy { "0123456789abcdef".contains($0) })
    #expect(bytes(fingerprint.hex) == fingerprint.full)
}

@Test func displayIsTwoLinesOfEightUppercaseGroups() throws {
    let zero = try #require(KeyFingerprint(publicKey: [UInt8](repeating: 0, count: 32)))
    #expect(zero.display == "6668 7AAD F862 BD77 6C8F C18B 8E9F 8E20\n0897 1485 6EE2 33B3 902A 591D 0D5F 2925")
    let fingerprint = KeyFingerprint(publicKey: Curve25519.Signing.PrivateKey().publicKey)
    let lines = fingerprint.display.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 2)
    for line in lines {
        let groups = line.split(separator: " ", omittingEmptySubsequences: false)
        #expect(groups.count == 8)
        #expect(groups.allSatisfy { $0.count == 4 && $0.allSatisfy { "0123456789ABCDEF".contains($0) } })
    }
    let joined = fingerprint.display.filter { $0 != " " && $0 != "\n" }
    #expect(joined == fingerprint.hex.uppercased())
}

@Test func matchesShortFingerprintOfKey() {
    let key = Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
    let short = KeyFingerprint(publicKey: key)!.short
    #expect(KeyFingerprint.matches(short: short, publicKey: key))
    var flipped = short
    flipped[7] ^= 0x01
    #expect(!KeyFingerprint.matches(short: flipped, publicKey: key))
    #expect(!KeyFingerprint.matches(short: Array(short.prefix(7)), publicKey: key))
    #expect(!KeyFingerprint.matches(short: short + [0], publicKey: key))
    #expect(!KeyFingerprint.matches(short: [], publicKey: key))
    #expect(!KeyFingerprint.matches(short: short, publicKey: Array(key.prefix(31))))
    #expect(!KeyFingerprint.matches(short: short, publicKey: key + [0]))
    let other = Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
    #expect(!KeyFingerprint.matches(short: short, publicKey: other))
}

@Test func distinctKeysGiveDistinctShortFingerprints() {
    var shorts = Set<[UInt8]>()
    for _ in 0..<256 {
        shorts.insert(KeyFingerprint(publicKey: Curve25519.Signing.PrivateKey().publicKey).short)
    }
    #expect(shorts.count == 256)
}

@Test func fingerprintsAreIndifferentToSmallOrderKeys() {
    // Key 19 hashes whatever bytes it is given; whether a key can sign is
    // `CardSignature.verify`'s business, and the two must not be coupled.
    let identity = [1] + [UInt8](repeating: 0, count: 31)
    let orderTwo = [0xec] + [UInt8](repeating: 0xff, count: 30) + [0x7f]
    let orderFour = [UInt8](repeating: 0, count: 32)
    for key in [identity, orderTwo, orderFour] {
        #expect(KeyFingerprint(publicKey: key)?.full.count == 32)
        #expect(KeyFingerprint.matches(short: KeyFingerprint(publicKey: key)!.short, publicKey: key))
        #expect(!CardSignature.isAcceptablePublicKey(key))
    }
}

@Test func personaFingerprintsAreStableAcrossDerivations() throws {
    let identity = try Identity(seed: Array(UInt8(0)...31))
    let a = KeyFingerprint(publicKey: identity.personaSigningKey(index: 5).publicKey)
    let b = KeyFingerprint(publicKey: identity.personaSigningKey(index: 5).publicKey)
    #expect(a == b)
    #expect(a != KeyFingerprint(publicKey: identity.personaSigningKey(index: 6).publicKey))
}
