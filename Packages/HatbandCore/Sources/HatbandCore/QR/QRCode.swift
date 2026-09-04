/// A QR Code symbol (ISO/IEC 18004, model 2, versions 1–40) as a matrix of
/// modules. Encoding follows the standard step by step: segments to data
/// codewords, Reed–Solomon blocks interleaved, function patterns, zigzag
/// placement, the mask with the lowest penalty, format and version bits.
public struct QRCode: Sendable, Equatable {
    public enum ErrorCorrection: Sendable, CaseIterable, Equatable {
        case low
        case medium
        case quartile
        case high

        /// Two-bit indicator in the format information, Table 12.
        var formatBits: Int {
            switch self {
            case .low: 1
            case .medium: 0
            case .quartile: 3
            case .high: 2
            }
        }

        /// Row in the block tables.
        var index: Int {
            switch self {
            case .low: 0
            case .medium: 1
            case .quartile: 2
            case .high: 3
            }
        }
    }

    public let version: Int
    public let errorCorrection: ErrorCorrection
    /// Mask pattern reference 0–7.
    public let mask: Int
    /// Modules per side, `17 + 4 * version`.
    public let size: Int
    /// Row-major, `size * size`; true is dark.
    public let modules: [Bool]

    /// Dark or not; anything outside the symbol is light.
    public func module(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < size, y < size else { return false }
        return modules[y * size + x]
    }
}

public enum QRError: Error, Equatable, Sendable {
    case dataTooLong
    case invalidCharacter
    case invalidVersion
    case invalidMask
}

// MARK: - Encoding

extension QRCode {
    public static let minVersion = 1
    public static let maxVersion = 40

    /// The smallest version in range that holds the segments at the requested
    /// level. With `boostErrorCorrection` the level then rises as far as that
    /// version allows without growing. A forced `mask` skips penalty scoring.
    public static func encode(
        _ segments: [QRSegment],
        errorCorrection: ErrorCorrection,
        minVersion: Int = QRCode.minVersion,
        maxVersion: Int = QRCode.maxVersion,
        boostErrorCorrection: Bool = true,
        mask: Int? = nil
    ) throws -> QRCode {
        guard QRCode.minVersion <= minVersion, minVersion <= maxVersion, maxVersion <= QRCode.maxVersion else {
            throw QRError.invalidVersion
        }
        if let mask, !(0...7).contains(mask) { throw QRError.invalidMask }
        guard let version = smallestVersion(for: segments, errorCorrection: errorCorrection, in: minVersion...maxVersion),
              let used = QRSegment.totalBits(segments, version: version)
        else { throw QRError.dataTooLong }

        var level = errorCorrection
        if boostErrorCorrection {
            // The level spending the most codewords on error correction that
            // still holds the data, chosen by capacity rather than case order;
            // the requested level always qualifies.
            func capacity(_ level: ErrorCorrection) -> Int { dataCapacity(version: version, errorCorrection: level) }
            level = ErrorCorrection.allCases.filter { used <= capacity($0) }.min { capacity($0) < capacity($1) } ?? level
        }

        let data = dataCodewords(segments, version: version, errorCorrection: level)
        var matrix = Matrix(version: version)
        matrix.drawFunctionPatterns()
        matrix.drawCodewords(interleave(data, version: version, errorCorrection: level))
        let chosen = mask ?? matrix.bestMask(errorCorrection: level)
        matrix.applyMask(chosen)
        matrix.drawFormatBits(errorCorrection: level, mask: chosen)
        return QRCode(version: version, errorCorrection: level, mask: chosen, size: matrix.size, modules: matrix.modules)
    }

    /// Data bits available at a version and level: data codewords × 8, or 0
    /// outside versions 1–40.
    public static func dataCapacity(version: Int, errorCorrection: ErrorCorrection) -> Int {
        guard (minVersion...maxVersion).contains(version) else { return 0 }
        return dataCodewordCount(version: version, errorCorrection: errorCorrection) * 8
    }

    /// The smallest version 1–40 whose capacity at the level holds the segments.
    public static func smallestVersion(for segments: [QRSegment], errorCorrection: ErrorCorrection) -> Int? {
        smallestVersion(for: segments, errorCorrection: errorCorrection, in: minVersion...maxVersion)
    }

