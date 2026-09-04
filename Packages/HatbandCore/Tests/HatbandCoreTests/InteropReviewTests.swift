import Testing
@testable import HatbandCore

// Second look at the interop hardening: more hostile input for each closed
// gap, and the octet-versus-grapheme seams the fixes stop short of.

private struct Xorshift {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

private let ed1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7 ed1"
private let ed1Base64 = "AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7"

// MARK: - Website

/// Cf scalars beyond the ones the fix names: bidi controls, joiners,
/// invisible operators, interlinear annotation, tags, musical beams.
private let formatScalars: [Unicode.Scalar] = [
    "\u{061C}", "\u{180E}", "\u{200C}", "\u{200E}", "\u{202A}", "\u{2060}", "\u{2064}", "\u{2069}", "\u{206A}",
    "\u{FFF9}", "\u{FFFB}", "\u{E0001}", "\u{E007F}", "\u{1D173}",
]

@Test(arguments: formatScalars)
func reviewWebsiteRejectsEveryFormatScalarAnywhere(scalar: Unicode.Scalar) {
    #expect(scalar.properties.generalCategory == .format)
    let cf = String(scalar)
    for input in [cf + "nnix.com", "nn" + cf + "ix.com", "nnix.com" + cf, "nnix.com/" + cf, "nnix.com/a" + cf + "b",
                  "nnix.com?q=" + cf, "nnix.com/#" + cf, "https://nnix.com:8080/" + cf, cf] {
        do {
            _ = try Normalize.website(input)
            Issue.record("accepted \(input.unicodeScalars.map { String($0.value, radix: 16) })")
        } catch Normalize.Error.invalidCharacter(let ch) {
            // A joiner fuses with the letter before it; the scalar is still named.
            #expect(ch.unicodeScalars.contains(scalar))
        } catch {
            Issue.record("\(error) for \(input.unicodeScalars.map { String($0.value, radix: 16) })")
        }
    }
}

/// Every printable ASCII byte in a path, query and fragment: the nine RFC 3986
/// delimiters the fix names are refused, everything else is kept as typed.
@Test func reviewWebsiteSweepsPrintableASCIIOutsideTheHost() {
    let refused = Set("<>\"\\^`{|}")
    for byte in UInt8(0x20)...UInt8(0x7f) {
        let ch = Character(Unicode.Scalar(byte))
        for (prefix, suffix) in [("nnix.com/x", "y"), ("nnix.com?q=", ""), ("nnix.com/#", "z"), ("nnix.com/", "")] {
            let input = prefix + String(ch) + suffix
            // A trailing space or DEL is trimmed, not refused.
            if suffix.isEmpty, byte == 0x20 || byte == 0x7f { continue }
            if byte == 0x20 || byte == 0x7f || refused.contains(ch) {
                #expect(throws: Normalize.Error.invalidCharacter(ch)) { try Normalize.website(input) }
            } else {
                #expect((try? Normalize.website(input))?.address == input, "\(input)")
            }
        }
    }
}

private let portForms: [(String, String?)] = [
    ("example.com:1", "example.com:1"), ("EXAMPLE.COM:8080/X?y#z", "example.com:8080/X?y#z"),
    ("example.com:65535", "example.com:65535"), ("nnix.com.:443/", "nnix.com:443"), ("müller.de:8080/x", "müller.de:8080/x"),
    ("https://example.com:80", "example.com:80"),
    ("example.com:65536", nil), ("example.com:100000", nil), ("example.com:01", nil), ("example.com:-1", nil),
    ("example.com:\u{668}\u{660}", nil), ("example.com:\u{FF18}\u{FF10}", nil), ("example.com:8080:", nil),
    ("example.com:0x50", nil), ("example.com:1e3", nil), ("example.com::80", nil), ("example.com:80.", nil),
    ("localhost:8080/x", nil), ("localhost:8080?x", nil), ("localhost:8080#x", nil), ("intranet:80/", nil),
    ("http:80/x", nil), ("a:1", nil), ("svc:65535/api/v1", nil),
]

@Test(arguments: portForms)
func reviewWebsitePorts(input: String, address: String?) {
    if let address {
        #expect((try? Normalize.website(input))?.address == address)
    } else {
        #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(input) }
    }
}

/// `Pasted` honours a leading `//` only when the text has no colon at all,
/// so the scheme-relative form accepted as `//nnix.com` is refused with
/// `invalidHost` as soon as a port or a colon in the path follows.
@Test func reviewSchemeRelativeAddressesMayCarryAColon() {
    #expect((try? Normalize.website("//example.com"))?.address == "example.com")
    #expect((try? Normalize.website("//example.com:9/"))?.address == "example.com:9")
    #expect((try? Normalize.website("//nnix.com/a:b"))?.address == "nnix.com/a:b")
}

/// RFC 3986 §2.1: `%` is only legal as `%` HEXDIG HEXDIG. Half an escape is
/// kept as typed and reaches the canonical URI, where Foundation's URL
/// parser refuses it.
@Test func reviewWebsiteKeepsMalformedPercentEscapes() {
    withKnownIssue("a % that does not start a pct-encoded triple is accepted") {
        for input in ["example.com/%", "example.com/%ZZ", "example.com/%2", "example.com?q=100%"] {
            #expect(throws: Normalize.Error.invalidCharacter("%")) { try Normalize.website(input) }
        }
    }
}

// MARK: - GitHub

private let githubReservedWords = [
    "orgs", "settings", "login", "join", "marketplace", "explore", "topics", "features", "about", "pricing",
    "apps", "sponsors", "notifications", "new", "site", "security", "enterprise", "team", "collections",
    "events", "trending", "search", "issues", "pulls", "codespaces", "dashboard", "account", "sessions",
]

@Test(arguments: githubReservedWords)
func reviewGithubRejectsEveryReservedSegment(word: String) throws {
    let mixed = word.prefix(1).uppercased() + word.dropFirst()
    for input in ["https://github.com/\(word)", "github.com/\(word)/", "https://www.github.com/\(word.uppercased())/x?y#z",
                  "GitHub.com/\(mixed)", "http://github.com//\(word)", "@github.com/\(word)"] {
        #expect(throws: Normalize.Error.invalidPath) { try Normalize.github(input) }
    }
    // As a second segment it is a repository, and a profile name may contain it.
    #expect(try Normalize.github("github.com/bloom/\(word)") == "bloom")
    #expect(try Normalize.github("https://github.com/\(word)-x") == "\(word)-x")
}

/// The reserved list says what is not a profile; the same word typed alone
/// is stored, and its canonical URI is the site path it names.
@Test func reviewGithubBareReservedWordsAreStillAccepted() {
    withKnownIssue("a reserved word typed alone is stored although it can never be a profile") {
        for word in githubReservedWords {
            #expect(throws: Normalize.Error.invalidUsername) { try Normalize.github(word) }
            #expect(throws: Normalize.Error.invalidUsername) { try Normalize.github("@" + word.uppercased()) }
        }
    }
}

// MARK: - LinkedIn and Mastodon

@Test func reviewLinkedInMobilePaths() throws {
    #expect(try Normalize.linkedin("https://ie.linkedin.com/mwlite/in/leopold-bloom/") == "leopold-bloom")
    #expect(try Normalize.linkedin("MWLITE/IN/Leopold-Bloom") == "Leopold-Bloom")
    #expect(try Normalize.linkedin("mwlite/company/freemans-journal") == "company/freemans-journal")
    #expect(try Normalize.linkedin("https://www.linkedin.com/mwlite/in/%C3%A9amonn?trk=x") == "éamonn")
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.linkedin("https://www.linkedin.com/mwlite/mwlite/in/x-y-z") }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.linkedin("mwlite/pub/x-y-z") }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.linkedin("mwlite//") }
    #expect(throws: Normalize.Error.invalidUsername) { try Normalize.linkedin("mwlite/in/-x-") }
}

