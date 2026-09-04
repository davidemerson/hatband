import Testing
@testable import HatbandCore

// Hostile and boundary cases for the deterministic CBOR codec, checked
// against RFC 8949 §3 (well-formedness), §4.2.1 (core deterministic
// encoding), §5.6.1 (key equivalence), Appendix A and Appendix F.

// MARK: - Helpers

/// Parses hex, ignoring spaces.
private func h(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var iterator = hex.filter { $0 != " " }.makeIterator()
    while let high = iterator.next(), let low = iterator.next() {
        out.append(UInt8(String([high, low]), radix: 16)!)
    }
    return out
}

private func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { $0 < 16 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
}

private func bigEndian(_ value: UInt64, bytes: Int) -> [UInt8] {
    stride(from: (bytes - 1) * 8, through: 0, by: -8).map { UInt8(truncatingIfNeeded: value >> UInt64($0)) }
}

/// The invariant every input must satisfy: either the decoder rejects it
/// with a `CBORError`, or the decoded value re-encodes to exactly the input.
/// Anything else means the decoder accepted a non-canonical encoding.
private func canonicalOrRejected(_ bytes: [UInt8]) -> Bool {
    do { return try CBOR.decode(bytes).encoded == bytes } catch is CBORError { return true } catch { return false }
}

/// Rewrites the head at `offset` one argument width wider without changing
/// its value. Returns nil when the head is already 8 bytes wide.
private func inflateHead(_ bytes: [UInt8], at offset: Int) -> [UInt8]? {
    let initial = bytes[offset]
    let major = initial & 0xe0
    let info = initial & 0x1f
    let value: UInt64
    let headLength: Int
    switch info {
    case 0..<24: value = UInt64(info); headLength = 1
    case 24: value = UInt64(bytes[offset + 1]); headLength = 2
    case 25: value = bytes[offset + 1..<offset + 3].reduce(0) { $0 << 8 | UInt64($1) }; headLength = 3
    case 26: value = bytes[offset + 1..<offset + 5].reduce(0) { $0 << 8 | UInt64($1) }; headLength = 5
    default: return nil
    }
    let wider: [UInt8]
    switch info {
    case 0..<24: wider = [major | 24, UInt8(value)]
    case 24: wider = [major | 25] + bigEndian(value, bytes: 2)
    case 25: wider = [major | 26] + bigEndian(value, bytes: 4)
    default: wider = [major | 27] + bigEndian(value, bytes: 8)
    }
    return Array(bytes[..<offset]) + wider + Array(bytes[(offset + headLength)...])
}

/// SplitMix64: a deterministic generator so property tests are reproducible
/// without Foundation.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private enum Gen {
    /// Every argument-width boundary and the signed 64-bit edges.
    static let boundaries: [UInt64] = [
        0, 1, 22, 23, 24, 25, 254, 255, 256, 257, 65534, 65535, 65536, 65537,
        0xffff_fffe, 0xffff_ffff, 0x1_0000_0000, 0x1_0000_0001,
        UInt64(Int.max) - 1, UInt64(Int.max), UInt64(Int.max) + 1, UInt64.max - 1, UInt64.max,
    ]

    /// Scalars spanning every UTF-8 width plus noncharacters, NUL and the
    /// BOM. No combining marks, so distinct keys never collide under Swift's
    /// canonical-equivalence string comparison.
    static let scalars: [Unicode.Scalar] = (0x20...0x7e).map { Unicode.Scalar(UInt8($0)) } + ([
        "\u{0}", "\u{1f}", "\u{7f}", "\u{80}", "\u{7ff}", "\u{800}", "\u{fffd}", "\u{fffe}", "\u{ffff}",
        "\u{feff}", "\u{10000}", "\u{1f600}", "\u{10fffe}", "\u{10ffff}", "水", "ü",
    ] as [Unicode.Scalar]) + [Unicode.Scalar(0xfdd0)!, Unicode.Scalar(0xfdef)!] // the lexer refuses these literals

    /// Bytes that start or shape items, so random fuzz gets past the head.
    static let structural: [UInt8] = [
        0x00, 0x01, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1f, 0x20, 0x37, 0x38, 0x3b,
        0x40, 0x41, 0x42, 0x58, 0x5f, 0x60, 0x61, 0x62, 0x78, 0x7f,
        0x80, 0x81, 0x82, 0x83, 0x98, 0x9f, 0xa0, 0xa1, 0xa2, 0xb8, 0xbf,
        0xc0, 0xc2, 0xd8, 0xf0, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb, 0xff,
    ]

    static func integer(using rng: inout SplitMix64) -> UInt64 {
        switch rng.next() % 4 {
        case 0: return boundaries.randomElement(using: &rng)!
        case 1: return rng.next() % 64
        case 2: return rng.next() % 70000
        default: return rng.next()
        }
    }

    static func bytes(using rng: inout SplitMix64) -> [UInt8] {
        let n = rng.next() % 16 == 0 ? Int(rng.next() % 300) : Int(rng.next() % 8)
        var out: [UInt8] = []
        for _ in 0..<n { out.append(UInt8(truncatingIfNeeded: rng.next())) }
        return out
    }

    static func text(using rng: inout SplitMix64) -> String {
        var view = String.UnicodeScalarView()
        for _ in 0..<Int(rng.next() % 8) { view.append(scalars.randomElement(using: &rng)!) }
        return String(view)
    }

    /// A random value nested at most `budget` containers deep.
    static func value(budget: Int, using rng: inout SplitMix64) -> CBOR {
        switch rng.next() % (budget > 0 ? 8 : 6) {
        case 0: return .unsigned(integer(using: &rng))
        case 1: return .negative(integer(using: &rng))
        case 2: return .bytes(bytes(using: &rng))
        case 3: return .text(text(using: &rng))
        case 4: return .bool(rng.next() & 1 == 0)
        case 5: return .null
        case 6:
            var array: [CBOR] = []
            for _ in 0..<Int(rng.next() % 5) { array.append(value(budget: budget - 1, using: &rng)) }
            return .array(array)
        default:
            var map: [CBOR: CBOR] = [:]
            for _ in 0..<Int(rng.next() % 5) {
                map[value(budget: budget - 1, using: &rng)] = value(budget: budget - 1, using: &rng)
            }
            return .map(map)
        }
    }

    static func values(count: Int, seed: UInt64) -> [CBOR] {
        var rng = SplitMix64(seed: seed)
        var out: [CBOR] = []
        for _ in 0..<count { out.append(value(budget: Int(rng.next() % 5), using: &rng)) }
        return out
    }

    static func fuzz(using rng: inout SplitMix64) -> [UInt8] {
        var out: [UInt8] = []
        for _ in 0..<Int(rng.next() % 33) {
            out.append(rng.next() & 1 == 0 ? structural.randomElement(using: &rng)! : UInt8(truncatingIfNeeded: rng.next()))
        }
        return out
    }
}

