import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct MergeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func signed(_ card: Card, index: UInt32) throws -> Card {
        try card.signed(with: try Identity(seed: Vectors.seed).personaSigningKey(index: index))
    }

    private func review(_ card: Card, source: CardSource = .scan, people: [Person] = []) -> Review {
        Review.make(card: card, source: source, people: people)
    }

    // MARK: - Outcome

    @Test func newWhenUnknown() throws {
        #expect(Merge.outcome(existing: nil, incoming: try Vectors.card("typical-signed")) == .new)
        #expect(Merge.outcome(existing: nil, incoming: try Vectors.card("compact-name-only")) == .new)
        #expect(Merge.outcome(existing: nil, incoming: try Vectors.card("minimal")) == .new)
    }

    @Test func encounterOnlySameKeySameOrLowerSeq() throws {
        let card = try Vectors.card("typical-signed")
        var existing = pinnedPerson(card)
        #expect(Merge.outcome(existing: existing, incoming: card) == .encounterOnly)
        var higher = card
        higher.seq = 5
        existing = pinnedPerson(try signed(higher, index: 1))
        #expect(Merge.outcome(existing: existing, incoming: card) == .encounterOnly)
    }

    @Test func updateSameKeyHigherSeq() throws {
        let card = try Vectors.card("typical-signed")
        let existing = pinnedPerson(card)
        var newer = card
        newer.seq = 2
        newer.company = "Evening Telegraph"
        let incoming = try signed(newer, index: 1)
        guard case .update(let changes) = Merge.outcome(existing: existing, incoming: incoming) else {
            Issue.record("expected .update")
            return
        }
        #expect(changes == [Merge.Change(label: "Company", old: "Freeman's Journal", new: "Evening Telegraph")])
    }

    @Test func keyChangedDifferentKey() throws {
        let card = try Vectors.card("typical-signed")
        let existing = pinnedPerson(card)
        var other = card
        other.seq = 9
        let incoming = try signed(other, index: 7)
        #expect(incoming.publicKey != card.publicKey)
        #expect(Merge.outcome(existing: existing, incoming: incoming) == .keyChanged)
    }

    @Test func compactMatchingFingerprintIsEncounterOnly() throws {
        let existing = pinnedPerson(try Vectors.card("typical-signed"))
        let compact = try Vectors.card("compact-name-only")
        #expect(compact.personaID == existing.personaID)
        #expect(Merge.outcome(existing: existing, incoming: compact) == .encounterOnly)
    }

    @Test func compactMismatchIsKeyChanged() throws {
        let existing = pinnedPerson(try Vectors.card("typical-signed"))
        var compact = try Vectors.card("compact-name-only")
        compact.keyFingerprint = [UInt8](repeating: 0x42, count: 8)
        #expect(Merge.outcome(existing: existing, incoming: compact) == .keyChanged)
    }

    @Test func compactAgainstFingerprintOnlyPin() throws {
        let compact = try Vectors.card("compact-name-only")
        let existing = pinnedPerson(compact)
        #expect(existing.publicKey == nil)
        #expect(existing.keyFingerprint == compact.keyFingerprint)
        #expect(Merge.outcome(existing: existing, incoming: compact) == .encounterOnly)
        var other = compact
        other.keyFingerprint = [UInt8](repeating: 0x42, count: 8)
        #expect(Merge.outcome(existing: existing, incoming: other) == .keyChanged)
        let full = try Vectors.card("typical-signed")
        guard case .update = Merge.outcome(existing: existing, incoming: full) else {
            Issue.record("a full card under the pinned key should replace the compact one")
            return
        }
        let stranger = try signed(full, index: 7)
        #expect(Merge.outcome(existing: existing, incoming: stranger) == .keyChanged)
    }

    @Test func rejectedWhenInvalid() throws {
        let tampered = try Vectors.card("tampered-signature")
        guard case .rejected = Merge.outcome(existing: nil, incoming: tampered) else {
            Issue.record("expected .rejected")
            return
        }
        let existing = pinnedPerson(try Vectors.card("typical-signed"))
        guard case .rejected = Merge.outcome(existing: existing, incoming: tampered) else {
            Issue.record("expected .rejected against a known person too")
            return
        }
    }

    // MARK: - Diff

    @Test func diffListsChangedLabelsOnly() throws {
        let old = try Vectors.card("typical-signed")
        var new = old
        new.phone = nil
        new.company = "Evening Telegraph"
        new.custom = [CustomField(label: "Pub", value: "Davy Byrne's")]
        let changes = Merge.diff(old: old, new: new)
        #expect(changes.contains(Merge.Change(label: "Company", old: "Freeman's Journal", new: "Evening Telegraph")))
        #expect(changes.contains(Merge.Change(label: "Pub", old: nil, new: "Davy Byrne's")))
        #expect(changes.contains(Merge.Change(label: "Phone", old: "+353871234567", new: nil)))
        #expect(changes.count == 3)
        #expect(Merge.diff(old: old, new: old).isEmpty)
    }

    @Test func diffNeverListsRemovalsForCompact() throws {
        let old = try Vectors.card("typical-signed")
        var compact = try Vectors.card("compact-two-channels")
        compact.email = "leopold@example.ie"
        let changes = Merge.diff(old: old, new: compact)
        #expect(changes == [Merge.Change(label: "Email", old: "henry.flower@example.ie", new: "leopold@example.ie")])
    }

    // MARK: - Apply

    @Test func applyNewSetsTrustBySource() throws {
        let card = try Vectors.card("typical-signed")
        for (source, trust) in [(CardSource.scan, Trust.inPerson), (.photo, .inPerson), (.file, .byFile), (.link, .byFile)] {
            let person = Merge.apply(existing: nil, review: review(card, source: source), fix: nil, label: "", note: "",
                                     tags: [" pub ", "pub", ""], acceptNewKey: false, now: now)
            #expect(person.trust == trust)
            #expect(person.source == source)
            #expect(person.publicKey == card.publicKey)
            #expect(person.keyFingerprint == KeyFingerprint(publicKey: card.publicKey ?? [])?.short)
            #expect(person.tags == ["pub"])
            #expect(person.createdAt == now)
            #expect(person.encounters.count == 1)
            #expect(person.cardBytes == card.cbor.encoded)
        }
    }

    @Test func applyAppendsEncounterWithFix() throws {
        let card = try Vectors.card("typical-signed")
        let existing = pinnedPerson(card)
        let fix = Fix(latitude: 53.3498, longitude: -6.2603, accuracy: 3000)
        let person = Merge.apply(existing: existing, review: review(card, people: [existing]), fix: fix, label: "Dublin",
                                 note: "By the river", tags: ["conference"], acceptNewKey: false, now: now)
        #expect(person.encounters.count == 1)
        let encounter = try #require(person.encounters.first)
        #expect(encounter.fix == fix)
        #expect(encounter.label == "Dublin")
        #expect(encounter.note == "By the river")
        #expect(encounter.date == now)
        #expect(person.tags == ["conference"])
        #expect(person.updatedAt == now)
        #expect(person.createdAt == existing.createdAt)
        #expect(person.cardBytes == existing.cardBytes)
    }

    @Test func applyUpdateReplacesCardBytes() throws {
        let card = try Vectors.card("typical-signed")
        let existing = pinnedPerson(card)
        var newer = card
        newer.seq = 3
        newer.email = "leopold@example.ie"
        let incoming = try signed(newer, index: 1)
        let person = Merge.apply(existing: existing, review: review(incoming, source: .link, people: [existing]), fix: nil,
                                 label: "", note: "", tags: [], acceptNewKey: false, now: now)
        #expect(person.cardBytes == incoming.cbor.encoded)
        #expect(person.card.email == "leopold@example.ie")
        #expect(person.card.seq == 3)
        #expect(person.publicKey == card.publicKey)
        #expect(person.trust == .inPerson)
        #expect(person.source == .link)
        #expect(person.encounters.count == 1)
    }

    /// A new person keeps the bytes that were received, signature and all,
    /// and is pinned to the key (or fingerprint) they carry.
    @Test(arguments: ["compact-name-only", "compact-two-channels", "typical-signed", "maximal-qr-signed", "alias-signed",
                      "unicode-nfc", "unicode-nfd"])
    func storedBytesAreTheReceivedBytes(name: String) throws {
        let card = try Vectors.card(name)
        let review = Review.make(card: card, source: card.isCompact ? .scan : .link, people: [])
        #expect(review.dropped.isEmpty, "\(name)")
        let person = Merge.apply(existing: nil, review: review, fix: nil, label: "", note: "", tags: [],
                                 acceptNewKey: false, now: now)
        #expect(person.cardBytes == (try Vectors.cbor(name)), "\(name)")
        let stored = try HB1.decode(cbor: person.cardBytes)
        #expect(stored == card)
        #expect(stored.signatureIsValid == card.isSigned)
        if let key = card.publicKey {
            #expect(person.publicKey == key)
            #expect(person.keyFingerprint == KeyFingerprint(publicKey: key)?.short)
        } else {
            #expect(person.publicKey == nil)
            #expect(person.keyFingerprint == card.keyFingerprint)
        }
        #expect(try PersonCodec.decode(PersonCodec.encode(person)).cardBytes == person.cardBytes)
    }

    /// README: a GPG certificate is kept only when it hashes to the card's
    /// fingerprint, on a first save and on an update alike.
    @Test func applyKeepsGPGKeyOnlyWhenItHashesToTheFingerprint() throws {
        let vector = try Vectors.card("file-with-photo-and-key")
        let unverified = Merge.apply(existing: nil, review: review(vector, source: .file), fix: nil, label: "", note: "",
                                     tags: [], acceptNewKey: false, now: now)
        #expect(unverified.gpgKey == nil)
        #expect(unverified.card.gpgKey == nil)
        #expect(unverified.card.photo == vector.photo)

        let certificate = syntheticV4Certificate()
        var anchored = vector
        anchored.gpgFingerprint = certificate.fingerprint
        anchored.gpgKey = certificate.packet
        let hashing = try signed(anchored, index: 3)
        let verified = Merge.apply(existing: nil, review: review(hashing, source: .link), fix: nil, label: "", note: "",
                                   tags: [], acceptNewKey: false, now: now)
        #expect(verified.gpgKey == certificate.packet)
        #expect(verified.card.gpgKey == certificate.packet)

        let pinned = pinnedPerson(try Vectors.card("maximal-qr-signed"))
        var newer = try Vectors.card("maximal-qr-signed")
        newer.seq = 8
        newer.gpgFingerprint = certificate.fingerprint
        newer.gpgKey = certificate.packet
        let update = try signed(newer, index: 2)
        let updateReview = review(update, source: .file, people: [pinned])
        guard case .update = updateReview.outcome else {
            Issue.record("expected .update, got \(updateReview.outcome)")
            return
        }
        let updated = Merge.apply(existing: pinned, review: updateReview, fix: nil, label: "", note: "", tags: [],
                                  acceptNewKey: false, now: now)
        #expect(updated.gpgKey == certificate.packet)
        #expect(updated.card.seq == 8)

        var mismatched = newer
        mismatched.seq = 9
        mismatched.gpgKey = vector.gpgKey
        let wrong = try signed(mismatched, index: 2)
        let wrongReview = review(wrong, source: .file, people: [pinned])
        #expect(wrongReview.dropped.contains { $0.hasPrefix("GPG key: ") })
        let refused = Merge.apply(existing: pinned, review: wrongReview, fix: nil, label: "", note: "", tags: [],
                                  acceptNewKey: false, now: now)
        #expect(refused.gpgKey == nil)
        #expect(refused.card.gpgKey == nil)
        #expect(refused.card.seq == 9)
    }

    @Test func applyKeyChangedKeepsOldUnlessAccepted() throws {
        let card = try Vectors.card("typical-signed")
        let existing = pinnedPerson(card)
        var other = card
        other.seq = 4
        let incoming = try signed(other, index: 7)
        let kept = Merge.apply(existing: existing, review: review(incoming, people: [existing]), fix: nil, label: "",
                               note: "", tags: [], acceptNewKey: false, now: now)
        #expect(kept.publicKey == card.publicKey)
        #expect(kept.cardBytes == existing.cardBytes)
        #expect(kept.trust == .inPerson)
        #expect(kept.encounters.count == 1)

        let accepted = Merge.apply(existing: existing, review: review(incoming, people: [existing]), fix: nil, label: "",
                                   note: "", tags: [], acceptNewKey: true, now: now)
        #expect(accepted.publicKey == incoming.publicKey)
        #expect(accepted.cardBytes == incoming.cbor.encoded)
        #expect(accepted.trust == .keyChanged(previous: card.publicKey ?? []))
        #expect(accepted.keyFingerprint == KeyFingerprint(publicKey: incoming.publicKey ?? [])?.short)
    }
}