    static func smallestVersion(
        for segments: [QRSegment], errorCorrection: ErrorCorrection, in range: ClosedRange<Int>
    ) -> Int? {
        range.first { version in
            guard let used = QRSegment.totalBits(segments, version: version) else { return false }
            return used <= dataCapacity(version: version, errorCorrection: errorCorrection)
        }
    }

    /// Segments with indicators and counts, a terminator of up to four zero
    /// bits, zero bits to a byte boundary, then pad codewords EC 11 (§7.4.10).
    static func dataCodewords(_ segments: [QRSegment], version: Int, errorCorrection: ErrorCorrection) -> [UInt8] {
        let capacity = dataCapacity(version: version, errorCorrection: errorCorrection)
        var buffer = BitBuffer()
        for segment in segments {
            buffer.append(segment.mode.indicator, count: 4)
            buffer.append(segment.characterCount, count: segment.mode.characterCountBits(version: version))
            buffer.append(contentsOf: segment.bits)
        }
        precondition(buffer.count <= capacity, "segments exceed the version's capacity")
        buffer.append(0, count: min(4, capacity - buffer.count))
        buffer.append(0, count: (8 - buffer.count % 8) % 8)
        var pad = 0xEC
        while buffer.count < capacity {
            buffer.append(pad, count: 8)
            pad ^= 0xEC ^ 0x11
        }
        return buffer.bytes
    }

    /// Splits data codewords into the version's blocks, appends each block's
    /// error correction, and interleaves data then EC codeword by codeword
    /// (§7.6). Longer blocks come last, so the tail has fewer contributors.
    static func interleave(_ data: [UInt8], version: Int, errorCorrection: ErrorCorrection) -> [UInt8] {
        let blockCount = blockCounts[errorCorrection.index][version]
        let eccLength = eccCodewordsPerBlock[errorCorrection.index][version]
        let total = totalCodewords(version: version)
        let shortBlocks = blockCount - total % blockCount
        let shortLength = total / blockCount - eccLength
        let generator = ReedSolomon.generator(degree: eccLength)

        var blocks: [[UInt8]] = []
        var ecc: [[UInt8]] = []
        var offset = 0
        for i in 0..<blockCount {
            let length = shortLength + (i < shortBlocks ? 0 : 1)
            let block = Array(data[offset..<offset + length])
            offset += length
            blocks.append(block)
            ecc.append(ReedSolomon.remainder(of: block, generator: generator))
        }
        precondition(offset == data.count, "data codeword count does not match the version")

        var out: [UInt8] = []
        out.reserveCapacity(total)
        for i in 0...shortLength {
            for block in blocks where i < block.count { out.append(block[i]) }
        }
        for i in 0..<eccLength {
            for block in ecc { out.append(block[i]) }
        }
        return out
    }
}

// MARK: - Tables

extension QRCode {
    /// Codewords in the symbol: data modules minus function patterns, over 8.
    static func totalCodewords(version: Int) -> Int {
        precondition((minVersion...maxVersion).contains(version), "version out of range")
        var modules = (16 * version + 128) * version + 64
        if version >= 2 {
            let align = version / 7 + 2
            modules -= (25 * align - 10) * align - 55
            if version >= 7 { modules -= 36 }
        }
        return modules / 8
    }

    static func dataCodewordCount(version: Int, errorCorrection: ErrorCorrection) -> Int {
        totalCodewords(version: version)
            - eccCodewordsPerBlock[errorCorrection.index][version] * blockCounts[errorCorrection.index][version]
    }