/// `n` nested arrays around `leaf`.
private func nestedArrays(_ n: Int, leaf: [UInt8] = [0x00]) -> [UInt8] {
    [UInt8](repeating: 0x81, count: n) + leaf
}

/// `n` nested single-entry maps keyed by 0 around `leaf`.
private func nestedMaps(_ n: Int, leaf: [UInt8] = [0x00]) -> [UInt8] {
    var out: [UInt8] = []
    for _ in 0..<n { out += [0xa1, 0x00] }
    return out + leaf
}

// MARK: - Map key ordering (§4.2.1)

@Suite struct CBORKeyOrderTests {
    /// The RFC's own example list, in the order it must appear on the wire.
    static let rfcKeys: [(CBOR, String)] = [
        (10, "0a"), (100, "1864"), (-1, "20"), ("z", "617a"), ("aa", "626161"),
        ([100], "811864"), ([-1], "8120"), (false, "f4"),
    ]

    static let rfcPairs: [(Int, Int)] = rfcKeys.indices.flatMap { i in
        rfcKeys.indices.filter { $0 > i }.map { (i, $0) }
    }

    @Test func rfcExampleKeysEncodeInBytewiseOrder() throws {
        var map: [CBOR: CBOR] = [:]
        for (i, (key, _)) in Self.rfcKeys.enumerated() { map[key] = .unsigned(UInt64(i)) }
        let expected = "a8" + Self.rfcKeys.enumerated().map { "\($1.1)0\($0)" }.joined()
        #expect(hex(CBOR.map(map).encoded) == expected)
        #expect(try CBOR.decode(h(expected)) == .map(map))
    }

    @Test func rfc7049LengthFirstOrderIsRejected() {
        // §4.2.3 order: 10, -1, false, 100, "z", [-1], "aa", [100].
        let lengthFirst = h("a8 0a00 2002 f407 186401 617a03 812006 62616104 81186405")
        #expect(throws: CBORError.mapKeysNotOrdered) { try CBOR.decode(lengthFirst) }
    }

    /// Every pair from the RFC list: accepted in order, rejected reversed.
    @Test(arguments: CBORKeyOrderTests.rfcPairs)
    func pairOrder(first: Int, second: Int) throws {
        let (a, b) = (Self.rfcKeys[first].1, Self.rfcKeys[second].1)
        #expect(try CBOR.decode(h("a2 \(a) 00 \(b) 00")).mapValue?.count == 2)
        #expect(throws: CBORError.mapKeysNotOrdered) { try CBOR.decode(h("a2 \(b) 00 \(a) 00")) }
    }

    /// Mixed-type keys sort purely by encoded bytes: every unsigned before
    /// every negative, wider integers between, bytes before text, then
    /// arrays, maps and simple values.
    @Test func mixedKeysSortByEncoding() throws {
        let keys: [CBOR] = [
            .null, .bool(true), .bool(false), .map([0: 0]), .map([:]), .array([0]), .array([]),
            .text("\u{ff}"), .text("a"), .text(""), .bytes([0xff]), .bytes([0]), .bytes([]),
            .negative(UInt64.max), .negative(24), .negative(23), .negative(0),
            .unsigned(1 << 32), .unsigned(65536), .unsigned(256), .unsigned(255), .unsigned(24), .unsigned(23), .unsigned(0),
        ]
        var map: [CBOR: CBOR] = [:]
        for key in keys { map[key] = .null }
        let expectedOrder: [[UInt8]] = keys.map(\.encoded).sorted { $0.lexicographicallyPrecedes($1) }
        let expected: [UInt8] = [0xb8, UInt8(keys.count)] + expectedOrder.flatMap { $0 + [0xf6] }
        #expect(CBOR.map(map).encoded == expected)
        #expect(try CBOR.decode(expected) == .map(map))

        // Pins on the ordering itself, independent of the sort above.
        #expect(hex(expectedOrder[0]) == "00")
        #expect(hex(expectedOrder[6]) == "1b0000000100000000")
        #expect(hex(expectedOrder[7]) == "20")
        #expect(hex(expectedOrder[10]) == "3bffffffffffffffff")
        #expect(hex(expectedOrder[11]) == "40")
        #expect(hex(expectedOrder[13]) == "41ff")
        #expect(hex(expectedOrder[14]) == "60")
        #expect(hex(expectedOrder[16]) == "62c3bf")
        #expect(hex(expectedOrder[17]) == "80")
        #expect(hex(expectedOrder[19]) == "a0")
        #expect(hex(expectedOrder[23]) == "f6")
    }

    @Test(arguments: [
        "a2 00 00 20 00",                   // 0 before -1
        "a2 1864 00 20 00",                 // 100 (2 bytes) before -1 (1 byte)
        "a2 1bffffffffffffffff 00 20 00",   // 2^64-1 before -1
        "a2 18ff 00 190100 00",             // 255 before 256
        "a2 37 00 3818 00",                 // -24 before -25
        "a2 41ff 00 60 00",                 // h'ff' before ""
        "a2 4161 00 6161 00",               // h'61' before "a"
        "a2 6162 00 626161 00",             // "b" before "aa"
        "a2 617a 00 626161 00",             // "z" before "aa"
        "a2 811864 00 8120 00",             // [100] before [-1]
        "a2 8120 00 a0 00",                 // [-1] before {}
        "a2 a0 00 f4 00",                   // {} before false
        "a2 f4 00 f6 00",                   // false before null
    ])
    func orderedPairsAreAccepted(encoded: String) throws {
        #expect(try CBOR.decode(h(encoded)).mapValue?.count == 2)
        #expect(try CBOR.decode(h(encoded)).encoded == h(encoded))
    }

    @Test(arguments: [
        "a2 20 00 00 00", "a2 20 00 1864 00", "a2 190100 00 18ff 00", "a2 3818 00 37 00",
        "a2 60 00 41ff 00", "a2 6161 00 4161 00", "a2 626161 00 6162 00", "a2 626161 00 617a 00",
        "a2 80 00 60 00", "a2 a0 00 80 00", "a2 f4 00 a0 00", "a2 f6 00 f5 00", "a2 f5 00 f4 00",
        "a2 8120 00 811864 00", "a2 a0 00 8120 00",
    ])
    func unorderedPairsAreRejected(encoded: String) {
        #expect(throws: CBORError.mapKeysNotOrdered) { try CBOR.decode(h(encoded)) }
    }

    @Test(arguments: [
        "a2 00 00 00 01", "a2 6161 00 6161 01", "a2 40 00 40 01", "a2 80 00 80 01",
        "a2 a0 00 a0 01", "a2 f6 00 f6 01", "a3 00 00 01 00 01 00", "a3 00 00 01 00 00 00",
    ])
    func duplicateKeysAreRejected(encoded: String) {
        #expect(throws: CBORError.mapKeysNotOrdered) { try CBOR.decode(h(encoded)) }
    }

