import Testing
@testable import HatbandCore

// Adversarial review of Validate. These tables go where the module's own
// tests do not: every hidden scalar at every position, the exact byte
// alphabets the parsers accept, every look-alike in the table, message
// hygiene and determinism under fuzz, and the hostile forms the module once
// let through, kept under "Closed gaps" so they stay refused. A new gap goes
// there wrapped in `withKnownIssue` until it is closed.

private let qr = Limits.qr
private let file = Limits.file

private func u(_ value: UInt32) -> String {
    String(Unicode.Scalar(value)!)
}

private func hex(_ value: UInt32) -> String {
    "U+" + String(value, radix: 16, uppercase: true)
}

private struct Prng {
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

// MARK: - TextCheck: position, precedence, caps

private let hiddenByReason: [(String, [UInt32])] = [
    ("control character",
     Array(UInt32(0x00)...0x09) + [0x0B, 0x0C] + Array(UInt32(0x0D)...0x1F) + [0x7F] + Array(UInt32(0x80)...0x9F)),
    ("bidirectional control character",
     [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]),
    ("invisible character",
     [0x00AD, 0x034F, 0x180E, 0x200B, 0x200C, 0x200D, 0x2028, 0x2029, 0x2060, 0x2061, 0x2064, 0x206A, 0x206F,
      0xFEFF, 0xFFF9, 0xFFFA, 0xFFFB, 0xE0001, 0xE0020, 0xE007F,
      0x115F, 0x1160, 0x3164, 0xFFA0, 0x17B4, 0x180B, 0x180F, 0x1BCA0, 0x1D173, 0x13430, 0x2800]),
    ("unassigned or private-use character",
     [0x0378, 0xE000, 0xF8FF, 0xFDD0, 0xFFFE, 0xFFFF, 0xF0000, 0x10FFFD, 0x10FFFF]),
]

/// A hidden scalar is caught first, last or between letters, under either
/// newline rule. Alone it may instead read "empty" when it is also
/// White_Space, so alone only the rejection is pinned.
@Test(arguments: hiddenByReason)
func rejectsHiddenScalarsAtEveryPosition(reason: String, values: [UInt32]) {
    for value in values {
        let hidden = u(value)
        for allowNewlines in [false, true] {
            for s in [hidden + "ab", "a" + hidden + "b", "ab" + hidden] {
                #expect(TextCheck.check(s, maxBytes: 64, allowNewlines: allowNewlines) == .reject(reason), "\(hex(value)) in \(s.debugDescription)")
            }
            #expect(!TextCheck.check(hidden, maxBytes: 64, allowNewlines: allowNewlines).isAccepted, "\(hex(value))")
            #expect(!TextCheck.check(hidden + hidden, maxBytes: 64, allowNewlines: allowNewlines).isAccepted, "\(hex(value))")
        }
    }
}

/// Blank, then size, then content; warnings only once all three pass. The
/// order decides what the user is told first, so it is pinned.
@Test func rejectionOrder() {
    #expect(TextCheck.check("   ", maxBytes: 1) == .reject("empty"))
    #expect(TextCheck.check(String(repeating: "\u{2003}", count: 70), maxBytes: 64) == .reject("empty"))
    #expect(TextCheck.check("", maxBytes: Int.min) == .reject("empty"))
    #expect(TextCheck.check(" \u{202E} ", maxBytes: 1) == .reject("over 1 bytes"))
    #expect(TextCheck.check("a\u{202E} ", maxBytes: 64) == .reject("bidirectional control character"))
    #expect(TextCheck.check(" a\u{0}", maxBytes: 64) == .reject("control character"))
    #expect(TextCheck.check(" p\u{430}ypal    x ", maxBytes: 64)
        == .warning("mixed scripts, looks like “paypal    x”; leading or trailing whitespace, use “p\u{430}ypal    x”; run of spaces"))
}

@Test func capCountsMixedWidths() {
    let ten = "a\u{E9}\u{20AC}😀"  // 1 + 2 + 3 + 4 bytes
    #expect(ten.utf8.count == 10)
    let exact = String(repeating: ten, count: 6) + "abcd"
    #expect(exact.utf8.count == 64)
    #expect(TextCheck.check(exact, maxBytes: 64) == .ok)
    #expect(TextCheck.check(exact + "a", maxBytes: 64) == .reject("over 64 bytes"))
    // Combining marks count too; a stack of them is accepted up to the cap.
    let stacked = "e" + String(repeating: "\u{301}", count: 31)
    #expect(stacked.utf8.count == 63)
    #expect(TextCheck.check(stacked, maxBytes: 64) == .ok)
    #expect(TextCheck.check(stacked + "\u{301}", maxBytes: 64) == .reject("over 64 bytes"))
    #expect(TextCheck.check(stacked, maxBytes: 63) == .ok)
    #expect(TextCheck.check(stacked, maxBytes: 62) == .reject("over 62 bytes"))
}

@Test func newlineRules() {
    #expect(TextCheck.check("a\n \n \n \n b", maxBytes: 64, allowNewlines: true) == .ok, "newlines break a run of spaces")
    #expect(TextCheck.check("a    \nb", maxBytes: 64, allowNewlines: true) == .warning("run of spaces"))
    #expect(TextCheck.check("\n\n\n\n", maxBytes: 64, allowNewlines: true) == .reject("empty"))
    #expect(TextCheck.check("a\u{85}b", maxBytes: 64, allowNewlines: true) == .reject("control character"), "NEL is not a newline")
    #expect(TextCheck.check("a\u{2028}b", maxBytes: 64, allowNewlines: true) == .reject("invisible character"), "nor is the line separator")
    #expect(TextCheck.check("a\u{0B}b", maxBytes: 64, allowNewlines: true) == .reject("control character"))
    #expect(TextCheck.check("a\u{0C}b", maxBytes: 64, allowNewlines: true) == .reject("control character"))
    #expect(TextCheck.check("a\r\nb", maxBytes: 64, allowNewlines: true) == .reject("control character"))
}

/// Four whitespace scalars of any kind warn; three of one kind and one
/// newline do not.
@Test(arguments: [0x0020, 0x00A0, 0x1680, 0x2000, 0x2007, 0x200A, 0x202F, 0x205F, 0x3000] as [UInt32])
func spaceRunsCountEveryKind(value: UInt32) {
    let space = u(value)
    #expect(TextCheck.check("a" + String(repeating: space, count: 3) + "b", maxBytes: 64) == .ok, "\(hex(value))")
    #expect(TextCheck.check("a" + String(repeating: space, count: 4) + "b", maxBytes: 64) == .warning("run of spaces"), "\(hex(value))")
    #expect(TextCheck.check("a   " + space + "b", maxBytes: 64) == .warning("run of spaces"), "\(hex(value))")
    #expect(TextCheck.check("a   \n" + space + "b", maxBytes: 64, allowNewlines: true) == .ok, "\(hex(value))")
    #expect(TextCheck.check(space + "a", maxBytes: 64) == .warning("leading or trailing whitespace, use “a”"), "\(hex(value))")
    #expect(TextCheck.check(String(repeating: space, count: 5), maxBytes: 64) == .reject("empty"), "\(hex(value))")
}

// MARK: - Confusables: scripts

private let scriptLetters = ["b", "\u{431}", "\u{3B2}", "\u{562}"]  // Latin, Cyrillic, Greek, Armenian; none a look-alike