@Test func reviewMastodonSlashesAndPrefixes() throws {
    for input in ["https://merveilles.town/users/bloom/?x=1", "merveilles.town/@bloom/#y", "HTTPS://Merveilles.Town/@bloom//",
                  "https://merveilles.town/users/bloom//?x"] {
        #expect(try Normalize.mastodon(input) == "bloom@merveilles.town", "\(input)")
    }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.mastodon("https://merveilles.town/@bloom/x/") }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.mastodon("https://merveilles.town/users/bloom/followers/") }
    let prefixed = try #require(CanonicalURI.mastodon("@bloom@merveilles.town"))
    #expect(prefixed.account == "acct:bloom@merveilles.town" && prefixed.profile == "https://merveilles.town/@bloom")
    #expect(try Normalize.mastodon(prefixed.profile) == "bloom@merveilles.town")
    #expect(CanonicalURI.mastodon("@bloom@") == nil)
}

// MARK: - GPG

/// Every scalar in the BMP that `hexDigitValue` reads and is not ASCII: the
/// fullwidth digits and letters, and nothing else, all refused.
@Test func reviewGPGFingerprintRefusesEveryNonASCIIHexDigit() {
    let torV4Hex = "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"
    var wide: [Character] = []
    for value in UInt32(0x80)...UInt32(0xFFFF) {
        guard let scalar = Unicode.Scalar(value), Character(scalar).hexDigitValue != nil else { continue }
        wide.append(Character(scalar))
    }
    #expect(wide.count == 22)
    for ch in wide {
        #expect(throws: Normalize.Error.invalidCharacter(ch)) { try Normalize.gpgFingerprint(String(torV4Hex.dropLast()) + String(ch)) }
        #expect(throws: Normalize.Error.invalidCharacter(ch)) { try Normalize.gpgFingerprint("0x" + String(ch) + torV4Hex.dropFirst()) }
    }
}

