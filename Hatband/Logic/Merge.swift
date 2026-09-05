import Foundation
import HatbandCore

/// The trust rules. A person is pinned to the first key seen for their
/// persona id (or, from a Lock Screen scan, its fingerprint). Later cards
/// update the record only under that key with a higher `seq`; a compact
/// card never updates; any other key is a warning, never a silent swap.
nonisolated enum Merge {
    nonisolated enum Outcome: Equatable, Sendable {
        case new
        case encounterOnly
        case update([Change])
        case keyChanged
        case rejected(String)
    }

    nonisolated struct Change: Equatable, Sendable {
        let label: String
        let old: String?
        let new: String?
    }

    static func outcome(existing: Person?, incoming: Card) -> Outcome {
        if incoming.publicKey != nil || incoming.signature != nil, !incoming.signatureIsValid {
            return .rejected("The signature does not verify.")
        }
        guard let existing else { return .new }
        if incoming.isCompact {
            guard let short = incoming.keyFingerprint else { return .encounterOnly }
            if let pinned = existing.publicKey {
                return KeyFingerprint.matches(short: short, publicKey: pinned) ? .encounterOnly : .keyChanged
            }
            if let pinned = existing.keyFingerprint {
                return pinned == short ? .encounterOnly : .keyChanged
            }
            return .encounterOnly
        }
        if let key = incoming.publicKey {
            if let pinned = existing.publicKey {
                if pinned != key { return .keyChanged }
            } else if let pinned = existing.keyFingerprint, !KeyFingerprint.matches(short: short(pinned), publicKey: key) {
                return .keyChanged
            }
        } else if existing.publicKey != nil || existing.keyFingerprint != nil {
            // An unsigned card cannot update a pinned person.
            return .encounterOnly
        }
        if incoming.seq > existing.card.seq {
            return .update(diff(old: existing.card, new: incoming))
        }
        if existing.card.isCompact, incoming.seq == existing.card.seq {
            // The full card behind a Lock Screen scan.
            return .update(diff(old: existing.card, new: incoming))
        }
        return .encounterOnly
    }

    /// Fields whose display value differs. A compact incoming never lists
    /// removals: it carries a subset by design. Photo and key are not listed.
    static func diff(old: Card, new: Card) -> [Change] {
        let before = CardFields.present(in: old).filter { !CardFields.isHeavy($0.id) }
        let after = CardFields.present(in: new).filter { !CardFields.isHeavy($0.id) }
        var changes: [Change] = []
        for field in after {
            let previous = before.first { $0.id == field.id }
            if previous?.value != field.value {
                changes.append(Change(label: field.label, old: previous?.value, new: field.value))
            }
        }
        if !new.isCompact {
            for field in before where !after.contains(where: { $0.id == field.id }) {
                changes.append(Change(label: field.label, old: field.value, new: nil))
            }
        }
        return changes
    }

    /// The person to store. A new person is pinned to the card's key (or
    /// fingerprint) with trust by source; an existing one gains an
    /// encounter and, per the outcome, a new card or a re-pin.
    static func apply(existing: Person?, review: Review, fix: Fix?, label: String, note: String, tags: [String],
                      acceptNewKey: Bool, now: Date) -> Person {
        let encounter = Encounter(id: UUID(), date: now, fix: fix, label: label, note: note)
        let card = review.acceptedCard
        guard var person = existing else {
            return Person(personaID: card.personaID, cardBytes: card.cbor.encoded, card: card,
                          publicKey: card.publicKey, keyFingerprint: fingerprint(of: card),
                          trust: review.source.isInPerson ? .inPerson : .byFile, source: review.source,
                          tags: cleaned(tags), note: "", gpgKey: review.gpgKeyVerified ? card.gpgKey : nil,
                          createdAt: now, updatedAt: now, encounters: [encounter])
        }
        person.encounters.append(encounter)
        person.tags = cleaned(person.tags + tags)
        person.updatedAt = now
        switch review.outcome {
        case .update:
            replaceCard(of: &person, with: card, review: review, keepPhoto: true)
        case .keyChanged where acceptNewKey:
            person.trust = .keyChanged(previous: person.publicKey ?? person.keyFingerprint ?? [])
            if card.isCompact {
                person.publicKey = nil
                person.keyFingerprint = card.keyFingerprint
            } else {
                replaceCard(of: &person, with: card, review: review, keepPhoto: false)
            }
        case .new, .encounterOnly, .keyChanged, .rejected:
            break
        }
        return person
    }

    // MARK: - Private

    /// The stored bytes are the incoming card's own: writing an earlier
    /// photo into them would put an unsigned key 20 under the signature.
    /// With `keepPhoto` the photo moves to `Person.photo` instead when the
    /// new card has none; a card under a new key starts without one.
    private static func replaceCard(of person: inout Person, with incoming: Card, review: Review, keepPhoto: Bool) {
        let earlier = person.currentPhoto
        person.card = incoming
        person.cardBytes = incoming.cbor.encoded
        person.photo = keepPhoto && incoming.photo == nil ? earlier : nil
        person.publicKey = incoming.publicKey
        person.keyFingerprint = fingerprint(of: incoming) ?? person.keyFingerprint
        person.source = review.source
        if review.gpgKeyVerified, let key = incoming.gpgKey {
            person.gpgKey = key
        }
    }

    /// The short fingerprint of the card's key, or the one it carries.
    private static func fingerprint(of card: Card) -> [UInt8]? {
        if let key = card.publicKey, let fingerprint = KeyFingerprint(publicKey: key) {
            return fingerprint.short
        }
        return card.keyFingerprint
    }

    /// A stored pin is 8 bytes; anything else cannot match.
    private static func short(_ pinned: [UInt8]) -> [UInt8] {
        Array(pinned.prefix(KeyFingerprint.shortLength))
    }

    /// Trimmed, non-empty, first occurrence wins.
    private static func cleaned(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            out.append(trimmed)
        }
        return out
    }
}
