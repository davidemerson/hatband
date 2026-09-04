import Testing
@testable import HatbandCore

// MARK: - Base64

/// RFC 4648 §10.
private let base64Vectors: [(String, String)] = [
    ("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="),
    ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy"),
]

@Test(arguments: base64Vectors)
func base64EncodesRFCVectors(plain: String, encoded: String) {
    #expect(Base64.encode(Array(plain.utf8)) == encoded)
    let unpadded = String(encoded.prefix { $0 != "=" })
    #expect(Base64.encode(Array(plain.utf8), url: true) == unpadded)
}

@Test(arguments: base64Vectors)
func base64DecodesRFCVectors(plain: String, encoded: String) throws {
    #expect(try Base64.decode(encoded) == Array(plain.utf8))
    let unpadded = String(encoded.prefix { $0 != "=" })
    #expect(try Base64.decode(unpadded) == Array(plain.utf8))
    #expect(try Base64.decode(unpadded, url: true) == Array(plain.utf8))
}

@Test func base64UsesTheRightAlphabet() throws {
    let bytes: [UInt8] = [0xfb, 0xff, 0xbf]
    #expect(Base64.encode(bytes) == "+/+/")
    #expect(Base64.encode(bytes, url: true) == "-_-_")
    #expect(try Base64.decode("+/+/") == bytes)
    #expect(try Base64.decode("-_-_", url: true) == bytes)
    #expect(throws: Base64.Error.invalidCharacter) { try Base64.decode("-_-_") }
    #expect(throws: Base64.Error.invalidCharacter) { try Base64.decode("+/+/", url: true) }
}

@Test func base64RoundTripsAllLengths() throws {
    for length in 0...64 {
        let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 53 &+ 7) }
        let standard = Base64.encode(bytes)
        #expect(standard.count == (length + 2) / 3 * 4)
        #expect(try Base64.decode(standard) == bytes)
        let url = Base64.encode(bytes, url: true)
        #expect(!url.contains("="))
        #expect(try Base64.decode(url, url: true) == bytes)
    }
    let all = Array(UInt8.min...UInt8.max)
    #expect(try Base64.decode(Base64.encode(all)) == all)
    #expect(try Base64.decode(Base64.encode(all, url: true), url: true) == all)
}

private let badBase64: [(String, Base64.Error)] = [
    ("Z", .invalidLength), ("Zm9vY", .invalidLength),
    ("Zg=", .invalidPadding), ("Zg===", .invalidPadding), ("Zm9v=", .invalidPadding), ("Zm9vYg=", .invalidPadding),
    ("Zh==", .nonZeroPadding), ("Zm9", .nonZeroPadding),
    ("Zm9v YmFy", .invalidCharacter), ("Zm9v\nYmFy", .invalidCharacter), ("Zm9v*", .invalidCharacter), ("=", .invalidPadding),
]

@Test(arguments: badBase64)
func base64RejectsMalformed(text: String, error: Base64.Error) {
    #expect(throws: error) { try Base64.decode(text) }
}

// MARK: - Phone

private let goodPhones: [(String, String)] = [
    ("+353871234567", "+353871234567"),
    ("+353 87 123 4567", "+353871234567"),
    ("+353-87-123-4567", "+353871234567"),
    ("+353.87.123.4567", "+353871234567"),
    ("+353 (87) 123 4567", "+353871234567"),
    ("  +353871234567\n", "+353871234567"),
    ("tel:+353871234567", "+353871234567"),
    ("TEL:+353871234567", "+353871234567"),
    ("+1 (415) 555-0100", "+14155550100"),
    ("+44 20 7946 0958", "+442079460958"),
    ("+353\u{2013}87\u{2013}123\u{2013}4567", "+353871234567"),
    ("+353\u{2212}87\u{2010}123\u{2014}4567", "+353871234567"),
    ("+353\u{a0}87\u{a0}123\u{a0}4567", "+353871234567"),
    ("+12345678", "+12345678"),
    ("+123456789012345", "+123456789012345"),
    ("+ 353 87 123 4567", "+353871234567"),
]