/// Every pair of the four scripts mixes inside a word and not across one;
/// digits and marks keep the word going.
@Test func everyPairOfConfusableScriptsMixes() {
    for (i, a) in scriptLetters.enumerated() {
        for (j, b) in scriptLetters.enumerated() {
            let mixed = i != j
            #expect(Confusables.mixedScripts(in: a + b) == mixed, "\(a + b)")
            #expect(Confusables.mixedScripts(in: a + "1" + b) == mixed, "\(a + b)")
            #expect(Confusables.mixedScripts(in: a + "\u{301}" + b) == mixed, "\(a + b)")
            #expect(!Confusables.mixedScripts(in: a + " " + b), "\(a + b)")
            #expect(TextCheck.check(a + b, maxBytes: 64) == (mixed ? .warning("mixed scripts") : .ok), "\(a + b)")
        }
    }
}

@Test(arguments: [" ", "\u{A0}", "\u{2009}", "\u{3000}", "-", "'", "\u{2019}", ".", "/", "@", "_", ",", "(", "\u{B7}", "\u{2014}", "😀", "\u{20AC}", "+", "&", "\u{FFFD}"])
func punctuationEndsAWord(separator: String) {
    #expect(!Confusables.mixedScripts(in: "pay" + separator + "\u{43F}\u{430}\u{43B}"), "\(separator.debugDescription)")
}

@Test(arguments: ["1", "\u{661}", "\u{301}", "\u{20DD}", "\u{903}", "\u{2070}", "\u{216B}", "\u{FE0F}", "\u{B2}"])
func marksAndNumbersKeepAWord(joiner: String) {
    #expect(Confusables.mixedScripts(in: "pay" + joiner + "\u{43F}\u{430}\u{43B}"), "\(joiner.debugDescription)")
}

@Test func cjkNeverCountsAsAScript() {
    #expect(!Confusables.mixedScripts(in: "東京\u{431}"))
    #expect(!Confusables.mixedScripts(in: "あ\u{431}"))
    #expect(!Confusables.mixedScripts(in: "한\u{3B2}"))
    #expect(Confusables.mixedScripts(in: "a東京\u{431}"), "CJK hides nothing: the Latin and Cyrillic still meet")
    #expect(Confusables.mixedScripts(in: "aあ\u{431}"))
}

/// A word wholly in one script is never flagged, even when every letter has
/// an ASCII twin: "Сара" is a name. The domain check is where that spelling
/// is refused. Pinned so the choice stays deliberate.
@Test(arguments: [
    "\u{430}\u{440}\u{440}\u{4CF}\u{435}",                      // аррӏе
    "\u{421}\u{430}\u{440}\u{430}",                              // Сара
    "\u{3BF}\u{3BD}",                                            // ον
    "\u{FF47}\u{FF49}\u{FF54}\u{FF48}\u{FF55}\u{FF42}",          // ｇｉｔｈｕｂ
    "\u{261}ithub",                                              // script g
    "m\u{131}crosoft",                                           // dotless i
])
func pureScriptLookalikesPassAsText(s: String) {
    #expect(!Confusables.mixedScripts(in: s))
    #expect(Confusables.looksLikeASCII(s) != nil)
    #expect(TextCheck.check(s, maxBytes: 64) == .ok)
    #expect(!Confusables.domainVerdict(s + ".com").isAccepted)
    #expect(!FieldValidator.handle(s, limits: qr).isAccepted)
}

/// Every look-alike in the table, dropped into a host, is refused with the
/// ASCII host it imitates, by every path that reaches a host. Dropped into a
/// Latin word it is flagged as mixed when its script is not Latin and passes
/// when it is.
@Test func everyLookalikeIsNamed() {
    var letters = 0
    for value in UInt32(0x80)...0x10FFFF {
        guard let scalar = Unicode.Scalar(value), let ascii = Confusables.asciiLookalike(scalar) else { continue }
        let host = "a" + String(scalar) + "b.com"
        let skeleton = "a\(ascii)b.com"
        #expect(Confusables.domainVerdict(host) == .reject("non-ASCII host, looks like “\(skeleton)”"), "\(hex(value))")
        #expect(FieldValidator.website(host, limits: qr) == .reject("non-ASCII character, looks like “\(skeleton)”"), "\(hex(value))")
        #expect(FieldValidator.handle("x@" + host, limits: qr) == .reject("non-ASCII character, looks like “x@\(skeleton)”"), "\(hex(value))")
        #expect(FieldValidator.email("x@" + host, limits: qr) == .reject("non-ASCII character, looks like “x@\(skeleton)”"), "\(hex(value))")
        if !scalar.properties.isWhitespace {
            #expect(URLPolicy.verdict(for: "https://" + host) == .reject("non-ASCII host, looks like “\(skeleton)”"), "\(hex(value))")
            #expect(URLPolicy.verdict(for: "mailto:x@" + host) == .reject("non-ASCII host, looks like “\(skeleton)”"), "\(hex(value))")
            #expect(URLPolicy.verdict(for: "acct:x@" + host) == .reject("non-ASCII host, looks like “\(skeleton)”"), "\(hex(value))")
        }
        guard let script = Confusables.Script.of(scalar) else { continue }
        letters += 1
        let word = "pay" + String(scalar) + "pal"
        if script == .latin {
            #expect(TextCheck.check(word, maxBytes: 64) == .ok, "\(hex(value))")
        } else {
            #expect(TextCheck.check(word, maxBytes: 64) == .warning("mixed scripts, looks like “pay\(ascii)pal”"), "\(hex(value))")
        }
    }
    // 36 Cyrillic, 26 Greek, 6 Armenian, 5 Latin (ℓ is in no script table), 52 fullwidth.
    #expect(letters == 125)
}

// MARK: - Hosts: alphabet and shape

/// Letters, digits and `-` inside a label, `.` between labels, nothing else.
@Test func hostLabelAlphabet() {
    for byte in UInt8(0x20)...0x7E {
        let host = "ab" + String(Unicode.Scalar(byte)) + "cd"
        let expected: Verdict = switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."):
            .ok
        default:
            .reject("invalid host label")
        }
        #expect(Confusables.domainVerdict(host) == expected, "\(host)")
    }
}

@Test func hostLabelCountBoundary() {
    let host253 = Array(repeating: "a", count: 127).joined(separator: ".")
    #expect(host253.utf8.count == 253)
    #expect(Confusables.domainVerdict(host253) == .ok)
    #expect(URLPolicy.verdict(for: "https://" + host253) == .ok)
    let host255 = Array(repeating: "a", count: 128).joined(separator: ".")
    #expect(Confusables.domainVerdict(host255) == .reject("host over 253 bytes"))
    #expect(URLPolicy.verdict(for: "https://" + host255) == .reject("host over 253 bytes"))
    #expect(URLPolicy.verdict(for: "mailto:a@" + host255) == .reject("host over 253 bytes"))
}

@Test(arguments: ["xn--mnchen-3ya", "XN--MNCHEN-3YA", "Xn--Mnchen-3ya", "xN--mnchen-3YA", "a.xn--mnchen-3ya", "xn--mnchen-3ya.a", "xn--9ca", "xn--i-7iq"])
func punycodeLabelsWarnInAnyCase(host: String) {
    #expect(Confusables.domainVerdict(host) == .warning("punycode host label"))
    #expect(URLPolicy.verdict(for: "https://" + host) == .warning("punycode host label"))
}

@Test(arguments: ["xn--", "xn---", "-xn--a", "xn--a-", "x.n--a"])
func punycodeShapesStillNeedValidLabels(host: String) {
    #expect(Confusables.domainVerdict(host) == (host == "x.n--a" ? .ok : .reject("invalid host label")))
}

// MARK: - URLPolicy: alphabets

