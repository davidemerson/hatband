import CryptoKit
import Foundation
import HatbandCore

/// Export, import, the three settings toggles, and erase.
extension AppModel {
    nonisolated enum ImportMode {
        case restore, merge
    }

    /// Restore: totals. Merge: personas added or replaced, people added or
    /// changed, encounters added, and people whose imported key differed
    /// from the local pin (which stays).
    nonisolated struct ImportSummary: Equatable {
        var personas: Int
        var people: Int
        var encounters: Int
        var keyChanges: Int
    }

    /// Test hook: PBKDF2 rounds for exports; the container's default in production.
    static var exportIterations = ExportContainer.defaultIterations

    static let protectionPrompt = "Confirm the change to how the people you have scanned are protected."

    // MARK: - Export

    /// Seed, owner blob, every person body and the persona-index counter,
    /// sealed under the passphrase off the main actor. Unlocks first, so
    /// app lock prompts.
    func exportData(passphrase: String) async throws -> Data {
        guard phase == .ready else { throw AppError.storage("Nothing to export yet.") }
        _ = try await requireKey()
        let bundle: ExportBundle
        do {
            let seed = try identity().seed
            let owner = OwnerCodec.encode(profile: profile, personas: personas, settings: settings)
            let nextKeyIndex = try nextPersonaIndex()
            bundle = ExportBundle(seed: seed, owner: owner, people: people.map { PersonCodec.encode($0) },
                                  nextKeyIndex: nextKeyIndex)
        } catch {
            throw AppError(error)
        }
        let iterations = AppModel.exportIterations
        do {
            let sealed = try await Task.detached(priority: .userInitiated) {
                try ExportBundle.seal(bundle, passphrase: passphrase, iterations: iterations)
            }.value
            Log.event("export sealed")
            return Data(sealed)
        } catch {
            throw AppError(error)
        }
    }

    // MARK: - Import

    /// Opens the container off the main actor, then restores or merges.
    /// Every error comes back as an `AppError`.
    func importData(_ data: Data, passphrase: String, mode: ImportMode) async throws -> ImportSummary {
        let container = Array(data)
        let bundle: ExportBundle
        do {
            bundle = try await Task.detached(priority: .userInitiated) {
                try ExportBundle.open(container, passphrase: passphrase)
            }.value
        } catch {
            throw AppError(error)
        }
        do {
            let owner = try OwnerCodec.decode(bundle.owner)
            let imported = try bundle.people.map { try PersonCodec.decode($0) }
            switch mode {
            case .restore:
                return try restore(seed: bundle.seed, owner: owner, people: imported, nextKeyIndex: bundle.nextKeyIndex)
            case .merge:
                return try await merge(owner: owner, people: imported, nextKeyIndex: bundle.nextKeyIndex)
            }
        } catch {
            throw AppError(error)
        }
    }

    /// Onto a fresh Hatband: the seed, a fresh database key and the
    /// persona-index counter go into the Keychain, the owner is replaced,
    /// every person is sealed under the new key, and the model comes up
    /// ready and unlocked.
    private func restore(seed: [UInt8], owner: (profile: Profile, personas: [Persona], settings: Settings),
                         people imported: [Person], nextKeyIndex: UInt32?) throws -> ImportSummary {
        guard phase == .onboarding else {
            throw AppError.storage("Restore only into a fresh Hatband. Erase everything first, or merge instead.")
        }
        let identity = try Identity(seed: seed)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try keys.write(KeyName.seed, Data(identity.seed), access: .seed)
        try keys.write(KeyName.database, keyData,
                       access: .database(appLock: owner.settings.appLock, includeInBackup: owner.settings.includeInBackup))
        // The counter travels with the seed, so an index a deleted persona
        // held is never derived again here; an older export starts past
        // the highest index it carries, and a counter left behind is kept.
        let carried = nextKeyIndex ?? BackupMerge.nextKeyIndex(after: owner.personas)
        let leftBehind = try storedPersonaIndex() ?? 0
        try storePersonaIndex(max(carried, leftBehind))
        profile = owner.profile
        personas = owner.personas
        settings = owner.settings
        selectedPersonaID = personas.first { $0.id == settings.lastPersonaID }?.id ?? personas.first?.id
        try saveOwner()
        let store = try openedStore()
        for record in try store.people() {
            store.delete(record)
        }
        for person in imported {
            store.insert(try sealedRecord(person, key: key))
        }
        try store.save()
        store.reassertProtection()
        try store.setExcludedFromBackup(!settings.includeInBackup)
        dbKey = key
        people = imported
        locked = false
        phase = .ready
        refreshWidget()
        performDeferredOpen()
        Log.event("restore")
        return ImportSummary(personas: personas.count, people: imported.count,
                             encounters: imported.reduce(0) { $0 + $1.encounters.count }, keyChanges: 0)
    }

