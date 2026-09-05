import CryptoKit
import Foundation
import HatbandCore
import Testing
@testable import Hatband

@MainActor struct AppModelCardsTests {
    private func sampleProfile() -> Profile {
        var profile = Profile()
        profile.name = "Leopold Bloom"
        profile.company = "Freeman's Journal"
        profile.email = "bloom@example.ie"
        profile.phone = "+353871234567"
        profile.website = Website(address: "nnix.com/~bloom", insecure: false)
        profile.gpgFingerprint = [UInt8](repeating: 0xA0, count: 20)
        profile.gpgKey = [UInt8](repeating: 0xC6, count: 400)
        profile.photo = [0xFF, 0xD8, 0xFF, 0xD9] + [UInt8](repeating: 7, count: 300)
        return profile
    }

    /// A loaded, onboarded, unlocked model.
    private func onboarded(profile: Profile? = nil) async throws -> AppModel {
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: profile ?? sampleProfile(), appLock: false)
        return model
    }

    /// A second model over the same store and keys.
    private func reload(_ model: AppModel) async throws -> AppModel {
        let store = try #require(model.store)
        let second = AppModel(keys: model.keys, makeStore: { store })
        second.protectedDataAvailable = { true }
        await second.load()
        return second
    }

    private func derivedKey(_ model: AppModel, _ persona: Persona) throws -> [UInt8] {
        Array(try model.identity().personaSigningKey(index: persona.keyIndex).publicKey.rawRepresentation)
    }

    @Test func fullQRCardIsSignedByPersonaKey() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        let card = try model.card(for: persona, form: .fullQR)
        let derived = try derivedKey(model, persona)
        #expect(card.signatureIsValid)
        #expect(card.publicKey == derived)
        #expect(!card.isCompact)
        #expect(card.personaID == persona.id)
        #expect(card.seq == persona.seq)
        #expect(card.color == persona.color)
        #expect(card.issuedDay == model.issuedDay())
        #expect(card.name == "Leopold Bloom")
        #expect(card.email == "bloom@example.ie")
        #expect(try HB1.decode(url: try model.url(for: persona, form: .fullQR)).signatureIsValid)
        #expect(try model.budget(for: persona, form: .fullQR).fitsFullQR)
    }

    @Test func fileCardCarriesPhotoAndGPGKey() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        let file = try model.card(for: persona, form: .file)
        #expect(file.photo == sampleProfile().photo)
        #expect(file.gpgKey == sampleProfile().gpgKey)
        #expect(file.gpgFingerprint == sampleProfile().gpgFingerprint)
        #expect(file.flags.contains(.photoAvailable))
        #expect(file.signatureIsValid)
        let full = try model.card(for: persona, form: .fullQR)
        #expect(full.photo == nil)
        #expect(full.gpgKey == nil)
        #expect(full.flags.contains(.photoAvailable))
        #expect(full.gpgFingerprint == sampleProfile().gpgFingerprint)
        #expect(try HB1.decode(file: try model.fileBytes(for: persona)).photo == sampleProfile().photo)
    }

    @Test func lockScreenCardIsCompactWithFingerprint() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        let card = try model.card(for: persona, form: .lockScreen)
        #expect(card.isCompact)
        #expect(card.publicKey == nil)
        #expect(card.signature == nil)
        #expect(!card.isSigned)
        let fingerprint = try #require(KeyFingerprint(publicKey: try derivedKey(model, persona)))
        #expect(card.keyFingerprint == fingerprint.short)
        #expect(card.name == "Leopold Bloom")
        #expect(card.email == nil)
        #expect(card.photo == nil)
        #expect(Budget(card: card).fitsLockScreen)
        #expect(try model.budget(for: persona, form: .lockScreen).fitsLockScreen)
        let qr = try #require(try model.qr(for: persona, form: .lockScreen))
        #expect(qr.version <= Budget.lockScreenMaxVersion)
    }

    @Test func lockScreenTrimsChannelsLastFirstNeverName() async throws {
        let name = String(repeating: "L", count: 64)
        let local = String(repeating: "a", count: 64)
        let host = String(repeating: "b", count: 63) + "." + String(repeating: "c", count: 63) + "." + String(repeating: "d", count: 61)
        let email = local + "@" + host
        #expect(email.utf8.count == 254)
        let website = Website(address: "example.org/" + String(repeating: "p", count: 116), insecure: false)
        #expect(website.address.utf8.count == 128)
        var profile = Profile()
        profile.name = name
        profile.email = email
        profile.website = website
        let model = try await onboarded(profile: profile)
        var persona = try #require(model.selectedPersona)
        persona.lockScreenChannels = [.email, .website]
        try await model.update(persona)

        let card = try model.card(for: persona, form: .lockScreen)
        #expect(card.name == name)
        #expect(card.website == nil)
        #expect(card.email == nil)
        #expect(Budget(card: card).fitsLockScreen)

        // With an email that fits, only the website goes: the last channel first.
        var shorter = profile
        shorter.email = "a@b.ie"
        try await model.saveProfile(shorter)
        let kept = try model.card(for: persona, form: .lockScreen)
        #expect(kept.name == name)
        #expect(kept.email == "a@b.ie")
        #expect(kept.website == nil)
        #expect(Budget(card: kept).fitsLockScreen)

        // A name that cannot fit on its own is refused rather than trimmed.
        var huge = persona
        huge.displayName = String(repeating: "N", count: 2000)
        #expect(throws: AppError.tooBigForLockScreen) {
            try model.card(for: huge, form: .lockScreen)
        }
    }

    @Test func qrIsNilForFileForm() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        #expect(try model.qr(for: persona, form: .file) == nil)
        let full = try #require(try model.qr(for: persona, form: .fullQR))
        #expect(full.version <= Budget.fullQRMaxVersion)
        let compact = try #require(try model.qr(for: persona, form: .lockScreen))
        #expect(compact.version <= Budget.lockScreenMaxVersion)
        #expect(compact.version <= full.version)
    }

    @Test func urlAndFileBytesRoundTrip() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        let url = try model.url(for: persona, form: .file)
        let bytes = try model.fileBytes(for: persona)
        #expect(url.hasPrefix(HB1.urlPrefix))
        #expect(bytes.starts(with: HB1.fileMagic))
        var fromURL = try HB1.decode(url: url)
        var fromFile = try HB1.decode(file: bytes)
        #expect(fromURL.signatureIsValid)
        #expect(fromFile.signatureIsValid)
        #expect(fromURL.photo == sampleProfile().photo)
        // Each call signs afresh and Ed25519 signing is randomised, so compare everything else.
        fromURL.signature = nil
        fromFile.signature = nil
        #expect(fromURL == fromFile)
    }

    @Test func addPersonaAllocatesFreshKeyIndex() async throws {
        let model = try await onboarded()
        let work = try model.addPersona(label: "Work", alias: false)
        #expect(work.keyIndex == 1)
        #expect(work.id.count == 8)
        #expect(work.channels == sampleProfile().presentChannels)
        #expect(!work.isAlias)
        #expect(work.color != model.personas[0].color)
        try model.delete(persona: work)
        #expect(model.personas.count == 1)
        let other = try model.addPersona(label: "Other", alias: false)
        #expect(other.keyIndex == 2)
        #expect(other.id != work.id)
        #expect(other.id.count == 8)
        let third = try model.addPersona(label: "Third", alias: false)
        #expect(third.keyIndex == 3)
        #expect(third.id != other.id)
        let reloaded = try await reload(model)
        #expect(reloaded.personas.map { $0.keyIndex } == [0, 2, 3])
        let fourth = try reloaded.addPersona(label: "Fourth", alias: false)
        #expect(fourth.keyIndex == 4)
        let signedByThird = try reloaded.card(for: third, form: .fullQR)
        let derivedThird = try derivedKey(reloaded, third)
        #expect(signedByThird.publicKey == derivedThird)
    }

    @Test func aliasPersonaCardHasAliasFlagAndNoCanonicalFields() async throws {
        let model = try await onboarded()
        var alias = try model.addPersona(label: "Henry Flower", alias: true)
        #expect(alias.isAlias)
        #expect(alias.aliasProfile == Profile())
        #expect(alias.channels.isEmpty)
        var flower = Profile()
        flower.name = "Henry Flower"
        alias.aliasProfile = flower
        try await model.update(alias)
        let saved = try #require(model.personas.first { $0.id == alias.id })
        let card = try model.card(for: saved, form: .fullQR)
        #expect(card.flags.contains(.alias))
        #expect(card.name == "Henry Flower")
        #expect(card.email == nil)
        #expect(card.phone == nil)
        #expect(card.company == nil)
        #expect(card.website == nil)
        #expect(card.gpgFingerprint == nil)
        #expect(card.signatureIsValid)
        let compact = try model.card(for: saved, form: .lockScreen)
        #expect(compact.flags.contains(.alias))
        #expect(compact.name == "Henry Flower")
    }

    @Test func updateBumpsSeqOnlyWhenChanged() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        #expect(persona.seq == 1)
        try await model.update(persona)
        #expect(model.selectedPersona?.seq == 1)
        var changed = persona
        changed.label = "Home"
        try await model.update(changed)
        #expect(model.selectedPersona?.seq == 2)
        #expect(model.selectedPersona?.label == "Home")
        var again = try #require(model.selectedPersona)
        again.lockScreenChannels = [.email]
        try await model.update(again)
        #expect(model.selectedPersona?.seq == 3)
        let reloaded = try await reload(model)
        #expect(reloaded.selectedPersona?.seq == 3)
        #expect(reloaded.selectedPersona?.label == "Home")
        #expect(try reloaded.card(for: try #require(reloaded.selectedPersona), form: .fullQR).seq == 3)
        var unknown = persona
        unknown.id = [9, 9, 9, 9, 9, 9, 9, 9]
        await #expect(throws: AppError.storage("Unknown persona")) {
            try await model.update(unknown)
        }
    }

    @Test func selectPersistsLastPersonaID() async throws {
        let model = try await onboarded()
        let work = try model.addPersona(label: "Work", alias: false)
        #expect(model.selectedPersonaID != work.id)
        model.select(work)
        #expect(model.selectedPersonaID == work.id)
        #expect(model.selectedPersona == work)
        #expect(model.settings.lastPersonaID == work.id)
        #expect(model.error == nil)
        let reloaded = try await reload(model)
        #expect(reloaded.selectedPersonaID == work.id)
        #expect(reloaded.settings.lastPersonaID == work.id)
    }

    @Test func deleteLastPersonaRefused() async throws {
        let model = try await onboarded()
        let only = try #require(model.selectedPersona)
        #expect(throws: AppError.storage("last persona")) {
            try model.delete(persona: only)
        }
        #expect(model.personas.count == 1)
        let work = try model.addPersona(label: "Work", alias: false)
        model.select(work)
        try model.delete(persona: work)
        #expect(model.personas == [only])
        #expect(model.selectedPersonaID == only.id)
        #expect(model.settings.lastPersonaID == only.id)
        let reloaded = try await reload(model)
        #expect(reloaded.personas == [only])
        #expect(throws: AppError.storage("last persona")) {
            try reloaded.delete(persona: only)
        }
    }

    @Test func issuedDayIsToday() async throws {
        let model = try await onboarded()
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let year = try #require(parts.year)
        let month = try #require(parts.month)
        let day = try #require(parts.day)
        let today = model.issuedDay()
        #expect(Int(today) == Day.number(year: year, month: month, day: day))
        let civil = Day.civil(Int(today))
        #expect(civil.year == year)
        #expect(civil.month == month)
        #expect(civil.day == day)
        #expect(today > 2000)
    }

    @Test func saveProfileBumpsOnlyAffectedPersonas() async throws {
        let model = try await onboarded()
        let personal = try #require(model.selectedPersona)
        let alias = try model.addPersona(label: "Henry Flower", alias: true)
        var profile = model.profile
        profile.company = "Sweets of Sin"
        try await model.saveProfile(profile)
        #expect(model.profile.company == "Sweets of Sin")
        #expect(model.personas.first { $0.id == personal.id }?.seq == personal.seq + 1)
        #expect(model.personas.first { $0.id == alias.id }?.seq == alias.seq)
        try await model.saveProfile(profile)
        #expect(model.personas.first { $0.id == personal.id }?.seq == personal.seq + 1)
        let reloaded = try await reload(model)
        #expect(reloaded.profile.company == "Sweets of Sin")
        #expect(try reloaded.card(for: personal, form: .fullQR).company == "Sweets of Sin")
    }
}