@Test func authorityAlphabet() {
    for byte in UInt8(0x20)...0x7E {
        let url = "https://ab" + String(Unicode.Scalar(byte)) + "cd"
        let expected: Verdict = switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."):
            .ok
        case UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "#"):
            .ok  // the authority ends; "cd" is a path, query or fragment
        case UInt8(ascii: ":"):
            .reject("invalid port")
        case UInt8(ascii: "@"):
            .reject("userinfo in URL")
        case UInt8(ascii: " "):
            .reject("whitespace")
        default:
            .reject("invalid host label")
        }
        #expect(URLPolicy.verdict(for: url) == expected, "\(url)")
    }
}

/// RFC 3986 unreserved and reserved characters, `%` only as a triplet.
@Test func tailAlphabet() {
    for byte in UInt8(0x20)...0x7E {
        let url = "https://x/" + String(Unicode.Scalar(byte))
        let expected: Verdict = switch byte {
        case UInt8(ascii: " "): .reject("whitespace")
        case UInt8(ascii: "%"): .reject("bad percent-encoding")
        case UInt8(ascii: "\""), UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "\\"), UInt8(ascii: "^"),
             UInt8(ascii: "`"), UInt8(ascii: "{"), UInt8(ascii: "|"), UInt8(ascii: "}"):
            .reject("invalid character in URL")
        default: .ok
        }
        #expect(URLPolicy.verdict(for: url) == expected, "\(url)")
        #expect(URLPolicy.verdict(for: "mailto:a@b?subject=" + String(Unicode.Scalar(byte))) == expected, "\(url)")
    }
}

@Test func percentTripletsNeedTwoHexDigits() {
    for byte in UInt8(0x20)...0x7E {
        let c = String(Unicode.Scalar(byte))
        let hexDigit = ("0"..."9").contains(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
        let expected: Verdict = byte == UInt8(ascii: " ") ? .reject("whitespace") : hexDigit ? .ok : .reject("bad percent-encoding")
        #expect(URLPolicy.verdict(for: "https://x/%4" + c) == expected, "\(c)")
        // `%04` and `%14` are well-formed triplets that decode to controls.
        let decoded: Verdict = c == "0" || c == "1" ? .reject("control character") : expected
        #expect(URLPolicy.verdict(for: "https://x/%" + c + "4") == decoded, "\(c)")
    }
    #expect(URLPolicy.verdict(for: "https://x/%") == .reject("bad percent-encoding"))
    #expect(URLPolicy.verdict(for: "https://x/%4") == .reject("bad percent-encoding"))
    #expect(URLPolicy.verdict(for: "https://x/%%41") == .reject("bad percent-encoding"))
    #expect(URLPolicy.verdict(for: "https://x/%41%") == .reject("bad percent-encoding"))
    #expect(URLPolicy.verdict(for: "https://x/%C3%A9") == .ok)
    #expect(URLPolicy.verdict(for: "https://x/%\u{FF14}1") == .reject("bad percent-encoding"), "fullwidth digits are not hex")
}

// MARK: - URLPolicy: tricks

@Test(arguments: ["vbscript", "about", "chrome", "intent", "itms-services", "shortcuts", "tg", "sms", "facetime", "facetime-audio",
                  "x-apple-data-detectors", "blob", "view-source", "ws", "wss", "ftps", "sftp", "smb", "afp", "nfs", "dict",
                  "gopher", "ldap", "jar", "vnc", "market", "app-settings", "prefs", "mailto2", "http2", "https2", "shttp", "h",
                  "https.", "https-", "https+x", "h2"])
func rejectsEveryOtherScheme(scheme: String) {
    #expect(URLPolicy.verdict(for: scheme + ":x") == .reject("scheme not allowed: " + scheme))
    #expect(URLPolicy.verdict(for: scheme + "://x") == .reject("scheme not allowed: " + scheme))
    #expect(URLPolicy.verdict(for: scheme.uppercased() + ":x") == .reject("scheme not allowed: " + scheme))
    #expect(!URLPolicy.isTappable(scheme + "://x"))
    #expect(FieldValidator.customValue(scheme + "://x", kind: .url, limits: file) == .reject("scheme not allowed: " + scheme))
}

@Test(arguments: [
    ("https\u{FF1A}//example.com", Verdict.reject("missing scheme")),        // fullwidth colon is not a colon
    ("javascript\u{FF1A}alert(1)", .reject("missing scheme")),
    ("javascript&colon;alert(1)", .reject("missing scheme")),
    ("java\u{200B}script:alert(1)", .reject("invisible character")),
    ("\u{FEFF}javascript:alert(1)", .reject("invisible character")),
    ("\u{202E}javascript:alert(1)", .reject("bidirectional control character")),
    ("JaVaScRiPt:alert(1)", .reject("scheme not allowed: javascript")),
    ("javascript:alert(1)//https://example.com", .reject("scheme not allowed: javascript")),
    ("https:\\\\example.com", .reject("malformed URL")),
    ("https:/\\example.com", .reject("malformed URL")),
    ("https:////example.com", .reject("empty host")),                        // a browser would skip the slashes
    ("https://:443", .reject("empty host")),
    ("https://.", .reject("invalid host label")),
    ("https://example.com%00.evil.com", .reject("invalid host label")),
    ("https://example.com%2F@evil.com", .reject("userinfo in URL")),
    ("https://example.com:443@evil.com/", .reject("userinfo in URL")),
    ("https://example.com\\@evil.com", .reject("userinfo in URL")),
    ("https://example.com:8O", .reject("invalid port")),
    ("https://example.com:+443", .reject("invalid port")),
    ("https://example.com:-1", .reject("invalid port")),
    ("https://example.com:\u{661}\u{661}", .reject("invalid port")),       // Arabic-Indic digits
    ("https://example.com:443\u{FF0F}evil", .reject("invalid port")),      // fullwidth slash does not end the authority
    ("https://example\u{FF0E}com", .reject("non-ASCII host, looks like “example.com”")),
    ("https://example.com\u{2024}evil.com", .reject("non-ASCII host, looks like “example.com.evil.com”")),
    ("https://example.com\u{3002}", .reject("non-ASCII host, looks like “example.com.”")),
    ("https://\u{FF45}\u{FF58}\u{FF41}\u{FF4D}\u{FF50}\u{FF4C}\u{FF45}.com", .reject("non-ASCII host, looks like “example.com”")),
    ("https://evil.com#@example.com", .ok),                                   // the fragment is not the authority
    ("https://evil.com/?@example.com", .ok),
    ("https://evil.com/example.com", .ok),
    ("https://example.com/\u{2044}..\u{2044}", .ok),                          // IRI path, by design
    ("https://example.com/%2e%2e/%2e%2e/", .ok),
    ("https://example.com:00443", .ok),
    ("https://EXAMPLE.com:443/A%2f", .ok),
    ("HTTP://EXAMPLE.COM", .warning("not encrypted")),
    ("http://xn--mnchen-3ya.de/", .warning("punycode host label; not encrypted")),
    ("http://xn--pple-43d.com/", .reject("non-ASCII host, looks like “apple.com”")),
])
func judgesTrickyWebForms(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
    #expect(URLPolicy.isTappable(url) == verdict.isAccepted)
}

@Test(arguments: [0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x202F, 0x205F] as [UInt32])
func everyUnicodeSpaceIsWhitespaceInAURL(value: UInt32) {
    let space = u(value)
    #expect(URLPolicy.verdict(for: "https://example.com/a" + space + "b") == .reject("whitespace"), "\(hex(value))")
    #expect(URLPolicy.verdict(for: "https://exam" + space + "ple.com") == .reject("whitespace"), "\(hex(value))")
    #expect(URLPolicy.verdict(for: "mailto:a" + space + "@b") == .reject("whitespace"), "\(hex(value))")
    #expect(URLPolicy.verdict(for: "tel:+1" + space + "555") == .reject("whitespace"), "\(hex(value))")
    #expect(URLPolicy.verdict(for: "acct:a" + space + "@b") == .reject("whitespace"), "\(hex(value))")
    #expect(URLPolicy.verdict(for: space + "https://x") == .reject("whitespace"), "\(hex(value))")
}

@Test(arguments: [
    ("mailto:a@b?", Verdict.ok),
    ("mailto:a@b??", .reject("mailto header not allowed")),                    // a header named `?`
    ("mailto:a@b?subject=", .ok),
    ("mailto:a@b?subject=x&subject=y", .ok),
    ("mailto:A@B?SUBJECT=x", .ok),
    ("mailto:a%40b@c", .reject("not an email address")),                      // decoded, the local part a@b needs quoting
    ("mailto:!#$%25&'*+-=^_`{|}~@c", .ok),                                    // every atext byte but `/`, the `%` as its triplet
    ("mailto:a/b@c", .reject("not an email address")),
    ("MAILTO:", .reject("not an email address")),
    ("mailto:a@b#frag", .reject("invalid host label")),
    ("mailto:a@b?subject=x#frag", .ok),
    ("mailto:a@b:25", .reject("invalid host label")),
    ("mailto:a@b.c\u{2024}d", .reject("non-ASCII host, looks like “b.c.d”")),
    ("mailto:a@b?subject=\u{FF1F}", .ok),                                     // non-ASCII in a header is an IRI
    ("mailto:a@\u{FF42}", .reject("non-ASCII host, looks like “b”")),
    ("mailto:\"a b\"@c", .reject("whitespace")),
    ("mailto:\"ab\"@c", .reject("not an email address")),
    ("mailto:a@b\u{0}", .reject("control character")),
])
func judgesTrickyMailto(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    ("tel:(+1)555", Verdict.ok),                                              // separators anywhere, RFC 3966 phonedigit
    ("tel:+-1555", .ok),
    ("tel:+1.5", .ok),
    ("tel:+1-555-", .ok),
    ("tel:+", .reject("not an E.164 number")),
    ("tel:+-", .reject("not an E.164 number")),
    ("tel:-", .reject("not an E.164 number")),
    ("tel:+1555;", .reject("not an E.164 number")),
    ("tel:+15551234567,123", .reject("not an E.164 number")),
    ("tel:+1555/", .reject("not an E.164 number")),
    ("tel:+1555?x", .reject("not an E.164 number")),
    ("tel:+1555#x", .reject("not an E.164 number")),
    ("tel:%2B1555", .reject("not an E.164 number")),
    ("tel:+1555\u{200B}", .reject("invisible character")),
    ("tel:+1555\u{A0}", .reject("whitespace")),
    ("tel:+\u{661}\u{661}\u{661}", .reject("not an E.164 number")),
])
func judgesTrickyTel(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
    #expect(URLPolicy.isTappable(url) == verdict.isAccepted)
}

