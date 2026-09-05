import CryptoKit
import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// A well-formed v4 Ed25519 public key packet and the fingerprint the
/// framing rule gives it: SHA-1 over 0x99, the two-byte length, the body.
nonisolated func syntheticV4Certificate() -> (packet: [UInt8], fingerprint: [UInt8]) {
    var body: [UInt8] = [4, 0x60, 0, 0, 0, 22]
    body += [0x09, 0x2B, 0x06, 0x01, 0x04, 0x01, 0xDA, 0x47, 0x0F, 0x01]
    body += [0x01, 0x07, 0x40] + [UInt8](repeating: 0xAB, count: 32)
    let header: [UInt8] = [0x99, UInt8(body.count >> 8), UInt8(body.count & 0xff)]
    let fingerprint = Array(Insecure.SHA1.hash(data: Data(header + body)))
    return (header + body, fingerprint)
}

/// A pinned person built straight from a card, as `Merge.apply` would.
nonisolated func pinnedPerson(_ card: Card, source: CardSource = .scan, trust: Trust = .inPerson) -> Person {
    let short = card.publicKey.flatMap { KeyFingerprint(publicKey: $0)?.short } ?? card.keyFingerprint
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    return Person(personaID: card.personaID, cardBytes: card.cbor.encoded, card: card, publicKey: card.publicKey,
                  keyFingerprint: short, trust: trust, source: source, tags: [], note: "", gpgKey: nil,
                  createdAt: when, updatedAt: when, encounters: [])
}

struct ReviewTests {
    @Test func typicalSignedIsValidAllOk() throws {
        let card = try Vectors.card("typical-signed")
        let review = Review.make(card: card, source: .scan, people: [])
        #expect(review.signature == .valid)
        #expect(review.dropped.isEmpty)
        #expect(review.items.count == 9)
        #expect(review.items.allSatisfy { $0.verdict == .ok && $0.included })
        #expect(review.items.map { $0.id } == ["name", "company", "phone", "email", "website", "github", "linkedin", "mastodon", "calendly"])
        #expect(review.items.first { $0.id == "website" }?.value == "https://nnix.com")
        #expect(review.outcome == .new)
        #expect(review.existing == nil)
        #expect(!review.gpgKeyVerified)
        #expect(review.source == .scan)
        #expect(review.card == card)
    }

    @Test func tamperedIsInvalidAndRejected() throws {
        let review = Review.make(card: try Vectors.card("tampered-signature"), source: .link, people: [])
        #expect(review.signature == .invalid)
        guard case .rejected = review.outcome else {
            Issue.record("expected .rejected, got \(review.outcome)")
            return
        }
    }

    @Test func compactVectorIsCompact() throws {
        let review = Review.make(card: try Vectors.card("compact-name-only"), source: .scan, people: [])
        #expect(review.signature == .compact)
        #expect(review.outcome == .new)
        #expect(review.items.map { $0.id } == ["name"])
        #expect(review.acceptedCard.keyFingerprint == review.card.keyFingerprint)
        #expect(review.acceptedCard.isCompact)
    }

    @Test func minimalIsUnsigned() throws {
        let review = Review.make(card: try Vectors.card("minimal"), source: .file, people: [])
        #expect(review.signature == .unsigned)
        #expect(review.items.isEmpty)
        #expect(review.dropped.isEmpty)
        #expect(review.outcome == .new)
    }

    @Test func javascriptCustomURLDropped() throws {
        var card = try Vectors.card("typical-signed")
        card.custom = [
            CustomField(label: "Site", value: "javascript:alert(1)", kind: .url),
            CustomField(label: "Pub", value: "Davy Byrne's", kind: .text),
        ]
        let review = Review.make(card: card, source: .scan, people: [])
        #expect(review.dropped.count == 1)
        #expect(review.dropped.first?.hasPrefix("Site: ") == true)
        #expect(review.items.contains { $0.id == "custom:Pub" })
        #expect(!review.items.contains { $0.id == "custom:Site" })
        #expect(review.acceptedCard.custom == [CustomField(label: "Pub", value: "Davy Byrne's", kind: .text)])
    }

