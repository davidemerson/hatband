import Testing
@testable import HatbandCore

// Third look at the interop module after the scalar rewrite: the closed gaps
// under more hostile input, then the grapheme seams the rewrite left behind.
// One cluster shape the audit missed: a letter with Grapheme_Cluster_Break=
// Prepend (U+0D4E, MALAYALAM LETTER DOT REPH) absorbs the scalar after it, so
// a space or a slash becomes the second scalar of a "letter" wherever a
// `Character` is asked `isLetter` or `isWhitespace` (both read the first
// scalar only).

private let ed1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7 ed1"
private let ed1Base64 = "AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7"
private let reph = "\u{0D4E}"

private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

// MARK: - Closed gaps, again

@Test func percentTriplesAreCheckedEverywhereOutsideTheHost() throws {
    for input in ["nnix.com/%2%41", "nnix.com/%41%", "nnix.com/a%", "nnix.com/%%", "nnix.com/%0", "nnix.com?%=1",
                  "nnix.com/#%%25", "nnix.com:8080/%", "https://nnix.com/%g0", "//nnix.com/%"] {
        #expect(throws: Normalize.Error.invalidCharacter("%")) { try Normalize.website(input) }
    }
    for input in ["nnix.com/%ff%FF%Ff%fF", "nnix.com/%25%25", "nnix.com/?%3D=%3D#%23", "nnix.com/%2525"] {
        #expect((try? Normalize.website(input))?.address == input)
    }
    // A `%` in the host or port is not a path escape: the host grammar refuses it first.
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("nn%69x.com") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("nnix.com:%38") }
    let (address, insecure) = try Normalize.website("http://nnix.com/%7Ebloom?%20#%00")
    #expect(insecure && address == "nnix.com/%7Ebloom?%20#%00")
    #expect(try Normalize.website(CanonicalURI.website(address, insecure: insecure)).address == address)
}

@Test func schemeRelativeFormsUnderStress() {
    #expect((try? Normalize.website("//nnix.com:65535/a:b?c:d#e:f"))?.address == "nnix.com:65535/a:b?c:d#e:f")
    #expect((try? Normalize.website(" //NNIX.com/ "))?.address == "nnix.com")
    #expect((try? Normalize.website("//nnix.com//x"))?.address == "nnix.com//x")
    #expect((try? Normalize.website("//nnix.com/mailto:x"))?.address == "nnix.com/mailto:x")
    #expect((try? Normalize.website("//nnix.com/https://y"))?.address == "nnix.com/https://y")
    for input in ["//", "///nnix.com", "//https://nnix.com", "//nnix.com:0", "//nnix.com:", "//:80", "//\u{301}nnix.com", "//nnix"] {
        #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(input) }
    }
    #expect(throws: Normalize.Error.userinfo) { try Normalize.website("//bloom@nnix.com") }
    #expect(throws: Normalize.Error.invalidCharacter(" ")) { try Normalize.website("// nnix.com") }
}

@Test func reservedGithubWordsInEverySpelling() throws {
    for input in ["orgs", "@ORGS", "\torgs\n", "@Orgs", "sEtTiNgS", "@@new"] {
        #expect(throws: Normalize.Error.invalidUsername, "\(input)") { try Normalize.github(input) }
    }
    for input in ["github.com/orgs", "https://github.com/ORGS/", "@github.com/settings?x", "http://www.github.com/login#y"] {
        #expect(throws: Normalize.Error.invalidPath, "\(input)") { try Normalize.github(input) }
    }
    #expect(throws: Normalize.Error.wrongHost("orgs")) { try Normalize.github("orgs/") }
    for ok in ["orgs1", "1orgs", "x-orgs", "orgsx", "log-in", "new1"] {
        #expect(try Normalize.github(ok) == ok)
    }
    for input in ["new-", "-new"] {
        #expect(throws: Normalize.Error.invalidUsername) { try Normalize.github(input) }
    }
}

