import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The floor of the accepted range: the cheapest legal container.
private let iterations = ExportContainer.iterationRange.lowerBound
private let passphrase = "correct horse battery staple"

private func sampleBundle() -> ExportBundle {
    let persona = Persona(id: [1, 2, 3, 4, 5, 6, 7, 8], label: "Personal", keyIndex: 0, color: 1)
    let owner = OwnerCodec.encode(profile: Profile(), personas: [persona], settings: Settings())
    return ExportBundle(seed: (0..<32).map { UInt8($0) }, owner: owner, people: [[0xa0], [0xa1, 0x00, 0x01]])
}

private func rebuilt(_ bundle: ExportBundle, _ change: (inout [CBOR: CBOR]) -> Void) throws -> [UInt8] {
    var map = try #require(CBOR.decode(ExportBundle.encode(bundle)).mapValue)
    change(&map)
    return CBOR.map(map).encoded
}

struct ExportBundleTests {
    @Test func encodeDecodeRoundTrip() throws {
        let bundle = sampleBundle()
        let bytes = ExportBundle.encode(bundle)
        #expect(try ExportBundle.decode(bytes) == bundle)
        let root = try CBOR.decode(bytes)
        #expect(root[0]?.unsignedValue == ExportBundle.version)
        #expect(root[1]?.bytesValue == bundle.seed)
        #expect(root[2]?.bytesValue == bundle.owner)
        #expect(root[3]?.arrayValue?.count == 2)
        #expect(ExportBundle.encode(try ExportBundle.decode(bytes)) == bytes)
        let nobody = ExportBundle(seed: bundle.seed, owner: bundle.owner, people: [])
        #expect(try ExportBundle.decode(ExportBundle.encode(nobody)) == nobody)
    }

    @Test func decodeRefusesWrongVersion() throws {
        let bytes = try rebuilt(sampleBundle()) { $0[.unsigned(0)] = .unsigned(2) }
        #expect(throws: CodecError.unsupportedVersion(2)) {
            try ExportBundle.decode(bytes)
        }
    }

    @Test func decodeIgnoresUnknownKeys() throws {
        let bundle = sampleBundle()
        let bytes = try rebuilt(bundle) { $0[.unsigned(99)] = .text("later") }
        #expect(try ExportBundle.decode(bytes) == bundle)
    }

    @Test func decodeRefusesMalformed() throws {
        #expect(throws: CodecError.malformed) {
            try ExportBundle.decode([0xff])
        }
        #expect(throws: CodecError.malformed) {
            try ExportBundle.decode(CBOR.array([]).encoded)
        }
        let shortSeed = try rebuilt(sampleBundle()) { $0[.unsigned(1)] = .bytes([1, 2, 3]) }
        #expect(throws: CodecError.malformed) {
            try ExportBundle.decode(shortSeed)
        }
        let textPerson = try rebuilt(sampleBundle()) { $0[.unsigned(3)] = .array([.text("not bytes")]) }
        #expect(throws: CodecError.malformed) {
            try ExportBundle.decode(textPerson)
        }
        let noOwner = try rebuilt(sampleBundle()) { $0[.unsigned(2)] = nil }
        #expect(throws: CodecError.malformed) {
            try ExportBundle.decode(noOwner)
        }
    }

    @Test func sealOpenAtMinimumIterations() throws {
        let bundle = sampleBundle()
        let container = try ExportBundle.seal(bundle, passphrase: passphrase, iterations: iterations)
        #expect(try CBOR.decode(container)[2]?.unsignedValue == UInt64(iterations))
        #expect(try ExportBundle.open(container, passphrase: passphrase) == bundle)
        let again = try ExportBundle.seal(bundle, passphrase: passphrase, iterations: iterations)
        #expect(again != container)
    }

    @Test func wrongPassphraseThrows() throws {
        let container = try ExportBundle.seal(sampleBundle(), passphrase: passphrase, iterations: iterations)
        #expect(throws: ExportError.wrongPassphraseOrTampered) {
            try ExportBundle.open(container, passphrase: "correct horse battery stapler")
        }
        var tampered = container
        tampered[tampered.count - 1] ^= 0x01
        #expect(throws: ExportError.wrongPassphraseOrTampered) {
            try ExportBundle.open(tampered, passphrase: passphrase)
        }
    }

    @Test func sealRefusesIterationsOutOfRange() {
        #expect(throws: ExportError.iterationsOutOfRange) {
            try ExportBundle.seal(sampleBundle(), passphrase: passphrase, iterations: 1)
        }
    }
}