// MARK: - SSH

private let optionLines: [String] = [
    "no-pty\t" + ed1,
    "no-pty   " + ed1,
    "environment=\"PATH=/bin /usr/bin\",no-agent-forwarding " + ed1,
    "from=\"*.nnix.com,!evil.nnix.com\" " + ed1,
    // A key type inside the quotes is not the type field.
    "command=\"ssh-ed25519 AAAA\" " + ed1,
    "command=\"echo \\\"a\\\" \\\"b\\\"\",restrict " + ed1,
    "restrict,command=\"\" " + ed1,
    "no-pty ecdsa-sha2-nistp256 AAAA",
    "no-pty ssh-rsa AAAA extra words",
    "no-pty ssh-ed25519",
]

@Test(arguments: optionLines)
func reviewSSHRecognisesOptionsBeforeAnyKeyType(line: String) {
    #expect(throws: SSHPublicKey.Error.optionsNotSupported) { try SSHPublicKey(line: line) }
}

private let notOptionLines: [(String, SSHPublicKey.Error)] = [
    // No whitespace after the closing quote: sshd would skip to `AAAA` and find no type.
    ("command=\"x\"ssh-ed25519 AAAA", .unsupportedType("command=\"x\"ssh-ed25519")),
    ("\"ssh-ed25519\" AAAA", .unsupportedType("\"ssh-ed25519\"")),
    ("ssh-ed25519\" AAAA", .unsupportedType("ssh-ed25519\"")),
    ("command=\"a\\\" " + ed1, .unsupportedType("command=\"a\\\"")),
    ("no-pty", .malformedLine),
]

@Test(arguments: notOptionLines)
func reviewSSHDoesNotInventOptions(line: String, error: SSHPublicKey.Error) {
    #expect(throws: error) { try SSHPublicKey(line: line) }
}

