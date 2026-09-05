import Foundation
import HatbandCore
import Testing
@testable import Hatband

private func samplePerson() throws -> Person {
    let bytes = try Vectors.cbor("typical-signed")
    let card = try HB1.decode(cbor: bytes)
    let publicKey = card.publicKey!
    let fixed = Encounter(id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000),
                          fix: Fix(latitude: 51.5074, longitude: -0.1278, accuracy: 4321.4),
                          label: "Dublin", note: "By the river")
    let unfixed = Encounter(id: UUID(), date: Date(timeIntervalSince1970: 1_700_100_000),
                            fix: nil, label: "", note: "")
    let southern = Encounter(id: UUID(), date: Date(timeIntervalSince1970: 1_700_200_000),
                             fix: Fix(latitude: -33.8688, longitude: 151.2093, accuracy: 50),
                             label: "Sydney", note: "")
    return Person(personaID: card.personaID, cardBytes: bytes, card: card,
                  publicKey: publicKey, keyFingerprint: KeyFingerprint(publicKey: publicKey)!.short,
                  trust: .keyChanged(previous: [UInt8](repeating: 9, count: 32)),
                  source: .link, tags: ["conference", "2026"], note: "Met at the pub",
                  gpgKey: [1, 2, 3], createdAt: Date(timeIntervalSince1970: 1_600_000_000),
                  updatedAt: Date(timeIntervalSince1970: 1_700_200_001),
                  encounters: [fixed, unfixed, southern])
}

struct PersonCodecTests {
    @Test func roundTripWithKeyChangedAndEncounters() throws {
        let person = try samplePerson()
        let decoded = try PersonCodec.decode(PersonCodec.encode(person))
        #expect(decoded == person)
        #expect(decoded.encounters[0].fix?.longitudeHundredths == -13)
        #expect(decoded.encounters[0].fix?.latitudeHundredths == 5151)
        #expect(decoded.encounters[0].fix?.accuracyMetres == 4321)
        #expect(decoded.encounters[1].fix == nil)
        #expect(decoded.encounters[2].fix?.latitudeHundredths == -3387)
        #expect(decoded.trust == .keyChanged(previous: [UInt8](repeating: 9, count: 32)))
        #expect(PersonCodec.encode(decoded) == PersonCodec.encode(person))
    }

    @Test func cardBytesPreserveSignature() throws {
        let person = try samplePerson()
        let decoded = try PersonCodec.decode(PersonCodec.encode(person))
        #expect(decoded.card.signatureIsValid)
        #expect(decoded.cardBytes == person.cardBytes)
        #expect(decoded.id == Hex.string(decoded.card.personaID))
    }

    @Test func sourceAndTrustRawValues() throws {
        let person = try samplePerson()
        let root = try CBOR.decode(PersonCodec.encode(person))
        #expect(root[4]?.unsignedValue == 2)
        #expect(root[5]?.bytesValue == [UInt8](repeating: 9, count: 32))
        #expect(root[11]?.unsignedValue == 3)

        var scanned = person
        scanned.trust = .inPerson
        scanned.source = .scan
        let scannedRoot = try CBOR.decode(PersonCodec.encode(scanned))
        #expect(scannedRoot[4]?.unsignedValue == 0)
        #expect(scannedRoot[5] == nil)
        #expect(scannedRoot[11]?.unsignedValue == 0)

        var filed = person
        filed.trust = .byFile
        filed.source = .file
        let filedRoot = try CBOR.decode(PersonCodec.encode(filed))
        #expect(filedRoot[4]?.unsignedValue == 1)
        #expect(filedRoot[11]?.unsignedValue == 2)

        var photographed = person
        photographed.source = .photo
        #expect(try CBOR.decode(PersonCodec.encode(photographed))[11]?.unsignedValue == 1)
    }

    @Test func datesAreWholeSeconds() throws {
        var person = try samplePerson()
        person.createdAt = Date(timeIntervalSince1970: 1_700_000_000.75)
        person.encounters[0].date = Date(timeIntervalSince1970: 1_700_000_000.25)
        let root = try CBOR.decode(PersonCodec.encode(person))
        #expect(root[9]?.unsignedValue == 1_700_000_000)
        let decoded = try PersonCodec.decode(PersonCodec.encode(person))
        #expect(decoded.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(decoded.encounters[0].date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func unsupportedVersionRefused() throws {
        let person = try samplePerson()
        var root = try #require(CBOR.decode(PersonCodec.encode(person)).mapValue)
        root[.unsigned(0)] = .unsigned(2)
        #expect(throws: CodecError.unsupportedVersion(2)) {
            try PersonCodec.decode(CBOR.map(root).encoded)
        }
        #expect(throws: CodecError.malformed) {
            try PersonCodec.decode([0xff])
        }
    }

    @Test func unknownKeysIgnored() throws {
        let person = try samplePerson()
        var root = try #require(CBOR.decode(PersonCodec.encode(person)).mapValue)
        root[.unsigned(99)] = .text("later")
        #expect(try PersonCodec.decode(CBOR.map(root).encoded) == person)
    }
}
