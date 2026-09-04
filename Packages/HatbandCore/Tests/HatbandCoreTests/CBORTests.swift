import Testing
@testable import HatbandCore

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String($0, radix: 16).leftPadded() }.joined()
}

private func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var iterator = hex.makeIterator()
    while let high = iterator.next(), let low = iterator.next() {
        out.append(UInt8(String([high, low]), radix: 16)!)
    }
    return out
}

private extension String {
    func leftPadded() -> String { count == 1 ? "0" + self : self }
}

/// RFC 8949 Appendix A, the subset within the supported types.
private let vectors: [(CBOR, String)] = [
    (0, "00"), (1, "01"), (10, "0a"), (23, "17"), (24, "1818"), (25, "1819"),
    (100, "1864"), (1000, "1903e8"), (1000000, "1a000f4240"),
    (1000000000000, "1b000000e8d4a51000"),
    (.unsigned(18446744073709551615), "1bffffffffffffffff"),
    (-1, "20"), (-10, "29"), (-100, "3863"), (-1000, "3903e7"),
    (.negative(18446744073709551615), "3bffffffffffffffff"),
    (false, "f4"), (true, "f5"), (.null, "f6"),
    (.bytes([]), "40"), (.bytes([1, 2, 3, 4]), "4401020304"),
    ("", "60"), ("a", "6161"), ("IETF", "6449455446"), ("\"\\", "62225c"),
    ("ü", "62c3bc"), ("水", "63e6b0b4"), ("𐅑", "64f0908591"),
    ([], "80"), ([1, 2, 3], "83010203"), ([1, [2, 3], [4, 5]], "8301820203820405"),
    (.array((1...25).map { CBOR.unsigned(UInt64($0)) }),
     "98190102030405060708090a0b0c0d0e0f101112131415161718181819"),
    ([:], "a0"), ([1: 2, 3: 4], "a201020304"), (["a": 1, "b": [2, 3]], "a26161016162820203"),
    (["a", ["b": "c"]], "826161a161626163"),
    (["a": "A", "b": "B", "c": "C", "d": "D", "e": "E"], "a56161614161626142616361436164614461656145"),
]

@Test(arguments: vectors)
func encodesRFCVectors(value: CBOR, expected: String) {
    #expect(hex(value.encoded) == expected)
}

@Test(arguments: vectors)
func decodesRFCVectors(value: CBOR, encoded: String) throws {
    #expect(try CBOR.decode(bytes(encoded)) == value)
}

@Test func mapKeysSortByEncodedBytes() {
    #expect(hex(CBOR.map([10: 1, 1: 2]).encoded) == "a201020a01")
    #expect(hex(CBOR.map([256: 0, 1: 0]).encoded) == "a20100190100 00".replacingOccurrences(of: " ", with: ""))
    #expect(hex(CBOR.map(["b": 1, "a": 2]).encoded) == "a2616102616201")
    // Bytewise, not length-first: "b" (61) precedes "aa" (62 61 61).
    #expect(hex(CBOR.map(["aa": 1, "b": 2]).encoded) == "a2616202626161 01".replacingOccurrences(of: " ", with: ""))
}

@Test(arguments: [
    ("1800", CBORError.notShortestForm),
    ("1817", CBORError.notShortestForm),
    ("1900ff", CBORError.notShortestForm),
    ("1a0000ffff", CBORError.notShortestForm),
    ("1b00000000ffffffff", CBORError.notShortestForm),
    ("5800", CBORError.notShortestForm),
    ("9f", CBORError.indefiniteLength),
    ("5f", CBORError.indefiniteLength),
    ("c000", CBORError.unsupported(majorType: 6, info: 0)),
    ("f93c00", CBORError.unsupported(majorType: 7, info: 25)),
    ("f7", CBORError.unsupported(majorType: 7, info: 23)),
    ("1c", CBORError.unsupported(majorType: 0, info: 28)),
    ("a20a010102", CBORError.mapKeysNotOrdered),
    ("a201010102", CBORError.mapKeysNotOrdered),
    ("a2616201616101", CBORError.mapKeysNotOrdered),
    ("62ffff", CBORError.invalidUTF8),
    ("18", CBORError.truncated),
    ("4401", CBORError.truncated),
    ("820101 01".replacingOccurrences(of: " ", with: ""), CBORError.trailingBytes),
    ("0000", CBORError.trailingBytes),
    ("", CBORError.truncated),
    ("83", CBORError.truncated),
])
func rejectsMalformed(encoded: String, error: CBORError) {
    #expect(throws: error) { try CBOR.decode(bytes(encoded)) }
}

@Test func rejectsDeepNesting() {
    let tooDeep = [UInt8](repeating: 0x81, count: CBOR.maxDepth + 1) + [0x00]
    #expect(throws: CBORError.tooDeep) { try CBOR.decode(tooDeep) }
    let allowed = [UInt8](repeating: 0x81, count: CBOR.maxDepth) + [0x00]
    #expect(throws: Never.self) { try CBOR.decode(allowed) }
}

@Test func hostileLengthDoesNotAllocate() {
    // Claims 2^32 bytes of text with none present.
    #expect(throws: CBORError.truncated) { try CBOR.decode(bytes("7b00000001 00000000".replacingOccurrences(of: " ", with: ""))) }
}

@Test func roundTripsNestedStructure() throws {
    let card: CBOR = [
        0: 3, 1: "Leopold Bloom", 2: "Freeman's Journal", 4: "henry.flower@example.ie",
        13: [["Pub", "Davy Byrne's", 0]], 16: .bytes([1, 2, 3, 4, 5, 6, 7, 8]), 17: 2430,
    ]
    let encoded = card.encoded
    #expect(try CBOR.decode(encoded) == card)
    #expect(try CBOR.decode(encoded).encoded == encoded)
}

@Test func accessors() {
    let value: CBOR = [1: "x", 2: .bytes([9]), 3: [true], 4: -5, 5: .null]
    #expect(value[1]?.textValue == "x")
    #expect(value[2]?.bytesValue == [9])
    #expect(value[3]?.arrayValue?.first?.boolValue == true)
    #expect(value[4]?.intValue == -5)
    #expect(value[5] == .null)
    #expect(value[6] == nil)
    #expect(CBOR.unsigned(UInt64(Int.max) + 1).intValue == nil)
    #expect(CBOR.negative(UInt64(Int.max)).intValue == Int.min)
    #expect(CBOR.negative(UInt64(Int.max) - 1).intValue == Int.min + 1)
}
