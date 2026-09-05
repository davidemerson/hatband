import CryptoKit
import Foundation
import HatbandCore
import SwiftUI
import Testing
import UIKit
@testable import Hatband

@MainActor struct AppModelTests {
    private let prompt = "Unlock the people you have scanned."

    private func sampleProfile() -> Profile {
        var profile = Profile()
        profile.name = "Leopold Bloom"
        profile.email = "bloom@example.ie"
        profile.phone = "+353871234567"
        return profile
    }

    /// A loaded, onboarded model and its key store.
    private func onboarded(appLock: Bool = true) async throws -> (AppModel, MemoryKeyStore) {
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(), appLock: appLock)
        let keys = try #require(model.keys as? MemoryKeyStore)
        return (model, keys)
    }

    @Test func loadWithoutOwnerIsOnboarding() async throws {
        let model = try AppModel.inMemory()
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .onboarding)
        #expect(model.locked)
        #expect(model.people.isEmpty)
        #expect(model.store != nil)
        #expect(model.error == nil)
    }

    @Test func finishOnboardingWritesKeysAndPersona() async throws {
        let (model, keys) = try await onboarded()
        let seed = try #require(keys.items[KeyName.seed])
        #expect(seed.data.count == 32)
        #expect(seed.access == .seed)
        let database = try #require(keys.items[KeyName.database])
        #expect(database.data.count == 32)
        #expect(database.access == .database(appLock: true, includeInBackup: false))
        #expect(model.personas.count == 1)
        let persona = try #require(model.personas.first)
        #expect(persona.label == "Personal")
        #expect(persona.keyIndex == 0)
        #expect(persona.color == 1)
        #expect(persona.id.count == 8)
        #expect(persona.channels == sampleProfile().presentChannels)
        #expect(model.selectedPersonaID == persona.id)
        #expect(model.settings.appLock)
        #expect(try model.store?.owner() != nil)
        #expect(model.phase == .ready)
        #expect(model.profile == sampleProfile())
    }

    @Test func reloadRestoresOwner() async throws {
        let (model, keys) = try await onboarded()
        let store = try #require(model.store)
        let second = AppModel(keys: keys, makeStore: { store })
        second.protectedDataAvailable = { true }
        await second.load()
        #expect(second.phase == .ready)
        #expect(second.profile == model.profile)
        #expect(second.personas == model.personas)
        #expect(second.settings == model.settings)
        #expect(second.selectedPersonaID == model.selectedPersonaID)
    }

    @Test func appLockOffUnlocksOnLoad() async throws {
        let (model, keys) = try await onboarded(appLock: false)
        let store = try #require(model.store)
        let second = AppModel(keys: keys, makeStore: { store })
        second.protectedDataAvailable = { true }
        await second.load()
        #expect(!second.locked)
        #expect(second.dbKey != nil)
    }

    @Test func appLockOnStaysLocked() async throws {
        let (model, keys) = try await onboarded(appLock: true)
        let store = try #require(model.store)
        let second = AppModel(keys: keys, makeStore: { store })
        second.protectedDataAvailable = { true }
        await second.load()
        #expect(second.phase == .ready)
        #expect(second.locked)
        #expect(second.dbKey == nil)
        #expect(keys.prompts.isEmpty)
    }

    @Test func unlockPromptsAndDecrypts() async throws {
        let (model, keys) = try await onboarded()
        model.lock()
        #expect(model.locked)
        let unlocked = await model.unlock()
        #expect(unlocked)
        #expect(keys.prompts.contains(prompt))
        #expect(model.dbKey != nil)
        #expect(!model.locked)
        #expect(model.error == nil)
    }

    @Test func unlockCancelledStaysLocked() async throws {
        let (model, keys) = try await onboarded()
        model.lock()
        keys.failNextRead = .cancelled
        let unlocked = await model.unlock()
        #expect(!unlocked)
        #expect(model.locked)
        #expect(model.error == .cancelled)
        #expect(model.people.isEmpty)
        #expect(model.dbKey == nil)
    }

    @Test func lockClearsPeopleUnlessAppLockOff() async throws {
        let (model, _) = try await onboarded(appLock: true)
        #expect(!model.locked)
        model.lock()
        #expect(model.locked)
        #expect(model.dbKey == nil)
        #expect(model.people.isEmpty)

        let (open, _) = try await onboarded(appLock: false)
        open.lock()
        #expect(!open.locked)
        #expect(open.dbKey != nil)
    }

    @Test func protectedDataUnavailableWaits() async throws {
        let model = try AppModel.inMemory()
        model.protectedDataAvailable = { false }
        let loading = Task { await model.load() }
        var spins = 0
        while model.phase != .protectedDataUnavailable, spins < 1000 {
            await Task.yield()
            spins += 1
        }
        #expect(model.phase == .protectedDataUnavailable)
        #expect(model.store == nil)
        model.protectedDataAvailable = { true }
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        await loading.value
        #expect(model.phase == .onboarding)
        #expect(model.store != nil)
    }

    @Test func scenePhaseTransitions() async throws {
        let (model, _) = try await onboarded(appLock: true)
        model.scenePhase(.inactive)
        #expect(model.covered)
        model.scenePhase(.active)
        #expect(!model.covered)
        #expect(!model.locked)
        model.scenePhase(.background)
        #expect(model.locked)
        #expect(model.dbKey == nil)
    }

    @Test func identityDerivesFromSeed() async throws {
        let (model, keys) = try await onboarded()
        let stored = try #require(keys.items[KeyName.seed])
        #expect(try model.identity().seed == Array(stored.data))
        #expect(try model.identity() == Identity(seed: Array(stored.data)))
    }

    @Test func requireKeyUnlocksOrCancels() async throws {
        let (model, keys) = try await onboarded()
        model.lock()
        let key = try await model.requireKey()
        let stored = try #require(keys.items[KeyName.database])
        #expect(key.withUnsafeBytes { Data($0) } == stored.data)
        #expect(!model.locked)
        #expect(keys.prompts == [prompt])
        model.lock()
        keys.failNextRead = .cancelled
        await #expect(throws: AppError.cancelled) {
            try await model.requireKey()
        }
    }

    @Test func resetAfterEraseClearsState() async throws {
        let (model, _) = try await onboarded()
        model.resetAfterErase()
        #expect(model.store == nil)
        #expect(model.phase == .onboarding)
        #expect(model.personas.isEmpty)
        #expect(model.profile == Profile())
        #expect(model.settings == Hatband.Settings())
        #expect(model.locked)
        #expect(model.dbKey == nil)
        try model.finishOnboarding(profile: sampleProfile(), appLock: false)
        #expect(model.phase == .ready)
        #expect(model.store != nil)
    }

    @Test func errorMapping() {
        #expect(AppError(HB1.Error.notHatband) == .notHatband)
        #expect(AppError(HB1.Error.badMagic) == .notHatband)
        #expect(AppError(HB1.Error.tooLarge(40_000)) == .tooLarge)
        #expect(AppError(HB1.Error.unsupportedFormat("9")) == .unsupportedFormat)
        #expect(AppError(KeyStoreError.cancelled) == .cancelled)
        #expect(AppError(KeyStoreError.failed(-25300)) == .keychain(-25300))
        #expect(AppError(ExportError.wrongPassphraseOrTampered) == .wrongPassphrase)
        #expect(AppError(ExportError.tooLarge) == .tooLarge)
        #expect(AppError(AppError.activitiesDisabled) == .activitiesDisabled)
        #expect(AppError(CodecError.unsupportedVersion(3)) == .storage("Stored data version 3 is newer than this app"))
    }
}
