/// One rendered card: exactly what a QR, file or URL carries. Values are in
/// stored form (see Interop for normalization and canonical URIs).
public struct Card: Sendable, Hashable {
    public var flags: CardFlags = []
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
    public var custom: [CustomField] = []
    /// Ed25519 public key of the persona. Absent on the compact tier.
    public var publicKey: [UInt8]?
    public var signature: [UInt8]?
    /// Random, per persona, 8 bytes. Lets a recipient recognise a re-scan.
    public var personaID: [UInt8]
    /// Days since 2020-01-01.
    public var issuedDay: UInt32
    /// Index into `Palette.colors`.
    public var color: UInt8 = 0
    /// First 8 bytes of SHA-256 of the public key. Compact tier only.
    public var keyFingerprint: [UInt8]?
    public var photo: [UInt8]?
    /// Monotonic per persona; a recipient accepts an update only when higher.
    public var seq: UInt32 = 0
    public var minReader: UInt8?
    public var gpgKey: [UInt8]?

    public init(personaID: [UInt8], issuedDay: UInt32) {
        self.personaID = personaID
        self.issuedDay = issuedDay
    }

    public var isCompact: Bool { flags.contains(.compact) }
    public var isSigned: Bool { publicKey != nil && signature != nil }
}

public enum CardError: Error, Equatable, Sendable {
    case notAMap
    case wrongType(FieldKey)
    case wrongLength(FieldKey, expected: [Int], actual: Int)
    case badCustomField
    case outOfRange(FieldKey)
    case missing(FieldKey)
}

// MARK: - CBOR mapping

extension Card {
    /// The HB1 map. Absent fields are absent keys.
    public var cbor: CBOR {
        var map: [CBOR: CBOR] = [:]
        func put(_ key: FieldKey, _ value: CBOR?) {
            if let value { map[.unsigned(key.rawValue)] = value }
        }
        var flags = self.flags
        flags.remove(.insecureWebsite)
        if website?.insecure == true { flags.insert(.insecureWebsite) }
        put(.flags, flags.rawValue == 0 ? nil : .unsigned(flags.rawValue))
        put(.name, name.map(CBOR.text))
        put(.company, company.map(CBOR.text))
        put(.phone, phone.map(CBOR.text))
        put(.email, email.map(CBOR.text))
        put(.website, website.map { .text($0.address) })
        put(.github, github.map(CBOR.text))
        put(.linkedin, linkedin.map(CBOR.text))
        put(.mastodon, mastodon.map(CBOR.text))
        switch signal {
        case .username(let bytes)?: put(.signal, .bytes(bytes))
        case .phone(let number)?: put(.signal, .text(number))
        case nil: break
        }
        put(.calendly, calendly.map(CBOR.text))
        put(.ssh, ssh.map { .bytes([$0.kind] + $0.bytes) })
        put(.gpgFingerprint, gpgFingerprint.map(CBOR.bytes))
        put(.custom, custom.isEmpty ? nil : .array(custom.map {
            [.text($0.label), .text($0.value), .unsigned(UInt64($0.kind.rawValue))]
        }))
        put(.publicKey, publicKey.map(CBOR.bytes))
        put(.signature, signature.map(CBOR.bytes))
        put(.personaID, .bytes(personaID))
        put(.issuedDay, .unsigned(UInt64(issuedDay)))
        put(.color, color == 0 ? nil : .unsigned(UInt64(color)))
        put(.keyFingerprint, keyFingerprint.map(CBOR.bytes))
        put(.photo, photo.map(CBOR.bytes))
        put(.seq, seq == 0 ? nil : .unsigned(UInt64(seq)))
        put(.minReader, minReader.map { .unsigned(UInt64($0)) })
        put(.gpgKey, gpgKey.map(CBOR.bytes))
        return .map(map)
    }

