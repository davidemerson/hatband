import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The one thing that crosses to another process without being compact. A
/// message needs a signed card, and the Messages extension cannot sign, so
/// the app writes finished cards for it to choose between.
struct ShareFeedTests {
    /// A fresh temporary directory; never the real group container.
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareFeed-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func card(file: String = "typical-signed", full: String = "maximal-qr-signed") throws -> ShareFeed.Card {
        ShareFeed.Card(personaID: Array(repeating: 0xAB, count: 8), label: "Work",
                       name: "Leopold Bloom", company: "Freeman's Journal", color: 4,
                       fileURL: try Vectors.url(file), fullQRURL: try Vectors.url(full))
    }

    private func feed(day: UInt32 = 2438) throws -> ShareFeed {
        ShareFeed(cards: [try card()], issuedDay: day, writtenAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func roundTripInTempDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(ShareFeed.read(from: directory) == nil)
        let written = try feed()
        try written.write(to: directory)
        #expect(FileManager.default.fileExists(atPath: ShareFeed.fileURL(in: directory).path))
        let read = try #require(ShareFeed.read(from: directory))
        #expect(read == written)
        #expect(read.cards.first?.name == "Leopold Bloom")
        #expect(read.cards.first?.company == "Freeman's Journal")

        ShareFeed.remove(from: directory)
        #expect(ShareFeed.read(from: directory) == nil)
    }

    /// The widget's file refuses anything but a compact card. This one
    /// refuses anything but a signed one: an unsigned card in a message can
    /// never update someone who already has you.
    @Test func onlySignedCardsAreOffered() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A compact card is unsigned, so an entry carrying one is dropped.
        var compact = try card()
        compact.fileURL = try Vectors.url("compact-name-only")
        try ShareFeed(cards: [compact], issuedDay: 2438, writtenAt: Date()).write(to: directory)
        #expect(ShareFeed.read(from: directory) == nil, "an unsigned card is not offered")

        // So is one whose URL is not a card at all.
        var nonsense = try card()
        nonsense.fullQRURL = "https://example.org/not-a-card"
        try ShareFeed(cards: [nonsense], issuedDay: 2438, writtenAt: Date()).write(to: directory)
        #expect(ShareFeed.read(from: directory) == nil)

        // And a good entry survives beside a bad one rather than taking it down.
        try ShareFeed(cards: [try card(), nonsense], issuedDay: 2438, writtenAt: Date()).write(to: directory)
        #expect(ShareFeed.read(from: directory)?.cards.count == 1)
    }

    /// A message's URL has an undocumented cap, and the whole card carries a
    /// photo. Under the cap it goes whole; over it, without the photo.
    @Test func theWholeCardGoesWhenAMessageWillCarryIt() throws {
        let small = try card(file: "typical-signed", full: "maximal-qr-signed")
        #expect(small.sendable() == small.fileURL)

        // The ceiling case: 32 KB of CBOR is past fifty thousand characters.
        var huge = try card()
        huge.fileURL = HB1.urlPrefix + String(HB1.formatTag) + String(repeating: "A", count: 60_000)
        #expect(huge.sendable() == huge.fullQRURL, "the photo is dropped rather than the message")

        // The boundary itself, so the rule is the length and not the vector.
        var exact = try card()
        exact.fileURL = String(repeating: "x", count: ShareFeed.safeURLCharacters)
        #expect(exact.sendable() == exact.fileURL)
        exact.fileURL = String(repeating: "x", count: ShareFeed.safeURLCharacters + 1)
        #expect(exact.sendable() == exact.fullQRURL)
    }

    /// The signature covers the issued day, so the extension cannot correct
    /// one that has passed; the app notices instead.
    @Test func aFeedKnowsWhenItsDayHasPassed() throws {
        let today = try feed(day: 2438)
        #expect(!today.isStale(on: 2438))
        #expect(today.isStale(on: 2439))
        #expect(today.isStale(on: 2437))
    }

    /// Unreadable while the phone is locked, and out of backups. Stronger
    /// than the widget's file, which has to draw before the first unlock;
    /// this one holds the photo and the certificate and never runs locked.
    @Test func writeSetsProtectionAndBackupExclusion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try feed().write(to: directory)
        let file = ShareFeed.fileURL(in: directory)
        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // The simulator does not always report a protection class; when it
        // does, it must be the complete one.
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
    }

    @Test func fileNameIsFixedAndSeparateFromTheWidgets() {
        #expect(ShareFeed.fileName == "card-share.json")
        #expect(ShareFeed.fileName != WidgetFeed.fileName)
        #expect(AppGroup.id == "group.link.hatband")
    }
}
