import Foundation
import HatbandCore

/// What a card shows, one row per channel, and the vCard a person
/// becomes. A row offers a url only when `URLPolicy.isTappable`.
nonisolated enum Links {
    nonisolated struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        let text: String
        let url: String?
        let domain: String?
        let mono: Bool
    }

    static func rows(for card: Card) -> [Row] {
        var rows: [Row] = []
        if let phone = card.phone {
            rows.append(row("phone", "Phone", phone, url: CanonicalURI.phone(phone)))
        }
        if let email = card.email {
            rows.append(row("email", "Email", email, url: CanonicalURI.email(email)))
        }
        if let website = card.website {
            let url = CanonicalURI.website(website.address, insecure: website.insecure)
            rows.append(row("website", "Website", website.address, url: url))
        }
        if let github = card.github {
            rows.append(row("github", "GitHub", github, url: CanonicalURI.github(github)))
        }
        if let linkedin = card.linkedin {
            rows.append(row("linkedin", "LinkedIn", linkedin, url: CanonicalURI.linkedin(linkedin)))
        }
        if let mastodon = card.mastodon {
            rows.append(row("mastodon", "Mastodon", mastodon, url: CanonicalURI.mastodon(mastodon)?.profile))
        }
        if let signal = card.signal {
            rows.append(signalRow(signal))
        }
        if let calendly = card.calendly {
            rows.append(row("calendly", "Calendly", calendly, url: CanonicalURI.calendly(calendly)))
        }
        if let ssh = card.ssh {
            rows.append(Row(id: "ssh", label: "SSH", text: sshText(ssh), url: nil, domain: nil, mono: true))
        }
        if let fingerprint = card.gpgFingerprint {
            let text = (try? GPGFingerprint(bytes: fingerprint))?.formatted ?? Hex.string(fingerprint).uppercased()
            rows.append(Row(id: "gpg", label: "GPG", text: text, url: nil, domain: nil, mono: true))
        }
        for (index, field) in card.custom.enumerated() {
            rows.append(customRow(field, index: index))
        }
        return rows
    }

    /// Name, organisation, mobile, email, the web links, the GPG
    /// fingerprint, the photo and the persona id, key and issued day as
    /// `X-HATBAND` lines. The note is the met string and nothing else.
    static func vcard(for person: Person, met: String?) -> VCard {
        let card = person.card
        var vcard = VCard(formattedName: card.name ?? "")
        vcard.organization = card.company
        vcard.phone = card.phone
        vcard.email = card.email
        var links: [VCard.Link] = []
        for row in rows(for: card) {
            if let url = row.url, url.hasPrefix("http") {
                links.append(VCard.Link(label: row.label, url: url))
            }
        }
        if let fingerprint = card.gpgFingerprint {
            links.append(VCard.Link(label: "GPG", url: CanonicalURI.gpgFingerprint(fingerprint)))
        }
        vcard.links = links
        vcard.note = met
        vcard.photoJPEG = card.photo
        var extensions = [
            VCard.Extension(name: "PERSONA", value: Hex.string(card.personaID)),
            VCard.Extension(name: "ISSUED-DAY", value: String(card.issuedDay)),
        ]
        if let key = card.publicKey {
            extensions.append(VCard.Extension(name: "KEY", value: Base64.encode(key)))
        }
        if let ssh = card.ssh, let line = authorizedKeysLine(ssh) {
            extensions.append(VCard.Extension(name: "SSH", value: line))
        }
        vcard.extensions = extensions
        return vcard
    }

    /// What the editors and inspector call a channel.
    static func label(for key: FieldKey) -> String {
        switch key {
        case .phone: return "Phone"
        case .email: return "Email"
        case .website: return "Website"
        case .github: return "GitHub"
        case .linkedin: return "LinkedIn"
        case .mastodon: return "Mastodon"
        case .signal: return "Signal"
        case .calendly: return "Calendly"
        case .ssh: return "SSH key"
        case .gpgFingerprint: return "GPG fingerprint"
        default: return String(describing: key)
        }
    }

    /// The `authorized_keys` line for an inline key; nil for RSA, which a
    /// card carries only as a fingerprint.
    static func authorizedKeysLine(_ field: SSHKeyField) -> String? {
        guard let kind = SSHPublicKey.Kind(rawValue: field.kind), kind != .rsa,
              let key = try? SSHPublicKey(kind: kind, inlineBytes: field.bytes)
        else { return nil }
        return key.authorizedKeysLine()
    }

    /// The host of an http, https or mailto URL without a leading `www.`.
    static func domain(of url: String) -> String? {
        let rest: Substring
        if let range = url.range(of: "://") {
            rest = url[range.upperBound...]
        } else if url.hasPrefix("mailto:"), let at = url.lastIndex(of: "@") {
            rest = url[url.index(after: at)...]
        } else {
            return nil
        }
        var host = String(rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host.isEmpty ? nil : host
    }

    // MARK: - Rows

    /// A row whose url and domain survive only under `URLPolicy.isTappable`.
    private static func row(_ id: String, _ label: String, _ text: String, url candidate: String?, mono: Bool = false) -> Row {
        guard let candidate, URLPolicy.isTappable(candidate) else {
            return Row(id: id, label: label, text: text, url: nil, domain: nil, mono: mono)
        }
        return Row(id: id, label: label, text: text, url: candidate, domain: domain(of: candidate), mono: mono)
    }

    private static func signalRow(_ signal: SignalField) -> Row {
        switch signal {
        case .username(let bytes):
            let link = try? SignalLink(username: bytes)
            return row("signal", "Signal", "Username link", url: link?.url)
        case .phone(let number):
            let link = try? SignalLink(phone: number)
            return row("signal", "Signal", number, url: link?.url)
        }
    }

    /// The OpenSSH fingerprint: computed for an inline key, carried as
    /// stored for RSA.
    private static func sshText(_ field: SSHKeyField) -> String {
        guard let kind = SSHPublicKey.Kind(rawValue: field.kind) else { return "unknown key type" }
        if kind == .rsa {
            guard field.bytes.count == 32 else { return "malformed ssh-rsa fingerprint" }
            return SSHPublicKey.fingerprintString(sha256: field.bytes)
        }
        guard let key = try? SSHPublicKey(kind: kind, inlineBytes: field.bytes) else {
            return "malformed \(kind.typeName) key"
        }
        return key.fingerprintString
    }

    private static func customRow(_ field: CustomField, index: Int) -> Row {
        let id = "custom-\(index)"
        switch field.kind {
        case .text:
            return Row(id: id, label: field.label, text: field.value, url: nil, domain: nil, mono: false)
        case .url:
            return row(id, field.label, field.value, url: field.value)
        case .email:
            return row(id, field.label, field.value, url: CanonicalURI.email(field.value))
        case .phone:
            return row(id, field.label, field.value, url: CanonicalURI.phone(field.value))
        case .key:
            return Row(id: id, label: field.label, text: field.value, url: nil, domain: nil, mono: true)
        }
    }
}
