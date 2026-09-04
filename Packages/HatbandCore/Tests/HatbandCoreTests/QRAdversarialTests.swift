import Foundation
import Testing
@testable import HatbandCore

// Adversarial review of the QR encoder: an independent reader that recovers
// the codewords from a finished symbol, an independent bit-stream decoder, a
// Nayuki-faithful penalty scorer, hostile inputs, and round trips through
// zbar at every version and level.

private let levels = QRCode.ErrorCorrection.allCases

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Independent reader

/// ISO/IEC 18004 Table E.1, transcribed separately from the encoder's formula.
private let alignmentCentres: [[Int]] = [
    [], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34],
    [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50], [6, 30, 54], [6, 32, 58], [6, 34, 62],
    [6, 26, 46, 66], [6, 26, 48, 70], [6, 26, 50, 74], [6, 30, 54, 78], [6, 30, 56, 82], [6, 30, 58, 86], [6, 34, 62, 90],
    [6, 28, 50, 72, 94], [6, 26, 50, 74, 98], [6, 30, 54, 78, 102], [6, 28, 54, 80, 106], [6, 32, 58, 84, 110],
    [6, 30, 58, 86, 114], [6, 34, 62, 90, 118],
    [6, 26, 50, 74, 98, 122], [6, 30, 54, 78, 102, 126], [6, 26, 52, 78, 104, 130], [6, 30, 56, 82, 108, 134],
    [6, 34, 60, 86, 112, 138], [6, 30, 58, 86, 114, 142], [6, 34, 62, 90, 118, 146],
    [6, 30, 54, 78, 102, 126, 150], [6, 24, 50, 76, 102, 128, 154], [6, 28, 54, 80, 106, 132, 158],
    [6, 32, 58, 84, 110, 136, 162], [6, 26, 54, 82, 110, 138, 166], [6, 30, 58, 86, 114, 142, 170],
]

/// Which modules a reader must skip: finders and separators with the format
/// areas beside them, timing lines, alignment patterns, version blocks.
private func functionMap(version: Int) -> [Bool] {
    let size = 17 + 4 * version
    var map = [Bool](repeating: false, count: size * size)
    func mark(_ x: Int, _ y: Int) { map[y * size + x] = true }
    for y in 0..<size {
        for x in 0..<size {
            if x == 6 || y == 6 { mark(x, y) }
            if x < 9 && y < 9 { mark(x, y) }
            if x >= size - 8 && y < 9 { mark(x, y) }
            if x < 9 && y >= size - 8 { mark(x, y) }
            if version >= 7 {
                if x < 6 && y >= size - 11 && y < size - 8 { mark(x, y) }
                if y < 6 && x >= size - 11 && x < size - 8 { mark(x, y) }
            }
        }
    }
    let centres = alignmentCentres[version]
    for cy in centres {
        for cx in centres {
            let corner = (cx == 6 && cy == 6) || (cx == 6 && cy == size - 7) || (cx == size - 7 && cy == 6)
            if corner { continue }
            for dy in -2...2 { for dx in -2...2 { mark(cx + dx, cy + dy) } }
        }
    }
    return map
}

/// Polynomial remainder over GF(2) for the BCH checks.
private func gf2Remainder(_ value: Int, bits: Int, generator: Int, degree: Int) -> Int {
    var v = value
    for i in stride(from: bits - 1, through: degree, by: -1) where (v >> i) & 1 == 1 {
        v ^= generator << (i - degree)
    }
    return v
}

private func maskCondition(_ mask: Int, _ x: Int, _ y: Int) -> Bool {
    switch mask {
    case 0: return (y + x) % 2 == 0
    case 1: return y % 2 == 0
    case 2: return x % 3 == 0
    case 3: return (y + x) % 3 == 0
    case 4: return (y / 2 + x / 3) % 2 == 0
    case 5: return (y * x) % 2 + (y * x) % 3 == 0
    case 6: return ((y * x) % 2 + (y * x) % 3) % 2 == 0
    case 7: return ((y + x) % 2 + (y * x) % 3) % 2 == 0
    default: fatalError()
    }
}

private struct ReadFailure: Error, CustomStringConvertible {
    let description: String
}

private struct ReadSymbol {
    var level: QRCode.ErrorCorrection
    var mask: Int
    var version: Int
    var codewords: [UInt8]
    var remainder: [Bool]
    var formatCopiesAgree: Bool
    var versionCopies: (Int, Int)?
}

/// Recovers everything a decoder needs from the matrix alone.
private func read(_ code: QRCode) throws -> ReadSymbol {
    let size = code.size
    let version = (size - 17) / 4
    func m(_ x: Int, _ y: Int) -> Bool { code.module(x: x, y: y) }

    var first = 0, second = 0
    for i in 0...5 where m(8, i) { first |= 1 << i }
    if m(8, 7) { first |= 1 << 6 }
    if m(8, 8) { first |= 1 << 7 }
    if m(7, 8) { first |= 1 << 8 }
    for i in 9..<15 where m(14 - i, 8) { first |= 1 << i }
    for i in 0..<8 where m(size - 1 - i, 8) { second |= 1 << i }
    for i in 8..<15 where m(8, size - 15 + i) { second |= 1 << i }
    let raw = first ^ 0x5412
    guard gf2Remainder(raw, bits: 15, generator: 0x537, degree: 10) == 0 else {
        throw ReadFailure(description: "format information is not a BCH codeword")
    }
    let levelBits = raw >> 13
    let level: QRCode.ErrorCorrection = [.medium, .low, .high, .quartile][levelBits]
    let mask = (raw >> 10) & 7

    var versionCopies: (Int, Int)?
    if version >= 7 {
        var a = 0, b = 0
        for i in 0..<18 {
            if m(size - 11 + i % 3, i / 3) { a |= 1 << i }
            if m(i / 3, size - 11 + i % 3) { b |= 1 << i }
        }
        versionCopies = (a, b)
    }

    let function = functionMap(version: version)
    var bits: [Bool] = []
    var right = size - 1
    while right >= 1 {
        if right == 6 { right -= 1 }
        let upward = ((right + 1) / 2) % 2 == 0
        for step in 0..<size {
            let y = upward ? size - 1 - step : step
            for x in [right, right - 1] where !function[y * size + x] {
                bits.append(m(x, y) != maskCondition(mask, x, y))
            }
        }
        right -= 2
    }
    var codewords: [UInt8] = []
    for i in stride(from: 0, through: bits.count - 8, by: 8) {
        codewords.append(bits[i..<i + 8].reduce(0) { $0 << 1 | ($1 ? 1 : 0) })
    }
    return ReadSymbol(
        level: level, mask: mask, version: version, codewords: codewords,
        remainder: Array(bits[(codewords.count * 8)...]),
        formatCopiesAgree: first == second, versionCopies: versionCopies
    )
}

