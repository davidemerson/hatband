import Testing
@testable import HatbandCore

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String($0, radix: 16).leftPadded() }.joined()
}

private extension String {
    func leftPadded() -> String { count == 1 ? "0" + self : self }
}

/// RFC 7914 §11 (the two PBKDF2-HMAC-SHA-256 vectors), the widely
/// published "password"/"salt" set, and cases from Python's hashlib covering
/// empty inputs and outputs that are not whole SHA-256 blocks.
private let vectors: [(password: String, salt: String, iterations: Int, keyLength: Int, expected: String)] = [
    ("passwd", "salt", 1, 64,
     "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"),
    ("Password", "NaCl", 80000, 64,
     "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d"),
    ("password", "salt", 1, 32, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"),
    ("password", "salt", 2, 32, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"),
    ("password", "salt", 4096, 32, "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"),
    ("passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 40,
     "348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9"),
    ("", "salt", 1000, 32, "94fb56af3ea22e5d3ed1b054085b136ca301b75d8b406c802c489479f27387c6"),
    ("password", "", 1000, 32, "26939681d19995a2cefb7b90d13e1343f09b30f0abbd07416a23b9bc3c5b3536"),
    ("hatband", "headband", 3, 100,
     "2e6b5ff9a3b26be6f3216a27d8ba70e3050e14d524b480d5ee25c0681046268dc32bf0d294441ccce8beb6a32f187493d2cf967eab4841d4ef4ee22ee105ba849736b9d55b0a9f2c5bf28b151bdeffc4f2d5c5b3bbe6ca040e26c525f35c1489c07a32d0"),
    ("hatband", "headband", 3, 33, "2e6b5ff9a3b26be6f3216a27d8ba70e3050e14d524b480d5ee25c0681046268dc3"),
    ("hatband", "headband", 3, 1, "2e"),
]

@Test(arguments: vectors)
func matchesPublishedVectors(password: String, salt: String, iterations: Int, keyLength: Int, expected: String) {
    let key = PBKDF2.deriveKey(password: Array(password.utf8), salt: Array(salt.utf8),
                               iterations: iterations, keyLength: keyLength)
    #expect(key.count == keyLength)
    #expect(hex(key) == expected)
}

@Test func outputIsPrefixConsistentAcrossBlockBoundaries() {
    let password = Array("hatband".utf8)
    let salt = Array("headband".utf8)
    let long = PBKDF2.deriveKey(password: password, salt: salt, iterations: 3, keyLength: 100)
    for length in [0, 1, 31, 32, 33, 63, 64, 65, 96, 99, 100] {
        let key = PBKDF2.deriveKey(password: password, salt: salt, iterations: 3, keyLength: length)
        #expect(key.count == length)
        #expect(key == Array(long.prefix(length)))
    }
}

@Test func firstBlockIsHMACOfSaltAndBigEndianOne() {
    // RFC 8018 §5.2: U_1 = PRF(P, S || INT(i)), T_i = U_1 for c = 1.
    let password = Array("Password".utf8)
    let salt = Array("NaCl".utf8)
    let key = SymmetricKey(data: password)
    let block1 = Array(HMAC<SHA256>.authenticationCode(for: salt + [0, 0, 0, 1], using: key))
    let block2 = Array(HMAC<SHA256>.authenticationCode(for: salt + [0, 0, 0, 2], using: key))
    #expect(PBKDF2.deriveKey(password: password, salt: salt, iterations: 1, keyLength: 64) == block1 + block2)
}

@Test func secondIterationXorsTheChain() {
    let password = Array("Password".utf8)
    let salt = Array("NaCl".utf8)
    let key = SymmetricKey(data: password)
    let u1 = Array(HMAC<SHA256>.authenticationCode(for: salt + [0, 0, 0, 1], using: key))
    let u2 = Array(HMAC<SHA256>.authenticationCode(for: u1, using: key))
    let expected = zip(u1, u2).map { $0 ^ $1 }
    #expect(PBKDF2.deriveKey(password: password, salt: salt, iterations: 2, keyLength: 32) == expected)
}

@Test func everyInputBitMatters() {
    let password = Array("password".utf8)
    let salt = Array("salt".utf8)
    let base = PBKDF2.deriveKey(password: password, salt: salt, iterations: 10, keyLength: 32)
    var otherPassword = password
    otherPassword[0] ^= 0x01
    #expect(PBKDF2.deriveKey(password: otherPassword, salt: salt, iterations: 10, keyLength: 32) != base)
    var otherSalt = salt
    otherSalt[3] ^= 0x80
    #expect(PBKDF2.deriveKey(password: password, salt: otherSalt, iterations: 10, keyLength: 32) != base)
    #expect(PBKDF2.deriveKey(password: password, salt: salt, iterations: 11, keyLength: 32) != base)
    #expect(PBKDF2.deriveKey(password: password, salt: salt + [0], iterations: 10, keyLength: 32) != base)
    // Except a trailing NUL on a short password: HMAC zero-pads keys to its
    // 64-byte block (RFC 2104 §2), so "password" and "password\0" are one key.
    #expect(PBKDF2.deriveKey(password: password + [0], salt: salt, iterations: 10, keyLength: 32) == base)
}

@Test func passwordsLongerThanTheHMACBlockWork() {
    // HMAC hashes keys over 64 bytes first; the derivation must not care.
    let long = [UInt8](repeating: 0x61, count: 200)
    let key = PBKDF2.deriveKey(password: long, salt: Array("salt".utf8), iterations: 2, keyLength: 32)
    let hashed = Array(SHA256.hash(data: long))
    #expect(key == PBKDF2.deriveKey(password: hashed, salt: Array("salt".utf8), iterations: 2, keyLength: 32))
}

/// The export default. Measured here: 0.4 s optimized, 1.2 s debug alone,
/// about 2 s debug with the rest of the suite running. Debug builds also run
/// swift-crypto unoptimized, hence the slack.
@Test func sixHundredThousandIterationsCompleteQuickly() {
    #if DEBUG
    let limit: Duration = .seconds(6)
    #else
    let limit: Duration = .seconds(3)
    #endif
    let clock = ContinuousClock()
    var key: [UInt8] = []
    let elapsed = clock.measure {
        key = PBKDF2.deriveKey(password: Array("correct horse battery staple".utf8),
                               salt: Array(UInt8(0)...15), iterations: 600_000, keyLength: 32)
    }
    print("PBKDF2-HMAC-SHA256, 600000 iterations, 32 bytes: \(elapsed)")
    #expect(key.count == 32)
    #expect(elapsed < limit)
}
