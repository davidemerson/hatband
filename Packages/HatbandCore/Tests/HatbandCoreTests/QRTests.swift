import Testing
@testable import HatbandCore

private func bits(_ s: String) -> [Bool] {
    s.compactMap { $0 == "1" ? true : $0 == "0" ? false : nil }
}

private let levels = QRCode.ErrorCorrection.allCases

/// A symbol whose data is just padding, at a fixed version and level.
private func emptySymbol(version: Int, level: QRCode.ErrorCorrection) throws -> QRCode {
    try QRCode.encode([], errorCorrection: level, minVersion: version, maxVersion: version, boostErrorCorrection: false)
}

// MARK: - Segments

@Test func numericSegmentBits() throws {
    // ISO/IEC 18004 §7.4.3 example.
    let s = try QRSegment.numeric("01234567")
    #expect(s.mode == .numeric)
    #expect(s.characterCount == 8)
    #expect(s.bits == bits("0000001100 0101011001 1000011"))
    #expect(try QRSegment.numeric("").bits.isEmpty)
    #expect(try QRSegment.numeric("7").bits == bits("0111"))
    #expect(try QRSegment.numeric("99").bits == bits("1100011"))
    #expect(try QRSegment.numeric("999").bits == bits("1111100111"))
}

@Test func alphanumericSegmentBits() throws {
    // ISO/IEC 18004 §7.4.4 example.
    let s = try QRSegment.alphanumeric("AC-42")
    #expect(s.mode == .alphanumeric)
    #expect(s.characterCount == 5)
    #expect(s.bits == bits("00111001110 11100111001 000010"))
    #expect(try QRSegment.alphanumeric(":").bits == bits("101100"))
    #expect(try QRSegment.alphanumeric("::").bits.count == 11)
    #expect(try QRSegment.alphanumeric("").bits.isEmpty)
}

@Test func byteSegmentBits() {
    let s = QRSegment.bytes([0x00, 0xFF, 0x5A])
    #expect(s.mode == .byte)
    #expect(s.characterCount == 3)
    #expect(s.bits == bits("00000000 11111111 01011010"))
    #expect(QRSegment.bytes([]).bits.isEmpty)
}

@Test(arguments: ["a", "12a", "-1", " ", "１２", "1.5", "+1"])
func numericRejects(text: String) {
    #expect(throws: QRError.invalidCharacter) { try QRSegment.numeric(text) }
}

@Test(arguments: ["a", "abc", "A!", "#", "_", "Ü", "A\n", "\u{0}", "A,B", "A\u{FF}"])
func alphanumericRejects(text: String) {
    #expect(throws: QRError.invalidCharacter) { try QRSegment.alphanumeric(text) }
}

@Test func alphanumericCharsetIsExactly45() {
    let accepted = (0...255).map(UInt8.init).filter { QRSegment.alphanumericValue($0) != nil }
    #expect(accepted == Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8).sorted())
    #expect(QRSegment.alphanumericValue(UInt8(ascii: "0")) == 0)
    #expect(QRSegment.alphanumericValue(UInt8(ascii: "A")) == 10)
    #expect(QRSegment.alphanumericValue(UInt8(ascii: " ")) == 36)
    #expect(QRSegment.alphanumericValue(UInt8(ascii: ":")) == 44)
}

@Test func optimalPicksTheDensestMode() {
    #expect(QRSegment.optimal(for: "").isEmpty)
    #expect(QRSegment.optimal(for: "0123").map(\.mode) == [.numeric])
    #expect(QRSegment.optimal(for: "HELLO WORLD").map(\.mode) == [.alphanumeric])
    #expect(QRSegment.optimal(for: "hello").map(\.mode) == [.byte])
    #expect(QRSegment.optimal(for: "Ulysses").first?.characterCount == 7)
    #expect(QRSegment.optimal(for: "ü").first?.characterCount == 2)
}

@Test func urlSegmentsSplitAtTheFragment() throws {
    let split = QRSegment.segments(forURL: "https://hatband.link/#1ABC234")
    #expect(split.count == 2)
    #expect(split[0] == .bytes(Array("https://hatband.link/#".utf8)))
    #expect(split[1] == (try QRSegment.alphanumeric("1ABC234")))

    for whole in ["https://hatband.link/", "https://hatband.link/#", "https://hatband.link/#abc", "a#B#C", "#Ü", ""] {
        #expect(QRSegment.segments(forURL: whole) == [.bytes(Array(whole.utf8))], "\(whole)")
    }
    #expect(QRSegment.segments(forURL: "#A") == [.bytes([UInt8(ascii: "#")]), try .alphanumeric("A")])
}

