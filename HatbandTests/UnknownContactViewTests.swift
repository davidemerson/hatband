import Contacts
import Foundation
import HatbandCore
import Testing
@testable import Hatband

@MainActor struct UnknownContactViewTests {
    private let instant = Date(timeIntervalSince1970: 1_788_000_000)   // 2026-08-29T10:40:00Z

    private func person(photo: [UInt8]? = nil) throws -> Person {
        let bytes = try Vectors.cbor("typical-signed")
        let card = try HB1.decode(cbor: bytes)
        let publicKey = try #require(card.publicKey)
        let met = Encounter(id: UUID(), date: instant, fix: nil, label: "Dublin", note: "")
        return Person(personaID: card.personaID, cardBytes: bytes, card: card, publicKey: publicKey,
                      keyFingerprint: KeyFingerprint(publicKey: publicKey)?.short, trust: .inPerson, source: .scan,
                      tags: [], note: "", gpgKey: nil, photo: photo, createdAt: instant, updatedAt: instant,
                      encounters: [met])
    }

    /// The "Met" date is the Gregorian year, month and day in the zone,
    /// stamped with that calendar, whatever calendar the phone displays.
    /// Add to Contacts and Share as vCard sit in one section and used to
    /// hand over different contacts: the sheet dropped every custom email and
    /// phone field, and attached a photo the vCard would have refused.
    @Test func customNumbersAndAddressesTravelToo() throws {
        let bytes = try Vectors.cbor("maximal-qr-signed")
        var card = try HB1.decode(cbor: bytes)
        card.custom = [
            CustomField(label: "Fax", value: "+35318000000", kind: .phone),
            CustomField(label: "Work", value: "bloom@example.ie", kind: .email),
            CustomField(label: "Desk", value: "3A", kind: .text),
        ]
        let publicKey = try #require(card.publicKey)
        let person = Person(personaID: card.personaID, cardBytes: bytes, card: card, publicKey: publicKey,
                            keyFingerprint: nil, trust: .inPerson, source: .scan, tags: [], note: "",
                            gpgKey: nil, photo: nil, createdAt: instant, updatedAt: instant, encounters: [])

        let contact = UnknownContactView.contact(for: person, met: nil)
        #expect(contact.phoneNumbers.contains { $0.value.stringValue == "+35318000000" })
        #expect(contact.emailAddresses.contains { ($0.value as String) == "bloom@example.ie" })
        // A text field is not a channel and stays off the contact.
        #expect(!contact.emailAddresses.contains { ($0.value as String) == "3A" })
    }

    /// The photo takes the same gate as the vCard's: without it Contacts is
    /// handed bytes it cannot draw.
    @Test func onlyAJPEGBecomesTheContactPicture() throws {
        let notJPEG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(UnknownContactView.contact(for: try person(photo: notJPEG), met: nil).imageData == nil)
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x01]
        #expect(UnknownContactView.contact(for: try person(photo: jpeg), met: nil).imageData == Data(jpeg))
    }

    @Test func metComponentsAreGregorian() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let components = UnknownContactView.metComponents(instant, timeZone: utc)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 29)
        #expect(components.hour == nil)
        #expect(components.calendar?.identifier == .gregorian)
        #expect(components.calendar?.timeZone == utc)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc
        #expect(buddhist.dateComponents([.year], from: instant).year == 2569)
        let samoa = try #require(TimeZone(identifier: "Pacific/Pago_Pago"))
        #expect(UnknownContactView.metComponents(instant, timeZone: samoa).day == 28)
        let kiritimati = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        #expect(UnknownContactView.metComponents(instant, timeZone: kiritimati).day == 30)
        #expect(UnknownContactView.metComponents(instant).calendar?.identifier == .gregorian)
    }

    /// The contact carries the card's fields, the kept photo and the Met
    /// date, and nothing else; without a photo or a meeting, neither.
    @Test func contactCarriesCardKeptPhotoAndMetDate() throws {
        let photo: [UInt8] = [0xff, 0xd8, 0xff, 0xe0] + (0..<100).map { UInt8($0 & 0xff) } + [0xff, 0xd9]
        let contact = UnknownContactView.contact(for: try person(photo: photo), met: instant)
        #expect(contact.organizationName == "Freeman's Journal")
        #expect(contact.phoneNumbers.first?.value.stringValue == "+353871234567")
        #expect(contact.emailAddresses.first.map { String($0.value) } == "henry.flower@example.ie")
        #expect(contact.imageData == Data(photo))
        #expect(contact.postalAddresses.isEmpty)
        #expect(contact.dates.count == 1)
        let date = try #require(contact.dates.first)
        #expect(date.label == "Met")
        #expect(date.value.calendar?.identifier == .gregorian)
        let expected = UnknownContactView.metComponents(instant)
        #expect(date.value.year == expected.year)
        #expect(date.value.month == expected.month)
        #expect(date.value.day == expected.day)

        let bare = UnknownContactView.contact(for: try person(), met: nil)
        #expect(bare.imageData == nil)
        #expect(bare.dates.isEmpty)
    }
}
