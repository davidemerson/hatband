import Foundation
import Testing
@testable import HatbandCore

/// Review of the QR hardening: the penalty scan checked against the rule
/// written out longhand rather than against another run-history scan, and
/// the guarded inputs pushed further than the fix's own tests do.

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

private let levels = QRCode.ErrorCorrection.allCases

// MARK: - N1 and N3 from the rule as written

private struct Run { let dark: Bool; let length: Int }

private func runs(_ line: [Bool]) -> [Run] {
    var out: [Run] = []
    var i = 0
    while i < line.count {
        var j = i
        while j < line.count, line[j] == line[i] { j += 1 }
        out.append(Run(dark: line[i], length: j - i))
        i = j
    }
    return out
}

/// N1: three for a run of five plus one per extra module.
private func ruleN1(_ line: [Bool]) -> Int {
    runs(line).reduce(0) { $0 + ($1.length >= 5 ? $1.length - 2 : 0) }
}

/// N3 longhand: every dark, light, dark, light, dark run sequence of lengths
/// n, n, 3n, n, n scores 40 for each side with at least 4n light modules
/// while the other side has at least n. A light run touching the edge of
/// the line borders the quiet zone, which is wider than any n can ask for.
private func ruleN3(_ line: [Bool]) -> Int {
    let r = runs(line)
    var score = 0
    for i in r.indices where r[i].dark && i + 4 < r.count {
        let n = r[i].length
        guard r[i + 1].length == n, r[i + 2].length == 3 * n, r[i + 3].length == n, r[i + 4].length == n else { continue }
        let before = i <= 1 ? Int.max : r[i - 1].length
        let after = i + 5 >= r.count - 1 ? Int.max : r[i + 5].length
        if before >= 4 * n && after >= n { score += 40 }
        if after >= 4 * n && before >= n { score += 40 }
    }
    return score
}

private func bits(_ s: String) -> [Bool] {
    s.compactMap { $0 == "1" ? true : $0 == "0" ? false : nil }
}

/// Every line up to sixteen modules: the scan and the longhand rule agree.
@Test func linePenaltyMatchesTheRuleExhaustivelyOnShortLines() {
    for length in 0...16 {
        for pattern in 0..<(1 << length) {
            let line = (0..<length).map { pattern >> $0 & 1 == 1 }
            let expected = ruleN1(line) + ruleN3(line)
            let actual = Matrix.linePenalty(line)
            if actual != expected {
                Issue.record("\(line.map { $0 ? "1" : "0" }.joined()): \(actual) vs \(expected)")
                return
            }
        }
    }
}

/// Random lines up to the largest symbol's width, biased toward long runs
/// so scaled patterns occur.
@Test func linePenaltyMatchesTheRuleOnRandomLongLines() {
    var rng = SplitMix(state: 0x5EED)
    for _ in 0..<4000 {
        let length = Int.random(in: 1...177, using: &rng)
        var line: [Bool] = []
        var dark = Bool.random(using: &rng)
        while line.count < length {
            let n = Int.random(in: 1...9, using: &rng)
            line += [Bool](repeating: dark, count: min(n, length - line.count))
            dark.toggle()
        }
        let expected = ruleN1(line) + ruleN3(line)
        #expect(Matrix.linePenalty(line) == expected, "\(line.map { $0 ? "1" : "0" }.joined())")
    }
}

/// Scaled patterns pinned by hand, including ones that fill the whole line
/// and ones where the far side has n − 1 light modules.
@Test func scaledFinderPatternsScoreAsTheRuleSays() {
    let cases: [(String, Int)] = [
        // 3:3:9:3:3 filling the line: both edges are quiet zone, plus N1 for the run of nine.
        ("111000111111111000111", 87),
        // 4:4:12:4:4 with sixteen lights before it and three after: three is one short of n.
        ("0000000000000000" + "1111000011111111111100001111" + "000" + "1", 0 + 14 + 10),
        // The same with four after: one side.
        ("0000000000000000" + "1111000011111111111100001111" + "0000" + "1", 40 + 14 + 10),
        // Two unit patterns sharing one light module between them.
        ("0000" + "1011101" + "0" + "1011101" + "0000", 80),
        // A pattern whose leading dark run touches a longer dark run through no light: 1:1:3:1:1 must start after a light run.
        ("11" + "1011101" + "0000000", 0 + 5),
    ]
    for (line, expected) in cases {
        #expect(Matrix.linePenalty(bits(line)) == expected, "\(line)")
        #expect(ruleN1(bits(line)) + ruleN3(bits(line)) == expected, "\(line)")
    }
}

