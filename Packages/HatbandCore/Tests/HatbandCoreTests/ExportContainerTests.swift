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

/// The floor of the accepted range: the cheapest legal container.
private let iterations = ExportContainer.iterationRange.lowerBound
private let passphrase = "correct horse battery staple"
private let plaintext = Array("Henry Flower".utf8)
/// One container shared by the tampering tests, so each pays for a single KDF.
private let sealed = try! ExportContainer.seal(plaintext, passphrase: passphrase, iterations: iterations)

/// Sealed by an independent Python implementation: hashlib PBKDF2, CBOR by
/// hand, ChaCha20-Poly1305 written from RFC 8439 and checked against its
/// §2.8.2 vector. Salt 00..0f, nonce 20..2b, 100000 iterations.
private let independentContainer = bytes(
    "a600010101021a000186a00350000102030405060708090a0b0c0d0e0f044c202122232425262728292a2b"
        + "05581c273b5ce980917163c081a3f821d2aac8862909fe483c90080ec7da6e")
/// Same salt and nonce, empty plaintext, passphrase "ﬁ Å" (U+FB01, U+00C5)
/// NFKD-normalized before PBKDF2.
private let independentNFKDContainer = bytes(
    "a600010101021a000186a00350000102030405060708090a0b0c0d0e0f044c202122232425262728292a2b"
        + "05500576009af7712e15fbfcdd6e82ec66d1")

private func fields(_ container: [UInt8]) throws -> [CBOR: CBOR] {
    try #require(try CBOR.decode(container).mapValue)
}

private func rebuilt(_ container: [UInt8], _ change: (inout [CBOR: CBOR]) -> Void) throws -> [UInt8] {
    var map = try fields(container)
    change(&map)
    return CBOR.map(map).encoded
}

@Test func roundTripsShortPlaintext() throws {
    #expect(try ExportContainer.open(sealed, passphrase: passphrase) == plaintext)
}

@Test func roundTripsEmptyPlaintext() throws {
    let container = try ExportContainer.seal([], passphrase: passphrase, iterations: iterations)
    #expect(try fields(container)[5]?.bytesValue?.count == 16, "only the tag")
    #expect(try ExportContainer.open(container, passphrase: passphrase) == [])
}

@Test func roundTripsOneMegabyte() throws {
    let big = (0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
    let container = try ExportContainer.seal(big, passphrase: passphrase, iterations: iterations)
    #expect(container.count == big.count + 16 + 49, "16-byte tag and a 49-byte header")
    #expect(try ExportContainer.open(container, passphrase: passphrase) == big)
}

@Test(arguments: ["Henry Flower — Bloomsday 1904 🌸", "", " ", "ﬁ Å", String(repeating: "x", count: 1000)])
func roundTripsAnyPassphrase(passphrase: String) throws {
    let container = try ExportContainer.seal(plaintext, passphrase: passphrase, iterations: iterations)
    #expect(try ExportContainer.open(container, passphrase: passphrase) == plaintext)
    #expect(throws: ExportError.wrongPassphraseOrTampered) {
        try ExportContainer.open(container, passphrase: passphrase + "!")
    }
}

@Test func containerIsTheDocumentedMap() throws {
    let map = try fields(sealed)
    #expect(map.count == 6)
    #expect(map[0] == 1)
    #expect(map[1] == 1)
    #expect(map[2] == .unsigned(UInt64(iterations)))
    #expect(map[3]?.bytesValue?.count == 16)
    #expect(map[4]?.bytesValue?.count == 12)
    #expect(map[5]?.bytesValue?.count == plaintext.count + 16)
    #expect(sealed.count == 74)
    #expect(Array(sealed.prefix(11)) == bytes("a600010101021a000186a0"))
    #expect(ExportContainer.formatVersion == 1 && ExportContainer.kdfPBKDF2 == 1)
    #expect(ExportContainer.iterationRange == 100_000...10_000_000)
    #expect(ExportContainer.maxContainerSize == 32 * 1024 * 1024)
    #expect(ExportContainer.maxPlaintextSize == 32 * 1024 * 1024 - 49 - 16)
}

@Test func sealingTwiceGivesUnrelatedContainers() throws {
    let again = try ExportContainer.seal(plaintext, passphrase: passphrase, iterations: iterations)
    let a = try fields(sealed)
    let b = try fields(again)
    #expect(a[3] != b[3], "fresh salt")
    #expect(a[4] != b[4], "fresh nonce")
    #expect(a[5] != b[5])
    #expect(try ExportContainer.open(again, passphrase: passphrase) == plaintext)
}

