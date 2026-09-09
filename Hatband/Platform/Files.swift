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

    /// How long a share's file is left alone. A receiver resolves the file
    /// after the sheet it came from has gone, so "the app is frontmost again"
    /// is not the same as "no share is in flight". A minute is far longer than
    /// any receiver has ever needed and keeps the bytes' life short, which is
    /// the point of sweeping at all.
    static let grace: TimeInterval = 60

    /// Removes the directories earlier shares left behind, so plaintext card
    /// bytes never outlive the share by much longer than the trip out and back.
    ///
    /// Age comes from the directory's own name, not from the file system: the
    /// boundary lint forbids reading creation dates, and a name cannot be
    /// touched by anything that reads the file.
    ///
    /// Never sweep indiscriminately. A `FileRepresentation` is resolved more
    /// than once — the share sheet resolves it to draw a thumbnail, then the
    /// receiving extension resolves it to take the bytes — and an extension
    /// like Signal's goes on preparing the attachment after its sheet has
    /// closed and Hatband is frontmost again. Deleting a file that is still
    /// being vended is what Signal reports as "Unable to Prepare Attachment".
    static func sweep(
        in temporary: URL = FileManager.default.temporaryDirectory,
        olderThan grace: TimeInterval = grace,
        now: Date = Date()
    ) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: temporary.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            // A name from a build that wrote no stamp is from a previous
            // launch by definition, and goes.
            if let written = stamp(in: name), now.timeIntervalSince(written) < grace { continue }
            try? manager.removeItem(at: temporary.appendingPathComponent(name))
        }
    }

    /// `Transfer-<seconds since the reference date>-<uuid>`, or nil if the
    /// name does not carry one.
    static func stamp(in name: String) -> Date? {
        let rest = name.dropFirst(prefix.count)
        guard let dash = rest.firstIndex(of: "-"), let seconds = Double(rest[rest.startIndex..<dash]) else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// `.completeUnlessOpen` rather than `.complete`: another process reads
    /// this file while Hatband is in the background, and a complete-protected
    /// file is unreadable the moment the phone locks behind the share sheet.
    /// The bytes are still unreadable at rest, which is what the class is for.
    static func write(_ bytes: [UInt8], name: String, now: Date = Date()) throws -> URL {
        // Rounded down, never up: a stamp in the future makes the age
        // negative, and a negative age is younger than any grace — including
        // the zero an erase passes.
        let stamp = String(Int(now.timeIntervalSinceReferenceDate.rounded(.down)))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + stamp + "-" + UUID().uuidString, isDirectory: true)
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