// MARK: - Merge

private let dedalusID: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
private let mollyID: [UInt8] = [9, 9, 9, 9, 9, 9, 9, 9]
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func encounter(_ seconds: TimeInterval, _ label: String) -> Encounter {
    Encounter(id: UUID(), date: Date(timeIntervalSince1970: seconds),
              fix: Fix(latitude: 53.3498, longitude: -6.2603, accuracy: 5000), label: label, note: "")
}

/// A signed file-form card from `identity`, stored the way a scan is.
private func makePerson(identity: Identity, personaID: [UInt8], name: String, seq: UInt32,
                        compact: Bool = false, encounters: [Encounter]) throws -> Person {
    var profile = Profile()
    profile.name = name
    profile.email = "someone@example.ie"
    let persona = Persona(id: personaID, label: "Personal", keyIndex: 0, color: 3, channels: [.email],
                          lockScreenChannels: [.email], seq: seq)
    let key = identity.personaSigningKey(index: 0)
    let publicKey = Array(key.publicKey.rawRepresentation)
    let card: Card
    if compact {
        card = CardBuilder.card(profile: profile, persona: persona, form: .lockScreen, issuedDay: 2400)
            .withKeyFingerprint(of: publicKey)
    } else {
        card = try CardBuilder.card(profile: profile, persona: persona, form: .file, issuedDay: 2400).signed(with: key)
    }
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    return Person(personaID: personaID, cardBytes: card.cbor.encoded, card: card,
                  publicKey: compact ? nil : publicKey, keyFingerprint: KeyFingerprint(publicKey: publicKey)?.short,
                  trust: .inPerson, source: compact ? .scan : .file, tags: [], note: "", gpgKey: nil,
                  createdAt: created, updatedAt: created, encounters: encounters)
}

struct BackupMergeTests {
    @Test func personasHigherSeqReplacesKeepingLocalKeyIndex() {
        let local = Persona(id: dedalusID, label: "Work", keyIndex: 2, color: 1, seq: 3)
        let newer = Persona(id: dedalusID, label: "Work, renamed", keyIndex: 7, color: 4, seq: 5)
        let result = BackupMerge.personas(local: [local], imported: [newer])
        #expect(result.changed == 1)
        #expect(result.personas.count == 1)
        #expect(result.personas[0].label == "Work, renamed")
        #expect(result.personas[0].seq == 5)
        #expect(result.personas[0].keyIndex == 2)
        let older = Persona(id: dedalusID, label: "Old", keyIndex: 2, color: 1, seq: 1)
        let unchanged = BackupMerge.personas(local: [local], imported: [older])
        #expect(unchanged.changed == 0)
        #expect(unchanged.personas == [local])
    }

    @Test func personasNewOneAvoidsKeyIndexCollision() {
        let local = Persona(id: dedalusID, label: "Personal", keyIndex: 0, seq: 1)
        let foreign = Persona(id: mollyID, label: "Henry Flower", keyIndex: 0, seq: 1)
        let result = BackupMerge.personas(local: [local], imported: [foreign])
        #expect(result.changed == 1)
        #expect(result.personas.map { $0.id } == [dedalusID, mollyID])
        #expect(result.personas[1].keyIndex == 1)
        let distinct = Persona(id: mollyID, label: "Henry Flower", keyIndex: 5, seq: 1)
        #expect(BackupMerge.personas(local: [local], imported: [distinct]).personas[1].keyIndex == 5)
        #expect(BackupMerge.nextKeyIndex(after: []) == 0)
    }

