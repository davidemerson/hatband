import Foundation
import Testing
@testable import HatbandCore

/// Round trips through an independent decoder: render to a bitmap, run
/// `zbarimg --raw`, compare. The suite is skipped when zbar is not installed.
enum ZBar {
    /// `$ZBARIMG`, then the usual install locations, then `$PATH` through
    /// `/usr/bin/env` so a brew-installed zbar is found on the macOS runner.
    static let path: String? = {
        let fixed = ["/usr/bin/zbarimg", "/usr/local/bin/zbarimg", "/opt/homebrew/bin/zbarimg"]
        let candidates = (ProcessInfo.processInfo.environment["ZBARIMG"].map { [$0] } ?? []) + fixed
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? onPath("zbarimg")
    }()

    /// The first executable named `name` on `$PATH`, via `/usr/bin/env`.
    static func onPath(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sh", "-c", "command -v -- \"$1\"", "sh", name]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        let found = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return found.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: found) ? found : nil
    }

    static var available: Bool { path != nil }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func decode(_ code: QRCode, scale: Int = 4) throws -> String {
        guard let path else { throw Failure(description: "zbarimg is not installed") }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatband-qr-\(UUID().uuidString).pbm")
        try Data(code.pbm(scale: scale).utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--raw", "-q", "-Sdisable", "-Sqrcode.enable", file.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw Failure(description: "zbarimg failed with status \(process.terminationStatus) on version \(code.version)")
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }
}

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
private let alphanumericSet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")
private let base32Set = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

private func randomString(from set: [Character], count: Int, using rng: inout some RandomNumberGenerator) -> String {
    String((0..<count).map { _ in set.randomElement(using: &rng)! })
}

/// Printable ASCII, cycling, so the decoder's text conversion is the identity.
private func asciiText(count: Int) -> String {
    String((0..<count).map { Character(UnicodeScalar(UInt8(0x20 + $0 % 95))) })
}

/// The most bytes a byte segment can carry at a version and level.
private func byteCapacity(version: Int, level: QRCode.ErrorCorrection) -> Int {
    (QRCode.dataCapacity(version: version, errorCorrection: level) - 4 - QRSegment.Mode.byte.characterCountBits(version: version)) / 8
}

/// The `$PATH` lookup finds a tool every POSIX system has and nothing else.
@Test func pathLookupFindsExecutables() {
    let sh = ZBar.onPath("sh")
    #expect(sh?.hasPrefix("/") == true && FileManager.default.isExecutableFile(atPath: sh ?? ""))
    #expect(ZBar.onPath("hatband-no-such-tool") == nil)
    #expect(ZBar.onPath("") == nil)
}

@Suite("zbar round trips", .enabled(if: ZBar.available, "zbarimg is not installed"))
struct ZBarTests {
    @Test(arguments: levels)
    func numeric(level: QRCode.ErrorCorrection) throws {
        for text in ["01234567", String(repeating: "9", count: 41), "8675309", (0..<300).map { String($0 % 10) }.joined()] {
            let code = try QRCode.encode([try .numeric(text)], errorCorrection: level, boostErrorCorrection: false)
            #expect(code.errorCorrection == level)
            #expect(try ZBar.decode(code) == text)
        }
    }

    @Test(arguments: levels)
    func alphanumeric(level: QRCode.ErrorCorrection) throws {
        for text in ["HATBAND", "HELLO WORLD $%*+-./:", "A", String(repeating: "Z", count: 200)] {
            let code = try QRCode.encode([try .alphanumeric(text)], errorCorrection: level)
            #expect(try ZBar.decode(code) == text)
        }
    }

    @Test(arguments: levels)
    func bytes(level: QRCode.ErrorCorrection) throws {
        for text in ["https://hatband.link/#abc?x=1&y=2", "Leopold Bloom, 7 Eccles Street", asciiText(count: 95), "x"] {
            let code = try QRCode.encode([.bytes(Array(text.utf8))], errorCorrection: level)
            #expect(try ZBar.decode(code) == text)
        }
    }

