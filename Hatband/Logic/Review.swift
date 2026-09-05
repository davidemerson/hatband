import Foundation
import HatbandCore

/// Where a card came from. Wire values 0 to 3.
nonisolated enum CardSource: UInt8, Sendable {
    case scan, photo, file, link

    /// Scan and photo were read off a screen or paper in the same room.
    var isInPerson: Bool {
        self == .scan || self == .photo
    }

    /// What a QR can carry for scan and photo; the 32 KB form otherwise.
    var limits: Limits {
        isInPerson ? .qr : .file
    }
}

/// One present field of a card, as the review lists it and the diff
/// compares it.
nonisolated struct CardField: Equatable, Sendable {
    let id: String
    let label: String
    let value: String
}

/// Field ids and display forms. Custom fields are `custom:<label>`.
nonisolated enum CardFields {
    static let name = "name"
    static let company = "company"
    static let phone = "phone"
    static let email = "email"
    static let website = "website"
    static let github = "github"
    static let linkedin = "linkedin"
    static let mastodon = "mastodon"
    static let signal = "signal"
    static let calendly = "calendly"
    static let ssh = "ssh"
    static let gpgFingerprint = "gpgFingerprint"
    static let photo = "photo"
    static let gpgKey = "gpgKey"
    static let customPrefix = "custom:"

    static func customID(_ label: String) -> String {
        customPrefix + label
    }

    static func customLabel(_ id: String) -> String? {
        guard id.hasPrefix(customPrefix) else { return nil }
        return String(id.dropFirst(customPrefix.count))
    }

    /// Photo and GPG key: never in a QR, never listed in a diff.
    static func isHeavy(_ id: String) -> Bool {
        id == photo || id == gpgKey
    }

    /// Every present field in registry order.
    static func present(in card: Card) -> [CardField] {
        var fields: [CardField] = []
        if let value = card.name { fields.append(CardField(id: name, label: "Name", value: value)) }
        if let value = card.company { fields.append(CardField(id: company, label: "Company", value: value)) }
        if let value = card.phone { fields.append(CardField(id: phone, label: "Phone", value: value)) }
        if let value = card.email { fields.append(CardField(id: email, label: "Email", value: value)) }
        if let value = card.website {
            fields.append(CardField(id: website, label: "Website",
                                    value: CanonicalURI.website(value.address, insecure: value.insecure)))
        }
        if let value = card.github { fields.append(CardField(id: github, label: "GitHub", value: value)) }
        if let value = card.linkedin { fields.append(CardField(id: linkedin, label: "LinkedIn", value: value)) }
        if let value = card.mastodon { fields.append(CardField(id: mastodon, label: "Mastodon", value: value)) }
        if let value = card.signal { fields.append(CardField(id: signal, label: "Signal", value: display(signal: value))) }
        if let value = card.calendly { fields.append(CardField(id: calendly, label: "Calendly", value: value)) }
        if let value = card.ssh { fields.append(CardField(id: ssh, label: "SSH key", value: display(ssh: value))) }
        if let value = card.gpgFingerprint {
            fields.append(CardField(id: gpgFingerprint, label: "GPG fingerprint", value: display(gpgFingerprint: value)))
        }
        for field in card.custom {
            fields.append(CardField(id: customID(field.label), label: field.label, value: field.value))
        }
        if let value = card.photo { fields.append(CardField(id: photo, label: "Photo", value: "\(value.count) bytes")) }
        if let value = card.gpgKey { fields.append(CardField(id: gpgKey, label: "GPG key", value: "\(value.count) bytes")) }
        return fields
    }

    /// `card` reduced to the fields in `ids`. Structure, colour, key,
    /// signature and flags are kept, so nothing removed leaves a trace
    /// beyond the fields themselves.
    static func card(_ card: Card, keeping ids: Set<String>) -> Card {
        var out = Card(personaID: card.personaID, issuedDay: card.issuedDay)
        out.flags = card.flags
        out.publicKey = card.publicKey
        out.signature = card.signature
        out.color = card.color
        out.keyFingerprint = card.keyFingerprint
        out.seq = card.seq
        out.minReader = card.minReader
        if ids.contains(name) { out.name = card.name }
        if ids.contains(company) { out.company = card.company }
        if ids.contains(phone) { out.phone = card.phone }
        if ids.contains(email) { out.email = card.email }
        if ids.contains(website) { out.website = card.website }
        if ids.contains(github) { out.github = card.github }
        if ids.contains(linkedin) { out.linkedin = card.linkedin }
        if ids.contains(mastodon) { out.mastodon = card.mastodon }
        if ids.contains(signal) { out.signal = card.signal }
        if ids.contains(calendly) { out.calendly = card.calendly }
        if ids.contains(ssh) { out.ssh = card.ssh }
        if ids.contains(gpgFingerprint) { out.gpgFingerprint = card.gpgFingerprint }
        out.custom = card.custom.filter { ids.contains(customID($0.label)) }
        if ids.contains(photo) { out.photo = card.photo }
        if ids.contains(gpgKey) { out.gpgKey = card.gpgKey }
        return out
    }

    static func display(signal: SignalField) -> String {
        switch signal {
        case .username(let bytes):
            return "https://signal.me/#eu/" + Base64.encode(bytes, url: true)
        case .phone(let number):
            return "https://signal.me/#p/" + number
        }
    }

    /// The authorized_keys line, or for RSA the type and fingerprint.
    static func display(ssh: SSHKeyField) -> String {
        guard let kind = SSHPublicKey.Kind(rawValue: ssh.kind) else { return Hex.string(ssh.bytes) }
        if kind == .rsa {
            return kind.typeName + " " + SSHPublicKey.fingerprintString(sha256: ssh.bytes)
        }
        guard let key = try? SSHPublicKey(kind: kind, inlineBytes: ssh.bytes) else { return Hex.string(ssh.bytes) }
        return key.authorizedKeysLine()
    }

    static func display(gpgFingerprint: [UInt8]) -> String {
        guard let fingerprint = try? GPGFingerprint(bytes: gpgFingerprint) else { return Hex.string(gpgFingerprint) }
        return fingerprint.formatted
    }
}