@Test func hashPrincipalsAfterEverySeparator() throws {
    let key = try SSHPublicKey(line: ed1)
    for principal in ["\t,#,\u{0}#bloom@nnix.com", "\u{2028}#bloom@nnix.com", " , #bloom@nnix.com", "#\u{85}#bloom@nnix.com"] {
        let line = key.allowedSignersLine(principal: principal)
        #expect(line == "bloom@nnix.com namespaces=\"git\" ssh-ed25519 " + ed1Base64, "\(principal)")
    }
    for principal in ["#*", "\u{a0}#\u{3000}", "#,#,#"] {
        #expect(key.allowedSignersLine(principal: principal).hasPrefix("* "), "\(principal)")
    }
    // The key still reads back from every line.
    for principal in ["#bloom@nnix.com", "#", "##"] {
        let fields = key.allowedSignersLine(principal: principal).split(separator: " ")
        #expect(try SSHPublicKey(line: fields[2...].joined(separator: " ")).blob == key.blob)
    }
}

// MARK: - The Prepend seam

/// `Normalize.website` promises whitespace is refused anywhere, but the scan
/// walks `Character`s and asks `isWhitespace` of the first scalar only. After
/// U+0D4E a space is the second scalar of a letter and reaches the host, where
/// `Hostname.normalized` asks the same first-scalar `isLetter`. The same hides
/// `_`, `<` and `!`, which the host grammar refuses on their own.
@Test func websiteHostCannotHideBytesBehindAPrependLetter() {
    for hidden in [" ", "\u{A0}", "\u{3000}", "\u{2009}", "_", "<", "!", "%"] {
        let input = "nn\(reph)\(hidden)ix.com"
        #expect(throws: Normalize.Error.self, "\(scalars(input))") { try Normalize.website(input) }
        #expect(throws: Normalize.Error.self, "\(scalars(input))") { try Normalize.website("https://" + input + ":8080/x") }
    }
    // The scalar delimiters end the authority before the host check and are refused as such.
    for hidden in ["/", "?", "#", ":", "@"] {
        #expect(throws: Normalize.Error.self) { try Normalize.website("nn\(reph)\(hidden)ix.com") }
    }
}

/// `Hostname.normalized` says letters, digits and hyphens; `Character.isLetter`
/// says yes to a letter followed by anything that extends it: a ZWJ, a ZWNJ,
/// a tag letter, or a Prepend letter's whitespace. `Normalize.website` catches
/// the format characters with its own scan; `Normalize.mastodon` has no scan
/// and hands the instance straight to `Hostname.normalized`.
@Test func mastodonInstanceCannotHideScalarsBehindALetter() {
    for hidden in ["\u{200D}", "\u{200C}", "\u{E0041}", "\(reph) ", "\(reph)_", "\(reph)\u{A0}"] {
        let host = "nn\(hidden)ix.com"
        #expect(throws: Normalize.Error.self, "\(scalars(host))") { try Normalize.mastodon("bloom@" + host) }
        #expect(throws: Normalize.Error.self, "\(scalars(host))") { try Normalize.mastodon("https://\(host)/@bloom") }
        #expect(throws: Normalize.Error.self, "\(scalars(host))") { try Normalize.mastodon("\(host)/users/bloom") }
    }
}

