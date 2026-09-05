import Testing
@testable import HatbandCore

// Review of the Validate hardening in 641f8b3. The RFC 3492 decoder is
// checked against Python's `punycode` codec, and the gaps the review found
// are pinned closed: an honest Cyrillic or Greek IDN keeps its warning, a
// percent-encoded address is judged as what it decodes to, and a variation
// selector needs a base it has a sequence with.

private let qr = Limits.qr

// MARK: - Punycode, against Python's codec

/// Random labels over Cyrillic, Greek, Arabic, Hebrew, kana, Han, Hangul,
/// emoji, ASCII and edge scalars (U+0080, U+200D, U+E000, U+10FFFF), each
/// encoded by Python's `punycode` codec.
@Test(arguments: [
    ("q39akczdvak7kd8w", "\u{AC3F}\u{AC7D}\u{AC02}\u{AC5D}\u{AC44}\u{AC46}\u{AC22}\u{AC5C}"),
    ("g1acpj1a1c55qcabi9a5b7ay5ecfb0jtb", "\u{5EA}\u{5D0}\u{440}\u{5D8}\u{437}\u{5E1}\u{5D0}\u{5D1}\u{5E1}\u{438}\u{5DC}\u{5D0}\u{5D4}\u{44D}\u{5E1}\u{5DA}\u{5E1}\u{445}\u{43D}\u{5E7}"),
    ("l1ab9305aoca3d73495a4ead", "\u{43D}\u{1F62F}\u{43C}\u{3069}\u{3090}\u{1F62F}\u{307E}\u{1F616}"),
    ("e1avz1392o3iawe", "\u{AC51}\u{AC68}\u{AC13}\u{440}\u{435}\u{448}"),
    ("nxah3bdr097a5bn9f", "\u{636}\u{3B6}\u{641}\u{3C4}\u{3C3}\u{62C}\u{3B2}\u{637}\u{3C7}"),
    ("OTzIsljPvIs-", "OTzIsljPvIs"),
    ("0y0c", "\u{E000}"),
    ("fCe47H4yZGUs-tyi1b4g8f91ffdwelc8d3cxc2dte", "f\u{44B}C\u{3C6}\u{43C}e47H\u{430}\u{3BD}\u{442}4\u{436}y\u{3B6}Z\u{43C}\u{447}G\u{444}\u{43F}U\u{43C}s\u{3B3}"),
    ("ngbbnkcfqb8a3a2cxcasfemfjs", "\u{634}\u{63B}\u{645}\u{638}\u{629}\u{648}\u{634}\u{647}\u{630}\u{63F}\u{645}\u{646}\u{628}\u{62D}\u{631}\u{643}\u{645}\u{646}\u{643}\u{630}"),
    ("zcatx9b21wsa7b9aaxcl7025grba91352dwejz", "\u{3BF}\u{200D}\u{3C7}\u{3C6}\u{F1}\u{E9}\u{FC}\u{3C3}\u{3C3}\u{DF}\u{3B5}\u{FFFD}\u{3B8}\u{2010}\u{3C5}\u{1F1FA}"),
    ("6db5bzn7b3bx592pmgakktp", "\u{640}\u{5E7}\u{649}\u{AC77}\u{AC23}\u{AC46}\u{5D2}\u{AC03}\u{630}"),
    ("b1ag2er3hmcln", "\u{627}\u{432}\u{44C}\u{63B}\u{639}\u{637}\u{435}"),
    ("g1a3b11h", "\u{44B}\u{639}\u{437}"),
    ("rgb7208a2m18r", "\u{4E45}\u{62C}\u{10FFFF}"),
    ("5dbqac9bdn4a00esd", "\u{5E6}\u{636}\u{5E4}\u{5D1}\u{5DA}\u{5E3}\u{641}\u{5D9}\u{5D9}\u{5E9}"),
    ("e7x-8i33bqdoeoa", "e\u{1F60D}\u{1F637}\u{1F639}7\u{1F625}x"),
    ("58jbk2cwbk5b8j", "\u{3089}\u{3076}\u{3070}\u{3057}\u{306E}\u{3056}\u{305A}\u{3066}"),
    ("j1aeh4cu1390bqba8d6c", "\u{1F623}\u{43F}\u{1F61A}\u{1F606}\u{43A}\u{43C}\u{44B}\u{1F60E}"),
    ("tda06xgu456b", "\u{10FFFF}\u{FC}\u{627}"),
    ("1ug8558fpupg10a", "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"),
])
func decodesWhatPythonEncodes(encoded: String, decoded: String) {
    #expect(Punycode.decode(Array(encoded.utf8)) == decoded)
}

