import CryptoKit
import Foundation
import HatbandCore
import Testing
@testable import Hatband

private let passphrase = "correct horse battery staple"
private let unlockPrompt = "Unlock the people you have scanned."
private let dedalusID: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
private let mollyID: [UInt8] = [9, 9, 9, 9, 9, 9, 9, 9]

private func encounter(_ seconds: TimeInterval, _ label: String) -> Encounter {
    Encounter(id: UUID(), date: Date(timeIntervalSince1970: seconds),
              fix: Fix(latitude: 53.3498, longitude: -6.2603, accuracy: 5000), label: label, note: "")
}

/// A signed file-form card from `identity`, as a scan would store it.
private func makePerson(identity: Identity, personaID: [UInt8], name: String, seq: UInt32,
                        encounters: [Encounter]) throws -> Person {
    var profile = Profile()
    profile.name = name
    profile.email = "someone@example.ie"
    let persona = Persona(id: personaID, label: "Personal", keyIndex: 0, color: 3, channels: [.email], seq: seq)
    let key = identity.personaSigningKey(index: 0)
    let card = try CardBuilder.card(profile: profile, persona: persona, form: .file, issuedDay: 2400).signed(with: key)
    let publicKey = try #require(card.publicKey)
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    return Person(personaID: personaID, cardBytes: card.cbor.encoded, card: card, publicKey: publicKey,
                  keyFingerprint: KeyFingerprint(publicKey: publicKey)?.short, trust: .inPerson, source: .scan,
                  tags: ["conference"], note: "", gpgKey: nil, createdAt: created, updatedAt: created,
                  encounters: encounters)
}

private func byID(_ people: [Person]) -> [Person] {
    people.sorted { $0.id < $1.id }
}

@MainActor struct AppModelBackupTests {
    private func sampleProfile(_ name: String) -> Profile {
        var profile = Profile()
        profile.name = name
        profile.email = "bloom@example.ie"
        profile.phone = "+353871234567"
        return profile
    }

