import Foundation
import HatbandCore

/// What the Messages extension offers: one entry per persona, each carrying
/// a finished, signed card. The extension cannot sign — the seed is the app's
/// alone, and giving a second process the master key for every persona would
/// cost far more than this feature is worth — so the app writes what there is
/// to send and the extension only chooses between them.
///
/// This is the one thing that crosses to another process without being
/// compact. `WidgetFeed` refuses anything but a compact card by design; a
/// message needs a signed one, and the file form carries the headshot and the
/// GPG certificate too. So this file takes `.completeFileProtection` rather
/// than the widget's until-first-unlock class: the widget has to draw on a
/// locked phone, and a Messages extension never runs on one.
nonisolated struct ShareFeed: Codable, Equatable {
    static let fileName = "card-share.json"

    /// Apple does not document the limit on a message's URL, only that
    /// passing it fails with `URLExceedsMaxSize`. Real cards are nowhere near
    /// this — 447 characters is typical, 1,334 with a photo and a key — so
    /// this is the point past which the photo is not worth the risk. The
    /// caller retries on the error as well; a threshold alone would be a guess.
    static let safeURLCharacters = 4_000

    nonisolated struct Card: Codable, Equatable {
        var personaID: [UInt8]
        var label: String
        var name: String?
        var company: String?
        var color: UInt8
        /// Signed, everything: channels, custom fields, the photo, the key.
        var fileURL: String
        /// Signed, without the photo or the certificate. Sent when the whole
        /// card is too long for a message to carry.
        var fullQRURL: String

        /// The URL a message should carry, given what it will take.
        func sendable(within limit: Int = ShareFeed.safeURLCharacters) -> String {
            fileURL.count <= limit ? fileURL : fullQRURL
        }
    }

    var cards: [Card]
    /// The day every card in the file was signed for. The signature covers it,
    /// so the extension cannot correct it; the app rewrites the file when the
    /// day has moved on.
    var issuedDay: UInt32
    var writtenAt: Date

    nonisolated enum Failure: Error, Equatable {
        case noContainer
    }

    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Nil unless the file parses; entries whose URLs do not decode to a
    /// signed card are dropped. The widget's guard keeps anything but a
    /// compact card out of its file; this one keeps anything but a signed
    /// card out of a message.
    static func read(from directory: URL? = AppGroup.container) -> ShareFeed? {
        guard let directory else { return nil }
        guard let data = try? Data(contentsOf: fileURL(in: directory)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard var feed = try? decoder.decode(ShareFeed.self, from: data) else { return nil }
        feed.cards = feed.cards.filter(ShareFeed.carriesSignedCards)
        return feed.cards.isEmpty ? nil : feed
    }

    static func carriesSignedCards(_ card: Card) -> Bool {
        guard let file = try? HB1.decode(url: card.fileURL), file.isSigned,
              let full = try? HB1.decode(url: card.fullQRURL), full.isSigned
        else { return false }
        return true
    }

    /// Atomic, unreadable while the phone is locked, excluded from backup.
    func write(to directory: URL? = AppGroup.container) throws {
        guard let directory else { throw Failure.noContainer }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(self)
        var file = ShareFeed.fileURL(in: directory)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }

    static func remove(from directory: URL? = AppGroup.container) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: fileURL(in: directory))
    }

    /// Whether the cards were signed for a day that has passed. They still
    /// verify and still save; only the day they name is yesterday's.
    func isStale(on day: UInt32) -> Bool {
        issuedDay != day
    }
}
