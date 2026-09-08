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

@Test func sweepRemovesEarlierTransfers() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let stale = temporary.appendingPathComponent(TransferredFiles.prefix + "old", isDirectory: true)
    let other = temporary.appendingPathComponent("keep", isDirectory: true)
    try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    TransferredFiles.sweep(in: temporary)
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: other.path))
}