@Test(arguments: goodPhones)
func normalizesPhones(input: String, stored: String) throws {
    #expect(try Normalize.phone(input) == stored)
    #expect(try Normalize.phone(stored) == stored, "stored form is a fixed point")
}

private let badPhones: [(String, Normalize.Error)] = [
    ("", .empty), ("   ", .empty), ("tel:", .empty), ("()", .empty),
    ("0871234567", .missingPlus), ("353871234567", .missingPlus), ("00353871234567", .missingPlus),
    ("+1234567", .tooShort), ("+", .tooShort), ("+1234567890123456", .tooLong),
    ("+0871234567", .invalidCountryCode),
    ("+353 87 CALL ME", .invalidCharacter("C")), ("++353871234567", .invalidCharacter("+")),
    ("+353871234567x12", .invalidCharacter("x")), ("+353871234567;ext=1", .invalidCharacter(";")),
    ("+\u{663}\u{665}\u{663}871234567", .invalidCharacter("\u{663}")), ("+353871234567/", .invalidCharacter("/")),
    ("+353871234567+", .invalidCharacter("+")), ("+353\u{0}871234567", .invalidCharacter("\u{0}")),
]

@Test(arguments: badPhones)
func rejectsPhones(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.phone(input) }
}

// MARK: - Email

private let goodEmails: [(String, String)] = [
    ("henry.flower@example.ie", "henry.flower@example.ie"),
    ("Henry.Flower@Example.IE", "Henry.Flower@example.ie"),
    ("  bloom@nnix.com ", "bloom@nnix.com"),
    ("mailto:bloom@nnix.com", "bloom@nnix.com"),
    ("MAILTO:bloom@nnix.com", "bloom@nnix.com"),
    ("Leopold Bloom <bloom@nnix.com>", "bloom@nnix.com"),
    ("<bloom@nnix.com>", "bloom@nnix.com"),
    ("a+b@example.com", "a+b@example.com"),
    ("o'brien@example.com", "o'brien@example.com"),
    ("user@sub.example.co.uk", "user@sub.example.co.uk"),
    ("x@example.com", "x@example.com"),
    ("a?b#c@example.com", "a?b#c@example.com"),
    ("!#$%&'*+-/=?^_`{|}~@example.com", "!#$%&'*+-/=?^_`{|}~@example.com"),
    ("bloom@nnix.com.", "bloom@nnix.com"),
    ("bloom@xn--mller-kva.de", "bloom@xn--mller-kva.de"),
]

@Test(arguments: goodEmails)
func normalizesEmails(input: String, stored: String) throws {
    #expect(try Normalize.email(input) == stored)
    #expect(try Normalize.email(stored) == stored)
}

private let badEmails: [(String, Normalize.Error)] = [
    ("", .empty), ("  ", .empty), ("mailto:", .empty), ("<>", .empty),
    ("bloom", .missingAt), ("bloom.nnix.com", .missingAt),
    ("a@b@c.com", .multipleAt), ("@@", .multipleAt),
    ("bloom@", .invalidHost), ("bloom@localhost", .invalidHost), ("bloom@nnix..com", .invalidHost),
    ("bloom@-nnix.com", .invalidHost), ("bloom@nnix-.com", .invalidHost), ("bloom@nnix.123", .invalidHost),
    ("bloom@[127.0.0.1]", .invalidHost), ("bloom@.nnix.com", .invalidHost),
    ("bloom@" + String(repeating: "a", count: 64) + ".com", .invalidHost),
    ("@nnix.com", .invalidLocalPart), (".bloom@nnix.com", .invalidLocalPart), ("bloom.@nnix.com", .invalidLocalPart),
    ("bl..oom@nnix.com", .invalidLocalPart), ("\"quoted\"@nnix.com", .invalidLocalPart),
    ("bl(oom)@nnix.com", .invalidLocalPart), ("bloom,x@nnix.com", .invalidLocalPart),
    (String(repeating: "a", count: 65) + "@nnix.com", .invalidLocalPart),
    ("bl oom@nnix.com", .invalidCharacter(" ")), ("blo\nom@nnix.com", .invalidCharacter("\n")),
    ("blo\tom@nnix.com", .invalidCharacter("\t")), ("bløom@nnix.com", .invalidCharacter("ø")),
    ("bloom@nnïx.com", .invalidCharacter("ï")),
    (String(repeating: "a", count: 64) + "@" + String(repeating: "b", count: 63) + "." + String(repeating: "c", count: 63) + "." + String(repeating: "d", count: 63) + ".com", .tooLong),
]

