/// HB1 map keys. Integer keys below 24 cost one CBOR byte; the registry is
/// frozen once cards exist in the wild, so keys are only ever added.
public enum FieldKey: UInt64, CaseIterable, Sendable {
    case flags = 0
    case name = 1
    case company = 2
    case phone = 3
    case email = 4
    case website = 5
    case github = 6
    case linkedin = 7
    case mastodon = 8
    case signal = 9
    case calendly = 10
    case ssh = 11
    case gpgFingerprint = 12
    case custom = 13
    case publicKey = 14
    case signature = 15
    case personaID = 16
    case issuedDay = 17
    case color = 18
    case keyFingerprint = 19
    case photo = 20
    case seq = 21
    case minReader = 22
    case gpgKey = 23

    /// Contact channels a persona may include. Everything else is structure.
    public static let channels: [FieldKey] = [
        .phone, .email, .website, .github, .linkedin, .mastodon, .signal, .calendly, .ssh, .gpgFingerprint,
    ]

    /// Keys that never travel in a QR code; they ride only in file and URL shares.
    public static let heavy: Set<FieldKey> = [.photo, .gpgKey]
}

/// Bit flags in key 0. Unknown bits are preserved on decode and ignored.
public struct CardFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// The Lock Screen tier: a subset of the persona, unsigned, fingerprint only.
    public static let compact = CardFlags(rawValue: 1 << 0)
    /// The persona has a headshot, available in file and URL shares.
    public static let photoAvailable = CardFlags(rawValue: 1 << 1)
    /// An alias persona: fields belong to the alias, not the canonical profile.
    public static let alias = CardFlags(rawValue: 1 << 2)
    /// The website is reachable only over http. Owned by `Website.insecure`;
    /// never present in `Card.flags`.
    public static let insecureWebsite = CardFlags(rawValue: 1 << 3)
}

public enum CustomKind: UInt8, CaseIterable, Sendable {
    case text = 0
    case url = 1
    case email = 2
    case phone = 3
    case key = 4
}

public struct CustomField: Sendable, Hashable {
    public var label: String
    public var value: String
    public var kind: CustomKind

    public init(label: String, value: String, kind: CustomKind = .text) {
        self.label = label
        self.value = value
        self.kind = kind
    }
}

/// An SSH public key as stored: a one-byte kind code and either the raw key
/// material (ed25519, ecdsa) or a 32-byte SHA-256 fingerprint (rsa).
public struct SSHKeyField: Sendable, Hashable {
    public var kind: UInt8
    public var bytes: [UInt8]

    public init(kind: UInt8, bytes: [UInt8]) {
        self.kind = kind
        self.bytes = bytes
    }
}

/// A Signal contact link. Username links are 48 opaque bytes from
/// `signal.me/#eu/`; phone links disclose the number and are stored as E.164.
public enum SignalField: Sendable, Hashable {
    case username([UInt8])
    case phone(String)
}

public struct Website: Sendable, Hashable {
    /// Host and path without a scheme, e.g. `nnix.com` or `example.org/~d`.
    public var address: String
    public var insecure: Bool

    public init(address: String, insecure: Bool = false) {
        self.address = address
        self.insecure = insecure
    }
}
