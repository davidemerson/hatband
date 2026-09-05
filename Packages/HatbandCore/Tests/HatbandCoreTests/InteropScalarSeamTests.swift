import Testing
@testable import HatbandCore

// Every `Character`-based operation the interop module used to run on user
// text, now run on scalars, under the two cluster shapes that fool
// `Character`: a combining mark (U+0301) that fuses with the scalar before
// it, and a Prepend letter (U+0D4E, MALAYALAM LETTER DOT REPH) that fuses
// with the scalar after it.

private let ed1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7 ed1"
private let ed1Base64 = "AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7"
private let reph = "\u{0D4E}"
private let mark = "\u{301}"

private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

// MARK: - Hostname

/// A label is judged scalar by scalar: the Prepend letter is a letter, and
/// whatever it absorbs is judged on its own.
@Test func hostnameLabelsAreCheckedScalarByScalar() throws {
    #expect(Hostname.normalized("nn\(reph)ix.com") == "nn\(reph)ix.com")
    for hidden in [" ", "\u{A0}", "\u{3000}", "\u{2009}", "_", "<", "!", "%", "\u{200B}", "\u{200D}", "\u{FE0F}", "\u{034F}",
                   "\u{E0041}", "\u{2024}", "\u{3002}", "\u{FF0E}", "\u{FF61}", "\u{2010}", "\u{00B2}", "\u{2167}", "\u{115F}"] {
        #expect(Hostname.normalized(Substring("nn\(reph)\(hidden)ix.com")) == nil, "\(scalars(hidden))")
        #expect(Hostname.normalized(Substring("nn\(hidden)ix.com")) == nil, "\(scalars(hidden))")
    }
    // A mark inside a label is a label scalar; one that starts a label is not.
    #expect(Hostname.normalized("e\(mark)amonn.ie") == "e\(mark)amonn.ie")
    #expect(Hostname.normalized("\(mark)eamonn.ie") == nil)
    #expect(Hostname.normalized("eamonn.\(mark)ie") == nil)
    #expect(Hostname.normalized("nnix.-\(mark)com") == nil)
    // The trailing dot is a scalar: one followed by a mark is not trailing.
    #expect(Hostname.normalized("nnix.com.") == "nnix.com")
    #expect(Hostname.normalized("nnix.com.\(mark)") == nil)
    // The last label may not be all digits, in any script.
    #expect(Hostname.normalized("nnix.123") == nil)
    #expect(Hostname.normalized("nnix.\u{661}\u{662}") == nil)
}

/// Label and host limits are UTF-8 octets, as RFC 1035 and IDNA count them.
@Test func hostnameLimitsCountOctets() throws {
    let marks = String(repeating: mark, count: 31)
    #expect(Hostname.normalized(Substring("a" + marks + ".com")) == "a" + marks + ".com")
    #expect(Hostname.normalized(Substring("ab" + marks + ".com")) == nil)
    let wide = String(repeating: "水", count: 21)
    let host = [wide, wide, wide, String(repeating: "水", count: 20) + "a"].joined(separator: ".")
    #expect(host.utf8.count == 253)
    #expect(Hostname.normalized(Substring(host)) == host)
    #expect(Hostname.normalized(Substring(host + "b")) == nil)
    #expect(Hostname.normalized(Substring(String(repeating: "a", count: 63) + ".com")) != nil)
    #expect(Hostname.normalized(Substring(String(repeating: "a", count: 64) + ".com")) == nil)
}

/// Lowercasing is per scalar: ASCII always, another script only when its
/// lowercase is one scalar. A mark on a capital does not shield it.
@Test func hostnameLowercasesScalarsNotGraphemes() throws {
    #expect(Hostname.normalized("NNIX.COM") == "nnix.com")
    #expect(Hostname.normalized("\u{212A}elvin.com") == "kelvin.com")
    #expect(Hostname.normalized("MO\(mark)SKVA.COM") == "mo\(mark)skva.com")
    #expect(Hostname.normalized("\u{130}stanbul.com") == "\u{130}stanbul.com")
    #expect(Hostname.normalized("ΕΛΛΆΔΑ.ΕΛ") == "ελλάδα.ελ")
}

// MARK: - Normalizers