@Test(arguments: badEmails)
func rejectsEmails(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.email(input) }
}

@Test func emailAcceptsExactly254Characters() throws {
    let local = String(repeating: "a", count: 64)
    let domain = [String(repeating: "b", count: 63), String(repeating: "c", count: 63), String(repeating: "d", count: 58), "ie"].joined(separator: ".")
    let address = local + "@" + domain
    #expect(address.count == 254)
    #expect(try Normalize.email(address) == address)
    #expect(throws: Normalize.Error.tooLong) { try Normalize.email(local + "@" + domain.dropLast(2) + "com") }
}

// MARK: - Website

private let goodWebsites: [(String, String, Bool)] = [
    ("nnix.com", "nnix.com", false),
    ("https://nnix.com", "nnix.com", false),
    ("http://nnix.com", "nnix.com", true),
    ("HTTPS://NNIX.COM/", "nnix.com", false),
    ("Http://Example.org", "example.org", true),
    ("nnix.com/", "nnix.com", false),
    ("//nnix.com", "nnix.com", false),
    ("www.nnix.com", "www.nnix.com", false),
    ("https://www.example.org/~d/Page?x=1&y=2", "www.example.org/~d/Page?x=1&y=2", false),
    ("Example.COM/Path/", "example.com/Path/", false),
    ("example.com:8080/app", "example.com:8080/app", false),
    ("https://example.com:443", "example.com:443", false),
    ("https://example.com?q=1", "example.com?q=1", false),
    ("https://example.com/#top", "example.com/#top", false),
    ("müller.de", "müller.de", false),
    ("MÜLLER.de/Straße", "müller.de/Straße", false),
    ("  nnix.com  ", "nnix.com", false),
    ("nnix.com.", "nnix.com", false),
    ("a.b.c.d.example.museum/x", "a.b.c.d.example.museum/x", false),
]

@Test(arguments: goodWebsites)
func normalizesWebsites(input: String, address: String, insecure: Bool) throws {
    let stored = try Normalize.website(input)
    #expect(stored.address == address)
    #expect(stored.insecure == insecure)
    let again = try Normalize.website(CanonicalURI.website(address, insecure: insecure))
    #expect(again.address == address && again.insecure == insecure, "canonical URI round-trips")
}

private let badWebsites: [(String, Normalize.Error)] = [
    ("", .empty), (" \n ", .empty),
    ("ftp://example.com", .unsupportedScheme("ftp")), ("mailto:bloom@nnix.com", .unsupportedScheme("mailto")),
    ("javascript:alert(1)", .unsupportedScheme("javascript")), ("data:text/html,x", .unsupportedScheme("data")),
    ("FILE:///etc/passwd", .unsupportedScheme("file")), ("hatband:x", .unsupportedScheme("hatband")),
    ("https://user:pw@example.com", .userinfo), ("https://user@example.com", .userinfo), ("user@example.com", .userinfo),
    ("example", .invalidHost), ("localhost:8080", .invalidHost), ("https://", .invalidHost), ("https:///path", .invalidHost),
    ("example.com:99999", .invalidHost), ("example.com:abc", .invalidHost), ("example.com:", .invalidHost),
    ("192.168.0.1", .invalidHost), ("[::1]", .invalidHost), ("-example.com", .invalidHost), ("example..com", .invalidHost),
    ("exam_ple.com", .invalidHost), (".example.com", .invalidHost), ("/path/only", .invalidHost),
    ("exa mple.com", .invalidCharacter(" ")), ("example.com/pa th", .invalidCharacter(" ")),
    ("exam\u{0}ple.com", .invalidCharacter("\u{0}")), ("example.com/\r\nx", .invalidCharacter("\r\n")),
]

