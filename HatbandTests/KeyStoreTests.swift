import Foundation
import Testing
@testable import Hatband

@MainActor struct KeyStoreTests {
    @Test func absentReadsNil() async throws {
        let store = MemoryKeyStore()
        #expect(try await store.read(KeyName.seed, prompt: nil) == nil)
    }

    @Test func writeReplaces() async throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.database, Data([1]), access: .database(appLock: true, includeInBackup: false))
        try store.write(KeyName.database, Data([2]), access: .database(appLock: false, includeInBackup: true))
        #expect(try await store.read(KeyName.database, prompt: nil) == Data([2]))
        #expect(store.items[KeyName.database]?.access == .database(appLock: false, includeInBackup: true))
        #expect(store.items.count == 1)
    }

    @Test func deleteRemoves() async throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.seed, Data([1]), access: .seed)
        try store.delete(KeyName.seed)
        #expect(try await store.read(KeyName.seed, prompt: nil) == nil)
        try store.delete(KeyName.seed)
        #expect(store.items.isEmpty)
    }

    @Test func promptsRecorded() async throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.database, Data([1]), access: .database(appLock: true, includeInBackup: false))
        _ = try await store.read(KeyName.database, prompt: "Unlock")
        _ = try await store.read(KeyName.database, prompt: nil)
        _ = try await store.read(KeyName.database, prompt: "Again")
        #expect(store.prompts == ["Unlock", "Again"])
    }

    @Test func failNextReadThrowsOnce() async throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.seed, Data([7]), access: .seed)
        store.failNextRead = .cancelled
        await #expect(throws: KeyStoreError.cancelled) {
            try await store.read(KeyName.seed, prompt: nil)
        }
        #expect(store.failNextRead == nil)
        #expect(try await store.read(KeyName.seed, prompt: nil) == Data([7]))
    }

    /// The contract every store keeps: a write that fails leaves the item
    /// as it was, data and access alike.
    @Test func failNextWriteLeavesTheItem() async throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.database, Data([1]), access: .database(appLock: true, includeInBackup: false))
        store.failNextWrite = .failed(-25299)
        #expect(throws: KeyStoreError.failed(-25299)) {
            try store.write(KeyName.database, Data([2]), access: .database(appLock: false, includeInBackup: false))
        }
        #expect(store.failNextWrite == nil)
        #expect(try await store.read(KeyName.database, prompt: nil) == Data([1]))
        #expect(store.items[KeyName.database]?.access == .database(appLock: true, includeInBackup: false))
        try store.write(KeyName.database, Data([2]), access: .database(appLock: false, includeInBackup: false))
        #expect(store.items[KeyName.database]?.data == Data([2]))
        #expect(store.items[KeyName.database]?.access == .database(appLock: false, includeInBackup: false))
    }

    /// A read behind a prompt suspends; the double can stand in for one.
    @Test func readDelaySuspends() async throws {
        let store = MemoryKeyStore()
        try store.write(KeyName.seed, Data([1]), access: .seed)
        store.readDelay = .milliseconds(50)
        let started = ContinuousClock.now
        #expect(try await store.read(KeyName.seed, prompt: nil) == Data([1]))
        #expect(ContinuousClock.now - started >= .milliseconds(40))
    }

    @Test func eventsFire() async throws {
        let store = MemoryKeyStore()
        var events: [String] = []
        store.onEvent = { events.append($0) }
        try store.write(KeyName.seed, Data([1]), access: .seed)
        _ = try await store.read(KeyName.seed, prompt: nil)
        try store.delete(KeyName.seed)
        #expect(events == ["write seed", "read seed", "delete seed"])
    }
}