/// ISO/IEC 18004 Table 9 block structure, from the encoder's tables but
/// applied through an independent de-interleaver.
private func deinterleave(_ codewords: [UInt8], version: Int, level: QRCode.ErrorCorrection) -> (data: [[UInt8]], ecc: [[UInt8]]) {
    let blocks = QRCode.blockCounts[level.index][version]
    let eccLength = QRCode.eccCodewordsPerBlock[level.index][version]
    let total = codewords.count
    let dataTotal = total - blocks * eccLength
    let shortLength = dataTotal / blocks
    let longBlocks = dataTotal % blocks
    var data = [[UInt8]](repeating: [], count: blocks)
    var ecc = [[UInt8]](repeating: [], count: blocks)
    var i = 0
    for column in 0...shortLength {
        for b in 0..<blocks {
            let length = shortLength + (b >= blocks - longBlocks ? 1 : 0)
            if column < length { data[b].append(codewords[i]); i += 1 }
        }
    }
    for _ in 0..<eccLength {
        for b in 0..<blocks { ecc[b].append(codewords[i]); i += 1 }
    }
    return (data, ecc)
}

/// Parses the data bit stream: modes, counts, characters, terminator.
private func decodeText(_ data: [UInt8], version: Int) throws -> [UInt8] {
    var bits: [Bool] = []
    for byte in data { for i in stride(from: 7, through: 0, by: -1) { bits.append((byte >> i) & 1 == 1) } }
    var position = 0
    func take(_ n: Int) throws -> Int {
        guard position + n <= bits.count else { throw QRError.dataTooLong }
        defer { position += n }
        return bits[position..<position + n].reduce(0) { $0 << 1 | ($1 ? 1 : 0) }
    }
    let alnum = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)
    let group = version <= 9 ? 0 : version <= 26 ? 1 : 2
    var out: [UInt8] = []
    while position + 4 <= bits.count {
        let mode = try take(4)
        switch mode {
        case 0:
            return out
        case 1:
            var count = try take([10, 12, 14][group])
            while count >= 3 {
                let v = try take(10)
                out += Array(String(format: "%03d", v).utf8)
                count -= 3
            }
            if count == 2 { out += Array(String(format: "%02d", try take(7)).utf8) }
            if count == 1 { out += Array(String(try take(4)).utf8) }
        case 2:
            var count = try take([9, 11, 13][group])
            while count >= 2 {
                let v = try take(11)
                out += [alnum[v / 45], alnum[v % 45]]
                count -= 2
            }
            if count == 1 { out.append(alnum[try take(6)]) }
        case 4:
            let count = try take([8, 16, 16][group])
            for _ in 0..<count { out.append(UInt8(try take(8))) }
        default:
            throw QRError.invalidCharacter
        }
    }
    return out
}

/// Encodes, reads the symbol back independently, and returns the recovered
/// text with the codeword check already asserted.
private func roundTripInMemory(_ segments: [QRSegment], level: QRCode.ErrorCorrection, version: Int? = nil, mask: Int? = nil) throws -> [UInt8] {
    let code = try QRCode.encode(
        segments, errorCorrection: level, minVersion: version ?? 1, maxVersion: version ?? 40,
        boostErrorCorrection: false, mask: mask
    )
    let symbol = try read(code)
    #expect(symbol.level == level)
    #expect(symbol.mask == code.mask)
    #expect(symbol.version == code.version)
    #expect(symbol.formatCopiesAgree)
    #expect(symbol.codewords.count == QRCode.totalCodewords(version: code.version))
    #expect(symbol.remainder.allSatisfy { !$0 }, "remainder bits must be zero before masking")
    if let (a, b) = symbol.versionCopies {
        #expect(a == b)
        #expect(a >> 12 == code.version)
        #expect(gf2Remainder(a, bits: 18, generator: 0x1F25, degree: 12) == 0)
    }
    let (data, ecc) = deinterleave(symbol.codewords, version: code.version, level: level)
    for (block, check) in zip(data, ecc) {
        let g = ReedSolomon.generator(degree: check.count)
        #expect(ReedSolomon.remainder(of: block + check, generator: g).allSatisfy { $0 == 0 })
    }
    return try decodeText(data.flatMap { $0 }, version: code.version)
}

// MARK: - Independent reader tests

@Test(arguments: 1...40)
func readerRecoversTheCodewordsAtEveryVersion(version: Int) throws {
    for level in levels {
        let capacity = QRCode.dataCapacity(version: version, errorCorrection: level)
        // A mixed payload sized to nearly fill the version: digits, alphanumerics, bytes.
        var rng = SplitMix(state: UInt64(version * 4 + level.index))
        let third = max(1, (capacity - 3 * 20 - 24) / 3)
        let digits = String((0..<max(1, third * 3 / 10)).map { _ in "0123456789".randomElement(using: &rng)! })
        let letters = String((0..<max(1, third * 2 / 11)).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567 $%*+-./:".randomElement(using: &rng)! })
        var bytes = (0..<max(1, third / 8)).map { _ in UInt8.random(in: 0x20...0x7E, using: &rng) }
        bytes[0] = 0x00
        bytes[bytes.count - 1] = 0xFF
        let segments: [QRSegment] = [try .numeric(digits), try .alphanumeric(letters), .bytes(bytes)]
        let expected = Array(digits.utf8) + Array(letters.utf8) + bytes
        #expect(QRSegment.totalBits(segments, version: version)! <= capacity, "\(version)-\(level)")
        #expect(try roundTripInMemory(segments, level: level, version: version) == expected, "\(version)-\(level)")
    }
}

@Test(arguments: [1, 6, 7, 9, 10, 26, 27, 40])
func readerAgreesWithEncoderCodewords(version: Int) throws {
    for level in levels {
        let count = (QRCode.dataCapacity(version: version, errorCorrection: level) - 20) / 16 + 1
        let segments = [QRSegment.bytes((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 29 &+ 3) })]
        for mask in [nil, 0, 5, 7] {
            let code = try QRCode.encode(segments, errorCorrection: level, minVersion: version, maxVersion: version, boostErrorCorrection: false, mask: mask)
            let symbol = try read(code)
            let expected = QRCode.interleave(QRCode.dataCodewords(segments, version: version, errorCorrection: level), version: version, errorCorrection: level)
            #expect(symbol.codewords == expected, "\(version)-\(level) mask \(String(describing: mask))")
        }
    }
}