@Test func characterCountFieldWidths() {
    for v in 1...9 {
        #expect(QRSegment.Mode.numeric.characterCountBits(version: v) == 10)
        #expect(QRSegment.Mode.alphanumeric.characterCountBits(version: v) == 9)
        #expect(QRSegment.Mode.byte.characterCountBits(version: v) == 8)
    }
    for v in 10...26 {
        #expect(QRSegment.Mode.numeric.characterCountBits(version: v) == 12)
        #expect(QRSegment.Mode.alphanumeric.characterCountBits(version: v) == 11)
        #expect(QRSegment.Mode.byte.characterCountBits(version: v) == 16)
    }
    for v in 27...40 {
        #expect(QRSegment.Mode.numeric.characterCountBits(version: v) == 14)
        #expect(QRSegment.Mode.alphanumeric.characterCountBits(version: v) == 13)
        #expect(QRSegment.Mode.byte.characterCountBits(version: v) == 16)
    }
}

@Test func totalBitsCountsHeadersAndRefusesOverflowingCounts() throws {
    let s = try QRSegment.alphanumeric("AC-42")
    #expect(QRSegment.totalBits([s], version: 1) == 4 + 9 + 28)
    #expect(QRSegment.totalBits([s], version: 10) == 4 + 11 + 28)
    #expect(QRSegment.totalBits([s, s], version: 27) == 2 * (4 + 13 + 28))
    #expect(QRSegment.totalBits([], version: 1) == 0)
    let long = QRSegment.bytes([UInt8](repeating: 0, count: 256))
    #expect(QRSegment.totalBits([long], version: 9) == nil)
    #expect(QRSegment.totalBits([long], version: 10) == 4 + 16 + 2048)
    let digits = try QRSegment.numeric(String(repeating: "7", count: 1024))
    #expect(QRSegment.totalBits([digits], version: 9) == nil)
    #expect(QRSegment.totalBits([digits], version: 10) != nil)
}

// MARK: - Tables

private let totalCodewords = [
    26, 44, 70, 100, 134, 172, 196, 242, 292, 346, 404, 466, 532, 581, 655, 733, 815, 901, 991, 1085,
    1156, 1258, 1364, 1474, 1588, 1706, 1828, 1921, 2051, 2185, 2323, 2465, 2611, 2761, 2876, 3034, 3196, 3362, 3532, 3706,
]

/// ISO/IEC 18004 Table 7, data codewords by level.
private let dataCodewords: [[Int]] = [
    [19, 34, 55, 80, 108, 136, 156, 194, 232, 274, 324, 370, 428, 461, 523, 589, 647, 721, 795, 861,
     932, 1006, 1094, 1174, 1276, 1370, 1468, 1531, 1631, 1735, 1843, 1955, 2071, 2191, 2306, 2434, 2566, 2702, 2812, 2956],
    [16, 28, 44, 64, 86, 108, 124, 154, 182, 216, 254, 290, 334, 365, 415, 453, 507, 563, 627, 669,
     714, 782, 860, 914, 1000, 1062, 1128, 1193, 1267, 1373, 1455, 1541, 1631, 1725, 1812, 1914, 1992, 2102, 2216, 2334],
    [13, 22, 34, 48, 62, 76, 88, 110, 132, 154, 180, 206, 244, 261, 295, 325, 367, 397, 445, 485,
     512, 568, 614, 664, 718, 754, 808, 871, 911, 985, 1033, 1115, 1171, 1231, 1286, 1354, 1426, 1502, 1582, 1666],
    [9, 16, 26, 36, 46, 60, 66, 86, 100, 122, 140, 158, 180, 197, 223, 253, 283, 313, 341, 385,
     406, 442, 464, 514, 538, 596, 628, 661, 701, 745, 793, 845, 901, 961, 986, 1054, 1096, 1142, 1222, 1276],
]

/// ISO/IEC 18004 Annex E, Table E.1.
private let alignmentTable: [[Int]] = [
    [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34],
    [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50], [6, 30, 54], [6, 32, 58], [6, 34, 62],
    [6, 26, 46, 66], [6, 26, 48, 70], [6, 26, 50, 74], [6, 30, 54, 78], [6, 30, 56, 82], [6, 30, 58, 86], [6, 34, 62, 90],
    [6, 28, 50, 72, 94], [6, 26, 50, 74, 98], [6, 30, 54, 78, 102], [6, 28, 54, 80, 106], [6, 32, 58, 84, 110],
    [6, 30, 58, 86, 114], [6, 34, 62, 90, 118],
    [6, 26, 50, 74, 98, 122], [6, 30, 54, 78, 102, 126], [6, 26, 52, 78, 104, 130], [6, 30, 56, 82, 108, 134],
    [6, 34, 60, 86, 112, 138], [6, 30, 58, 86, 114, 142], [6, 34, 62, 90, 118, 146],
    [6, 30, 54, 78, 102, 126, 150], [6, 24, 50, 76, 102, 128, 154], [6, 28, 54, 80, 106, 132, 158],
    [6, 32, 58, 84, 110, 136, 162], [6, 26, 54, 82, 110, 138, 166], [6, 30, 58, 86, 114, 142, 170],
]

