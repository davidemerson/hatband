import CoreTransferable
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

    /// Every share vends its bytes and its name, and writes nothing to disk.
    /// Signal refused a PNG, an SVG and a PDF vended as files while taking a
    /// `.hatband` through the same code; the bytes were in memory either way,
    /// so the file was only ever an extra copy to get wrong.
    @Test func sharesVendBytesAndAName() async throws {
        func check<T: Transferable>(_ item: T, bytes: [UInt8], name: String, type: UTType) async throws {
            #expect(T.exportedContentTypes() == [type], "\(name)")
            #expect(Array(try await item.exported(as: type)) == bytes, "\(name)")
            let provider = NSItemProvider()
            provider.register(item)
            #expect(provider.registeredTypeIdentifiers == [type.identifier], "\(name)")
            #expect(provider.suggestedName == name, "\(name)")
        }
        let temporary = FileManager.default.temporaryDirectory.path
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: temporary)) ?? [])
        try await check(CardFile(bytes: [1, 2, 3], name: "a.hatband"), bytes: [1, 2, 3], name: "a.hatband", type: .hatbandCard)
        try await check(PNGFile(bytes: [4, 5], name: "b.png"), bytes: [4, 5], name: "b.png", type: .png)
        try await check(SVGFile(bytes: [6], name: "c.svg"), bytes: [6], name: "c.svg", type: .svg)
        try await check(PDFFile(bytes: [7], name: "d.pdf"), bytes: [7], name: "d.pdf", type: .pdf)
        try await check(VCardFile(bytes: [8], name: "e.vcf"), bytes: [8], name: "e.vcf", type: .vCard)
        try await check(ExportFile(bytes: [9], name: "f.hatband-export"), bytes: [9], name: "f.hatband-export", type: .hatbandExport)
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: temporary)) ?? [])
        #expect(after.subtracting(before).filter { $0.hasPrefix(TransferredFiles.prefix) }.isEmpty,
                "a share wrote to the temporary directory")
    }
}

/// Builds before this one wrote `Transfer-*` directories full of plaintext
/// card bytes. Nothing writes them now, so the sweep can take them all.
@Test func sweepClearsWhatOlderBuildsLeft() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    func directory(_ name: String) throws -> URL {
        let url = temporary.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    let stamped = try directory(TransferredFiles.prefix + "800000000-" + UUID().uuidString)
    let unstamped = try directory(TransferredFiles.prefix + "old")
    let other = try directory("keep")
    TransferredFiles.sweep(in: temporary)
    #expect(!FileManager.default.fileExists(atPath: stamped.path))
    #expect(!FileManager.default.fileExists(atPath: unstamped.path))
    #expect(FileManager.default.fileExists(atPath: other.path), "swept something that was not ours")
}
