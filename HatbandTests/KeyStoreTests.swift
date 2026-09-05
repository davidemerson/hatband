import Foundation
import Testing
@testable import Hatband

@MainActor struct KeyStoreTests {
    @Test func absentReadsNil() throws {
        let store = MemoryKeyStore()
        #expect(try store.read(KeyName.seed, prompt: nil) == nil)
    }

    @Test func writeReplaces() throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.database, Data([1]), access: .database(appLock: true, includeInBackup: false))
        try store.write(KeyName.database, Data([2]), access: .database(appLock: false, includeInBackup: true))
        #expect(try store.read(KeyName.database, prompt: nil) == Data([2]))
        #expect(store.items[KeyName.database]?.access == .database(appLock: false, includeInBackup: true))
        #expect(store.items.count == 1)
    }

    @Test func deleteRemoves() throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.seed, Data([1]), access: .seed)
        try store.delete(KeyName.seed)
        #expect(try store.read(KeyName.seed, prompt: nil) == nil)
        try store.delete(KeyName.seed)
        #expect(store.items.isEmpty)
    }

    @Test func promptsRecorded() throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.database, Data([1]), access: .database(appLock: true, includeInBackup: false))
        _ = try store.read(KeyName.database, prompt: "Unlock")
        _ = try store.read(KeyName.database, prompt: nil)
        _ = try store.read(KeyName.database, prompt: "Again")
        #expect(store.prompts == ["Unlock", "Again"])
    }

    @Test func failNextReadThrowsOnce() throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.seed, Data([7]), access: .seed)
        store.failNextRead = .cancelled
        #expect(throws: KeyStoreError.cancelled) {
            try store.read(KeyName.seed, prompt: nil)
        }
        #expect(store.failNextRead == nil)
        #expect(try store.read(KeyName.seed, prompt: nil) == Data([7]))
    }

    @Test func eventsFire() throws {
        let store = MemoryKeyStore()
        var events: [String] = []
        store.onEvent = { events.append($0) }
        try store.write(KeyName.seed, Data([1]), access: .seed)
        _ = try store.read(KeyName.seed, prompt: nil)
        try store.delete(KeyName.seed)
        #expect(events == ["write seed", "read seed", "delete seed"])
    }
}