    /// Nested maps are checked too, in value and key position.
    @Test(arguments: ["a1 00 a2 01 00 00 00", "81 a2 01 00 00 00", "a1 a2 01 00 00 00 00", "82 00 a2 00 00 00 01"])
    func nestedMapOrderIsChecked(encoded: String) {
        #expect(throws: CBORError.mapKeysNotOrdered) { try CBOR.decode(h(encoded)) }
    }

    /// Bytes and text with identical content are distinct keys (§5.6.1),
    /// as are 0 and -1, [] and {}.
    @Test func lookalikeKeysAreDistinct() throws {
        let map: CBOR = [.bytes([0x61]): 1, .text("a"): 2, 0: 3, -1: 4, []: 5, [:]: 6, false: 7, .null: 8]
        #expect(map.mapValue?.count == 8)
        let decoded = try CBOR.decode(map.encoded)
        #expect(decoded == map)
        #expect(decoded.mapValue?[.bytes([0x61])] == 1)
        #expect(decoded.mapValue?[.text("a")] == 2)
        #expect(decoded[0] == 3)
        #expect(decoded.mapValue?[.negative(0)] == 4)
    }

    /// U+00E9 precomposed and "e" + U+0301 are distinct CBOR keys with
    /// different encodings (§5.6.1 compares text bytewise), but Swift's
    /// `String` treats them as equal, so a `[CBOR: CBOR]` cannot hold both.
    /// The decoder must not silently drop one; it rejects the map instead.
    /// "é" as NFC (c3a9) and NFD (65cc81) are distinct keys on the wire
    /// (RFC 8949 §5.6.1) and stay distinct in the value model.
    @Test func canonicallyEquivalentTextKeysAreNotMerged() throws {
        let encoded = h("a2 62c3a9 00 6365cc81 01")
        #expect(canonicalOrRejected(encoded))
        for wrapped in [encoded, [0x81] + encoded, [0xa1, 0x00] + encoded] {
            let value = try CBOR.decode(wrapped)
            #expect(value.encoded == wrapped)
            var inner = value
            if let a = inner.arrayValue { inner = a[0] }
            if let m = inner.mapValue, let v = m[0] { inner = v }
            #expect(inner.mapValue?.count == 2)
        }
        #expect(CBOR.text("\u{e9}") != CBOR.text("e\u{301}"))
        #expect(CBOR.text("\u{e9}").hashValue != CBOR.text("e\u{301}").hashValue)
    }

    /// Rotating a sorted map's entries by one always breaks the order.
    @Test func rotatedEntriesAreRejected() throws {
        var checked = 0
        for value in Gen.values(count: 600, seed: 7) {
            guard let map = value.mapValue, map.count >= 2 else { continue }
            let entries = map.map { ($0.key.encoded, $0.value.encoded) }.sorted { $0.0.lexicographicallyPrecedes($1.0) }
            let body = entries.flatMap { $0.0 + $0.1 }
            let head = Array(value.encoded.prefix(value.encoded.count - body.count))
            let rotated = Array(entries[1...] + entries[..<1]).flatMap { $0.0 + $0.1 }
            #expect(throws: CBORError.mapKeysNotOrdered) { try CBOR.decode(head + rotated) }
            #expect(try CBOR.decode(head + body) == value)
            checked += 1
        }
        #expect(checked > 30)
    }
}

// MARK: - Integer boundaries

@Suite struct CBORIntegerBoundaryTests {
    static let widths: [(UInt64, Int)] = [
        (0, 1), (23, 1), (24, 2), (255, 2), (256, 3), (65535, 3), (65536, 5),
        (0xffff_ffff, 5), (0x1_0000_0000, 9), (UInt64(Int.max), 9), (UInt64.max, 9),
    ]

    @Test(arguments: CBORIntegerBoundaryTests.widths)
    func unsignedUsesShortestHead(value: UInt64, width: Int) throws {
        let encoded = CBOR.unsigned(value).encoded
        #expect(encoded.count == width)
        #expect(try CBOR.decode(encoded) == .unsigned(value))
        if let inflated = inflateHead(encoded, at: 0) {
            #expect(throws: CBORError.notShortestForm) { try CBOR.decode(inflated) }
        }
    }

    @Test(arguments: CBORIntegerBoundaryTests.widths)
    func negativeUsesShortestHead(value: UInt64, width: Int) throws {
        let encoded = CBOR.negative(value).encoded
        #expect(encoded.count == width)
        #expect(encoded[0] >> 5 == 1)
        #expect(try CBOR.decode(encoded) == .negative(value))
        if let inflated = inflateHead(encoded, at: 0) {
            #expect(throws: CBORError.notShortestForm) { try CBOR.decode(inflated) }
        }
    }

    @Test(arguments: [
        ("1a ffffffff", CBOR.unsigned(0xffff_ffff)),
        ("1b 0000000100000000", CBOR.unsigned(0x1_0000_0000)),
        ("1b 7fffffffffffffff", CBOR.unsigned(UInt64(Int.max))),
        ("1b 8000000000000000", CBOR.unsigned(UInt64(Int.max) + 1)),
        ("1b ffffffffffffffff", CBOR.unsigned(UInt64.max)),
        ("3a ffffffff", CBOR.negative(0xffff_ffff)),                // -2^32
        ("3b 0000000100000000", CBOR.negative(0x1_0000_0000)),      // -2^32 - 1
        ("3b 7fffffffffffffff", CBOR.negative(UInt64(Int.max))),    // Int.min
        ("3b 8000000000000000", CBOR.negative(UInt64(Int.max) + 1)), // Int.min - 1
        ("3b ffffffffffffffff", CBOR.negative(UInt64.max)),         // -2^64
    ])
    func sixtyFourBitEdges(encoded: String, value: CBOR) throws {
        #expect(try CBOR.decode(h(encoded)) == value)
        #expect(value.encoded == h(encoded))
    }

    @Test(arguments: [
        "18 00", "18 17", "19 0000", "19 0018", "19 00ff", "1a 00000000", "1a 0000ffff",
        "1b 0000000000000000", "1b 00000000ffffffff",
        "38 00", "38 17", "39 00ff", "3a 0000ffff", "3b 00000000ffffffff",
    ])
    func nonShortestIntegersAreRejected(encoded: String) {
        #expect(throws: CBORError.notShortestForm) { try CBOR.decode(h(encoded)) }
    }

    @Test(arguments: [
        Int.min, Int.min + 1, -(1 << 32) - 1, -(1 << 32), -65537, -65536, -257, -256, -25, -24, -1,
        0, 1, 23, 24, 255, 256, 65535, 65536, 1 << 32, Int.max - 1, Int.max,
    ])
    func integerLiteralRoundTripsThroughIntValue(value: Int) throws {
        let cbor = CBOR(integerLiteral: value)
        #expect(cbor.intValue == value)
        #expect(try CBOR.decode(cbor.encoded).intValue == value)
        if value < 0 {
            #expect(cbor == .negative(UInt64(-1 - value)))
            #expect(cbor.unsignedValue == nil)
        } else {
            #expect(cbor == .unsigned(UInt64(value)))
            #expect(cbor.unsignedValue == UInt64(value))
        }
    }