@Test func websiteChecksPortAndPathOnScalars() throws {
    for input in ["nnix.com:8\(mark)0", "nnix.com:\(reph)80", "nnix.com:80\(mark)", "nnix.com.\(mark)"] {
        #expect(throws: Normalize.Error.invalidHost, "\(scalars(input))") { try Normalize.website(input) }
    }
    // Errors name the grapheme holding the offending scalar.
    #expect(throws: Normalize.Error.invalidCharacter(Character("<\(mark)"))) { try Normalize.website("nnix.com/<\(mark)x") }
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph)x"))) { try Normalize.website("nnix.com/\(reph)x") }
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph) "))) { try Normalize.website("nn\(reph) ix.com") }
    #expect(throws: Normalize.Error.invalidCharacter("x\u{200D}")) { try Normalize.website("nnix.com/x\u{200D}y") }
    #expect(throws: Normalize.Error.invalidCharacter("x\u{FE0F}")) { try Normalize.website("nnix\u{FE0F}.com") }
    #expect(try Normalize.website("NN\(reph)IX.com/x").address == "nn\(reph)ix.com/x")
}

@Test func emailScansScalars() throws {
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph) "))) { try Normalize.email("bl\(reph) oom@nnix.com") }
    #expect(throws: Normalize.Error.invalidCharacter(Character("o\(mark)"))) { try Normalize.email("blo\(mark)om@nnix.com") }
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph)i"))) { try Normalize.email("bloom@nn\(reph)ix.com") }
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph) "))) { try Normalize.email("mailto:bl%E0%B5%8E%20oom@nnix.com") }
    #expect(throws: Normalize.Error.invalidCharacter("m\u{FE0F}")) { try Normalize.email("bloom\u{FE0F}@nnix.com") }
    #expect(throws: Normalize.Error.invalidLocalPart) { try Normalize.email("bl..oom@nnix.com") }
    #expect(try Normalize.email("Bloom \(reph) <bloom@nnix.com>") == "bloom@nnix.com")
}

@Test func githubChecksUsernamesOnScalars() throws {
    for input in ["bl\(reph)oom", "bl\(reph) oom", "blo\(mark)om", "github.com/bl\(reph)oom", "https://github.com/blo\(mark)om",
                  "orgs\(mark)", "github.com/orgs\(mark)", "bl-\(mark)-oom"] {
        #expect(throws: Normalize.Error.invalidUsername, "\(scalars(input))") { try Normalize.github(input) }
    }
    // Hosts are compared scalar by scalar: a mark after `github.com` is another host.
    #expect(throws: Normalize.Error.wrongHost("github.com\(mark)")) { try Normalize.github("https://github.com\(mark)/bloom") }
    #expect(throws: Normalize.Error.tooLong) { try Normalize.github("a" + String(repeating: mark, count: 39)) }
    #expect(try Normalize.github("GITHUB.COM/Bloom") == "Bloom")
}

@Test func linkedinChecksPrefixesAndSlugsOnScalars() throws {
    // A prefix with a mark is not the prefix: the URL parser runs and refuses the host or path.
    #expect(throws: Normalize.Error.wrongHost("in\(mark)")) { try Normalize.linkedin("in\(mark)/bloom") }
    #expect(throws: Normalize.Error.wrongHost("mwlite\(mark)")) { try Normalize.linkedin("mwlite\(mark)/in/bloom") }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.linkedin("https://www.linkedin.com/in\(mark)/bloom") }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.linkedin("https://www.linkedin.com/mwlite\(mark)/in/bloom") }
    #expect(throws: Normalize.Error.wrongHost("linkedin.com\(mark)")) { try Normalize.linkedin("https://linkedin.com\(mark)/in/bloom") }
    // Slugs: a Prepend letter is a letter, a mark inside is fine, a mark first is not.
    #expect(try Normalize.linkedin("bl\(reph)oom") == "bl\(reph)oom")
    #expect(try Normalize.linkedin("e\(mark)amonn") == "e\(mark)amonn")
    #expect(try Normalize.linkedin("in/e\(mark)amonn") == "e\(mark)amonn")
    for input in ["\(mark)eamonn", "in/\(mark)eamonn", "company/\(mark)x", "bl\(reph)-oom-", "bl\(reph)_oom", "bl\(reph)\u{FE0F}oom"] {
        #expect(throws: Normalize.Error.invalidUsername, "\(scalars(input))") { try Normalize.linkedin(input) }
    }
    // At least three letters, digits or hyphens; at most 100 scalars in all.
    #expect(throws: Normalize.Error.invalidUsername) { try Normalize.linkedin("e\(mark)e\(mark)") }
    #expect(throws: Normalize.Error.invalidUsername) { try Normalize.linkedin("e" + String(repeating: mark, count: 99)) }
    let long = "abc" + String(repeating: mark, count: 97)
    #expect(try Normalize.linkedin(long) == long)
    #expect(try Normalize.linkedin(CanonicalURI.linkedin(long)) == long)
    #expect(throws: Normalize.Error.tooLong) { try Normalize.linkedin(long + mark) }
    #expect(CanonicalURI.linkedin("company/x\(mark)y") == "https://www.linkedin.com/company/x\(mark)y")
    #expect(try Normalize.linkedin("MWLITE/COMPANY/x\(mark)yz") == "company/x\(mark)yz")
}

