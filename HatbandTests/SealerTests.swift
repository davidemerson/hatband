import CryptoKit
import Foundation
import Testing
@testable import Hatband

struct SealerTests {
    private let key = SymmetricKey(size: .bits256)
    private let id = Data([1, 2, 3, 4, 5, 6, 7, 8])
    private let plaintext: [UInt8] = Array("Henry Flower, Westland Row".utf8)

    private var aad: Data {
        Sealer.aad(domain: Sealer.personDomain, id: id)
    }

    @Test func roundTrip() throws {
        let sealed = try Sealer.seal(plaintext, key: key, aad: aad)
        #expect(try Sealer.open(sealed, key: key, aad: aad) == plaintext)
    }

    @Test func wrongKeyThrows() throws {
        let sealed = try Sealer.seal(plaintext, key: key, aad: aad)
        let other = SymmetricKey(size: .bits256)
        #expect(throws: (any Error).self) {
            try Sealer.open(sealed, key: other, aad: aad)
        }
    }

    @Test func wrongIDThrows() throws {
        let sealed = try Sealer.seal(plaintext, key: key, aad: aad)
        let otherAAD = Sealer.aad(domain: Sealer.personDomain, id: Data([8, 7, 6, 5, 4, 3, 2, 1]))
        #expect(throws: (any Error).self) {
            try Sealer.open(sealed, key: key, aad: otherAAD)
        }
    }

    @Test func wrongDomainThrows() throws {
        let sealed = try Sealer.seal(plaintext, key: key, aad: aad)
        let otherAAD = Sealer.aad(domain: "hatband/person/v2", id: id)
        #expect(throws: (any Error).self) {
            try Sealer.open(sealed, key: key, aad: otherAAD)
        }
    }

    @Test func tamperedByteThrows() throws {
        var sealed = try Sealer.seal(plaintext, key: key, aad: aad)
        let middle = sealed.count / 2
        sealed[middle] ^= 0x01
        #expect(throws: (any Error).self) {
            try Sealer.open(sealed, key: key, aad: aad)
        }
    }

    @Test func aadLayout() {
        let aad = Sealer.aad(domain: "ab", id: Data([9, 8]))
        #expect(Array(aad) == [0x61, 0x62, 0x00, 9, 8])
        let person = Sealer.aad(domain: Sealer.personDomain, id: id)
        #expect(Array(person) == Array("hatband/person/v1".utf8) + [0] + Array(id))
    }

    @Test func freshNonceEachSeal() throws {
        let first = try Sealer.seal(plaintext, key: key, aad: aad)
        let second = try Sealer.seal(plaintext, key: key, aad: aad)
        #expect(first != second)
    }
}