/// What the review sheet shows before anything is saved: every field that
/// passed screening, with its warning, and what was left out and why.
nonisolated struct Review: Identifiable, Equatable, Sendable {
    nonisolated struct Item: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let value: String
        let verdict: Verdict
        var included: Bool
    }

    nonisolated enum Signature: Equatable, Sendable {
        case valid, invalid, unsigned, compact
    }

    let id: UUID
    /// The card as received.
    let card: Card
    let source: CardSource
    var items: [Item]
    /// "Label: reason" for every field screening removed.
    let dropped: [String]
    let signature: Signature
    let existing: Person?
    let outcome: Merge.Outcome
    /// The received certificate hashes to the card's fingerprint.
    let gpgKeyVerified: Bool

    /// The card with excluded and dropped fields removed.
    var acceptedCard: Card {
        CardFields.card(card, keeping: Set(items.filter { $0.included }.map { $0.id }))
    }

    /// Screens every present field under `Limits.qr` for scan and photo,
    /// `Limits.file` otherwise. Rejections become `dropped`; warnings stay
    /// on their item. The GPG key survives only when it hashes to key 12.
    static func make(card: Card, source: CardSource, people: [Person]) -> Review {
        let limits = source.limits
        let customCount = FieldValidator.customCount(card.custom.count, limits: limits)
        var items: [Item] = []
        var dropped: [String] = []
        var gpgKeyVerified = false
        for field in CardFields.present(in: card) {
            var verdict = Review.verdict(for: field, in: card, limits: limits)
            if CardFields.customLabel(field.id) != nil {
                verdict = customCount.merged(with: verdict)
            }
            switch verdict {
            case .reject(let reason):
                dropped.append(field.label + ": " + reason)
            case .ok, .warning:
                items.append(Item(id: field.id, label: field.label, value: field.value, verdict: verdict, included: true))
                if field.id == CardFields.gpgKey {
                    gpgKeyVerified = true
                }
            }
        }
        let signature: Signature
        if card.isCompact {
            signature = .compact
        } else if card.publicKey == nil, card.signature == nil {
            signature = .unsigned
        } else {
            signature = card.signatureIsValid ? .valid : .invalid
        }
        let existing = people.first { $0.personaID == card.personaID }
        return Review(id: UUID(), card: card, source: source, items: items, dropped: dropped, signature: signature,
                      existing: existing, outcome: Merge.outcome(existing: existing, incoming: card),
                      gpgKeyVerified: gpgKeyVerified)
    }

    private static func verdict(for field: CardField, in card: Card, limits: Limits) -> Verdict {
        switch field.id {
        case CardFields.name:
            return FieldValidator.name(card.name ?? "", limits: limits)
        case CardFields.company:
            return FieldValidator.company(card.company ?? "", limits: limits)
        case CardFields.phone:
            return FieldValidator.phone(card.phone ?? "", limits: limits)
        case CardFields.email:
            return FieldValidator.email(card.email ?? "", limits: limits)
        case CardFields.website:
            guard let website = card.website else { return .reject("empty") }
            let verdict = FieldValidator.website(website.address, limits: limits)
            return website.insecure ? verdict.merged(with: .warning("not encrypted")) : verdict
        case CardFields.github:
            return FieldValidator.handle(card.github ?? "", limits: limits)
        case CardFields.linkedin:
            return FieldValidator.handle(card.linkedin ?? "", limits: limits)
        case CardFields.mastodon:
            return FieldValidator.handle(card.mastodon ?? "", limits: limits)
        case CardFields.calendly:
            return FieldValidator.handle(card.calendly ?? "", limits: limits)
        case CardFields.signal:
            return signalVerdict(card.signal, limits: limits)
        case CardFields.ssh:
            return sshVerdict(card.ssh)
        case CardFields.gpgFingerprint:
            return card.gpgFingerprint == nil ? .reject("empty") : .ok
        case CardFields.photo:
            return FieldValidator.photo(byteCount: card.photo?.count ?? 0, limits: limits)
        case CardFields.gpgKey:
            return gpgKeyVerdict(card, limits: limits)
        default:
            guard let label = CardFields.customLabel(field.id),
                  let custom = card.custom.first(where: { $0.label == label })
            else { return .reject("unknown field") }
            return FieldValidator.customLabel(custom.label, limits: limits)
                .merged(with: FieldValidator.customValue(custom.value, kind: custom.kind, limits: limits))
        }
    }

    /// The stored link must parse as a signal.me link and pass the URL policy.
    private static func signalVerdict(_ signal: SignalField?, limits: Limits) -> Verdict {
        guard let signal else { return .reject("empty") }
        let link: SignalLink
        do {
            switch signal {
            case .username(let bytes):
                link = try SignalLink(username: bytes)
            case .phone(let number):
                link = try SignalLink(phone: number)
            }
        } catch {
            return .reject("not a signal.me link")
        }
        return FieldValidator.signalURL(link.url, limits: limits)
    }

    /// Inline keys must rebuild into a well-formed OpenSSH key; an RSA entry
    /// must be a 32-byte fingerprint.
    private static func sshVerdict(_ ssh: SSHKeyField?) -> Verdict {
        guard let ssh, let kind = SSHPublicKey.Kind(rawValue: ssh.kind) else { return .reject("unknown key type") }
        if kind == .rsa {
            return ssh.bytes.count == 32 ? .ok : .reject("not a SHA-256 fingerprint")
        }
        guard (try? SSHPublicKey(kind: kind, inlineBytes: ssh.bytes)) != nil else { return .reject("invalid key") }
        return .ok
    }

    /// Size under the form's cap, then the certificate must hash to key 12.
    private static func gpgKeyVerdict(_ card: Card, limits: Limits) -> Verdict {
        guard let key = card.gpgKey else { return .reject("empty") }
        let size = FieldValidator.gpgKey(byteCount: key.count, limits: limits)
        guard size.isAccepted else { return size }
        guard let fingerprint = card.gpgFingerprint else { return .reject("no fingerprint on the card") }
        guard OpenPGP.fingerprint(ofCertificate: key) == fingerprint else { return .reject("does not match the fingerprint") }
        return size
    }
}