@Test func mastodonChecksUsersAndSegmentsOnScalars() throws {
    for input in ["bl\(reph)oom@nnix.com", "blo\(mark)om@nnix.com", "https://nnix.com/@bl\(reph) oom", "https://nnix.com/users/blo\(mark)om",
                  "a" + String(repeating: mark, count: 30) + "@nnix.com"] {
        #expect(throws: Normalize.Error.invalidUsername, "\(scalars(input))") { try Normalize.mastodon(input) }
    }
    // `users` with a mark is another segment, not the users route.
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.mastodon("https://nnix.com/users\(mark)/bloom") }
    // Instances are hostnames: the Prepend letter is a letter, its whitespace is not.
    #expect(try Normalize.mastodon("bloom@nn\(reph)ix.com") == "bloom@nn\(reph)ix.com")
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.mastodon("bloom@nn\(reph) ix.com") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.mastodon("https://nn\(reph)_ix.com/@bloom") }
    // The canonical URI splits at the last `@` scalar.
    let canonical = try #require(CanonicalURI.mastodon("@bloom@\(mark)nnix.com"))
    #expect(canonical.account == "acct:bloom@\(mark)nnix.com")
    #expect(canonical.profile == "https://\(mark)nnix.com/@bloom")
    #expect(CanonicalURI.mastodon("bloom@") == nil)
}

@Test func calendlyChecksSegmentsOnScalars() throws {
    for input in ["bl\(reph)oom", "bl\(reph) oom/coffee", "blo\(mark)om", "https://calendly.com/bl\(reph)oom",
                  "a" + String(repeating: mark, count: 64)] {
        #expect(throws: Normalize.Error.invalidPath, "\(scalars(input))") { try Normalize.calendly(input) }
    }
    // `://` and the host prefix are matched as scalars, whatever follows them.
    #expect(throws: Normalize.Error.wrongHost("\(mark)calendly.com")) { try Normalize.calendly("https://\(mark)calendly.com/bloom") }
    #expect(throws: Normalize.Error.wrongHost("calendly.com\(mark)")) { try Normalize.calendly("calendly.com\(mark)/bloom") }
    #expect(try Normalize.calendly("CALENDLY.COM/bloom/coffee") == "bloom/coffee")
}

@Test func signalMatchesHostAndPathOnScalars() throws {
    let encoded = Base64.encode([UInt8](repeating: 0x5a, count: 48), url: true)
    #expect(throws: Normalize.Error.wrongHost("signal.me\(mark)")) { try SignalLink.parse("https://signal.me\(mark)/#eu/" + encoded) }
    for input in ["https://signal.me/#\(mark)eu/" + encoded, "https://signal.me/#eu/\(mark)" + encoded,
                  "https://signal.me/\(mark)#eu/" + encoded, "https://signal.me/#eu\(mark)/" + encoded] {
        #expect(throws: Normalize.Error.invalidPath, "\(scalars(input))") { try SignalLink.parse(input) }
    }
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph) "))) { try SignalLink.parse("https://signal.me/#p/+353\(reph) 871234567") }
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph)8"))) { try SignalLink.parse("https://signal.me/#p/+353\(reph)871234567") }
    #expect(try SignalLink.parse("SGNL://SIGNAL.ME/#eu/" + encoded).url == "https://signal.me/#eu/" + encoded)
}

