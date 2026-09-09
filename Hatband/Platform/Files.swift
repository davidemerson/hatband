import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let hatbandCard = UTType(exportedAs: "link.hatband.card")
    static let hatbandExport = UTType(exportedAs: "link.hatband.export")
}

/// Everything below shares bytes it already holds, so nothing is written to
/// disk to be shared. This only clears up after builds that did.
///
/// Sharing through a `FileRepresentation` cost a temporary directory, a
/// protection class and a sweep that had to guess when a receiver had finished
/// reading — and Signal's share extension refused a PNG, an SVG and a PDF
/// vended that way while accepting a `.hatband` file through the same code.
/// A `DataRepresentation` hands over the bytes and lets the system put them
/// wherever the receiver needs them. The bytes were in memory either way.
nonisolated enum TransferredFiles {
    static let prefix = "Transfer-"

    /// Deletes what earlier builds left in the temporary directory, so their
    /// plaintext card bytes do not sit there until iOS gets round to it.
    /// Nothing writes these any more, so there is nothing in flight to race.
    static func sweep(in temporary: URL = FileManager.default.temporaryDirectory) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: temporary.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? manager.removeItem(at: temporary.appendingPathComponent(name))
        }
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
        DataRepresentation(exportedContentType: .hatbandCard) { Data($0.bytes) }
            .suggestedFileName { $0.name }
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
        DataRepresentation(exportedContentType: .hatbandExport) { Data($0.bytes) }
            .suggestedFileName { $0.name }
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
        DataRepresentation(exportedContentType: .vCard) { Data($0.bytes) }
            .suggestedFileName { $0.name }
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
        DataRepresentation(exportedContentType: .png) { Data($0.bytes) }
            .suggestedFileName { $0.name }
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
        DataRepresentation(exportedContentType: .pdf) { Data($0.bytes) }
            .suggestedFileName { $0.name }
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
        DataRepresentation(exportedContentType: .svg) { Data($0.bytes) }
            .suggestedFileName { $0.name }
    }
}