    /// Into what is here: the local seed stays, personas and people merge
    /// by id (`BackupMerge`), the persona-index counter becomes the higher
    /// of the two, and everything is re-sealed under this device's key.
    private func merge(owner: (profile: Profile, personas: [Persona], settings: Settings),
                       people imported: [Person], nextKeyIndex: UInt32?) async throws -> ImportSummary {
        guard phase == .ready else { throw AppError.storage("Set up Hatband before merging an export.") }
        let key = try await requireKey()
        let ownCounter = try nextPersonaIndex()
        let counter = max(ownCounter, nextKeyIndex ?? BackupMerge.nextKeyIndex(after: owner.personas))
        let personaResult = BackupMerge.personas(local: personas, imported: owner.personas, nextKeyIndex: counter)
        // Whole seconds, as `PersonCodec` stores dates, so what is held in
        // memory equals what reloads.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let peopleResult = BackupMerge.people(local: people, imported: imported, now: now)
        personas = personaResult.personas
        try storePersonaIndex(personaResult.nextKeyIndex)
        try saveOwner()
        let store = try openedStore()
        var records: [Data: PersonRecord] = [:]
        for record in try store.people() {
            records[record.personaID] = record
        }
        for person in peopleResult.people {
            let fresh = try sealedRecord(person, key: key)
            if let record = records[fresh.personaID] {
                record.sealed = fresh.sealed
                record.updatedAt = fresh.updatedAt
            } else {
                store.insert(fresh)
            }
        }
        try store.save()
        store.reassertProtection()
        people = peopleResult.people
        refreshWidget()
        Log.event("merge")
        return ImportSummary(personas: personaResult.changed, people: peopleResult.added + peopleResult.updated,
                             encounters: peopleResult.encountersAdded, keyChanges: peopleResult.keyChanges)
    }

    // MARK: - Settings

    /// Reads the database key with a prompt and rewrites it under the new
    /// access, then persists the setting.
    func setAppLock(_ on: Bool) async throws {
        do {
            let data = try readDatabaseKeyWithPrompt()
            try keys.write(KeyName.database, data, access: .database(appLock: on, includeInBackup: settings.includeInBackup))
            settings.appLock = on
            try saveOwner()
        } catch {
            throw AppError(error)
        }
    }

    /// As `setAppLock`, and the store follows the choice.
    func setIncludeInBackup(_ on: Bool) async throws {
        do {
            let data = try readDatabaseKeyWithPrompt()
            try keys.write(KeyName.database, data, access: .database(appLock: settings.appLock, includeInBackup: on))
            settings.includeInBackup = on
            try saveOwner()
            try store?.setExcludedFromBackup(!on)
        } catch {
            throw AppError(error)
        }
    }

    func setHomeWidget(_ on: Bool) throws {
        settings.homeWidget = on
        do {
            try saveOwner()
        } catch {
            throw AppError(error)
        }
        refreshWidget()
    }

    // MARK: - Erase

    /// Keys first, so the sealed rows are unreadable even if the rest
    /// fails; then activities, the widget feed (and its reload), files
    /// left for the share sheet, the store and its directory. Ends at
    /// onboarding.
    func eraseEverything() async {
        do {
            try keys.delete(KeyName.database)
            try keys.delete(KeyName.seed)
            try keys.delete(KeyName.personaIndex)
        } catch {
            Log.failure("erase keys", error)
        }
        await stopSharing()
        clearWidget()
        TransferredFiles.sweep()
        if let store {
            do {
                try store.erase()
            } catch {
                Log.failure("erase store", error)
            }
        }
        Diagnostics.removeAll()
        resetAfterErase()
        Log.event("erased")
    }

    // MARK: - Private

    private func readDatabaseKeyWithPrompt() throws -> Data {
        guard let data = try keys.read(KeyName.database, prompt: AppModel.protectionPrompt) else {
            throw AppError.storage("No database key")
        }
        return data
    }

    private func openedStore() throws -> Store {
        guard let store else { throw AppError.storage("The store is not open") }
        return store
    }

    private func sealedRecord(_ person: Person, key: SymmetricKey) throws -> PersonRecord {
        let id = Data(person.personaID)
        let aad = Sealer.aad(domain: Sealer.personDomain, id: id)
        let sealed = try Sealer.seal(PersonCodec.encode(person), key: key, aad: aad)
        return PersonRecord(personaID: id, updatedAt: person.updatedAt, sealed: sealed)
    }
}
