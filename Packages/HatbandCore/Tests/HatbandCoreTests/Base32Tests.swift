import Testing
@testable import HatbandCore

/// RFC 4648 §10, without padding.
private let vectors: [(String, String)] = [
    ("", ""), ("f", "MY"), ("fo", "MZXQ"), ("foo", "MZXW6"), ("foob", "MZXW6YQ"),
    ("fooba", "MZXW6YTB"), ("foobar", "MZXW6YTBOI"),
]

@Test(arguments: vectors)
func encodesRFCVectors(plain: String, encoded: String) {
    #expect(Base32.encode(Array(plain.utf8)) == encoded)
}

@Test(arguments: vectors)
func decodesRFCVectors(plain: String, encoded: String) throws {
    #expect(try Base32.decode(encoded) == Array(plain.utf8))
    #expect(try Base32.decode(encoded.lowercased()) == Array(plain.utf8))
}

@Test func decodesPaddedInput() throws {
    #expect(try Base32.decode("MY======") == Array("f".utf8))
    #expect(try Base32.decode("MZXW6===") == Array("foo".utf8))
}

@Test func roundTripsAllByteValuesAndLengths() throws {
    for length in 0...64 {
        let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
        let text = Base32.encode(bytes)
        #expect(text.utf8.count == (length * 8 + 4) / 5)
        #expect(text.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0) })
        #expect(try Base32.decode(text) == bytes)
    }
    let all = Array(UInt8.min...UInt8.max)
    #expect(try Base32.decode(Base32.encode(all)) == all)
}

@Test(arguments: [
    ("M", Base32.Error.invalidLength), ("MZX", .invalidLength), ("MZXW6Y", .invalidLength),
    ("MY1", .invalidCharacter), ("M Y", .invalidCharacter), ("MY=A", .invalidCharacter),
    ("MZ", .nonZeroPadding), ("MZXW7", .nonZeroPadding),
])
func rejectsMalformed(text: String, error: Base32.Error) {
    #expect(throws: error) { try Base32.decode(text) }
}
