import Testing
@testable import HatbandCore

// Second review of Validate, after 4cf7fce closed the first review's gaps:
// the homograph rule is attacked label by label and script by script, the
// decoded mailto and acct address byte by byte, and the variation-selector
// rule base by base. One test fails on a real defect (a label that starts
// with a combining mark hides the homograph label before it from the
// per-label split); what the rule accepts by design is pinned as such, and
// what it lets through is kept under `withKnownIssue`.

private let qr = Limits.qr

/// The raw form of a host is refused whatever it spells; only a homograph
/// says what it looks like.
private func rawVerdict(for verdict: Verdict) -> Verdict {
    if case .reject(let reason) = verdict, reason.hasPrefix("non-ASCII host, looks like") { return verdict }
    return .reject("non-ASCII host")
}

@Suite struct ValidateSecondReview {
    // MARK: - Homograph rule

    /// Each decoded label is judged on its own: whole-script Armenian, Greek
    /// with a final sigma, a Latin ligature, an emoji and an astral
    /// ideograph keep a letter with no twin and are honest; a label whose
    /// every letter is a twin is a homograph in any script the table
    /// covers, digits, dashes and a fullwidth dot included; mixed scripts
    /// are a homograph first and mixed second; and one homograph label
    /// under or over an honest one condemns the host. The raw form gets the
    /// same "looks like" or a plain refusal.
    @Test(arguments: [
        ("xn--y9aaa1d0ai1cq.am", "\u{570}\u{561}\u{575}\u{561}\u{57D}\u{57F}\u{561}\u{576}.am", Verdict.warning("punycode host label")),
        ("xn--0xage.gr", "\u{3C4}\u{3BF}\u{3C2}.gr", .warning("punycode host label")),
        ("xn--le-1b1n.com", "\u{FB01}le.com", .warning("punycode host label")),
        ("xn--qei9934e.ws", "\u{2764}\u{FE0F}.ws", .warning("punycode host label")),
        ("xn--j50i.cn", "\u{20000}.cn", .warning("punycode host label")),
        ("xn--80aa2cbv.com", "\u{441}\u{430}\u{445}\u{430}\u{440}.com", .reject("non-ASCII host, looks like “caxap.com”")),
        ("xn--80a1aff.com", "\u{440}\u{43E}\u{441}\u{430}.com", .reject("non-ASCII host, looks like “poca.com”")),
        ("xn--mxasph.gr", "\u{3B1}\u{3BA}\u{3C1}\u{3BF}.gr", .reject("non-ASCII host, looks like “akpo.gr”")),
        ("xn--mbbky.am", "\u{578}\u{57D}\u{585}.am", .reject("non-ASCII host, looks like “nuo.am”")),
        ("xn--ecure-zib.com", "\u{17F}ecure.com", .reject("non-ASCII host, looks like “secure.com”")),
        ("xn--ntel-kza.com", "\u{131}ntel.com", .reject("non-ASCII host, looks like “intel.com”")),
        ("xn--oogle-qmc.com", "\u{261}oogle.com", .reject("non-ASCII host, looks like “google.com”")),
        ("xn--8g7ccd.com", "\u{FF11}\u{FF12}\u{FF13}.com", .reject("non-ASCII host, looks like “123.com”")),
        ("xn--PPLE-kzd.com", "\u{410}PPLE.com", .reject("non-ASCII host, looks like “APPLE.com”")),
        ("xn--12-7kc.com", "1\u{430}2.com", .reject("non-ASCII host, looks like “1a2.com”")),
        ("xn--4ug.com", "\u{2010}.com", .reject("non-ASCII host, looks like “-.com”")),
        ("xn--ypal-43d9g.com", "\u{440}\u{430}ypal.com", .reject("non-ASCII host, looks like “paypal.com”")),
        ("xn--pyal-53d1b.com", "p\u{430}y\u{436}al.com", .reject("mixed scripts in punycode label")),
        ("xn--80adxhks.xn--e1ay", "москва.\u{435}\u{441}", .reject("non-ASCII host, looks like “москва.ec”")),
        ("xn--pple-43d.xn--80adxhks", "\u{430}pple.москва", .reject("non-ASCII host, looks like “apple.москва”")),
        ("xn--pplecom-1fg61198c.net", "\u{430}pple\u{FF0E}com.net", .reject("non-ASCII host, looks like “apple.com.net”")),
    ])
    func judgesEachDecodedLabelOnItsOwn(host: String, raw: String, verdict: Verdict) {
        #expect(Confusables.domainVerdict(host) == verdict)
        #expect(URLPolicy.verdict(for: "https://" + host) == verdict)
        #expect(URLPolicy.verdict(for: "mailto:a@" + host) == verdict)
        #expect(FieldValidator.website(host, limits: qr) == verdict)
        #expect(Confusables.domainVerdict(raw) == rawVerdict(for: verdict), "raw form")
    }

