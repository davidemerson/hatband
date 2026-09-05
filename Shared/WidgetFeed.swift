import Foundation
import HatbandCore

/// The only file allowed to name the App Group container.
nonisolated enum AppGroup {
    static let id = "group.link.hatband"
}

/// What the Home Screen widget draws: the selected persona's compact URL,
/// its name when the user shows it, and its colour. A JSON file in the
/// App Group container; never a preferences store.
nonisolated struct WidgetFeed: Codable, Equatable {
    /// The widget kind string.
    static let kind = "link.hatband.card"
    static let fileName = "card-widget.json"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
    }

    nonisolated enum Failure: Error, Equatable {
        case noContainer
    }

    var url: String
    var name: String?
    var color: UInt8
    var writtenAt: Date

    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Nil unless the file parses and its URL decodes to a compact card.
    static func read(from directory: URL? = container) -> WidgetFeed? {
        guard let directory else { return nil }
        guard let data = try? Data(contentsOf: fileURL(in: directory)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let feed = try? decoder.decode(WidgetFeed.self, from: data) else { return nil }
        guard let card = try? HB1.decode(url: feed.url), card.isCompact else { return nil }
        return feed
    }

    /// Atomic, readable after the first unlock, excluded from backup.
    func write(to directory: URL? = container) throws {
        guard let directory else { throw Failure.noContainer }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(self)
        var file = WidgetFeed.fileURL(in: directory)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }

    static func remove(from directory: URL? = container) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: fileURL(in: directory))
    }
}