    @Test func utf8Bytes() throws {
        let text = "Leopold Bloom — Henry Flower — Ulysses ü 水"
        let code = try QRCode.encode(QRSegment.optimal(for: text), errorCorrection: .medium)
        #expect(code.mask >= 0)
        #expect(try ZBar.decode(code) == text)
    }

    /// A byte payload sized to fill each version exactly, at every level.
    @Test(arguments: [1, 2, 5, 7, 10, 13, 20, 27, 40])
    func versions(version: Int) throws {
        for level in levels {
            let text = asciiText(count: byteCapacity(version: version, level: level))
            let code = try QRCode.encode([.bytes(Array(text.utf8))], errorCorrection: level, boostErrorCorrection: false)
            #expect(code.version == version, "\(version)-\(level)")
            #expect(code.errorCorrection == level)
            #expect(try ZBar.decode(code) == text, "\(version)-\(level)")
        }
    }

    @Test(arguments: levels)
    func mixedURL(level: QRCode.ErrorCorrection) throws {
        var rng = SplitMix(state: 0x4A11)
        let url = "https://hatband.link/#1" + randomString(from: base32Set, count: 300, using: &rng)
        let segments = QRSegment.segments(forURL: url)
        #expect(segments.map(\.mode) == [.byte, .alphanumeric])
        let code = try QRCode.encode(segments, errorCorrection: level)
        #expect(try ZBar.decode(code) == url)
        // The same text as one byte segment decodes identically, from a bigger symbol.
        let plain = try QRCode.encode([.bytes(Array(url.utf8))], errorCorrection: level)
        #expect(plain.version > code.version)
        #expect(try ZBar.decode(plain) == url)
    }

    @Test(arguments: 0..<8)
    func forcedMask(mask: Int) throws {
        let url = "https://hatband.link/#1MZXW6YTBOI2DENBUGA3DGNRVGYZTAMJSGE3DIMBSGIZTIMJUGQ2TMNRWG44DSOBZ"
        let code = try QRCode.encode(QRSegment.segments(forURL: url), errorCorrection: .medium, mask: mask)
        #expect(code.mask == mask)
        #expect(try ZBar.decode(code) == url)
    }

    @Test func lockScreenSizedSymbolAtSmallScale() throws {
        let payload = (0..<110).map { UInt8(truncatingIfNeeded: $0 &* 53 &+ 1) }
        let url = "https://hatband.link/#1" + Base32.encode(payload)
        let code = try QRCode.encode(QRSegment.segments(forURL: url), errorCorrection: .medium)
        #expect(code.version <= 10)
        #expect(try ZBar.decode(code, scale: 2) == url)
        #expect(try ZBar.decode(code, scale: 3) == url)
    }

    @Test func emptyAndTinySegments() throws {
        let code = try QRCode.encode([.bytes([UInt8(ascii: "7")])], errorCorrection: .high)
        #expect(try ZBar.decode(code) == "7")
        let multi = try QRCode.encode([try .numeric("42"), try .alphanumeric("AB"), .bytes(Array("c".utf8)), try .numeric("1")], errorCorrection: .low)
        #expect(try ZBar.decode(multi) == "42ABc1")
    }

    /// Random alphanumeric text of random length at a random level.
    @Test(arguments: 0..<300)
    func randomAlphanumeric(seed: Int) throws {
        var rng = SplitMix(state: 0xB100_0000 &+ UInt64(seed))
        let length = Int.random(in: 1...250, using: &rng)
        let text = randomString(from: alphanumericSet, count: length, using: &rng)
        let level = levels.randomElement(using: &rng)!
        let code = try QRCode.encode([try .alphanumeric(text)], errorCorrection: level)
        #expect(try ZBar.decode(code) == text, "seed \(seed): \(text) at \(level)")
    }
}