/// Remainder bits after the last codeword, Table 1.
private func remainderBits(version: Int) -> Int {
    switch version {
    case 2...6: 7
    case 14...20, 28...34: 3
    case 21...27: 4
    default: 0
    }
}

@Test(arguments: 1...40)
func codewordTables(version: Int) {
    #expect(QRCode.totalCodewords(version: version) == totalCodewords[version - 1])
    for level in levels {
        let data = QRCode.dataCodewordCount(version: version, errorCorrection: level)
        #expect(data == dataCodewords[level.index][version - 1], "\(version)-\(level)")
        #expect(QRCode.dataCapacity(version: version, errorCorrection: level) == data * 8)
        let blocks = QRCode.blockCounts[level.index][version]
        let ecc = QRCode.eccCodewordsPerBlock[level.index][version]
        #expect(blocks >= 1)
        #expect((7...30).contains(ecc))
        // Every block has at least one data codeword and the short/long split is exact.
        #expect(QRCode.totalCodewords(version: version) / blocks > ecc)
    }
    #expect(QRCode.alignmentPositions(version: version) == alignmentTable[version - 1])
}

@Test func knownTotals() {
    #expect(QRCode.totalCodewords(version: 1) == 26)
    #expect(QRCode.totalCodewords(version: 10) == 346)
    #expect(QRCode.totalCodewords(version: 40) == 3706)
}

// MARK: - Codewords

@Test func isoWorkedExampleCodewords() throws {
    let segments = [try QRSegment.numeric("01234567")]
    let data = QRCode.dataCodewords(segments, version: 1, errorCorrection: .medium)
    #expect(data == [0x10, 0x20, 0x0C, 0x56, 0x61, 0x80, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11])
    let all = QRCode.interleave(data, version: 1, errorCorrection: .medium)
    #expect(all.count == 26)
    #expect(Array(all[..<16]) == data)
    #expect(Array(all[16...]) == [0xA5, 0x24, 0xD4, 0xC1, 0xED, 0x36, 0xC7, 0x87, 0x2C, 0x55])
}

@Test func terminatorIsShortenedWhenTheSymbolIsFull() throws {
    // 1-L holds 152 bits; 17 bytes use 4 + 8 + 136 = 148, leaving room for exactly four terminator bits.
    let full = QRCode.dataCodewords([.bytes([UInt8](repeating: 0xFF, count: 17))], version: 1, errorCorrection: .low)
    #expect(full.count == 19)
    #expect(full.last == 0xF0)
    // 1-H holds 72 bits; 7 bytes use 68, leaving four, all of them terminator.
    let tight = QRCode.dataCodewords([.bytes([UInt8](repeating: 0xFF, count: 7))], version: 1, errorCorrection: .high)
    #expect(tight.count == 9)
    #expect(tight.last == 0xF0)
    // 41 digits at 1-L: 4 + 10 + 137 = 151 bits, one terminator bit.
    let digits = QRCode.dataCodewords([try .numeric(String(repeating: "9", count: 41))], version: 1, errorCorrection: .low)
    #expect(digits.count == 19)
}

@Test func padBytesAlternate() {
    let data = QRCode.dataCodewords([], version: 1, errorCorrection: .low)
    #expect(data == [0x00] + Array(repeating: [0xEC, 0x11], count: 9).flatMap { $0 })
    #expect(data.count == 19)
}

@Test(arguments: 1...40)
func interleavingCoversEveryCodeword(version: Int) {
    for level in levels {
        let count = QRCode.dataCodewordCount(version: version, errorCorrection: level)
        let data = (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ 7) }
        let all = QRCode.interleave(data, version: version, errorCorrection: level)
        #expect(all.count == QRCode.totalCodewords(version: version), "\(version)-\(level)")
        // Data codewords appear before any ECC and every one of them is present.
        let blocks = QRCode.blockCounts[level.index][version]
        let ecc = QRCode.eccCodewordsPerBlock[level.index][version]
        let dataPart = Array(all[..<count])
        #expect(dataPart.sorted() == data.sorted())
        #expect(all.count - count == blocks * ecc)
        if blocks == 1 {
            #expect(dataPart == data)
            let g = ReedSolomon.generator(degree: ecc)
            #expect(ReedSolomon.remainder(of: all, generator: g).allSatisfy { $0 == 0 })
        }
    }
}