/// Random label bytes: whatever Python's codec decodes or refuses, this
/// decoder does too. Four hundred agreed; a sample is kept.
@Test(arguments: [
    ("KRmPaLw0f3WOkOSDw0", nil),
    ("1F6lmE5CDpOvRnx4smGmgOvZ", nil),
    ("L", nil),
    ("jv3", nil),
    ("UgrD9SG1HQ", nil),
    ("8cnc0sd0", nil),
    ("R8py", nil),
    ("YCcvcRCzhuKIgwmCp3JT3jf", nil),
    ("k8T8Ycp-wPQYWSoWfl", nil),
    ("6c9lIYn2Ap2T36", nil),
    ("Xg", nil),
    ("gjh7w7Ry1A7wsDov", "\u{261A}\u{249B}\u{2579}\u{23E0}\u{262E}\u{2675}\u{2340}"),
    ("5CuRXNK3Z", "\u{6099}\u{61AA}\u{62DC}\u{6219}"),
    ("17y", "\u{77F6}"),
    ("s2K", "\u{3440}"),
    ("LABFUI", "\u{95}\u{8E}\u{93}\u{8C}\u{8B}"),
    ("48qK8VV4Msy8BDoLfBcWZS5Z", "\u{7D38}\u{5670}\u{522B}\u{51D4}\u{7D1C}\u{51D9}\u{7D19}\u{7D20}\u{73FB}\u{7D13}\u{7D19}\u{7D1E}"),
    ("gD4dPxsq3s-", "gD4dPxsq3s"),
    ("dAhbanZS", "\u{87}\u{83}\u{91}\u{8A}\u{87}\u{8E}\u{87}"),
    ("5afzZ", "\u{B1}\u{A2}\u{9F}\u{AA}"),
    ("LtTnPWOgO0Sn-zdk", "LtTn\u{438}PWOgO0Sn"),
    ("BCjKbjMf31MqUqAG", "\u{2BE4}\u{2BE3}\u{2CBA}\u{2D16}\u{2BDE}\u{2BD8}\u{2BE0}\u{2D15}\u{2BDD}\u{2D13}"),
] as [(String, String?)])
func decodesOrRefusesLikePython(encoded: String, decoded: String?) {
    #expect(Punycode.decode(Array(encoded.utf8)) == decoded)
}

// MARK: - Honest IDNs

/// A host wholly in Cyrillic or Greek is no homograph: its skeleton keeps
/// letters no ASCII host has, so no ASCII host looks like it (UTS #39 §4,
/// whole-script confusables). A label is refused as a look-alike only when
/// every scalar in it is ASCII or has an ASCII twin; one that keeps a letter
/// with no twin, true of nearly every Cyrillic and Greek word, is honest
/// and keeps the punycode warning.
@Test(arguments: [
    ("xn--d1abbgf6aiiy.xn--p1ai", "президент.рф"),
    ("xn--80adxhks.xn--p1ai", "москва.рф"),
    ("xn--80aa2annq7l.xn--j1amh", "україна.укр"),
    ("xn--80abgvjd1bi0f.xn--90ae", "български.бг"),
    ("xn--hxakic4aa.xn--qxam", "ελλάδα.ελ"),
    ("xn--vxaejoc4c.gr", "κόσμος.gr"),
    ("xn--kxae4bafwg.xn--pxaix.gr", "ουτοπία.δπθ.gr"),
])
func honestCyrillicAndGreekIDNsKeepTheWarning(host: String, spelled: String) {
    #expect(Confusables.domainVerdict(host) == .warning("punycode host label"), "\(spelled)")
    #expect(URLPolicy.verdict(for: "https://" + host) == .warning("punycode host label"), "\(spelled)")
    #expect(FieldValidator.website(host, limits: qr) == .warning("punycode host label"), "\(spelled)")
    #expect(FieldValidator.email("a@" + host, limits: qr) == .warning("punycode host label"), "\(spelled)")
}