@Test func readerSeesEveryMaskAsAValidFormatWord() throws {
    let segments = [try QRSegment.alphanumeric("HATBAND")]
    for level in levels {
        for mask in 0..<8 {
            let code = try QRCode.encode(segments, errorCorrection: level, boostErrorCorrection: false, mask: mask)
            let symbol = try read(code)
            #expect(symbol.mask == mask)
            #expect(symbol.level == level)
            #expect(try decodeText(deinterleave(symbol.codewords, version: code.version, level: level).data.flatMap { $0 }, version: code.version) == Array("HATBAND".utf8))
        }
    }
}

/// Remainder bit counts per version, Table 1: the reader must see exactly them.
@Test(arguments: 1...40)
func remainderBitCountMatchesTable1(version: Int) throws {
    let expected: Int
    switch version {
    case 2...6: expected = 7
    case 14...20, 28...34: expected = 3
    case 21...27: expected = 4
    default: expected = 0
    }
    let code = try QRCode.encode([], errorCorrection: .low, minVersion: version, maxVersion: version, boostErrorCorrection: false)
    #expect(try read(code).remainder.count == expected)
}

/// The function map a reader derives from the standard alone equals the
/// encoder's, so no data lands on a function module or vice versa.
@Test(arguments: 1...40)
func functionModuleMapsAgree(version: Int) {
    var matrix = Matrix(version: version)
    matrix.drawFunctionPatterns()
    #expect(matrix.isFunction == functionMap(version: version))
}

// MARK: - Data stream details

@Test func byteCountFieldWidensAtVersionTen() {
    let segments = [QRSegment.bytes([0xAB])]
    let nine = QRCode.dataCodewords(segments, version: 9, errorCorrection: .low)
    #expect(Array(nine[..<3]) == [0x40, 0x1A, 0xB0])
    #expect(nine[3] == 0xEC)
    let ten = QRCode.dataCodewords(segments, version: 10, errorCorrection: .low)
    #expect(Array(ten[..<4]) == [0x40, 0x00, 0x1A, 0xB0])
    #expect(ten[4] == 0xEC)
}

@Test func numericCountFieldWidensTwice() throws {
    let segments = [try QRSegment.numeric("5")]
    // 0001, a 10/12/14-bit count of 1, 0101, then the terminator and zero fill.
    #expect(Array(QRCode.dataCodewords(segments, version: 1, errorCorrection: .low)[..<3]) == [0x10, 0x05, 0x40])
    #expect(Array(QRCode.dataCodewords(segments, version: 10, errorCorrection: .low)[..<3]) == [0x10, 0x01, 0x50])
    #expect(Array(QRCode.dataCodewords(segments, version: 27, errorCorrection: .low)[..<4]) == [0x10, 0x00, 0x54, 0x00])
}

@Test func alphanumericCountFieldWidensTwice() throws {
    let segments = [try QRSegment.alphanumeric("A")]
    // 0010, a 9/11/13-bit count of 1, 001010, then the terminator and zero fill.
    #expect(Array(QRCode.dataCodewords(segments, version: 1, errorCorrection: .low)[..<3]) == [0x20, 0x09, 0x40])
    #expect(Array(QRCode.dataCodewords(segments, version: 10, errorCorrection: .low)[..<4]) == [0x20, 0x02, 0x50, 0x00])
    #expect(Array(QRCode.dataCodewords(segments, version: 27, errorCorrection: .low)[..<4]) == [0x20, 0x00, 0x94, 0x00])
}

@Test func partialTerminatorsAndNoPadding() throws {
    // 25 alphanumerics at 1-L: 4 + 9 + 138 = 151 bits, one terminator bit, no pad.
    let one = QRCode.dataCodewords([try .alphanumeric(String(repeating: "Z", count: 25))], version: 1, errorCorrection: .low)
    #expect(one.count == 19)
    #expect(one.last! & 1 == 0)
    // 14 bytes and "1234" at 1-L: 12 + 112 + 14 + 14 = 152 bits, no terminator at all.
    let exactLow: [QRSegment] = [.bytes([UInt8](repeating: 0xFF, count: 14)), try .numeric("1234")]
    #expect(QRSegment.totalBits(exactLow, version: 1) == 152)
    let low = QRCode.dataCodewords(exactLow, version: 1, errorCorrection: .low)
    #expect(low.count == 19)
    #expect(low.last == 0xB4)
    #expect(try roundTripInMemory(exactLow, level: .low, version: 1) == [UInt8](repeating: 0xFF, count: 14) + Array("1234".utf8))
    // "12345" and "ABCDE" at 1-H: 14 + 17 + 13 + 28 = 72 bits.
    let exactHigh: [QRSegment] = [try .numeric("12345"), try .alphanumeric("ABCDE")]
    #expect(QRSegment.totalBits(exactHigh, version: 1) == 72)
    let high = QRCode.dataCodewords(exactHigh, version: 1, errorCorrection: .high)
    #expect(high.count == 9)
    #expect(high.last == 0x4E)
    #expect(try roundTripInMemory(exactHigh, level: .high, version: 1) == Array("12345ABCDE".utf8))
}

@Test func zeroLengthSegmentsStillEncodeAndParse() throws {
    let segments: [QRSegment] = [.bytes([]), try .numeric(""), try .alphanumeric(""), try .alphanumeric("OK")]
    #expect(QRSegment.totalBits(segments, version: 1) == 12 + 14 + 13 + 13 + 11)
    #expect(try roundTripInMemory(segments, level: .high) == Array("OK".utf8))
}

// MARK: - Capacity edges