@Test func phoneAndFingerprintNameTheGraphemeAroundABadScalar() throws {
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph)8"))) { try Normalize.phone("+353\(reph)871234567") }
    #expect(throws: Normalize.Error.invalidCharacter(Character(" \(mark)"))) { try Normalize.phone("+353 \(mark)871234567") }
    #expect(try Normalize.phone("+353\u{2003}87 123 4567") == "+353871234567")
    let hex = "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph)6"))) { try Normalize.gpgFingerprint("EF\(reph)6E" + hex.dropFirst(4)) }
    #expect(throws: Normalize.Error.invalidCharacter(Character("F\(mark)"))) { try Normalize.gpgFingerprint("EF\(mark)6E" + hex.dropFirst(4)) }
}

// MARK: - SSH

@Test func sshLinesSplitOnSpaceAndTabOnly() throws {
    let key = try SSHPublicKey(line: ed1)
    let tabbed = try SSHPublicKey(line: "ssh-ed25519\t\(ed1Base64)  \t ed1 \u{A0}x")
    #expect(tabbed.blob == key.blob && tabbed.comment == "ed1 \u{A0}x")
    // A Prepend letter or a mark glued to a separator does not hide it.
    #expect(throws: SSHPublicKey.Error.unsupportedType("ssh-ed25519\(reph)")) { try SSHPublicKey(line: "ssh-ed25519\(reph) \(ed1Base64)") }
    #expect(throws: SSHPublicKey.Error.invalidBase64) { try SSHPublicKey(line: "ssh-ed25519 \(mark)\(ed1Base64)") }
    #expect(try SSHPublicKey(line: "ssh-ed25519 \(ed1Base64) \(reph) x").comment == "\(reph) x")
    #expect(try SSHPublicKey(line: "ssh-ed25519 \(ed1Base64) \(mark)x").comment == "\(mark)x")
    // Type names and the `sk-` prefix are matched scalar by scalar.
    #expect(throws: SSHPublicKey.Error.securityKey("sk-\(mark)ssh-ed25519@openssh.com")) { try SSHPublicKey(line: "sk-\(mark)ssh-ed25519@openssh.com AAAA") }
    #expect(throws: SSHPublicKey.Error.unsupportedType("ssh-ed25519\(mark)")) { try SSHPublicKey(line: "ssh-ed25519\(mark) \(ed1Base64)") }
    #expect(SSHPublicKey.Kind(typeName: "ssh-ed25519\(mark)") == nil)
    #expect(SSHPublicKey.Kind(typeName: "ssh-ed25519") == .ed25519)
    // An options field ends at a space or tab, not at another whitespace scalar.
    #expect(throws: SSHPublicKey.Error.optionsNotSupported) { try SSHPublicKey(line: "no-pty\t" + ed1) }
    #expect(throws: SSHPublicKey.Error.unsupportedType("no-pty\u{A0}ssh-ed25519")) { try SSHPublicKey(line: "no-pty\u{A0}ssh-ed25519 \(ed1Base64)") }
    // The comment is the remainder verbatim, so it round-trips.
    let commented = try SSHPublicKey(line: "ssh-ed25519 \(ed1Base64) a\u{A0}b\u{3000}c")
    #expect(commented.comment == "a\u{A0}b\u{3000}c")
    #expect(try SSHPublicKey(line: commented.authorizedKeysLine()) == commented)
}

@Test func allowedSignersDropQuotesAndBackslashesOnScalars() throws {
    let key = try SSHPublicKey(line: ed1)
    let tail = "ssh-ed25519 " + ed1Base64
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: "git\\\(mark)") == "bloom@nnix.com namespaces=\"git\(mark)\" " + tail)
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: "\"\(mark)git\"") == "bloom@nnix.com namespaces=\"\(mark)git\" " + tail)
    #expect(key.allowedSignersLine(principal: "bl\"\\oom@nnix.com\(reph) x") == "bloom@nnix.com\(reph)x namespaces=\"git\" " + tail)
    #expect(key.allowedSignersLine(principal: "\\\(mark)#bloom@nnix.com") == "\(mark)#bloom@nnix.com namespaces=\"git\" " + tail)
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: "\\\"\\") == "bloom@nnix.com namespaces=\"\" " + tail)
}