/// The slug test `isLetter || isNumber || "-"` runs on `Character`s after
/// percent-decoding, so `%2F`, `%3F`, `%23` and `%20` decoded right after
/// U+0D4E are letters: the stored slug carries a path separator, a query or a
/// space, its canonical URI gains a segment, and the round trip
/// `Normalize.linkedin(CanonicalURI.linkedin(slug)) == slug` breaks.
@Test func linkedinSlugCannotHideDelimitersBehindAPrependLetter() {
    for escaped in ["%2F", "%3F", "%23", "%20", "%2E"] {
        for input in ["https://www.linkedin.com/in/bl%E0%B5%8E\(escaped)oom", "in/bl%E0%B5%8E\(escaped)oom", "company/bl%E0%B5%8E\(escaped)oom"] {
            #expect(throws: Normalize.Error.self, "\(input)") { try Normalize.linkedin(input) }
        }
    }
    // A raw space needs no escape at all: nothing in `linkedin` looks for whitespace.
    for input in ["in/bl\(reph) oom", "bl\(reph) oom", "bl\(reph)\u{3000}oom", "https://www.linkedin.com/in/bl\(reph)\u{A0}oom"] {
        #expect(throws: Normalize.Error.self, "\(scalars(input))") { try Normalize.linkedin(input) }
    }
    // Whatever is stored must survive its own canonical URI; a slug with a
    // slash inside loses its tail there.
    if let slug = try? Normalize.linkedin("in/bl%E0%B5%8E%2Foom") {
        #expect((try? Normalize.linkedin(CanonicalURI.linkedin(slug))) == slug, "\(scalars(slug))")
    }
}

/// A default-ignorable mark — VS16, the combining grapheme joiner, VS1 — is
/// not a format character, but IDNA 2008 disallows every
/// Default_Ignorable_Code_Point in a label: the website scan names it and
/// `Hostname.normalized` refuses it. (Gap closed.)
@Test func knownGapIgnorableMarksStayInsideHosts() {
    for mark in ["\u{FE0F}", "\u{034F}", "\u{FE00}", "\u{E0100}"] {
        #expect(throws: Normalize.Error.self) { try Normalize.website("nnix\(mark).com") }
        #expect(throws: Normalize.Error.self) { try Normalize.mastodon("bloom@nnix\(mark).com") }
    }
}

/// The 63-octet label and 253-octet host limits count UTF-8 octets, so a
/// letter with two hundred marks is four hundred and one. (Gap closed.)
@Test func knownGapHostLimitsCountGraphemesNotOctets() {
    let label = "a" + String(repeating: "\u{301}", count: 200)
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(label + ".com") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.mastodon("bloom@" + label + ".com") }
    // Sixty-four plain letters are still refused, so only the marks stretch it.
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(String(repeating: "a", count: 64) + ".com") }
}

/// What the interop layer says about scripts: nothing. Every letter is a host
/// letter, whole-script and mixed-script alike, lowercased by full case
/// mapping, and the look-alike verdict is `Confusables.domainVerdict`'s. Digit
/// and hyphen placement is the one rule applied here.
@Test func idnHostsPassThroughForValidateToJudge() throws {
    let idns: [(String, String)] = [
        ("москва.рф", "москва.рф"), ("МОСКВА.РФ", "москва.рф"), ("ελλάδα.ελ", "ελλάδα.ελ"), ("ΕΛΛΆΔΑ.ΕΛ", "ελλάδα.ελ"),
        ("հայաստան.հայ", "հայաստան.հայ"), ("pаypal.com", "pаypal.com"), ("wikipediа.org", "wikipediа.org"),
        ("bücher.de", "bücher.de"), ("xn--bcher-kva.de", "xn--bcher-kva.de"), ("\u{212A}elvin.com", "kelvin.com"),
        ("e\u{301}amonn.ie", "e\u{301}amonn.ie"), ("日本.jp", "日本.jp"),
    ]
    for (input, stored) in idns {
        #expect(try Normalize.website(input).address == stored, "\(input)")
        #expect(try Normalize.mastodon("bloom@" + input) == "bloom@" + stored, "\(input)")
    }
    // Email hosts stay ASCII, named by the first offending character.
    #expect(throws: Normalize.Error.invalidCharacter("м")) { try Normalize.email("bloom@москва.рф") }
    #expect(throws: Normalize.Error.invalidCharacter("а")) { try Normalize.email("bloom@pаypal.com") }
    for ok in ["1.com", "1-2.com", "a--b.com", "xn--80adxhks.xn--p1ai", "123.456.com", "a.b.c.d.e.ie", "0a.com", "a.0b"] {
        #expect(try Normalize.website(ok).address == ok, "\(ok)")
    }
    for bad in ["1.2", "a.1", "-a.com", "a-.com", "a.-b.com", "xn--.com", "a_b.com", "a..com", "a.com..", "a", ".com", "a.com.1"] {
        #expect(throws: Normalize.Error.invalidHost, "\(bad)") { try Normalize.website(bad) }
    }
}