@Test func reviewEmittedLinesReparseUnderFuzz() throws {
    let key = try SSHPublicKey(line: ed1)
    var rng = Xorshift(state: 0x55)
    let pieces = ["a", " ", "\t", "\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}", "\u{0b}", "\u{0c}", "\u{0}", "\u{7f}", "\u{1b}",
                  "\u{a0}", "\u{200B}", ",", "\"", "#", "*", "ssh-rsa", "AAAA", "水", "🎩", "e\u{301}", "namespaces=\"x\"", "cert-authority"]
    for _ in 0..<800 {
        let s = (0..<rng.below(8)).map { _ in pieces[rng.below(pieces.count)] }.joined()
        let back = try SSHPublicKey(line: key.authorizedKeysLine(comment: s))
        #expect(back.blob == key.blob && back.kind == .ed25519)
        let signers = key.allowedSignersLine(principal: s, namespace: s)
        let fields = signers.split(whereSeparator: \.isWhitespace)
        #expect(fields.count == 4, "\(signers)")
        #expect(fields[2] == "ssh-ed25519" && fields[3] == ed1Base64)
        #expect(fields[1].hasPrefix("namespaces=\"") && fields[1].hasSuffix("\""))
        #expect(!fields[1].dropFirst("namespaces=\"".count).dropLast().contains("\""))
        #expect(!signers.contains { $0.isNewline || $0.isControl })
        #expect(try SSHPublicKey(line: fields[2...].joined(separator: " ")).blob == key.blob)
    }
}

/// sshsig skips a line whose first character is `#` (sshsig.c,
/// parse_principals_key_and_options), so a principal that begins with one
/// turns the entry into a comment. `#` is legal in a dot-atom local part.
@Test func reviewAllowedSignersPrincipalCannotBeginWithHash() throws {
    let key = try SSHPublicKey(line: ed1)
    #expect(try Normalize.email("#bloom@nnix.com") == "#bloom@nnix.com")
    withKnownIssue("a leading # makes the allowed_signers entry a comment") {
        for principal in ["#bloom@nnix.com", "\u{0}#bloom@nnix.com", " #", "#"] {
            #expect(!key.allowedSignersLine(principal: principal).hasPrefix("#"))
        }
    }
}

// MARK: - vCard

private func minimalCard(_ line: String) throws -> VCard {
    try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\n" + line + "\r\nNOTE:after\r\nEND:VCARD\r\n")
}

@Test func reviewVCardPhotoReferencesAndJunkAreSkipped() throws {
    for photo in ["PHOTO;VALUE=URI;TYPE=JPEG:data:image/jpeg;base64,/9j/4AAQ", "PHOTO;TYPE=JPEG;VALUE=\"URI\":https://nnix.com/a.jpg",
                  "PHOTO;X=\"VALUE=uri\":https://nnix.com/a.jpg", "PHOTO:https://nnix.com/a.jpg", "PHOTO;VALUE=uri:",
                  "PHOTO;ENCODING=b;TYPE=JPEG:/9j/4AAQ=====", "PHOTO;ENCODING=b:A", "PHOTO;ENCODING=b:\u{0}",
                  "PHOTO;ENCODING=b;TYPE=JPEG:-_-_", "PHOTO;ENCODING=b;TYPE=JPEG:AAAA\r\n AA==\r\n x"] {
        let parsed = try minimalCard(photo)
        #expect(parsed.photoJPEG == nil, "\(photo)")
        #expect(parsed.note == "after" && parsed.formattedName == "x")
    }
    #expect(try minimalCard("photo;encoding=b;type=jpeg:AAAA\r\n AAAA").photoJPEG == [0, 0, 0, 0, 0, 0])
    #expect(try minimalCard("PHOTO;ENCODING=b;TYPE=\"JPEG:x\":AAAA").photoJPEG == [0, 0, 0])
    #expect(try minimalCard("PHOTO;ENCODING=b:AAA").photoJPEG == [0, 0])
}