    @Test func intValueAtSignedEdges() {
        #expect(CBOR.unsigned(UInt64(Int.max)).intValue == Int.max)
        #expect(CBOR.unsigned(UInt64(Int.max) + 1).intValue == nil)
        #expect(CBOR.unsigned(UInt64.max).intValue == nil)
        #expect(CBOR.negative(0).intValue == -1)
        #expect(CBOR.negative(UInt64(Int.max) - 1).intValue == Int.min + 1)
        #expect(CBOR.negative(UInt64(Int.max)).intValue == Int.min)
        #expect(CBOR.negative(UInt64(Int.max) + 1).intValue == nil)
        #expect(CBOR.negative(UInt64.max).intValue == nil)
        #expect(CBOR.negative(UInt64.max).unsignedValue == nil)
    }

    static let nonShortestLengths: [String] = [
        "58 00", "58 17 " + String(repeating: "00 ", count: 23),
        "59 0018 " + String(repeating: "00 ", count: 24),
        "5a 000000ff " + String(repeating: "00 ", count: 255),
        "5b 0000000000000000",
        "78 00", "78 01 61", "79 0001 61", "7b 0000000000000001 61",
        "98 00", "98 01 00", "99 0001 00", "9a 00000001 00", "9b 0000000000000001 00",
        "b8 00", "b8 01 00 00", "b9 0001 00 00", "ba 00000001 00 00", "bb 0000000000000001 00 00",
        "9b 00000000ffffffff", "5b 00000000ffffffff", "ba 0000ffff",
    ]

    /// Length arguments obey the same shortest-form rule as integers, and
    /// the rule is checked before the length is bounded by remaining input.
    @Test(arguments: CBORIntegerBoundaryTests.nonShortestLengths)
    func nonShortestLengthsAreRejected(encoded: String) {
        #expect(throws: CBORError.notShortestForm) { try CBOR.decode(h(encoded)) }
    }

    /// Strings, arrays and maps at every width boundary round-trip and
    /// reject a widened head.
    @Test(arguments: [0, 1, 23, 24, 255, 256, 65535, 65536])
    func lengthBoundariesRoundTrip(n: Int) throws {
        let bytes = CBOR.bytes([UInt8](repeating: 0xab, count: n))
        let text = CBOR.text(String(repeating: "a", count: n))
        let array = CBOR.array([CBOR](repeating: .null, count: n))
        var map: [CBOR: CBOR] = [:]
        for i in 0..<n { map[.unsigned(UInt64(i))] = .null }
        for value in [bytes, text, array, .map(map)] {
            let encoded = value.encoded
            #expect(try CBOR.decode(encoded) == value)
            #expect(try CBOR.decode(encoded).encoded == encoded)
            if let inflated = inflateHead(encoded, at: 0) {
                #expect(throws: CBORError.notShortestForm) { try CBOR.decode(inflated) }
            }
        }
        let width = n < 24 ? 1 : n < 256 ? 2 : n < 65536 ? 3 : 5
        #expect(bytes.encoded.count == width + n)
        #expect(text.encoded.count == width + n)
        #expect(array.encoded.count == width + n)
    }
}

// MARK: - Text strings and UTF-8

@Suite struct CBORTextTests {
    @Test(arguments: [
        "61 80",                // lone continuation
        "61 c0",                // truncated 2-byte lead
        "62 c0 80",             // overlong NUL
        "62 c1 bf",             // overlong U+007F
        "63 e0 80 80",          // overlong U+0000 (3 bytes)
        "63 e0 9f bf",          // overlong U+07FF
        "64 f0 80 80 80",       // overlong U+0000 (4 bytes)
        "64 f0 8f bf bf",       // overlong U+FFFF
        "63 ed a0 80",          // surrogate U+D800
        "63 ed bf bf",          // surrogate U+DFFF
        "66 ed a0 bd ed b2 a9", // CESU-8 surrogate pair
        "64 f4 90 80 80",       // U+110000, above Unicode
        "64 f5 80 80 80",       // lead byte f5
        "65 f8 88 80 80 80",    // 5-byte form
        "61 fe", "61 ff",
        "62 e2 82",             // truncated 3-byte sequence
        "63 e2 82 41",          // continuation replaced by ASCII
        "62 c3 28",             // bad continuation
        "63 e2 28 a1",
        "64 f0 90 28 bc",
        "64 f0 28 8c bc",
        "62 61 ff",             // valid then invalid
        "63 ef bf ff",          // 3-byte lead with a bad last byte
    ])
    func invalidUTF8IsRejected(encoded: String) {
        #expect(throws: CBORError.invalidUTF8) { try CBOR.decode(h(encoded)) }
    }

    /// Valid UTF-8 at every width, including noncharacters (not excluded by
    /// RFC 3629), NUL, the BOM and combining sequences.
    @Test(arguments: [
        ("61 00", "\u{0}"), ("61 7f", "\u{7f}"), ("62 c2 80", "\u{80}"), ("62 df bf", "\u{7ff}"),
        ("63 e0 a0 80", "\u{800}"), ("63 ed 9f bf", "\u{d7ff}"), ("63 ee 80 80", "\u{e000}"),
        ("63 ef bf bd", "\u{fffd}"), ("63 ef bf be", "\u{fffe}"), ("63 ef bf bf", "\u{ffff}"),
        ("63 ef b7 90", String(Unicode.Scalar(0xfdd0)!)), ("63 ef b7 af", String(Unicode.Scalar(0xfdef)!)), ("63 ef bb bf", "\u{feff}"),
        ("64 f0 90 80 80", "\u{10000}"), ("64 f4 8f bf be", "\u{10fffe}"), ("64 f4 8f bf bf", "\u{10ffff}"),
        ("64 f0 9f 98 80", "\u{1f600}"), ("62 0d 0a", "\r\n"), ("66 65 cc 81 e2 80 8d", "e\u{301}\u{200d}"),
    ])
    func validUTF8RoundTrips(encoded: String, text: String) throws {
        let value = try CBOR.decode(h(encoded))
        #expect(value == .text(text))
        #expect(Array(value.textValue!.utf8) == Array(h(encoded).dropFirst()))
        #expect(value.encoded == h(encoded))
    }

    /// Invalid UTF-8 is rejected wherever it appears.
    @Test(arguments: ["81 61 ff", "a1 61 ff 00", "a1 00 61 ff", "82 00 82 00 61 ff", "a1 81 61 ff 00"])
    func invalidUTF8IsRejectedWhenNested(encoded: String) {
        #expect(throws: CBORError.invalidUTF8) { try CBOR.decode(h(encoded)) }
    }