// MARK: - mailto decoding

private let mailtoForms: [(String, String?)] = [
    ("mailto:a%2Bb@x.ie", "a+b@x.ie"), ("mailto:a%2bb@x.ie", "a+b@x.ie"), ("MAILTO:A%2bB@X.IE", "A+B@x.ie"),
    // `+` is not a space in a mailto URI, and a bare `%` in the local part is
    // an escape once the scheme is present.
    ("mailto:a+b@x.ie", "a+b@x.ie"), ("a+b@x.ie", "a+b@x.ie"), ("mailto:a%25b@x.ie", "a%b@x.ie"),
    // Decoded once: `%2540` is the two characters `%40`, a legal local part.
    ("mailto:a%2540b@x.ie", "a%40b@x.ie"), ("a%40b@x.ie", "a%40b@x.ie"), ("mailto:%2525@x.ie", "%25@x.ie"),
    // A decoded `@`, `?` or `.` is the character itself.
    ("mailto:bloom%40nnix.com", "bloom@nnix.com"), ("mailto:a%3F@x.ie?subject=x", "a?@x.ie"), ("mailto:bloom@nnix%2Ecom", "bloom@nnix.com"),
    ("mailto:%62loom@%6Enix.com", "bloom@nnix.com"), ("mailto:bloom@nnix.com?", "bloom@nnix.com"),
    ("mailto:bloom@nnix.com?to=x@y.ie&cc=%00", "bloom@nnix.com"), ("mailto:bloom@nnix.com?%", "bloom@nnix.com"),
    // Without the scheme nothing is decoded.
    ("a%2Bb@x.ie", "a%2Bb@x.ie"), ("a%ZZ@x.ie", "a%ZZ@x.ie"),
    // Refused: a second `@`, controls, non-ASCII, non-UTF-8, half an escape, a decoded scheme.
    ("mailto:a%40b@x.ie", nil), ("mailto:a%00@x.ie", nil), ("mailto:a%0D%0A@x.ie", nil), ("mailto:a%C3%A9@x.ie", nil),
    ("mailto:a%FF@x.ie", nil), ("mailto:a%ZZ@x.ie", nil), ("mailto:a%4@x.ie", nil), ("mailto:a%@x.ie", nil),
    ("mailto:%6Dailto:a@x.ie", nil), ("mailto:%20a@x.ie", nil), ("mailto:a@x.ie%3Fsubject=x", nil), ("mailto:?to=a@x.ie", nil),
    ("mailto:a@x.ie#x", nil), ("mailto:a%2540b@x%2Eie", "a%40b@x.ie"),
]

@Test(arguments: mailtoForms)
func mailtoDecodesOnceAndOnlyWithTheScheme(input: String, stored: String?) throws {
    if let stored {
        #expect(try Normalize.email(input) == stored)
        // The canonical URI re-encodes what decoding produced and normalises back.
        #expect(try Normalize.email(CanonicalURI.email(stored)) == stored)
    } else {
        #expect(throws: Normalize.Error.self) { try Normalize.email(input) }
    }
}

