import Testing
@testable import HatbandCore

private let qr = Limits.qr
private let file = Limits.file

private func scalar(_ value: UInt32) -> String {
    String(Unicode.Scalar(value)!)
}

// MARK: - Limits and Verdict

@Test func presets() {
    for limits in [qr, file] {
        #expect(limits.name == 64)
        #expect(limits.company == 64)
        #expect(limits.email == 254)
        #expect(limits.phone == 16)
        #expect(limits.website == 128)
        #expect(limits.handle == 64)
        #expect(limits.signalURL == 128)
        #expect(limits.customLabel == 24)
        #expect(limits.nesting == 3)
        #expect(limits.customKinds == Set(CustomKind.allCases))
    }
    #expect(qr.payloadBytes == 2_953)
    #expect(qr.customFields == 8)
    #expect(qr.customValue == 128)
    #expect(qr.photoBytes == 0)
    #expect(qr.gpgKeyBytes == 0)
    #expect(file.payloadBytes == 32_768)
    #expect(file.customFields == 32)
    #expect(file.customValue == 1024)
    #expect(file.photoBytes == 16_384)
    #expect(file.gpgKeyBytes == 24_576)
}

@Test func verdictMerging() {
    #expect(Verdict.ok.merged(with: .ok) == .ok)
    #expect(Verdict.ok.merged(with: .warning("a")) == .warning("a"))
    #expect(Verdict.warning("a").merged(with: .ok) == .warning("a"))
    #expect(Verdict.warning("a").merged(with: .warning("b")) == .warning("a; b"))
    #expect(Verdict.warning("a").merged(with: .reject("r")) == .reject("r"))
    #expect(Verdict.reject("r").merged(with: .warning("a")) == .reject("r"))
    #expect(Verdict.reject("r").merged(with: .reject("s")) == .reject("r"))
    #expect(Verdict.ok.isAccepted)
    #expect(Verdict.warning("a").isAccepted)
    #expect(!Verdict.reject("r").isAccepted)
}

// MARK: - TextCheck

@Test(arguments: [
    ("Leopold Bloom", Verdict.ok),
    ("Лев Толстой", .ok),
    ("李小龍", .ok),
    ("山田 太郎", .ok),
    ("Zo\u{EB} O'Brien-Smith", .ok),
    ("\u{C9}mile", .ok),
    ("😀 Bloom", .ok),
    ("👋🏽", .ok),
    ("❤\u{FE0F}", .ok),
    ("\u{FB01}", .ok),
    ("a\u{FFFD}b", .ok),                 // lossy decoding leaves U+FFFD, which is a plain symbol
    ("Leopold   Bloom", .ok),            // three spaces
    ("Henry\u{A0}Flower", .ok),
    ("東京\u{3000}Tokyo", .ok),
    ("", .reject("empty")),
    ("   ", .reject("empty")),
    ("\u{A0}", .reject("empty")),
    (" \n\t ", .reject("empty")),
    ("\u{2028}", .reject("empty")),
    ("\u{3000}", .reject("empty")),
    ("a\tb", .reject("control character")),
    ("a\nb", .reject("control character")),
    ("a\rb", .reject("control character")),
    ("a\u{0}b", .reject("control character")),
    ("a\u{1B}[31mb", .reject("control character")),
    ("a\u{7F}b", .reject("control character")),
    ("a\u{85}b", .reject("control character")),
    ("a\u{9F}b", .reject("control character")),
    ("🏳\u{FE0F}\u{200D}🌈", .reject("invisible character")),   // ZWJ sequences are out, by design
    ("👨\u{200D}👩\u{200D}👧", .reject("invisible character")),
    ("می\u{200C}خواهم", .reject("invisible character")),      // and so is ZWNJ, which Persian needs
    ("a\u{E000}b", .reject("unassigned or private-use character")),
    ("a\u{378}b", .reject("unassigned or private-use character")),
    ("a\u{FFFE}b", .reject("unassigned or private-use character")),
    ("a\u{10FFFF}b", .reject("unassigned or private-use character")),
    ("a\u{F0000}b", .reject("unassigned or private-use character")),
])
func checksText(s: String, verdict: Verdict) {
    #expect(TextCheck.check(s, maxBytes: 64) == verdict)
}