    @Test func photoDroppedUnderQRLimits() throws {
        let card = try Vectors.card("file-with-photo-and-key")
        let scanned = Review.make(card: card, source: .scan, people: [])
        #expect(scanned.dropped.contains { $0.hasPrefix("Photo: ") })
        #expect(!scanned.items.contains { $0.id == "photo" })
        #expect(scanned.acceptedCard.photo == nil)
        let filed = Review.make(card: card, source: .file, people: [])
        #expect(!filed.dropped.contains { $0.hasPrefix("Photo: ") })
        #expect(filed.items.contains { $0.id == "photo" && $0.verdict == .ok })
        #expect(filed.acceptedCard.photo == card.photo)
    }

    @Test func oversizeGPGKeyDropped() throws {
        var card = try Vectors.card("maximal-qr-signed")
        card.gpgKey = [UInt8](repeating: 0x98, count: Limits.file.gpgKeyBytes + 1)
        let review = Review.make(card: card, source: .file, people: [])
        #expect(review.dropped.contains { $0.hasPrefix("GPG key: ") })
        #expect(!review.gpgKeyVerified)
        #expect(review.acceptedCard.gpgKey == nil)
        #expect(review.items.contains { $0.id == "gpgFingerprint" })
    }

    @Test func gpgKeyKeptOnlyWhenHashMatches() throws {
        let vector = try Vectors.card("file-with-photo-and-key")
        let synthetic = Review.make(card: vector, source: .file, people: [])
        #expect(!synthetic.gpgKeyVerified)
        #expect(synthetic.dropped.contains { $0.hasPrefix("GPG key: ") })
        #expect(synthetic.acceptedCard.gpgKey == nil)

        let certificate = syntheticV4Certificate()
        var card = vector
        card.gpgFingerprint = certificate.fingerprint
        card.gpgKey = certificate.packet
        let hashing = Review.make(card: card, source: .link, people: [])
        #expect(hashing.gpgKeyVerified)
        #expect(!hashing.dropped.contains { $0.hasPrefix("GPG key: ") })
        #expect(hashing.items.contains { $0.id == "gpgKey" })
        #expect(hashing.acceptedCard.gpgKey == certificate.packet)
    }

    @Test func acceptedCardOmitsExcludedItems() throws {
        let card = try Vectors.card("typical-signed")
        var review = Review.make(card: card, source: .scan, people: [])
        #expect(review.acceptedCard == card)
        #expect(review.acceptedCard.cbor.encoded == (try Vectors.cbor("typical-signed")))
        #expect(review.acceptedCard.signatureIsValid)
        let index = try #require(review.items.firstIndex { $0.id == "email" })
        review.items[index].included = false
        let accepted = review.acceptedCard
        #expect(accepted.email == nil)
        #expect(accepted.name == card.name)
        #expect(accepted.phone == card.phone)
        #expect(accepted.publicKey == card.publicKey)
        #expect(accepted.signature == card.signature)
        #expect(accepted.seq == card.seq)
        #expect(accepted.color == card.color)
    }

    @Test func existingPersonDrivesOutcome() throws {
        let card = try Vectors.card("typical-signed")
        let person = pinnedPerson(card)
        let same = Review.make(card: card, source: .scan, people: [person])
        #expect(same.existing == person)
        #expect(same.outcome == .encounterOnly)

        var newer = card
        newer.seq = card.seq + 1
        newer.email = "leopold@example.ie"
        let key = try Identity(seed: Vectors.seed).personaSigningKey(index: 1)
        let signed = try newer.signed(with: key)
        #expect(signed.publicKey == card.publicKey)
        let updated = Review.make(card: signed, source: .link, people: [person])
        #expect(updated.signature == .valid)
        guard case .update(let changes) = updated.outcome else {
            Issue.record("expected .update, got \(updated.outcome)")
            return
        }
        #expect(changes == [Merge.Change(label: "Email", old: "henry.flower@example.ie", new: "leopold@example.ie")])
    }
}
