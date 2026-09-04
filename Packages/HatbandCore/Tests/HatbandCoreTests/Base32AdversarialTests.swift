import Testing
@testable import HatbandCore

// Base32 against RFC 4648 §6, with §3.3 (non-alphabet characters) and
// §3.5 (canonical encoding). Two independent oracles: a bit-string
// reference codec written straight from the RFC prose, and vectors
// produced by GNU coreutils `base32`.

private let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
private let alphabetScalars = Array(alphabet.unicodeScalars)

/// ISO/IEC 18004 alphanumeric mode, Table 5.
private let qrAlphanumeric = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")

/// Remainders mod 8 an RFC 4648 §6 encoding can have (cases 1–5).
private let validRemainders: Set<Int> = [0, 2, 4, 5, 7]

/// SplitMix64, so every failure reproduces from its seed.
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

    mutating func bytes(_ count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8(truncatingIfNeeded: next()) }
    }
}

/// RFC 4648 §6 as prose: the bit stream most-significant bit first,
/// zero-filled on the right to a multiple of five, each group indexing
/// Table 3. Nothing like the implementation's shift register.
private func referenceEncode(_ bytes: [UInt8]) -> String {
    var bits: [Bool] = []
    for byte in bytes {
        for shift in stride(from: 7, through: 0, by: -1) { bits.append((byte >> shift) & 1 == 1) }
    }
    while bits.count % 5 != 0 { bits.append(false) }
    var out = String.UnicodeScalarView()
    for start in stride(from: 0, to: bits.count, by: 5) {
        out.append(alphabetScalars[bits[start..<start + 5].reduce(0) { $0 << 1 | ($1 ? 1 : 0) }])
    }
    return String(out)
}

/// The documented decode policy: trailing `=` dropped, ASCII case folded,
/// any other scalar rejected, then the RFC's length and zero-fill rules.
private func referenceDecode(_ text: String) -> Result<[UInt8], Base32.Error> {
    var scalars = Array(text.unicodeScalars)
    while scalars.last == "=" { scalars.removeLast() }
    let table = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567abcdefghijklmnopqrstuvwxyz".unicodeScalars)
    var bits: [Bool] = []
    for scalar in scalars {
        guard let index = table.firstIndex(of: scalar) else { return .failure(.invalidCharacter) }
        let value = index < 32 ? index : index - 32
        for shift in stride(from: 4, through: 0, by: -1) { bits.append((value >> shift) & 1 == 1) }
    }
    guard validRemainders.contains(scalars.count % 8) else { return .failure(.invalidLength) }
    let whole = bits.count / 8 * 8
    guard !bits[whole...].contains(true) else { return .failure(.nonZeroPadding) }
    var out: [UInt8] = []
    for start in stride(from: 0, to: whole, by: 8) {
        out.append(bits[start..<start + 8].reduce(0) { $0 << 1 | ($1 ? 1 : 0) })
    }
    return .success(out)
}

/// `nil` means decode threw something other than `Base32.Error`.
private func outcome(_ text: String) -> Result<[UInt8], Base32.Error>? {
    do { return .success(try Base32.decode(text)) } catch let error as Base32.Error {
        return .failure(error)
    } catch { return nil }
}

/// What a decode of `text` must re-encode to if it succeeds.
private func canonical(_ text: String) -> String {
    var scalars = Array(text.unicodeScalars)
    while scalars.last == "=" { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars)).uppercased()
}

/// `count` characters, all `A` except `value` at `position`.
private func string(placing value: Int, at position: Int, in count: Int) -> String {
    var scalars = [Unicode.Scalar](repeating: "A", count: count)
    scalars[position] = alphabetScalars[value]
    return String(String.UnicodeScalarView(scalars))
}

/// The bytes that string decodes to: every 5-bit group zero except
/// `position`, with bits past the last whole byte dropped.
private func bytes(placing value: Int, at position: Int, in count: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: count * 5 / 8)
    for i in 0..<5 where (value >> (4 - i)) & 1 == 1 {
        let bit = position * 5 + i
        if bit / 8 < out.count { out[bit / 8] |= 1 << (7 - bit % 8) }
    }
    return out
}

