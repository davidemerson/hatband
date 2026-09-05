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

    /// README: "`seq` rises only when a card's content changes." The label
    /// names the persona in the app and rides in no card; Lock Screen
    /// channels, colour, display name and the field selection all do.
    @Test func updateBumpsSeqOnlyWhenCardContentChanges() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        #expect(persona.seq == 1)
        try await model.update(persona)
        #expect(model.selectedPersona?.seq == 1)

        var renamed = persona
        renamed.label = "Home"
        try await model.update(renamed)
        #expect(model.selectedPersona?.label == "Home")
        #expect(model.selectedPersona?.seq == 1)

        var lockScreen = try #require(model.selectedPersona)
        lockScreen.lockScreenChannels = [.email]
        try await model.update(lockScreen)
        #expect(model.selectedPersona?.seq == 2)

        var recoloured = try #require(model.selectedPersona)
        recoloured.color = 5
        try await model.update(recoloured)
        #expect(model.selectedPersona?.seq == 3)

        var named = try #require(model.selectedPersona)
        named.displayName = "L. Bloom"
        try await model.update(named)
        #expect(model.selectedPersona?.seq == 4)

        var narrower = try #require(model.selectedPersona)
        narrower.channels.remove(.phone)
        try await model.update(narrower)
        #expect(model.selectedPersona?.seq == 5)

        // A stale `seq` on the way in is ignored: the counter is the model's.
        var stale = try #require(model.selectedPersona)
        stale.seq = 1
        stale.label = "Home again"
        try await model.update(stale)
        #expect(model.selectedPersona?.seq == 5)
        #expect(model.selectedPersona?.label == "Home again")

        let reloaded = try await reload(model)
        #expect(reloaded.selectedPersona?.seq == 5)
        #expect(reloaded.selectedPersona?.label == "Home again")
        #expect(try reloaded.card(for: try #require(reloaded.selectedPersona), form: .fullQR).seq == 5)
        var unknown = persona
        unknown.id = [9, 9, 9, 9, 9, 9, 9, 9]
        await #expect(throws: AppError.storage("Unknown persona")) {
            try await model.update(unknown)
        }
    }

    /// Key 17 counts Gregorian days in the local time zone, whatever
    /// calendar the phone displays; before the epoch it is clamped to 0.
    @Test func issuedDayCountsGregorianDaysInTheLocalTimeZone() async throws {
        let instant = Date(timeIntervalSince1970: 1_788_000_000)   // 2026-08-29T10:40:00Z
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(AppModel.issuedDay(on: instant, timeZone: utc) == 2432)
        let civil = Day.civil(2432)
        #expect(civil.year == 2026 && civil.month == 8 && civil.day == 29)
        #expect(AppModel.issuedDay(on: instant, timeZone: try #require(TimeZone(identifier: "Pacific/Pago_Pago"))) == 2431)
        #expect(AppModel.issuedDay(on: instant, timeZone: try #require(TimeZone(identifier: "Pacific/Kiritimati"))) == 2433)
        #expect(AppModel.issuedDay(on: Date(timeIntervalSince1970: 0), timeZone: utc) == 0)
        // The vectors were issued on 2026-09-04.
        #expect(AppModel.issuedDay(on: Date(timeIntervalSince1970: 1_788_000_000 + 6 * 86_400), timeZone: utc) == 2438)
        let model = try await onboarded()
        #expect(model.issuedDay() == AppModel.issuedDay(on: Date(), timeZone: .current))
        #expect(try model.card(for: try #require(model.selectedPersona), form: .file).issuedDay == model.issuedDay())
    }

    /// Key 23 travels only beside key 12: a persona that withholds its GPG
    /// channel does not ship the certificate that names it.
    @Test func fileCardCarriesGPGKeyOnlyWithItsFingerprint() async throws {
        let model = try await onboarded()
        var persona = try #require(model.selectedPersona)
        #expect(persona.channels.contains(.gpgFingerprint))
        let shared = try model.card(for: persona, form: .file)
        #expect(shared.gpgFingerprint == sampleProfile().gpgFingerprint)
        #expect(shared.gpgKey == sampleProfile().gpgKey)

        persona.channels.remove(.gpgFingerprint)
        try await model.update(persona)
        persona = try #require(model.selectedPersona)
        let withheld = try model.card(for: persona, form: .file)
        #expect(withheld.gpgFingerprint == nil)
        #expect(withheld.gpgKey == nil)
        #expect(withheld.photo == sampleProfile().photo)
        #expect(withheld.signatureIsValid)
        #expect(try HB1.decode(file: try model.fileBytes(for: persona)).gpgKey == nil)
        #expect(try HB1.decode(url: try model.url(for: persona, form: .file)).gpgKey == nil)
        #expect(AppModel.unsignedCard(profile: model.profile, persona: persona, form: .file, issuedDay: 1).gpgKey == nil)
        #expect(CardBuilder.card(profile: model.profile, persona: persona, form: .file, issuedDay: 1).gpgKey != nil)

        // Importing a certificate the persona does not share is not a content change either.
        var profile = model.profile
        profile.gpgKey = [UInt8](repeating: 0xC7, count: 300)
        let before = persona.seq
        try await model.saveProfile(profile)
        #expect(model.selectedPersona?.seq == before)
    }

    /// The set of HB1 keys each form emits is the set the vector of that
    /// tier carries; the app never writes key 22.
    @Test func tiersEmitTheVectorKeySets() async throws {
        let model = try await onboarded(profile: maximalProfile())
        var persona = try #require(model.selectedPersona)
        persona.customLabels = ["Pub", "Matrix", "Fax"]
        try await model.update(persona)
        persona = try #require(model.selectedPersona)

        let compact = try model.card(for: persona, form: .lockScreen)
        #expect(try keys(of: compact) == vectorKeys("compact-name-only"))
        #expect(compact.flags == .compact)
        #expect(compact.name == "Leopold Bloom")
        #expect(compact.publicKey == nil && compact.signature == nil)

        persona.lockScreenChannels = [.email, .mastodon]
        try await model.update(persona)
        persona = try #require(model.selectedPersona)
        let channels = try model.card(for: persona, form: .lockScreen)
        #expect(try keys(of: channels) == vectorKeys("compact-two-channels"))
        #expect(channels.email == "henry.flower@example.ie")
        #expect(channels.mastodon == "bloom@merveilles.town")
        #expect(channels.company == nil)
        #expect(channels.custom.isEmpty)
        #expect(channels.keyFingerprint == KeyFingerprint(publicKey: try derivedKey(model, persona))?.short)

        let full = try model.card(for: persona, form: .fullQR)
        #expect(try keys(of: full) == vectorKeys("maximal-qr-signed").subtracting([FieldKey.minReader.rawValue]))
        #expect(full.flags == [.photoAvailable])
        #expect(full.website?.insecure == true)
        #expect(full.photo == nil)
        #expect(full.gpgKey == nil)
        #expect(full.custom == maximalProfile().custom)
        #expect(full.signatureIsValid)

        let file = try model.card(for: persona, form: .file)
        #expect(try keys(of: file) == vectorKeys("file-with-photo-and-key").subtracting([FieldKey.minReader.rawValue]))
        #expect(file.photo == maximalProfile().photo)
        #expect(file.gpgKey == maximalProfile().gpgKey)
        #expect(file.signatureIsValid)
    }

    /// The maximal vector's fields as a profile.
    private func maximalProfile() -> Profile {
        var profile = Profile()
        profile.name = "Leopold Bloom"
        profile.company = "Freeman's Journal"
        profile.phone = "+353871234567"
        profile.email = "henry.flower@example.ie"
        profile.website = Website(address: "example.org/~bloom", insecure: true)
        profile.github = "lbloom"
        profile.linkedin = "leopold-bloom"
        profile.mastodon = "bloom@merveilles.town"
        profile.signal = .username((0..<48).map { UInt8($0 &* 5 &+ 3) })
        profile.calendly = "bloom/coffee"
        profile.ssh = SSHKeyField(kind: 1, bytes: (0..<32).map { UInt8(0x40 + $0) })
        profile.gpgFingerprint = (0..<20).map { UInt8(0xa0 + $0) }
        profile.gpgKey = [0x98, 0x33, 0x04] + (0..<120).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        profile.photo = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01]
            + (0..<200).map { UInt8($0 & 0xff) } + [0xff, 0xd9]
        profile.custom = [
            CustomField(label: "Pub", value: "Davy Byrne's", kind: .text),
            CustomField(label: "Matrix", value: "https://matrix.to/#/@bloom:example.ie", kind: .url),
            CustomField(label: "Fax", value: "+35318000000", kind: .phone),
        ]
        return profile
    }

    private func vectorKeys(_ name: String) throws -> Set<UInt64> {
        let map = try #require(try Vectors.vector(name)["map"] as? [String: Any])
        return Set(map.keys.compactMap { UInt64($0) })
    }

    private func keys(of card: Card) throws -> Set<UInt64> {
        let map = try #require(card.cbor.mapValue)
        return Set(map.keys.compactMap { $0.unsignedValue })
    }

    /// `budget(for:form:)` reads the persona and nothing else: repeated
    /// calls agree with each other and with `Budget(card:)`, though every
    /// signed card carries a fresh signature, and nothing is written or
    /// prompted for on the way.
    @Test func budgetIsPure() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        let keys = try #require(model.keys as? MemoryKeyStore)
        let promptsBefore = keys.prompts.count
        var events: [String] = []
        keys.onEvent = { events.append($0) }
        defer { keys.onEvent = nil }
        let personas = model.personas
        let profile = model.profile
        let settings = model.settings
        for form in CardForm.allCases {
            let first = try model.budget(for: persona, form: form)
            let second = try model.budget(for: persona, form: form)
            #expect(first == second)
            #expect(first == Budget(card: try model.card(for: persona, form: form)))
            #expect(first.bytes > 0)
            #expect(first.characters > first.bytes)
        }
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0 == "read " + KeyName.seed })
        #expect(keys.prompts.count == promptsBefore)
        #expect(model.personas == personas)
        #expect(model.profile == profile)
        #expect(model.settings == settings)
    }

    /// A view caches its meters under `budgetKey(for:)`, so the key moves
    /// exactly with what a card carries: never for a label, always for a
    /// colour, channel, name or Lock Screen change, and for `seq`, the day
    /// and the signing key, which ride in or under every card.
    @Test func budgetKeyFollowsCardContentOnly() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        let day = model.issuedDay()
        let key = model.budgetKey(for: persona)
        #expect(model.budgetKey(for: persona) == key)
        #expect(key == AppModel.budgetKey(profile: model.profile, persona: persona, issuedDay: day))

        var relabelled = persona
        relabelled.label = "Home"
        #expect(model.budgetKey(for: relabelled) == key)
        for form in CardForm.allCases {
            #expect(try model.budget(for: relabelled, form: form) == (try model.budget(for: persona, form: form)))
        }

        var recoloured = persona
        recoloured.color = 5
        #expect(model.budgetKey(for: recoloured) != key)
        var lockScreen = persona
        lockScreen.lockScreenChannels = [.email]
        #expect(model.budgetKey(for: lockScreen) != key)
        var named = persona
        named.displayName = "L. Bloom"
        #expect(model.budgetKey(for: named) != key)
        var narrower = persona
        narrower.channels.remove(.phone)
        #expect(model.budgetKey(for: narrower) != key)
        var withoutPhoto = persona
        withoutPhoto.includePhoto = false
        #expect(model.budgetKey(for: withoutPhoto) != key)
        var bumped = persona
        bumped.seq += 1
        #expect(model.budgetKey(for: bumped) != key)
        var rekeyed = persona
        rekeyed.keyIndex += 1
        #expect(model.budgetKey(for: rekeyed) != key)
        #expect(AppModel.budgetKey(profile: model.profile, persona: persona, issuedDay: day + 1) != key)

        // A profile change the persona does not share leaves its key alone; one it shares moves it.
        var withheld = persona
        withheld.channels.remove(.gpgFingerprint)
        let before = AppModel.budgetKey(profile: model.profile, persona: withheld, issuedDay: day)
        var profile = model.profile
        profile.gpgKey = [UInt8](repeating: 0xC7, count: 300)
        #expect(AppModel.budgetKey(profile: profile, persona: withheld, issuedDay: day) == before)
        profile.company = "Sweets of Sin"
        #expect(AppModel.budgetKey(profile: profile, persona: withheld, issuedDay: day) != before)
    }

    /// `measure` is `card(for:form:)` and `Budget(card:)` in one value, a
    /// failure kept as the error to show.
    @Test func measureCarriesCardBudgetOrProblem() async throws {
        let model = try await onboarded()
        let persona = try #require(model.selectedPersona)
        for form in CardForm.allCases {
            let measured = model.measure(persona, form: form)
            let card = try #require(measured.card)
            #expect(measured.problem == nil)
            #expect(measured.budget == Budget(card: card))
            #expect(measured.budget == (try model.budget(for: persona, form: form)))
            #expect(card.isCompact == (form == .lockScreen))
        }
        var huge = persona
        huge.displayName = String(repeating: "N", count: 2000)
        let refused = model.measure(huge, form: .lockScreen)
        #expect(refused.card == nil)
        #expect(refused.budget == nil)
        #expect(refused.problem == .tooBigForLockScreen)
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

    /// The phone's display calendar never reaches key 17: the Buddhist and
    /// Japanese calendars number the same instant 2569 and Reiwa 8, and
    /// `issuedDay` still counts the Gregorian day.
    @Test func issuedDayIgnoresTheDisplayCalendar() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let instant = Date(timeIntervalSince1970: 1_788_000_000)   // 2026-08-29T10:40:00Z
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = utc
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = utc
        let civil = gregorian.dateComponents([.year, .month, .day], from: instant)
        let thai = buddhist.dateComponents([.year, .month, .day], from: instant)
        let reiwa = japanese.dateComponents([.era, .year, .month, .day], from: instant)
        let year = try #require(civil.year)
        let month = try #require(civil.month)
        let dayOfMonth = try #require(civil.day)
        #expect(year == 2026 && month == 8 && dayOfMonth == 29)
        let thaiYear = try #require(thai.year)
        let reiwaYear = try #require(reiwa.year)
        #expect(thaiYear == 2569 && reiwaYear == 8)
        #expect(thai.month == month && thai.day == dayOfMonth)
        #expect(reiwa.month == month && reiwa.day == dayOfMonth)
        let day = Int(AppModel.issuedDay(on: instant, timeZone: utc))
        #expect(day == Day.number(year: year, month: month, day: dayOfMonth))
        #expect(day == 2432)
        // What the display calendars' years would have produced instead.
        #expect(Day.number(year: thaiYear, month: month, day: dayOfMonth) > day + 500 * 365)
        #expect(Day.number(year: reiwaYear, month: month, day: dayOfMonth) < 0)
        // The civil day a Buddhist phone shows, read back through its own
        // calendar, is the same instant and so the same number.
        var thaiMidday = thai
        thaiMidday.hour = 12
        let viaBuddhist = try #require(buddhist.date(from: thaiMidday))
        #expect(AppModel.issuedDay(on: viaBuddhist, timeZone: utc) == 2432)
        var reiwaMidday = reiwa
        reiwaMidday.hour = 12
        let viaJapanese = try #require(japanese.date(from: reiwaMidday))
        #expect(AppModel.issuedDay(on: viaJapanese, timeZone: utc) == 2432)
    }

    @Test func issuedDayIsToday() async throws {
        let model = try await onboarded()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let parts = gregorian.dateComponents([.year, .month, .day], from: Date())
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
