import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let hatbandCard = UTType(exportedAs: "link.hatband.card")
    static let hatbandExport = UTType(exportedAs: "link.hatband.export")
}

/// Writes bytes for a share under complete protection in a fresh
/// temporary directory. Every `FileRepresentation` below goes through it.
nonisolated enum TransferredFiles {
    static func write(_ bytes: [UInt8], name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Transfer-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

/// A `.hatband` card.
nonisolated struct CardFile: Transferable {
    let bytes: [UInt8]
    let name: String

    init(bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .hatbandCard) { file in
            SentTransferredFile(try TransferredFiles.write(file.bytes, name: file.name), allowAccessingOriginalFile: false)
        }
    }
}

/// A `.hatband-export` container.
nonisolated struct ExportFile: Transferable {
    let bytes: [UInt8]
    let name: String

    init(bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .hatbandExport) { file in
            SentTransferredFile(try TransferredFiles.write(file.bytes, name: file.name), allowAccessingOriginalFile: false)
        }
    }
}

nonisolated struct VCardFile: Transferable {
    let bytes: [UInt8]
    let name: String

    init(bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .vCard) { file in
            SentTransferredFile(try TransferredFiles.write(file.bytes, name: file.name), allowAccessingOriginalFile: false)
        }
    }
}

nonisolated struct PNGFile: Transferable {
    let bytes: [UInt8]
    let name: String

    init(bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { file in
            SentTransferredFile(try TransferredFiles.write(file.bytes, name: file.name), allowAccessingOriginalFile: false)
        }
    }
}

nonisolated struct PDFFile: Transferable {
    let bytes: [UInt8]
    let name: String

    init(bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(try TransferredFiles.write(file.bytes, name: file.name), allowAccessingOriginalFile: false)
        }
    }
}

nonisolated struct SVGFile: Transferable {
    let bytes: [UInt8]
    let name: String

    init(bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .svg) { file in
            SentTransferredFile(try TransferredFiles.write(file.bytes, name: file.name), allowAccessingOriginalFile: false)
        }
    }
}