    /// `homographSkeleton` names the ASCII a homograph label imitates and
    /// leaves every other label alone, ASCII ones included.
    @Test func skeletonIsPerLabel() {
        #expect(Confusables.homographSkeleton("\u{430}pple.com") == "apple.com")
        #expect(Confusables.homographSkeleton("\u{441}\u{430}\u{445}\u{430}\u{440}") == "caxap")
        #expect(Confusables.homographSkeleton("москва.\u{430}pple.com") == "москва.apple.com")
        #expect(Confusables.homographSkeleton("\u{430}.\u{431}") == "a.\u{431}")
        #expect(Confusables.homographSkeleton("\u{430}pple\u{FF0E}com") == "apple.com")
        #expect(Confusables.homographSkeleton("a\u{2010}b") == "a-b")
        #expect(Confusables.homographSkeleton("москва.рф") == nil)
        #expect(Confusables.homographSkeleton("münchen.de") == nil)
        #expect(Confusables.homographSkeleton("github.com") == nil)
        #expect(Confusables.homographSkeleton("") == nil)
    }

    /// The raw form: case, a trailing dot, a fake dot inside an honest
    /// label, and one homograph label among honest ones.
    @Test func rawHostsAtTheEdges() {
        #expect(Confusables.domainVerdict("\u{410}PPLE.COM") == .reject("non-ASCII host, looks like “APPLE.COM”"))
        #expect(Confusables.domainVerdict("\u{430}pple.com.") == .reject("non-ASCII host, looks like “apple.com.”"))
        #expect(Confusables.domainVerdict("москва\u{3002}рф") == .reject("non-ASCII host"))
        #expect(Confusables.domainVerdict("москва.\u{430}pple.com") == .reject("non-ASCII host, looks like “москва.apple.com”"))
        #expect(FieldValidator.handle("user@xn--80ak6aa92e.com", limits: qr) == .reject("non-ASCII host, looks like “apple.com”"))
    }

    /// The homograph rule splits the decoded host on `Character` ".", so a
    /// label that begins with a combining mark swallows the dot before it
    /// and the label ahead of it is never judged on its own: `аррӏе.́evil.com`
    /// gets the warning `аррӏе.evil.com` is refused with. RFC 5891 §4.2.3.2
    /// forbids a mark-initial label, so the spelling is nonsense a resolver
    /// still answers for. Fails until the split is on scalars, or a
    /// mark-initial label is refused outright.
    @Test func homographLabelIsJudgedBeforeAMarkInitialLabel() {
        #expect(Confusables.domainVerdict("xn--80ak6aa92e.evil.com") == .reject("non-ASCII host, looks like “apple.evil.com”"))
        #expect(!Confusables.domainVerdict("xn--80ak6aa92e.xn--evil-uvc.com").isAccepted)
        #expect(!URLPolicy.isTappable("https://xn--80ak6aa92e.xn--evil-uvc.com"))
    }

    // MARK: - Homograph rule, known gaps

    /// A combining mark is neither ASCII nor in the table, so `аррӏе́`
    /// (every letter a twin, an acute on the last) and `аррӏ̇е` (a dot on
    /// the ӏ) keep a scalar the rule calls honest and take the warning; a
    /// browser draws `applé.com`. Marks belong to the letter before them
    /// and should not make a label honest.
    @Test func knownGapMarkOnAHomographLabel() {
        withKnownIssue("a combining mark makes a homograph label honest") {
            #expect(!Confusables.domainVerdict("xn--lsa91dpa7ba27f.com").isAccepted)
            #expect(!Confusables.domainVerdict("xn--rsa70dqa6ba27f.com").isAccepted)
        }
    }

    /// A decoded label with an ideographic full stop inside it spells
    /// `москва。com`: UTS #46 maps U+3002 to `.`, so no honest A-label
    /// contains one, yet the letters around it have no twins and the label
    /// takes the warning. Before 4cf7fce it was refused as a look-alike.
    @Test func knownGapFakeDotInsideAnHonestLabel() {
        withKnownIssue("a dot look-alike inside a decoded label passes as honest") {
            #expect(!Confusables.domainVerdict("xn--com-5cdj1cnq1a7213i").isAccepted)
        }
    }

