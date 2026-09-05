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
