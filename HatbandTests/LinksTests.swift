import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct LinksTests {
    private func row(_ id: String, in rows: [Links.Row]) throws -> Links.Row {
        try #require(rows.first { $0.id == id }, "row \(id)")
    }

    @Test func maximalVectorRowsCarryDomains() throws {
        let rows = Links.rows(for: try Vectors.card("maximal-qr-signed"))
        let domains = Set(rows.compactMap { $0.domain })
        for expected in ["github.com", "linkedin.com", "merveilles.town", "calendly.com", "example.org"] {
            #expect(domains.contains(expected), "\(expected)")
        }
        #expect(try row("email", in: rows).domain == "example.ie")
        #expect(try row("phone", in: rows).domain == nil)
        #expect(try row("phone", in: rows).url == "tel:+353871234567")
        // The maximal vector's website is http: tappable with a warning, and the row says so through its url.
        #expect(try row("website", in: rows).url == "http://example.org/~bloom")
        #expect(try row("linkedin", in: rows).url == "https://www.linkedin.com/in/leopold-bloom")
        #expect(try row("signal", in: rows).domain == "signal.me")
        #expect(rows.contains { $0.label == "Pub" && $0.url == nil && $0.text == "Davy Byrne's" })
        #expect(rows.contains { $0.label == "Fax" && $0.url == "tel:+35318000000" })
        #expect(rows.contains { $0.label == "Matrix" && $0.domain == "matrix.to" })
        #expect(Set(rows.map { $0.id }).count == rows.count)
    }

    @Test func mastodonRowUsesProfileURL() throws {
        let rows = Links.rows(for: try Vectors.card("typical-signed"))
        let mastodon = try row("mastodon", in: rows)
        let uri = try #require(CanonicalURI.mastodon("bloom@merveilles.town"))
        #expect(mastodon.url == uri.profile)
        #expect(mastodon.url == "https://merveilles.town/@bloom")
        #expect(mastodon.text == "bloom@merveilles.town")
        #expect(mastodon.domain == "merveilles.town")
        #expect(!mastodon.mono)
        #expect(uri.account == "acct:bloom@merveilles.town")
        #expect(!URLPolicy.isTappable(uri.account))
    }

    @Test func rsaRowHasNoURL() {
        var card = Card(personaID: [1, 2, 3, 4, 5, 6, 7, 8], issuedDay: 1)
        let digest = [UInt8](repeating: 0xAB, count: 32)
        card.ssh = SSHKeyField(kind: SSHPublicKey.Kind.rsa.rawValue, bytes: digest)
        let rows = Links.rows(for: card)
        #expect(rows.count == 1)
        #expect(rows[0].id == "ssh")
        #expect(rows[0].url == nil)
        #expect(rows[0].domain == nil)
        #expect(rows[0].mono)
        #expect(rows[0].text == SSHPublicKey.fingerprintString(sha256: digest))
        #expect(rows[0].text.hasPrefix("SHA256:"))
        #expect(Links.authorizedKeysLine(card.ssh!) == nil)
    }

    @Test func ed25519RowShowsFingerprint() throws {
        let card = try Vectors.card("maximal-qr-signed")
        let field = try #require(card.ssh)
        let key = try SSHPublicKey(kind: .ed25519, inlineBytes: field.bytes)
        let ssh = try row("ssh", in: Links.rows(for: card))
        #expect(ssh.text == key.fingerprintString)
        #expect(ssh.mono)
        #expect(ssh.url == nil)
        #expect(Links.authorizedKeysLine(field) == key.authorizedKeysLine())
    }

    @Test func gpgRowIsMonoWithoutURL() throws {
        let card = try Vectors.card("maximal-qr-signed")
        let bytes = try #require(card.gpgFingerprint)
        let gpg = try row("gpg", in: Links.rows(for: card))
        let formatted = try GPGFingerprint(bytes: bytes).formatted
        #expect(gpg.text == formatted)
        #expect(formatted.count == 50)
        #expect(gpg.mono)
        #expect(gpg.url == nil)
        #expect(gpg.domain == nil)
    }

    @Test func customURLRowTappableOnlyByPolicy() {
        var card = Card(personaID: [1, 2, 3, 4, 5, 6, 7, 8], issuedDay: 1)
        card.custom = [
            CustomField(label: "Matrix", value: "https://matrix.to/#/@bloom:example.ie", kind: .url),
            CustomField(label: "Script", value: "javascript:alert(1)", kind: .url),
            CustomField(label: "Plain", value: "http://example.com/x", kind: .url),
            CustomField(label: "Key", value: "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p", kind: .key),
            CustomField(label: "Work", value: "bloom@example.ie", kind: .email),
            CustomField(label: "Desk", value: "+35318000001", kind: .phone),
            CustomField(label: "Pub", value: "Davy Byrne's", kind: .text),
        ]
        let rows = Links.rows(for: card)
        #expect(rows.map { $0.label } == ["Matrix", "Script", "Plain", "Key", "Work", "Desk", "Pub"])
        #expect(rows[0].url == "https://matrix.to/#/@bloom:example.ie")
        #expect(rows[0].domain == "matrix.to")
        #expect(rows[1].url == nil)
        #expect(rows[1].domain == nil)
        #expect(rows[1].text == "javascript:alert(1)")
        #expect(rows[2].url == "http://example.com/x")
        #expect(rows[3].url == nil)
        #expect(rows[3].mono)
        #expect(rows[4].url == "mailto:bloom@example.ie")
        #expect(rows[4].domain == "example.ie")
        #expect(rows[5].url == "tel:+35318000001")
        #expect(rows[6].url == nil)
        #expect(!rows[6].mono)
        #expect(Links.domain(of: "https://www.linkedin.com/in/x") == "linkedin.com")
        #expect(Links.domain(of: "tel:+1") == nil)
    }

    @Test func metNoteNamesTheDayNotThePlace() {
        let encounter = Encounter(id: UUID(), date: Date(timeIntervalSince1970: 1_781_568_000),
                                  fix: Fix(latitude: 53.34, longitude: -6.26, accuracy: 5000),
                                  label: "Davy Byrne's", note: "Gorgonzola")
        let note = Links.metNote(for: encounter)
        #expect(note.hasPrefix("Met "))
        #expect(!note.contains("Davy"))
        #expect(!note.contains("Gorgonzola"))
        #expect(!note.contains("53"))
    }

    @Test func vcardParsesBack() throws {
        let card = try Vectors.card("typical-signed")
        let person = Person(personaID: card.personaID, cardBytes: try Vectors.cbor("typical-signed"), card: card,
                            publicKey: card.publicKey, keyFingerprint: nil, trust: .inPerson, source: .scan,
                            tags: [], note: "private", gpgKey: nil, createdAt: Date(), updatedAt: Date(), encounters: [])
        let met = "Bloomsday 2026, Davy Byrne's"
        let vcard = Links.vcard(for: person, met: met)
        let parsed = try VCard.parseBasic(vcard.text)
        #expect(parsed.formattedName == "Leopold Bloom")
        #expect(parsed.familyName == "Bloom")
        #expect(parsed.organization == "Freeman's Journal")
        #expect(parsed.phone == "+353871234567")
        #expect(parsed.email == "henry.flower@example.ie")
        // Website, GitHub, LinkedIn, Mastodon and Calendly; phone and email are their own properties.
        #expect(parsed.links.count == 5)
        #expect(parsed.links.map { $0.label } == ["Website", "GitHub", "LinkedIn", "Mastodon", "Calendly"])
        #expect(parsed.links.contains { $0.url == "https://merveilles.town/@bloom" })
        #expect(parsed.note == met)
        #expect(parsed.note?.contains("private") == false)
        #expect(longestDigitRun(parsed.note ?? "") <= 4)
        #expect(parsed.extensions.contains { $0.name == "PERSONA" && $0.value == "0101010101010101" })
        #expect(parsed.extensions.contains { $0.name == "ISSUED-DAY" && $0.value == "2438" })
        #expect(parsed.extensions.contains { $0.name == "KEY" && $0.value == Base64.encode(card.publicKey ?? []) })
        #expect(Links.vcard(for: person, met: nil).note == nil)
    }

    /// The site's `cardVCard` output for every vector, generated into
    /// `SiteVCardFixtures` from `site/src/hb1.js`: without a met line the
    /// app must produce the same bytes for the same card.
    @Test(arguments: ["minimal", "compact-name-only", "compact-two-channels", "typical-signed", "maximal-qr-signed",
                      "file-with-photo-and-key", "alias-signed", "unicode-nfc", "unicode-nfd", "tampered-signature"])
    func vcardMatchesTheSiteForVector(name: String) throws {
        let card = try Vectors.card(name)
        let person = Person(personaID: card.personaID, cardBytes: try Vectors.cbor(name), card: card,
                            publicKey: card.publicKey, keyFingerprint: card.keyFingerprint, trust: .byFile, source: .file,
                            tags: ["private"], note: "private", gpgKey: card.gpgKey, createdAt: Date(), updatedAt: Date(),
                            encounters: [])
        let expected = try #require(SiteVCardFixtures.text[name])
        let text = Links.vcard(for: person, met: nil).text
        #expect(Array(text.utf8) == Array(expected.utf8), "\(name)")
        #expect(!text.contains("private"))
    }

    @Test func vcardMetLeadsTheNoteAndRejectedChannelsFollow() throws {
        var card = try Vectors.card("maximal-qr-signed")
        card.website = Website(address: "evil.example/\"><script>", insecure: false)
        card.custom.append(CustomField(label: "Work", value: "bloom@example.ie", kind: .email))
        card.custom.append(CustomField(label: "Script", value: "javascript:alert(1)", kind: .url))
        let person = Person(personaID: card.personaID, cardBytes: card.cbor.encoded, card: card, publicKey: card.publicKey,
                            keyFingerprint: nil, trust: .inPerson, source: .scan, tags: [], note: "", gpgKey: nil,
                            createdAt: Date(), updatedAt: Date(), encounters: [])
        let met = "Met 16 Jun 2026 at Davy Byrne's"
        let vcard = Links.vcard(for: person, met: met)
        let parsed = try VCard.parseBasic(vcard.text)
        let sshField = try #require(card.ssh)
        let ssh = try #require(Links.sshDisplay(sshField))
        #expect(parsed.note == [met, "Website: evil.example/\"><script>", "Pub: Davy Byrne's", "Fax: +35318000000",
                                "Work: bloom@example.ie", "Script: javascript:alert(1)", ssh].joined(separator: "\n"))
        #expect(parsed.links.map { $0.label } == ["GitHub", "LinkedIn", "Mastodon", "Signal", "Calendly", "GPG", "Matrix"])
        #expect(parsed.links.allSatisfy { URLPolicy.verdict(for: $0.url).isAccepted })
        #expect(!vcard.text.contains("URL:javascript"))
        #expect(!vcard.text.contains("URL:https://evil.example"))
        #expect(parsed.extensions.map { $0.name } == ["PERSONA", "KEY", "ISSUED-DAY", "SEQ"])
        #expect(parsed.extensions.last?.value == "7")
        #expect(Links.vcard(for: person, met: nil).note?.hasPrefix("Website: ") == true)

        var pictured = card
        pictured.photo = [0x89, 0x50, 0x4E, 0x47]
        var portrait = person
        portrait.card = pictured
        #expect(Links.vcard(for: portrait, met: nil).photoJPEG == nil)
        pictured.photo = [0xFF, 0xD8, 0xFF, 0xD9]
        portrait.card = pictured
        #expect(Links.vcard(for: portrait, met: nil).photoJPEG == [0xFF, 0xD8, 0xFF, 0xD9])
    }

    @Test func sshDisplayMatchesSite() throws {
        let card = try Vectors.card("maximal-qr-signed")
        let field = try #require(card.ssh)
        let key = try SSHPublicKey(kind: .ed25519, inlineBytes: field.bytes)
        #expect(Links.sshDisplay(field) == key.authorizedKeysLine())
        #expect(Links.sshDisplay(field)?.hasPrefix("ssh-ed25519 ") == true)
        let digest = [UInt8](repeating: 0xAB, count: 32)
        let rsa = SSHKeyField(kind: SSHPublicKey.Kind.rsa.rawValue, bytes: digest)
        #expect(Links.sshDisplay(rsa) == SSHPublicKey.fingerprintString(sha256: digest))
        #expect(Links.sshDisplay(rsa)?.hasPrefix("SHA256:") == true)
        #expect(Links.sshDisplay(SSHKeyField(kind: SSHPublicKey.Kind.rsa.rawValue, bytes: [1, 2, 3])) == nil)
        #expect(Links.sshDisplay(SSHKeyField(kind: 0x7f, bytes: digest)) == nil)
        #expect(Links.sshDisplay(SSHKeyField(kind: SSHPublicKey.Kind.ed25519.rawValue, bytes: [1, 2, 3])) == nil)
        #expect(Links.isJPEG([0xFF, 0xD8]))
        #expect(!Links.isJPEG([0xFF]))
        #expect(!Links.isJPEG([0x89, 0x50, 0x4E, 0x47]))
    }

    /// Every row's url is the canonical URI and passes `URLPolicy.isTappable`;
    /// a row without one has no domain either.
    @Test func rowsOfferOnlyTappableCanonicalURIsForEveryVector() throws {
        for vector in try Vectors.all() {
            let name = try #require(vector["name"] as? String)
            let card = try Vectors.card(name)
            let rows = Links.rows(for: card)
            for row in rows {
                if let url = row.url {
                    #expect(URLPolicy.isTappable(url), "\(name) \(row.id)")
                    #expect(row.domain != nil || url.hasPrefix("tel:"), "\(name) \(row.id)")
                } else {
                    #expect(row.domain == nil, "\(name) \(row.id)")
                }
            }
            if let phone = card.phone { #expect(rows.first { $0.id == "phone" }?.url == CanonicalURI.phone(phone)) }
            if let email = card.email { #expect(rows.first { $0.id == "email" }?.url == CanonicalURI.email(email)) }
            if let website = card.website {
                #expect(rows.first { $0.id == "website" }?.url == CanonicalURI.website(website.address, insecure: website.insecure))
            }
            if let github = card.github { #expect(rows.first { $0.id == "github" }?.url == CanonicalURI.github(github)) }
            if let linkedin = card.linkedin { #expect(rows.first { $0.id == "linkedin" }?.url == CanonicalURI.linkedin(linkedin)) }
            if let mastodon = card.mastodon { #expect(rows.first { $0.id == "mastodon" }?.url == CanonicalURI.mastodon(mastodon)?.profile) }
            if let calendly = card.calendly { #expect(rows.first { $0.id == "calendly" }?.url == CanonicalURI.calendly(calendly)) }
            if let signal = card.signal { #expect(rows.first { $0.id == "signal" }?.url == CardFields.display(signal: signal)) }
            #expect(rows.first { $0.id == "gpg" }?.url == nil)
            #expect(rows.first { $0.id == "ssh" }?.url == nil)
        }
    }

    private func longestDigitRun(_ text: String) -> Int {
        var longest = 0
        var run = 0
        for character in text {
            if character.isNumber {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }
}