    @Test func peopleUnionEncountersAndTakeNewerCard() throws {
        let identity = Identity.generate()
        let shared = encounter(1_700_000_000, "Martello tower")
        let onlyLocal = encounter(1_700_300_000, "Eccles Street")
        let onlyImported = encounter(1_700_100_000, "Sandymount")
        let local = try makePerson(identity: identity, personaID: dedalusID, name: "Stephen Dedalus", seq: 3,
                                   encounters: [shared, onlyLocal])
        var imported = try makePerson(identity: identity, personaID: dedalusID, name: "Stephen Dedalus", seq: 5,
                                      encounters: [shared, onlyImported])
        imported.tags = ["poet"]
        imported.note = "Telemachus"
        let molly = try makePerson(identity: Identity.generate(), personaID: mollyID, name: "Molly Bloom", seq: 1,
                                   encounters: [encounter(1_700_200_000, "Gibraltar")])
        let result = BackupMerge.people(local: [local], imported: [imported, molly], now: now)
        #expect(result.added == 1)
        #expect(result.updated == 1)
        #expect(result.encountersAdded == 2)
        #expect(result.keyChanges == 0)
        #expect(result.people.count == 2)
        let dedalus = try #require(result.people.first { $0.personaID == dedalusID })
        #expect(dedalus.card.seq == 5)
        #expect(dedalus.card.signatureIsValid)
        #expect(dedalus.cardBytes == imported.cardBytes)
        #expect(dedalus.encounters.map { $0.id } == [shared.id, onlyImported.id, onlyLocal.id])
        #expect(dedalus.tags == ["poet"])
        #expect(dedalus.note == "Telemachus")
        #expect(dedalus.updatedAt == now)
        #expect(dedalus.createdAt == local.createdAt)
        #expect(result.people[1] == molly)
    }

    @Test func peopleKeyChangeKeepsLocalPinAndCard() throws {
        let pinned = Identity.generate()
        let other = Identity.generate()
        let meeting = encounter(1_700_000_000, "Davy Byrne's")
        let local = try makePerson(identity: pinned, personaID: dedalusID, name: "Stephen Dedalus", seq: 3,
                                   encounters: [])
        let imported = try makePerson(identity: other, personaID: dedalusID, name: "Stephen Dedalus", seq: 9,
                                      encounters: [meeting])
        let result = BackupMerge.people(local: [local], imported: [imported], now: now)
        #expect(result.keyChanges == 1)
        #expect(result.updated == 1)
        #expect(result.encountersAdded == 1)
        let dedalus = try #require(result.people.first)
        #expect(dedalus.publicKey == local.publicKey)
        #expect(dedalus.card.seq == 3)
        #expect(dedalus.cardBytes == local.cardBytes)
        #expect(dedalus.trust == .inPerson)
        #expect(dedalus.encounters.map { $0.id } == [meeting.id])
        #expect(!BackupMerge.keysMatch(local, imported))
    }

    @Test func compactImportNeverReplacesAFullCard() throws {
        let identity = Identity.generate()
        let full = try makePerson(identity: identity, personaID: dedalusID, name: "Stephen Dedalus", seq: 2, encounters: [])
        let compact = try makePerson(identity: identity, personaID: dedalusID, name: "Stephen Dedalus", seq: 9,
                                     compact: true, encounters: [])
        #expect(BackupMerge.keysMatch(full, compact))
        #expect(BackupMerge.keysMatch(compact, full))
        let result = BackupMerge.people(local: [full], imported: [compact], now: now)
        #expect(result.updated == 0)
        #expect(result.keyChanges == 0)
        #expect(result.people == [full])
        let upgraded = BackupMerge.people(local: [compact], imported: [full], now: now)
        #expect(upgraded.updated == 1)
        #expect(upgraded.people[0].publicKey == full.publicKey)
        #expect(upgraded.people[0].card.signatureIsValid)
        let stranger = try makePerson(identity: Identity.generate(), personaID: dedalusID, name: "Stephen Dedalus",
                                      seq: 9, compact: true, encounters: [])
        #expect(!BackupMerge.keysMatch(full, stranger))
        #expect(!BackupMerge.keysMatch(compact, stranger))
    }
}