@Test func defaultsToSixHundredThousandIterations() throws {
    #expect(ExportContainer.defaultIterations == 600_000)
    let container = try ExportContainer.seal(plaintext, passphrase: passphrase)
    #expect(try fields(container)[2] == 600_000)
}

@Test(arguments: ["correct horse battery staple ", "Correct horse battery staple", "correct horse battery stapl", ""])
func wrongPassphraseIsRejected(wrong: String) {
    #expect(throws: ExportError.wrongPassphraseOrTampered) {
        try ExportContainer.open(sealed, passphrase: wrong)
    }
}

@Test func tamperedCiphertextOrTagIsRejected() throws {
    let body = try #require(try fields(sealed)[5]?.bytesValue)
    for offset in [0, body.count / 2, body.count - 17, body.count - 16, body.count - 1] {
        var tampered = body
        tampered[offset] ^= 0x01
        let container = try rebuilt(sealed) { $0[5] = .bytes(tampered) }
        #expect(throws: ExportError.wrongPassphraseOrTampered, "offset \(offset)") {
            try ExportContainer.open(container, passphrase: passphrase)
        }
    }
}

@Test func shortenedBodyIsRejected() throws {
    let body = try #require(try fields(sealed)[5]?.bytesValue)
    let missingOne = try rebuilt(sealed) { $0[5] = .bytes(Array(body.dropLast())) }
    #expect(throws: ExportError.wrongPassphraseOrTampered) { try ExportContainer.open(missingOne, passphrase: passphrase) }
    let tagOnly = try rebuilt(sealed) { $0[5] = .bytes(Array(body.suffix(16))) }
    #expect(throws: ExportError.wrongPassphraseOrTampered) { try ExportContainer.open(tagOnly, passphrase: passphrase) }
    let lessThanATag = try rebuilt(sealed) { $0[5] = .bytes(Array(body.suffix(15))) }
    #expect(throws: ExportError.malformed) { try ExportContainer.open(lessThanATag, passphrase: passphrase) }
}

@Test func changedIterationCountFailsAuthentication() throws {
    let container = try rebuilt(sealed) { $0[2] = 200_000 }
    #expect(throws: ExportError.wrongPassphraseOrTampered) { try ExportContainer.open(container, passphrase: passphrase) }
}

@Test func changedSaltFailsAuthentication() throws {
    var salt = try #require(try fields(sealed)[3]?.bytesValue)
    salt[0] ^= 0x80
    let container = try rebuilt(sealed) { $0[3] = .bytes(salt) }
    #expect(throws: ExportError.wrongPassphraseOrTampered) { try ExportContainer.open(container, passphrase: passphrase) }
}

@Test func changedNonceFailsAuthentication() throws {
    var nonce = try #require(try fields(sealed)[4]?.bytesValue)
    nonce[11] ^= 0x01
    let container = try rebuilt(sealed) { $0[4] = .bytes(nonce) }
    #expect(throws: ExportError.wrongPassphraseOrTampered) { try ExportContainer.open(container, passphrase: passphrase) }
}

@Test(arguments: [0, 2, 255, UInt64.max])
func unsupportedVersionIsRejected(version: UInt64) throws {
    let container = try rebuilt(sealed) { $0[0] = .unsigned(version) }
    #expect(throws: ExportError.unsupportedVersion) { try ExportContainer.open(container, passphrase: passphrase) }
}

@Test func unsupportedVersionWinsOverOtherHeaderFaults() throws {
    // A future format may change every other key; the version says so first.
    let container = try rebuilt(sealed) { $0[0] = 2; $0[1] = 9; $0[2] = 1; $0[3] = "salt"; $0[7] = .null }
    #expect(throws: ExportError.unsupportedVersion) { try ExportContainer.open(container, passphrase: passphrase) }
}

@Test(arguments: [0, 2, UInt64.max])
func unsupportedKDFIsRejected(kdf: UInt64) throws {
    let container = try rebuilt(sealed) { $0[1] = .unsigned(kdf) }
    #expect(throws: ExportError.unsupportedKDF) { try ExportContainer.open(container, passphrase: passphrase) }
}

@Test(arguments: [0, 1, 99_999, 10_000_001, UInt64(Int.max), UInt64.max])
func iterationsOutOfRangeIsRejectedBeforeAnyWork(count: UInt64) throws {
    let container = try rebuilt(sealed) { $0[2] = .unsigned(count) }
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        #expect(throws: ExportError.iterationsOutOfRange) { try ExportContainer.open(container, passphrase: passphrase) }
    }
    #expect(elapsed < .milliseconds(100))
}