@Test(arguments: badWebsites)
func rejectsWebsites(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.website(input) }
}

// MARK: - GitHub

private let goodGitHub: [(String, String)] = [
    ("bloom", "bloom"), ("@bloom", "bloom"), (" @Bloom ", "Bloom"),
    ("https://github.com/bloom", "bloom"), ("https://github.com/bloom/", "bloom"),
    ("https://www.github.com/Bloom?tab=repositories", "Bloom"), ("github.com/bloom/hatband", "bloom"),
    ("http://GitHub.com/bloom", "bloom"), ("GITHUB.COM/bloom#readme", "bloom"),
    ("a", "a"), ("a-b", "a-b"), ("1234", "1234"),
    (String(repeating: "a", count: 39), String(repeating: "a", count: 39)),
]

@Test(arguments: goodGitHub)
func normalizesGitHub(input: String, stored: String) throws {
    #expect(try Normalize.github(input) == stored)
    #expect(try Normalize.github(CanonicalURI.github(stored)) == stored)
}

private let badGitHub: [(String, Normalize.Error)] = [
    ("", .empty), ("@", .empty), ("  ", .empty),
    ("-bloom", .invalidUsername), ("bloom-", .invalidUsername), ("bl_oom", .invalidUsername), ("bloom!", .invalidUsername),
    ("blöom", .invalidUsername), ("bl oom", .invalidUsername), ("@-", .invalidUsername),
    (String(repeating: "a", count: 40), .tooLong),
    ("https://gitlab.com/bloom", .wrongHost("gitlab.com")), ("https://github.com.evil.io/bloom", .wrongHost("github.com.evil.io")),
    ("bloom/hatband", .wrongHost("bloom")), ("https://gist.github.com/bloom", .wrongHost("gist.github.com")),
    ("https://github.com/", .invalidPath), ("https://github.com", .invalidPath),
    ("ftp://github.com/bloom", .unsupportedScheme("ftp")), ("https://bloom@github.com/bloom", .userinfo),
]

@Test(arguments: badGitHub)
func rejectsGitHub(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.github(input) }
}

// MARK: - LinkedIn

private let goodLinkedIn: [(String, String)] = [
    ("leopold-bloom", "leopold-bloom"), ("@leopold-bloom", "leopold-bloom"),
    ("https://www.linkedin.com/in/leopold-bloom", "leopold-bloom"),
    ("https://www.linkedin.com/in/leopold-bloom/", "leopold-bloom"),
    ("https://ie.linkedin.com/in/leopold-bloom?trk=public_profile", "leopold-bloom"),
    ("http://uk.linkedin.com/in/leopold-bloom/#experience", "leopold-bloom"),
    ("linkedin.com/in/leopold-bloom", "leopold-bloom"), ("in/leopold-bloom", "leopold-bloom"),
    ("www.linkedin.com/in/leopold-bloom-1a2b3c/", "leopold-bloom-1a2b3c"),
    ("LinkedIn.com/IN/Bloom", "Bloom"),
    ("https://www.linkedin.com/company/freemans-journal", "company/freemans-journal"),
    ("company/freemans-journal", "company/freemans-journal"),
    ("https://www.linkedin.com/in/%C3%A9amonn-de-valera", "éamonn-de-valera"),
    ("https://www.linkedin.com/in/李四-1a2b", "李四-1a2b"),
    ("abc", "abc"),
    (String(repeating: "a", count: 100), String(repeating: "a", count: 100)),
]