@Test(arguments: [
    (" Leopold", Verdict.warning("leading or trailing whitespace, use “Leopold”")),
    ("Leopold ", .warning("leading or trailing whitespace, use “Leopold”")),
    ("\u{A0}Leopold\u{A0}", .warning("leading or trailing whitespace, use “Leopold”")),
    ("\u{3000}Leopold", .warning("leading or trailing whitespace, use “Leopold”")),
    ("Leopold    Bloom", .warning("run of spaces")),
    ("Leopold\u{A0}\u{A0}\u{A0}\u{A0}Bloom", .warning("run of spaces")),
    ("Leopold \u{A0} \u{A0}Bloom", .warning("run of spaces")),
    (" Leopold    Bloom ", .warning("leading or trailing whitespace, use “Leopold    Bloom”; run of spaces")),
    ("p\u{430}ypal", .warning("mixed scripts, looks like “paypal”")),
    ("J\u{43E}hn Smith", .warning("mixed scripts, looks like “John Smith”")),
    ("\u{3A9}mega", .warning("mixed scripts")),
    (" p\u{430}ypal", .warning("mixed scripts, looks like “paypal”; leading or trailing whitespace, use “p\u{430}ypal”")),
])
func warnsAboutText(s: String, verdict: Verdict) {
    #expect(TextCheck.check(s, maxBytes: 64) == verdict)
}

@Test func newlinesOnlyWhenAllowed() {
    #expect(TextCheck.check("Line 1\nLine 2", maxBytes: 64) == .reject("control character"))
    #expect(TextCheck.check("Line 1\nLine 2", maxBytes: 64, allowNewlines: true) == .ok)
    #expect(TextCheck.check("Line 1\r\nLine 2", maxBytes: 64, allowNewlines: true) == .reject("control character"))
    #expect(TextCheck.check("a\n\n\n\n\nb", maxBytes: 64, allowNewlines: true) == .ok, "newlines are not a run of spaces")
    #expect(TextCheck.check("a\n", maxBytes: 64, allowNewlines: true) == .warning("leading or trailing whitespace, use “a”"))
    #expect(TextCheck.check("\n", maxBytes: 64, allowNewlines: true) == .reject("empty"))
}

private let controls: [UInt32] = Array(UInt32(0x00)...0x1F) + [0x7F] + Array(UInt32(0x80)...0x9F)
private let bidi: [UInt32] = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
private let invisible: [UInt32] = [
    0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD, 0x034F, 0x180E, 0x2028, 0x2029, 0xFFF9, 0xFFFA, 0xFFFB,
    0x2061, 0x2062, 0x2063, 0x2064, 0x206A, 0x206F, 0xE0001, 0xE0020, 0xE0041, 0xE007F,
]
private let unassigned: [UInt32] = [
    0x0378, 0x0380, 0x2FE0, 0xE0080, 0xFDD0, 0xFDEF, 0xFFFE, 0xFFFF, 0x1FFFE, 0x1FFFF, 0x10FFFF,
    0xE000, 0xF8FF, 0xF0000, 0x100000,
]

@Test(arguments: controls)
func rejectsEachControl(value: UInt32) {
    let s = "a" + scalar(value) + "b"
    #expect(TextCheck.check(s, maxBytes: 64) == .reject("control character"))
    let allowed: Verdict = value == 0x0A ? .ok : .reject("control character")
    #expect(TextCheck.check(s, maxBytes: 64, allowNewlines: true) == allowed)
    #expect(TextCheck.problem(Unicode.Scalar(value)!) == "control character")
}

@Test(arguments: bidi)
func rejectsEachBidiControl(value: UInt32) {
    #expect(TextCheck.check("a" + scalar(value) + "b", maxBytes: 64) == .reject("bidirectional control character"))
    #expect(TextCheck.check(scalar(value), maxBytes: 64) == .reject("bidirectional control character"))
}

@Test(arguments: invisible)
func rejectsEachInvisible(value: UInt32) {
    #expect(TextCheck.check("a" + scalar(value) + "b", maxBytes: 64, allowNewlines: true) == .reject("invisible character"))
}