    /// Table 9, by level then version; index 0 is unused.
    static let eccCodewordsPerBlock: [[Int]] = [
        [0, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
        [0, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [0, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    ]

    /// Table 9, number of error correction blocks; index 0 is unused.
    static let blockCounts: [[Int]] = [
        [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
        [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
        [0, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
        [0, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
    ]

    /// Centre coordinates of alignment patterns along one axis (Annex E).
    /// Evenly spaced from 6 to `size - 7`, rounded to even; version 32 is the
    /// one exception the table makes.
    static func alignmentPositions(version: Int) -> [Int] {
        guard version >= 2 else { return [] }
        let count = version / 7 + 2
        let step = version == 32 ? 26 : (version * 4 + count * 2 + 1) / (count * 2 - 2) * 2
        var positions = [6]
        let last = version * 4 + 10
        for i in stride(from: count - 2, through: 0, by: -1) {
            positions.append(last - i * step)
        }
        return positions
    }

    /// Fifteen bits: level and mask, BCH(15,5) remainder, XOR 0x5412 (Annex C).
    static func formatBits(errorCorrection: ErrorCorrection, mask: Int) -> Int {
        let data = errorCorrection.formatBits << 3 | mask
        var remainder = data
        for _ in 0..<10 {
            remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
        }
        return (data << 10 | remainder) ^ 0x5412
    }

    /// Eighteen bits: the version and its BCH(18,6) remainder (Annex D).
    static func versionBits(version: Int) -> Int {
        var remainder = version
        for _ in 0..<12 {
            remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
        }
        return version << 12 | remainder
    }

    /// Mask condition for a module, Table 10; true means invert.
    static func maskBit(_ mask: Int, x: Int, y: Int) -> Bool {
        switch mask {
        case 0: (x + y) % 2 == 0
        case 1: y % 2 == 0
        case 2: x % 3 == 0
        case 3: (x + y) % 3 == 0
        case 4: (x / 3 + y / 2) % 2 == 0
        case 5: x * y % 2 + x * y % 3 == 0
        case 6: (x * y % 2 + x * y % 3) % 2 == 0
        case 7: ((x + y) % 2 + x * y % 3) % 2 == 0
        default: preconditionFailure("mask out of range")
        }
    }
}

// MARK: - Matrix

/// The symbol under construction. Function modules are fixed by the version
/// and level; everything else is data and gets masked.
struct Matrix {
    let version: Int
    let size: Int
    var modules: [Bool]
    var isFunction: [Bool]

    init(version: Int) {
        self.version = version
        size = 17 + 4 * version
        modules = [Bool](repeating: false, count: size * size)
        isFunction = modules
    }

    subscript(x: Int, y: Int) -> Bool {
        get { modules[y * size + x] }
        set { modules[y * size + x] = newValue }
    }

    mutating func setFunction(_ x: Int, _ y: Int, _ dark: Bool) {
        self[x, y] = dark
        isFunction[y * size + x] = true
    }

    /// Timing, finders with separators, alignment, format placeholder, version.
    mutating func drawFunctionPatterns() {
        for i in 0..<size {
            setFunction(6, i, i % 2 == 0)
            setFunction(i, 6, i % 2 == 0)
        }
        drawFinder(x: 3, y: 3)
        drawFinder(x: size - 4, y: 3)
        drawFinder(x: 3, y: size - 4)
        let positions = QRCode.alignmentPositions(version: version)
        let last = positions.count - 1
        for (i, y) in positions.enumerated() {
            for (j, x) in positions.enumerated() {
                let underFinder = (i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0)
                if !underFinder { drawAlignment(x: x, y: y) }
            }
        }
        drawFormatBits(errorCorrection: .low, mask: 0)
        drawVersionBits()
    }

    /// 7×7 finder with its one-module light separator, clipped to the symbol.
    private mutating func drawFinder(x: Int, y: Int) {
        for dy in -4...4 {
            for dx in -4...4 {
                let xx = x + dx, yy = y + dy
                guard (0..<size).contains(xx), (0..<size).contains(yy) else { continue }
                let ring = max(abs(dx), abs(dy))
                setFunction(xx, yy, ring != 2 && ring != 4)
            }
        }
    }

    private mutating func drawAlignment(x: Int, y: Int) {
        for dy in -2...2 {
            for dx in -2...2 {
                setFunction(x + dx, y + dy, max(abs(dx), abs(dy)) != 1)
            }
        }
    }

    /// Both copies of the format information plus the dark module (§7.9).
    mutating func drawFormatBits(errorCorrection: QRCode.ErrorCorrection, mask: Int) {
        let bits = QRCode.formatBits(errorCorrection: errorCorrection, mask: mask)
        func bit(_ i: Int) -> Bool { (bits >> i) & 1 == 1 }
        for i in 0...5 { setFunction(8, i, bit(i)) }
        setFunction(8, 7, bit(6))
        setFunction(8, 8, bit(7))
        setFunction(7, 8, bit(8))
        for i in 9..<15 { setFunction(14 - i, 8, bit(i)) }
        for i in 0..<8 { setFunction(size - 1 - i, 8, bit(i)) }
        for i in 8..<15 { setFunction(8, size - 15 + i, bit(i)) }
        setFunction(8, size - 8, true)
    }

    /// Two 6×3 blocks beside the top-right and bottom-left finders (§7.10).
    private mutating func drawVersionBits() {
        guard version >= 7 else { return }
        let bits = QRCode.versionBits(version: version)
        for i in 0..<18 {
            let bit = (bits >> i) & 1 == 1
            let a = size - 11 + i % 3, b = i / 3
            setFunction(a, b, bit)
            setFunction(b, a, bit)
        }
    }

    /// Codewords in two-module columns snaking up and down from the right,
    /// skipping function modules and the vertical timing column (§7.7.3).
    mutating func drawCodewords(_ codewords: [UInt8]) {
        precondition(codewords.count == QRCode.totalCodewords(version: version), "codeword count does not match the version")
        var i = 0
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }
            for vertical in 0..<size {
                for j in 0..<2 {
                    let x = right - j
                    let upward = (right + 1) & 2 == 0
                    let y = upward ? size - 1 - vertical : vertical
                    if !isFunction[y * size + x], i < codewords.count * 8 {
                        self[x, y] = (codewords[i >> 3] >> (7 - i & 7)) & 1 == 1
                        i += 1
                    }
                }
            }
            right -= 2
        }
        // Any remainder bits stay light.
    }

    /// XORs the pattern into the data modules; applying it twice undoes it.
    mutating func applyMask(_ mask: Int) {
        for y in 0..<size {
            for x in 0..<size where !isFunction[y * size + x] && QRCode.maskBit(mask, x: x, y: y) {
                self[x, y].toggle()
            }
        }
    }

    /// Tries all eight masks in place and returns the lowest penalty, ties to
    /// the lower number. Leaves the matrix unmasked.
    mutating func bestMask(errorCorrection: QRCode.ErrorCorrection) -> Int {
        var best = 0
        var lowest = Int.max
        for mask in 0..<8 {
            applyMask(mask)
            drawFormatBits(errorCorrection: errorCorrection, mask: mask)
            let score = penalty()
            if score < lowest {
                lowest = score
                best = mask
            }
            applyMask(mask)
        }
        return best
    }

    /// The four penalty rules of §7.8.3 with N1 = 3, N2 = 3, N3 = 40, N4 = 10.
    func penalty() -> Int {
        var result = 0
        var line = [Bool](repeating: false, count: size)
        for i in 0..<size {
            for x in 0..<size { line[x] = self[x, i] }
            result += Matrix.linePenalty(line)
            for y in 0..<size { line[y] = self[i, y] }
            result += Matrix.linePenalty(line)
        }
        for y in 0..<size - 1 {
            for x in 0..<size - 1 {
                let c = self[x, y]
                if c == self[x + 1, y], c == self[x, y + 1], c == self[x + 1, y + 1] { result += 3 }
            }
        }
        let dark = modules.reduce(0) { $0 + ($1 ? 1 : 0) }
        let total = size * size
        // Deviation from 50% in 5% steps, rounded up, less one.
        let deviation = abs(dark * 20 - total * 10)
        result += max(0, (deviation + total - 1) / total - 1) * 10
        return result
    }

    /// N1: each run of five or more, 3 plus one per extra module. N3: each
    /// finder-like run pattern dark n, light n, dark 3n, light n, dark n with
    /// at least 4n light modules on one side and n on the other, 40 per such
    /// side; the quiet zone beyond either end counts as a light run as long as
    /// the line. Nayuki's run-length scan, which libqrencode agrees with.
    static func linePenalty(_ line: [Bool]) -> Int {
        let border = line.count
        var result = 0
        var runColor = false
        var runLength = 0
        // The last seven runs, most recent first; [0] is light when counted.
        var history = [Int](repeating: 0, count: 7)
        func addHistory(_ length: Int) {
            var length = length
            if history[0] == 0 { length += border }
            for i in stride(from: 6, to: 0, by: -1) { history[i] = history[i - 1] }
            history[0] = length
        }
        func countPatterns() -> Int {
            let n = history[1]
            let core = n > 0 && history[2] == n && history[3] == 3 * n && history[4] == n && history[5] == n
            return (core && history[0] >= 4 * n && history[6] >= n ? 1 : 0)
                + (core && history[6] >= 4 * n && history[0] >= n ? 1 : 0)
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
        if runColor {
            addHistory(runLength)
            runLength = 0
        }
        addHistory(runLength + border)
        return result + countPatterns() * 40
    }
}