@Test(arguments: [Int.min, -1, 0, 1, 99_999, 10_000_001, Int.max])
func sealRejectsIterationsOutOfRange(count: Int) {
    #expect(throws: ExportError.iterationsOutOfRange) {
        try ExportContainer.seal(plaintext, passphrase: passphrase, iterations: count)
    }
}

@Test func sealRejectsOversizePlaintextBeforeTheKDF() {
    let plaintext = [UInt8](repeating: 0, count: ExportContainer.maxPlaintextSize + 1)
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        #expect(throws: ExportError.tooLarge) {
            try ExportContainer.seal(plaintext, passphrase: passphrase, iterations: iterations)
        }
    }
    #expect(elapsed < .milliseconds(100), "\(elapsed)")
    #expect(throws: ExportError.iterationsOutOfRange, "the iteration count is checked first") {
        try ExportContainer.seal(plaintext, passphrase: passphrase, iterations: 1)
    }
}

@Test func sealsAndOpensTheLargestPlaintext() throws {
    // The bound is exact: the container just fits `maxContainerSize`.
    let big = [UInt8](repeating: 0x5a, count: ExportContainer.maxPlaintextSize)
    let container = try ExportContainer.seal(big, passphrase: passphrase, iterations: iterations)
    #expect(container.count == ExportContainer.maxContainerSize)
    #expect(try ExportContainer.open(container, passphrase: passphrase) == big)
}

@Test func nonMapInputIsRejectedWithoutDecoding() {
    // The initial byte must open a definite map of under 24 entries;
    // anything else is refused before the CBOR decoder runs, however large.
    // A 32 MiB decode is about a second in debug, so the bound below shows
    // none happened. The entry count itself is left to the decoder so that
    // a later version with a different header can still say so.
    let size = ExportContainer.maxContainerSize
    let byteString: [UInt8] = [0x5a, 0x01, 0xff, 0xff, 0xfb] + [UInt8](repeating: 0, count: size - 5)
    let array: [UInt8] = [0x9a, 0x01, 0xff, 0xff, 0xfb] + [UInt8](repeating: 0xf6, count: size - 5)
    var wideMap: [UInt8] = [0xba, 0x00, 0x04, 0x00, 0x00]
    for key in 0..<(1 << 18) {
        wideMap += CBOR.unsigned(UInt64(key)).encoded
        wideMap.append(0x00)
    }
    let cases: [(String, [UInt8])] = [
        ("32 MiB byte string", byteString),
        ("32 MiB array", array),
        ("256K-entry map", wideMap),
        ("24-entry map", [0xb8, 0x18] + sealed.dropFirst()),
        ("indefinite map", [0xbf] + sealed.dropFirst() + [0xff]),
        ("tagged", [0xd8, 0x2a] + sealed),
        ("text", CBOR.text("hatband").encoded),
        ("empty", []),
    ]
    let clock = ContinuousClock()
    for (label, container) in cases {
        let elapsed = clock.measure {
            #expect(throws: ExportError.malformed, "\(label)") { try ExportContainer.open(container, passphrase: passphrase) }
        }
        #expect(elapsed < .milliseconds(50), "\(label) took \(elapsed)")
    }
    #expect(ExportContainer.mapInitialBytes == 0xa0...0xb7)
    #expect(sealed.first == 0xa6)
}

@Test func everyTruncationIsMalformed() {
    for length in 0..<sealed.count {
        #expect(throws: ExportError.malformed, "prefix of \(length) bytes") {
            try ExportContainer.open(Array(sealed.prefix(length)), passphrase: passphrase)
        }
    }
}

@Test func trailingBytesAreMalformed() {
    #expect(throws: ExportError.malformed) { try ExportContainer.open(sealed + [0], passphrase: passphrase) }
}