@Test(arguments: unassigned)
func rejectsEachUnassignedOrPrivate(value: UInt32) {
    #expect(TextCheck.check("a" + scalar(value) + "b", maxBytes: 64) == .reject("unassigned or private-use character"))
}

/// The rejected sets are exactly the lists above plus the categories; every
/// assigned, visible scalar outside them is allowed. Counts pin the tables.
@Test func problemScalarsAreEnumerable() {
    var counts: [String: Int] = [:]
    for value in UInt32(0)...0x10FFFF {
        guard let s = Unicode.Scalar(value), let problem = TextCheck.problem(s) else { continue }
        counts[problem, default: 0] += 1
    }
    #expect(counts["control character"] == 65)
    #expect(counts["bidirectional control character"] == 12)
    #expect(counts["invisible character"] == 3 + 3 + 2 + 5 + 6 + 1 + 3 + 128)
    #expect(counts["unassigned or private-use character", default: 0] > 800_000)
    #expect(TextCheck.problem("a") == nil)
    #expect(TextCheck.problem("\u{FE0F}") == nil, "variation selectors carry emoji presentation")
    #expect(TextCheck.problem("\u{301}") == nil)
    #expect(TextCheck.problem("\u{A0}") == nil)
}

@Test func capCountsUTF8Bytes() {
    #expect(TextCheck.check(String(repeating: "a", count: 64), maxBytes: 64) == .ok)
    #expect(TextCheck.check(String(repeating: "a", count: 65), maxBytes: 64) == .reject("over 64 bytes"))
    let twoByte = String(repeating: "\u{E9}", count: 32)
    #expect(twoByte.utf8.count == 64)
    #expect(TextCheck.check(twoByte, maxBytes: 64) == .ok)
    #expect(TextCheck.check(twoByte + "\u{E9}", maxBytes: 64) == .reject("over 64 bytes"), "33 characters, 66 bytes")
    let fourByte = String(repeating: "😀", count: 16)
    #expect(fourByte.utf8.count == 64)
    #expect(TextCheck.check(fourByte, maxBytes: 64) == .ok)
    #expect(TextCheck.check(fourByte + "😀", maxBytes: 64) == .reject("over 64 bytes"))
    #expect(TextCheck.check(String(repeating: "\u{202E}", count: 100), maxBytes: 64) == .reject("over 64 bytes"), "size before content")
    #expect(TextCheck.check("a", maxBytes: 0) == .reject("over 0 bytes"))
}

// MARK: - FieldValidator: text fields

@Test(arguments: [
    ("Leopold Bloom", Verdict.ok),
    ("Freeman's Journal", .ok),
    ("", .reject("empty")),
    ("p\u{430}ypal", .warning("mixed scripts, looks like “paypal”")),
    ("a\u{202E}b", .reject("bidirectional control character")),
    ("a\nb", .reject("control character")),
])
func validatesNameAndCompany(s: String, verdict: Verdict) {
    for limits in [qr, file] {
        #expect(FieldValidator.name(s, limits: limits) == verdict)
        #expect(FieldValidator.company(s, limits: limits) == verdict)
    }
}

@Test func nameAndCompanyCaps() {
    let n64 = String(repeating: "n", count: 64)
    for limits in [qr, file] {
        #expect(FieldValidator.name(n64, limits: limits) == .ok)
        #expect(FieldValidator.name(n64 + "n", limits: limits) == .reject("over 64 bytes"))
        #expect(FieldValidator.company(n64, limits: limits) == .ok)
        #expect(FieldValidator.company(n64 + "n", limits: limits) == .reject("over 64 bytes"))
    }
    var tight = qr
    tight.name = 8
    #expect(FieldValidator.name("Leopold B", limits: tight) == .reject("over 8 bytes"))
    #expect(FieldValidator.name("Leopold", limits: tight) == .ok)
}

@Test(arguments: [
    ("Pub", Verdict.ok),
    ("", .reject("empty")),
    ("a\tb", .reject("control character")),
    (" Pub", .warning("leading or trailing whitespace, use “Pub”")),
])
func validatesCustomLabel(s: String, verdict: Verdict) {
    #expect(FieldValidator.customLabel(s, limits: qr) == verdict)
    #expect(FieldValidator.customLabel(s, limits: file) == verdict)
}