/// OpenSSH's 17-byte title buffer: what fits is a matter of bytes.
@Test func randomartBordersCountBytes() throws {
    let sixteenBytes = "[" + String(repeating: "é", count: 7) + "]"
    #expect(sixteenBytes.utf8.count == 16 && sixteenBytes.count == 9)
    #expect(SSHPublicKey.randomart(fingerprint: [], title: sixteenBytes).hasPrefix("+" + sixteenBytes + "-+\n"))
    let seventeenBytes = "[" + String(repeating: "é", count: 7) + "x]"
    #expect(SSHPublicKey.randomart(fingerprint: [], title: seventeenBytes).hasPrefix("+-----------------+\n"))
    #expect(SSHPublicKey.randomart(fingerprint: [], title: "[e\(mark)]").hasPrefix("+------[e\(mark)]------+\n"))
}

// MARK: - vCard

@Test func vCardNameWordsSplitOnWhitespaceScalars() throws {
    let card = VCard(formattedName: "Leopold\(reph) Bloom")
    #expect(card.givenName == "Leopold\(reph)" && card.familyName == "Bloom")
    let marked = VCard(formattedName: "Leopold \(mark)Bloom")
    #expect(marked.givenName == "Leopold" && marked.familyName == "\(mark)Bloom")
    #expect(VCard(formattedName: "\(mark)").givenName == "\(mark)")
    #expect(VCard(formattedName: "Henry\u{2003}Flower\u{A0}Bloom").givenName == "Henry Flower")
}

@Test func vCardPropertyNamesAreASCIIOnScalars() throws {
    #expect(VCard.Extension(name: "ke\(mark)y", value: "").name == "KEY")
    #expect(VCard.Extension(name: "k\(reph)ey", value: "").name == "KEY")
    // Names fold ASCII case only; a name with a mark is not the property, and
    // a dotless i does not uppercase into BEGIN.
    let text = "begin:vcard\r\nversion:3.0\r\nfn\(mark):x\r\nFN:y\r\nend:vcard\r\n"
    #expect(try VCard.parseBasic(text).formattedName == "y")
    #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("BEGIN:VCARD\(mark)\r\nVERSION:3.0\r\nEND:VCARD\r\n") }
    #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("begın:vcard\r\nVERSION:3.0\r\nEND:VCARD\r\n") }
    #expect(throws: VCard.Error.unsupportedVersion("3.0\(mark)")) { try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0\(mark)\r\nEND:VCARD\r\n") }
    // The group ends at the dot scalar, whatever precedes it.
    let grouped = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\nitem1\(reph).URL:https://nnix.com\r\nitem1\(reph).X-ABLabel:Web\r\nEND:VCARD\r\n"
    #expect(try VCard.parseBasic(grouped).links == [VCard.Link(label: "Web", url: "https://nnix.com")])
    // The property head ends at the colon scalar, even after a Prepend letter.
    #expect(VCard.splitProperty("FN\(reph):x")?.head == "FN\(reph)")
    #expect(VCard.splitProperty("FN\(reph):x")?.value == "x")
    // A photo's base64 loses whitespace scalars only; a mark is not base64.
    let photo = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\nPHOTO;ENCODING=b;TYPE=JPEG:AAEC \(mark)Aw==\r\nEND:VCARD\r\n"
    #expect(try VCard.parseBasic(photo).photoJPEG == nil)
    let spaced = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\nPHOTO;ENCODING=b;TYPE=JPEG:AAEC Aw==\r\nEND:VCARD\r\n"
    #expect(try VCard.parseBasic(spaced).photoJPEG == [0, 1, 2, 3])
    let uri = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\nPHOTO;value=\"uri\":AAECAw==\r\nEND:VCARD\r\n"
    #expect(try VCard.parseBasic(uri).photoJPEG == nil)
}