    /// Text length is bytes, not characters; the same bytes as a byte
    /// string decode to a different value.
    @Test func lengthCountsBytes() throws {
        let text = CBOR.text("水ü𐅑")
        #expect(text.encoded.count == 1 + 3 + 2 + 4)
        #expect(hex(text.encoded) == "69e6b0b4c3bcf0908591")
        let asBytes = CBOR.bytes(Array("水ü𐅑".utf8))
        #expect(asBytes != text)
        #expect(asBytes.encoded[0] == 0x49)
        #expect(try CBOR.decode(asBytes.encoded) == asBytes)
    }

    /// The encoder writes a string's stored bytes verbatim: no normalization.
    @Test func encoderDoesNotNormalize() {
        #expect(hex(CBOR.text("\u{e9}").encoded) == "62c3a9")
        #expect(hex(CBOR.text("e\u{301}").encoded) == "6365cc81")
    }
}

// MARK: - Well-formedness (§3, Appendix C, Appendix F)

@Suite struct CBORWellFormednessTests {
    @Test func maxDepthIsPinned() {
        #expect(CBOR.maxDepth == 32)
    }

    /// Appendix F.1 "end of input in a head". Heads outside the supported
    /// subset fail as unsupported before the head is read.
    @Test(arguments: [
        ("18", CBORError.truncated), ("19", .truncated), ("1a", .truncated), ("1b", .truncated),
        ("19 01", .truncated), ("1a 01 02", .truncated), ("1b 01 02 03 04 05 06 07", .truncated),
        ("38", .truncated), ("58", .truncated), ("78", .truncated), ("98", .truncated),
        ("9a 01 ff 00", .truncated), ("b8", .truncated),
        ("d8", .unsupported(majorType: 6, info: 24)), ("f8", .unsupported(majorType: 7, info: 24)),
        ("f9 00", .unsupported(majorType: 7, info: 25)), ("fa 00 00", .unsupported(majorType: 7, info: 26)),
        ("fb 00 00 00", .unsupported(majorType: 7, info: 27)),
    ])
    func endOfInputInHead(encoded: String, error: CBORError) {
        #expect(throws: error) { try CBOR.decode(h(encoded)) }
    }

    /// Appendix F.1 "definite-length strings with short data".
    @Test(arguments: ["41", "61", "5a ff ff ff ff 00", "5b ff ff ff ff ff ff ff ff 01 02 03", "7a ff ff ff ff 00", "7b 7f ff ff ff ff ff ff ff 01 02 03"])
    func stringsWithShortData(encoded: String) {
        #expect(throws: CBORError.truncated) { try CBOR.decode(h(encoded)) }
    }

    /// Appendix F.1 "maps and arrays not closed with enough items". The
    /// RFC's `a2 00 00 00` repeats key 0, which this decoder notices first.
    @Test(arguments: [
        ("81", CBORError.truncated), ("81 81 81 81 81 81 81 81 81 81", .truncated), ("82 00", .truncated),
        ("a1", .truncated), ("a2 01 02", .truncated), ("a1 00", .truncated), ("a2 00 00 00", .truncated),
        ("a2 00 00 01", .truncated), ("a1 81", .truncated), ("a1 00 81", .truncated),
    ])
    func containersNotClosed(encoded: String, error: CBORError) {
        #expect(throws: error) { try CBOR.decode(h(encoded)) }
    }

    /// Appendix F.1 subkind 1: reserved additional information 28–30.
    @Test(arguments: [0x1c, 0x1d, 0x1e, 0x3c, 0x3d, 0x3e, 0x5c, 0x5d, 0x5e, 0x7c, 0x7d, 0x7e, 0x9c, 0x9d, 0x9e, 0xbc, 0xbd, 0xbe, 0xdc, 0xdd, 0xde, 0xfc, 0xfd, 0xfe] as [UInt8])
    func reservedAdditionalInformation(initial: UInt8) {
        let error = CBORError.unsupported(majorType: initial >> 5, info: initial & 0x1f)
        #expect(throws: error) { try CBOR.decode([initial]) }
        #expect(throws: error) { try CBOR.decode([initial, 0, 0, 0, 0, 0, 0, 0, 0]) }
        #expect(throws: error) { try CBOR.decode([0x81, initial]) }
    }

    /// Appendix F.1 subkind 2: two-byte simple values below 32, plus every
    /// two-byte simple value the codec does not model.
    @Test(arguments: ["f8 00", "f8 01", "f8 14", "f8 15", "f8 16", "f8 18", "f8 1f", "f8 20", "f8 ff"])
    func twoByteSimpleValues(encoded: String) {
        #expect(throws: CBORError.unsupported(majorType: 7, info: 24)) { try CBOR.decode(h(encoded)) }
    }

    @Test(arguments: (0...19).map { UInt8(0xe0 | $0) } + [0xf7])
    func unassignedSimpleValues(initial: UInt8) {
        #expect(throws: CBORError.unsupported(majorType: 7, info: initial & 0x1f)) { try CBOR.decode([initial]) }
    }

    /// Appendix F.1 subkinds 4 and 5: stray breaks and info 31 on 0, 1, 6.
    @Test(arguments: [
        ("ff", CBORError.unsupported(majorType: 7, info: 31)), ("81 ff", .unsupported(majorType: 7, info: 31)),
        ("82 00 ff", .unsupported(majorType: 7, info: 31)), ("a1 ff", .truncated),
        ("a1 ff 00", .unsupported(majorType: 7, info: 31)), ("a1 00 ff", .unsupported(majorType: 7, info: 31)),
        ("a2 00 00 ff", .truncated),
        ("1f", .indefiniteLength), ("3f", .indefiniteLength), ("df", .unsupported(majorType: 6, info: 31)),
    ])
    func breaksAndInfo31(encoded: String, error: CBORError) {
        #expect(throws: error) { try CBOR.decode(h(encoded)) }
    }

    /// Every indefinite-length form in Appendix A, including well-formed
    /// ones, is rejected (§4.2.1: "Indefinite-length items MUST NOT appear").
    @Test(arguments: [
        "5f 42 01 02 43 03 04 05 ff", "7f 65 73 74 72 65 61 64 6d 69 6e 67 ff", "9f ff",
        "9f 01 82 02 03 9f 04 05 ff ff", "9f 01 82 02 03 82 04 05 ff", "83 01 82 02 03 9f 04 05 ff",
        "83 01 9f 02 03 ff 82 04 05",
        "9f 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 18 18 19 ff",
        "bf 61 61 01 61 62 9f 02 03 ff ff", "82 61 61 bf 61 62 61 63 ff", "bf 63 46 75 6e f5 63 41 6d 74 21 ff",
        "5f 41 00", "7f 61 00", "9f", "9f 01 02", "bf", "bf 01 02 01 02", "81 9f", "9f 80 00",
        "5f 00 ff", "5f 21 ff", "5f 5f 41 00 ff ff", "bf 00 ff", "a1 00 9f ff", "a1 9f ff 00",
    ])
    func indefiniteLengthsAreRejected(encoded: String) {
        #expect(throws: CBORError.indefiniteLength) { try CBOR.decode(h(encoded)) }
    }