@Test func mailtoErrorsNameTheDecodedCharacter() {
    #expect(throws: Normalize.Error.multipleAt) { try Normalize.email("mailto:a%40b@x.ie") }
    #expect(throws: Normalize.Error.invalidCharacter("\u{0}")) { try Normalize.email("mailto:a%00@x.ie") }
    #expect(throws: Normalize.Error.invalidCharacter("é")) { try Normalize.email("mailto:a%C3%A9@x.ie") }
    #expect(throws: Normalize.Error.invalidCharacter("%")) { try Normalize.email("mailto:a%FF@x.ie") }
    #expect(throws: Normalize.Error.invalidCharacter("%")) { try Normalize.email("mailto:a%4@x.ie") }
    #expect(throws: Normalize.Error.invalidCharacter(" ")) { try Normalize.email("mailto:%20a@x.ie") }
    #expect(throws: Normalize.Error.invalidLocalPart) { try Normalize.email("mailto:%6Dailto:a@x.ie") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.email("mailto:a@x.ie%3Fsubject=x") }
    #expect(throws: Normalize.Error.empty) { try Normalize.email("mailto:?to=a@x.ie") }
    // Decoded text is not trimmed again: a decoded space is named, not dropped.
    #expect(throws: Normalize.Error.invalidCharacter(" ")) { try Normalize.email("mailto:%20") }
}

// MARK: - Escaping across astral scalars

private let sequences = [
    "🏳\u{FE0F}\u{200D}🌈", "🇮🇪", "👨\u{200D}👩\u{200D}👧", "👍\u{1F3FB}", "#\u{FE0F}\u{20E3}", "\u{1F600}", "e\u{301}",
    "\u{037E}", "\u{212A}", "\u{FEFF}", "\u{E0041}", "\u{10FFFD}",
]

/// RFC 2426 escapes octets. Astral scalars, ZWJ sequences, flags and
/// selectors sit against the reserved bytes without absorbing them, and the
/// round trip is exact at scalar level, not merely canonically equal.
@Test func escapingIsExactAroundAstralScalarsAndSequences() throws {
    let reserved: [(String, String, String)] = [(";", "\\;", ";"), (",", "\\,", ","), ("\\", "\\\\", "\\"), ("\n", "\\n", "\n"), ("\r\n", "\\n", "\n")]
    for s in sequences {
        for (raw, escaped, back) in reserved {
            let value = s + raw + s
            #expect(VCard.escape(value).utf8.elementsEqual((s + escaped + s).utf8), "\(scalars(value))")
            #expect(scalars(VCard.unescape(VCard.escape(value))) == scalars(s + back + s), "\(scalars(value))")
        }
        #expect(VCard.splitComponents(s + ";" + s).map(scalars) == [scalars(s), scalars(s)])
        #expect(VCard.splitComponents(s + "\\;" + s).map(scalars) == [scalars(s + ";" + s)])
        var card = VCard(formattedName: s, familyName: s + ";" + s, givenName: s + "," + s)
        card.note = s + "\r\n" + s + "\\" + s
        card.organization = s + ";x"
        let parsed = try VCard.parseBasic(card.text)
        #expect(scalars(parsed.familyName) == scalars(s + ";" + s), "\(scalars(s))")
        #expect(scalars(parsed.givenName) == scalars(s + "," + s), "\(scalars(s))")
        #expect(scalars(parsed.note ?? "") == scalars(s + "\n" + s + "\\" + s), "\(scalars(s))")
        // ORG is structured, but `text` escapes the `;` so the unit stays whole.
        #expect(scalars(parsed.organization ?? "") == scalars(s + ";x"), "\(scalars(s))")
    }
}

/// A fold may land between the two regional indicators of a flag or inside a
/// ZWJ sequence; the unfold on scalars puts them back byte for byte.
@Test func foldsInsideFlagsAndSequencesUnfoldExactly() throws {
    for s in ["🇮🇪", "🏳\u{FE0F}\u{200D}🌈", "👨\u{200D}👩\u{200D}👧", "e\u{301}\u{302}"] {
        for pad in 60...72 {
            var card = VCard(formattedName: "x")
            card.note = String(repeating: "a", count: pad) + s + s
            let lines = card.text.split(separator: "\r\n", omittingEmptySubsequences: false)
            #expect(lines.allSatisfy { $0.utf8.count <= VCard.foldWidth })
            #expect(scalars(try VCard.parseBasic(card.text).note ?? "") == scalars(card.note!), "\(scalars(s)) at \(pad)")
        }
    }
}

