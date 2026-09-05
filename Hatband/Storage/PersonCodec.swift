import Foundation
import HatbandCore

/// The person body, sealed under the database key:
/// `{0 version, 1 cardBytes, 2 publicKey?, 3 keyFingerprint?, 4 trust uint, 5 previousKey?, 6 [tags],
/// 7 note, 8 gpgKey?, 9 createdAt, 10 updatedAt, 11 source uint, 12 [encounter]}`;
/// encounter `{0 uuid 16 bytes, 1 date, 2 latHundredths int?, 3 lonHundredths int?, 4 accuracyMetres uint?,
/// 5 label, 6 note}`. Dates are whole unix seconds.
nonisolated enum PersonCodec {
    static let version: UInt64 = 1

    static func encode(_ person: Person) -> [UInt8] {
        var map: [CBOR: CBOR] = [:]
        map[.unsigned(0)] = .unsigned(version)
        map[.unsigned(1)] = .bytes(person.cardBytes)
        if let key = person.publicKey {
            map[.unsigned(2)] = .bytes(key)
        }
        if let fingerprint = person.keyFingerprint {
            map[.unsigned(3)] = .bytes(fingerprint)
        }
        switch person.trust {
        case .inPerson:
            map[.unsigned(4)] = .unsigned(0)
        case .byFile:
            map[.unsigned(4)] = .unsigned(1)
        case .keyChanged(let previous):
            map[.unsigned(4)] = .unsigned(2)
            map[.unsigned(5)] = .bytes(previous)
        }
        map[.unsigned(6)] = .array(person.tags.map { .text($0) })
        map[.unsigned(7)] = .text(person.note)
        if let gpgKey = person.gpgKey {
            map[.unsigned(8)] = .bytes(gpgKey)
        }
        map[.unsigned(9)] = seconds(person.createdAt)
        map[.unsigned(10)] = seconds(person.updatedAt)
        map[.unsigned(11)] = .unsigned(UInt64(person.source.rawValue))
        map[.unsigned(12)] = .array(person.encounters.map { encode($0) })
        return CBOR.map(map).encoded
    }

    /// `card` is `HB1.decode(cbor: cardBytes)`.
    static func decode(_ bytes: [UInt8]) throws -> Person {
        let root: CBOR
        do {
            root = try CBOR.decode(bytes)
        } catch {
            throw CodecError.malformed
        }
        guard root.mapValue != nil, let version = root[0]?.unsignedValue else { throw CodecError.malformed }
        guard version == PersonCodec.version else { throw CodecError.unsupportedVersion(version) }
        guard let cardBytes = root[1]?.bytesValue else { throw CodecError.malformed }
        let card: Card
        do {
            card = try HB1.decode(cbor: cardBytes)
        } catch {
            throw CodecError.malformed
        }
        guard let trustRaw = root[4]?.unsignedValue else { throw CodecError.malformed }
        let trust: Trust
        switch trustRaw {
        case 0:
            trust = .inPerson
        case 1:
            trust = .byFile
        case 2:
            guard let previous = root[5]?.bytesValue else { throw CodecError.malformed }
            trust = .keyChanged(previous: previous)
        default:
            throw CodecError.malformed
        }
        var tags: [String] = []
        for value in root[6]?.arrayValue ?? [] {
            guard let text = value.textValue else { throw CodecError.malformed }
            tags.append(text)
        }
        guard let createdValue = root[9], let createdAt = date(createdValue),
              let updatedValue = root[10], let updatedAt = date(updatedValue),
              let sourceRaw = root[11]?.unsignedValue, sourceRaw <= UInt64(UInt8.max),
              let source = CardSource(rawValue: UInt8(sourceRaw))
        else { throw CodecError.malformed }
        var encounters: [Encounter] = []
        for value in root[12]?.arrayValue ?? [] {
            encounters.append(try decodeEncounter(value))
        }
        return Person(personaID: card.personaID, cardBytes: cardBytes, card: card,
                      publicKey: root[2]?.bytesValue, keyFingerprint: root[3]?.bytesValue,
                      trust: trust, source: source, tags: tags, note: root[7]?.textValue ?? "",
                      gpgKey: root[8]?.bytesValue, createdAt: createdAt, updatedAt: updatedAt,
                      encounters: encounters)
    }

    // MARK: - Encounter

    static func encode(_ encounter: Encounter) -> CBOR {
        var map: [CBOR: CBOR] = [:]
        map[.unsigned(0)] = .bytes(uuidBytes(encounter.id))
        map[.unsigned(1)] = seconds(encounter.date)
        if let fix = encounter.fix {
            map[.unsigned(2)] = integer(fix.latitudeHundredths)
            map[.unsigned(3)] = integer(fix.longitudeHundredths)
            map[.unsigned(4)] = .unsigned(UInt64(max(0, fix.accuracyMetres)))
        }
        map[.unsigned(5)] = .text(encounter.label)
        map[.unsigned(6)] = .text(encounter.note)
        return .map(map)
    }

    private static func decodeEncounter(_ value: CBOR) throws -> Encounter {
        guard value.mapValue != nil,
              let idBytes = value[0]?.bytesValue, let id = uuid(from: idBytes),
              let dateValue = value[1], let date = date(dateValue)
        else { throw CodecError.malformed }
        var fix: Fix?
        if let latitude = value[2]?.intValue, let longitude = value[3]?.intValue {
            let accuracy = value[4]?.intValue ?? 0
            fix = Fix(latitude: Double(latitude) / 100, longitude: Double(longitude) / 100, accuracy: Double(accuracy))
        }
        return Encounter(id: id, date: date, fix: fix, label: value[5]?.textValue ?? "", note: value[6]?.textValue ?? "")
    }

    // MARK: - Scalars

    static func seconds(_ date: Date) -> CBOR {
        integer(Int(date.timeIntervalSince1970.rounded(.down)))
    }

    static func date(_ value: CBOR) -> Date? {
        guard let seconds = value.intValue else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func integer(_ value: Int) -> CBOR {
        value >= 0 ? .unsigned(UInt64(value)) : .negative(UInt64(-(value + 1)))
    }

    static func uuidBytes(_ id: UUID) -> [UInt8] {
        withUnsafeBytes(of: id.uuid) { Array($0) }
    }

    static func uuid(from bytes: [UInt8]) -> UUID? {
        guard bytes.count == 16 else { return nil }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