    /// Reads a card from its map. Unknown keys are ignored so newer cards
    /// still open; known keys with the wrong shape are errors.
    public init(cbor: CBOR) throws {
        guard let map = cbor.mapValue else { throw CardError.notAMap }

        func text(_ key: FieldKey) throws -> String? {
            guard let v = map[.unsigned(key.rawValue)] else { return nil }
            guard let s = v.textValue else { throw CardError.wrongType(key) }
            return s
        }
        func bytes(_ key: FieldKey, length: [Int]? = nil) throws -> [UInt8]? {
            guard let v = map[.unsigned(key.rawValue)] else { return nil }
            guard let b = v.bytesValue else { throw CardError.wrongType(key) }
            if let length, !length.contains(b.count) {
                throw CardError.wrongLength(key, expected: length, actual: b.count)
            }
            return b
        }
        func unsigned(_ key: FieldKey, max: UInt64) throws -> UInt64? {
            guard let v = map[.unsigned(key.rawValue)] else { return nil }
            guard let u = v.unsignedValue else { throw CardError.wrongType(key) }
            guard u <= max else { throw CardError.outOfRange(key) }
            return u
        }

        guard let personaID = try bytes(.personaID, length: [8]) else { throw CardError.missing(.personaID) }
        guard let issuedDay = try unsigned(.issuedDay, max: UInt64(UInt32.max)) else { throw CardError.missing(.issuedDay) }
        self.init(personaID: personaID, issuedDay: UInt32(issuedDay))

        flags = CardFlags(rawValue: try unsigned(.flags, max: UInt64.max) ?? 0)
        let insecure = flags.contains(.insecureWebsite)
        flags.remove(.insecureWebsite)
        name = try text(.name)
        company = try text(.company)
        phone = try text(.phone)
        email = try text(.email)
        website = try text(.website).map { Website(address: $0, insecure: insecure) }
        github = try text(.github)
        linkedin = try text(.linkedin)
        mastodon = try text(.mastodon)
        if let v = map[.unsigned(FieldKey.signal.rawValue)] {
            if let b = v.bytesValue {
                guard b.count == 48 else { throw CardError.wrongLength(.signal, expected: [48], actual: b.count) }
                signal = .username(b)
            } else if let s = v.textValue {
                signal = .phone(s)
            } else {
                throw CardError.wrongType(.signal)
            }
        }
        calendly = try text(.calendly)
        if let b = try bytes(.ssh) {
            guard b.count >= 2 else { throw CardError.wrongLength(.ssh, expected: [2], actual: b.count) }
            ssh = SSHKeyField(kind: b[0], bytes: Array(b.dropFirst()))
        }
        gpgFingerprint = try bytes(.gpgFingerprint, length: [20, 32])
        if let v = map[.unsigned(FieldKey.custom.rawValue)] {
            guard let items = v.arrayValue else { throw CardError.wrongType(.custom) }
            custom = try items.map { item in
                guard let triple = item.arrayValue, triple.count == 3,
                      let label = triple[0].textValue, let value = triple[1].textValue,
                      let raw = triple[2].unsignedValue, raw <= UInt64(UInt8.max),
                      let kind = CustomKind(rawValue: UInt8(raw))
                else { throw CardError.badCustomField }
                return CustomField(label: label, value: value, kind: kind)
            }
        }
        publicKey = try bytes(.publicKey, length: [32])
        signature = try bytes(.signature, length: [64])
        color = UInt8(try unsigned(.color, max: UInt64(UInt8.max)) ?? 0)
        keyFingerprint = try bytes(.keyFingerprint, length: [8])
        photo = try bytes(.photo)
        seq = UInt32(try unsigned(.seq, max: UInt64(UInt32.max)) ?? 0)
        minReader = try unsigned(.minReader, max: UInt64(UInt8.max)).map(UInt8.init)
        gpgKey = try bytes(.gpgKey)
    }

    /// Canonical bytes a signature covers: the map without key 15.
    public var signingBytes: [UInt8] {
        var copy = self
        copy.signature = nil
        return copy.cbor.encoded
    }

    public func withSignature(_ signature: [UInt8], publicKey: [UInt8]) -> Card {
        var copy = self
        copy.publicKey = publicKey
        copy.signature = signature
        return copy
    }
}
