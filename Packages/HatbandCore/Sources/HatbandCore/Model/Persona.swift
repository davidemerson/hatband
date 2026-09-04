/// Everything the user has entered, in stored form. Personas select from it.
public struct Profile: Sendable, Hashable {
    public var name: String?
    public var company: String?
    public var phone: String?
    public var email: String?
    public var website: Website?
    public var github: String?
    public var linkedin: String?
    public var mastodon: String?
    public var signal: SignalField?
    public var calendly: String?
    public var ssh: SSHKeyField?
    public var gpgFingerprint: [UInt8]?
    public var gpgKey: [UInt8]?
    public var photo: [UInt8]?
    public var custom: [CustomField] = []

    public init() {}

    /// Which channels have a value.
    public var presentChannels: Set<FieldKey> {
        var keys = Set<FieldKey>()
        if phone != nil { keys.insert(.phone) }
        if email != nil { keys.insert(.email) }
        if website != nil { keys.insert(.website) }
        if github != nil { keys.insert(.github) }
        if linkedin != nil { keys.insert(.linkedin) }
        if mastodon != nil { keys.insert(.mastodon) }
        if signal != nil { keys.insert(.signal) }
        if calendly != nil { keys.insert(.calendly) }
        if ssh != nil { keys.insert(.ssh) }
        if gpgFingerprint != nil { keys.insert(.gpgFingerprint) }
        return keys
    }
}

/// A card identity: a subset of the profile (or, for an alias, its own
/// profile) with its own colour, id, key and Lock Screen choices.
public struct Persona: Sendable, Hashable {
    public static let maxLockScreenChannels = 2

    /// Random 8 bytes; goes in the payload.
    public var id: [UInt8]
    /// What the user calls it: Work, Personal, Henry Flower.
    public var label: String
    /// Index for the derived signing key.
    public var keyIndex: UInt32
    public var color: UInt8
    /// Channels this persona shares. Ignored for alias personas.
    public var channels: Set<FieldKey>
    /// Labels of profile custom fields this persona shares.
    public var customLabels: Set<String>
    public var includeCompany: Bool
    public var includePhoto: Bool
    public var displayName: String?
    /// Up to two channels for the compact Lock Screen tier. Name is always there.
    public var lockScreenChannels: [FieldKey]
    /// Present for an alias persona: the only source of its fields.
    public var aliasProfile: Profile?
    /// Bumped on every change the user makes; carried as key 21.
    public var seq: UInt32

    public init(id: [UInt8], label: String, keyIndex: UInt32, color: UInt8 = 0,
                channels: Set<FieldKey> = [], customLabels: Set<String> = [],
                includeCompany: Bool = true, includePhoto: Bool = true,
                displayName: String? = nil, lockScreenChannels: [FieldKey] = [],
                aliasProfile: Profile? = nil, seq: UInt32 = 1) {
        self.id = id
        self.label = label
        self.keyIndex = keyIndex
        self.color = color
        self.channels = channels
        self.customLabels = customLabels
        self.includeCompany = includeCompany
        self.includePhoto = includePhoto
        self.displayName = displayName
        self.lockScreenChannels = Array(lockScreenChannels.prefix(Persona.maxLockScreenChannels))
        self.aliasProfile = aliasProfile
        self.seq = seq
    }

    public var isAlias: Bool { aliasProfile != nil }
}

/// Where a card is going. Each form has its own stripping rules.
public enum CardForm: Sendable, CaseIterable {
    /// Compact tier drawn by the Live Activity. Unsigned; fingerprint only.
    case lockScreen
    /// The in-app full-screen QR: signed, no heavy fields.
    case fullQR
    /// `.hatband` file or URL share: signed, everything.
    case file
}

public enum CardBuilder {
    /// Builds the unsigned card for a form. The caller signs full and file
    /// forms with the persona key and sets `keyFingerprint` on compact ones.
    public static func card(profile: Profile, persona: Persona, form: CardForm, issuedDay: UInt32) -> Card {
        let source = persona.aliasProfile ?? profile
        var card = Card(personaID: persona.id, issuedDay: issuedDay)
        card.color = persona.color
        card.seq = persona.seq
        card.name = persona.displayName ?? source.name
        if persona.isAlias { card.flags.insert(.alias) }

        let channels: Set<FieldKey>
        switch form {
        case .lockScreen:
            card.flags.insert(.compact)
            channels = Set(persona.lockScreenChannels.prefix(Persona.maxLockScreenChannels))
        case .fullQR, .file:
            channels = persona.isAlias ? source.presentChannels : persona.channels
            if persona.includeCompany { card.company = source.company }
            card.custom = source.custom.filter { persona.isAlias || persona.customLabels.contains($0.label) }
            if persona.includePhoto, source.photo != nil {
                card.flags.insert(.photoAvailable)
                if form == .file { card.photo = source.photo }
            }
            if form == .file { card.gpgKey = source.gpgKey }
        }

        for key in channels {
            switch key {
            case .phone: card.phone = source.phone
            case .email: card.email = source.email
            case .website: card.website = source.website
            case .github: card.github = source.github
            case .linkedin: card.linkedin = source.linkedin
            case .mastodon: card.mastodon = source.mastodon
            case .signal: card.signal = source.signal
            case .calendly: card.calendly = source.calendly
            case .ssh: card.ssh = source.ssh
            case .gpgFingerprint: card.gpgFingerprint = source.gpgFingerprint
            default: break
            }
        }
        return card
    }
}