    // MARK: - Decoded addresses

    /// One level of decoding: a triplet that decodes to `%` stays a literal
    /// `%`, atext in a local part; `?`, `&`, `=` and `#` decoded are atext
    /// too; a fully encoded address is the address it spells. A decoded
    /// dot obeys the dot-atom rules, a decoded byte in the host is judged
    /// as the host it spells (a dot, a slash, a colon, a look-alike, an IP
    /// address), and every hidden scalar the raw scan refuses is refused
    /// encoded, in any hex case, including bytes that are not UTF-8.
    @Test(arguments: [
        ("mailto:a%252B@b", Verdict.ok),
        ("mailto:a%2540b@c", .ok),
        ("mailto:a%2525@b", .ok),
        ("mailto:a%2B%2b@b", .ok),
        ("mailto:a%3Fb@c", .ok),
        ("mailto:a%26b%3Dc%23d@e", .ok),
        ("mailto:%61%40b", .ok),
        ("MAILTO:first%2Blast@x.ie", .ok),
        ("mailto:a%2Eb%2Ec@d", .ok),
        ("acct:%62loom@merveilles.town", .ok),
        ("acct:a%2540b@c", .ok),
        ("acct:a%40b@c", .reject("not an acct address")),
        ("acct:a@b%3Fx", .reject("invalid host label")),
        ("mailto:%2Ea@b", .reject("not an email address")),
        ("mailto:a%2E@b", .reject("not an email address")),
        ("mailto:a%2E%2Eb@c", .reject("not an email address")),
        ("mailto:a@%2Ecom", .reject("invalid host label")),
        ("mailto:a@b%2E", .reject("invalid host label")),
        ("mailto:a@b%2E%2Ec", .reject("invalid host label")),
        ("mailto:a@b%25c", .reject("invalid host label")),
        ("mailto:a@b%3A25", .reject("invalid host label")),
        ("mailto:a@b%2Fc", .reject("invalid host label")),
        ("mailto:a@b%3Fsubject=x", .reject("invalid host label")),
        ("mailto:a@xn--pple-43d%2Ecom", .reject("non-ASCII host, looks like “apple.com”")),
        ("mailto:a@%78n--pple-43d.com", .reject("non-ASCII host, looks like “apple.com”")),
        ("mailto:a@b%EF%BC%8Ecom", .reject("non-ASCII host, looks like “b.com”")),
        ("mailto:a@127%2E0%2E0%2E1", .reject("IP address")),
        ("mailto:a@%30x7f000001", .reject("IP address")),
        ("mailto:a@%D0%BC%D0%BE%D1%81%D0%BA%D0%B2%D0%B0.%D1%80%D1%84", .reject("non-ASCII host")),
        ("mailto:a%EF%BC%8Bb@c", .reject("non-ASCII character")),
        ("mailto:a%09b@c", .reject("control character")),
        ("mailto:a%0Ab@c", .reject("control character")),
        ("mailto:a%7F@b", .reject("control character")),
        ("mailto:a%C2%85@b", .reject("control character")),
        ("mailto:a%c2%a0b@c", .reject("whitespace")),
        ("mailto:a%E2%80%83b@c", .reject("whitespace")),
        ("mailto:a%E3%80%80b@c", .reject("whitespace")),
        ("mailto:a%E2%80%8Eb@c", .reject("bidirectional control character")),
        ("mailto:a%D8%9Cb@c", .reject("bidirectional control character")),
        ("mailto:a%E2%81%A6b@c", .reject("bidirectional control character")),
        ("mailto:a%C2%ADb@c", .reject("invisible character")),
        ("mailto:a%EF%BB%BFb@c", .reject("invisible character")),
        ("mailto:a%F3%A0%80%81b@c", .reject("invisible character")),
        ("mailto:a%E2%80%8Db@c", .reject("invisible character")),
        ("mailto:a%EF%B8%8F@b", .reject("invisible character")),
        ("mailto:a%EE%80%80@b", .reject("unassigned or private-use character")),
        ("mailto:a%EF%BF%BE@b", .reject("unassigned or private-use character")),
        ("mailto:a%EF%BF%BD@b", .reject("non-ASCII character")),
        ("mailto:a%FF@b", .reject("non-ASCII character")),
        ("mailto:a%C0%80@b", .reject("non-ASCII character")),
        ("mailto:a%ED%A0%80@b", .reject("non-ASCII character")),
        ("mailto:a@b%FF", .reject("non-ASCII host")),
        ("mailto:a@b%C0%80", .reject("non-ASCII host")),
        ("mailto:%%41@b", .reject("bad percent-encoding")),
        ("mailto:a%4@b", .reject("bad percent-encoding")),
        ("mailto:a%G0@b", .reject("bad percent-encoding")),
        ("mailto:a%2%41@b", .reject("bad percent-encoding")),
        ("mailto:a@b%?subject=x", .reject("bad percent-encoding")),
    ])
    func decodedAddressesAtTheEdges(url: String, verdict: Verdict) {
        #expect(URLPolicy.verdict(for: url) == verdict)
    }