/// The scan is called on rows and columns alike; the whole-symbol penalty
/// equals the longhand rule summed over both plus N2 and N4.
@Test func symbolPenaltyMatchesTheRuleOnEncodedSymbols() throws {
    var rng = SplitMix(state: 0xC0FFEE)
    for _ in 0..<12 {
        let length = Int.random(in: 10...300, using: &rng)
        let text = String((0..<length).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".randomElement(using: &rng)! })
        let code = try QRCode.encode([try .alphanumeric(text)], errorCorrection: levels.randomElement(using: &rng)!, mask: Int.random(in: 0..<8, using: &rng))
        var expected = 0
        for i in 0..<code.size {
            let row = (0..<code.size).map { code.module(x: $0, y: i) }
            let column = (0..<code.size).map { code.module(x: i, y: $0) }
            expected += ruleN1(row) + ruleN3(row) + ruleN1(column) + ruleN3(column)
        }
        for y in 0..<(code.size - 1) {
            for x in 0..<(code.size - 1) {
                let c = code.module(x: x, y: y)
                if c == code.module(x: x + 1, y: y), c == code.module(x: x, y: y + 1), c == code.module(x: x + 1, y: y + 1) { expected += 3 }
            }
        }
        let dark = code.modules.filter { $0 }.count
        let total = code.size * code.size
        expected += ((abs(dark * 20 - total * 10) + total - 1) / total - 1) * 10
        var matrix = Matrix(version: code.version)
        matrix.modules = code.modules
        #expect(matrix.penalty() == expected)
    }
}

// MARK: - Colours

/// Accepted means exactly `#` and three or six ASCII hex digits, judged by
/// Character rather than by the byte check under test; everything else
/// renders the default document.
@Test func svgColourAcceptanceIsExactlyAsciiHex() throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    let plain = code.svg()
    let hexDigits: [Character] = Array("0123456789abcdefABCDEF")
    let poison: [Character] = ["#", "g", "G", "\"", "'", "<", ">", " ", "\n", "\0", "\u{FEFF}", "ｆ", "\u{301}", "-", "+", ";", "&", "０"]
    var rng = SplitMix(state: 0xC010)
    var accepted = 0
    for _ in 0..<3000 {
        let length = Int.random(in: 0...8, using: &rng)
        var s = String((0..<length).map { _ in
            Int.random(in: 0..<10, using: &rng) < 8 ? hexDigits.randomElement(using: &rng)! : poison.randomElement(using: &rng)!
        })
        if Int.random(in: 0..<10, using: &rng) < 8 { s = "#" + s }
        let hex = (s.count == 4 || s.count == 7) && s.first == "#" && s.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit }
        let svg = code.svg(dark: s, light: s)
        if hex {
            accepted += 1
            #expect(svg != plain && svg.contains("fill=\"\(s)\""), "\(s.debugDescription)")
        } else {
            #expect(svg == plain, "\(s.debugDescription)")
        }
        // Whatever went in, the document has exactly two fill attributes, both hex.
        let fills = svg.components(separatedBy: "fill=\"").dropFirst().map { $0.prefix { $0 != "\"" } }
        #expect(fills.count == 2 && fills.allSatisfy { $0.first == "#" && $0.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit } }, "\(s.debugDescription)")
    }
    #expect(accepted > 20)
}

@Test(arguments: [
    "\u{FEFF}#abc", "#abc\u{FEFF}", "#abc\0", "#abcdef\0", "\0#abc", "##abcd", "#abc#ef", "#+12345", "#-12345", "#１２３",
    "#abc\r", "\t#abc", "#ab c", "#abcdef ", "#ABCDEF\u{200B}", "#e\u{301}bc", "＃abc", "#abcdefabc",
])
func svgRejectsNearMissColours(colour: String) throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    #expect(QRCode.hexColour(colour) == nil)
    #expect(code.svg(dark: colour) == code.svg() && code.svg(light: colour) == code.svg())
}

@Test(arguments: ["#1e2345", "#E1F", "#000", "#FFF", "#deadBE", "#0f0F0f"])
func svgAcceptsHexColoursVerbatim(colour: String) throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    #expect(QRCode.hexColour(colour) == colour)
    #expect(code.svg(dark: colour).contains("<path d=\"M") && code.svg(dark: colour).hasSuffix("fill=\"\(colour)\"/></svg>"))
    #expect(code.svg(light: colour).contains("<rect width=\"116\" height=\"116\" fill=\"\(colour)\"/>"))
}

// MARK: - Sizes

/// Whatever Double goes in, path data is made of the path letters, digits,
/// signs, points and exponents only: never a quote or a tag.
@Test(arguments: [0, -1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNonzeroMagnitude, 1e300, 1e-300, 0.1, 1.5, 1e15, 1e16] as [Double])
func pathDataStaysWithinPathCharacters(moduleSize: Double) throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    let allowed = Set("Mhvz 0123456789.-+einfa")
    for quietZone in [Int.min, -1, 0, 4, Int.max / 4] {
        let path = code.pathData(moduleSize: moduleSize, quietZone: quietZone)
        #expect(path.hasPrefix("M") && path.hasSuffix("z") && path.allSatisfy { allowed.contains($0) }, "\(moduleSize) \(quietZone)")
    }
}