    /// Appendix A entries outside the supported subset: bignums, tags,
    /// floats, undefined and simple values.
    @Test(arguments: [
        ("c2 49 01 00 00 00 00 00 00 00 00", CBORError.unsupported(majorType: 6, info: 2)),
        ("c3 49 01 00 00 00 00 00 00 00 00", .unsupported(majorType: 6, info: 3)),
        ("c0 74 32 30 31 33 2d 30 33 2d 32 31 54 32 30 3a 30 34 3a 30 30 5a", .unsupported(majorType: 6, info: 0)),
        ("c1 1a 51 4b 67 b0", .unsupported(majorType: 6, info: 1)),
        ("c1 fb 41 d4 52 d9 ec 20 00 00", .unsupported(majorType: 6, info: 1)),
        ("d7 44 01 02 03 04", .unsupported(majorType: 6, info: 23)),
        ("d8 18 45 64 49 45 54 46", .unsupported(majorType: 6, info: 24)),
        ("d8 20 76 68 74 74 70 3a 2f 2f 77 77 77 2e 65 78 61 6d 70 6c 65 2e 63 6f 6d", .unsupported(majorType: 6, info: 24)),
        ("d9 d9 f7 00", .unsupported(majorType: 6, info: 25)),
        ("f9 00 00", .unsupported(majorType: 7, info: 25)), ("f9 80 00", .unsupported(majorType: 7, info: 25)),
        ("f9 3c 00", .unsupported(majorType: 7, info: 25)), ("f9 7c 00", .unsupported(majorType: 7, info: 25)),
        ("f9 7e 00", .unsupported(majorType: 7, info: 25)), ("f9 fc 00", .unsupported(majorType: 7, info: 25)),
        ("fa 47 c3 50 00", .unsupported(majorType: 7, info: 26)), ("fa 7f 80 00 00", .unsupported(majorType: 7, info: 26)),
        ("fa 7f c0 00 00", .unsupported(majorType: 7, info: 26)),
        ("fb 3f f1 99 99 99 99 99 9a", .unsupported(majorType: 7, info: 27)),
        ("fb 7f f0 00 00 00 00 00 00", .unsupported(majorType: 7, info: 27)),
        ("fb 7f f8 00 00 00 00 00 00", .unsupported(majorType: 7, info: 27)),
        ("f7", .unsupported(majorType: 7, info: 23)), ("f0", .unsupported(majorType: 7, info: 16)),
        ("f8 ff", .unsupported(majorType: 7, info: 24)),
    ])
    func unsupportedAppendixAItems(encoded: String, error: CBORError) {
        #expect(throws: error) { try CBOR.decode(h(encoded)) }
    }

    @Test(arguments: [
        ("80", CBOR.array([])), ("a0", .map([:])), ("40", .bytes([])), ("60", .text("")),
        ("81 80", [[]]), ("81 a0", [[:]]), ("a1 80 a0", .map([[]: [:]])), ("a1 a0 80", .map([[:]: []])),
        ("82 80 80", [[], []]), ("a2 40 60 60 40", .map([.bytes([]): "", "": .bytes([])])),
        ("82 40 60", [.bytes([]), ""]),
    ] as [(String, CBOR)])
    func emptyContainers(encoded: String, value: CBOR) throws {
        #expect(try CBOR.decode(h(encoded)) == value)
        #expect(value.encoded == h(encoded))
    }

    @Test func nestingAtAndBeyondMaxDepth() throws {
        let depth = CBOR.maxDepth
        #expect(throws: Never.self) { try CBOR.decode(nestedArrays(depth)) }
        #expect(throws: CBORError.tooDeep) { try CBOR.decode(nestedArrays(depth + 1)) }
        #expect(throws: Never.self) { try CBOR.decode(nestedMaps(depth)) }
        #expect(throws: CBORError.tooDeep) { try CBOR.decode(nestedMaps(depth + 1)) }
        // Alternating arrays and maps.
        var mixed: [UInt8] = []
        for i in 0..<depth { mixed += i % 2 == 0 ? [0x81] : [0xa1, 0x00] }
        #expect(throws: Never.self) { try CBOR.decode(mixed + [0x00]) }
        #expect(throws: CBORError.tooDeep) { try CBOR.decode(mixed + [0x81, 0x00]) }
        #expect(throws: CBORError.tooDeep) { try CBOR.decode(mixed + [0xa1, 0x00, 0x00]) }
        // Depth is counted through map keys as well as values.
        #expect(throws: Never.self) { try CBOR.decode([0xa1] + nestedArrays(depth - 1) + [0x00]) }
        #expect(throws: CBORError.tooDeep) { try CBOR.decode([0xa1] + nestedArrays(depth) + [0x00]) }
        // Deep nesting fails fast, before truncation is noticed or the stack grows.
        #expect(throws: CBORError.tooDeep) { try CBOR.decode([UInt8](repeating: 0x81, count: 1_000_000)) }
        #expect(throws: CBORError.tooDeep) { try CBOR.decode([UInt8](repeating: 0xa1, count: 1_000_000)) }
        // What the decoder accepts, it round-trips; the encoder has no limit.
        let deepest = try CBOR.decode(nestedArrays(depth))
        #expect(deepest.encoded == nestedArrays(depth))
        let tooDeep = CBOR.array([deepest])
        #expect(tooDeep.encoded == nestedArrays(depth + 1))
        #expect(throws: CBORError.tooDeep) { try CBOR.decode(tooDeep.encoded) }
    }

    /// Length claims that exceed the remaining input fail before allocating.
    @Test(arguments: [
        "9a ff ff ff ff", "9b 00 00 00 01 00 00 00 00", "9b ff ff ff ff ff ff ff ff",
        "ba ff ff ff ff", "bb 00 00 00 01 00 00 00 00", "bb ff ff ff ff ff ff ff ff",
        "5a ff ff ff ff", "5b 00 00 00 01 00 00 00 00", "7a ff ff ff ff", "7b ff ff ff ff ff ff ff ff",
        "98 ff", "99 ff ff 00", "b8 ff 00 00", "b9 ff ff 00 00",
        "a3 00 00 01 01", "a2 00 00 01", "83 00 01", "58 20 00",
        "81 9a ff ff ff ff", "a1 00 ba ff ff ff ff", "a1 9a ff ff ff ff 00",
    ])
    func hostileLengths(encoded: String) {
        #expect(throws: CBORError.truncated) { try CBOR.decode(h(encoded)) }
    }

    /// A map claiming as many pairs as there are bytes left passes the
    /// length bound but must still fail on content.
    @Test func mapCountLargerThanRemainingPairs() {
        #expect(throws: CBORError.truncated) { try CBOR.decode(h("a5 00 00 01 01 02")) }
        #expect(throws: Never.self) { try CBOR.decode(h("a2 00 00 01 01")) }
    }

