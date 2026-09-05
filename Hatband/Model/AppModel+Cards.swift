import CryptoKit
import Foundation
import HatbandCore

/// Card building and persona bookkeeping.
extension AppModel {
    /// Key-store item holding the next persona key index, so a deleted
    /// persona's key is never derived again for another one.
    static let personaIndexKey = KeyName.personaIndex

    /// The stored counter, four big-endian bytes; nil until a persona has
    /// been added after onboarding. Read once by `load()` and held; throws
    /// while that read has not succeeded.
    func storedPersonaIndex() throws -> UInt32? {
        guard personaIndexKnown else { throw AppError.storage("The persona counter could not be read. Try again.") }
        return personaIndexCounter
    }

    func storePersonaIndex(_ next: UInt32) throws {
        let data = Data([UInt8(next >> 24 & 0xFF), UInt8(next >> 16 & 0xFF),
                         UInt8(next >> 8 & 0xFF), UInt8(next & 0xFF)])
        try keys.write(AppModel.personaIndexKey, data, access: .seed)
        personaIndexCounter = next
        personaIndexKnown = true
    }

    /// One past the highest index in use or ever handed out: what the next
    /// persona gets, and what an export carries so a restore continues
    /// from it.
    func nextPersonaIndex() throws -> UInt32 {
        let stored = try storedPersonaIndex() ?? 0
        return max((personas.map { $0.keyIndex }.max() ?? 0) + 1, stored)
    }

    /// Days since 2020-01-01 for today, in the local time zone; never negative.
    func issuedDay() -> UInt32 {
        AppModel.issuedDay(on: Date(), timeZone: .current)
    }