// MARK: - Oracles

/// Produced by GNU coreutils `base32 -w0`, padding kept.
private let coreutilsVectors: [([UInt8], String)] = [
    ([0, 0, 0, 0, 0], "AAAAAAAA"),
    ([0xff, 0xff, 0xff, 0xff, 0xff], "77777777"),
    ([0xff, 0xff, 0xff, 0xff], "777777Y="),
    ([0x01], "AE======"),
    ([0x80], "QA======"),
    (Array(0...15), "AAAQEAYEAUDAOCAJBIFQYDIOB4======"),
    (Array("The quick brown fox jumps over the lazy dog".utf8),
     "KRUGKIDROVUWG2ZAMJZG653OEBTG66BANJ2W24DTEBXXMZLSEB2GQZJANRQXU6JAMRXWO==="),
    (Array(UInt8.min...UInt8.max),
     "AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPSAIJCEMSCKJRHFAUSUKZMFUXC6MBRGIZTINJWG44DSOR3HQ6T4P2AIFBEGRCFIZDUQSKKJNGE2TSPKBIVEU2UKVLFOWCZLJNVYXK6L5QGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XU634PV7H7AEBQKBYJBMGQ6EITCULRSGY5D4QSGJJHFEVS2LZRGM2TOOJ3HU7UCQ2FI5EUWTKPKFJVKV2ZLNOV6YLDMVTWS23NN5YXG5LXPF5X274BQOCYPCMLRWHZDE4VS6MZXHM7UGR2LJ5JVOW27MNTWW33TO55X7A4HROHZHF43T6R2PK5PWO33XP6DY7F47U6X3PP6HZ7L57Z7P674======"),
]

@Test(arguments: coreutilsVectors)
func matchesCoreutils(bytes: [UInt8], padded: String) throws {
    let unpadded = String(padded.prefix { $0 != "=" })
    #expect(Base32.encode(bytes) == unpadded)
    #expect(referenceEncode(bytes) == unpadded)
    #expect(try Base32.decode(padded) == bytes)
    #expect(try Base32.decode(unpadded) == bytes)
}

/// RFC 4648 §10, exactly as printed (padded).
private let rfcPaddedVectors: [(String, String)] = [
    ("", ""), ("f", "MY======"), ("fo", "MZXQ===="), ("foo", "MZXW6==="),
    ("foob", "MZXW6YQ="), ("fooba", "MZXW6YTB"), ("foobar", "MZXW6YTBOI======"),
]

@Test(arguments: rfcPaddedVectors)
func rfcVectorsWithPadding(plain: String, padded: String) throws {
    let bytes = Array(plain.utf8)
    #expect(padded.count % 8 == 0)
    #expect(try Base32.decode(padded) == bytes)
    #expect(try Base32.decode(padded.lowercased()) == bytes)
    #expect(Base32.encode(bytes) + String(repeating: "=", count: padded.filter { $0 == "=" }.count) == padded)
}

// MARK: - Round trips

@Test func roundTripsEveryLengthThrough100() throws {
    var rng = SplitMix64(seed: 0x4842_3120_6261_7365)
    for length in 0...100 {
        for _ in 0..<4 {
            let bytes = rng.bytes(length)
            let text = Base32.encode(bytes)
            #expect(text.utf8.count == (length * 8 + 4) / 5, "length \(length)")
            #expect(text == referenceEncode(bytes), "length \(length)")
            #expect(try Base32.decode(text) == bytes, "length \(length)")
            #expect(try Base32.decode(text.lowercased()) == bytes, "length \(length)")
            #expect(referenceDecode(text) == .success(bytes), "length \(length)")
        }
    }
}

