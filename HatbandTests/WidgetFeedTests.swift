import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct WidgetFeedTests {
    /// A fresh temporary directory; never the real group container.
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetFeed-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func compactFeed() throws -> WidgetFeed {
        WidgetFeed(url: try Vectors.url("compact-two-channels"), name: "Leopold Bloom", color: 4,
                   writtenAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func roundTripInTempDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(WidgetFeed.read(from: directory) == nil)
        let feed = try compactFeed()
        try feed.write(to: directory)
        #expect(FileManager.default.fileExists(atPath: WidgetFeed.fileURL(in: directory).path))
        let read = try #require(WidgetFeed.read(from: directory))
        #expect(read == feed)
        #expect(read.url == feed.url)
        #expect(read.name == "Leopold Bloom")
        #expect(read.color == 4)
        #expect(read.writtenAt == feed.writtenAt)

        var nameless = feed
        nameless.name = nil
        try nameless.write(to: directory)
        #expect(WidgetFeed.read(from: directory) == nameless)
    }

    @Test func readRefusesFullCard() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let feed = WidgetFeed(url: try Vectors.url("typical-signed"), name: nil, color: 1, writtenAt: Date())
        try feed.write(to: directory)
        #expect(FileManager.default.fileExists(atPath: WidgetFeed.fileURL(in: directory).path))
        #expect(WidgetFeed.read(from: directory) == nil)
    }

    @Test func readRefusesGarbage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = WidgetFeed.fileURL(in: directory)
        try Data([0xFF, 0x00, 0x7B, 0x7D]).write(to: file)
        #expect(WidgetFeed.read(from: directory) == nil)
        try Data("{}".utf8).write(to: file)
        #expect(WidgetFeed.read(from: directory) == nil)
        let notACard = WidgetFeed(url: "https://hatband.link/#1NOTACARD", name: nil, color: 0, writtenAt: Date())
        try notACard.write(to: directory)
        #expect(WidgetFeed.read(from: directory) == nil)
        #expect(WidgetFeed.read(from: nil) == nil)
    }

    @Test func removeDeletesFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try compactFeed().write(to: directory)
        let path = WidgetFeed.fileURL(in: directory).path
        #expect(FileManager.default.fileExists(atPath: path))
        WidgetFeed.remove(from: directory)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(WidgetFeed.read(from: directory) == nil)
        // Removing twice, or from nowhere, is quiet.
        WidgetFeed.remove(from: directory)
        WidgetFeed.remove(from: nil)
    }

    @Test func writeSetsProtectionAndBackupExclusion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try compactFeed().write(to: directory)
        let file = WidgetFeed.fileURL(in: directory)
        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // The simulator may not report a protection class; where it does,
        // it must be readable after the first unlock and no later.
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let protection = attributes[.protectionKey]
        if let raw = (protection as? FileProtectionType)?.rawValue ?? (protection as? String) {
            #expect(raw == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        }
    }

    /// Of the ten vectors only the two Lock Screen cards may feed the widget.
    @Test func readAcceptsOnlyCompactVectors() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var accepted: [String] = []
        for vector in try Vectors.all() {
            let name = try #require(vector["name"] as? String)
            let url = try #require(vector["url"] as? String)
            try WidgetFeed(url: url, name: nil, color: 0, writtenAt: Date()).write(to: directory)
            if WidgetFeed.read(from: directory) != nil {
                accepted.append(name)
            }
            #expect(try HB1.decode(url: url).isCompact == name.hasPrefix("compact-"), "\(name)")
        }
        #expect(accepted == ["compact-name-only", "compact-two-channels"])
    }

    @Test func kindAndFileNameAreFixed() {
        #expect(WidgetFeed.kind == "link.hatband.card")
        #expect(WidgetFeed.fileName == "card-widget.json")
        #expect(AppGroup.id == "group.link.hatband")
    }
}