@Test(arguments: goodLinkedIn)
func normalizesLinkedIn(input: String, stored: String) throws {
    #expect(try Normalize.linkedin(input) == stored)
    #expect(try Normalize.linkedin(CanonicalURI.linkedin(stored)) == stored)
}

private let badLinkedIn: [(String, Normalize.Error)] = [
    ("", .empty), ("@", .empty),
    ("ab", .invalidUsername), ("-bloom", .invalidUsername), ("bloom-", .invalidUsername), ("bloom_x", .invalidUsername),
    ("bloom.x", .invalidUsername), ("in/ab", .invalidUsername), ("in/李四", .invalidUsername), ("company/-x", .invalidUsername),
    ("in/", .invalidPath), ("company/", .invalidPath),
    (String(repeating: "a", count: 101), .tooLong),
    ("https://www.linkedin.com/pub/leopold-bloom", .invalidPath), ("https://www.linkedin.com/in/", .invalidPath),
    ("https://www.linkedin.com/", .invalidPath), ("https://www.linkedin.com/school/ucd", .invalidPath),
    ("https://lnkd.in/abc", .wrongHost("lnkd.in")), ("https://linkedin.com.evil.com/in/bloom", .wrongHost("linkedin.com.evil.com")),
    ("https://notlinkedin.com/in/bloom", .wrongHost("notlinkedin.com")),
    ("https://www.linkedin.com/in/%ZZ", .invalidPath), ("https://www.linkedin.com/in/%C3%28", .invalidPath),
    ("ftp://www.linkedin.com/in/bloom", .unsupportedScheme("ftp")), ("https://x@www.linkedin.com/in/bloom", .userinfo),
]

@Test(arguments: badLinkedIn)
func rejectsLinkedIn(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.linkedin(input) }
}

// MARK: - Mastodon

private let goodMastodon: [(String, String)] = [
    ("bloom@merveilles.town", "bloom@merveilles.town"), ("@bloom@merveilles.town", "bloom@merveilles.town"),
    ("@bloom@Merveilles.Town", "bloom@merveilles.town"), (" bloom@merveilles.town ", "bloom@merveilles.town"),
    ("https://merveilles.town/@bloom", "bloom@merveilles.town"), ("https://merveilles.town/@bloom/", "bloom@merveilles.town"),
    ("https://merveilles.town/users/bloom", "bloom@merveilles.town"), ("merveilles.town/@bloom", "bloom@merveilles.town"),
    ("http://MERVEILLES.town/@bloom?x=1", "bloom@merveilles.town"),
    ("Bloom_1@mastodon.social", "Bloom_1@mastodon.social"),
    (String(repeating: "a", count: 30) + "@m.social", String(repeating: "a", count: 30) + "@m.social"),
]

@Test(arguments: goodMastodon)
func normalizesMastodon(input: String, stored: String) throws {
    #expect(try Normalize.mastodon(input) == stored)
    let canonical = try #require(CanonicalURI.mastodon(stored))
    #expect(try Normalize.mastodon(canonical.profile) == stored)
    #expect(canonical.account == "acct:" + stored)
}

private let badMastodon: [(String, Normalize.Error)] = [
    ("", .empty), ("@", .empty),
    ("bloom", .missingAt), ("@bloom", .missingAt),
    ("bloom@a@b.c", .multipleAt), ("@bloom@a@b.c", .multipleAt),
    ("bloom@merveilles", .invalidHost), ("bloom@", .invalidHost), ("bloom@-m.town", .invalidHost),
    ("https://merveilles/@bloom", .invalidHost),
    ("@merveilles.town", .missingAt), ("bl-oom@merveilles.town", .invalidUsername),
    ("bloom.x@m.town", .invalidUsername), ("blöom@m.town", .invalidUsername),
    (String(repeating: "a", count: 31) + "@m.social", .invalidUsername),
    ("https://merveilles.town/bloom", .invalidPath), ("https://merveilles.town/", .invalidPath),
    ("https://merveilles.town/@bloom/followers", .invalidPath), ("https://merveilles.town/users/", .invalidPath),
    ("https://merveilles.town/@", .invalidUsername),
    ("ftp://merveilles.town/@bloom", .unsupportedScheme("ftp")), ("https://x@merveilles.town/@bloom", .userinfo),
]