private let bitPatterns: [[UInt8]] = [
    [UInt8](repeating: 0x00, count: 41),
    [UInt8](repeating: 0xff, count: 41),
    (0..<41).map { (i: Int) -> UInt8 in i % 2 == 0 ? 0x55 : 0xaa },
    (0..<41).map { (i: Int) -> UInt8 in i % 2 == 0 ? 0xaa : 0x55 },
    (0..<41).map { (i: Int) -> UInt8 in 1 << UInt8(i % 8) },
    (0..<41).map { (i: Int) -> UInt8 in 0x80 >> UInt8(i % 8) },
]

@Test(arguments: bitPatterns)
func roundTripsBitPatterns(bytes: [UInt8]) throws {
    for length in 0...bytes.count {
        let prefix = Array(bytes.prefix(length))
        let text = Base32.encode(prefix)
        #expect(text == referenceEncode(prefix))
        #expect(try Base32.decode(text) == prefix)
    }
}

/// Decoding is the left inverse of encoding and, on canonical text, the
/// right inverse too: a decodable string re-encodes to itself once case is
/// folded and trailing `=` dropped.
@Test func encodeIsInverseOfDecodeOnCanonicalText() throws {
    var rng = SplitMix64(seed: 7)
    for _ in 0..<500 {
        let count = Int.random(in: 0...80, using: &rng)
        let text = Base32.encode(rng.bytes(count))
        #expect(Base32.encode(try Base32.decode(text)) == text)
        #expect(Base32.encode(try Base32.decode(text.lowercased())) == text)
    }
}

// MARK: - Alphabet

/// Table 3: value `v` is the character at index `v`, and 0, 1, 8, 9 are absent.
@Test func alphabetIsTable3() {
    #expect(alphabet.count == 32)
    #expect(Set(alphabet).count == 32)
    #expect(Set(alphabet).isDisjoint(with: "0189"))
    for value in 0..<32 {
        // A single byte `v << 3` puts `v` in the first group and zero in the second.
        #expect(Base32.encode([UInt8(value << 3)]) == String(alphabetScalars[value]) + "A")
    }
}

/// Every value in every position of two whole quanta, both directions,
/// both cases.
@Test(arguments: 0..<16, 0..<32)
func everyValueInEveryPosition(position: Int, value: Int) throws {
    let text = string(placing: value, at: position, in: 16)
    let expected = bytes(placing: value, at: position, in: 16)
    #expect(try Base32.decode(text) == expected)
    #expect(try Base32.decode(text.lowercased()) == expected)
    #expect(Base32.encode(expected) == text)
    #expect(referenceEncode(expected) == text)
}

/// Output is uppercase, in Table 3, inside QR alphanumeric mode, and has
/// no line breaks (§3.1).
@Test func encodeOutputIsUppercaseQRAlphanumeric() {
    #expect(Set(alphabet).isSubset(of: qrAlphanumeric))
    var rng = SplitMix64(seed: 3)
    var samples = [Array(UInt8.min...UInt8.max), [], [0], [0xff]]
    for _ in 0..<200 {
        let count = Int.random(in: 0...300, using: &rng)
        samples.append(rng.bytes(count))
    }
    for bytes in samples {
        let text = Base32.encode(bytes)
        #expect(text == text.uppercased())
        #expect(text.allSatisfy { alphabet.contains($0) })
        #expect(text.allSatisfy { qrAlphanumeric.contains($0) })
        #expect(text.unicodeScalars.allSatisfy { $0.isASCII && !$0.properties.isWhitespace })
    }
}

// MARK: - Length

@Test(arguments: [
    (0, true), (1, false), (2, true), (3, false), (4, true), (5, true), (6, false), (7, true),
    (8, true), (9, false), (10, true), (11, false), (12, true), (13, true), (14, false), (15, true), (16, true),
])
func acceptsExactlyTheLengthsAQuantumCanEnd(count: Int, accepted: Bool) throws {
    let text = String(repeating: "A", count: count)
    if accepted {
        #expect(try Base32.decode(text) == [UInt8](repeating: 0, count: count * 5 / 8))
    } else {
        #expect(throws: Base32.Error.invalidLength) { try Base32.decode(text) }
    }
}