@Test(arguments: [
    ("acct:", Verdict.reject("not an acct address")),
    ("acct:@", .reject("not an acct address")),
    ("acct:a@", .reject("empty host")),
    ("acct:a b@c", .reject("whitespace")),
    ("acct:a@b:80", .reject("invalid host label")),
    ("acct:a@b/c", .reject("invalid host label")),
    ("acct:a@b?c", .reject("invalid host label")),
    ("acct://a@b", .reject("not an acct address")),
    ("ACCT:a@b", .ok),
    ("acct:a.b_c@d", .ok),
])
func judgesTrickyAcct(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
    #expect(!URLPolicy.isTappable(url), "acct is display-only")
}

@Test func judgesTrickyFingerprints() {
    let hex40 = String(repeating: "0123456789abcdef", count: 2) + "01234567"
    let hex64 = hex40 + String(repeating: "f", count: 24)
    #expect(hex40.utf8.count == 40)
    #expect(hex64.utf8.count == 64)
    #expect(URLPolicy.verdict(for: "openpgp4fpr:" + hex40) == .ok)
    #expect(URLPolicy.verdict(for: "OpenPGP4Fpr:" + hex64) == .ok)
    let bad = Verdict.reject("not an OpenPGP fingerprint")
    #expect(URLPolicy.verdict(for: "openpgp4fpr:" + hex40 + "?") == bad)
    #expect(URLPolicy.verdict(for: "openpgp4fpr:" + hex40.dropLast() + "g") == bad)
    #expect(URLPolicy.verdict(for: "openpgp4fpr:" + hex40.dropLast(2) + "%4") == bad)
    #expect(URLPolicy.verdict(for: "openpgp4fpr:" + String(repeating: "0", count: 48)) == bad, "neither v4 nor v6")
    #expect(URLPolicy.verdict(for: "openpgp4fpr:0x" + hex40.dropLast(2)) == bad)
    #expect(URLPolicy.verdict(for: "openpgp4fpr:" + String(repeating: "\u{FF10}", count: 40)) == bad)
    #expect(URLPolicy.verdict(for: "openpgp4fpr://" + hex40) == bad)
    #expect(!URLPolicy.isTappable("openpgp4fpr:" + hex40))
}

@Test func capComesBeforeSchemeParsing() {
    #expect(URLPolicy.verdict(for: String(repeating: "j", count: 3000) + ":") == .reject("over 2048 bytes"))
    #expect(URLPolicy.verdict(for: "https://" + String(repeating: "a", count: 2040)) == .reject("host over 253 bytes"))
    #expect(URLPolicy.verdict(for: "https://" + String(repeating: "a", count: 2041)) == .reject("over 2048 bytes"))
}

// MARK: - FieldValidator: hostile forms

@Test(arguments: [
    ("example.com@evil.com", Verdict.reject("userinfo in URL")),
    ("example.com\\@evil.com", .reject("userinfo in URL")),
    ("example.com:443@evil.com", .reject("userinfo in URL")),
    ("evil.com#@example.com", .ok),
    ("evil.com/?@example.com", .ok),
    ("ExAmPlE.CoM/Path", .ok),
    ("example.com:65535", .ok),
    ("example.com:65536", .reject("invalid port")),
    ("example.com:", .reject("invalid port")),
    ("example.com:443:", .reject("invalid port")),
    ("example.com\u{FF0F}evil", .reject("non-ASCII character, looks like “example.com/evil”")),
    ("example\u{2024}com", .reject("non-ASCII character, looks like “example.com”")),
    ("\\\\evil.com", .reject("invalid host label")),
    ("/evil.com", .reject("empty host")),
    ("?evil.com", .reject("empty host")),
    ("#evil.com", .reject("empty host")),
    (":443", .reject("empty host")),
    ("example.com/path?next=https://evil.com", .ok),                            // a URL in the query is not a scheme
    ("localhost:8080", .ok),
    ("localhost:abc", .reject("scheme in website")),
    ("example.com/%2e%2e/", .ok),
    ("example.com/<", .reject("invalid character in URL")),
    ("example.com/%zz", .reject("bad percent-encoding")),
    ("2130706433", .reject("IP address")),
])
func judgesTrickyWebsites(s: String, verdict: Verdict) {
    #expect(FieldValidator.website(s, limits: qr) == verdict)
    #expect(FieldValidator.website(s, limits: file) == verdict)
}

/// A scheme in a website is named as such, even a bare one that the URL
/// grammar would read as host `javascript` with port `alert(1)`.
@Test(arguments: ["javascript:alert(1)", "http:evil.com", "http:/evil.com", "data:text/html,x", "mailto:a@b", "tel:+1555", "file:/etc/passwd",
                  "HTTPS:example.com", "https://x", "//x", "a:b", "wiki:main/page"])