@Test(arguments: badMastodon)
func rejectsMastodon(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.mastodon(input) }
}

// MARK: - Calendly

private let goodCalendly: [(String, String)] = [
    ("bloom", "bloom"), ("bloom/coffee", "bloom/coffee"), ("/bloom/coffee/", "bloom/coffee"),
    ("https://calendly.com/bloom/coffee", "bloom/coffee"), ("https://calendly.com/bloom/coffee?month=2026-09", "bloom/coffee"),
    ("calendly.com/bloom", "bloom"), ("https://www.calendly.com/bloom/", "bloom"), ("HTTPS://CALENDLY.COM/bloom", "bloom"),
    ("https://calendly.com/d/cmz-3gv-xyz/coffee-chat", "d/cmz-3gv-xyz/coffee-chat"),
    ("d/cmz-3gv-xyz/coffee-chat", "d/cmz-3gv-xyz/coffee-chat"),
    ("Bloom_2/30min", "Bloom_2/30min"),
]

@Test(arguments: goodCalendly)
func normalizesCalendly(input: String, stored: String) throws {
    #expect(try Normalize.calendly(input) == stored)
    #expect(try Normalize.calendly(CanonicalURI.calendly(stored)) == stored)
}

private let badCalendly: [(String, Normalize.Error)] = [
    ("", .empty), ("/", .empty), ("https://calendly.com/", .empty), ("?month=1", .empty),
    ("https://cal.com/bloom", .wrongHost("cal.com")), ("https://calendly.com.evil.io/bloom", .wrongHost("calendly.com.evil.io")),
    ("a/b/c/d", .invalidPath), ("bloom/co ffee", .invalidPath), ("bloom/../x", .invalidPath), ("bl.oom", .invalidPath),
    ("blöom", .invalidPath), (String(repeating: "a", count: 65), .invalidPath),
    ("ftp://calendly.com/bloom", .unsupportedScheme("ftp")), ("https://x@calendly.com/bloom", .userinfo),
]

@Test(arguments: badCalendly)
func rejectsCalendly(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.calendly(input) }
}

// MARK: - GPG fingerprints

private let torV4 = "EF6E 286D DA85 EA2A 4BA7  DE68 4E2C 6E87 9329 8290"
private let torV4Hex = "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"
/// RFC 9580 Appendix A.3, the v6 sample certificate.
private let rfcV6Hex = "CB186C4F0609A697E4D52DFA6C722B0C1F1E27C18A56708F6525EC27BAD9ACC9"

private let v4Spellings: [String] = [
    torV4, torV4Hex, torV4Hex.lowercased(), "0x" + torV4Hex, "0X" + torV4Hex.lowercased(),
    "OPENPGP4FPR:" + torV4Hex, "openpgp4fpr:" + torV4Hex, "OPENPGP4FPR: " + torV4,
    "EF:6E:28:6D:DA:85:EA:2A:4B:A7:DE:68:4E:2C:6E:87:93:29:82:90",
    "  EF6E 286D DA85 EA2A 4BA7\n DE68 4E2C 6E87 9329 8290  ",
]

@Test(arguments: v4Spellings)
func normalizesV4Fingerprints(input: String) throws {
    let fingerprint = try Normalize.gpgFingerprint(input)
    #expect(fingerprint.bytes.count == 20)
    #expect(fingerprint.isV4)
    #expect(fingerprint.hex == torV4Hex)
    #expect(fingerprint.formatted == torV4)
    #expect(fingerprint.uri == "OPENPGP4FPR:" + torV4Hex)
    #expect(fingerprint.bytes.prefix(4) == [0xef, 0x6e, 0x28, 0x6d])
    #expect(CanonicalURI.gpgFingerprint(fingerprint.bytes) == fingerprint.uri)
    #expect(try Normalize.gpgFingerprint(fingerprint.uri) == fingerprint)
    #expect(try Normalize.gpgFingerprint(fingerprint.formatted) == fingerprint)
}

