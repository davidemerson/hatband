import CryptoKit
import Foundation
import HatbandCore

/// Card building and persona bookkeeping.
extension AppModel {
    /// Key-store item holding the next persona key index, so a deleted
    /// persona's key is never derived again for another one.
    static let personaIndexKey = KeyName.personaIndex

    /// Days since 2020-01-01 for today in the current calendar; never negative.
    func issuedDay() -> UInt32 {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
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
            let card = CardBuilder.card(profile: profile, persona: persona, form: form, issuedDay: day)
            return try card.signed(with: key)
        case .lockScreen:
            let publicKey = Array(key.publicKey.rawRepresentation)
            var trimmed = persona
            while true {
                let card = CardBuilder.card(profile: profile, persona: trimmed, form: .lockScreen, issuedDay: day)
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

    /// Replaces the persona, bumping `seq` only when something other than
    /// `seq` changed, then saves, refreshes the widget and updates a
    /// running activity.
    func update(_ persona: Persona) async throws {
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else {
            throw AppError.storage("Unknown persona")
        }
        var existing = personas[index]
        var incoming = persona
        existing.seq = 0
        incoming.seq = 0
        guard existing != incoming else { return }
        var updated = persona
        updated.seq = personas[index].seq + 1
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
        let day = issuedDay()
        var updated: [Persona] = []
        for persona in personas {
            var next = persona
            let before = CardBuilder.card(profile: self.profile, persona: persona, form: .file, issuedDay: day)
            let after = CardBuilder.card(profile: profile, persona: persona, form: .file, issuedDay: day)
            if before != after {
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

    // MARK: - Private

    /// One past the highest index in use or ever handed out, and the
    /// counter advanced past it.
    private func nextKeyIndex() throws -> UInt32 {
        var next = (personas.map { $0.keyIndex }.max() ?? 0) + 1
        if let data = try keys.read(AppModel.personaIndexKey, prompt: nil), data.count == 4 {
            let bytes = Array(data)
            let stored = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            next = max(next, stored)
        }
        let following = next + 1
        let data = Data([UInt8(following >> 24 & 0xFF), UInt8(following >> 16 & 0xFF),
                         UInt8(following >> 8 & 0xFF), UInt8(following & 0xFF)])
        try keys.write(AppModel.personaIndexKey, data, access: .seed)
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