@Test func customLabelCap() {
    let l24 = String(repeating: "l", count: 24)
    #expect(FieldValidator.customLabel(l24, limits: qr) == .ok)
    #expect(FieldValidator.customLabel(l24 + "l", limits: qr) == .reject("over 24 bytes"))
}

// MARK: - FieldValidator: email and phone

@Test(arguments: [
    ("henry.flower@example.ie", Verdict.ok),
    ("a@b", .ok),
    ("HENRY@EXAMPLE.IE", .ok),
    ("henry+flower@example.ie", .ok),
    ("h_f-1@ex-ample.co.uk", .ok),
    ("a@xn--mnchen-3ya.de", .warning("punycode host label")),
    ("", .reject("empty")),
    ("   ", .reject("not an email address")),
    ("henry", .reject("not an email address")),
    ("@example.ie", .reject("not an email address")),
    ("henry@", .reject("empty host")),
    ("henry@@example.ie", .reject("not an email address")),
    ("a b@c", .reject("not an email address")),
    ("a@b c", .reject("invalid host label")),
    (".a@b", .reject("not an email address")),
    ("a.@b", .reject("not an email address")),
    ("a..b@c", .reject("not an email address")),
    ("a@-b", .reject("invalid host label")),
    ("a@b_c", .reject("invalid host label")),
    ("mailto:a@b", .reject("not an email address")),
    (" a@b", .reject("not an email address")),
    ("a@b ", .reject("invalid host label")),
    ("a@g\u{456}thub.com", .reject("non-ASCII character, looks like “a@github.com”")),
    ("ü@x", .reject("non-ASCII character")),
    ("a\u{0}@b", .reject("control character")),
    ("a\u{200B}@b", .reject("invisible character")),
    ("a@b\u{202E}", .reject("bidirectional control character")),
])
func validatesEmail(s: String, verdict: Verdict) {
    for limits in [qr, file] {
        #expect(FieldValidator.email(s, limits: limits) == verdict)
    }
}

@Test func emailCaps() {
    let local64 = String(repeating: "l", count: 64)
    #expect(FieldValidator.email(local64 + "@b", limits: qr) == .ok)
    #expect(FieldValidator.email(local64 + "l@b", limits: qr) == .reject("not an email address"))
    let label63 = String(repeating: "d", count: 63)
    let exact = local64 + "@" + [label63, label63, String(repeating: "d", count: 61)].joined(separator: ".")
    #expect(exact.utf8.count == 254)
    #expect(FieldValidator.email(exact, limits: qr) == .ok)
    let over = local64 + "@" + [label63, label63, String(repeating: "d", count: 62)].joined(separator: ".")
    #expect(over.utf8.count == 255)
    #expect(FieldValidator.email(over, limits: qr) == .reject("over 254 bytes"))
}

@Test(arguments: [
    ("+353871234567", Verdict.ok),
    ("+12", .ok),
    ("+123456789012345", .ok),
    ("", .reject("empty")),
    ("+1", .reject("not an E.164 number")),
    ("+1234567890123456", .reject("over 16 bytes")),
    ("1234567", .reject("not an E.164 number")),
    ("+0123", .reject("not an E.164 number")),
    ("+1-555", .reject("not an E.164 number")),
    ("+1 555", .reject("not an E.164 number")),
    ("+1(555)1234", .reject("not an E.164 number")),
    ("tel:+1555", .reject("not an E.164 number")),
    ("\u{FF0B}\u{FF11}\u{FF15}\u{FF15}\u{FF15}", .reject("non-ASCII character, looks like “+1555”")),
    ("+1555\u{0}", .reject("control character")),
])
func validatesPhone(s: String, verdict: Verdict) {
    for limits in [qr, file] {
        #expect(FieldValidator.phone(s, limits: limits) == verdict)
    }
}

// MARK: - FieldValidator: website, handle, Signal