@Test func maximaAtVersionFortyLow() throws {
    #expect(QRCode.smallestVersion(for: [try .numeric(String(repeating: "7", count: 7089))], errorCorrection: .low) == 40)
    #expect(QRCode.smallestVersion(for: [try .numeric(String(repeating: "7", count: 7090))], errorCorrection: .low) == nil)
    #expect(QRCode.smallestVersion(for: [try .alphanumeric(String(repeating: "Z", count: 4296))], errorCorrection: .low) == 40)
    #expect(QRCode.smallestVersion(for: [try .alphanumeric(String(repeating: "Z", count: 4297))], errorCorrection: .low) == nil)
    #expect(QRCode.smallestVersion(for: [.bytes([UInt8](repeating: 0, count: 2953))], errorCorrection: .low) == 40)
    #expect(QRCode.smallestVersion(for: [.bytes([UInt8](repeating: 0, count: 2954))], errorCorrection: .low) == nil)
    // Table 7 maxima at 40-H.
    #expect(QRCode.smallestVersion(for: [try .numeric(String(repeating: "7", count: 3057))], errorCorrection: .high) == 40)
    #expect(QRCode.smallestVersion(for: [try .numeric(String(repeating: "7", count: 3058))], errorCorrection: .high) == nil)
    #expect(QRCode.smallestVersion(for: [try .alphanumeric(String(repeating: "Z", count: 1852))], errorCorrection: .high) == 40)
    #expect(QRCode.smallestVersion(for: [try .alphanumeric(String(repeating: "Z", count: 1853))], errorCorrection: .high) == nil)
}

/// Table 7, byte capacity at every version and level, low then high.
private let byteMaxima: [(Int, Int, Int)] = [
    (1, 17, 7), (2, 32, 14), (3, 53, 24), (4, 78, 34), (5, 106, 44), (6, 134, 58), (7, 154, 64), (8, 192, 84), (9, 230, 98),
    (10, 271, 119), (11, 321, 137), (12, 367, 155), (13, 425, 177), (14, 458, 194), (15, 520, 220), (16, 586, 250),
    (17, 644, 280), (18, 718, 310), (19, 792, 338), (20, 858, 382), (21, 929, 403), (22, 1003, 439), (23, 1091, 461),
    (24, 1171, 511), (25, 1273, 535), (26, 1367, 593), (27, 1465, 625), (28, 1528, 658), (29, 1628, 698), (30, 1732, 742),
    (31, 1840, 790), (32, 1952, 842), (33, 2068, 898), (34, 2188, 958), (35, 2303, 983), (36, 2431, 1051), (37, 2563, 1093),
    (38, 2699, 1139), (39, 2809, 1219), (40, 2953, 1273),
]

@Test(arguments: byteMaxima)
func byteCapacityMatchesTable7(version: Int, low: Int, high: Int) {
    for (level, maximum) in [(QRCode.ErrorCorrection.low, low), (.high, high)] {
        let fits = QRCode.smallestVersion(for: [.bytes([UInt8](repeating: 0x41, count: maximum))], errorCorrection: level)
        #expect(fits == version, "\(version)-\(level)")
        let overflow = QRCode.smallestVersion(for: [.bytes([UInt8](repeating: 0x41, count: maximum + 1))], errorCorrection: level)
        #expect(overflow == nil || overflow! > version, "\(version)-\(level)")
    }
}

@Test func smallestVersionSkipsVersionsWhereTheCountFieldOverflows() {
    // 256 bytes need a 16-bit count: never version 9 even though its capacity would hold 230.
    let segments = [QRSegment.bytes([UInt8](repeating: 0, count: 256))]
    #expect(QRCode.smallestVersion(for: segments, errorCorrection: .low) == 10)
    #expect(QRCode.smallestVersion(for: segments, errorCorrection: .high) == 17)
    // Many tiny byte segments: header growth at version 10 can make a payload
    // that fits at 9 not fit at 10; the smallest version is still found.
    let many = [QRSegment](repeating: .bytes([1]), count: 90)
    #expect(QRSegment.totalBits(many, version: 9)! <= QRCode.dataCapacity(version: 9, errorCorrection: .low))
    #expect(QRSegment.totalBits(many, version: 10)! > QRCode.dataCapacity(version: 10, errorCorrection: .low))
    #expect(QRCode.smallestVersion(for: many, errorCorrection: .low) == 9)
    #expect(QRCode.smallestVersion(for: many, errorCorrection: .low, in: 10...40) == 11)
    #expect(throws: QRError.dataTooLong) { try QRCode.encode(many, errorCorrection: .low, minVersion: 10, maxVersion: 10) }
}

@Test func boostNeverGrowsTheSymbolAndNeverLowersTheLevel() throws {
    var rng = SplitMix(state: 0xB005)
    for _ in 0..<200 {
        let length = Int.random(in: 1...400, using: &rng)
        let segments = [QRSegment.bytes((0..<length).map { _ in UInt8.random(in: 0...255, using: &rng) })]
        let level = levels.randomElement(using: &rng)!
        let plain = try QRCode.encode(segments, errorCorrection: level, boostErrorCorrection: false)
        let boosted = try QRCode.encode(segments, errorCorrection: level)
        #expect(boosted.version == plain.version)
        #expect(boosted.errorCorrection.index >= level.index)
        // Nothing higher would still fit.
        if boosted.errorCorrection != .high {
            let next = levels[boosted.errorCorrection.index + 1]
            #expect(QRSegment.totalBits(segments, version: boosted.version)! > QRCode.dataCapacity(version: boosted.version, errorCorrection: next))
        }
    }
}

// MARK: - Hostile input

@Test(arguments: ["٣", "1\u{200B}2", "-0", "1e5", " 1", "1 ", "1\n", "0x1", "１", "①", "\u{0}", "1\r\n"])
func numericRejectsUnicodeAndPunctuation(text: String) {
    #expect(throws: QRError.invalidCharacter) { try QRSegment.numeric(text) }
}

@Test(arguments: ["a", "Ａ", "A\t", "A\r", ";", "@", "=", "?", "&", "_", "~", "!", "\"", "'", "(", ")", ",", "A\u{0301}", "É", "\u{FEFF}A"])
func alphanumericRejectsLookalikes(text: String) {
    #expect(throws: QRError.invalidCharacter) { try QRSegment.alphanumeric(text) }
}

@Test func alphanumericAcceptsExactlyTheIsoSet() throws {
    let all = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
    let s = try QRSegment.alphanumeric(all)
    #expect(s.characterCount == 45)
    #expect(s.bits.count == 22 * 11 + 6)
    #expect(try roundTripInMemory([s], level: .low) == Array(all.utf8))
}