/// A label whose whole skeleton is ASCII is a homograph under any TLD, an
/// IDN one included; the fix for the test above must keep these refused.
@Test(arguments: ["xn--80ak6aa92e.xn--p1ai", "xn--pple-43d.xn--p1ai", "www.xn--80ak6aa92e.xn--90ae", "xn--pypal-4ve.xn--qxam"])
func homographLabelsUnderIDNTopLevelsStayRefused(host: String) {
    #expect(!Confusables.domainVerdict(host).isAccepted)
    #expect(!URLPolicy.isTappable("https://" + host))
    #expect(!FieldValidator.website(host, limits: qr).isAccepted)
}

/// Scripts with no twins in the table, and an emoji label, keep the
/// warning today; pinned so the fix does not widen the refusal.
@Test(arguments: ["xn--fiqs8s", "xn--wgbh1c", "xn--mgbaam7a8h", "xn--j6w193g", "xn--55qx5d.xn--fiqs8s", "xn--4dbrk0ce", "xn--1ug8558fpupg10a.ws"])
func idnsWithoutLookalikesWarn(host: String) {
    #expect(Confusables.domainVerdict(host) == .warning("punycode host label"))
    #expect(URLPolicy.isTappable("https://" + host))
}

// MARK: - Pinned behaviour of the fixes

/// A label of extended digits alone decodes to C1 controls and is refused
/// as such; a header name in a case form that is not ASCII is not the
/// header.
@Test func decodedLabelsAndHeaderNamesAreJudgedAsText() {
    #expect(Confusables.domainVerdict("xn---abc.com") == .reject("control character"))
    #expect(URLPolicy.verdict(for: "mailto:a@b?\u{17F}ubject=x") == .reject("mailto header not allowed"), "long s")
    #expect(URLPolicy.verdict(for: "mailto:a@b?\u{FF33}\u{FF35}\u{FF22}\u{FF2A}\u{FF25}\u{FF23}\u{FF34}=x") == .reject("mailto header not allowed"), "fullwidth")
    #expect(URLPolicy.verdict(for: "mailto:a@b?subject=x&%73ubject=y") == .ok)
    #expect(URLPolicy.verdict(for: "mailto:a@b?SUBJECT%00=x") == .reject("control character"))
}

// MARK: - Closed gaps

