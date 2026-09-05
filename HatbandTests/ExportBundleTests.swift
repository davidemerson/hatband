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

    /// Key 4 carries the persona-index counter; an export from before it
    /// travelled decodes to nil, and anything that is not a 32-bit count
    /// is malformed.
    @Test func nextKeyIndexRidesUnderKey4() throws {
        let bundle = sampleBundle()
        #expect(try CBOR.decode(ExportBundle.encode(bundle))[4] == nil)
        var counted = bundle
        counted.nextKeyIndex = 7
        let bytes = ExportBundle.encode(counted)
        #expect(try CBOR.decode(bytes)[4]?.unsignedValue == 7)
        #expect(try ExportBundle.decode(bytes) == counted)
        #expect(try ExportBundle.decode(bytes).nextKeyIndex == 7)
        #expect(ExportBundle.encode(try ExportBundle.decode(bytes)) == bytes)
        let older = try rebuilt(counted) { $0[.unsigned(4)] = nil }
        #expect(try ExportBundle.decode(older).nextKeyIndex == nil)
        #expect(try ExportBundle.decode(older) == bundle)
        let tooBig = try rebuilt(counted) { $0[.unsigned(4)] = .unsigned(UInt64(UInt32.max) + 1) }
        #expect(throws: CodecError.malformed) {
            try ExportBundle.decode(tooBig)
        }
        let text = try rebuilt(counted) { $0[.unsigned(4)] = .text("7") }
        #expect(throws: CodecError.malformed) {
            try ExportBundle.decode(text)
        }
        let sealed = try ExportBundle.seal(counted, passphrase: passphrase, iterations: iterations)
        #expect(try ExportBundle.open(sealed, passphrase: passphrase).nextKeyIndex == 7)
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
                        compact: Bool = false, photo: [UInt8]? = nil, encounters: [Encounter]) throws -> Person {
    var profile = Profile()
    profile.name = name
    profile.email = "someone@example.ie"
    profile.photo = photo
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

    /// A colliding import takes an index no lower than the higher counter,
    /// so it never lands on one a deleted persona held, and the result
    /// reports the counter to store: above every index and both counters.
    @Test func personasCollisionAllocatesFromTheCounter() {
        let local = Persona(id: dedalusID, label: "Personal", keyIndex: 0, seq: 1)
        let foreign = Persona(id: mollyID, label: "Henry Flower", keyIndex: 0, seq: 1)
        let result = BackupMerge.personas(local: [local], imported: [foreign], nextKeyIndex: 5)
        #expect(result.personas.map { $0.keyIndex } == [0, 5])
        #expect(result.nextKeyIndex == 6)
        let low = BackupMerge.personas(local: [local], imported: [foreign], nextKeyIndex: 1)
        #expect(low.personas.map { $0.keyIndex } == [0, 1])
        #expect(low.nextKeyIndex == 2)
        let distinct = Persona(id: mollyID, label: "Henry Flower", keyIndex: 9, seq: 1)
        let kept = BackupMerge.personas(local: [local], imported: [distinct], nextKeyIndex: 5)
        #expect(kept.personas[1].keyIndex == 9)
        #expect(kept.nextKeyIndex == 10)
        #expect(BackupMerge.personas(local: [local], imported: [], nextKeyIndex: 3).nextKeyIndex == 3)
        #expect(BackupMerge.personas(local: [local], imported: []).nextKeyIndex == 1)
    }

    /// Under another seed an imported index names no key here and may be
    /// one a deleted local persona held, so every persona added from a
    /// different identity takes a fresh index from the counter; under the
    /// same seed only a live collision moves one. A replacement by id keeps
    /// the local index either way.
    @Test func personasFromAnotherSeedTakeFreshIndices() {
        let local = Persona(id: dedalusID, label: "Personal", keyIndex: 0, seq: 1)
        let work = Persona(id: mollyID, label: "Work", keyIndex: 1, seq: 1)
        let club = Persona(id: [3, 3, 3, 3, 3, 3, 3, 3], label: "Club", keyIndex: 2, seq: 1)
        // Local counter 3: indices 1 and 2 were handed out here and retired.
        let foreign = BackupMerge.personas(local: [local], imported: [work, club], nextKeyIndex: 3, sameSeed: false)
        #expect(foreign.personas.map { $0.id } == [dedalusID, mollyID, club.id])
        #expect(foreign.personas.map { $0.keyIndex } == [0, 3, 4])
        #expect(foreign.nextKeyIndex == 5)
        #expect(foreign.changed == 2)
        let own = BackupMerge.personas(local: [local], imported: [work, club], nextKeyIndex: 3, sameSeed: true)
        #expect(own.personas.map { $0.keyIndex } == [0, 1, 2])
        #expect(own.nextKeyIndex == 3)
        #expect(BackupMerge.personas(local: [local], imported: [work, club], nextKeyIndex: 3) == own)
        let renamed = Persona(id: dedalusID, label: "Renamed", keyIndex: 9, seq: 2)
        let replaced = BackupMerge.personas(local: [local], imported: [renamed], nextKeyIndex: 3, sameSeed: false)
        #expect(replaced.personas.map { $0.keyIndex } == [0])
        #expect(replaced.personas[0].label == "Renamed")
        #expect(replaced.nextKeyIndex == 3)
    }

    /// A newer card without a photo replaces the stored one and the earlier
    /// photo stays beside it, the stored bytes still the signed ones; a
    /// photo is taken where there was none; never from a different key.
    @Test func peopleKeepEarlierPhotoBesideTheNewerCard() throws {
        let identity = Identity.generate()
        let photo: [UInt8] = [0xff, 0xd8, 0xff, 0xe0] + (0..<100).map { UInt8($0 & 0xff) } + [0xff, 0xd9]
        let local = try makePerson(identity: identity, personaID: dedalusID, name: "Stephen Dedalus", seq: 3,
                                   photo: photo, encounters: [])
        #expect(local.card.photo == photo)
        let imported = try makePerson(identity: identity, personaID: dedalusID, name: "Stephen Dedalus", seq: 5,
                                      encounters: [])
        let result = BackupMerge.people(local: [local], imported: [imported], now: now)
        let dedalus = try #require(result.people.first)
        #expect(dedalus.cardBytes == imported.cardBytes)
        #expect(dedalus.card.signatureIsValid)
        #expect(dedalus.card.photo == nil)
        #expect(dedalus.photo == photo)
        #expect(dedalus.currentPhoto == photo)
        #expect(try PersonCodec.decode(PersonCodec.encode(dedalus)) == dedalus)

        let adopted = BackupMerge.people(local: [imported], imported: [local], now: now)
        let filled = try #require(adopted.people.first)
        #expect(filled.cardBytes == imported.cardBytes)
        #expect(filled.photo == photo)
        #expect(adopted.updated == 1)

        let stranger = try makePerson(identity: Identity.generate(), personaID: dedalusID, name: "Stephen Dedalus",
                                      seq: 9, photo: photo, encounters: [])
        let refused = BackupMerge.people(local: [imported], imported: [stranger], now: now)
        #expect(refused.people.first?.currentPhoto == nil)
        #expect(refused.keyChanges == 1)
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