/// The clamped size is what the header advertises, and the pixel rows agree.
@Test func degenerateRenderSizesProduceConsistentDocuments() throws {
    let code = try QRCode.encode([try .alphanumeric("HATBAND")], errorCorrection: .medium)
    for (scale, quiet) in [(0, 0), (-1, -1), (Int.min, Int.min), (0, 2), (3, -9)] {
        let side = code.size + 2 * max(quiet, 0)
        let expectedSide = side * max(scale, 1)
        let pbm = code.pbm(scale: scale, quietZone: quiet)
        let lines = pbm.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "P1" && lines[1] == "\(expectedSide) \(expectedSide)")
        #expect(lines.dropFirst(2).dropLast().count == expectedSide && lines.dropFirst(2).dropLast().allSatisfy { $0.count == expectedSide })
        let svg = code.svg(moduleSize: scale, quietZone: quiet)
        #expect(svg.contains("width=\"\(expectedSide)\" height=\"\(expectedSide)\" viewBox=\"0 0 \(expectedSide) \(expectedSide)\""))
    }
}

/// In range the capacity is positive and whole codewords; out of range it is
/// zero at both edges and does not trap on extreme versions.
@Test func dataCapacityEdges() {
    for level in levels {
        #expect(QRCode.dataCapacity(version: 1, errorCorrection: level) > 0)
        #expect(QRCode.dataCapacity(version: 40, errorCorrection: level) % 8 == 0)
        #expect(QRCode.dataCapacity(version: 0, errorCorrection: level) == 0)
        #expect(QRCode.dataCapacity(version: 41, errorCorrection: level) == 0)
        #expect(QRCode.dataCapacity(version: Int.min + 1, errorCorrection: level) == 0)
    }
    #expect(QRCode.dataCapacity(version: 1, errorCorrection: .low) == 19 * 8)
    #expect(QRCode.dataCapacity(version: 40, errorCorrection: .high) == 1276 * 8)
}

// MARK: - Boost by capacity

/// The boosted level is the fitting level of least capacity, stated in
/// capacities alone; with boosting off the level is exactly what was asked.
@Test func boostIsTheLeastFittingCapacity() throws {
    var rng = SplitMix(state: 0xB0057)
    for _ in 0..<40 {
        let segments = [QRSegment.bytes((0..<Int.random(in: 1...300, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })]
        let asked = levels.randomElement(using: &rng)!
        let plain = try QRCode.encode(segments, errorCorrection: asked, boostErrorCorrection: false)
        #expect(plain.errorCorrection == asked)
        let boosted = try QRCode.encode(segments, errorCorrection: asked)
        let used = QRSegment.totalBits(segments, version: boosted.version)!
        func capacity(_ level: QRCode.ErrorCorrection) -> Int { QRCode.dataCapacity(version: boosted.version, errorCorrection: level) }
        let least = levels.filter { used <= capacity($0) }.map(capacity).min()!
        #expect(capacity(boosted.errorCorrection) == least)
        #expect(capacity(boosted.errorCorrection) <= capacity(asked))
    }
}

// MARK: - Reed–Solomon at the low end

/// Degree one: the generator is x + 1, so the remainder is the data
/// evaluated at 1, the XOR of the bytes. Pins that the degree-0 guard did
/// not move the boundary.
@Test func degreeOneRemainderIsTheXorOfTheData() {
    let g = ReedSolomon.generator(degree: 1)
    #expect(g == [1, 1])
    var rng = SplitMix(state: 0x2501)
    for _ in 0..<50 {
        let data = (0..<Int.random(in: 0...60, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
        #expect(ReedSolomon.remainder(of: data, generator: g) == [data.reduce(0, ^)])
    }
    #expect(ReedSolomon.remainder(of: [7], generator: [1]) == [])
    #expect(ReedSolomon.remainder(of: [7], generator: [9]) == [])
}

// MARK: - Tool lookup

/// The name reaches `command -v` as one argument: shell syntax in it finds
/// nothing and runs nothing, and a path is returned only when executable.
@Test func pathLookupDoesNotInterpretTheName() throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("hatband-onpath-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    for name in [
        "$(touch \(marker.path))", "`touch \(marker.path)`", "; touch \(marker.path)", "sh; touch \(marker.path)",
        "sh\ntouch \(marker.path)", "sh && touch \(marker.path)", "\"; touch \(marker.path); \"", "sh -c 'touch \(marker.path)'",
        "-v", "--", "-", ".", "..", "/dev/null", "/etc/passwd", marker.path,
    ] {
        #expect(ZBar.onPath(name) == nil, "\(name)")
    }
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(ZBar.onPath("/bin/sh") == "/bin/sh")
    #expect(ZBar.onPath("sh")?.hasSuffix("/sh") == true)
}