    /// The 64-byte local-part cap counts decoded bytes, not triplets.
    @Test func localPartCapCountsDecodedBytes() {
        let sixtyFour = String(repeating: "%61", count: 64)
        #expect(URLPolicy.verdict(for: "mailto:" + sixtyFour + "@b") == .ok)
        #expect(URLPolicy.verdict(for: "mailto:" + sixtyFour + "%61@b") == .reject("not an email address"))
    }

    /// Every stored address the email field accepts is accepted again as
    /// the `mailto:` `CanonicalURI` builds from it: the builder encodes `%`
    /// and the other bytes RFC 6068 reserves, and the policy decodes them
    /// back to the address.
    @Test(arguments: ["first+last@x.ie", "!#$%&'*+-=^_`{|}~@c", "henry.flower@example.ie", "a%0D%0A@b", "a@xn--mnchen-3ya.de"])
    func storedAddressesSurviveTheirMailto(stored: String) {
        let field = FieldValidator.email(stored, limits: qr)
        #expect(field.isAccepted)
        #expect(URLPolicy.verdict(for: CanonicalURI.email(stored)) == field)
    }

    // MARK: - Variation selectors

    /// Emoji bases of every kind take U+FE0E and U+FE0F: symbols in Latin-1
    /// and the arrows, an enclosed ideograph, an astral emoji, the keycap
    /// bases, and inside a ZWJ sequence; a flag and a modifier sequence
    /// need none. An astral or compatibility ideograph takes the IVD and
    /// U+FE00; a mathematical operator U+FE00. A selector on a selector, a
    /// mark, a ZWJ, a flag half, a modifier, U+FFFD or a letter of any
    /// other script is the hidden byte it is. The same in a URL query.
    @Test(arguments: [
        ("\u{A9}\u{FE0F}", Verdict.ok),
        ("\u{AE}\u{FE0E}", .ok),
        ("\u{2122}\u{FE0F}", .ok),
        ("\u{203C}\u{FE0F}", .ok),
        ("\u{2139}\u{FE0F}", .ok),
        ("\u{2194}\u{FE0F}", .ok),
        ("\u{3297}\u{FE0F}", .ok),
        ("\u{1F21A}\u{FE0F}", .ok),
        ("*\u{FE0F}\u{20E3}", .ok),
        ("0\u{FE0F}\u{20E3}", .ok),
        ("9\u{FE0E}\u{20E3}", .ok),
        ("5\u{FE0E}", .ok),
        ("\u{1F441}\u{FE0F}\u{200D}\u{1F5E8}\u{FE0F}", .ok),
        ("\u{1F3F3}\u{FE0F}\u{200D}\u{26A7}\u{FE0F}", .ok),
        ("\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", .ok),
        ("\u{1F1FA}\u{1F1F8}", .ok),
        ("\u{1F44D}\u{1F3FD}", .ok),
        ("\u{20000}\u{E0100}", .ok),
        ("\u{20000}\u{FE00}", .ok),
        ("\u{F900}\u{FE00}", .ok),
        ("\u{2268}\u{FE00}", .ok),
        ("\u{65E5}\u{E0100}\u{672C}\u{E0148}\u{8A9E}\u{E01EF}", .ok),        // the IVD channel the rule keeps, by design
        ("\u{263A}\u{FE0F}\u{FE0E}", .reject("invisible character")),
        ("\u{263A}\u{FE0F}\u{FE0F}", .reject("invisible character")),
        ("\u{908A}\u{E0100}\u{E0101}", .reject("invisible character")),
        ("\u{908A}\u{E0100}\u{FE00}", .reject("invisible character")),
        ("\u{2268}\u{FE0F}", .reject("invisible character")),
        ("\u{2268}\u{E0100}", .reject("invisible character")),
        ("\u{1820}\u{FE0F}", .reject("invisible character")),
        ("\u{1820}\u{E0100}", .reject("invisible character")),
        ("\u{A856}\u{FE0E}", .reject("invisible character")),
        ("\u{3042}\u{FE00}", .reject("invisible character")),
        ("\u{30A2}\u{FE0F}", .reject("invisible character")),
        ("\u{D55C}\u{FE00}", .reject("invisible character")),
        ("\u{5D0}\u{FE00}", .reject("invisible character")),
        ("\u{905}\u{E0100}", .reject("invisible character")),
        ("\u{1D400}\u{E0100}", .reject("invisible character")),
        ("\u{1F600}\u{E0100}", .reject("invisible character")),
        ("\u{1F1FA}\u{FE00}\u{1F1F8}", .reject("invisible character")),
        ("\u{1F44D}\u{1F3FD}\u{FE00}", .reject("invisible character")),
        ("\u{FFFD}\u{FE0F}", .reject("invisible character")),
        ("\u{263A}\u{200D}\u{FE0F}\u{263A}", .reject("invisible character")),
        ("\u{263A}\u{20E3}\u{FE0F}", .reject("invisible character")),
        ("1\u{20E3}\u{FE0F}", .reject("invisible character")),
        ("1\u{FE00}", .reject("invisible character")),
        ("1\u{FE0F}\u{FE0F}\u{20E3}", .reject("invisible character")),
    ])
    func selectorsOnEveryKindOfBase(s: String, verdict: Verdict) {
        #expect(TextCheck.check(s, maxBytes: 64) == verdict)
        #expect(URLPolicy.verdict(for: "https://example.com/?q=" + s) == verdict, "in a query")
    }