func websiteRefusesAnyScheme(s: String) {
    #expect(FieldValidator.website(s, limits: qr) == .reject("scheme in website"))
    #expect(FieldValidator.website(s, limits: file) == .reject("scheme in website"))
}

@Test func websiteCapIsBytesAndComesBeforeASCII() {
    let a126 = String(repeating: "a", count: 126)
    #expect((a126 + "\u{E9}").utf8.count == 128)
    #expect(FieldValidator.website(a126 + "\u{E9}", limits: qr) == .reject("non-ASCII character"))
    #expect(FieldValidator.website(a126 + "a\u{E9}", limits: qr) == .reject("over 128 bytes"))
    #expect(FieldValidator.website(a126 + "\u{FF41}", limits: qr) == .reject("over 128 bytes"), "three bytes")
}

@Test(arguments: [
    ("_", Verdict.ok),
    ("a.b.c", .ok),
    ("a-b_c.d/e", .ok),
    ("a/b/c/d/e/f/g", .ok),
    ("BLOOM", .ok),
    ("bloom@X.COM", .ok),
    ("bloom@127.0.0.1", .reject("IP address")),
    ("a/../b", .reject("invalid handle")),
    ("a/.b", .reject("invalid handle")),
    ("a//b", .reject("invalid handle")),
    ("a/-b", .reject("invalid handle")),
    ("a\\b", .reject("invalid handle")),
    ("a:b", .reject("invalid handle")),
    ("a?b", .reject("invalid handle")),
    ("a#b", .reject("invalid handle")),
    ("a%20b", .reject("invalid handle")),
    ("a b", .reject("invalid handle")),
    ("\u{661}", .reject("non-ASCII character")),
    ("bl\u{43E}\u{43E}m@merveilles.town", .reject("non-ASCII character, looks like “bloom@merveilles.town”")),
    ("bloom@x.y.", .reject("invalid host label")),
    ("bloom@x@y", .reject("invalid host label")),
    ("bloom@x:80", .reject("invalid host label")),
    ("bloom@x/y", .reject("invalid host label")),
    ("@bloom@x", .warning("leading @, use “bloom@x”")),                          // the pasted Mastodon form
    ("@bloom@xn--mnchen-3ya.de", .warning("leading @, use “bloom@xn--mnchen-3ya.de”; punycode host label")),
    ("@bloom", .reject("invalid handle")),
    ("@@x", .reject("invalid handle")),
    ("@bloom@", .reject("empty host")),
    ("@bl\u{43E}om@x", .reject("non-ASCII character, looks like “@bloom@x”")),
    ("bloom@", .reject("empty host")),
    ("a\u{0}", .reject("control character")),
])
func judgesTrickyHandles(s: String, verdict: Verdict) {
    #expect(FieldValidator.handle(s, limits: qr) == verdict)
    #expect(FieldValidator.handle(s, limits: file) == verdict)
}

@Test func handleCapIsBytesAndComesBeforeASCII() {
    let h62 = String(repeating: "h", count: 62)
    #expect(FieldValidator.handle(h62 + "\u{E9}", limits: qr) == .reject("non-ASCII character"))
    #expect(FieldValidator.handle(h62 + "h\u{E9}", limits: qr) == .reject("over 64 bytes"))
}

@Test(arguments: [
    ("!#$%&'*+-=?^_`{|}~@b", Verdict.ok),                                       // every atext byte but `/`
    ("a/b@c", .reject("not an email address")),
    ("\"a b\"@c", .reject("not an email address")),
    ("\"ab\"@c", .reject("not an email address")),
    ("a@b.", .reject("invalid host label")),
    ("a@.b", .reject("invalid host label")),
    ("a@b..c", .reject("invalid host label")),
    ("a@b:25", .reject("invalid host label")),
    ("a@b/c", .reject("invalid host label")),
    ("a@[127.0.0.1]", .reject("invalid host label")),
    ("a@127.0.0.1", .reject("IP address")),
    ("a@localhost", .ok),
    ("a@b\u{2024}c", .reject("non-ASCII character, looks like “a@b.c”")),
    ("\u{FF41}@b", .reject("non-ASCII character, looks like “a@b”")),
    ("a\u{FF20}b", .reject("non-ASCII character, looks like “a@b”")),           // fullwidth @ is not an @
    ("a@b\u{FEFF}", .reject("invisible character")),
    ("a\n@b", .reject("control character")),
    ("A@B.C", .ok),
])
func judgesTrickyEmails(s: String, verdict: Verdict) {
    #expect(FieldValidator.email(s, limits: qr) == verdict)
    #expect(FieldValidator.email(s, limits: file) == verdict)
}

@Test(arguments: [
    ("+155512345678901", Verdict.ok),                                           // 15 digits, the E.164 maximum
    ("+1555123456789012", .reject("over 16 bytes")),
    ("+0", .reject("not an E.164 number")),
    ("+00", .reject("not an E.164 number")),
    ("0015551234567", .reject("not an E.164 number")),
    ("+1\u{200B}555", .reject("invisible character")),
    ("+1\u{A0}555", .reject("non-ASCII character")),
    ("+1\u{FF15}55", .reject("non-ASCII character, looks like “+1555”")),
    ("\u{2212}1555", .reject("non-ASCII character, looks like “-1555”")),      // minus sign is not a plus
    ("+1555\r", .reject("control character")),
    (" +1555", .reject("not an E.164 number")),
    ("+1555 ", .reject("not an E.164 number")),
    ("++1555", .reject("not an E.164 number")),
    ("+", .reject("not an E.164 number")),
])
func judgesTrickyPhones(s: String, verdict: Verdict) {
    #expect(FieldValidator.phone(s, limits: qr) == verdict)
    #expect(FieldValidator.phone(s, limits: file) == verdict)
}

@Test(arguments: [
    ("https://signal.me/#p/+1-555", Verdict.reject("not a signal.me link")),   // strict E.164 in the fragment
    ("https://signal.me/#p/+1555#x", .reject("not a signal.me link")),
    ("https://signal.me/#p/+1555/", .reject("not a signal.me link")),
    ("https://signal.me/#p/+1555?x", .reject("not a signal.me link")),
    ("https://signal.me/#P/+1555", .reject("not a signal.me link")),
    ("https://signal.me/#eu/a", .ok),
    ("https://signal.me/#eu/abc?x", .reject("not a signal.me link")),
    ("https://signal.me/#eu/abc/d", .reject("not a signal.me link")),
    ("https://signal.me/#eu/abc%20", .reject("not a signal.me link")),
    ("https://signal.me/#EU/abc", .reject("not a signal.me link")),
    ("https://signal.me/?#p/+1555", .reject("not a signal.me link")),
    ("https://signal.me//#p/+1555", .reject("not a signal.me link")),
    ("https://signal.me:443/#p/+1555", .reject("not a signal.me link")),
    ("https://signal.me/#p/+1555", .ok),
    ("https://signal.me/#eu/ab\u{FF41}", .reject("non-ASCII character, looks like “https://signal.me/#eu/aba”")),
    ("https://signal.me/#p/+1555\u{200B}", .reject("invisible character")),
    ("https://user@signal.me/#p/+1555", .reject("userinfo in URL")),
])
func judgesTrickySignalLinks(s: String, verdict: Verdict) {
    #expect(FieldValidator.signalURL(s, limits: qr) == verdict)
    #expect(FieldValidator.signalURL(s, limits: file) == verdict)
}