@Test(arguments: [
    ("nnix.com", Verdict.ok),
    ("nnix.com/~bloom", .ok),
    ("example.org:8080/x", .ok),
    ("NNIX.COM", .ok),
    ("127.0.0.1", .ok),
    ("example.com/path?q=1#frag", .ok),
    ("xn--mnchen-3ya.de", .warning("punycode host label")),
    ("", .reject("empty")),
    ("https://nnix.com", .reject("scheme in website")),
    ("http://nnix.com", .reject("scheme in website")),
    ("HTTPS://nnix.com", .reject("scheme in website")),
    ("//nnix.com", .reject("scheme in website")),
    ("nnix.com/a://b", .reject("scheme in website")),
    ("user@nnix.com", .reject("userinfo in URL")),
    ("nnix.com:abc", .reject("invalid port")),
    ("nnix .com", .reject("whitespace")),
    ("nnix.com/<x>", .reject("invalid character in URL")),
    ("g\u{456}thub.com", .reject("non-ASCII character, looks like “github.com”")),
    ("münchen.de", .reject("non-ASCII character")),
    ("-nnix.com", .reject("invalid host label")),
    ("nnix.com/\u{202E}", .reject("bidirectional control character")),
])
func validatesWebsite(s: String, verdict: Verdict) {
    for limits in [qr, file] {
        #expect(FieldValidator.website(s, limits: limits) == verdict)
    }
}

@Test func websiteCap() {
    let label63 = String(repeating: "w", count: 63)
    let exact = label63 + "." + String(repeating: "w", count: 60) + ".com"
    #expect(exact.utf8.count == 128)
    #expect(FieldValidator.website(exact, limits: qr) == .ok)
    let over = label63 + "." + String(repeating: "w", count: 61) + ".com"
    #expect(over.utf8.count == 129)
    #expect(FieldValidator.website(over, limits: qr) == .reject("over 128 bytes"))
}

@Test(arguments: [
    ("lbloom", Verdict.ok),
    ("leopold-bloom", .ok),
    ("bloom/coffee", .ok),
    ("bloom@merveilles.town", .ok),
    ("_bloom", .ok),
    ("bloom_", .ok),
    ("a.b", .ok),
    ("Bloom123", .ok),
    ("a", .ok),
    ("bloom@xn--mnchen-3ya.de", .warning("punycode host label")),
    ("", .reject("empty")),
    ("-bloom", .reject("invalid handle")),
    ("bloom-", .reject("invalid handle")),
    ("bloom--x", .reject("invalid handle")),
    ("bloom//x", .reject("invalid handle")),
    ("bloom/", .reject("invalid handle")),
    ("/bloom", .reject("invalid handle")),
    (".bloom", .reject("invalid handle")),
    ("bloom.", .reject("invalid handle")),
    ("bl oom", .reject("invalid handle")),
    ("bloom!", .reject("invalid handle")),
    ("@merveilles.town", .reject("invalid handle")),
    ("https://github.com/lbloom", .reject("invalid handle")),
    ("bloom@x@y", .reject("invalid host label")),
    ("bloom@", .reject("empty host")),
    ("bloom@-x", .reject("invalid host label")),
    ("t\u{43E}rvalds", .reject("non-ASCII character, looks like “torvalds”")),
    ("ünï", .reject("non-ASCII character")),
    ("bloom\u{200B}", .reject("invisible character")),
])
func validatesHandle(s: String, verdict: Verdict) {
    for limits in [qr, file] {
        #expect(FieldValidator.handle(s, limits: limits) == verdict)
    }
}

@Test func handleCap() {
    let h64 = String(repeating: "h", count: 64)
    #expect(FieldValidator.handle(h64, limits: qr) == .ok)
    #expect(FieldValidator.handle(h64 + "h", limits: qr) == .reject("over 64 bytes"))
}

@Test(arguments: [
    ("https://signal.me/#p/+15551234567", Verdict.ok),
    ("https://signal.me/#eu/abcDEF123-_=", .ok),
    ("HTTPS://SIGNAL.ME/#p/+1555", .ok),
    ("http://signal.me/#p/+1555", .reject("not a signal.me link")),
    ("https://signal.me/#p/5551234", .reject("not a signal.me link")),
    ("https://signal.me/#eu/", .reject("not a signal.me link")),
    ("https://signal.me/#eu/ab$c", .reject("not a signal.me link")),
    ("https://example.com/#p/+1555", .reject("not a signal.me link")),
    ("https://signal.me", .reject("not a signal.me link")),
    ("https://signal.me/#", .reject("not a signal.me link")),
    ("https://signal.me/#x/1", .reject("not a signal.me link")),
    ("https://signal.me.evil.com/#p/+1555", .reject("not a signal.me link")),
    ("sgnl://signal.me/#p/+1555", .reject("scheme not allowed: sgnl")),
    ("", .reject("empty")),
    ("https://signal.me/#p/+1555 ", .reject("whitespace")),
    ("https://sign\u{430}l.me/#p/+1555", .reject("non-ASCII character, looks like “https://signal.me/#p/+1555”")),
])
func validatesSignalURL(s: String, verdict: Verdict) {
    for limits in [qr, file] {
        #expect(FieldValidator.signalURL(s, limits: limits) == verdict)
    }
}

