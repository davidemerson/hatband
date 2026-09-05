import CryptoKit
import Foundation
import HatbandCore
import LocalAuthentication
import SwiftUI
import UIKit

/// The one model. State, lifecycle and lock live here; cards, sharing,
/// people and backup are extensions in their own files.
@MainActor @Observable final class AppModel {
    nonisolated enum Phase: Equatable {
        case loading, protectedDataUnavailable, storeUnavailable, onboarding, ready
    }

    nonisolated struct Sharing: Equatable {
        var personaID: [UInt8]
        var endsAt: Date
    }

    var phase: Phase = .loading
    var profile = Profile()
    var personas: [Persona] = []
    var settings = Settings()
    var selectedPersonaID: [UInt8]?
    /// People, Where and Settings show `LockedView` while true.
    var locked = true
    /// Empty while locked.
    var people: [Person] = []
    var sharing: Sharing?
    /// Drives `ReviewSheet` via `.sheet(item:)`.
    var pendingReview: Review?
    /// Drives the import passphrase sheet.
    var pendingImport: Data?
    var route = Route()
    /// The forget buffer, kept for `undoWindow`; emptied by `lock()`.
    var undo: Person?
    /// Advances on every `forget` and `restoreForgotten`, so an expiry timer
    /// started for an earlier forget never clears a later one.
    var undoGeneration = 0
    /// A card, export or route that arrived before `phase` allowed it,
    /// performed once by `performDeferredOpen()`.
    var deferredOpen: DeferredOpen?
    var error: AppError?
    /// `PrivacyCover`: scene inactive or screen captured.
    var covered = false
    /// Nil while locked.
    var dbKey: SymmetricKey?
    /// The signing identity: read from the Keychain by `load()`, set by
    /// onboarding and restore, dropped by an erase. Held so a card is built
    /// without a Keychain call; the seed item never prompts.
    var signingIdentity: Identity?
    /// The persona-index counter as stored, nil until a persona has been
    /// added after onboarding: read by `load()`, written through by
    /// `storePersonaIndex`. `personaIndexKnown` stays false until a read
    /// has succeeded, so an index is never allotted on a guess.
    var personaIndexCounter: UInt32?
    var personaIndexKnown = false
    /// Nil means the App Group container.
    var widgetDirectory: URL?
    var undoWindow: Duration = .seconds(10)

    let keys: any KeyStore
    private(set) var store: Store?
    var protectedDataAvailable: () -> Bool
    private let makeStore: () throws -> Store
    /// The activation in flight, shared by a second `.active` that lands
    /// before it settles, so `load()` cannot run twice.
    @ObservationIgnored private var activation: Task<Void, Never>?
    /// The unlock in flight, shared by every caller until it settles, so a
    /// second tap while the prompt is up does not ask again.
    @ObservationIgnored private var unlocking: Task<Bool, Never>?

    init(keys: any KeyStore, makeStore: @escaping () throws -> Store) {
        self.keys = keys
        self.makeStore = makeStore
        self.protectedDataAvailable = { UIApplication.shared.isProtectedDataAvailable }
    }

    static func live() -> AppModel {
        AppModel(keys: KeychainStore(), makeStore: { try Store.onDisk() })
    }

    /// A memory key store, an in-memory store, a temp widget directory
    /// and a short undo window.
    static func inMemory() throws -> AppModel {
        let model = AppModel(keys: MemoryKeyStore(), makeStore: { try Store.inMemory() })
        model.protectedDataAvailable = { true }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Widget-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.widgetDirectory = directory
        model.undoWindow = .milliseconds(50)
        return model
    }

    /// Eight random bytes for a new persona.
    static func randomPersonaID() -> [UInt8] {
        var bytes: [UInt8] = []
        for _ in 0..<8 {
            bytes.append(UInt8.random(in: 0...255))
        }
        return bytes
    }

