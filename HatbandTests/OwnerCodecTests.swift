import Foundation
import HatbandCore
import Testing
@testable import Hatband

private func fullProfile() -> Profile {
    var profile = Profile()
    profile.name = "Leopold Bloom"
    profile.company = "Freeman's Journal"
    profile.phone = "+353871234567"
    profile.email = "bloom@example.ie"
    profile.website = Website(address: "nnix.com/~bloom", insecure: true)
    profile.github = "bloom"
    profile.linkedin = "leopold-bloom"
    profile.mastodon = "bloom@merveilles.town"
    profile.signal = .username([UInt8](repeating: 5, count: 48))
    profile.calendly = "bloom/coffee"
    profile.ssh = SSHKeyField(kind: 1, bytes: [UInt8](repeating: 1, count: 32))
    profile.gpgFingerprint = [UInt8](repeating: 2, count: 20)
    profile.gpgKey = [UInt8](repeating: 3, count: 500)
    profile.photo = [UInt8](repeating: 4, count: 100)
    profile.custom = [
        CustomField(label: "Pub", value: "Davy Byrne's"),
        CustomField(label: "Matrix", value: "https://matrix.to/#/@bloom:example.ie", kind: .url),
    ]
    return profile
}

private let work = Persona(id: [1, 1, 1, 1, 1, 1, 1, 1], label: "Work", keyIndex: 0, color: 2,
                           channels: [.email, .website, .ssh, .gpgFingerprint], customLabels: ["Matrix"],
                           includeCompany: true, includePhoto: false, displayName: "L. Bloom",
                           lockScreenChannels: [.email, .mastodon], seq: 3)

private func aliasPersona() -> Persona {
    var flower = Profile()
    flower.name = "Henry Flower"
    flower.email = "henry@flower.ie"
    return Persona(id: [9, 9, 9, 9, 9, 9, 9, 9], label: "Henry Flower", keyIndex: 3, color: 4,
                   lockScreenChannels: [.email], aliasProfile: flower, seq: 7)
}

private func fullSettings() -> Settings {
    var settings = Settings()
    settings.appLock = false
    settings.includeInBackup = true
    settings.homeWidget = true
    settings.showNameOnLockScreen = false
    settings.alwaysOnQR = true
    settings.durationMinutes = 30
    settings.lastPersonaID = work.id
    return settings
}

struct OwnerCodecTests {
    @Test func roundTripEveryField() throws {
        let profile = fullProfile()
        let personas = [work, aliasPersona()]
        let settings = fullSettings()
        let bytes = OwnerCodec.encode(profile: profile, personas: personas, settings: settings)
        let decoded = try OwnerCodec.decode(bytes)
        #expect(decoded.profile == profile)
        #expect(decoded.personas == personas)
        #expect(decoded.settings == settings)
        let again = OwnerCodec.encode(profile: decoded.profile, personas: decoded.personas, settings: decoded.settings)
        #expect(again == bytes)
    }

    @Test func unknownKeysIgnored() throws {
        let bytes = OwnerCodec.encode(profile: fullProfile(), personas: [work], settings: fullSettings())
        var root = try #require(CBOR.decode(bytes).mapValue)
        root[.unsigned(99)] = .text("later")
        var settings = try #require(root[.unsigned(3)]?.mapValue)
        settings[.unsigned(42)] = .bool(true)
        root[.unsigned(3)] = .map(settings)
        var personas = try #require(root[.unsigned(2)]?.arrayValue)
        var persona = try #require(personas[0].mapValue)
        persona[.unsigned(50)] = .array([])
        personas[0] = .map(persona)
        root[.unsigned(2)] = .array(personas)
        let decoded = try OwnerCodec.decode(CBOR.map(root).encoded)
        #expect(decoded.profile == fullProfile())
        #expect(decoded.personas == [work])
        #expect(decoded.settings == fullSettings())
    }

    @Test func unsupportedVersionRefused() throws {
        let bytes = OwnerCodec.encode(profile: Profile(), personas: [], settings: Settings())
        var root = try #require(CBOR.decode(bytes).mapValue)
        root[.unsigned(0)] = .unsigned(2)
        #expect(throws: CodecError.unsupportedVersion(2)) {
            try OwnerCodec.decode(CBOR.map(root).encoded)
        }
    }

    @Test func malformedRefused() {
        #expect(throws: CodecError.malformed) {
            try OwnerCodec.decode([0xff])
        }
        #expect(throws: CodecError.malformed) {
            try OwnerCodec.decode(CBOR.array([]).encoded)
        }
        var missingProfile: [CBOR: CBOR] = [:]
        missingProfile[.unsigned(0)] = .unsigned(1)
        missingProfile[.unsigned(2)] = .array([])
        #expect(throws: CodecError.malformed) {
            try OwnerCodec.decode(CBOR.map(missingProfile).encoded)
        }
        var badPersona: [CBOR: CBOR] = [:]
        badPersona[.unsigned(0)] = .unsigned(1)
        badPersona[.unsigned(1)] = OwnerCodec.card(Profile()).cbor
        badPersona[.unsigned(2)] = .array([.text("not a persona")])
        #expect(throws: CodecError.malformed) {
            try OwnerCodec.decode(CBOR.map(badPersona).encoded)
        }
    }

    @Test func absentSettingsAreDefaults() throws {
        var root: [CBOR: CBOR] = [:]
        root[.unsigned(0)] = .unsigned(1)
        root[.unsigned(1)] = OwnerCodec.card(Profile()).cbor
        root[.unsigned(2)] = .array([])
        let decoded = try OwnerCodec.decode(CBOR.map(root).encoded)
        #expect(decoded.settings == Settings())
        #expect(decoded.personas.isEmpty)
        #expect(decoded.profile == Profile())
        var partial: [CBOR: CBOR] = [:]
        partial[.unsigned(5)] = .unsigned(30)
        root[.unsigned(3)] = .map(partial)
        var expected = Settings()
        expected.durationMinutes = 30
        #expect(try OwnerCodec.decode(CBOR.map(root).encoded).settings == expected)
    }

    @Test func profileCardRoundTrip() {
        let profile = fullProfile()
        let card = OwnerCodec.card(profile)
        #expect(card.personaID == [UInt8](repeating: 0, count: 8))
        #expect(card.issuedDay == 0)
        #expect(card.name == profile.name)
        #expect(card.website == profile.website)
        #expect(card.photo == profile.photo)
        #expect(card.gpgKey == profile.gpgKey)
        #expect(card.custom == profile.custom)
        #expect(OwnerCodec.profile(from: card) == profile)
    }
}