@Test(arguments: [
    ("https://x.com/Stra\u{DF}e", CustomKind.url, Verdict.ok),                  // IRI path
    ("https://stra\u{DF}e.de", .url, .reject("non-ASCII host")),
    ("\u{FEFF}https://x.com", .url, .reject("invisible character")),
    ("HTTPS://X.COM", .url, .ok),
    (" https://x.com", .url, .reject("whitespace")),
    ("-----BEGIN PGP PUBLIC KEY BLOCK-----\nmQ", .key, .reject("control character")),  // one line only
    ("ssh-ed25519 AAAA\r", .key, .reject("control character")),
    ("ssh-ed25519\tAAAA", .key, .reject("control character")),
    ("ssh-ed25519 AAAA bloom@host", .key, .ok),
    ("ssh-ed25519 AAAA\u{200B}", .key, .reject("invisible character")),
    ("\u{FF33}SH-ed25519 AAAA", .key, .reject("non-ASCII character")),
    ("a\r\nb", .text, .reject("control character")),
    ("a\n\n\n\nb", .text, .ok),
    ("a    b", .text, .warning("run of spaces")),
    ("a\u{2028}b", .text, .reject("invisible character")),
    ("p\u{430}ypal", .text, .warning("mixed scripts, looks like “paypal”")),
    ("a@b", .email, .ok),
    ("a@b\n", .email, .reject("control character")),
])
func judgesTrickyCustomValues(s: String, kind: CustomKind, verdict: Verdict) {
    #expect(FieldValidator.customValue(s, kind: kind, limits: qr) == verdict)
    #expect(FieldValidator.customValue(s, kind: kind, limits: file) == verdict)
}

/// A custom email or phone is capped by the custom value, not by the field
/// of the same kind: the QR cap is 128 either way, and a 16-digit phone is
/// refused as a number, not for its length.
@Test func customValuesUseTheCustomCap() {
    let local64 = String(repeating: "l", count: 64)
    let email130 = local64 + "@" + String(repeating: "d", count: 63) + ".d"
    #expect(email130.utf8.count == 130)
    #expect(FieldValidator.customValue(email130, kind: .email, limits: qr) == .reject("over 128 bytes"))
    #expect(FieldValidator.customValue(email130, kind: .email, limits: file) == .ok)
    #expect(FieldValidator.customValue("+1234567890123456", kind: .phone, limits: qr) == .reject("not an E.164 number"))
    #expect(FieldValidator.phone("+1234567890123456", limits: qr) == .reject("over 16 bytes"))
    let url129 = "https://x.com/" + String(repeating: "u", count: 115)
    #expect(url129.utf8.count == 129)
    #expect(FieldValidator.customValue(url129, kind: .url, limits: qr) == .reject("over 128 bytes"))
    #expect(FieldValidator.customValue(url129, kind: .url, limits: file) == .ok)
}

@Test func customLabelCapCountsCJKBytes() {
    let eight = String(repeating: "字", count: 8)
    #expect(eight.utf8.count == 24)
    #expect(FieldValidator.customLabel(eight, limits: qr) == .ok)
    #expect(FieldValidator.customLabel(eight + "字", limits: qr) == .reject("over 24 bytes"))
    #expect(FieldValidator.customLabel("p\u{430}ypal", limits: qr) == .warning("mixed scripts, looks like “paypal”"))
}

@Test func disallowedKindIsRefusedBeforeAnythingElse() {
    var none = qr
    none.customKinds = []
    for kind in CustomKind.allCases {
        #expect(FieldValidator.customValue("", kind: kind, limits: none) == .reject("kind not allowed"))
        #expect(FieldValidator.customValue("\u{202E}", kind: kind, limits: none) == .reject("kind not allowed"))
    }
    var keysOnly = file
    keysOnly.customKinds = [.key]
    #expect(FieldValidator.customValue("Pub", kind: .text, limits: keysOnly) == .reject("kind not allowed"))
    #expect(FieldValidator.customValue("ssh-ed25519 AAAA", kind: .key, limits: keysOnly) == .ok)
}

@Test func blobsRejectNonsenseCounts() {
    for count in [0, -1, Int.min] {
        #expect(FieldValidator.photo(byteCount: count, limits: file) == .reject("empty"))
        #expect(FieldValidator.gpgKey(byteCount: count, limits: file) == .reject("empty"))
    }
    var tiny = file
    tiny.photoBytes = 1
    tiny.gpgKeyBytes = 1
    #expect(FieldValidator.photo(byteCount: 1, limits: tiny) == .ok)
    #expect(FieldValidator.photo(byteCount: 2, limits: tiny) == .reject("photo over 1 bytes"))
    #expect(FieldValidator.gpgKey(byteCount: 2, limits: tiny) == .reject("key over 1 bytes"))
}

// MARK: - Closed gaps

/// Default_Ignorable_Code_Point scalars outside the old hand-kept list
/// render as nothing and are refused: the Hangul fillers (Lo), Khmer and
/// Mongolian selectors (Mn), the musical and shorthand format controls (Cf),
/// and the hieroglyph controls, Cf but not ignorable.
@Test(arguments: [0x115F, 0x1160, 0x3164, 0xFFA0, 0x17B4, 0x17B5, 0x180B, 0x180F, 0x1BCA0, 0x1BCA3, 0x1D173, 0x1D17A, 0x13430] as [UInt32])
func rejectsDefaultIgnorables(value: UInt32) {
    #expect(TextCheck.check("Jo" + u(value) + "hn", maxBytes: 64) == .reject("invisible character"), "\(hex(value))")
    #expect(URLPolicy.verdict(for: "https://example.com/" + u(value)) == .reject("invisible character"), "\(hex(value))")
    #expect(FieldValidator.handle("jo" + u(value) + "hn", limits: qr) == .reject("invisible character"), "\(hex(value))")
}

/// The three invisibles with a job are allowed only where they do it. A
/// variation selector follows a base; a ZWJ joins two pictographs, skin
/// tone and presentation selector included; a ZWNJ parts two Arabic
/// letters, a vowel mark on the first included.
@Test(arguments: [
    ("🏳\u{FE0F}\u{200D}🌈", Verdict.ok),
    ("👨🏽\u{200D}👩🏽\u{200D}👧🏽\u{200D}👦🏽", .ok),
    ("👁\u{FE0F}\u{200D}🗨\u{FE0F}", .ok),
    ("\u{A9}\u{200D}\u{2122}", .ok),                                             // pictographs, if odd ones
    ("\u{645}\u{6CC}\u{200C}\u{62E}\u{648}\u{627}\u{647}\u{645}", .ok),
    ("\u{645}\u{650}\u{200C}\u{62E}", .ok),
    ("\u{6A9}\u{200C}\u{6C1}", .ok),                                             // Urdu letters
    ("\u{FB56}\u{200C}\u{FE8D}", .ok),                                           // presentation forms
    ("a\u{200D}😀", .reject("invisible character")),
    ("😀\u{200D}\u{200D}😀", .reject("invisible character")),
    ("😀\u{FE0F}\u{200D}", .reject("invisible character")),
    ("😀\u{200D}\u{FE0F}😀", .reject("invisible character")),
    ("1\u{200D}2", .reject("invisible character")),                              // ASCII emoji are not pictographs
    ("#\u{200D}#", .reject("invisible character")),
    ("😀\u{200C}😀", .reject("invisible character")),                            // the joiners are not interchangeable
    ("\u{645}\u{200D}\u{62E}", .reject("invisible character")),
    ("\u{645}\u{200C}\u{200C}\u{62E}", .reject("invisible character")),
    ("\u{645}\u{200C} \u{62E}", .reject("invisible character")),
    ("\u{660}\u{200C}\u{62E}", .reject("invisible character")),                  // an Arabic digit is not a letter
    ("\u{5D0}\u{200C}\u{5D1}", .reject("invisible character")),                  // Hebrew has no such rule
    ("\u{915}\u{200D}\u{937}", .reject("invisible character")),                  // nor Devanagari, by design
    ("\u{200D}", .reject("invisible character")),
    ("a\u{3164}\u{FE0F}", .reject("invisible character")),                       // a filler is no base
    ("a\u{FE0F}\u{E0100}", .reject("invisible character")),
])
func joinersAndSelectorsInContext(s: String, verdict: Verdict) {
    #expect(TextCheck.check(s, maxBytes: 64) == verdict)
    #expect(FieldValidator.customValue(s, kind: .text, limits: file) == verdict)
    let inPath = URLPolicy.verdict(for: "https://example.com/" + s)
    #expect(inPath == verdict, "in a path")
    #expect(URLPolicy.verdict(for: "https://example.com/" + percentEncoded(s)) == verdict, "in a path, percent-encoded")
}