@Test func urlSplitIsExactlyAsSpecified() throws {
    // Lowercase, a second hash, or a non-set character in the fragment collapses to bytes.
    for whole in ["https://hatband.link/#1abc", "https://hatband.link/#1ABC#", "https://hatband.link/#1ABC?x", "https://hatband.link/#1ABC\n", "#", "##", "a#"] {
        let segments = QRSegment.segments(forURL: whole)
        #expect(segments == [.bytes(Array(whole.utf8))], "\(whole)")
    }
    // A fragment of only digits or only symbols is still alphanumeric mode.
    #expect(QRSegment.segments(forURL: "x#123").map(\.mode) == [.byte, .alphanumeric])
    #expect(QRSegment.segments(forURL: "x#$%*").map(\.mode) == [.byte, .alphanumeric])
    // Non-ASCII before the hash is carried as UTF-8 bytes; the fragment still splits.
    let unicode = QRSegment.segments(forURL: "https://hatband.link/ü#ABC")
    #expect(unicode.map(\.mode) == [.byte, .alphanumeric])
    #expect(unicode[0].characterCount == "https://hatband.link/ü#".utf8.count)
    #expect(try roundTripInMemory(unicode, level: .medium) == Array("https://hatband.link/ü#ABC".utf8))
}

/// The specified split costs 13 header bits, so it only pays off once the
/// fragment has six or more characters; Hatband fragments always do.
@Test func urlSplitCrossoverIsSixFragmentCharacters() throws {
    for count in 1...8 {
        let url = "https://hatband.link/#" + String(repeating: "A", count: count)
        let split = QRSegment.totalBits(QRSegment.segments(forURL: url), version: 1)!
        let single = QRSegment.totalBits([.bytes(Array(url.utf8))], version: 1)!
        #expect((split < single) == (count >= 6), "\(count) characters: split \(split), single \(single)")
    }
}

@Test func optimalHandlesEdgeStrings() throws {
    #expect(QRSegment.optimal(for: "0").map(\.mode) == [.numeric])
    #expect(QRSegment.optimal(for: " ").map(\.mode) == [.alphanumeric])
    #expect(QRSegment.optimal(for: "0 ").map(\.mode) == [.alphanumeric])
    #expect(QRSegment.optimal(for: "\u{0}").map(\.mode) == [.byte])
    #expect(QRSegment.optimal(for: "🎩").first?.characterCount == 4)
    #expect(try roundTripInMemory(QRSegment.optimal(for: "🎩"), level: .high) == Array("🎩".utf8))
}

@Test func moduleLookupTolerantOfExtremeCoordinates() throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    for (x, y) in [(Int.min, 0), (0, Int.min), (Int.max, 0), (0, Int.max), (Int.min, Int.max), (-1, -1), (code.size, code.size)] {
        #expect(code.module(x: x, y: y) == false)
    }
}

@Test func errorsOnMaskWithOutOfRangeVersions() {
    #expect(throws: QRError.invalidVersion) { try QRCode.encode([], errorCorrection: .low, minVersion: Int.min) }
    #expect(throws: QRError.invalidVersion) { try QRCode.encode([], errorCorrection: .low, maxVersion: Int.max) }
    #expect(throws: QRError.invalidVersion) { try QRCode.encode([], errorCorrection: .low, minVersion: -1, maxVersion: -1) }
    #expect(throws: QRError.invalidMask) { try QRCode.encode([], errorCorrection: .low, mask: Int.min) }
    #expect(throws: QRError.invalidMask) { try QRCode.encode([], errorCorrection: .low, mask: Int.max) }
    // Version validation precedes mask validation, mask precedes capacity.
    #expect(throws: QRError.invalidVersion) { try QRCode.encode([], errorCorrection: .low, minVersion: 0, mask: 9) }
    #expect(throws: QRError.invalidMask) { try QRCode.encode([.bytes([UInt8](repeating: 0, count: 5000))], errorCorrection: .low, mask: 8) }
}

// MARK: - Renderers

@Test func rendererDimensionsAndQuietZone() throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    for (scale, quiet) in [(1, 0), (1, 4), (3, 2), (4, 4), (7, 1)] {
        let side = (code.size + 2 * quiet) * scale
        let pbm = code.pbm(scale: scale, quietZone: quiet)
        let lines = pbm.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "P1")
        #expect(lines[1] == "\(side) \(side)")
        #expect(lines.count == side + 3)
        for row in lines[2..<(2 + side)] {
            #expect(row.count == side)
            #expect(row.allSatisfy { $0 == "0" || $0 == "1" })
        }
        // Quiet zone is entirely light.
        for i in 0..<(quiet * scale) {
            #expect(lines[2 + i].allSatisfy { $0 == "0" })
            #expect(lines[2 + side - 1 - i].allSatisfy { $0 == "0" })
        }
        let svg = code.svg(moduleSize: scale, quietZone: quiet)
        #expect(svg.contains("width=\"\(side)\" height=\"\(side)\" viewBox=\"0 0 \(side) \(side)\""))
        #expect(!code.pathData(moduleSize: Double(scale), quietZone: quiet).contains("."))
        // Dark pixel count from the path equals modules × scale².
        let dark = code.modules.filter { $0 }.count
        let pbmDark = lines[2..<(2 + side)].joined().utf8.filter { $0 == UInt8(ascii: "1") }.count
        #expect(pbmDark == dark * scale * scale)
    }
}

@Test func pathDataGeometryIsExact() throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    let path = code.pathData(moduleSize: 3, quietZone: 2)
    var area = 0
    var runs = 0
    for piece in path.split(separator: "M") {
        let parts = piece.split(whereSeparator: { "hvz ".contains($0) }).map { Int($0)! }
        #expect(parts.count == 5)
        #expect(parts[4] == -parts[2])
        #expect(parts[3] == 3)
        #expect(parts[0] % 3 == 0 && parts[1] % 3 == 0 && parts[2] % 3 == 0)
        #expect(parts[0] >= 6 && parts[1] >= 6)
        area += parts[2] * parts[3]
        runs += 1
    }
    #expect(area == code.modules.filter { $0 }.count * 9)
    // Runs equal the number of dark run starts in the matrix.
    var starts = 0
    for y in 0..<code.size { for x in 0..<code.size where code.module(x: x, y: y) && !code.module(x: x - 1, y: y) { starts += 1 } }
    #expect(runs == starts)
    #expect(path.hasSuffix("z"))
    #expect(!path.contains(" h") && !path.contains("\n"))
}