    /// A selector after whitespace or at the start has no base at all.
    @Test func selectorsWithNoBase() {
        #expect(TextCheck.check(" \u{FE0F}", maxBytes: 64) == .reject("invisible character"))
        #expect(TextCheck.check("\u{FE0F}a", maxBytes: 64) == .reject("invisible character"))
        #expect(TextCheck.check("a\n\u{FE0F}", maxBytes: 64, allowNewlines: true) == .reject("invisible character"))
    }

    /// A URL tail is judged decoded: an encoded emoji with its encoded
    /// selector, or a raw emoji with an encoded selector, is the sequence
    /// it spells; an encoded selector on a letter, a slash or nothing is
    /// not. A raw selector after an encoded base follows the last raw
    /// character, a hex digit, and is refused before decoding.
    @Test(arguments: [
        ("https://example.com/%E2%98%BA%EF%B8%8F", Verdict.ok),
        ("https://example.com/\u{263A}%EF%B8%8F", .ok),
        ("https://example.com/1%EF%B8%8F%E2%83%A3", .ok),
        ("https://example.com/%E9%82%8A%F3%A0%84%80", .ok),
        ("mailto:a@b?subject=%E2%9C%88%EF%B8%8F", .ok),
        ("https://example.com/%E2%98%BA\u{FE0F}", .reject("invisible character")),
        ("https://example.com/a%EF%B8%8F", .reject("invisible character")),
        ("https://example.com/%F3%A0%84%80", .reject("invisible character")),
        ("https://example.com/?%EF%B8%8F", .reject("invisible character")),
        ("mailto:a@b?subject=x%EF%B8%8F", .reject("invisible character")),
    ])
    func encodedSelectorsInTails(url: String, verdict: Verdict) {
        #expect(URLPolicy.verdict(for: url) == verdict)
    }

    // MARK: - Known schemes

    /// A known scheme is one whatever follows the colon; an unknown one
    /// with a port-like tail still reads as host and port, and is refused
    /// either way.
    @Test(arguments: [
        ("http:80", Verdict.reject("malformed URL")),
        ("acct:80", .reject("not an acct address")),
        ("openpgp4fpr:1", .reject("not an OpenPGP fingerprint")),
        ("OPENPGP4FPR:12345", .reject("not an OpenPGP fingerprint")),
        ("TEL:555", .reject("not an E.164 number")),
        ("tel:55555", .reject("not an E.164 number")),
        ("tel:555555", .reject("not an E.164 number")),
        ("mailto:80/x", .reject("not an email address")),
        ("javascript:80", .reject("missing scheme")),
    ])
    func knownSchemesKeepTheirReasons(url: String, verdict: Verdict) {
        #expect(URLPolicy.verdict(for: url) == verdict)
        #expect(!URLPolicy.isTappable(url))
    }
}
