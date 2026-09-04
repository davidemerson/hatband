import Testing
@testable import HatbandCore

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

private func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String($0, radix: 16).leftPadded() }.joined()
}

private extension String {
    func leftPadded() -> String { count == 1 ? "0" + self : self }
}

private let seed = Array(UInt8(0)...31)

/// HKDF-SHA256 outputs for seed 00..1f and the matching public keys, computed
/// with Python's hmac module and OpenSSL 3.5 independently of swift-crypto.
private let signingVectors: [(index: UInt32, privateKey: String, publicKey: String)] = [
    (0, "7eca78162a12b06680dd2b68e7c3ea097bc3f205f07a3f6288b87add8aa6f09a",
     "dc5b87a3de54d883016d5e5519d11431c20b97ad4a9a1d3ef1802cdd9a2c6140"),
    (1, "4731ac7aa97b92891482902ca19ddfd4c123ac285123c78ec9c1135d9dbd9d7f",
     "a3dcc742d3741c2827adc49f0422532608dfd9148ed49f50b688a9fc0ece1e38"),
    (7, "951b2b3deecbfb57899d26513793e604374c59e1e924943c68b1f9f7554a9c26",
     "88981066af9594e105f1776ee089a7501269919f97d749a054d35eaef11bf7c5"),
    (4294967295, "ede146124aa5d305628e3dde093a65749ff844ccc3be53b97cc780f80dc8d8cc",
     "051dcbe1652981c756addc306a306ea364a28def7f64932cb42172922b4007a4"),
]

private let agreementVectors: [(index: UInt32, privateKey: String, publicKey: String)] = [
    (0, "ad8ecccd047f2cce68d6c1227126f95ffd544b800de49f65b1bed46734f5fa99",
     "380a64d960eefd068fe2e7ca9642f0af595955e1df7ffa3bc66908da9a975068"),
    (1, "c03182d391e4748febf09cd6190e9efc0a70348b878a743942adf31b992985c5",
     "643b4fffe3f2e02c7458db306ec89a7fca06fe4fd2db902c3918bced03dd7433"),
    (7, "824efa2f6955466c6c3d3e38070d6594ec00c474bb939a5e62a28229795d8137",
     "e0fc222d3a53916117a540a24e008fdd844170f01fe0baf6286014787b218a18"),
    (4294967295, "603161855a2390f6512c6865a61f4035ff1b969153d41e25bd8c4149e62c307a",
     "bea7b81a85c88ba4423e70c5d1f1f733cb77b8c3e10fffe699caed814a2d6e14"),
]

@Test func generatesDistinct32ByteSeeds() {
    let a = Identity.generate()
    let b = Identity.generate()
    #expect(a.seed.count == 32 && b.seed.count == 32)
    #expect(a != b)
    #expect(Set(a.seed).count > 4, "32 random bytes are not all alike")
}

@Test(arguments: [0, 1, 16, 31, 33, 64])
func rejectsSeedsThatAreNot32Bytes(count: Int) {
    #expect(throws: Identity.Error.invalidSeedLength) {
        try Identity(seed: [UInt8](repeating: 7, count: count))
    }
}

@Test func keepsTheSeedItWasGiven() throws {
    let identity = try Identity(seed: seed)
    #expect(identity.seed == seed)
    #expect(identity == (try Identity(seed: seed)))
}

@Test(arguments: signingVectors)
func derivesSigningKeysMatchingIndependentVectors(index: UInt32, privateKey: String, publicKey: String) throws {
    let key = try Identity(seed: seed).personaSigningKey(index: index)
    #expect(hex(key.rawRepresentation) == privateKey)
    #expect(hex(key.publicKey.rawRepresentation) == publicKey)
}

@Test(arguments: agreementVectors)
func derivesAgreementKeysMatchingIndependentVectors(index: UInt32, privateKey: String, publicKey: String) throws {
    let key = try Identity(seed: seed).personaAgreementKey(index: index)
    #expect(hex(key.rawRepresentation) == privateKey)
    #expect(hex(key.publicKey.rawRepresentation) == publicKey)
}

@Test func derivationIsDeterministicAcrossCallsAndInstances() throws {
    let a = try Identity(seed: seed)
    let b = try Identity(seed: seed)
    for index: UInt32 in [0, 1, 2, 10, 1000, .max] {
        let signing = Array(a.personaSigningKey(index: index).rawRepresentation)
        #expect(Array(a.personaSigningKey(index: index).rawRepresentation) == signing)
        #expect(Array(b.personaSigningKey(index: index).rawRepresentation) == signing)
        let agreement = Array(a.personaAgreementKey(index: index).rawRepresentation)
        #expect(Array(a.personaAgreementKey(index: index).rawRepresentation) == agreement)
        #expect(Array(b.personaAgreementKey(index: index).rawRepresentation) == agreement)
        #expect(signing != agreement)
    }
}

@Test func indicesGiveIndependentKeys() throws {
    let identity = try Identity(seed: seed)
    var seen = Set<[UInt8]>()
    for index: UInt32 in 0..<64 {
        seen.insert(Array(identity.personaSigningKey(index: index).rawRepresentation))
        seen.insert(Array(identity.personaAgreementKey(index: index).rawRepresentation))
    }
    #expect(seen.count == 128)
}

@Test func indexIsDecimalNotAPrefixMatch() throws {
    // "1" and "10" and "100" differ as info strings; so must the keys.
    let identity = try Identity(seed: seed)
    let keys = [1, 10, 100, 11].map { Array(identity.personaSigningKey(index: UInt32($0)).rawRepresentation) }
    #expect(Set(keys).count == keys.count)
}

@Test func oneSeedBitChangesEveryKey() throws {
    var other = seed
    other[31] ^= 0x01
    let a = try Identity(seed: seed)
    let b = try Identity(seed: other)
    for index: UInt32 in 0..<4 {
        #expect(a.personaSigningKey(index: index).rawRepresentation != b.personaSigningKey(index: index).rawRepresentation)
        #expect(a.personaAgreementKey(index: index).rawRepresentation != b.personaAgreementKey(index: index).rawRepresentation)
    }
}

@Test func derivedSigningKeysSignAndVerify() throws {
    let key = try Identity(seed: seed).personaSigningKey(index: 3)
    let message = Array("Henry Flower".utf8)
    let signature = try key.signature(for: message)
    #expect(key.publicKey.isValidSignature(signature, for: message))
    let other = try Identity(seed: seed).personaSigningKey(index: 4)
    #expect(!other.publicKey.isValidSignature(signature, for: message))
}

@Test func derivedAgreementKeysAgree() throws {
    let mine = try Identity(seed: seed).personaAgreementKey(index: 0)
    let theirs = Identity.generate().personaAgreementKey(index: 0)
    let a = try mine.sharedSecretFromKeyAgreement(with: theirs.publicKey).withUnsafeBytes { Array($0) }
    let b = try theirs.sharedSecretFromKeyAgreement(with: mine.publicKey).withUnsafeBytes { Array($0) }
    #expect(a == b)
    #expect(a.count == 32)
}