    private func onboarded(appLock: Bool = true, name: String = "Leopold Bloom") async throws -> (AppModel, MemoryKeyStore) {
        AppModel.exportIterations = ExportContainer.iterationRange.lowerBound
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(name), appLock: appLock)
        let keys = try #require(model.keys as? MemoryKeyStore)
        return (model, keys)
    }

    /// Through A's seams: seal, insert, save, then reload by unlocking.
    private func seed(_ people: [Person], into model: AppModel) async throws {
        let store = try #require(model.store)
        let key = try #require(model.dbKey)
        for person in people {
            let id = Data(person.personaID)
            let aad = Sealer.aad(domain: Sealer.personDomain, id: id)
            let sealed = try Sealer.seal(PersonCodec.encode(person), key: key, aad: aad)
            store.insert(PersonRecord(personaID: id, updatedAt: person.updatedAt, sealed: sealed))
        }
        try store.save()
        let unlocked = await model.unlock()
        #expect(unlocked)
    }

    /// A model over the same store instance, as after a relaunch.
    private func relaunched(_ model: AppModel, keys: MemoryKeyStore) async throws -> AppModel {
        let store = try #require(model.store)
        let again = AppModel(keys: keys, makeStore: { store })
        again.protectedDataAvailable = { true }
        await again.load()
        return again
    }

    @Test func exportRestoreReproducesEverything() async throws {
        let (source, sourceKeys) = try await onboarded(appLock: true)
        source.settings.durationMinutes = 30
        source.settings.showNameOnLockScreen = false
        try source.saveOwner()
        let dedalus = try makePerson(identity: Identity.generate(), personaID: dedalusID, name: "Stephen Dedalus", seq: 2,
                                     encounters: [encounter(1_700_000_000, "Martello tower"), encounter(1_700_100_000, "Sandymount")])
        let molly = try makePerson(identity: Identity.generate(), personaID: mollyID, name: "Molly Bloom", seq: 1,
                                   encounters: [encounter(1_700_200_000, "Gibraltar")])
        try await seed([dedalus, molly], into: source)
        let data = try await source.exportData(passphrase: passphrase)
        #expect(!data.isEmpty)

        let restored = try AppModel.inMemory()
        await restored.load()
        #expect(restored.phase == .onboarding)
        let summary = try await restored.importData(data, passphrase: passphrase, mode: .restore)
        #expect(summary == AppModel.ImportSummary(personas: 1, people: 2, encounters: 3, keyChanges: 0))
        #expect(restored.phase == .ready)
        #expect(!restored.locked)
        #expect(restored.dbKey != nil)
        #expect(try restored.identity() == source.identity())
        #expect(restored.profile == source.profile)
        #expect(restored.personas == source.personas)
        #expect(restored.settings == source.settings)
        #expect(restored.selectedPersonaID == source.selectedPersonaID)
        #expect(byID(restored.people) == byID(source.people))
        let restoredKeys = try #require(restored.keys as? MemoryKeyStore)
        #expect(restoredKeys.items[KeyName.seed]?.data == sourceKeys.items[KeyName.seed]?.data)
        #expect(restoredKeys.items[KeyName.seed]?.access == .seed)
        #expect(restoredKeys.items[KeyName.database]?.data != sourceKeys.items[KeyName.database]?.data)
        #expect(restoredKeys.items[KeyName.database]?.access == .database(appLock: true, includeInBackup: false))
        #expect(try restored.store?.people().count == 2)

        let third = try await relaunched(restored, keys: restoredKeys)
        #expect(third.phase == .ready)
        #expect(third.locked)
        #expect(third.personas == source.personas)
        #expect(third.settings == source.settings)
        #expect(third.profile == source.profile)
        let unlocked = await third.unlock()
        #expect(unlocked)
        #expect(byID(third.people) == byID(source.people))
        #expect(try third.identity() == source.identity())
    }

    @Test func mergeKeepsLocalSeedAndDedupes() async throws {
        let (source, _) = try await onboarded(name: "Leopold Bloom")
        let (target, targetKeys) = try await onboarded(name: "Henry Flower")
        let dedalusIdentity = Identity.generate()
        let shared = encounter(1_700_000_000, "Martello tower")
        let onlySource = encounter(1_700_100_000, "Sandymount")
        let onlyTarget = encounter(1_700_300_000, "Eccles Street")
        let gibraltar = encounter(1_700_200_000, "Gibraltar")
        let newer = try makePerson(identity: dedalusIdentity, personaID: dedalusID, name: "Stephen Dedalus", seq: 5,
                                   encounters: [shared, onlySource])
        let older = try makePerson(identity: dedalusIdentity, personaID: dedalusID, name: "Stephen Dedalus", seq: 3,
                                   encounters: [shared, onlyTarget])
        let molly = try makePerson(identity: Identity.generate(), personaID: mollyID, name: "Molly Bloom", seq: 1,
                                   encounters: [gibraltar])
        try await seed([newer, molly], into: source)
        try await seed([older], into: target)
        let seedBefore = try #require(targetKeys.items[KeyName.seed]).data
        let targetPersona = try #require(target.personas.first)
        let sourcePersona = try #require(source.personas.first)

        let data = try await source.exportData(passphrase: passphrase)
        let summary = try await target.importData(data, passphrase: passphrase, mode: .merge)
        #expect(targetKeys.items[KeyName.seed]?.data == seedBefore)
        #expect(try target.identity() != source.identity())
        #expect(summary == AppModel.ImportSummary(personas: 1, people: 2, encounters: 2, keyChanges: 0))
        #expect(target.personas.map { $0.id } == [targetPersona.id, sourcePersona.id])
        #expect(target.personas[0] == targetPersona)
        #expect(target.personas[1].keyIndex == 1)
        #expect(target.people.count == 2)
        let dedalus = try #require(target.people.first { $0.personaID == dedalusID })
        #expect(dedalus.card.seq == 5)
        #expect(dedalus.card.signatureIsValid)
        #expect(dedalus.encounters.map { $0.id } == [shared.id, onlySource.id, onlyTarget.id])
        #expect(target.people.contains { $0.personaID == mollyID })
        #expect(!target.locked)

        let again = try await relaunched(target, keys: targetKeys)
        #expect(again.personas == target.personas)
        let unlocked = await again.unlock()
        #expect(unlocked)
        #expect(byID(again.people) == byID(target.people))
        let stored = try #require(again.people.first { $0.personaID == dedalusID })
        #expect(stored.card.seq == 5)
        #expect(stored.encounters.count == 3)
    }

    @Test func mergeCountsKeyChangesAndKeepsLocalPin() async throws {
        let (source, _) = try await onboarded(name: "Leopold Bloom")
        let (target, targetKeys) = try await onboarded(name: "Henry Flower")
        let pinned = Identity.generate()
        let impostor = Identity.generate()
        let meeting = encounter(1_700_000_000, "Davy Byrne's")
        let theirs = try makePerson(identity: impostor, personaID: dedalusID, name: "Stephen Dedalus", seq: 9,
                                    encounters: [meeting])
        let mine = try makePerson(identity: pinned, personaID: dedalusID, name: "Stephen Dedalus", seq: 3, encounters: [])
        try await seed([theirs], into: source)
        try await seed([mine], into: target)

        let data = try await source.exportData(passphrase: passphrase)
        let summary = try await target.importData(data, passphrase: passphrase, mode: .merge)
        #expect(summary.keyChanges == 1)
        #expect(summary.people == 1)
        #expect(summary.encounters == 1)
        #expect(target.people.count == 1)
        let dedalus = try #require(target.people.first)
        #expect(dedalus.publicKey == mine.publicKey)
        #expect(dedalus.publicKey == Array(pinned.personaSigningKey(index: 0).publicKey.rawRepresentation))
        #expect(dedalus.card.seq == 3)
        #expect(dedalus.cardBytes == mine.cardBytes)
        #expect(dedalus.trust == .inPerson)
        #expect(dedalus.encounters.map { $0.id } == [meeting.id])

        let again = try await relaunched(target, keys: targetKeys)
        let unlocked = await again.unlock()
        #expect(unlocked)
        #expect(again.people.first?.publicKey == mine.publicKey)
    }

    /// Key indices are never reused, on this phone or one restored from it:
    /// the counter rides in the export, so a persona added after a restore
    /// takes an index above every one the old phone ever handed out. An
    /// export from before the counter travelled starts past what it carries.
    @Test func restoreCarriesThePersonaIndexCounter() async throws {
        let (source, sourceKeys) = try await onboarded()
        let work = try source.addPersona(label: "Work", alias: false)
        let other = try source.addPersona(label: "Other", alias: false)
        #expect(work.keyIndex == 1 && other.keyIndex == 2)
        try source.delete(persona: other)
        #expect(source.personas.map { $0.keyIndex } == [0, 1])
        #expect(sourceKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 3]))
        let data = try await source.exportData(passphrase: passphrase)
        let bundle = try ExportBundle.open(Array(data), passphrase: passphrase)
        #expect(bundle.nextKeyIndex == 3)

        let restored = try AppModel.inMemory()
        await restored.load()
        _ = try await restored.importData(data, passphrase: passphrase, mode: .restore)
        let restoredKeys = try #require(restored.keys as? MemoryKeyStore)
        #expect(restoredKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 3]))
        #expect(restoredKeys.items[KeyName.personaIndex]?.access == .seed)
        let added = try restored.addPersona(label: "New", alias: false)
        #expect(added.keyIndex == 3)
        #expect(added.keyIndex > other.keyIndex)
        let deletedKey = Array(try source.identity().personaSigningKey(index: other.keyIndex).publicKey.rawRepresentation)
        #expect(try restored.card(for: added, form: .fullQR).publicKey != deletedKey)
        #expect(restoredKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 4]))

        var older = bundle
        older.nextKeyIndex = nil
        let olderData = Data(try ExportBundle.seal(older, passphrase: passphrase,
                                                   iterations: ExportContainer.iterationRange.lowerBound))
        let legacy = try AppModel.inMemory()
        await legacy.load()
        _ = try await legacy.importData(olderData, passphrase: passphrase, mode: .restore)
        let legacyKeys = try #require(legacy.keys as? MemoryKeyStore)
        #expect(legacyKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 2]))
        #expect(try legacy.addPersona(label: "New", alias: false).keyIndex == 2)
    }

    /// Merging takes the higher of the two counters: a persona moved off a
    /// colliding index lands above both, the next one added above that,
    /// and a lower imported counter leaves the local one alone.
    @Test func mergeTakesTheHigherCounter() async throws {
        let (source, _) = try await onboarded(name: "Leopold Bloom")
        let (target, targetKeys) = try await onboarded(name: "Henry Flower")
        for label in ["Work", "Club", "Press", "Lodge"] {
            _ = try source.addPersona(label: label, alias: false)
        }
        while source.personas.count > 1 {
            let last = try #require(source.personas.last)
            try source.delete(persona: last)
        }
        #expect(source.personas.map { $0.keyIndex } == [0])
        let data = try await source.exportData(passphrase: passphrase)
        #expect(try ExportBundle.open(Array(data), passphrase: passphrase).nextKeyIndex == 5)
        let spare = try target.addPersona(label: "Spare", alias: false)
        try target.delete(persona: spare)
        #expect(targetKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 2]))

        let summary = try await target.importData(data, passphrase: passphrase, mode: .merge)
        #expect(summary.personas == 1)
        #expect(target.personas.map { $0.keyIndex } == [0, 5])
        #expect(targetKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 6]))
        #expect(try target.addPersona(label: "New", alias: false).keyIndex == 6)

        let (fresh, _) = try await onboarded(name: "Molly Bloom")
        let freshData = try await fresh.exportData(passphrase: passphrase)
        #expect(try ExportBundle.open(Array(freshData), passphrase: passphrase).nextKeyIndex == 1)
        _ = try await target.importData(freshData, passphrase: passphrase, mode: .merge)
        #expect(target.personas.map { $0.keyIndex } == [0, 5, 6, 7])
        #expect(targetKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 8]))
        let again = try await relaunched(target, keys: targetKeys)
        #expect(again.personas.map { $0.keyIndex } == [0, 5, 6, 7])
        #expect(try again.addPersona(label: "Later", alias: false).keyIndex == 8)
    }

    /// A persona merged from another phone's identity never lands on an
    /// index this phone retired: under the seed that stays, that index is
    /// the deleted persona's key. Merged from this identity, an index still
    /// names the key it always did and is kept.
    @Test func mergeFromAnotherSeedNeverReusesARetiredIndex() async throws {
        let (source, _) = try await onboarded(name: "Leopold Bloom")
        _ = try source.addPersona(label: "Work", alias: false)
        #expect(source.personas.map { $0.keyIndex } == [0, 1])
        let data = try await source.exportData(passphrase: passphrase)

        let (target, targetKeys) = try await onboarded(name: "Henry Flower")
        let spare = try target.addPersona(label: "Spare", alias: false)
        try target.delete(persona: spare)
        let retiredCard = try target.card(for: spare, form: .fullQR)
        let retired = try #require(retiredCard.publicKey)
        #expect(targetKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 2]))
        #expect(try target.identity() != source.identity())
        let summary = try await target.importData(data, passphrase: passphrase, mode: .merge)
        #expect(summary.personas == 2)
        #expect(target.personas.map { $0.label } == ["Personal", "Personal", "Work"])
        #expect(target.personas.map { $0.keyIndex } == [0, 2, 3])
        #expect(targetKeys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 4]))
        for persona in target.personas {
            #expect(try target.card(for: persona, form: .fullQR).publicKey != retired)
        }
        #expect(try target.addPersona(label: "New", alias: false).keyIndex == 4)

        let twin = try AppModel.inMemory()
        await twin.load()
        _ = try await twin.importData(data, passphrase: passphrase, mode: .restore)
        #expect(try twin.identity() == source.identity())
        let work = try #require(twin.personas.first { $0.label == "Work" })
        try twin.delete(persona: work)
        #expect(twin.personas.map { $0.keyIndex } == [0])
        let back = try await twin.importData(data, passphrase: passphrase, mode: .merge)
        #expect(back.personas == 1)
        #expect(twin.personas.map { $0.keyIndex } == [0, 1])
        #expect(twin.personas.last?.id == work.id)
        #expect(try twin.card(for: work, form: .fullQR).publicKey == source.card(for: work, form: .fullQR).publicKey)
    }

    @Test func importWrongPassphraseMapsToAppError() async throws {
        let (source, _) = try await onboarded()
        let data = try await source.exportData(passphrase: passphrase)
        let fresh = try AppModel.inMemory()
        await fresh.load()
        await #expect(throws: AppError.wrongPassphrase) {
            try await fresh.importData(data, passphrase: "correct horse battery stapler", mode: .restore)
        }
        #expect(fresh.phase == .onboarding)
        let freshKeys = try #require(fresh.keys as? MemoryKeyStore)
        #expect(freshKeys.items.isEmpty)
        await #expect(throws: AppError.wrongPassphrase) {
            try await source.importData(data, passphrase: "", mode: .merge)
        }
        await #expect(throws: AppError.unsupportedFormat) {
            try await fresh.importData(Data([0xa0]), passphrase: passphrase, mode: .restore)
        }
    }

    @Test func restoreOnlyIntoFreshHatbandMergeOnlyIntoReady() async throws {
        let (source, _) = try await onboarded()
        let data = try await source.exportData(passphrase: passphrase)
        await #expect(throws: AppError.self) {
            try await source.importData(data, passphrase: passphrase, mode: .restore)
        }
        #expect(source.personas.count == 1)
        let fresh = try AppModel.inMemory()
        await fresh.load()
        await #expect(throws: AppError.self) {
            try await fresh.importData(data, passphrase: passphrase, mode: .merge)
        }
        #expect(fresh.phase == .onboarding)
    }

    @Test func setAppLockRewritesAccess() async throws {
        let (model, keys) = try await onboarded(appLock: true)
        let before = try #require(keys.items[KeyName.database])
        keys.prompts = []
        try await model.setAppLock(false)
        let after = try #require(keys.items[KeyName.database])
        #expect(after.data == before.data)
        #expect(after.access == .database(appLock: false, includeInBackup: false))
        #expect(!after.access.userPresence)
        #expect(keys.prompts == [AppModel.protectionPrompt])
        #expect(!model.settings.appLock)

        let again = try await relaunched(model, keys: keys)
        #expect(!again.settings.appLock)
        #expect(!again.locked)

        try await model.setAppLock(true)
        #expect(keys.items[KeyName.database]?.access == .database(appLock: true, includeInBackup: false))
        #expect(model.settings.appLock)

        keys.failNextRead = .cancelled
        await #expect(throws: AppError.cancelled) {
            try await model.setAppLock(false)
        }
        #expect(model.settings.appLock)
        #expect(keys.items[KeyName.database]?.access.userPresence == true)
    }

    @Test func setIncludeInBackupRewritesAccess() async throws {
        let (model, keys) = try await onboarded(appLock: true)
        let before = try #require(keys.items[KeyName.database])
        keys.prompts = []
        try await model.setIncludeInBackup(true)
        let after = try #require(keys.items[KeyName.database])
        #expect(after.data == before.data)
        #expect(after.access == .database(appLock: true, includeInBackup: true))
        #expect(!after.access.thisDeviceOnly)
        #expect(after.access.userPresence)
        #expect(keys.prompts == [AppModel.protectionPrompt])
        #expect(model.settings.includeInBackup)

        let again = try await relaunched(model, keys: keys)
        #expect(again.settings.includeInBackup)

        try await model.setIncludeInBackup(false)
        #expect(keys.items[KeyName.database]?.access == .database(appLock: true, includeInBackup: false))
        #expect(!model.settings.includeInBackup)
    }

    @Test func setHomeWidgetWritesFeed() async throws {
        let (model, keys) = try await onboarded()
        let directory = try #require(model.widgetDirectory)
        #expect(WidgetFeed.read(from: directory) == nil)
        try model.setHomeWidget(true)
        #expect(model.settings.homeWidget)
        let feed = try #require(WidgetFeed.read(from: directory))
        #expect(try HB1.decode(url: feed.url).isCompact)
        #expect(feed.color == model.selectedPersona?.color)
        let again = try await relaunched(model, keys: keys)
        #expect(again.settings.homeWidget)
        try model.setHomeWidget(false)
        #expect(!model.settings.homeWidget)
        #expect(WidgetFeed.read(from: directory) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WidgetFeed.fileName).path))
    }

    @Test func exportRunsWhileLockedOnlyAfterUnlock() async throws {
        let (model, keys) = try await onboarded(appLock: true)
        let dedalus = try makePerson(identity: Identity.generate(), personaID: dedalusID, name: "Stephen Dedalus", seq: 1,
                                     encounters: [encounter(1_700_000_000, "Martello tower")])
        try await seed([dedalus], into: model)
        model.lock()
        #expect(model.locked)
        keys.prompts = []
        let data = try await model.exportData(passphrase: passphrase)
        #expect(keys.prompts == [unlockPrompt])
        #expect(!model.locked)
        let bundle = try ExportBundle.open(Array(data), passphrase: passphrase)
        let storedSeed = try #require(keys.items[KeyName.seed]).data
        #expect(bundle.seed == Array(storedSeed))
        #expect(bundle.people.count == 1)
        #expect(try PersonCodec.decode(bundle.people[0]) == dedalus)
        #expect(try OwnerCodec.decode(bundle.owner).personas == model.personas)

        model.lock()
        keys.failNextRead = .cancelled
        await #expect(throws: AppError.cancelled) {
            try await model.exportData(passphrase: passphrase)
        }
        #expect(model.locked)
    }
}