@Test func normalizesV6Fingerprints() throws {
    let fingerprint = try Normalize.gpgFingerprint(rfcV6Hex)
    #expect(fingerprint.bytes.count == 32)
    #expect(!fingerprint.isV4)
    #expect(fingerprint.hex == rfcV6Hex)
    #expect(fingerprint.formatted == "CB18 6C4F 0609 A697 E4D5 2DFA 6C72 2B0C  1F1E 27C1 8A56 708F 6525 EC27 BAD9 ACC9")
    #expect(fingerprint.uri == "OPENPGP4FPR:" + rfcV6Hex)
    #expect(try Normalize.gpgFingerprint(fingerprint.formatted) == fingerprint)
    #expect(try GPGFingerprint(bytes: fingerprint.bytes) == fingerprint)
}

private let badFingerprints: [(String, Normalize.Error)] = [
    ("", .empty), ("0x", .empty), ("OPENPGP4FPR:", .empty), (" : : ", .empty),
    (String(torV4Hex.dropLast()), .invalidHex),
    (String(torV4Hex.dropLast(2)), .wrongLength(19)), (torV4Hex + "AB", .wrongLength(21)),
    ("4E2C6E8793298290", .wrongLength(8)), (rfcV6Hex + "00", .wrongLength(33)),
    (String(torV4Hex.dropLast()) + "G", .invalidCharacter("G")), ("0x" + torV4Hex + "x", .invalidCharacter("x")),
    (torV4 + "!", .invalidCharacter("!")), ("OPENPGP4FPR:" + torV4Hex + ";", .invalidCharacter(";")),
]

@Test(arguments: badFingerprints)
func rejectsFingerprints(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.gpgFingerprint(input) }
}

@Test(arguments: [0, 1, 19, 21, 31, 33, 64])
func fingerprintRequiresTwentyOrThirtyTwoBytes(count: Int) {
    #expect(throws: Normalize.Error.wrongLength(count)) { try GPGFingerprint(bytes: [UInt8](repeating: 0, count: count)) }
}

// MARK: - Canonical URIs

@Test func canonicalURIs() {
    #expect(CanonicalURI.phone("+353871234567") == "tel:+353871234567")
    #expect(CanonicalURI.email("bloom@nnix.com") == "mailto:bloom@nnix.com")
    #expect(CanonicalURI.email("o'brien+x@x.com") == "mailto:o'brien+x@x.com")
    #expect(CanonicalURI.email("a?b#c%d&e=f/g@x.com") == "mailto:a%3Fb%23c%25d%26e%3Df%2Fg@x.com")
    #expect(CanonicalURI.website("nnix.com") == "https://nnix.com")
    #expect(CanonicalURI.website("nnix.com/~bloom?x=1", insecure: true) == "http://nnix.com/~bloom?x=1")
    #expect(CanonicalURI.github("lbloom") == "https://github.com/lbloom")
    #expect(CanonicalURI.linkedin("leopold-bloom") == "https://www.linkedin.com/in/leopold-bloom")
    #expect(CanonicalURI.linkedin("company/freemans-journal") == "https://www.linkedin.com/company/freemans-journal")
    #expect(CanonicalURI.calendly("bloom/coffee") == "https://calendly.com/bloom/coffee")
    #expect(CanonicalURI.gpgFingerprint([0xab, 0xcd, 0x01]) == "OPENPGP4FPR:ABCD01")
    let mastodon = CanonicalURI.mastodon("bloom@merveilles.town")
    #expect(mastodon?.account == "acct:bloom@merveilles.town")
    #expect(mastodon?.profile == "https://merveilles.town/@bloom")
    #expect(CanonicalURI.mastodon("bloom") == nil)
    #expect(CanonicalURI.mastodon("@merveilles.town") == nil)
    #expect(CanonicalURI.mastodon("bloom@") == nil)
}

