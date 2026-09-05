import Foundation
import Testing
@testable import Hatband

@MainActor struct StoreTests {
    private let first = Data([1, 1, 1, 1, 1, 1, 1, 1])
    private let second = Data([2, 2, 2, 2, 2, 2, 2, 2])

    @Test func inMemoryInsertFetchDelete() throws {
        let store = try Store.inMemory()
        #expect(store.directory == nil)
        #expect(try store.owner() == nil)
        store.insert(OwnerRecord(blob: Data([1])))
        let older = PersonRecord(personaID: first, updatedAt: Date(timeIntervalSince1970: 100), sealed: Data([1]))
        let newer = PersonRecord(personaID: second, updatedAt: Date(timeIntervalSince1970: 200), sealed: Data([2]))
        store.insert(newer)
        store.insert(older)
        try store.save()
        #expect(try store.owner()?.blob == Data([1]))
        #expect(try store.people().map { $0.personaID } == [first, second])
        #expect(try store.person(id: second)?.sealed == Data([2]))
        #expect(try store.person(id: Data([3, 3, 3, 3, 3, 3, 3, 3])) == nil)
        store.delete(older)
        try store.save()
        #expect(try store.people().map { $0.personaID } == [second])
    }

    @Test func saveFiresEvent() throws {
        let store = try Store.inMemory()
        var events: [String] = []
        Store.onEvent = { events.append($0) }
        defer { Store.onEvent = nil }
        store.insert(OwnerRecord(blob: Data([1])))
        try store.save()
        store.reassertProtection()
        #expect(events == ["save", "reassert"])
    }

    @Test func onDiskSetsProtectionAndBackupExclusion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Store-" + UUID().uuidString, isDirectory: true)
        let store = try Store.onDisk(at: directory)
        #expect(store.directory == directory)
        store.insert(OwnerRecord(blob: Data([1])))
        try store.save()
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Hatband.store").path))

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let protection = attributes[.protectionKey]
        let raw = (protection as? FileProtectionType)?.rawValue ?? (protection as? String)
        #expect(raw == FileProtectionType.complete.rawValue)

        try store.setExcludedFromBackup(true)
        #expect(try URL(fileURLWithPath: directory.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        try store.setExcludedFromBackup(false)
        #expect(try URL(fileURLWithPath: directory.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)

        var events: [String] = []
        Store.onEvent = { events.append($0) }
        defer { Store.onEvent = nil }
        try store.erase()
        #expect(events == ["erase"])
        Store.removeDirectory(at: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