/// CR LF is one line break; CR alone, LF alone, and LF CR are what they are.
@Test func lineBreaksCountAsTheyAre() {
    #expect(VCard.escape("a\r\nb") == "a\\nb")
    #expect(VCard.escape("a\n\rb") == "a\\n\\nb")
    #expect(VCard.escape("a\r\r\nb") == "a\\n\\nb")
    #expect(VCard.escape("a\r\n\nb") == "a\\n\\nb")
    #expect(VCard.escape("a\r\u{0}\nb") == "a\\n\\nb")
    #expect(VCard.escape("\r\n\r\n") == "\\n\\n")
    #expect(VCard.escape("\r\n\u{85}\u{2028}\u{2029}") == "\\n\\n\\n\\n")
}

// MARK: - SSH

/// `sshkey_advance_past_options` treats `\"` as a literal quote, so a namespace
/// whose last scalar is a backslash would escape the closing quote of
/// `namespaces="…"` and the entry would never parse. The sanitiser drops
/// every backslash and quote, so the field always closes. (Gap closed.)
@Test func knownGapNamespaceEndingInABackslashEscapesItsQuote() throws {
    let key = try SSHPublicKey(line: ed1)
    for namespace in ["git\\", "\\", "a\\\"", "git\\\\"] {
        let line = key.allowedSignersLine(principal: "bloom@nnix.com", namespace: namespace)
        #expect(optionsFieldTerminates(line), "\(line)")
    }
    for namespace in ["git", "git\\x", "\\\"git", "a\\\\b"] {
        #expect(optionsFieldTerminates(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: namespace)), "\(namespace)")
    }
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: "git\\") == "bloom@nnix.com namespaces=\"git\" ssh-ed25519 " + ed1Base64)
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: "\\") == "bloom@nnix.com namespaces=\"\" ssh-ed25519 " + ed1Base64)
}

/// sshsig's option scan after the principals field: to whitespace, except
/// inside double quotes, where `\"` is a literal. True when the quote closes
/// and the key type follows.
private func optionsFieldTerminates(_ line: String) -> Bool {
    let bytes = Array(line.utf8)
    guard let space = bytes.firstIndex(of: UInt8(ascii: " ")) else { return false }
    var index = space + 1
    var quoted = false
    while index < bytes.count, quoted || (bytes[index] != UInt8(ascii: " ") && bytes[index] != UInt8(ascii: "\t")) {
        if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "\"") {
            index += 1
        } else if bytes[index] == UInt8(ascii: "\"") {
            quoted.toggle()
        }
        index += 1
    }
    guard !(index == bytes.count && quoted) else { return false }
    return bytes[index...].dropFirst().starts(with: "ssh-ed25519 ".utf8)
}

/// Fields split on space and tab, as sshd splits. A Unicode space between
/// the type and the key is part of the type name, which sshd would not
/// recognise either; one in the comment is comment.
@Test func unicodeSpacesBetweenFieldsAreNotSeparators() throws {
    let key = try SSHPublicKey(line: ed1)
    for space in ["\u{A0}", "\u{3000}", "\u{2003}"] {
        #expect(throws: SSHPublicKey.Error.malformedLine) { try SSHPublicKey(line: "ssh-ed25519\(space)\(ed1Base64)\(space)bloom") }
        #expect(throws: SSHPublicKey.Error.unsupportedType("ssh-ed25519\(space)")) { try SSHPublicKey(line: "ssh-ed25519\(space) \(ed1Base64)") }
        let parsed = try SSHPublicKey(line: "ssh-ed25519 \(ed1Base64) blo\(space)om")
        #expect(parsed.blob == key.blob && parsed.comment == "blo\(space)om")
        #expect(try SSHPublicKey(line: parsed.authorizedKeysLine()) == parsed)
    }
}
