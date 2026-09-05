import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// A People row's second line: the company, or the last meeting as a
/// timestamp, which the row sets in `Theme.mono`.
struct PeopleViewTests {
    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    private func person(company: String?, encounters: [Encounter]) -> Person {
        var card = Card(personaID: [1, 2, 3, 4, 5, 6, 7, 8], issuedDay: 2438)
        card.name = "Leopold Bloom"
        card.company = company
        return Person(personaID: card.personaID, cardBytes: card.cbor.encoded, card: card, publicKey: nil,
                      keyFingerprint: nil, trust: .inPerson, source: .scan, tags: [], note: "", gpgKey: nil,
                      createdAt: when, updatedAt: when, encounters: encounters)
    }

    private func encounter(_ offset: TimeInterval, label: String) -> Encounter {
        Encounter(id: UUID(), date: when.addingTimeInterval(offset), fix: nil, label: label, note: "")
    }

    @Test func companyIsNotATimestamp() {
        let line = PeopleView.subtitle(for: person(company: "Freeman's Journal", encounters: [encounter(0, label: "Dublin")]))
        #expect(line == PeopleView.Subtitle(text: "Freeman's Journal", mono: false))
    }

    @Test func lastMeetingIsMonoWithItsDayAndPlace() {
        let older = encounter(0, label: "Dublin")
        let newer = encounter(86_400 * 3, label: "Sandymount")
        let line = PeopleView.subtitle(for: person(company: nil, encounters: [older, newer]))
        let day = newer.date.formatted(date: .abbreviated, time: .omitted)
        #expect(line.mono)
        #expect(line.text == "Met " + day + " · Sandymount")
        #expect(!line.text.contains("Dublin"))
        let unplaced = PeopleView.subtitle(for: person(company: nil, encounters: [encounter(0, label: "")]))
        let olderDay = older.date.formatted(date: .abbreviated, time: .omitted)
        #expect(unplaced == PeopleView.Subtitle(text: "Met " + olderDay, mono: true))
    }

    @Test func nothingWithoutCompanyOrMeeting() {
        #expect(PeopleView.subtitle(for: person(company: nil, encounters: [])) == PeopleView.Subtitle(text: "", mono: false))
    }
}
