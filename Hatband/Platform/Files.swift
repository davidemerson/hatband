import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let hatbandCard = UTType(exportedAs: "link.hatband.card")
    static let hatbandExport = UTType(exportedAs: "link.hatband.export")
}

/// Writes bytes for a share in a fresh temporary directory. Every
/// `FileRepresentation` below goes through it.
nonisolated enum TransferredFiles {
    static let prefix = "Transfer-"

    /// Removes the directories earlier shares left behind, so plaintext card
    /// bytes never outlive the share by longer than the trip out and back.
    ///
    /// Never call this from `write`. A `FileRepresentation` is resolved more
    /// than once — the share sheet resolves it to draw a thumbnail, then the
    /// receiving extension resolves it to take the bytes — and the print
    /// sheet keeps three of them alive at once, so sweeping on write deletes
    /// the file the previous resolution is still vending. That is what Signal
    /// reported as "Unable to Prepare Attachment".
    static func sweep(in temporary: URL = FileManager.default.temporaryDirectory) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: temporary.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? manager.removeItem(at: temporary.appendingPathComponent(name))
        }
    }

    /// `.completeUnlessOpen` rather than `.complete`: another process reads
    /// this file while Hatband is in the background, and a complete-protected
    /// file is unreadable the moment the phone locks behind the share sheet.
    /// The bytes are still unreadable at rest, which is what the class is for.
    static func write(_ bytes: [UInt8], name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
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