@Test func signalURLCap() {
    let prefix = "https://signal.me/#eu/"
    let exact = prefix + String(repeating: "a", count: 128 - prefix.utf8.count)
    #expect(exact.utf8.count == 128)
    #expect(FieldValidator.signalURL(exact, limits: qr) == .ok)
    #expect(FieldValidator.signalURL(exact + "a", limits: qr) == .reject("over 128 bytes"))
}

// MARK: - FieldValidator: custom values

@Test(arguments: [
    ("Davy Byrne's", CustomKind.text, Verdict.ok),
    ("7 Eccles Street\nDublin", .text, .ok),
    ("a\tb", .text, .reject("control character")),
    ("", .text, .reject("empty")),
    ("https://nnix.com", .url, .ok),
    ("http://nnix.com", .url, .warning("not encrypted")),
    ("javascript:alert(1)", .url, .reject("scheme not allowed: javascript")),
    ("nnix.com", .url, .reject("missing scheme")),
    ("", .url, .reject("missing scheme")),
    ("a@b", .email, .ok),
    ("x", .email, .reject("not an email address")),
    ("", .email, .reject("empty")),
    ("+1555", .phone, .ok),
    ("555", .phone, .reject("not an E.164 number")),
    ("+1-555", .phone, .reject("not an E.164 number")),
    ("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGxK5 bloom@host", .key, .ok),
    ("age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3290gq", .key, .ok),
    ("ssh-ed25519 \u{C4}\u{C4}\u{C4}", .key, .reject("non-ASCII character")),
    ("", .key, .reject("empty")),
    ("a\u{0}", .key, .reject("control character")),
    (" key", .key, .warning("leading or trailing whitespace, use “key”")),
])
func validatesCustomValue(s: String, kind: CustomKind, verdict: Verdict) {
    for limits in [qr, file] {
        #expect(FieldValidator.customValue(s, kind: kind, limits: limits) == verdict)
    }
}

@Test func customValueCapsAndKinds() {
    let t128 = String(repeating: "t", count: 128)
    #expect(FieldValidator.customValue(t128, kind: .text, limits: qr) == .ok)
    #expect(FieldValidator.customValue(t128 + "t", kind: .text, limits: qr) == .reject("over 128 bytes"))
    let t1024 = String(repeating: "t", count: 1024)
    #expect(FieldValidator.customValue(t1024, kind: .text, limits: file) == .ok)
    #expect(FieldValidator.customValue(t1024 + "t", kind: .text, limits: file) == .reject("over 1024 bytes"))
    let url = "https://nnix.com/" + String(repeating: "u", count: 128 - 17)
    #expect(url.utf8.count == 128)
    #expect(FieldValidator.customValue(url, kind: .url, limits: qr) == .ok)
    #expect(FieldValidator.customValue(url + "u", kind: .url, limits: qr) == .reject("over 128 bytes"))
    #expect(FieldValidator.customValue(t128 + "t", kind: .key, limits: qr) == .reject("over 128 bytes"))
    var textOnly = qr
    textOnly.customKinds = [.text]
    #expect(FieldValidator.customValue("https://nnix.com", kind: .url, limits: textOnly) == .reject("kind not allowed"))
    #expect(FieldValidator.customValue("+1555", kind: .phone, limits: textOnly) == .reject("kind not allowed"))
    #expect(FieldValidator.customValue("Pub", kind: .text, limits: textOnly) == .ok)
}

// MARK: - FieldValidator: counts and blobs