    /// Key 17 counts proleptic Gregorian days, so the phone's calendar
    /// setting is not consulted: a Buddhist year would land the card
    /// centuries ahead and a Japanese era year before the epoch.
    nonisolated static func issuedDay(on date: Date, timeZone: TimeZone) -> UInt32 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let number = Day.number(year: parts.year ?? Day.epochYear, month: parts.month ?? 1, day: parts.day ?? 1)
        return UInt32(max(0, number))
    }

    /// `.fullQR` and `.file` are signed with the persona's derived key.
    /// `.lockScreen` carries the key fingerprint instead and drops Lock
    /// Screen channels last-first until it fits; the name is never trimmed,
    /// and when it alone does not fit the form throws `.tooBigForLockScreen`.
    func card(for persona: Persona, form: CardForm) throws -> Card {
        let key = try identity().personaSigningKey(index: persona.keyIndex)
        let day = issuedDay()
        switch form {
        case .fullQR, .file:
            let card = AppModel.unsignedCard(profile: profile, persona: persona, form: form, issuedDay: day)
            return try card.signed(with: key)
        case .lockScreen:
            let publicKey = Array(key.publicKey.rawRepresentation)
            var trimmed = persona
            while true {
                let card = AppModel.unsignedCard(profile: profile, persona: trimmed, form: .lockScreen, issuedDay: day)
                    .withKeyFingerprint(of: publicKey)
                if Budget(card: card).fitsLockScreen {
                    return card
                }
                guard !trimmed.lockScreenChannels.isEmpty else { throw AppError.tooBigForLockScreen }
                trimmed.lockScreenChannels.removeLast()
            }
        }
    }

    /// Nil for `.file`, and for a card too large for the form.
    func qr(for persona: Persona, form: CardForm) throws -> QRCode? {
        try Budget.qrCode(for: try card(for: persona, form: form), form: form)
    }

    func budget(for persona: Persona, form: CardForm) throws -> Budget {
        Budget(card: try card(for: persona, form: form))
    }

    func url(for persona: Persona, form: CardForm) throws -> String {
        HB1.url(for: try card(for: persona, form: form))
    }

    func fileBytes(for persona: Persona) throws -> [UInt8] {
        HB1.fileBytes(for: try card(for: persona, form: .file))
    }

    var selectedPersona: Persona? {
        personas.first { $0.id == selectedPersonaID }
    }

    /// Remembered as `settings.lastPersonaID`, so the same card comes back
    /// after a relaunch, and mirrored to the widget.
    func select(_ persona: Persona) {
        selectedPersonaID = persona.id
        settings.lastPersonaID = persona.id
        do {
            try saveOwner()
        } catch {
            self.error = AppError(error)
            Log.failure("select persona", error)
        }
        refreshWidget()
    }

    /// A random 8-byte id, a key index one past the highest ever allocated,
    /// the first unused palette colour, and for an alias an empty profile
    /// of its own.
    func addPersona(label: String, alias: Bool) throws -> Persona {
        let index = try nextKeyIndex()
        let persona = Persona(id: AppModel.randomPersonaID(), label: label, keyIndex: index, color: nextColor(),
                              channels: alias ? [] : profile.presentChannels, customLabels: [],
                              includeCompany: !alias, includePhoto: !alias,
                              aliasProfile: alias ? Profile() : nil)
        personas.append(persona)
        try saveOwner()
        return persona
    }

    /// Replaces the persona, then saves, refreshes the widget and updates a
    /// running activity. `seq` rises only when the content of one of its
    /// cards changes: a new label rides in no card and leaves it alone.
    func update(_ persona: Persona) async throws {
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else {
            throw AppError.storage("Unknown persona")
        }
        let existing = personas[index]
        var updated = persona
        updated.seq = existing.seq
        guard existing != updated else { return }
        if AppModel.cardContent(profile: profile, persona: existing) != AppModel.cardContent(profile: profile, persona: updated) {
            updated.seq = existing.seq + 1
        }
        personas[index] = updated
        try saveOwner()
        refreshWidget()
        await updateActivity(for: updated)
    }

    /// Refused for the last persona. The selection moves to the first
    /// remaining one, and a sharing session for it ends.
    func delete(persona: Persona) throws {
        guard personas.count > 1 else { throw AppError.storage("last persona") }
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else { return }
        personas.remove(at: index)
        if selectedPersonaID == persona.id, let first = personas.first {
            selectedPersonaID = first.id
            settings.lastPersonaID = first.id
        }
        try saveOwner()
        refreshWidget()
        if sharing?.personaID == persona.id {
            Task { await self.stopSharing() }
        }
    }

    /// Replaces the canonical profile, bumping `seq` on every persona whose
    /// card content changes, and refreshes what is on show.
    func saveProfile(_ profile: Profile) async throws {
        var updated: [Persona] = []
        for persona in personas {
            var next = persona
            if AppModel.cardContent(profile: self.profile, persona: persona) != AppModel.cardContent(profile: profile, persona: persona) {
                next.seq += 1
            }
            updated.append(next)
        }
        self.profile = profile
        personas = updated
        try saveOwner()
        refreshWidget()
        if let sharing, let persona = personas.first(where: { $0.id == sharing.personaID }) {
            await updateActivity(for: persona)
        }
    }

    /// `CardBuilder`'s card for the form, less a GPG certificate the persona
    /// has not anchored: key 23 means nothing without key 12, and a persona
    /// that keeps its GPG channel back must not ship the certificate that
    /// names it.
    nonisolated static func unsignedCard(profile: Profile, persona: Persona, form: CardForm, issuedDay: UInt32) -> Card {
        var card = CardBuilder.card(profile: profile, persona: persona, form: form, issuedDay: issuedDay)
        if card.gpgFingerprint == nil {
            card.gpgKey = nil
        }
        return card
    }

    /// Every form of the persona's card with `seq` and the day held fixed:
    /// what a recipient can tell apart, and so what `seq` must count.
    nonisolated static func cardContent(profile: Profile, persona: Persona) -> [Card] {
        var fixed = persona
        fixed.seq = 0
        return CardForm.allCases.map { unsignedCard(profile: profile, persona: fixed, form: $0, issuedDay: 0) }
    }

    // MARK: - Private

    /// `nextPersonaIndex()`, with the counter advanced past it.
    private func nextKeyIndex() throws -> UInt32 {
        let next = try nextPersonaIndex()
        try storePersonaIndex(next + 1)
        return next
    }

    /// The first palette colour no persona uses, or the next one round.
    private func nextColor() -> UInt8 {
        let used = Set(personas.map { $0.color })
        for index in 0..<Palette.colors.count where !used.contains(UInt8(index)) {
            return UInt8(index)
        }
        return UInt8(personas.count % Palette.colors.count)
    }
}