@Test func lengthRuleHoldsForEveryCountThrough256() {
    for count in 0...256 {
        let text = String(repeating: "A", count: count)
        let expected: Result<[UInt8], Base32.Error> = validRemainders.contains(count % 8)
            ? .success([UInt8](repeating: 0, count: count * 5 / 8))
            : .failure(.invalidLength)
        #expect(outcome(text) == expected, "count \(count)")
    }
}

/// Every prefix of a canonical encoding is either an impossible length,
/// carries non-zero fill bits, or decodes to a prefix of the bytes.
@Test func prefixesOfCanonicalText() {
    var rng = SplitMix64(seed: 11)
    let bytes = rng.bytes(50)
    let text = Base32.encode(bytes)
    for count in 0...text.count {
        let prefix = String(text.prefix(count))
        let result = outcome(prefix)
        #expect(result == referenceDecode(prefix), "count \(count)")
        switch result {
        case .success(let decoded)?:
            #expect(validRemainders.contains(count % 8))
            #expect(decoded == Array(bytes.prefix(count * 5 / 8)))
        case .failure(.invalidLength)?:
            #expect(!validRemainders.contains(count % 8))
        case .failure(.nonZeroPadding)?:
            #expect(validRemainders.contains(count % 8) && count % 8 != 0)
        default:
            Issue.record("prefix of length \(count): \(String(describing: result))")
        }
    }
}

// MARK: - Padding

/// §6 cases 2–5: 8, 16, 24, 32 residual bits pad with 6, 4, 3, 1 `=`.
@Test func decodesRFCPaddingCounts() throws {
    var rng = SplitMix64(seed: 5)
    for length in 0...25 {
        let bytes = rng.bytes(length)
        let text = Base32.encode(bytes)
        let pads = (8 - text.count % 8) % 8
        #expect(pads == [0, 6, 4, 3, 1][length % 5], "length \(length)")
        let padded = text + String(repeating: "=", count: pads)
        #expect(padded.count % 8 == 0)
        #expect(try Base32.decode(padded) == bytes, "length \(length)")
        #expect(try Base32.decode(padded.lowercased()) == bytes, "length \(length)")
    }
}

/// The pad count is not checked: any run of trailing `=` is dropped,
/// which §3.3 permits for excess pad and which this decoder extends to
/// too little or nothing but pad. The wire form is unpadded and the
/// signature covers the bytes, so no meaning rides on the count.
@Test(arguments: 0...9)
func toleratesAnyTrailingPadCount(pads: Int) throws {
    let pad = String(repeating: "=", count: pads)
    #expect(try Base32.decode("MY" + pad) == Array("f".utf8))
    #expect(try Base32.decode("MZXW6YTBOI" + pad) == Array("foobar".utf8))
    #expect(try Base32.decode(pad) == [])
}

@Test func toleratesLongPadRun() throws {
    #expect(try Base32.decode("MY" + String(repeating: "=", count: 1000)) == Array("f".utf8))
}

@Test(arguments: [
    "=MY", "M=Y", "MY=MY", "MY======MY", "MZXW6=YTB", "MZXW6===MZXW6===", "MY======MZXQ====",
    "MY======\n", "MY====== ", "MY=======A", "MY=\u{200B}",
])
func rejectsPadBeforeTheEnd(text: String) {
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode(text) }
}

@Test(arguments: [
    ("M=======", Base32.Error.invalidLength), ("MZX=====", .invalidLength), ("MZXW6Y==", .invalidLength),
    ("MZXW6YTBO=======", .invalidLength), ("A=", .invalidLength),
    ("MZ======", .nonZeroPadding), ("MZXW7===", .nonZeroPadding), ("777777Z=", .nonZeroPadding),
    ("MZXQ====" + "MZXW7===", .invalidCharacter),
])
func paddingHidesNothing(text: String, error: Base32.Error) {
    #expect(throws: error) { try Base32.decode(text) }
}

// MARK: - Fill bits (§3.5)