/// Colour strings are interpolated into attributes verbatim, so a caller
/// passing anything but a colour breaks the document.
@Test func svgDoesNotEscapeColourArguments() throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    withKnownIssue("svg(dark:light:) does not validate or escape its colour arguments") {
        let svg = code.svg(dark: "#000\"/><script>", light: "red\" onload=\"x")
        let injected = svg.contains("<script>") || svg.contains("onload=")
        #expect(!injected)
    }
}

@Test func fractionalModuleSizeKeepsCoordinatesProportional() {
    let tiny = QRCode(version: 1, errorCorrection: .low, mask: 0, size: 2, modules: [true, true, false, true])
    #expect(tiny.pathData(moduleSize: 0.5, quietZone: 0) == "M0 0h1v0.5h-1zM0.5 0.5h0.5v0.5h-0.5z")
    #expect(tiny.pathData(moduleSize: 10, quietZone: 1) == "M10 10h20v10h-20zM20 20h10v10h-10z")
    #expect(tiny.pathData(moduleSize: 1, quietZone: 0) == "M0 0h2v1h-2zM1 1h1v1h-1z")
}

// MARK: - Determinism and concurrency

@Test func concurrentEncodesAgree() async throws {
    let url = "https://hatband.link/#1" + String(repeating: "MZXW6YTBOI2DENBUGA3DGNRVGYZTAMJSGE3DIMBS", count: 5)
    let segments = QRSegment.segments(forURL: url)
    let reference = try QRCode.encode(segments, errorCorrection: .medium)
    let results = await withTaskGroup(of: QRCode?.self) { group in
        for _ in 0..<32 {
            group.addTask { try? QRCode.encode(segments, errorCorrection: .medium) }
        }
        var all: [QRCode?] = []
        for await r in group { all.append(r) }
        return all
    }
    #expect(results.count == 32)
    #expect(results.allSatisfy { $0 == reference })
}

@Test func encodingDoesNotDependOnSegmentIdentity() throws {
    // Equal segments built different ways give the same symbol.
    let a = QRSegment.optimal(for: "HELLO WORLD")
    let b = [try QRSegment.alphanumeric("HELLO WORLD")]
    #expect(a == b)
    #expect(try QRCode.encode(a, errorCorrection: .low) == (try QRCode.encode(b, errorCorrection: .low)))
}

// MARK: - Mask selection versus the reference algorithm

/// Nayuki's penalty scorer, written from the algorithm: runs (N1), 2×2 blocks
/// (N2), finder-like 1:1:3:1:1 patterns at any scale with a 4:1 light margin
/// (N3), and dark proportion (N4).
private func referencePenalty(size: Int, module: (Int, Int) -> Bool) -> Int {
    var result = 0
    for i in 0..<size {
        result += singleLine((0..<size).map { module($0, i) })
        result += singleLine((0..<size).map { module(i, $0) })
    }
    for y in 0..<(size - 1) {
        for x in 0..<(size - 1) {
            let c = module(x, y)
            if c == module(x + 1, y) && c == module(x, y + 1) && c == module(x + 1, y + 1) { result += 3 }
        }
    }
    var dark = 0
    for y in 0..<size { for x in 0..<size where module(x, y) { dark += 1 } }
    let total = size * size
    let k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
    result += k * 10
    return result
}

/// Reference N1 and N3 for one row or column; the border beyond either end
/// counts as a light run as long as the line.
private func singleLine(_ line: [Bool]) -> Int {
    let n = line.count
    var result = 0
    var runColor = false
    var runLength = 0
    var history = [Int](repeating: 0, count: 7)
    func addHistory(_ length: Int) {
        var length = length
        if history[0] == 0 { length += n }
        history.removeLast()
        history.insert(length, at: 0)
    }
    func countPatterns() -> Int {
        let k = history[1]
        let core = k > 0 && history[2] == k && history[3] == 3 * k && history[4] == k && history[5] == k
        return (core && history[0] >= 4 * k && history[6] >= k ? 1 : 0)
            + (core && history[6] >= 4 * k && history[0] >= k ? 1 : 0)
    }
    for dark in line {
        if dark == runColor {
            runLength += 1
            if runLength == 5 { result += 3 } else if runLength > 5 { result += 1 }
        } else {
            addHistory(runLength)
            if !runColor { result += countPatterns() * 40 }
            runColor = dark
            runLength = 1
        }
    }
    if runColor { addHistory(runLength); runLength = 0 }
    runLength += n
    addHistory(runLength)
    result += countPatterns() * 40
    return result
}

private func bits(_ s: String) -> [Bool] {
    s.compactMap { $0 == "1" ? true : $0 == "0" ? false : nil }
}

@Test func linePenaltyAgreesWithReferenceOnUnitScalePatterns() {
    for (line, expected) in [
        ("0000101110100000", 83), ("1011101", 80), ("00001011101", 80), ("0000101110100011", 40),
        ("000001011100", 3), ("01010", 0), ("11111", 3), ("111111111", 7), ("0000000000", 8),
        ("1010101010101", 0), ("0000101110100001011101", 160),
    ] {
        #expect(Matrix.linePenalty(bits(line)) == expected, "\(line)")
        #expect(singleLine(bits(line)) == expected, "\(line)")
    }
}

/// The encoder scores N3 only for the seven-module pattern at unit scale and
/// does not require the far side to be light; Nayuki's reference scores the
/// 1:1:3:1:1 ratio at every scale and demands a light module on the far side.
@Test func linePenaltyDivergesFromReferenceOnScaledAndAbuttingPatterns() {
    let divergent = [
        // 2:2:6:2:2 with eight light modules either side: the reference sees two finders.
        "00000000" + "1100111111001100" + "00000000",
        // Unit pattern with four lights after it but a dark module before it.
        "1" + "1011101" + "0000",
        // Unit pattern with four lights before it but a dark module after it.
        "0000" + "1011101" + "1",
    ]
    withKnownIssue("N3 scoring differs from the Nayuki reference; symbols stay valid, only the mask choice can differ") {
        for line in divergent {
            #expect(Matrix.linePenalty(bits(line)) == singleLine(bits(line)), "\(line)")
        }
    }
}

