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
            rows.append(Row(id: "gpg", label: "GPG", text: gpgText(fingerprint), url: nil, domain: nil, mono: true))
        }
        for (index, field) in card.custom.enumerated() {
            rows.append(customRow(field, index: index))
        }
        return rows
    }

    /// The vCard hatband.link builds for the same card (`cardVCard` in
    /// `site/src/hb1.js`), plus the met line. Name, organisation, mobile
    /// and email; each channel and url-kind custom field as a labelled link
    /// when `URLPolicy` accepts its URI and as `Label: text` in the note
    /// otherwise; text, email and phone custom fields and the SSH key as
    /// note lines; a JPEG photo; `X-HATBAND-PERSONA`, `-KEY`, `-ISSUED-DAY`
    /// and `-SEQ`. `met` leads the note and is the one thing the site lacks.
    static func vcard(for person: Person, met: String?) -> VCard {
        let card = person.card
        var vcard = VCard(formattedName: card.name ?? "")
        vcard.organization = card.company
        vcard.phone = card.phone
        vcard.email = card.email
        var links: [VCard.Link] = []
        var note: [String] = []
        if let met {
            note.append(met)
        }
        func link(_ label: String, _ url: String?, _ text: String) {
            if let url, URLPolicy.verdict(for: url).isAccepted {
                links.append(VCard.Link(label: label, url: url))
            } else {
                note.append(label + ": " + text)
            }
        }
        if let website = card.website {
            link("Website", CanonicalURI.website(website.address, insecure: website.insecure), website.address)
        }
        if let github = card.github {
            link("GitHub", CanonicalURI.github(github), github)
        }
        if let linkedin = card.linkedin {
            link("LinkedIn", CanonicalURI.linkedin(linkedin), linkedin)
        }
        if let mastodon = card.mastodon {
            link("Mastodon", CanonicalURI.mastodon(mastodon)?.profile, mastodon)
        }
        if let signal = card.signal {
            switch signal {
            case .username:
                link("Signal", CardFields.display(signal: signal), "username link")
            case .phone(let number):
                link("Signal", CardFields.display(signal: signal), number)
            }
        }
        if let calendly = card.calendly {
            link("Calendly", CanonicalURI.calendly(calendly), calendly)
        }
        if let fingerprint = card.gpgFingerprint {
            link("GPG", CanonicalURI.gpgFingerprint(fingerprint), gpgText(fingerprint))
        }
        for field in card.custom {
            if field.kind == .url {
                link(field.label, field.value, field.value)
            } else {
                note.append(field.label + ": " + field.value)
            }
        }
        if let ssh = card.ssh, let line = sshDisplay(ssh) {
            note.append(line)
        }
        vcard.links = links
        vcard.note = note.isEmpty ? nil : note.joined(separator: "\n")
        if let photo = person.currentPhoto, isJPEG(photo) {
            vcard.photoJPEG = photo
        }
        var extensions = [VCard.Extension(name: "PERSONA", value: Hex.string(card.personaID))]
        if let key = card.publicKey {
            extensions.append(VCard.Extension(name: "KEY", value: Base64.encode(key)))
        }
        extensions.append(VCard.Extension(name: "ISSUED-DAY", value: String(card.issuedDay)))
        if card.seq != 0 {
            extensions.append(VCard.Extension(name: "SEQ", value: String(card.seq)))
        }
        vcard.extensions = extensions
        return vcard
    }

    /// The vCard note: the day of the meeting and nothing else, so a card
    /// passed on never says where you met.
    static func metNote(for encounter: Encounter) -> String {
        "Met " + encounter.date.formatted(date: .abbreviated, time: .omitted)
    }

    /// What the site shows for key 11 (`sshDisplay`): the `authorized_keys`
    /// line for an inline key, `SHA256:` and the stored digest for RSA, nil
    /// for anything malformed.
    static func sshDisplay(_ field: SSHKeyField) -> String? {
        guard let kind = SSHPublicKey.Kind(rawValue: field.kind) else { return nil }
        if kind == .rsa {
            return field.bytes.count == 32 ? SSHPublicKey.fingerprintString(sha256: field.bytes) : nil
        }
        return authorizedKeysLine(field)
    }

    /// The site's `isJPEG`: the SOI marker, nothing else is a photo.
    static func isJPEG(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8
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

    /// GnuPG's grouped display form, or bare hex for an impossible length.
    private static func gpgText(_ fingerprint: [UInt8]) -> String {
        (try? GPGFingerprint(bytes: fingerprint))?.formatted ?? Hex.string(fingerprint).uppercased()
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