    /// Four big-endian bytes, as `storePersonaIndex` writes them; nil for
    /// anything else.
    nonisolated static func personaIndex(from data: Data?) -> UInt32? {
        guard let data, data.count == 4 else { return nil }
        let bytes = Array(data)
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    // MARK: - Lifecycle

    func scenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            covered = false
            Task { await self.activate() }
        case .inactive:
            covered = true
        case .background:
            lock()
            Screen.restoreBrightness()
        @unknown default:
            break
        }
    }

    /// Loads on the first activation; afterwards re-asserts protection,
    /// reads what a failed Keychain read left behind, and reconciles
    /// activities. Calls that overlap share one run.
    func activate() async {
        if let activation {
            return await activation.value
        }
        let task = Task { await self.performActivation() }
        activation = task
        await task.value
        activation = nil
    }

    private func performActivation() async {
        if store == nil {
            await load()
            return
        }
        store?.reassertProtection()
        if (phase == .ready && signingIdentity == nil) || !personaIndexKnown {
            await loadKeychainState()
        }
        await reconcileActivities()
    }

    /// Opens the store once protected data is available, waiting for the
    /// notification otherwise, reads the Keychain items that never prompt,
    /// and reads the owner blob.
    func load() async {
        guard protectedDataAvailable() else {
            phase = .protectedDataUnavailable
            await ProtectedDataWaiter().wait()
            return await load()
        }
        do {
            let store = try openStore()
            // Before `.ready`, so the Card tab never draws without them.
            await loadKeychainState()
            if let record = try store.owner() {
                let owner = try OwnerCodec.decode(Array(record.blob))
                profile = owner.profile
                personas = owner.personas
                settings = owner.settings
                selectedPersonaID = personas.first { $0.id == settings.lastPersonaID }?.id ?? personas.first?.id
                phase = .ready
            } else {
                phase = .onboarding
            }
            try store.setExcludedFromBackup(!settings.includeInBackup)
        } catch {
            // The store could not open; RootView offers a retry.
            phase = .storeUnavailable
            self.error = AppError(error)
            Log.failure("load", error)
            return
        }
        if phase == .ready, !settings.appLock {
            _ = await unlock()
        }
        await reconcileActivities()
        refreshWidget()
        performDeferredOpen()
    }

    /// Reads the seed and the persona-index counter into memory. A failed
    /// read is logged, not fatal: `identity()` and `storedPersonaIndex()`
    /// throw until `activate()` reads again.
    func loadKeychainState() async {
        do {
            let data = try await keys.read(KeyName.seed, prompt: nil)
            signingIdentity = try data.map { try Identity(seed: Array($0)) }
        } catch {
            Log.failure("read seed", error)
        }
        do {
            let data = try await keys.read(KeyName.personaIndex, prompt: nil)
            personaIndexCounter = AppModel.personaIndex(from: data)
            personaIndexKnown = true
        } catch {
            Log.failure("read persona index", error)
        }
    }

    /// Reads the database key, prompting when app lock is on, and decrypts
    /// every person. False, with `error` set, when that fails. Calls that
    /// overlap share one prompt and one answer.
    func unlock() async -> Bool {
        if let unlocking {
            return await unlocking.value
        }
        let task = Task { await self.performUnlock() }
        unlocking = task
        let unlocked = await task.value
        unlocking = nil
        return unlocked
    }

    private func performUnlock() async -> Bool {
        do {
            guard let data = try await keys.read(KeyName.database, prompt: "Unlock the people you have scanned.") else {
                throw AppError.storage("No database key")
            }
            let key = SymmetricKey(data: data)
            var loaded: [Person] = []
            if let store {
                for record in try store.people() {
                    let aad = Sealer.aad(domain: Sealer.personDomain, id: record.personaID)
                    let bytes = try Sealer.open(record.sealed, key: key, aad: aad)
                    loaded.append(try PersonCodec.decode(bytes))
                }
            }
            dbKey = key
            // Oldest first, so `people(matching:)` can break timestamp ties by position.
            people = loaded.sorted { ($0.updatedAt, $0.createdAt) < ($1.updatedAt, $1.createdAt) }
            locked = false
            return true
        } catch {
            self.error = AppError(error)
            return false
        }
    }

    /// No-op when app lock is off. The forget buffer goes with the people:
    /// a decrypted person does not outlive the lock.
    func lock() {
        guard settings.appLock else { return }
        dbKey = nil
        people = []
        undo = nil
        undoGeneration += 1
        locked = true
    }

    func canUseAppLock() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Generates the identity and database key, writes both, creates the
    /// first persona and saves the owner. Leaves the model unlocked.
    func finishOnboarding(profile: Profile, appLock: Bool) throws {
        let identity = Identity.generate()
        try keys.write(KeyName.seed, Data(identity.seed), access: .seed)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try keys.write(KeyName.database, keyData, access: .database(appLock: appLock, includeInBackup: false))
        signingIdentity = identity
        let persona = Persona(id: AppModel.randomPersonaID(), label: "Personal", keyIndex: 0, color: 1,
                              channels: profile.presentChannels)
        var settings = Settings()
        settings.appLock = appLock
        settings.lastPersonaID = persona.id
        self.profile = profile
        self.personas = [persona]
        self.settings = settings
        self.selectedPersonaID = persona.id
        try saveOwner()
        dbKey = key
        people = []
        locked = false
        phase = .ready
        performDeferredOpen()
    }

    /// Encodes the owner blob into the single `OwnerRecord` and saves.
    func saveOwner() throws {
        let store = try openStore()
        let blob = Data(OwnerCodec.encode(profile: profile, personas: personas, settings: settings))
        if let record = try store.owner() {
            record.blob = blob
        } else {
            store.insert(OwnerRecord(blob: blob))
        }
        try store.save()
        store.reassertProtection()
    }

    /// The identity `load()` read, or onboarding or a restore set. Throws
    /// until then.
    func identity() throws -> Identity {
        guard let signingIdentity else { throw AppError.storage("No identity") }
        return signingIdentity
    }

    /// The database key, unlocking first when needed. `.cancelled` when
    /// the user declines.
    func requireKey() async throws -> SymmetricKey {
        if let dbKey {
            return dbKey
        }
        guard await unlock(), let dbKey else { throw AppError.cancelled }
        return dbKey
    }

    /// After `store.erase()`: drops the store, removes its directory and
    /// resets every piece of state. The Keychain items are gone, so the
    /// counter is known to be absent.
    func resetAfterErase() {
        let directory = store?.directory
        store = nil
        if let directory {
            Store.removeDirectory(at: directory)
        }
        profile = Profile()
        personas = []
        settings = Settings()
        selectedPersonaID = nil
        locked = true
        people = []
        sharing = nil
        pendingReview = nil
        pendingImport = nil
        route = Route()
        undo = nil
        undoGeneration += 1
        deferredOpen = nil
        error = nil
        covered = false
        dbKey = nil
        signingIdentity = nil
        personaIndexCounter = nil
        personaIndexKnown = true
        phase = .onboarding
    }

    // MARK: - Private

    /// The open store, opening it on first use (after `load()` or after an
    /// erase, when onboarding runs again).
    private func openStore() throws -> Store {
        if let store {
            return store
        }
        let store = try makeStore()
        self.store = store
        store.reassertProtection()
        // A directory created here (onboarding again after an erase) must
        // start outside backups now, not at the next launch.
        try store.setExcludedFromBackup(!settings.includeInBackup)
        return store
    }
}

/// Suspends until `protectedDataDidBecomeAvailableNotification` is posted.
@MainActor private final class ProtectedDataWaiter: NSObject {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            NotificationCenter.default.addObserver(
                self, selector: #selector(didBecomeAvailable),
                name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        }
    }

    @objc private func didBecomeAvailable() {
        NotificationCenter.default.removeObserver(self)
        continuation?.resume()
        continuation = nil
    }
}