/// For each partial quantum length the last character carries 2, 4, 1 or
/// 3 fill bits. Every value that sets one is rejected; every other value
/// decodes to exactly its whole bytes.
@Test(arguments: [2, 4, 5, 7], 0..<32)
func fillBitsMustBeZero(count: Int, value: Int) throws {
    let fill = count * 5 % 8
    let partial = string(placing: value, at: count - 1, in: count)
    let expected = bytes(placing: value, at: count - 1, in: count)
    for prefix in ["", "MZXW6YTB"] {
        let text = prefix + partial
        let prefixBytes = Array("fooba".utf8.prefix(prefix.count * 5 / 8))
        if value & ((1 << fill) - 1) == 0 {
            #expect(try Base32.decode(text) == prefixBytes + expected)
            #expect(try Base32.decode(text.lowercased()) == prefixBytes + expected)
            #expect(Base32.encode(prefixBytes + expected) == text)
        } else {
            #expect(throws: Base32.Error.nonZeroPadding) { try Base32.decode(text) }
            #expect(throws: Base32.Error.nonZeroPadding) { try Base32.decode(text.lowercased()) }
        }
    }
}

/// Two uppercase characters spell exactly the 256 byte values, once each.
@Test func twoCharacterStringsAreABijectionOntoBytes() {
    var seen: Set<UInt8> = []
    var accepted = 0
    for first in alphabetScalars {
        for second in alphabetScalars {
            let text = String(String.UnicodeScalarView([first, second]))
            guard case .success(let bytes)? = outcome(text) else { continue }
            accepted += 1
            #expect(bytes.count == 1)
            #expect(seen.insert(bytes[0]).inserted, "\(text)")
        }
    }
    #expect(accepted == 256)
    #expect(seen.count == 256)
}

// MARK: - Case

@Test func acceptsLowerAndMixedCase() throws {
    var rng = SplitMix64(seed: 13)
    for _ in 0..<200 {
        let count = Int.random(in: 0...60, using: &rng)
        let bytes = rng.bytes(count)
        let upper = Base32.encode(bytes)
        let mixed = String(upper.enumerated().map { $0.offset % 2 == 0 ? $0.element : Character($0.element.lowercased()) })
        #expect(try Base32.decode(upper.lowercased()) == bytes)
        #expect(try Base32.decode(mixed) == bytes)
    }
}

/// O, I and L are alphabet members with their own values; 0 and 1 are not
/// aliases for them (§3.4: a decoder "by default ... should not").
@Test func confusablesInTheAlphabetKeepTheirValues() throws {
    #expect(try Base32.decode("OA") == [14 << 3])
    #expect(try Base32.decode("oA") == [14 << 3])
    #expect(try Base32.decode("IA") == [8 << 3])
    #expect(try Base32.decode("iA") == [8 << 3])
    #expect(try Base32.decode("LA") == [11 << 3])
    #expect(try Base32.decode("lA") == [11 << 3])
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode("0A") }
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode("1A") }
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode("OAAAAAA0") }
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode("IAAAAAA1") }
}

// MARK: - Non-alphabet characters (§3.3)

/// Each is one scalar. `=` is covered by the padding tests.
private let hostileScalars: [String] = [
    "0", "1", "8", "9", " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\0", "\u{7F}",
    "-", "_", "+", "/", ".", ",", ":", "$", "%", "*",
    "\u{A0}", "\u{200B}", "\u{FEFF}", "\u{301}", "\u{E9}", "\u{DF}", "\u{131}", "\u{130}",
    "\u{212A}", "\u{FF21}", "\u{FF12}", "\u{662}", "\u{1D400}", "\u{1F600}", "\u{FFFD}",
]

@Test(arguments: hostileScalars)
func rejectsNonAlphabetScalars(scalar: String) {
    #expect(scalar.unicodeScalars.count == 1)
    for (head, tail) in [("", "MZXW6YTB"), ("MZXW", "6YTB"), ("MZXW6YTB", ""), ("MZXW6YTBOI", ""), ("", "")] {
        let text = head + scalar + tail
        #expect(throws: Base32.Error.invalidCharacter, "\(text.unicodeScalars.map { $0.value })") {
            try Base32.decode(text)
        }
    }
}