    @Test(arguments: [
        "00 00", "00 ff", "80 00", "a0 00", "40 00", "60 00", "f6 f6", "81 00 00", "a1 00 00 00",
        "1b ff ff ff ff ff ff ff ff 00", "44 01 02 03 04 05", "63 e6 b0 b4 00", "80 ff",
    ])
    func trailingBytes(encoded: String) {
        #expect(throws: CBORError.trailingBytes) { try CBOR.decode(h(encoded)) }
    }

    @Test func emptyInputIsTruncated() {
        #expect(throws: CBORError.truncated) { try CBOR.decode([]) }
    }

    /// Every initial byte alone: exactly the values that fit in one byte
    /// decode; everything else is rejected with the expected error.
    @Test(arguments: (0...255).map { UInt8($0) })
    func everyInitialByteAlone(initial: UInt8) throws {
        let major = initial >> 5
        let info = initial & 0x1f
        switch (major, info) {
        case (0, 0..<24): #expect(try CBOR.decode([initial]) == .unsigned(UInt64(info)))
        case (1, 0..<24): #expect(try CBOR.decode([initial]) == .negative(UInt64(info)))
        case (2, 0): #expect(try CBOR.decode([initial]) == .bytes([]))
        case (3, 0): #expect(try CBOR.decode([initial]) == .text(""))
        case (4, 0): #expect(try CBOR.decode([initial]) == .array([]))
        case (5, 0): #expect(try CBOR.decode([initial]) == .map([:]))
        case (7, 20): #expect(try CBOR.decode([initial]) == false)
        case (7, 21): #expect(try CBOR.decode([initial]) == true)
        case (7, 22): #expect(try CBOR.decode([initial]) == .null)
        case (0...5, 24...27), (2...5, 1..<24): #expect(throws: CBORError.truncated) { try CBOR.decode([initial]) }
        case (0...5, 31): #expect(throws: CBORError.indefiniteLength) { try CBOR.decode([initial]) }
        default: #expect(throws: CBORError.unsupported(majorType: major, info: info)) { try CBOR.decode([initial]) }
        }
        #expect(canonicalOrRejected([initial]))
    }
}

// MARK: - Non-canonical inputs a lenient decoder would silently repair

@Suite struct CBORNonCanonicalTests {
    /// Each input is well-formed CBOR whose re-encoding would differ from
    /// the input. The decoder must reject rather than normalise; the
    /// canonical spelling of the same value is accepted and stable.
    @Test(arguments: [
        ("18 01", CBORError.notShortestForm, "01"),
        ("19 00 01", .notShortestForm, "01"),
        ("1a 00 00 00 01", .notShortestForm, "01"),
        ("1b 00 00 00 00 00 00 00 01", .notShortestForm, "01"),
        ("38 00", .notShortestForm, "20"),
        ("58 01 00", .notShortestForm, "41 00"),
        ("78 01 61", .notShortestForm, "61 61"),
        ("98 02 00 01", .notShortestForm, "82 00 01"),
        ("b8 01 00 00", .notShortestForm, "a1 00 00"),
        ("82 00 18 01", .notShortestForm, "82 00 01"),
        ("a1 18 01 00", .notShortestForm, "a1 01 00"),
        ("a1 00 18 01", .notShortestForm, "a1 00 01"),
        ("a2 01 00 00 00", .mapKeysNotOrdered, "a2 00 00 01 00"),
        ("a2 20 00 18 64 00", .mapKeysNotOrdered, "a2 18 64 00 20 00"),
        ("a2 62 61 61 00 61 7a 00", .mapKeysNotOrdered, "a2 61 7a 00 62 61 61 00"),
        ("a2 81 20 00 81 18 64 00", .mapKeysNotOrdered, "a2 81 18 64 00 81 20 00"),
        ("a2 f4 00 0a 00", .mapKeysNotOrdered, "a2 0a 00 f4 00"),
        ("a2 00 00 00 01", .mapKeysNotOrdered, "a1 00 01"),
        ("9f 00 01 ff", .indefiniteLength, "82 00 01"),
        ("bf 00 01 ff", .indefiniteLength, "a1 00 01"),
        ("5f 41 01 41 02 ff", .indefiniteLength, "42 01 02"),
        ("7f 61 61 61 62 ff", .indefiniteLength, "62 61 62"),
    ])
    func nonCanonicalInputsAreRejected(encoded: String, error: CBORError, canonical: String) throws {
        #expect(throws: error) { try CBOR.decode(h(encoded)) }
        #expect(canonicalOrRejected(h(encoded)))
        #expect(try CBOR.decode(h(canonical)).encoded == h(canonical))
    }

    /// Alternative spellings of supported values through unsupported
    /// types: a tagged bignum for 1, a float for 1.0, undefined for null.
    @Test(arguments: [
        ("c2 41 01", CBORError.unsupported(majorType: 6, info: 2)),
        ("f9 3c 00", .unsupported(majorType: 7, info: 25)),
        ("f8 f4", .unsupported(majorType: 7, info: 24)),
        ("d8 18 41 00", .unsupported(majorType: 6, info: 24)),
        ("f7", .unsupported(majorType: 7, info: 23)),
    ])
    func alternativeTypesAreRejected(encoded: String, error: CBORError) {
        #expect(throws: error) { try CBOR.decode(h(encoded)) }
    }

    /// Widening any head in a canonical encoding must be caught, at the top
    /// level and nested inside an array and a map.
    @Test func inflatedHeadsAreRejected() throws {
        var checked = 0
        for value in Gen.values(count: 1500, seed: 11) {
            let encoded = value.encoded
            guard let inflated = inflateHead(encoded, at: 0) else { continue }
            let expected: CBORError = encoded[0] >> 5 == 7 ? .unsupported(majorType: 7, info: 24) : .notShortestForm
            #expect(throws: expected) { try CBOR.decode(inflated) }
            #expect(throws: expected) { try CBOR.decode([0x81] + inflated) }
            #expect(throws: expected) { try CBOR.decode([0xa1, 0x00] + inflated) }
            #expect(throws: expected) { try CBOR.decode([0xa1] + inflated + [0x00]) }
            checked += 1
        }
        #expect(checked > 1000)
    }
}

// MARK: - Properties over generated values

@Suite struct CBORPropertyTests {
    /// decode(encode(x)) == x and encode(decode(encode(x))) == encode(x).
    @Test func generatedValuesRoundTrip() throws {
        for value in Gen.values(count: 5000, seed: 1) {
            let encoded = value.encoded
            let decoded = try CBOR.decode(encoded)
            #expect(decoded == value)
            #expect(decoded.encoded == encoded)
            #expect(decoded.hashValue == value.hashValue)
        }
    }