@Test func malformedShapesAreRejected() throws {
    let salt = try #require(try fields(sealed)[3]?.bytesValue)
    let nonce = try #require(try fields(sealed)[4]?.bytesValue)
    let body = try #require(try fields(sealed)[5]?.bytesValue)
    let cases: [(String, [UInt8])] = [
        ("empty", []),
        ("not CBOR", [0xff]),
        ("array", CBOR.array([1, 1]).encoded),
        ("text", CBOR.text("hatband").encoded),
        ("integer", CBOR.unsigned(1).encoded),
        ("no body", try rebuilt(sealed) { $0[5] = nil }),
        ("extra key", try rebuilt(sealed) { $0[6] = 0 }),
        ("body under another key", try rebuilt(sealed) { $0[7] = $0[5]; $0[5] = nil }),
        ("no version", try rebuilt(sealed) { $0[0] = nil }),
        ("version as text", try rebuilt(sealed) { $0[0] = "1" }),
        ("version negative", try rebuilt(sealed) { $0[0] = -1 }),
        ("kdf as text", try rebuilt(sealed) { $0[1] = "pbkdf2" }),
        ("iterations as text", try rebuilt(sealed) { $0[2] = "100000" }),
        ("iterations negative", try rebuilt(sealed) { $0[2] = -100_000 }),
        ("salt as text", try rebuilt(sealed) { $0[3] = "0123456789abcdef" }),
        ("salt 15 bytes", try rebuilt(sealed) { $0[3] = .bytes(Array(salt.prefix(15))) }),
        ("salt 17 bytes", try rebuilt(sealed) { $0[3] = .bytes(salt + [0]) }),
        ("salt empty", try rebuilt(sealed) { $0[3] = .bytes([]) }),
        ("nonce 11 bytes", try rebuilt(sealed) { $0[4] = .bytes(Array(nonce.prefix(11))) }),
        ("nonce 13 bytes", try rebuilt(sealed) { $0[4] = .bytes(nonce + [0]) }),
        ("nonce as array", try rebuilt(sealed) { $0[4] = .array(nonce.map { .unsigned(UInt64($0)) }) }),
        ("body as text", try rebuilt(sealed) { $0[5] = "ciphertext" }),
        ("body empty", try rebuilt(sealed) { $0[5] = .bytes([]) }),
        ("body 15 bytes", try rebuilt(sealed) { $0[5] = .bytes(Array(body.prefix(15))) }),
        ("non-canonical length", [0xa6, 0x00, 0x18, 0x01] + Array(sealed.dropFirst(3))),
    ]
    for (label, container) in cases {
        #expect(throws: ExportError.malformed, "\(label)") {
            try ExportContainer.open(container, passphrase: passphrase)
        }
    }
}

@Test func oversizeContainerIsRejectedWithoutDecoding() {
    let limit = ExportContainer.maxContainerSize
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        #expect(throws: ExportError.malformed) {
            try ExportContainer.open([UInt8](repeating: 0xa6, count: limit + 1), passphrase: passphrase)
        }
    }
    #expect(elapsed < .milliseconds(100))
    #expect(throws: ExportError.malformed) {
        try ExportContainer.open([UInt8](repeating: 0xa6, count: limit), passphrase: passphrase)
    }
}

@Test func passphraseIsNFKDNormalized() throws {
    let composed = "ﬁ Å"
    let decomposed = "fi A\u{030A}"
    #expect(composed != decomposed)
    let container = try ExportContainer.seal(plaintext, passphrase: composed, iterations: iterations)
    #expect(try ExportContainer.open(container, passphrase: decomposed) == plaintext)
    #expect(try ExportContainer.open(container, passphrase: "ﬁ A\u{030A}") == plaintext)
    #expect(throws: ExportError.wrongPassphraseOrTampered) { try ExportContainer.open(container, passphrase: "fi A") }
}

@Test func opensContainersSealedByAnIndependentImplementation() throws {
    #expect(try ExportContainer.open(independentContainer, passphrase: passphrase) == plaintext)
    #expect(throws: ExportError.wrongPassphraseOrTampered) {
        try ExportContainer.open(independentContainer, passphrase: "correct horse battery staples")
    }
    #expect(try ExportContainer.open(independentNFKDContainer, passphrase: "ﬁ Å") == [])
    #expect(try ExportContainer.open(independentNFKDContainer, passphrase: "fi A\u{030A}") == [])
}

@Test func additionalDataIsTheHeaderWithoutTheBody() throws {
    // Decrypt by hand exactly as the format is documented.
    var header = try fields(sealed)
    let body = try #require(header.removeValue(forKey: 5)?.bytesValue)
    let salt = try #require(header[3]?.bytesValue)
    let nonce = try #require(header[4]?.bytesValue)
    let aad = CBOR.map(header).encoded
    #expect(aad.first == 0xa5)
    #expect(Array(sealed.prefix(aad.count)) == [0xa6] + aad.dropFirst(), "the header is a prefix of the container")
    let key = SymmetricKey(data: PBKDF2.deriveKey(password: Array(passphrase.utf8), salt: salt,
                                                  iterations: iterations, keyLength: 32))
    let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce),
                                       ciphertext: body.dropLast(16), tag: body.suffix(16))
    #expect(try Array(ChaChaPoly.open(box, using: key, authenticating: aad)) == plaintext)
    #expect(throws: (any Error).self) { try ChaChaPoly.open(box, using: key, authenticating: []) }
    #expect(throws: (any Error).self) { try ChaChaPoly.open(box, using: key, authenticating: sealed) }
}