private func percentEncoded(_ s: String) -> String {
    s.utf8.map { byte in
        let hex = String(byte, radix: 16, uppercase: true)
        return "%" + (hex.count == 1 ? "0" + hex : hex)
    }.joined()
}

/// A value with no visible base character is empty to the eye: marks alone
/// read "empty", and a selector or filler alone, or on a mark, is the
/// invisible it is.
@Test(arguments: [
    ("\u{FE0F}", Verdict.reject("invisible character")),
    ("\u{E0100}", .reject("invisible character")),
    (String(repeating: "\u{FE0F}", count: 20), .reject("invisible character")),
    ("\u{3164}", .reject("invisible character")),
    ("\u{301}", .reject("empty")),
    ("\u{20DD}\u{20DD}", .reject("empty")),
    ("\u{301}\u{FE0F}", .reject("invisible character")),
    (" \u{94B} ", .reject("empty")),                                              // a spacing mark
])
func rejectsValuesWithNoVisibleBase(s: String, verdict: Verdict) {
    #expect(FieldValidator.name(s, limits: qr) == verdict)
    #expect(FieldValidator.customValue(s, kind: .text, limits: file) == verdict)
}

/// Numeric and hex host forms a browser resolves to an address, and an
/// all-digit last label (never a public suffix, RFC 3696 §2), are refused
/// as addresses by every field that takes a host.
@Test(arguments: ["2130706433", "0x7f000001", "0177.0.0.1", "256.256.256.256", "example.123", "127.0.0.1"])
func rejectsObfuscatedHosts(host: String) {
    #expect(URLPolicy.verdict(for: "https://" + host) == .reject("IP address"))
    #expect(!URLPolicy.isTappable("https://" + host))
    #expect(FieldValidator.website(host, limits: qr) == .reject("IP address"))
    #expect(FieldValidator.website(host + "/path", limits: qr) == .reject("IP address"))
    #expect(FieldValidator.email("a@" + host, limits: qr) == .reject("IP address"))
    #expect(FieldValidator.handle("a@" + host, limits: qr) == .reject("IP address"))
    #expect(FieldValidator.customValue("http://" + host, kind: .url, limits: qr) == .reject("IP address"))
}

/// RFC 6068 §3: `to`, `cc` and `bcc` header fields add recipients, so a
/// link that reads as one address could prefill another. Only `subject` and
/// `body` pass, in any case and any encoding; nothing else is a header.
@Test(arguments: ["mailto:a@b?bcc=spy@evil.com", "mailto:a@b?to=spy@evil.com", "mailto:a@b?cc=spy@evil.com&subject=hi", "mailto:a@b?subject=x&BCC=spy@evil.com",
                  "mailto:a@b?%62cc=x", "mailto:a@b?subject=x&=y", "mailto:a@b?in-reply-to=x", "mailto:a@b?subject%3Dx", "mailto:a@b?#bcc=x", "mailto:a@b?subject=x#&bcc=y"])
func rejectsMailtoRecipientHeaders(url: String) {
    #expect(URLPolicy.verdict(for: url) == .reject("mailto header not allowed"))
    #expect(!URLPolicy.isTappable(url))
}

@Test(arguments: ["mailto:a@b?subject=x", "mailto:a@b?body=x", "mailto:a@b?Subject=x&BODY=y", "mailto:a@b?%53ubject=x", "mailto:a@b?subject=a=b&",
                  "mailto:a@b?&&subject=x", "mailto:a@b?subject=x#frag", "mailto:a@b?body=to=x"])
func allowsMailtoSubjectAndBody(url: String) {
    #expect(URLPolicy.verdict(for: url) == .ok)
}

/// Percent-encoded control, bidi and invisible bytes are valid RFC 3986;
/// decoded, they get the scan the raw text gets.
@Test(arguments: [
    ("https://example.com/%00", "control character"),
    ("https://example.com/%0D%0A", "control character"),
    ("https://example.com/%1B%5B31m", "control character"),
    ("https://example.com/%E2%80%AEexe.txt", "bidirectional control character"),
    ("https://example.com/?q=%E2%80%8B", "invisible character"),
    ("https://example.com/#%EF%BB%BF", "invisible character"),
    ("https://example.com/%E3%85%A4", "invisible character"),                  // Hangul filler
    ("https://example.com/%F3%A0%80%81", "invisible character"),               // tag block
    ("https://example.com/%E2%80%8D", "invisible character"),                  // a ZWJ with nothing to join
    ("https://example.com/%EF%B8%8F%EF%B8%8F", "invisible character"),         // a selector on a selector
    ("https://example.com/%EE%80%80", "unassigned or private-use character"),
    ("mailto:a@b?subject=%0D%0Abcc:x", "control character"),
    ("mailto:a@b?body=%E2%80%AE", "bidirectional control character"),
    ("mailto:a@b?body=%0A", "control character"),
])
func rejectsPercentEncodedControls(url: String, reason: String) {
    #expect(URLPolicy.verdict(for: url) == .reject(reason))
}

/// Encoded text that is fine raw is fine encoded: UTF-8, a space, an emoji
/// with its selector, and bytes that are not UTF-8 at all (they decode to
/// U+FFFD, a plain symbol).
@Test(arguments: ["https://example.com/%C3%A9", "https://example.com/%FF%FE", "https://example.com/%20%2F%25", "https://example.com/%7e/%2e%2e",
                  "https://example.com/%E2%9C%88%EF%B8%8F", "mailto:a@b?subject=%F0%9F%98%80&body=%20x"])
func acceptsPercentEncodedText(url: String) {
    #expect(URLPolicy.verdict(for: url) == .ok)
}

/// `xn--pple-43d.com` is `аpple.com`: the label is decoded (RFC 3492) and
/// refused the way the raw form is, by every path that reaches a host.
@Test func punycodeHomographIsNotTappable() {
    let apple = Verdict.reject("non-ASCII host, looks like “apple.com”")
    #expect(!URLPolicy.isTappable("https://xn--pple-43d.com"))
    #expect(URLPolicy.verdict(for: "https://xn--pple-43d.com") == apple)
    #expect(URLPolicy.verdict(for: "https://\u{430}pple.com") == apple)
    #expect(URLPolicy.verdict(for: "mailto:a@xn--80ak6aa92e.com") == apple)
    #expect(URLPolicy.verdict(for: "acct:a@xn--80ak6aa92e.com") == apple)
    #expect(FieldValidator.website("xn--80ak6aa92e.com/path", limits: qr) == apple)
    #expect(FieldValidator.email("a@xn--pple-43d.com", limits: qr) == apple)
    #expect(FieldValidator.handle("a@xn--pple-43d.com", limits: qr) == apple)
    #expect(URLPolicy.isTappable("https://xn--mnchen-3ya.de"))
}

