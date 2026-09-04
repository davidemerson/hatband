import Testing
@testable import HatbandCore

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@Test func formatVersionIsOne() {
    #expect(HatbandCore.formatVersion == 1)
}

@Test func cryptoBackendSignsAndVerifies() throws {
    let key = Curve25519.Signing.PrivateKey()
    let message = Array("hatband".utf8)
    let signature = try key.signature(for: message)
    #expect(key.publicKey.isValidSignature(signature, for: message))
    #expect(!key.publicKey.isValidSignature(signature, for: Array("hatbands".utf8)))
}
