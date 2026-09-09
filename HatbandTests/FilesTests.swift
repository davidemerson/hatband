import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Hatband

struct FilesTests {
    @Test func utTypesResolve() {
        #expect(UTType.hatbandCard.identifier == "link.hatband.card")
        #expect(UTType.hatbandCard.preferredFilenameExtension == "hatband")
        #expect(UTType.hatbandExport.identifier == "link.hatband.export")
        #expect(UTType.hatbandExport.preferredFilenameExtension == "hatband-export")
    }

    @Test func writtenFileCarriesBytesAndProtection() throws {
        let bytes: [UInt8] = [0x48, 0x42, 0x31, 0x00, 1, 2, 3]
        let url = try TransferredFiles.write(bytes, name: "card.hatband")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(url.lastPathComponent == "card.hatband")
        #expect(Array(try Data(contentsOf: url)) == bytes)
        // The simulator may not report a protection class; where it does, it
        // must be the hand-off class. `.complete` reads as nothing to the
        // process on the other side of the share sheet.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attributes[.protectionKey]
        if let raw = (protection as? FileProtectionType)?.rawValue ?? (protection as? String) {
            #expect(raw == FileProtectionType.completeUnlessOpen.rawValue)
        }
    }

    /// The bug Signal reported: a second write, which is what a thumbnail or a
    /// second `ShareLink` on the same screen provokes, used to delete the file
    /// the first one had already handed out.
    @Test func writingAgainLeavesTheEarlierFileAlone() throws {
        let first = try TransferredFiles.write([1, 2, 3], name: "first.png")
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        let second = try TransferredFiles.write([4, 5, 6], name: "second.png")
        defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
        #expect(Array(try Data(contentsOf: first)) == [1, 2, 3], "the first share's file was swept mid-flight")
        #expect(Array(try Data(contentsOf: second)) == [4, 5, 6])
    }

    @Test func transferablesKeepTheirBytes() {
        let card = CardFile(bytes: [1, 2], name: "a.hatband")
        #expect(card.bytes == [1, 2])
        #expect(card.name == "a.hatband")
        let export = ExportFile(bytes: [3], name: "b.hatband-export")
        #expect(export.bytes == [3])
        #expect(VCardFile(bytes: [], name: "c.vcf").name == "c.vcf")
        #expect(PNGFile(bytes: [], name: "d.png").name == "d.png")
        #expect(PDFFile(bytes: [], name: "e.pdf").name == "e.pdf")
        #expect(SVGFile(bytes: [], name: "f.svg").name == "f.svg")
    }
}

@Test func sweepRemovesEarlierTransfersAndSparesRecentOnes() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let now = Date()
    func directory(_ name: String) throws -> URL {
        let url = temporary.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    let stamp = { (age: TimeInterval) in String(Int((now.timeIntervalSinceReferenceDate - age).rounded())) }
    let stale = try directory(TransferredFiles.prefix + stamp(TransferredFiles.grace + 60) + "-" + UUID().uuidString)
    let fresh = try directory(TransferredFiles.prefix + stamp(5) + "-" + UUID().uuidString)
    // A directory from a build that wrote no stamp is from an earlier launch.
    let unstamped = try directory(TransferredFiles.prefix + "old")
    let other = try directory("keep")
    TransferredFiles.sweep(in: temporary, now: now)
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: fresh.path), "swept a share that may still be in flight")
    #expect(!FileManager.default.fileExists(atPath: unstamped.path))
    #expect(FileManager.default.fileExists(atPath: other.path))
    // Erase takes everything, however new.
    TransferredFiles.sweep(in: temporary, olderThan: 0, now: now)
    #expect(!FileManager.default.fileExists(atPath: fresh.path))
    #expect(FileManager.default.fileExists(atPath: other.path))
}

/// A stamp rounded to nearest lands in the future for half of every second,
/// which makes the directory's age negative — younger than any grace, and so
/// spared even by the zero an erase passes.
@Test func aStampIsNeverInTheFuture() throws {
    for fraction in [0.0, 0.4, 0.5, 0.6, 0.99] {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000 + fraction)
        let url = try TransferredFiles.write([1], name: "a.png", now: now)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let name = url.deletingLastPathComponent().lastPathComponent
        let written = try #require(TransferredFiles.stamp(in: name))
        #expect(now.timeIntervalSince(written) >= 0, "stamped \(fraction) into the future")
        TransferredFiles.sweep(in: url.deletingLastPathComponent().deletingLastPathComponent(), olderThan: 0, now: now)
        #expect(!FileManager.default.fileExists(atPath: url.path), "an erase spared it")
    }
}

@Test func aWrittenDirectoryCarriesItsTime() throws {
    let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let url = try TransferredFiles.write([1], name: "a.png", now: when)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let name = url.deletingLastPathComponent().lastPathComponent
    #expect(TransferredFiles.stamp(in: name).map { abs($0.timeIntervalSince(when)) < 1 } == true)
    #expect(TransferredFiles.stamp(in: "Transfer-nonsense-x") == nil)
    #expect(TransferredFiles.stamp(in: "Transfer-") == nil)
}
