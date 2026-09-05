import Foundation
import HatbandCore

nonisolated enum CodecError: Error, Equatable {
    case malformed
    case unsupportedVersion(UInt64)
}

/// The owner blob: `{0 version, 1 profile Card.cbor, 2 [persona], 3 settings}`.
/// Unknown keys are ignored; another version is refused.
nonisolated enum OwnerCodec {
    static let version: UInt64 = 1

    static func encode(profile: Profile, personas: [Persona], settings: Settings) -> [UInt8] {
        var map: [CBOR: CBOR] = [:]
        map[.unsigned(0)] = .unsigned(version)
        map[.unsigned(1)] = card(profile).cbor
        map[.unsigned(2)] = .array(personas.map { encode($0) })
        map[.unsigned(3)] = encode(settings)
        return CBOR.map(map).encoded
    }

    static func decode(_ bytes: [UInt8]) throws -> (profile: Profile, personas: [Persona], settings: Settings) {
        let root: CBOR
        do {
            root = try CBOR.decode(bytes)
        } catch {
            throw CodecError.malformed
        }
        guard root.mapValue != nil, let version = root[0]?.unsignedValue else { throw CodecError.malformed }
        guard version == OwnerCodec.version else { throw CodecError.unsupportedVersion(version) }
        guard let profileValue = root[1], let personaValues = root[2]?.arrayValue else { throw CodecError.malformed }
        let profile = profile(from: try decodeCard(profileValue))
        let personas = try personaValues.map { try decodePersona($0) }
        var settings = Settings()
        if let settingsValue = root[3] {
            settings = try decodeSettings(settingsValue)
        }
        return (profile, personas, settings)
    }

    /// `personaID` eight zero bytes, `issuedDay` 0, every field copied.
    static func card(_ profile: Profile) -> Card {
        var card = Card(personaID: [UInt8](repeating: 0, count: 8), issuedDay: 0)
        card.name = profile.name
        card.company = profile.company
        card.phone = profile.phone
        card.email = profile.email
        card.website = profile.website
        card.github = profile.github
        card.linkedin = profile.linkedin
        card.mastodon = profile.mastodon
        card.signal = profile.signal
        card.calendly = profile.calendly
        card.ssh = profile.ssh
        card.gpgFingerprint = profile.gpgFingerprint
        card.custom = profile.custom
        card.photo = profile.photo
        card.gpgKey = profile.gpgKey
        return card
    }

    static func profile(from card: Card) -> Profile {
        var profile = Profile()
        profile.name = card.name
        profile.company = card.company
        profile.phone = card.phone
        profile.email = card.email
        profile.website = card.website
        profile.github = card.github
        profile.linkedin = card.linkedin
        profile.mastodon = card.mastodon
        profile.signal = card.signal
        profile.calendly = card.calendly
        profile.ssh = card.ssh
        profile.gpgFingerprint = card.gpgFingerprint
        profile.custom = card.custom
        profile.photo = card.photo
        profile.gpgKey = card.gpgKey
        return profile
    }

    // MARK: - Persona

    /// `{0 id, 1 label, 2 keyIndex, 3 color, 4 [channel raw], 5 [customLabels], 6 includeCompany,
    /// 7 includePhoto, 8 displayName?, 9 [lockScreenChannels raw], 10 aliasProfile Card.cbor?, 11 seq}`
    static func encode(_ persona: Persona) -> CBOR {
        var map: [CBOR: CBOR] = [:]
        map[.unsigned(0)] = .bytes(persona.id)
        map[.unsigned(1)] = .text(persona.label)
        map[.unsigned(2)] = .unsigned(UInt64(persona.keyIndex))
        map[.unsigned(3)] = .unsigned(UInt64(persona.color))
        map[.unsigned(4)] = .array(persona.channels.map { $0.rawValue }.sorted().map { .unsigned($0) })
        map[.unsigned(5)] = .array(persona.customLabels.sorted().map { .text($0) })
        map[.unsigned(6)] = .bool(persona.includeCompany)
        map[.unsigned(7)] = .bool(persona.includePhoto)
        if let displayName = persona.displayName {
            map[.unsigned(8)] = .text(displayName)
        }
        map[.unsigned(9)] = .array(persona.lockScreenChannels.map { .unsigned($0.rawValue) })
        if let alias = persona.aliasProfile {
            map[.unsigned(10)] = card(alias).cbor
        }
        map[.unsigned(11)] = .unsigned(UInt64(persona.seq))
        return .map(map)
    }

    private static func decodePersona(_ value: CBOR) throws -> Persona {
        guard value.mapValue != nil,
              let id = value[0]?.bytesValue, id.count == 8,
              let label = value[1]?.textValue,
              let keyIndex = value[2]?.unsignedValue, keyIndex <= UInt64(UInt32.max)
        else { throw CodecError.malformed }
        var persona = Persona(id: id, label: label, keyIndex: UInt32(keyIndex))
        if let color = value[3]?.unsignedValue {
            guard color <= UInt64(UInt8.max) else { throw CodecError.malformed }
            persona.color = UInt8(color)
        }
        if let raws = value[4]?.arrayValue {
            persona.channels = Set(try fieldKeys(raws))
        }
        if let labels = value[5]?.arrayValue {
            persona.customLabels = Set(try texts(labels))
        }
        if let flag = value[6]?.boolValue {
            persona.includeCompany = flag
        }
        if let flag = value[7]?.boolValue {
            persona.includePhoto = flag
        }
        if let displayName = value[8]?.textValue {
            persona.displayName = displayName
        }
        if let raws = value[9]?.arrayValue {
            persona.lockScreenChannels = try fieldKeys(raws)
        }
        if let alias = value[10] {
            persona.aliasProfile = profile(from: try decodeCard(alias))
        }
        if let seq = value[11]?.unsignedValue {
            guard seq <= UInt64(UInt32.max) else { throw CodecError.malformed }
            persona.seq = UInt32(seq)
        }
        return persona
    }

    // MARK: - Settings

    /// `{0 appLock, 1 includeInBackup, 2 homeWidget, 3 showNameOnLockScreen, 4 alwaysOnQR,
    /// 5 durationMinutes, 6 lastPersonaID?}`
    static func encode(_ settings: Settings) -> CBOR {
        var map: [CBOR: CBOR] = [:]
        map[.unsigned(0)] = .bool(settings.appLock)
        map[.unsigned(1)] = .bool(settings.includeInBackup)
        map[.unsigned(2)] = .bool(settings.homeWidget)
        map[.unsigned(3)] = .bool(settings.showNameOnLockScreen)
        map[.unsigned(4)] = .bool(settings.alwaysOnQR)
        map[.unsigned(5)] = .unsigned(UInt64(max(0, settings.durationMinutes)))
        if let last = settings.lastPersonaID {
            map[.unsigned(6)] = .bytes(last)
        }
        return .map(map)
    }

    /// Absent keys keep their defaults.
    private static func decodeSettings(_ value: CBOR) throws -> Settings {
        guard value.mapValue != nil else { throw CodecError.malformed }
        var settings = Settings()
        if let flag = value[0]?.boolValue { settings.appLock = flag }
        if let flag = value[1]?.boolValue { settings.includeInBackup = flag }
        if let flag = value[2]?.boolValue { settings.homeWidget = flag }
        if let flag = value[3]?.boolValue { settings.showNameOnLockScreen = flag }
        if let flag = value[4]?.boolValue { settings.alwaysOnQR = flag }
        if let minutes = value[5]?.intValue { settings.durationMinutes = minutes }
        if let last = value[6]?.bytesValue { settings.lastPersonaID = last }
        return settings
    }

    // MARK: - Shared

    private static func decodeCard(_ value: CBOR) throws -> Card {
        do {
            return try Card(cbor: value)
        } catch {
            throw CodecError.malformed
        }
    }

    /// Unknown channel values from a newer app are dropped, not refused.
    private static func fieldKeys(_ values: [CBOR]) throws -> [FieldKey] {
        var keys: [FieldKey] = []
        for value in values {
            guard let raw = value.unsignedValue else { throw CodecError.malformed }
            if let key = FieldKey(rawValue: raw) {
                keys.append(key)
            }
        }
        return keys
    }

    private static func texts(_ values: [CBOR]) throws -> [String] {
        var out: [String] = []
        for value in values {
            guard let text = value.textValue else { throw CodecError.malformed }
            out.append(text)
        }
        return out
    }
}