@Test func reviewVCardSplitsProperties() throws {
    #expect(VCard.splitProperty("N;X=\"a;b:c\";Y=\"\":d")?.head == "N;X=\"a;b:c\";Y=\"\"")
    #expect(VCard.splitProperty("N;X=\"a;b:c\";Y=\"\":d")?.value == "d")
    #expect(VCard.splitProperty("FN:\"quoted\":x")?.value == "\"quoted\":x")
    #expect(VCard.splitProperty("FN;X=\"\":\"")?.value == "\"")
    #expect(VCard.splitProperty(":")?.head == "")
    #expect(VCard.splitProperty("\"") == nil)
    #expect(VCard.splitProperty("\"a\":b\"")?.value == "b\"")
    #expect(try minimalCard("TEL;X=\"a:b\";TYPE=\"c;d\":+1").phone == "+1")
    #expect(throws: VCard.Error.malformedLine("TEL;X=\"a:b")) { try minimalCard("TEL;X=\"a:b") }
}

/// The exact set: HTAB kept, CR, LF and NEL mapped, every other C0 and DEL
/// dropped, printable ASCII and C1 untouched.
@Test func reviewVCardEscapeDropsExactlyC0AndDEL() {
    for value in UInt32(0)...UInt32(0x9f) {
        let scalar = Unicode.Scalar(value)!
        let out = VCard.escape("a" + String(scalar) + "b")
        switch value {
        case 0x09: #expect(out == "a\tb")
        case 0x0a, 0x0d, 0x85: #expect(out == "a\\nb")
        case 0x00...0x1f, 0x7f: #expect(out == "ab", "\(value)")
        case 0x2c: #expect(out == "a\\,b")
        case 0x3b: #expect(out == "a\\;b")
        case 0x5c: #expect(out == "a\\\\b")
        default: #expect(out == "a" + String(scalar) + "b", "\(value)")
        }
    }
    #expect(VCard.escape("\u{0}\\\u{1b},\u{7f};\u{0b}\u{0c}") == "\\\\\\,\\;")
    var card = VCard(formattedName: "\u{1}\u{2}")
    card.note = "\u{7f}"
    #expect(card.text == "BEGIN:VCARD\r\nVERSION:3.0\r\nN:;;;;\r\nFN:\r\nNOTE:\r\nEND:VCARD\r\n")
}

/// RFC 2426 escapes octets, but `escape`, `unescape` and `splitComponents`
/// compare grapheme clusters, so a reserved character followed by a
/// combining mark is neither escaped on the way out nor recognised on the
/// way back. Contacts splits the N below at the raw semicolon; our own `\n`
/// is read back as the letter n.
@Test func reviewVCardEscapingIsGraphemeBlind() throws {
    #expect(VCard.escape(";\u{301}") == "\\;\u{301}")
    #expect(VCard.escape(",\u{301}") == "\\,\u{301}")
    #expect(VCard.escape("\\\u{301}") == "\\\\\u{301}")
    var card = VCard(formattedName: "x", familyName: "Bloom;\u{301}Virag", givenName: "Leopold")
    #expect(card.text.contains("N:Bloom\\;\u{301}Virag;Leopold;;;"))
    #expect(VCard.unescape("\\n\u{301}") == "\n\u{301}")
    #expect(VCard.splitComponents("a;\u{301}b") == ["a", "\u{301}b"])
    card.note = "a\n\u{301}b"
    #expect(try VCard.parseBasic(card.text).note == "a\n\u{301}b")
}

/// A value that begins with a combining mark fuses with the colon before it,
/// so `splitProperty` finds no colon and our own output does not parse.
@Test func reviewVCardValueMayStartWithACombiningMark() throws {
    #expect(VCard.splitProperty("FN:\u{301}x")?.value == "\u{301}x")
    #expect(try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:\u{301}x\r\nEND:VCARD\r\n").formattedName == "\u{301}x")
    let card = VCard(formattedName: "\u{301}x")
    #expect(try VCard.parseBasic(card.text) == card)
}