@Test func countsAndBlobs() {
    #expect(FieldValidator.customCount(8, limits: qr) == .ok)
    #expect(FieldValidator.customCount(9, limits: qr) == .reject("more than 8 custom fields"))
    #expect(FieldValidator.customCount(32, limits: file) == .ok)
    #expect(FieldValidator.customCount(33, limits: file) == .reject("more than 32 custom fields"))
    #expect(FieldValidator.customCount(0, limits: qr) == .ok)

    for count in [0, 1, 16_384, 16_385, Int.max, -1, Int.min] {
        #expect(FieldValidator.photo(byteCount: count, limits: qr) == .reject("no photo in this form"))
        #expect(FieldValidator.gpgKey(byteCount: count, limits: qr) == .reject("no key in this form"))
    }
    #expect(FieldValidator.photo(byteCount: 1, limits: file) == .ok)
    #expect(FieldValidator.photo(byteCount: 16_384, limits: file) == .ok)
    #expect(FieldValidator.photo(byteCount: 16_385, limits: file) == .reject("photo over 16384 bytes"))
    #expect(FieldValidator.photo(byteCount: Int.max, limits: file) == .reject("photo over 16384 bytes"))
    #expect(FieldValidator.photo(byteCount: 0, limits: file) == .reject("empty"))
    #expect(FieldValidator.photo(byteCount: -1, limits: file) == .reject("empty"))
    #expect(FieldValidator.photo(byteCount: Int.min, limits: file) == .reject("empty"))
    #expect(FieldValidator.gpgKey(byteCount: 420, limits: file) == .ok)
    #expect(FieldValidator.gpgKey(byteCount: 24_576, limits: file) == .ok)
    #expect(FieldValidator.gpgKey(byteCount: 24_577, limits: file) == .reject("key over 24576 bytes"))
    #expect(FieldValidator.gpgKey(byteCount: 0, limits: file) == .reject("empty"))

    #expect(FieldValidator.payload(byteCount: 2_953, limits: qr) == .ok)
    #expect(FieldValidator.payload(byteCount: 2_954, limits: qr) == .reject("over 2953 bytes"))
    #expect(FieldValidator.payload(byteCount: 32_768, limits: file) == .ok)
    #expect(FieldValidator.payload(byteCount: 32_769, limits: file) == .reject("over 32768 bytes"))
    #expect(FieldValidator.payload(byteCount: 0, limits: qr) == .ok)

    #expect(FieldValidator.nesting(depth: 3, limits: qr) == .ok)
    #expect(FieldValidator.nesting(depth: 4, limits: qr) == .reject("nested deeper than 3"))
    #expect(FieldValidator.nesting(depth: 0, limits: file) == .ok)
}

// MARK: - Fuzz

private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}

/// Every entry point on one string, with the invariants an accepted value
/// must satisfy. Nothing here may trap.
private func exercise(_ s: String) {
    for allowNewlines in [false, true] {
        let verdict = TextCheck.check(s, maxBytes: 64, allowNewlines: allowNewlines)
        if verdict.isAccepted {
            #expect(s.utf8.count <= 64)
            #expect(TextCheck.problem(in: s, allowNewlines: allowNewlines) == nil)
            #expect(s.unicodeScalars.contains { !$0.properties.isWhitespace })
        }
    }
    _ = Confusables.mixedScripts(in: s)
    if let skeleton = Confusables.looksLikeASCII(s) {
        // Scalars, not `==`: the Kelvin sign is canonically equivalent to K.
        #expect(!skeleton.unicodeScalars.elementsEqual(s.unicodeScalars))
        #expect(Confusables.looksLikeASCII(skeleton) == nil, "a skeleton has no look-alikes left")
        #expect(skeleton.unicodeScalars.count == s.unicodeScalars.count)
    }
    if Confusables.domainVerdict(s).isAccepted {
        #expect(s.utf8.allSatisfy { $0 < 0x80 })
        #expect((1...253).contains(s.utf8.count))
    }
    let url = URLPolicy.verdict(for: s)
    if url.isAccepted {
        #expect(s.utf8.count <= URLPolicy.maxBytes)
        #expect(TextCheck.problem(in: s) == nil)
        #expect(!s.unicodeScalars.contains { $0.properties.isWhitespace })
        #expect(URLPolicy.scheme(of: Array(s.utf8)) != nil)
    }
    if URLPolicy.isTappable(s) {
        #expect(url.isAccepted)
        #expect(URLPolicy.tappableSchemes.contains(URLPolicy.scheme(of: Array(s.utf8)) ?? ""))
    }
    for limits in [qr, file] {
        _ = FieldValidator.name(s, limits: limits)
        _ = FieldValidator.company(s, limits: limits)
        _ = FieldValidator.email(s, limits: limits)
        _ = FieldValidator.phone(s, limits: limits)
        _ = FieldValidator.website(s, limits: limits)
        _ = FieldValidator.handle(s, limits: limits)
        _ = FieldValidator.signalURL(s, limits: limits)
        _ = FieldValidator.customLabel(s, limits: limits)
        for kind in CustomKind.allCases {
            _ = FieldValidator.customValue(s, kind: kind, limits: limits)
        }
        if FieldValidator.phone(s, limits: limits).isAccepted {
            #expect(s.utf8.count <= 16)
            #expect(s.hasPrefix("+"))
        }
        if FieldValidator.handle(s, limits: limits).isAccepted || FieldValidator.email(s, limits: limits).isAccepted {
            #expect(s.utf8.allSatisfy { $0 < 0x80 })
        }
    }
}