@Test func penaltyAgreesWithReferenceExceptForN3() throws {
    var rng = SplitMix(state: 0x9A5C)
    var agreements = 0
    var disagreements = 0
    for _ in 0..<30 {
        let length = Int.random(in: 5...120, using: &rng)
        let text = String((0..<length).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".randomElement(using: &rng)! })
        let level = levels.randomElement(using: &rng)!
        for mask in 0..<8 {
            let code = try QRCode.encode([try .alphanumeric(text)], errorCorrection: level, mask: mask)
            var matrix = Matrix(version: code.version)
            matrix.modules = code.modules
            let ours = matrix.penalty()
            let reference = referencePenalty(size: code.size) { code.module(x: $0, y: $1) }
            if ours == reference { agreements += 1 } else { disagreements += 1 }
            // Whatever N3 says, the other three rules agree: differences are multiples of 40.
            #expect((ours - reference) % 40 == 0, "\(text) mask \(mask): \(ours) vs \(reference)")
        }
    }
    #expect(agreements > 0)
    #expect(agreements + disagreements == 240)
}

/// How often the chosen mask differs from the reference's choice: an
/// exploratory count, reported through the failure message.
@Test func maskChoiceVersusReference() throws {
    var rng = SplitMix(state: 0x3A5C)
    var mismatches: [String] = []
    for i in 0..<60 {
        let length = Int.random(in: 5...150, using: &rng)
        let text = "https://hatband.link/#1" + String((0..<length).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".randomElement(using: &rng)! })
        let level = levels.randomElement(using: &rng)!
        let auto = try QRCode.encode(QRSegment.segments(forURL: text), errorCorrection: level)
        var scores: [Int] = []
        for mask in 0..<8 {
            let forced = try QRCode.encode(QRSegment.segments(forURL: text), errorCorrection: level, mask: mask)
            scores.append(referencePenalty(size: forced.size) { forced.module(x: $0, y: $1) })
        }
        let reference = scores.firstIndex(of: scores.min()!)!
        if reference != auto.mask { mismatches.append("case \(i): chose \(auto.mask), reference \(reference) \(scores)") }
    }
    withKnownIssue("mask choice can differ from the Nayuki reference because N3 is scored differently") {
        #expect(mismatches.isEmpty, "\(mismatches.count) of 60: \(mismatches.prefix(3))")
    }
}

// MARK: - zbar at every version and level

private enum ImageMagick {
    static let path: String? = ["/usr/bin/magick", "/usr/local/bin/magick", "/opt/homebrew/bin/magick", "/usr/bin/convert"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Rasterizes the SVG with ImageMagick and decodes the PNG with zbar.
    static func decodeSVG(_ svg: String) throws -> String {
        guard let path, let zbar = ZBar.path else { throw ZBar.Failure(description: "tools missing") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("hatband-qr-\(UUID().uuidString)")
        let svgFile = base.appendingPathExtension("svg")
        let pngFile = base.appendingPathExtension("png")
        try Data(svg.utf8).write(to: svgFile)
        defer { try? FileManager.default.removeItem(at: svgFile); try? FileManager.default.removeItem(at: pngFile) }

        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: path)
        convert.arguments = [svgFile.path, pngFile.path]
        convert.standardOutput = FileHandle.nullDevice
        convert.standardError = FileHandle.nullDevice
        try convert.run()
        convert.waitUntilExit()
        guard convert.terminationStatus == 0 else { throw ZBar.Failure(description: "ImageMagick failed") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: zbar)
        process.arguments = ["--raw", "-q", "-Sdisable", "-Sqrcode.enable", pngFile.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw ZBar.Failure(description: "zbarimg failed with status \(process.terminationStatus)")
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }
}

@Suite("zbar adversarial", .enabled(if: ZBar.available, "zbarimg is not installed"))
struct ZBarAdversarialTests {
    /// Every version at every level, filled to capacity with bytes, so that
    /// each block structure in Table 9 is exercised by a real decoder.
    @Test(arguments: 1...40)
    func everyVersionAndLevel(version: Int) throws {
        for level in levels {
            let capacity = (QRCode.dataCapacity(version: version, errorCorrection: level) - 4 - QRSegment.Mode.byte.characterCountBits(version: version)) / 8
            let text = String((0..<capacity).map { Character(UnicodeScalar(UInt8(0x21 + ($0 &* 7) % 94))) })
            let code = try QRCode.encode([.bytes(Array(text.utf8))], errorCorrection: level, boostErrorCorrection: false)
            #expect(code.version == version && code.errorCorrection == level)
            #expect(try ZBar.decode(code, scale: version > 20 ? 3 : 4) == text, "\(version)-\(level)")
        }
    }

    /// The count field widths not reached by the other suites: numeric at
    /// 12 and 14 bits, alphanumeric at 11 and 13.
    @Test func wideCountFields() throws {
        var rng = SplitMix(state: 0xC0DE)
        let digits4000 = String((0..<4000).map { _ in "0123456789".randomElement(using: &rng)! })
        let digits600 = String(digits4000.prefix(600))
        let letters2500 = String((0..<2500).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".randomElement(using: &rng)! })
        let letters400 = String(letters2500.prefix(400))
        let cases: [(String, QRSegment, ClosedRange<Int>)] = [
            (digits600, try .numeric(digits600), 10...26),
            (digits4000, try .numeric(digits4000), 27...40),
            (letters400, try .alphanumeric(letters400), 10...26),
            (letters2500, try .alphanumeric(letters2500), 27...40),
        ]
        for (text, segment, expected) in cases {
            let code = try QRCode.encode([segment], errorCorrection: .low, boostErrorCorrection: false)
            #expect(expected.contains(code.version), "\(text.count) characters gave version \(code.version)")
            #expect(try ZBar.decode(code, scale: 3) == text)
        }
    }

    @Test func maximaAtFortyLowDecode() throws {
        let digits = String((0..<7089).map { Character(UnicodeScalar(UInt8(0x30 + ($0 &* 3) % 10))) })
        let letters = String((0..<4296).map { $0 % 7 == 0 ? Character("-") : Character("A") })
        for (text, segment) in [(digits, try QRSegment.numeric(digits)), (letters, try QRSegment.alphanumeric(letters))] {
            let code = try QRCode.encode([segment], errorCorrection: .low, boostErrorCorrection: false)
            #expect(code.version == 40)
            #expect(try ZBar.decode(code, scale: 3) == text)
        }
    }

    @Test func leadingZerosAndSingleDigitsSurvive() throws {
        for text in ["0", "00", "000", "0000000000", "007", "1000000", "0" + String(repeating: "9", count: 40)] {
            let code = try QRCode.encode([try .numeric(text)], errorCorrection: .medium)
            #expect(try ZBar.decode(code) == text, "\(text)")
        }
    }

    @Test func partialTerminatorsDecode() throws {
        // One, four, and zero terminator bits.
        let cases: [(QRCode.ErrorCorrection, [QRSegment], String)] = [
            (.low, [try .alphanumeric(String(repeating: "Z", count: 25))], String(repeating: "Z", count: 25)),
            (.low, [.bytes([UInt8](repeating: 0x41, count: 17))], String(repeating: "A", count: 17)),
            (.low, [.bytes([UInt8](repeating: 0x42, count: 14)), try .numeric("1234")], String(repeating: "B", count: 14) + "1234"),
            (.high, [try .numeric("12345"), try .alphanumeric("ABCDE")], "12345ABCDE"),
        ]
        for (level, segments, text) in cases {
            let code = try QRCode.encode(segments, errorCorrection: level, boostErrorCorrection: false)
            #expect(code.version == 1)
            #expect(try ZBar.decode(code) == text)
        }
    }

    @Test func zeroLengthSegmentsDecode() throws {
        let segments: [QRSegment] = [.bytes([]), try .numeric(""), try .alphanumeric("HATBAND"), try .alphanumeric("")]
        let code = try QRCode.encode(segments, errorCorrection: .quartile)
        #expect(try ZBar.decode(code) == "HATBAND")
    }

    @Test func segmentOrderIsPreserved() throws {
        let segments: [QRSegment] = [
            try .alphanumeric("A"), try .numeric("1"), .bytes(Array("b".utf8)), try .numeric("22"), try .alphanumeric("CC"),
            .bytes(Array("dd".utf8)), try .numeric("333"), try .alphanumeric("EEE"), .bytes(Array("fff".utf8)),
        ]
        let code = try QRCode.encode(segments, errorCorrection: .low)
        #expect(try ZBar.decode(code) == "A1b22CCdd333EEEfff")
    }

    @Test(arguments: [1, 5, 10, 27])
    func eachMaskAtEachLevel(version: Int) throws {
        let text = "https://hatband.link/#1" + String(repeating: "MZXW6YTBOI2DENBUGA3DGNRVGYZTAMJSGE3DIMBS", count: version)
        let segments = QRSegment.segments(forURL: text)
        for level in levels {
            for mask in 0..<8 {
                let code = try QRCode.encode(segments, errorCorrection: level, minVersion: version, boostErrorCorrection: false, mask: mask)
                #expect(code.mask == mask && code.errorCorrection == level && code.version >= version)
                #expect(try ZBar.decode(code, scale: 3) == text, "\(version)-\(level) mask \(mask)")
            }
        }
    }

    @Test(arguments: [1, 3, 5, 6, 7, 8, 9, 11, 12, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26])
    func hatbandPayloadsOfManySizes(version: Int) throws {
        var rng = SplitMix(state: 0x4A7 &+ UInt64(version))
        let payloadBytes = version * 20
        let url = "https://hatband.link/#1" + Base32.encode((0..<payloadBytes).map { _ in UInt8.random(in: 0...255, using: &rng) })
        let segments = QRSegment.segments(forURL: url)
        #expect(segments.map(\.mode) == [.byte, .alphanumeric])
        let code = try QRCode.encode(segments, errorCorrection: .medium)
        #expect(try ZBar.decode(code, scale: 3) == url)
    }

    @Test func randomPrintableBytesDecode() throws {
        // Printable ASCII only: zbar's charset guessing is not under test, the placement is.
        var rng = SplitMix(state: 0xA5C1)
        for _ in 0..<40 {
            let length = Int.random(in: 1...600, using: &rng)
            let text = String((0..<length).map { _ in Character(UnicodeScalar(UInt8.random(in: 0x20...0x7E, using: &rng))) })
            let level = levels.randomElement(using: &rng)!
            let code = try QRCode.encode([.bytes(Array(text.utf8))], errorCorrection: level)
            #expect(try ZBar.decode(code, scale: 3) == text)
        }
    }

    @Test func pbmAtScaleOneAndTwoStillDecodes() throws {
        let url = "https://hatband.link/#1MZXW6YTBOI2DENBUGA3DGNRVGYZTAMJSGE3DIMBSGIZTIMJUGQ2TMNRWG44DSOBZ"
        let code = try QRCode.encode(QRSegment.segments(forURL: url), errorCorrection: .medium)
        #expect(try ZBar.decode(code, scale: 2) == url)
        #expect(try ZBar.decode(code, scale: 1) == url)
    }
}

@Suite("SVG through ImageMagick", .enabled(if: ZBar.available && ImageMagick.path != nil, "zbarimg or ImageMagick is not installed"))
struct SVGRasterTests {
    @Test(arguments: [1, 4, 10, 25, 40])
    func svgRasterizesAndDecodes(version: Int) throws {
        let capacity = (QRCode.dataCapacity(version: version, errorCorrection: .medium) - 20) / 8
        let text = String((0..<capacity).map { Character(UnicodeScalar(UInt8(0x21 + ($0 &* 11) % 94))) })
        let code = try QRCode.encode([.bytes(Array(text.utf8))], errorCorrection: .medium, boostErrorCorrection: false)
        #expect(code.version == version)
        #expect(try ImageMagick.decodeSVG(code.svg(moduleSize: 4, quietZone: 4)) == text)
    }

    @Test func svgWithCustomColoursDecodes() throws {
        let url = "https://hatband.link/#1MZXW6YTBOI2DENBUGA3DGNRVGYZTAMJSGE3DIMBS"
        let code = try QRCode.encode(QRSegment.segments(forURL: url), errorCorrection: .medium)
        #expect(try ImageMagick.decodeSVG(code.svg(moduleSize: 6, quietZone: 4, dark: "#101010", light: "#fafafa")) == url)
        #expect(try ImageMagick.decodeSVG(code.svg(moduleSize: 3, quietZone: 2)) == url)
    }
}