    /// Structural equality is insensitive to map insertion order, and so is
    /// the encoding.
    @Test func mapEncodingIsInsertionOrderIndependent() {
        var rng = SplitMix64(seed: 3)
        for _ in 0..<500 {
            var entries: [(CBOR, CBOR)] = []
            for _ in 0..<Int(rng.next() % 8) {
                entries.append((Gen.value(budget: 2, using: &rng), Gen.value(budget: 2, using: &rng)))
            }
            var forward: [CBOR: CBOR] = [:]
            var backward: [CBOR: CBOR] = [:]
            var shuffled: [CBOR: CBOR] = [:]
            for (k, v) in entries { forward[k] = v }
            for (k, v) in entries.reversed() { backward[k] = v }
            for (k, v) in entries.shuffled(using: &rng) { shuffled[k] = v }
            // Later insertions win on duplicate keys, so compare only when all keys are distinct.
            guard forward.count == entries.count else { continue }
            #expect(CBOR.map(forward) == .map(backward))
            #expect(CBOR.map(forward).encoded == CBOR.map(backward).encoded)
            #expect(CBOR.map(forward).encoded == CBOR.map(shuffled).encoded)
        }
    }

    /// The deterministic-encoding property from the other direction: any
    /// byte string is either rejected or reproduced exactly.
    @Test func randomBytesAreCanonicalOrRejected() {
        var rng = SplitMix64(seed: 5)
        var accepted = 0
        for _ in 0..<40000 {
            let bytes = Gen.fuzz(using: &rng)
            #expect(canonicalOrRejected(bytes), "\(hex(bytes))")
            if (try? CBOR.decode(bytes)) != nil { accepted += 1 }
        }
        // The structural alphabet gets some inputs past the head.
        #expect(accepted > 100)
    }

    /// Single-byte mutations of canonical encodings never yield an accepted
    /// non-canonical input.
    @Test func mutatedEncodingsAreCanonicalOrRejected() {
        var rng = SplitMix64(seed: 9)
        for value in Gen.values(count: 3000, seed: 13) {
            let encoded = value.encoded
            let i = Int(rng.next() % UInt64(encoded.count))
            var flipped = encoded
            flipped[i] ^= UInt8(1 << (rng.next() % 8))
            var replaced = encoded
            replaced[i] = UInt8(truncatingIfNeeded: rng.next())
            var inserted = encoded
            inserted.insert(UInt8(truncatingIfNeeded: rng.next()), at: i)
            var deleted = encoded
            deleted.remove(at: i)
            for mutant in [flipped, replaced, inserted, deleted] {
                #expect(canonicalOrRejected(mutant), "\(hex(encoded)) -> \(hex(mutant))")
            }
        }
    }

    /// A proper prefix of a well-formed item is never a well-formed item
    /// (§3, items are self-delimiting), and the decoder reports exactly
    /// truncation, never some other error, because the bytes it sees are
    /// identical up to the cut.
    @Test func everyProperPrefixIsTruncated() {
        for value in Gen.values(count: 400, seed: 17) {
            let encoded = value.encoded
            for cut in 0..<encoded.count {
                #expect(throws: CBORError.truncated) { try CBOR.decode(Array(encoded[..<cut])) }
            }
        }
    }

    /// Appending anything to a well-formed item is exactly `trailingBytes`.
    @Test func everyExtensionIsTrailing() {
        var rng = SplitMix64(seed: 19)
        for value in Gen.values(count: 1000, seed: 23) {
            let encoded = value.encoded
            #expect(throws: CBORError.trailingBytes) { try CBOR.decode(encoded + [0xff]) }
            let tail = Gen.fuzz(using: &rng)
            guard !tail.isEmpty else { continue }
            #expect(throws: CBORError.trailingBytes) { try CBOR.decode(encoded + tail) }
        }
    }

    /// Random structures exactly at the depth limit round-trip; one more
    /// container is rejected.
    @Test func deepGeneratedValuesRoundTrip() throws {
        var rng = SplitMix64(seed: 29)
        for _ in 0..<50 {
            var value = Gen.value(budget: 0, using: &rng)
            for _ in 0..<CBOR.maxDepth {
                value = rng.next() & 1 == 0 ? .array([value]) : .map([Gen.value(budget: 0, using: &rng): value])
            }
            let encoded = value.encoded
            #expect(try CBOR.decode(encoded) == value)
            #expect(throws: CBORError.tooDeep) { try CBOR.decode(CBOR.array([value]).encoded) }
        }
    }

    /// Integers across the whole 64-bit range, both signs, with the head
    /// width derived independently of the encoder.
    @Test func integersRoundTripWithExpectedWidth() throws {
        var rng = SplitMix64(seed: 31)
        for _ in 0..<5000 {
            let v = Gen.integer(using: &rng)
            let width = v < 24 ? 1 : v <= 0xff ? 2 : v <= 0xffff ? 3 : v <= 0xffff_ffff ? 5 : 9
            for value in [CBOR.unsigned(v), .negative(v)] {
                let encoded = value.encoded
                #expect(encoded.count == width)
                #expect(try CBOR.decode(encoded) == value)
            }
        }
    }
}

// MARK: - Accessors

@Suite struct CBORAccessorTests {
    @Test func accessorsAreTypeExact() {
        let values: [CBOR] = [.unsigned(1), .negative(0), .bytes([1]), .text("a"), .array([]), .map([:]), .bool(true), .null]
        for (i, value) in values.enumerated() {
            #expect((value.unsignedValue != nil) == (i == 0))
            #expect((value.intValue != nil) == (i <= 1))
            #expect((value.bytesValue != nil) == (i == 2))
            #expect((value.textValue != nil) == (i == 3))
            #expect((value.arrayValue != nil) == (i == 4))
            #expect((value.mapValue != nil) == (i == 5))
            #expect((value.boolValue != nil) == (i == 6))
            #expect(value[0] == nil)
        }
        #expect(CBOR.bytes([0x61]).textValue == nil)
        #expect(CBOR.text("a").bytesValue == nil)
        #expect(CBOR.array([0]).mapValue == nil)
        #expect(CBOR.map([:]).arrayValue == nil)
    }

    @Test func subscriptMatchesUnsignedKeysOnly() {
        let map: CBOR = [0: "zero", -1: "minus one", .unsigned(UInt64.max): "max", "0": "text", [0]: "array"]
        #expect(map[0] == "zero")
        #expect(map[UInt64.max] == "max")
        #expect(map[1] == nil)
        #expect(map.mapValue?[.negative(0)] == "minus one")
        #expect(map.mapValue?["0"] == "text")
        #expect(map.mapValue?[[0]] == "array")
        #expect(CBOR.array([0])[0] == nil)
        #expect(CBOR.null[0] == nil)
    }

    @Test func distinctValuesAreNotEqual() {
        let values: [CBOR] = [
            .unsigned(0), .negative(0), .bytes([]), .text(""), .array([]), .map([:]), .bool(false), .bool(true), .null,
            .unsigned(1), .negative(1), .bytes([0]), .text("\u{0}"), .array([0]), .map([0: 0]),
            .bytes([0x61]), .text("a"), .array([.bytes([])]), .array([.text("")]), .array([[]]), .array([[:]]),
        ]
        for (i, a) in values.enumerated() {
            for (j, b) in values.enumerated() {
                #expect((a == b) == (i == j))
                #expect((a.encoded == b.encoded) == (i == j))
            }
        }
    }
}