// MARK: - Properties under fuzz

/// Every message a verdict carries is shown to the user. It must be clean
/// text (nothing hidden, no control but a newline the input was allowed),
/// bounded, and the same on every call.
private func messages(for s: String) -> [(String, allowNewlines: Bool)] {
    var out: [(String, allowNewlines: Bool)] = []
    func add(_ verdict: Verdict, allowNewlines: Bool = false) {
        switch verdict {
        case .ok: break
        case .warning(let m), .reject(let m): out.append((m, allowNewlines))
        }
    }
    add(TextCheck.check(s, maxBytes: 64))
    add(TextCheck.check(s, maxBytes: 64, allowNewlines: true), allowNewlines: true)
    add(Confusables.domainVerdict(s))
    add(URLPolicy.verdict(for: s))
    for limits in [qr, file] {
        add(FieldValidator.name(s, limits: limits))
        add(FieldValidator.company(s, limits: limits))
        add(FieldValidator.email(s, limits: limits))
        add(FieldValidator.phone(s, limits: limits))
        add(FieldValidator.website(s, limits: limits))
        add(FieldValidator.handle(s, limits: limits))
        add(FieldValidator.signalURL(s, limits: limits))
        add(FieldValidator.customLabel(s, limits: limits))
        for kind in CustomKind.allCases {
            add(FieldValidator.customValue(s, kind: kind, limits: limits), allowNewlines: kind == .text)
        }
    }
    return out
}

private func checkMessages(for s: String) {
    let first = messages(for: s)
    let second = messages(for: s)
    #expect(first.map(\.0) == second.map(\.0), "deterministic")
    for (message, allowNewlines) in first {
        #expect(!message.isEmpty)
        #expect(message.utf8.count <= 1200, "\(message.utf8.count) bytes")
        #expect(TextCheck.problem(in: message, allowNewlines: allowNewlines) == nil, "\(message.debugDescription)")
    }
}

/// Invariants of an accepted value, beyond what its check promises.
private func checkAccepted(_ s: String) {
    if TextCheck.check(s, maxBytes: 64) == .ok {
        #expect(!Confusables.mixedScripts(in: s))
        #expect(!s.unicodeScalars.first!.properties.isWhitespace)
        #expect(!s.unicodeScalars.last!.properties.isWhitespace)
    }
    let bytes = Array(s.utf8)
    if let scheme = URLPolicy.scheme(of: bytes), URLPolicy.verdict(for: s).isAccepted {
        let rest = bytes[(scheme.utf8.count + 1)...]
        switch scheme {
        case "https", "http":
            let authority = rest.dropFirst(2).prefix { !"/?#".utf8.contains($0) }
            #expect(!authority.contains(UInt8(ascii: "@")))
            #expect(authority.allSatisfy { $0 < 0x80 })
            #expect(!authority.isEmpty)
        case "mailto", "acct":
            let address = rest.prefix { $0 != UInt8(ascii: "?") }
            #expect(address.filter { $0 == UInt8(ascii: "@") }.count == 1)
            #expect(address.allSatisfy { $0 < 0x80 })
        case "tel":
            #expect(rest.first == UInt8(ascii: "+"))
            #expect(rest.allSatisfy { $0 < 0x80 })
        case "openpgp4fpr":
            #expect(rest.count == 40 || rest.count == 64)
        default:
            Issue.record("accepted scheme \(scheme)")
        }
    }
    for limits in [qr, file] {
        if FieldValidator.website(s, limits: limits).isAccepted {
            #expect(!s.utf8.contains(UInt8(ascii: "@")))
            #expect(URLPolicy.isTappable("https://" + s))
        }
        if FieldValidator.signalURL(s, limits: limits).isAccepted {
            #expect(s.lowercased().hasPrefix("https://signal.me/#"))
            #expect(URLPolicy.isTappable(s))
        }
        if FieldValidator.email(s, limits: limits).isAccepted {
            #expect(URLPolicy.isTappable("mailto:" + s))
        }
        if FieldValidator.phone(s, limits: limits).isAccepted {
            #expect(URLPolicy.isTappable("tel:" + s))
        }
    }
}

private let hostilePool: [UInt32] = Array(UInt32(0x20)...0x7E) + [
    0x00, 0x09, 0x0A, 0x0D, 0x1B, 0x7F, 0x85, 0xA0, 0xAD, 0xE9, 0x131, 0x261, 0x301, 0x34F, 0x378, 0x3BF, 0x430, 0x435,
    0x43E, 0x456, 0x4CF, 0x561, 0x61C, 0x661, 0x115F, 0x180E, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2009, 0x2024, 0x2028,
    0x202E, 0x2044, 0x2060, 0x2066, 0x2069, 0x20DD, 0x2126, 0x212A, 0x2215, 0x2800, 0x3000, 0x3002, 0x3042, 0x3164, 0x4E2C,
    0xAC00, 0xE000, 0xFB01, 0xFDD0, 0xFE0F, 0xFEFF, 0xFF0B, 0xFF0E, 0xFF1A, 0xFF20, 0xFF41, 0xFFA0, 0xFFF9, 0xFFFD, 0xFFFE,
    0x1D173, 0x1F600, 0xE0041, 0xE0100, 0xF0000, 0x10FFFF,
]

private let hostileFragments = [
    "https://", "http://", "HTTPS://", "mailto:", "tel:+", "acct:", "OPENPGP4FPR:", "javascript:", "signal.me/#p/+", "signal.me/#eu/",
    "xn--", "@", ".com", "://", "%2", "%00", "//", "\\\\", ":443", ":0", "?q=", "#", "?bcc=", "127.0.0.1", "2130706433", "..", "/../",
    "example.com", "user:pw@", "[::1]", "+1555", "ssh-ed25519 ", "pay", "pal",
]

@Test func messagesAreCleanUnderRandomBytes() {
    var rng = Prng(state: 0xADBE)
    for _ in 0..<2000 {
        let count = rng.next(below: 200)
        let bytes = (0..<count).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
        let s = String(decoding: bytes, as: UTF8.self)
        checkMessages(for: s)
        checkAccepted(s)
    }
}

@Test func messagesAreCleanUnderHostileScalars() {
    var rng = Prng(state: 0xF00D)
    for _ in 0..<3000 {
        var s = ""
        for _ in 0..<rng.next(below: 40) {
            if rng.next(below: 3) == 0 {
                s += hostileFragments[rng.next(below: hostileFragments.count)]
            } else {
                s.unicodeScalars.append(Unicode.Scalar(hostilePool[rng.next(below: hostilePool.count)])!)
            }
        }
        checkMessages(for: s)
        checkAccepted(s)
    }
}

/// Oversized input is refused without being read in full where a cap comes
/// first, and never traps where it does not.
@Test func hugeInputsDoNotTrap() {
    let spaces = String(repeating: " ", count: 1_000_000)
    #expect(TextCheck.check(spaces, maxBytes: 64) == .reject("empty"))
    #expect(TextCheck.check(spaces + "a", maxBytes: 64) == .reject("over 64 bytes"))
    #expect(URLPolicy.verdict(for: "https://" + spaces) == .reject("over 2048 bytes"))
    #expect(Confusables.domainVerdict(spaces) == .reject("host over 253 bytes"))
    #expect(!Confusables.mixedScripts(in: spaces))
    #expect(Confusables.looksLikeASCII(spaces) == nil)
    let marks = "a" + String(repeating: "\u{301}", count: 500_000)
    #expect(TextCheck.check(marks, maxBytes: Int.max) == .ok)
    #expect(FieldValidator.customValue(marks, kind: .text, limits: file) == .reject("over 1024 bytes"))
}