/// `A` + U+0301 is one grapheme that looks like Á; the decoder sees bytes.
@Test func rejectsCombiningMarkOnAlphabetCharacter() {
    let text = "MZXW6YTA\u{301}"
    #expect(text.count == 8)
    #expect(text.utf8.count == 10)
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode(text) }
}

/// CRLF and inner whitespace are non-alphabet, so a wrapped encoding is
/// rejected rather than joined (§3.1, §3.3).
@Test(arguments: ["MZXW6YTB\r\nOI", "MZXW6YTB\nOI", "MZXW6YTB OI", "MZXW6YTBOI\n", " MZXW6YTBOI", "MZXW6YTBOI\r"])
func rejectsWrappedInput(text: String) {
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode(text) }
}

// MARK: - Empty and input types

@Test func emptyInput() throws {
    #expect(Base32.encode([]) == "")
    #expect(Base32.encode(EmptyCollection<UInt8>()) == "")
    #expect(try Base32.decode("") == [])
    #expect(try Base32.decode(Substring("")) == [])
}

@Test func encodeAcceptsAnyCollectionOfBytes() {
    let foobar = Array("foobar".utf8)
    #expect(Base32.encode("foobar".utf8) == "MZXW6YTBOI")
    #expect(Base32.encode(foobar[...]) == "MZXW6YTBOI")
    #expect(Base32.encode(ContiguousArray(foobar)) == "MZXW6YTBOI")
    #expect(Base32.encode(foobar[3...]) == Base32.encode(Array("bar".utf8)))
    #expect(Base32.encode(foobar.reversed()) == Base32.encode(Array("raboof".utf8)))
    #expect(Base32.encode(repeatElement(0xff, count: 5)) == "77777777")
    #expect(Base32.encode((0..<16).lazy.map { UInt8($0) }) == "AAAQEAYEAUDAOCAJBIFQYDIOB4")
}

@Test func decodeAcceptsSubstring() throws {
    let wrapped = "[MZXW6YTBOI]"
    #expect(try Base32.decode(wrapped.dropFirst().dropLast()) == Array("foobar".utf8))
    #expect(try Base32.decode(wrapped.dropFirst().dropLast().lowercased()) == Array("foobar".utf8))
}

// MARK: - Never traps

/// All 256 one-byte strings: `=` alone is empty, alphabet members are an
/// impossible length, the other 197 are rejected as characters.
@Test func everyOneByteInput() {
    var counts: [Result<[UInt8], Base32.Error>: Int] = [:]
    for byte in UInt8.min...UInt8.max {
        let text = String(decoding: [byte], as: UTF8.self)
        let result = outcome(text)
        #expect(result == referenceDecode(text), "byte \(byte)")
        if let result { counts[result, default: 0] += 1 }
    }
    #expect(counts[.success([])] == 1)
    #expect(counts[.failure(.invalidLength)] == 58)
    #expect(counts[.failure(.invalidCharacter)] == 197)
}

/// All 65536 two-byte sequences, invalid UTF-8 included. Accepted: 58
/// first characters times the 15 spellings of a second whose low two bits
/// are zero, plus `==`.
@Test func everyTwoByteInput() {
    var mismatches = 0
    var accepted = 0
    for first in UInt8.min...UInt8.max {
        for second in UInt8.min...UInt8.max {
            let text = String(decoding: [first, second], as: UTF8.self)
            let result = outcome(text)
            if result != referenceDecode(text) {
                mismatches += 1
                Issue.record("bytes \(first) \(second): \(String(describing: result))")
            }
            if case .success(let bytes)? = result {
                accepted += 1
                #expect(Base32.encode(bytes) == canonical(text))
            }
        }
    }
    #expect(mismatches == 0)
    #expect(accepted == 58 * 15 + 1)
}

