import Foundation
import HatbandCore
import SwiftUI
import Testing
@testable import Hatband

/// The person screen's two answers to the app leaving the foreground:
/// pending edits are committed before the lock can empty `people`, and a
/// fetch that lands after a lock or a Forget is dropped.
struct PersonViewTests {
    @Test func editsCommitAsTheSceneLeavesTheForeground() {
        #expect(!PersonView.commitsEdits(entering: .active))
        #expect(PersonView.commitsEdits(entering: .inactive), "before .background, so before the lock")
        #expect(PersonView.commitsEdits(entering: .background))
    }

    /// The screen holds a snapshot of the person taken when it appeared, and
    /// nothing refreshes it. Committing that snapshot whole would undo a GPG
    /// key fetched from this very screen, or a newer card merged behind it.
    /// Only the note, the tags and the meetings are this screen's to write.
    @Test func committingKeepsWhatWasStoredBehindTheScreen() throws {
        let card = try Vectors.card("typical-signed")
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        func person(gpgKey: [UInt8]?, note: String, tags: [String]) -> Person {
            Person(personaID: card.personaID, cardBytes: card.cbor.encoded, card: card, publicKey: card.publicKey,
                   keyFingerprint: nil, trust: .inPerson, source: .scan, tags: tags, note: note, gpgKey: gpgKey,
                   photo: nil, createdAt: day, updatedAt: day, encounters: [])
        }
        // The snapshot predates the fetch; the model's copy has the key.
        let snapshot = person(gpgKey: nil, note: "met at the bar", tags: ["dublin"])
        let current = person(gpgKey: [0xC0, 0xFF, 0xEE], note: "", tags: [])

        let committed = PersonView.committed(snapshot, onto: current)
        #expect(committed.gpgKey == [0xC0, 0xFF, 0xEE], "the fetched key survives the commit")
        #expect(committed.note == "met at the bar")
        #expect(committed.tags == ["dublin"])
        #expect(committed.cardBytes == current.cardBytes)
        #expect(committed.updatedAt == current.updatedAt)
    }

    /// Committing an untouched screen changes nothing, so `commit()` can
    /// compare and skip the write.
    @Test func committingAnUntouchedScreenIsANoOp() throws {
        let card = try Vectors.card("typical-signed")
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        let current = Person(personaID: card.personaID, cardBytes: card.cbor.encoded, card: card,
                             publicKey: card.publicKey, keyFingerprint: nil, trust: .inPerson, source: .scan,
                             tags: ["a"], note: "n", gpgKey: nil, photo: nil, createdAt: day, updatedAt: day,
                             encounters: [])
        #expect(PersonView.committed(current, onto: current) == current)
    }

    @Test func fetchResultsKeptOnlyWhileUnlockedAndKnown() throws {
        let card = try Vectors.card("typical-signed")
        let person = Person(personaID: card.personaID, cardBytes: card.cbor.encoded, card: card, publicKey: card.publicKey,
                            keyFingerprint: nil, trust: .inPerson, source: .scan, tags: [], note: "", gpgKey: nil,
                            createdAt: Date(), updatedAt: Date(), encounters: [])
        #expect(PersonView.keepsFetchResult(locked: false, people: [person], personID: person.id))
        #expect(!PersonView.keepsFetchResult(locked: true, people: [person], personID: person.id), "locked meanwhile")
        #expect(!PersonView.keepsFetchResult(locked: false, people: [], personID: person.id), "forgotten meanwhile")
        #expect(!PersonView.keepsFetchResult(locked: true, people: [], personID: person.id))
    }
}
