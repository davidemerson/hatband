import Foundation
import HatbandCore

/// The export body, `{0 version, 1 seed, 2 owner blob, 3 [person body]}`,
/// sealed in an `ExportContainer` under the passphrase. Unknown keys are
/// ignored; another version is refused.
nonisolated struct ExportBundle: Equatable, Sendable {
    static let version: UInt64 = 1

    var seed: [UInt8]
    var owner: [UInt8]
    var people: [[UInt8]]

    static func encode(_ bundle: ExportBundle) -> [UInt8] {
        var map: [CBOR: CBOR] = [:]
        map[.unsigned(0)] = .unsigned(version)
        map[.unsigned(1)] = .bytes(bundle.seed)
        map[.unsigned(2)] = .bytes(bundle.owner)
        map[.unsigned(3)] = .array(bundle.people.map { .bytes($0) })
        return CBOR.map(map).encoded
    }

    static func decode(_ bytes: [UInt8]) throws -> ExportBundle {
        let root: CBOR
        do {
            root = try CBOR.decode(bytes)
        } catch {
            throw CodecError.malformed
        }
        guard root.mapValue != nil, let version = root[0]?.unsignedValue else { throw CodecError.malformed }
        guard version == ExportBundle.version else { throw CodecError.unsupportedVersion(version) }
        guard let seed = root[1]?.bytesValue, seed.count == Identity.seedLength,
              let owner = root[2]?.bytesValue,
              let bodies = root[3]?.arrayValue
        else { throw CodecError.malformed }
        var people: [[UInt8]] = []
        for body in bodies {
            guard let bytes = body.bytesValue else { throw CodecError.malformed }
            people.append(bytes)
        }
        return ExportBundle(seed: seed, owner: owner, people: people)
    }

    static func seal(_ bundle: ExportBundle, passphrase: String,
                     iterations: Int = ExportContainer.defaultIterations) throws -> [UInt8] {
        try ExportContainer.seal(encode(bundle), passphrase: passphrase, iterations: iterations)
    }

    static func open(_ container: [UInt8], passphrase: String) throws -> ExportBundle {
        try decode(try ExportContainer.open(container, passphrase: passphrase))
    }
}

/// Merging an opened bundle into what this phone holds. Pure; the model
/// persists the result.
nonisolated enum BackupMerge {
    nonisolated struct PersonaResult: Equatable {
        var personas: [Persona]
        /// Added or replaced.
        var changed: Int
    }

    nonisolated struct PeopleResult: Equatable {
        var people: [Person]
        var added: Int
        var updated: Int
        var encountersAdded: Int
        var keyChanges: Int
    }

    nonisolated struct Merged: Equatable {
        var person: Person
        var changed: Bool
        var encountersAdded: Int
        var keyChanged: Bool
    }

    /// Imported personas join the local list by id. The same id with a
    /// higher `seq` replaces the local one but keeps the local `keyIndex`,
    /// so contacts who pinned that persona see the same key. A new persona
    /// whose `keyIndex` a local one already uses gets a fresh index: two
    /// personas never share a signing key.
    static func personas(local: [Persona], imported: [Persona]) -> PersonaResult {
        var result = local
        var changed = 0
        for incoming in imported {
            var persona = incoming
            if let index = result.firstIndex(where: { $0.id == persona.id }) {
                guard persona.seq > result[index].seq else { continue }
                persona.keyIndex = result[index].keyIndex
                result[index] = persona
                changed += 1
            } else {
                if result.contains(where: { $0.keyIndex == persona.keyIndex }) {
                    persona.keyIndex = nextKeyIndex(after: result)
                }
                result.append(persona)
                changed += 1
            }
        }
        return PersonaResult(personas: result, changed: changed)
    }

    /// One above the highest index in use; 0 for an empty list.
    static func nextKeyIndex(after personas: [Persona]) -> UInt32 {
        guard let highest = personas.map({ $0.keyIndex }).max() else { return 0 }
        return highest + 1
    }

    /// Imported people join by persona id: unknown ones are added; known
    /// ones are merged (see `merge`).
    static func people(local: [Person], imported: [Person], now: Date) -> PeopleResult {
        var result = local
        var added = 0
        var updated = 0
        var encountersAdded = 0
        var keyChanges = 0
        for incoming in imported {
            guard let index = result.firstIndex(where: { $0.personaID == incoming.personaID }) else {
                result.append(incoming)
                added += 1
                encountersAdded += incoming.encounters.count
                continue
            }
            let merged = merge(local: result[index], imported: incoming, now: now)
            if merged.keyChanged {
                keyChanges += 1
            }
            if merged.changed {
                updated += 1
                encountersAdded += merged.encountersAdded
            }
            result[index] = merged.person
        }
        return PeopleResult(people: result, added: added, updated: updated,
                            encountersAdded: encountersAdded, keyChanges: keyChanges)
    }

    /// The local pin always stays. A full imported card signed by the same
    /// key with a higher `seq` (or a full card where only a compact one was
    /// held) replaces the stored card; a different key is counted and its
    /// card ignored. Encounters are unioned by uuid, tags unioned, an empty
    /// note filled, and a verified GPG key taken when there was none.
    static func merge(local: Person, imported: Person, now: Date) -> Merged {
        let keyChanged = !keysMatch(local, imported)
        var person = local
        var changed = false
        if !keyChanged, !imported.card.isCompact,
           local.card.isCompact || imported.card.seq > local.card.seq {
            person.cardBytes = imported.cardBytes
            person.card = imported.card
            person.publicKey = imported.publicKey ?? local.publicKey
            person.keyFingerprint = imported.keyFingerprint ?? local.keyFingerprint
            changed = true
        }
        let known = Set(local.encounters.map { $0.id })
        let fresh = imported.encounters.filter { !known.contains($0.id) }
        if !fresh.isEmpty {
            person.encounters = (local.encounters + fresh).sorted { $0.date < $1.date }
            changed = true
        }
        for tag in imported.tags where !person.tags.contains(tag) {
            person.tags.append(tag)
            changed = true
        }
        if person.note.isEmpty, !imported.note.isEmpty {
            person.note = imported.note
            changed = true
        }
        if !keyChanged, local.gpgKey == nil, let gpgKey = imported.gpgKey {
            person.gpgKey = gpgKey
            changed = true
        }
        if changed {
            person.updatedAt = now
        }
        return Merged(person: person, changed: changed, encountersAdded: fresh.count, keyChanged: keyChanged)
    }

    /// Whether two records of the same persona vouch for the same key, by
    /// whatever each holds: a full key, a compact fingerprint, or both.
    static func keysMatch(_ a: Person, _ b: Person) -> Bool {
        if let x = a.publicKey, let y = b.publicKey {
            return x == y
        }
        if let x = a.publicKey, let f = b.keyFingerprint {
            return KeyFingerprint.matches(short: f, publicKey: x)
        }
        if let f = a.keyFingerprint, let y = b.publicKey {
            return KeyFingerprint.matches(short: f, publicKey: y)
        }
        if let f = a.keyFingerprint, let g = b.keyFingerprint {
            return f == g
        }
        return true
    }
}