/// Random strings over a pool of alphabet, pad, look-alike, whitespace and
/// non-ASCII scalars: never a trap, always the reference verdict, and any
/// success re-encodes to the canonical spelling.
@Test func fuzzDecodeAgainstReference() {
    let pool = Array((alphabet + alphabet.lowercased() + "=" + "0189").unicodeScalars)
        + hostileScalars.flatMap { Array($0.unicodeScalars) }
    var rng = SplitMix64(seed: 0xDEAD_BEEF)
    var successes = 0
    for iteration in 0..<20_000 {
        let count = Int.random(in: 0...40, using: &rng)
        // Mostly alphabet so a useful share gets past the character check.
        let scalars = (0..<count).map { _ -> Unicode.Scalar in
            Int.random(in: 0..<8, using: &rng) == 0 ? pool.randomElement(using: &rng)! : alphabetScalars.randomElement(using: &rng)!
        }
        let text = String(String.UnicodeScalarView(scalars))
        let result = outcome(text)
        #expect(result == referenceDecode(text), "iteration \(iteration): \(text)")
        if case .success(let bytes)? = result {
            successes += 1
            #expect(Base32.encode(bytes) == canonical(text), "iteration \(iteration): \(text)")
        }
    }
    #expect(successes > 500)
}

/// Arbitrary bytes pushed through `String(decoding:)` (invalid UTF-8
/// becomes U+FFFD) never trap the decoder.
@Test func fuzzDecodeArbitraryBytes() {
    var rng = SplitMix64(seed: 0xC0FF_EE)
    for iteration in 0..<5_000 {
        let count = Int.random(in: 0...64, using: &rng)
        let text = String(decoding: rng.bytes(count), as: UTF8.self)
        #expect(outcome(text) == referenceDecode(text), "iteration \(iteration)")
    }
}

@Test func fuzzEncodeArbitraryBytes() throws {
    var rng = SplitMix64(seed: 0xF00D)
    for _ in 0..<5_000 {
        let count = Int.random(in: 0...200, using: &rng)
        let bytes = rng.bytes(count)
        let text = Base32.encode(bytes)
        #expect(text.utf8.count == (count * 8 + 4) / 5)
        #expect(try Base32.decode(text) == bytes)
    }
}

// MARK: - Size

/// 1 MiB each way, with a bound loose enough for a debug build on a slow
/// runner and tight enough to catch anything superlinear.
@Test func oneMebibyteRoundTrip() throws {
    var rng = SplitMix64(seed: 1 << 20)
    let bytes = rng.bytes(1 << 20)
    let clock = ContinuousClock()
    var text = ""
    var decoded: [UInt8] = []
    let elapsed = try clock.measure {
        text = Base32.encode(bytes)
        decoded = try Base32.decode(text)
    }
    #expect(text.utf8.count == 1_677_722)
    #expect(decoded == bytes)
    #expect(elapsed < .seconds(20), "\(elapsed)")
    #expect(try Base32.decode(text.lowercased()) == bytes)
}

@Test func oneMebibyteHostileInputs() throws {
    let clock = ContinuousClock()
    let start = clock.now
    let zeros = String(repeating: "A", count: 1 << 20)
    #expect(try Base32.decode(zeros) == [UInt8](repeating: 0, count: (1 << 20) * 5 / 8))
    #expect(try Base32.decode(zeros.lowercased()) == [UInt8](repeating: 0, count: (1 << 20) * 5 / 8))
    #expect(try Base32.decode(String(repeating: "=", count: 1 << 20)) == [])
    #expect(throws: Base32.Error.invalidLength) { try Base32.decode(zeros + "A") }
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode(zeros + "0") }
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode("0" + zeros) }
    #expect(throws: Base32.Error.nonZeroPadding) { try Base32.decode(zeros + "AB") }
    #expect(throws: Base32.Error.invalidCharacter) { try Base32.decode("0" + String(repeating: "=", count: 1 << 20)) }
    #expect(try Base32.decode(String(repeating: "7", count: 1 << 20)) == [UInt8](repeating: 0xff, count: (1 << 20) * 5 / 8))
    let elapsed = clock.now - start
    #expect(elapsed < .seconds(30), "\(elapsed)")
}
