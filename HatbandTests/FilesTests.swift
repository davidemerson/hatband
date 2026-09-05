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
        // The simulator may not report a protection class; where it does, it must be complete.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attributes[.protectionKey]
        if let raw = (protection as? FileProtectionType)?.rawValue ?? (protection as? String) {
            #expect(raw == FileProtectionType.complete.rawValue)
        }
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
