import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// Serialized: `Store.onEvent` is one hook for the whole process.
@MainActor @Suite(.serialized) struct EraseTests {
    private func sampleProfile() -> Profile {
        var profile = Profile()
        profile.name = "Leopold Bloom"
        profile.email = "bloom@example.ie"
        return profile
    }

    private func onboarded() async throws -> (AppModel, MemoryKeyStore) {
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(), appLock: true)
        let keys = try #require(model.keys as? MemoryKeyStore)
        return (model, keys)
    }

    /// On a temp directory store, so `erase()` reaches a real container.
    @Test func keysBeforeStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Erase-" + UUID().uuidString, isDirectory: true)
        let keys = MemoryKeyStore()
        let model = AppModel(keys: keys, makeStore: { try Store.onDisk(at: directory) })
        model.protectedDataAvailable = { true }
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(), appLock: true)
        var events: [String] = []
        var ownerStillThere: [Bool] = []
        keys.onEvent = { event in
            events.append(event)
            if event.hasPrefix("delete ") {
                ownerStillThere.append((try? model.store?.owner()) != nil)
            }
        }
        Store.onEvent = { events.append($0) }
        defer { Store.onEvent = nil }
        await model.eraseEverything()
        let dbkey = try #require(events.firstIndex(of: "delete dbkey"))
        let seed = try #require(events.firstIndex(of: "delete seed"))
        let index = try #require(events.firstIndex(of: "delete persona-index"))
        let erase = try #require(events.firstIndex(of: "erase"))
        #expect(dbkey < seed)
        #expect(seed < index)
        #expect(index < erase)
        #expect(ownerStillThere == [true, true, true])
    }

    @Test func afterEraseNothingRemains() async throws {
        let (model, keys) = try await onboarded()
        try model.setHomeWidget(true)
        let directory = try #require(model.widgetDirectory)
        await model.eraseEverything()
        #expect(keys.items.isEmpty)
        #expect(model.store == nil)
        #expect(WidgetFeed.read(from: directory) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WidgetFeed.fileName).path))
        #expect(model.sharing == nil)
        #expect(model.people.isEmpty)
        #expect(model.personas.isEmpty)
        #expect(model.profile == Profile())
        #expect(model.settings == Hatband.Settings())
        #expect(model.dbKey == nil)
        #expect(model.locked)
        #expect(model.error == nil)
        #expect(model.phase == .onboarding)
    }

    @Test func reonboardAfterErase() async throws {
        let (model, keys) = try await onboarded()
        let oldSeed = try #require(keys.items[KeyName.seed]).data
        await model.eraseEverything()
        try model.finishOnboarding(profile: sampleProfile(), appLock: false)
        #expect(model.phase == .ready)
        #expect(model.store != nil)
        #expect(!model.locked)
        let newSeed = try #require(keys.items[KeyName.seed]).data
        #expect(newSeed.count == 32)
        #expect(newSeed != oldSeed)
        #expect(try model.identity().seed == Array(newSeed))
        #expect(keys.items[KeyName.database]?.access == .database(appLock: false, includeInBackup: false))
        #expect(try model.store?.owner() != nil)
        #expect(try model.store?.people().isEmpty == true)
        #expect(model.personas.count == 1)
    }

    @Test func eraseRemovesStoreDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Erase-" + UUID().uuidString, isDirectory: true)
        let model = AppModel(keys: MemoryKeyStore(), makeStore: { try Store.onDisk(at: directory) })
        model.protectedDataAvailable = { true }
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(), appLock: false)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        await model.eraseEverything()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(model.store == nil)
        #expect(model.phase == .onboarding)
    }

    /// The next onboarding recreates the directory; it must start outside
    /// backups at once, not at the next launch.
    @Test func reonboardAfterEraseExcludesStoreFromBackup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Erase-" + UUID().uuidString, isDirectory: true)
        defer { Store.removeDirectory(at: directory) }
        let model = AppModel(keys: MemoryKeyStore(), makeStore: { try Store.onDisk(at: directory) })
        model.protectedDataAvailable = { true }
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(), appLock: false)
        await model.eraseEverything()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try model.finishOnboarding(profile: sampleProfile(), appLock: false)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        let values = try URL(fileURLWithPath: directory.path).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    /// The Home Screen widget keeps its last entry until WidgetKit is
    /// told; erase tells it once the feed is gone.
    @Test func eraseReloadsWidgetAfterRemovingFeed() async throws {
        let (model, _) = try await onboarded()
        try model.setHomeWidget(true)
        let directory = try #require(model.widgetDirectory)
        let path = WidgetFeed.fileURL(in: directory).path
        #expect(FileManager.default.fileExists(atPath: path))
        var feedPresentAtReload: [Bool] = []
        AppModel.onWidgetReload = { feedPresentAtReload.append(FileManager.default.fileExists(atPath: path)) }
        defer { AppModel.onWidgetReload = nil }
        await model.eraseEverything()
        #expect(feedPresentAtReload == [false])
    }

    /// A file written for the share sheet (a card, a vCard, an export)
    /// does not outlive an erase.
    @Test func eraseSweepsSharedFiles() async throws {
        let (model, _) = try await onboarded()
        let shared = try TransferredFiles.write([0x42, 0x45, 0x47, 0x49, 0x4E], name: "someone.vcf")
        #expect(FileManager.default.fileExists(atPath: shared.path))
        await model.eraseEverything()
        #expect(!FileManager.default.fileExists(atPath: shared.path))
        #expect(!FileManager.default.fileExists(atPath: shared.deletingLastPathComponent().path))
    }
}