@Test func survivesRandomBytes() {
    var rng = SplitMix64(state: 0x5EED)
    for _ in 0..<3000 {
        let count = rng.next(below: 300)
        let bytes = (0..<count).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
        exercise(String(decoding: bytes, as: UTF8.self))
    }
}

/// Strings drawn from scalars the checks care about, so every branch runs.
@Test func survivesRandomScalars() {
    var pool: [UInt32] = Array(UInt32(0x20)...0x7E)
    pool += [0x09, 0x0A, 0x0D, 0x7F, 0x85, 0xA0, 0xAD, 0xE9, 0x131, 0x17F, 0x261, 0x301, 0x34F, 0x378, 0x3BF, 0x3C9]
    pool += [0x410, 0x430, 0x435, 0x43E, 0x456, 0x531, 0x561, 0x61C, 0x180E, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F]
    pool += [0x2024, 0x2028, 0x202E, 0x2044, 0x2060, 0x2066, 0x2069, 0x212A, 0x2215, 0x3000, 0x3002, 0x3042, 0x30A2]
    pool += [0x4E2C, 0xAC00, 0xE000, 0xFB01, 0xFDD0, 0xFE0F, 0xFEFF, 0xFF0B, 0xFF0E, 0xFF41, 0xFFF9, 0xFFFD, 0xFFFE]
    pool += [0x1F600, 0xE0041, 0xF0000, 0x10FFFF]
    let fragments = ["https://", "http://", "mailto:", "tel:+", "acct:", "OPENPGP4FPR:", "signal.me/#p/+", "signal.me/#eu/",
                     "xn--", "@", ".com", "://", "%2", "javascript:", "//", ":443", "?q=", "#"]
    var rng = SplitMix64(state: 0xB100)
    for _ in 0..<3000 {
        var s = ""
        for _ in 0..<rng.next(below: 40) {
            if rng.next(below: 4) == 0 {
                s += fragments[rng.next(below: fragments.count)]
            } else {
                s.unicodeScalars.append(Unicode.Scalar(pool[rng.next(below: pool.count)])!)
            }
        }
        exercise(s)
    }
}

@Test func survivesAnyByteCount() {
    var rng = SplitMix64(state: 0xC0DE)
    var counts = [0, 1, -1, Int.max, Int.min, Int.max - 1, Int.min + 1]
    for _ in 0..<200 { counts.append(Int(truncatingIfNeeded: rng.next())) }
    for count in counts {
        for limits in [qr, file] {
            _ = FieldValidator.photo(byteCount: count, limits: limits)
            _ = FieldValidator.gpgKey(byteCount: count, limits: limits)
            _ = FieldValidator.payload(byteCount: count, limits: limits)
            _ = FieldValidator.customCount(count, limits: limits)
            _ = FieldValidator.nesting(depth: count, limits: limits)
        }
        _ = TextCheck.check("a", maxBytes: count)
    }
}