// MARK: - Signal

private let usernameBytes = (0..<48).map { UInt8($0 &* 5 &+ 3) }
private let usernameBase64 = Base64.encode(usernameBytes, url: true)
private let usernameLink = "https://signal.me/#eu/" + usernameBase64

private let usernameSpellings: [String] = [
    usernameLink, " " + usernameLink + "\n", "signal.me/#eu/" + usernameBase64,
    "sgnl://signal.me/#eu/" + usernameBase64, "https://SIGNAL.ME/#eu/" + usernameBase64,
    "http://signal.me#eu/" + usernameBase64,
]

@Test(arguments: usernameSpellings)
func parsesSignalUsernameLinks(input: String) throws {
    let link = try SignalLink.parse(input)
    #expect(link.kind == .username(usernameBytes))
    #expect(link.url == usernameLink)
    #expect(!link.disclosesPhoneNumber)
    #expect(link.url.count == "https://signal.me/#eu/".count + 64)
    #expect(try SignalLink.parse(link.url) == link)
    #expect(try SignalLink(username: usernameBytes) == link)
}

private let phoneSpellings: [String] = [
    "https://signal.me/#p/+353871234567", "signal.me/#p/+353.87.123.4567", "sgnl://signal.me/#p/+353-87-123-4567",
    "https://signal.me/#p/+353(87)1234567",
]

@Test(arguments: phoneSpellings)
func parsesSignalPhoneLinks(input: String) throws {
    let link = try SignalLink.parse(input)
    #expect(link.kind == .phone("+353871234567"))
    #expect(link.url == "https://signal.me/#p/+353871234567")
    #expect(link.disclosesPhoneNumber)
    #expect(try SignalLink.parse(link.url) == link)
    #expect(try SignalLink(phone: "+353 87 123 4567") == link)
}

private let badSignalLinks: [(String, Normalize.Error)] = [
    ("", .empty),
    ("https://example.com/#eu/abcd", .wrongHost("example.com")), ("https://signal.org/#eu/abcd", .wrongHost("signal.org")),
    ("https://signal.me.evil/#eu/abcd", .wrongHost("signal.me.evil")),
    ("https://signal.me/eu/abcd", .invalidPath), ("https://signal.me/#x/abcd", .invalidPath), ("https://signal.me/", .invalidPath),
    ("https://signal.me/#eu/!!!!", .invalidPath), ("https://signal.me/#eu/" + Base64.encode(usernameBytes), .invalidPath),
    ("https://signal.me/#eu/", .wrongLength(0)), ("https://signal.me/#eu/abcd", .wrongLength(3)),
    ("https://signal.me/#eu/" + Base64.encode(Array(usernameBytes.dropLast()), url: true), .wrongLength(47)),
    ("https://signal.me/#eu/" + Base64.encode(usernameBytes + [0], url: true), .wrongLength(49)),
    ("https://signal.me/#p/0871234567", .missingPlus), ("https://signal.me/#p/", .empty), ("https://signal.me/#p/+1", .tooShort),
    ("ftp://signal.me/#p/+353871234567", .unsupportedScheme("ftp")),
    ("https://signal.me/#eu/ab cd", .invalidCharacter(" ")),
]

@Test(arguments: badSignalLinks)
func rejectsSignalLinks(input: String, error: Normalize.Error) {
    #expect(throws: error) { try SignalLink.parse(input) }
}

@Test func signalUsernameNeedsFortyEightBytes() {
    #expect(throws: Normalize.Error.wrongLength(32)) { try SignalLink(username: [UInt8](repeating: 1, count: 32)) }
    #expect(throws: Normalize.Error.missingPlus) { try SignalLink(phone: "0871234567") }
}