/// RFC 6068 §2: the address in a `mailto` is percent-encoded, so `%0D%0A`
/// or `%E2%80%AE` in the local part would reach the mail client as CRLF or
/// an RLO. The address is decoded and scanned as the raw text is, then
/// judged as what it spells; `acct` (RFC 7565) is encoded the same way. A
/// `%` outside a triplet is refused, and a decoded `@` or `/` is the
/// character it is, not atext.
@Test(arguments: [
    ("mailto:a%00@b", Verdict.reject("control character")),
    ("mailto:a%0D%0A@b", .reject("control character")),
    ("mailto:a%E2%80%AE@b", .reject("bidirectional control character")),
    ("mailto:a%E2%80%8B@b", .reject("invisible character")),
    ("mailto:a@b%E2%80%8B", .reject("invisible character")),
    ("acct:a%0D%0A@b", .reject("control character")),
    ("acct:a%E2%80%AE@b", .reject("bidirectional control character")),
    ("mailto:a%20b@c", .reject("whitespace")),
    ("mailto:%C3%BC@b", .reject("non-ASCII character")),
    ("mailto:a@m%C3%BCnchen.de", .reject("non-ASCII host")),
    ("mailto:a@g%D1%96thub.com", .reject("non-ASCII host, looks like “github.com”")),
    ("mailto:a%40b@c", .reject("not an email address")),                      // the local part a@b needs quoting
    ("mailto:a%2Fb@c", .reject("not an email address")),
    ("mailto:a%b@c", .reject("bad percent-encoding")),
    ("mailto:a%@b", .reject("bad percent-encoding")),
    ("mailto:a%2@b", .reject("bad percent-encoding")),
    ("mailto:a@b%", .reject("bad percent-encoding")),
    ("acct:a%zz@b", .reject("bad percent-encoding")),
    ("mailto:first%2Blast@x.ie", .ok),
    ("mailto:first%2blast@x.ie", .ok),
    ("mailto:a%2Eb@c", .ok),
    ("mailto:a@x%2Eie", .ok),
    ("mailto:a%25b@c", .ok),                                                  // a literal `%`, atext in the address
    ("mailto:first%2Blast@x.ie?subject=%2B", .ok),
    ("acct:first%2Blast@x.ie", .ok),
])
func percentEncodedAddressIsJudgedDecoded(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

/// A variation selector is allowed only after a base it has a standardized
/// sequence with: U+FE0E and U+FE0F after an emoji (the keycap bases too),
/// the rest of U+FE00–FE0F after an ideograph, a Phags-pa letter or a
/// mathematical operator, and the IVD's U+E0100–E01EF after an ideograph.
/// Anywhere else, a Latin letter above all, it is a hidden byte with 256
/// values, three or four bytes of the cap each. A Mongolian letter is no
/// base for one: StandardizedVariants.txt lists none, Mongolian having
/// selectors of its own (pinned in the second review).
@Test(arguments: [
    ("\u{263A}\u{FE0E}", Verdict.ok),                                            // ☺︎ text style
    ("\u{263A}\u{FE0F}", .ok),                                                   // ☺️ emoji style
    ("\u{2708}\u{FE0F}", .ok),                                                   // ✈️
    ("1\u{FE0F}\u{20E3}", .ok),                                                  // 1️⃣
    ("#\u{FE0F}\u{20E3}", .ok),
    ("\u{908A}\u{E0100}", .ok),                                                  // 邊󠄀, an IVD sequence
    ("\u{908A}\u{FE00}", .ok),
    ("\u{2205}\u{FE00}", .ok),                                                   // ∅︀, a standardized variant
    ("\u{A856}\u{FE00}", .ok),
    ("\u{1820}\u{FE00}", .reject("invisible character")),                     // Mongolian uses FVS1–4 instead
    ("J\u{E0100}o\u{E0148}h\u{E01EF}n\u{FE03}", .reject("invisible character")),
    ("a\u{FE0F}", .reject("invisible character")),
    ("a\u{FE00}", .reject("invisible character")),
    ("a\u{E0100}", .reject("invisible character")),
    ("e\u{301}\u{FE0F}", .reject("invisible character")),                       // a mark is no base
    ("\u{908A}\u{FE0F}", .reject("invisible character")),                       // an ideograph has no emoji style
    ("\u{263A}\u{FE00}", .reject("invisible character")),                       // nor an emoji a text variant
    ("\u{263A}\u{E0100}", .reject("invisible character")),
    ("1\u{E0100}", .reject("invisible character")),
    ("\u{430}\u{FE0F}", .reject("invisible character")),                        // Cyrillic
    ("\u{627}\u{FE00}", .reject("invisible character")),                        // Arabic
])
func selectorsNeedAStandardizedSequence(s: String, verdict: Verdict) {
    #expect(TextCheck.check(s, maxBytes: 64) == verdict)
    #expect(FieldValidator.customValue(s, kind: .text, limits: qr) == verdict)
    #expect(URLPolicy.verdict(for: "https://example.com/" + s) == verdict, "in a path")
}

/// No Latin letter has a variation sequence, so every selector after one
/// is refused.
@Test func latinLettersTakeNoSelector() {
    for value in Array(UInt32(0xFE00)...0xFE0F) + Array(UInt32(0xE0100)...0xE01EF) {
        let name = "Jo" + String(Unicode.Scalar(value)!) + "hn"
        #expect(TextCheck.check(name, maxBytes: 64) == .reject("invisible character"), "\(String(value, radix: 16))")
    }
}