@Test func interleavingOrderWithUnevenBlocks() {
    // 5-H: 4 blocks of 11, 11, 12, 12 data codewords (46 total) and 22 ECC each.
    let data = (0..<46).map { UInt8($0) }
    let all = QRCode.interleave(data, version: 5, errorCorrection: .high)
    #expect(all.count == 134)
    #expect(Array(all[..<8]) == [0, 11, 22, 34, 1, 12, 23, 35])
    #expect(Array(all[40..<46]) == [10, 21, 32, 44, 33, 45])
    // ECC interleaves block by block too.
    let g = ReedSolomon.generator(degree: 22)
    let eccs = [Array(data[0..<11]), Array(data[11..<22]), Array(data[22..<34]), Array(data[34..<46])]
        .map { ReedSolomon.remainder(of: $0, generator: g) }
    for i in 0..<22 {
        for b in 0..<4 { #expect(all[46 + i * 4 + b] == eccs[b][i]) }
    }
}

// MARK: - Format and version information

/// ISO/IEC 18004 Table C.1.
private let formatTable: [(QRCode.ErrorCorrection, [Int])] = [
    (.low, [0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976]),
    (.medium, [0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0]),
    (.quartile, [0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED]),
    (.high, [0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B]),
]

/// Polynomial remainder over GF(2), written independently of the encoder.
private func remainder(_ value: Int, bits: Int, generator: Int, degree: Int) -> Int {
    var v = value
    for i in stride(from: bits - 1, through: degree, by: -1) where (v >> i) & 1 == 1 {
        v ^= generator << (i - degree)
    }
    return v
}

@Test(arguments: formatTable)
func formatBitsMatchTheTable(level: QRCode.ErrorCorrection, expected: [Int]) {
    for mask in 0..<8 {
        let bits = QRCode.formatBits(errorCorrection: level, mask: mask)
        #expect(bits == expected[mask], "\(level) mask \(mask)")
        #expect(bits >> 15 == 0)
        // Unmasked, the word is a BCH(15,5) codeword with the data in the top five bits.
        let raw = bits ^ 0x5412
        #expect(remainder(raw, bits: 15, generator: 0x537, degree: 10) == 0)
        #expect(raw >> 10 == level.formatBits << 3 | mask)
    }
}

@Test func formatWordsAreAllDistinct() {
    var words = Set<Int>()
    for level in levels { for mask in 0..<8 { words.insert(QRCode.formatBits(errorCorrection: level, mask: mask)) } }
    #expect(words.count == 32)
    // Minimum Hamming distance 7 lets a reader fix three bit errors.
    let list = Array(words)
    for i in list.indices { for j in list.indices where i < j { #expect((list[i] ^ list[j]).nonzeroBitCount >= 7) } }
}

@Test(arguments: [(7, 0x07C94), (21, 0x15683), (40, 0x28C69)])
func versionBitsMatchKnownValues(version: Int, expected: Int) {
    #expect(QRCode.versionBits(version: version) == expected)
}

@Test(arguments: 7...40)
func versionBitsAreBCHCodewords(version: Int) {
    let bits = QRCode.versionBits(version: version)
    #expect(bits >> 18 == 0)
    #expect(bits >> 12 == version)
    #expect(remainder(bits, bits: 18, generator: 0x1F25, degree: 12) == 0)
}

// MARK: - Structure

@Test(arguments: [1, 2, 5, 6, 7, 10, 13, 14, 20, 21, 27, 28, 32, 35, 40])
func symbolStructure(version: Int) throws {
    for level in levels {
        let code = try emptySymbol(version: version, level: level)
        let size = 17 + 4 * version
        #expect(code.size == size)
        #expect(code.modules.count == size * size)
        #expect(code.version == version)
        #expect(code.errorCorrection == level)
        #expect(code.module(x: -1, y: 0) == false)
        #expect(code.module(x: 0, y: size) == false)

        var wrong: [String] = []
        // Finders with separators at three corners.
        for (cx, cy) in [(3, 3), (size - 4, 3), (3, size - 4)] {
            for dy in -4...4 {
                for dx in -4...4 {
                    let x = cx + dx, y = cy + dy
                    guard (0..<size).contains(x), (0..<size).contains(y) else { continue }
                    let ring = max(abs(dx), abs(dy))
                    if code.module(x: x, y: y) != (ring != 2 && ring != 4) { wrong.append("finder (\(x),\(y))") }
                }
            }
        }
        // Timing patterns between the finders, dark at even positions.
        for i in 8..<(size - 8) {
            if code.module(x: 6, y: i) != (i % 2 == 0) { wrong.append("timing (6,\(i))") }
            if code.module(x: i, y: 6) != (i % 2 == 0) { wrong.append("timing (\(i),6)") }
        }
        // Dark module.
        #expect(code.module(x: 8, y: 4 * version + 9))

        // Alignment patterns at every table position not under a finder.
        let positions = QRCode.alignmentPositions(version: version)
        var found = 0
        for cy in positions {
            for cx in positions {
                if (cx == 6 && cy == 6) || (cx == 6 && cy == size - 7) || (cx == size - 7 && cy == 6) { continue }
                for dy in -2...2 {
                    for dx in -2...2 where code.module(x: cx + dx, y: cy + dy) != (max(abs(dx), abs(dy)) != 1) {
                        wrong.append("alignment (\(cx),\(cy))")
                    }
                }
                found += 1
            }
        }
        #expect(wrong.isEmpty, "\(version)-\(level): \(wrong)")
        let expectedCount = version == 1 ? 0 : positions.count * positions.count - 3
        #expect(found == expectedCount)

        // Format information: both copies decode to the level and mask.
        let bits = QRCode.formatBits(errorCorrection: level, mask: code.mask)
        var first = 0, second = 0
        for i in 0...5 where code.module(x: 8, y: i) { first |= 1 << i }
        if code.module(x: 8, y: 7) { first |= 1 << 6 }
        if code.module(x: 8, y: 8) { first |= 1 << 7 }
        if code.module(x: 7, y: 8) { first |= 1 << 8 }
        for i in 9..<15 where code.module(x: 14 - i, y: 8) { first |= 1 << i }
        for i in 0..<8 where code.module(x: size - 1 - i, y: 8) { second |= 1 << i }
        for i in 8..<15 where code.module(x: 8, y: size - 15 + i) { second |= 1 << i }
        #expect(first == bits)
        #expect(second == bits)

        // Version information for 7 and up, both copies.
        if version >= 7 {
            let expected = QRCode.versionBits(version: version)
            var a = 0, b = 0
            for i in 0..<18 {
                if code.module(x: size - 11 + i % 3, y: i / 3) { a |= 1 << i }
                if code.module(x: i / 3, y: size - 11 + i % 3) { b |= 1 << i }
            }
            #expect(a == expected)
            #expect(b == expected)
        }
    }
}

@Test(arguments: 1...40)
func dataRegionHoldsExactlyTheCodewordsPlusRemainder(version: Int) {
    var matrix = Matrix(version: version)
    matrix.drawFunctionPatterns()
    let dataModules = matrix.isFunction.filter { !$0 }.count
    #expect(dataModules == QRCode.totalCodewords(version: version) * 8 + remainderBits(version: version))
}

@Test func codewordsArePlacedInZigzagOrder() {
    // Version 1: the first codeword fills the bottom-right 2×4 block, upward.
    var matrix = Matrix(version: 1)
    matrix.drawFunctionPatterns()
    var codewords = [UInt8](repeating: 0, count: 26)
    codewords[0] = 0b1011_0001
    matrix.drawCodewords(codewords)
    let order = [(20, 20), (19, 20), (20, 19), (19, 19), (20, 18), (19, 18), (20, 17), (19, 17)]
    for (i, (x, y)) in order.enumerated() {
        #expect(matrix[x, y] == ((0b1011_0001 >> (7 - i)) & 1 == 1))
    }
    #expect(matrix.modules.filter { $0 }.count == matrix.isFunction.enumerated().filter { $0.element && matrix.modules[$0.offset] }.count + 4)
}

// MARK: - Encoding and masks

@Test func encodesTheIsoExampleSymbol() throws {
    let code = try QRCode.encode([try .numeric("01234567")], errorCorrection: .medium, boostErrorCorrection: false)
    #expect(code.version == 1)
    #expect(code.errorCorrection == .medium)
    #expect(code.size == 21)
    #expect((0...7).contains(code.mask))
}

@Test func boostRaisesTheLevelWithoutGrowing() throws {
    let segments = [try QRSegment.numeric("01234567")]
    let boosted = try QRCode.encode(segments, errorCorrection: .medium)
    #expect(boosted.version == 1)
    #expect(boosted.errorCorrection == .high)
    let asked = try QRCode.encode(segments, errorCorrection: .medium, boostErrorCorrection: false)
    #expect(asked.errorCorrection == .medium)
    // 17 bytes fill 1-L exactly; nothing higher fits at version 1.
    let full = try QRCode.encode([.bytes([UInt8](repeating: 1, count: 17))], errorCorrection: .low)
    #expect(full.version == 1 && full.errorCorrection == .low)
    // 14 bytes fit 1-M (128 bits: 4 + 8 + 112 = 124) but not 1-Q (104).
    let some = try QRCode.encode([.bytes([UInt8](repeating: 1, count: 14))], errorCorrection: .low)
    #expect(some.version == 1 && some.errorCorrection == .medium)
}

@Test func forcedMasksProduceTheSameDataUnderTheMask() throws {
    let segments = QRSegment.segments(forURL: "https://hatband.link/#1MZXW6YTBOI")
    let reference = try QRCode.encode(segments, errorCorrection: .medium, mask: 0)
    #expect(reference.version == 3)
    #expect(reference.errorCorrection == .quartile)
    var function = Matrix(version: reference.version)
    function.drawFunctionPatterns()
    for mask in 0..<8 {
        let code = try QRCode.encode(segments, errorCorrection: .medium, mask: mask)
        #expect(code.mask == mask)
        #expect(code.version == reference.version)
        var mismatches: [(Int, Int)] = []
        for y in 0..<code.size {
            for x in 0..<code.size where !function.isFunction[y * code.size + x] {
                let unmasked = code.module(x: x, y: y) != QRCode.maskBit(mask, x: x, y: y)
                let expected = reference.module(x: x, y: y) != QRCode.maskBit(0, x: x, y: y)
                if unmasked != expected { mismatches.append((x, y)) }
            }
        }
        #expect(mismatches.isEmpty, "mask \(mask): \(mismatches)")
    }
}

@Test func automaticMaskHasTheLowestPenalty() throws {
    for text in ["HATBAND", "https://hatband.link/#1ABCDEFGHIJKLMNOPQRSTUVWXYZ234567", "0000000000000000000000000000000"] {
        let segments = QRSegment.optimal(for: text)
        let auto = try QRCode.encode(segments, errorCorrection: .quartile)
        var scores: [Int] = []
        for mask in 0..<8 {
            let forced = try QRCode.encode(segments, errorCorrection: .quartile, mask: mask)
            var m = Matrix(version: forced.version)
            m.modules = forced.modules
            scores.append(m.penalty())
            if mask == auto.mask { #expect(forced == auto) }
        }
        #expect(scores[auto.mask] == scores.min())
        #expect(auto.mask == scores.firstIndex(of: scores.min()!))
    }
}

@Test func maskPatternsMatchTable10() {
    // The top-left 6×6 of each pattern, rows top to bottom, 1 where inverted.
    let expected = [
        ["101010", "010101", "101010", "010101", "101010", "010101"],
        ["111111", "000000", "111111", "000000", "111111", "000000"],
        ["100100", "100100", "100100", "100100", "100100", "100100"],
        ["100100", "001001", "010010", "100100", "001001", "010010"],
        ["111000", "111000", "000111", "000111", "111000", "111000"],
        ["111111", "100000", "100100", "101010", "100100", "100000"],
        ["111111", "111000", "110110", "101010", "101101", "100011"],
        ["101010", "000111", "100011", "010101", "111000", "011100"],
    ]
    for mask in 0..<8 {
        for y in 0..<6 {
            let row = String((0..<6).map { QRCode.maskBit(mask, x: $0, y: y) ? "1" : "0" })
            #expect(row == expected[mask][y], "mask \(mask) row \(y)")
        }
    }
}

@Test func penaltyRulesOnCraftedLines() {
    #expect(Matrix.linePenalty([Bool](repeating: false, count: 4)) == 0)
    #expect(Matrix.linePenalty([Bool](repeating: true, count: 5)) == 3)
    #expect(Matrix.linePenalty([Bool](repeating: true, count: 6)) == 4)
    #expect(Matrix.linePenalty([Bool](repeating: true, count: 9)) == 7)
    #expect(Matrix.linePenalty(bits("01010")) == 0)
    // Finder-like pattern with four lights after it only.
    #expect(Matrix.linePenalty(bits("110111010000")) == 40)
    // Border counts as light on both ends.
    #expect(Matrix.linePenalty(bits("1011101")) == 80)
    #expect(Matrix.linePenalty(bits("00001011101")) == 80)
    #expect(Matrix.linePenalty(bits("0000101110100011")) == 40)
    // Not a finder pattern; a run of five.
    #expect(Matrix.linePenalty(bits("000001011100")) == 3)
}

@Test func penaltyOnBlankSymbol() {
    // 21 rows and columns of 21: N1 = 42 × (3 + 16); N2 = 400 × 3; N4: 0% dark is ten steps from 50%, so k = 9.
    let matrix = Matrix(version: 1)
    #expect(matrix.penalty() == 42 * 19 + 400 * 3 + 90)
    var dark = matrix
    dark.modules = [Bool](repeating: true, count: 441)
    #expect(dark.penalty() == 42 * 19 + 400 * 3 + 90)
}

@Test func encodingIsDeterministic() throws {
    let segments = QRSegment.segments(forURL: "https://hatband.link/#1MZXW6YTBOI")
    #expect(try QRCode.encode(segments, errorCorrection: .medium) == (try QRCode.encode(segments, errorCorrection: .medium)))
}

@Test(arguments: 1...40)
func everyVersionAndLevelEncodes(version: Int) throws {
    for level in levels {
        let code = try emptySymbol(version: version, level: level)
        #expect(code.size == 17 + 4 * version)
        #expect(code.modules.count == code.size * code.size)
    }
}

// MARK: - Capacity and version choice

@Test func knownCapacities() throws {
    func fits(_ segments: [QRSegment], _ version: Int, _ level: QRCode.ErrorCorrection) -> Bool {
        QRCode.smallestVersion(for: segments, errorCorrection: level) == version
    }
    #expect(fits([try .numeric(String(repeating: "1", count: 41))], 1, .low))
    #expect(fits([try .numeric(String(repeating: "1", count: 42))], 2, .low))
    #expect(fits([try .alphanumeric(String(repeating: "A", count: 25))], 1, .low))
    #expect(fits([try .alphanumeric(String(repeating: "A", count: 26))], 2, .low))
    #expect(fits([.bytes([UInt8](repeating: 0, count: 17))], 1, .low))
    #expect(fits([.bytes([UInt8](repeating: 0, count: 18))], 2, .low))
    #expect(fits([try .numeric(String(repeating: "1", count: 17))], 1, .high))
    #expect(fits([try .alphanumeric(String(repeating: "A", count: 10))], 1, .high))
    #expect(fits([.bytes([UInt8](repeating: 0, count: 7))], 1, .high))
    #expect(fits([.bytes([UInt8](repeating: 0, count: 2953))], 40, .low))
    #expect(QRCode.smallestVersion(for: [.bytes([UInt8](repeating: 0, count: 2954))], errorCorrection: .low) == nil)
    #expect(fits([try .numeric(String(repeating: "1", count: 7089))], 40, .low))
    #expect(fits([try .alphanumeric(String(repeating: "A", count: 4296))], 40, .low))
    #expect(fits([.bytes([UInt8](repeating: 0, count: 1273))], 40, .high))
    #expect(QRCode.smallestVersion(for: [], errorCorrection: .high) == 1)
}

@Test func compactTierFitsTheLockScreenBudget() {
    // 110 bytes of CBOR: prefix, format tag, Base32.
    let payload = (0..<110).map { UInt8(truncatingIfNeeded: $0 &* 53 &+ 1) }
    let url = "https://hatband.link/#1" + Base32.encode(payload)
    let segments = QRSegment.segments(forURL: url)
    #expect(segments.count == 2)
    #expect(segments[0].characterCount == 22)
    let version = QRCode.smallestVersion(for: segments, errorCorrection: .medium)
    #expect(version != nil && version! <= 10)
    #expect(version == 8)
    // A 110-byte URL: 22-byte prefix and 88 Base32 characters.
    let short = QRSegment.segments(forURL: "https://hatband.link/#" + String(Base32.encode(payload).prefix(88)))
    #expect(QRCode.smallestVersion(for: short, errorCorrection: .medium) == 5)
    // The split beats one byte segment.
    #expect(QRCode.smallestVersion(for: [.bytes(Array(url.utf8))], errorCorrection: .medium)! > version!)
}

@Test func versionRangeIsHonoured() throws {
    let segments = [QRSegment.bytes([UInt8](repeating: 0, count: 17))]
    #expect(try QRCode.encode(segments, errorCorrection: .low, minVersion: 3).version == 3)
    #expect(throws: QRError.dataTooLong) { try QRCode.encode(segments, errorCorrection: .medium, maxVersion: 1) }
    #expect(try QRCode.encode([], errorCorrection: .low, minVersion: 40).version == 40)
}

@Test func errors() {
    #expect(throws: QRError.invalidVersion) { try QRCode.encode([], errorCorrection: .low, minVersion: 0) }
    #expect(throws: QRError.invalidVersion) { try QRCode.encode([], errorCorrection: .low, maxVersion: 41) }
    #expect(throws: QRError.invalidVersion) { try QRCode.encode([], errorCorrection: .low, minVersion: 5, maxVersion: 4) }
    #expect(throws: QRError.invalidMask) { try QRCode.encode([], errorCorrection: .low, mask: 8) }
    #expect(throws: QRError.invalidMask) { try QRCode.encode([], errorCorrection: .low, mask: -1) }
    #expect(throws: QRError.dataTooLong) { try QRCode.encode([.bytes([UInt8](repeating: 0, count: 2954))], errorCorrection: .low) }
    #expect(throws: QRError.dataTooLong) { try QRCode.encode([.bytes([UInt8](repeating: 0, count: 1274))], errorCorrection: .high) }
    // A count that overflows its field at every allowed version.
    #expect(throws: QRError.dataTooLong) { try QRCode.encode([.bytes([UInt8](repeating: 0, count: 256))], errorCorrection: .low, maxVersion: 9) }
}

// MARK: - Renderers

private let tiny = QRCode(version: 1, errorCorrection: .low, mask: 0, size: 3, modules: bits("110 010 101"))

@Test func pathDataMergesRuns() {
    #expect(tiny.pathData(moduleSize: 4, quietZone: 4) == "M16 16h8v4h-8z" + "M20 20h4v4h-4z" + "M16 24h4v4h-4z" + "M24 24h4v4h-4z")
    #expect(tiny.pathData(moduleSize: 1, quietZone: 0) == "M0 0h2v1h-2zM1 1h1v1h-1zM0 2h1v1h-1zM2 2h1v1h-1z")
    #expect(tiny.pathData(moduleSize: 2.5, quietZone: 1) == "M2.5 2.5h5v2.5h-5zM5 5h2.5v2.5h-2.5zM2.5 7.5h2.5v2.5h-2.5zM7.5 7.5h2.5v2.5h-2.5z")
    let blank = QRCode(version: 1, errorCorrection: .low, mask: 0, size: 2, modules: [false, false, false, false])
    #expect(blank.pathData(moduleSize: 4, quietZone: 4) == "")
}

@Test func svgIsSelfContained() {
    let svg = tiny.svg(moduleSize: 4, quietZone: 4)
    #expect(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"44\" height=\"44\" viewBox=\"0 0 44 44\""))
    #expect(svg.contains("<rect width=\"44\" height=\"44\" fill=\"#ffffff\"/>"))
    #expect(svg.contains("<path d=\"M16 16h8v4h-8zM20 20h4v4h-4zM16 24h4v4h-4zM24 24h4v4h-4z\" fill=\"#000000\"/>"))
    #expect(svg.hasSuffix("</svg>"))
    #expect(!svg.contains("\n"))
    let styled = tiny.svg(moduleSize: 10, quietZone: 0, dark: "#0d0d0d", light: "#f2f2f2")
    #expect(styled.contains("width=\"30\""))
    #expect(styled.contains("fill=\"#f2f2f2\""))
    #expect(styled.contains("fill=\"#0d0d0d\""))
}

@Test func pbmIsPlainBitmap() {
    let pbm = tiny.pbm(scale: 1, quietZone: 0)
    #expect(pbm == "P1\n3 3\n110\n010\n101\n")
    let scaled = tiny.pbm(scale: 2, quietZone: 1)
    #expect(scaled == "P1\n10 10\n" + "0000000000\n0000000000\n0011110000\n0011110000\n0000110000\n0000110000\n0011001100\n0011001100\n0000000000\n0000000000\n")
}

@Test func debugDescriptionUsesHashes() {
    #expect(tiny.debugDescription == "####  \n  ##  \n##  ##\n")
}

@Test func renderersAgreeOnRealSymbol() throws {
    let code = try QRCode.encode(QRSegment.segments(forURL: "https://hatband.link/#1MZXW6YTBOI"), errorCorrection: .medium)
    let pbm = code.pbm(scale: 1, quietZone: 0).split(separator: "\n").dropFirst(2)
    #expect(pbm.count == code.size)
    for (y, row) in pbm.enumerated() {
        #expect(row.count == code.size)
        for (x, c) in row.enumerated() { #expect(code.module(x: x, y: y) == (c == "1")) }
    }
    // Every dark module is covered by exactly one path rectangle.
    let path = code.pathData(moduleSize: 1, quietZone: 0)
    var covered = 0
    for piece in path.split(separator: "M") {
        let parts = piece.split(whereSeparator: { "hvz ".contains($0) })
        let x = Int(parts[0])!, y = Int(parts[1])!, w = Int(parts[2])!
        for dx in 0..<w { #expect(code.module(x: x + dx, y: y)); covered += 1 }
        #expect(!code.module(x: x - 1, y: y))
        #expect(!code.module(x: x + w, y: y))
    }
    #expect(covered == code.modules.filter { $0 }.count)
}
