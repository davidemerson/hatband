import Testing
@testable import HatbandCore

// Third review of Validate, a sweep for one defect class. Swift's `Character`
// is a grapheme cluster: a combining mark, a variation selector, a ZWJ or a
// tag letter fuses with the scalar before it, and a Prepend-class letter
// (the Malayalam dot reph, the Arabic number sign) with the one after it,
// so any `split`, `hasPrefix`, `count` or `contains` and any test of
// `.isWhitespace` on `Character`s can be fooled. Every public entry point
// takes plain accepted inputs and gets each of six fusing scalars inserted
// at every scalar gap: every delimiter, whitespace, allowed invisible and
// limit boundary, the start and the end. A fusion must be refused, or keep
// the plain verdict with the scheme, host, address and header names byte
// for byte the same. Octet caps are probed with marks piled on one letter,
// case mapping with the letters whose mapping changes the scalar count.
// Nothing here changes the module; what it accepts by design is pinned as
// such.

private let qr = Limits.qr

/// Fuse with the scalar before them: a combining acute, the emoji
/// presentation selector, a ZWJ, a tag letter. Fuse with the scalar after
/// them (Grapheme_Cluster_Break=Prepend): the Malayalam dot reph, a letter,
/// and the Arabic number sign, a format control.
private let fusing: [Unicode.Scalar] = ["\u{301}", "\u{FE0F}", "\u{200D}", "\u{E0041}", "\u{D4E}", "\u{600}"]

private func hex(_ scalar: Unicode.Scalar) -> String {
    "U+" + String(scalar.value, radix: 16, uppercase: true)
}

/// One fusing scalar inserted into a plain input at one scalar gap.
private struct Fusion {
    let inserted: Unicode.Scalar
    let index: Int
    let scalars: [Unicode.Scalar]

    var text: String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    var previous: Unicode.Scalar? { index > 0 ? scalars[index - 1] : nil }
    var next: Unicode.Scalar? { index + 1 < scalars.count ? scalars[index + 1] : nil }
    var name: String { "\(hex(inserted)) at scalar \(index)" }
}

/// Every fusing scalar at every gap of `plain`, the start and end included.
private func fusions(of plain: String) -> [Fusion] {
    let scalars = Array(plain.unicodeScalars)
    var out: [Fusion] = []
    for index in 0...scalars.count {
        for scalar in fusing {
            var fused = scalars
            fused.insert(scalar, at: index)
            out.append(Fusion(inserted: scalar, index: index, scalars: fused))
        }
    }
    return out
}

/// What a fusion may do to a verdict. An ASCII field refuses every one. A
/// text or URL field refuses the tag letter and the number sign always, the
/// selector unless it lands on an emoji, the ZWJ unless it lands between
/// two pictographs, and keeps the plain verdict when it accepts the mark or
/// the reph; a URL keeps its frame too (`frame(of:)`).
private enum Field {
    case ascii, text, url
}

private func isPictograph(_ scalar: Unicode.Scalar?) -> Bool {
    guard let scalar else { return false }
    return scalar.value >= 0x80 && scalar.properties.isEmoji
}

/// The parts of a URL no accepted fusion may touch: the scheme, then the
/// authority of a `//` URL or the address and header names of a `mailto`.
/// Bytes, so canonical equivalence has no say.
private func frame(of url: String) -> [[UInt8]] {
    let bytes = Array(url.utf8)
    guard let colon = bytes.firstIndex(of: UInt8(ascii: ":")) else { return [bytes] }
    let scheme = Array(bytes[..<colon])
    let rest = bytes[(colon + 1)...]
    if rest.starts(with: "//".utf8) {
        return [scheme, Array(rest.dropFirst(2).prefix { !"/?#".utf8.contains($0) })]
    }
    let address = rest.prefix { $0 != UInt8(ascii: "?") }
    let names = rest.dropFirst(address.count + 1).split(separator: UInt8(ascii: "&")).map { field in
        Array(field.prefix { $0 != UInt8(ascii: "=") })
    }
    return [scheme, Array(address)] + names
}

/// The plain input is accepted; each fusion of it is refused or, as `field`
/// allows, keeps the plain verdict.
private func sweep(
    _ plain: String, as field: Field, _ check: (String) -> Verdict, sourceLocation: SourceLocation = #_sourceLocation
) {
    let expected = check(plain)
    #expect(expected.isAccepted, "plain \(plain) is \(expected)", sourceLocation: sourceLocation)
    for fusion in fusions(of: plain) {
        let verdict = check(fusion.text)
        guard verdict.isAccepted else { continue }
        let at = "\(fusion.name) in \(plain): \(verdict)"
        switch field {
        case .ascii:
            Issue.record("accepted \(at)", sourceLocation: sourceLocation)
        case .text, .url:
            #expect(verdict == expected, "\(at)", sourceLocation: sourceLocation)
            switch fusion.inserted {
            case "\u{E0041}", "\u{600}":
                Issue.record("accepted \(at)", sourceLocation: sourceLocation)
            case "\u{FE0F}":
                #expect(fusion.previous?.properties.isEmoji == true, "\(at)", sourceLocation: sourceLocation)
            case "\u{200D}":
                #expect(isPictograph(fusion.previous) && isPictograph(fusion.next), "\(at)", sourceLocation: sourceLocation)
            default:
                break
            }
            if case .url = field {
                #expect(frame(of: fusion.text) == frame(of: plain), "\(at)", sourceLocation: sourceLocation)
            }
        }
    }
}

/// What a rejection says a host looks like: the scalars between the last
/// `looks like “` and the `”` after it, or nil when it says no such thing.
private func lookAlike(in reason: String) -> [Unicode.Scalar]? {
    let scalars = Array(reason.unicodeScalars)
    let marker = Array("looks like \u{201C}".unicodeScalars)
    guard let start = scalars.indices.last(where: { scalars[$0...].starts(with: marker) }) else { return nil }
    return Array(scalars[(start + marker.count)...].prefix { $0 != "\u{201D}" })
}

@Suite struct ValidateScalarSweep {
    // MARK: - The class

    /// Why the sweep exists: each of the six fuses with a dot into one
    /// `Character`, so a `Character` split sees no dot where a scalar
    /// split sees one.
    @Test func eachFusingScalarSwallowsADelimiter() {
        for scalar in fusing.prefix(4) {
            let host = "a.\(scalar)b"
            #expect(host.unicodeScalars.count == 4, "\(hex(scalar))")
            #expect(host.count == 3, "\(hex(scalar))")
            #expect(host.split(separator: ".").count == 1, "\(hex(scalar))")
            #expect(host.unicodeScalars.split(separator: ".").count == 2, "\(hex(scalar))")
        }
        for scalar in fusing.suffix(2) {
            let host = "a\(scalar).b"
            #expect(host.count == 3, "\(hex(scalar))")
            #expect(host.split(separator: ".").count == 1, "\(hex(scalar))")
            #expect(host.unicodeScalars.split(separator: ".").count == 2, "\(hex(scalar))")
        }
    }

    // MARK: - Text fields

    /// A name, a company, a custom label and a custom text: a mark or a
    /// reph anywhere, a space, a hyphen, an apostrophe or a comma before
    /// it included, changes nothing; the four invisibles are refused
    /// wherever they land.
    @Test(arguments: ["David Emerson", "\u{DC}n\u{EF}code N\u{E4}me", "David \u{414}\u{44D}\u{432}\u{438}\u{434}",
                      "Jean-Luc O'Brien", "Acme, Inc.", "a  b", "x"])
    func textFieldsKeepTheirVerdictOrRefuse(plain: String) {
        sweep(plain, as: .text) { TextCheck.check($0, maxBytes: 64) }
        sweep(plain, as: .text) { FieldValidator.name($0, limits: qr) }
        sweep(plain, as: .text) { FieldValidator.company($0, limits: qr) }
        sweep(plain, as: .text) { FieldValidator.customLabel($0, limits: qr) }
        sweep(plain, as: .text) { FieldValidator.customValue($0, kind: .text, limits: qr) }
    }

    /// The invisibles the rule allows in context: a fusion beside one is
    /// refused, or leaves the sequence as it was. A selector is accepted
    /// only on an emoji, a ZWJ only between two pictographs, so a second
    /// one, one on a mark or on a reph, never passes.
    @Test(arguments: [
        "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", "\u{263A}\u{FE0F}", "\u{1F468}\u{200D}\u{1F469}", "\u{1820}\u{180B}",
        "\u{628}\u{200C}\u{627}", "\u{908A}\u{E0100}", "\u{2205}\u{FE00}", "1\u{FE0F}\u{20E3}", "\u{1F600} ok",
    ])
    func allowedInvisiblesKeepTheirVerdictOrRefuse(plain: String) {
        sweep(plain, as: .text) { TextCheck.check($0, maxBytes: 64) }
        sweep(plain, as: .text) { FieldValidator.name($0, limits: qr) }
    }

    /// Text that may span lines: a fusion on the newline changes nothing
    /// where newlines are allowed, and the newline stays a control
    /// character where they are not.
    @Test func multilineTextKeepsItsVerdictOrRefuses() {
        sweep("Line one\nLine two", as: .text) { FieldValidator.customValue($0, kind: .text, limits: qr) }
        for scalar in ["\u{301}", "\u{D4E}"] as [Unicode.Scalar] {
            #expect(TextCheck.check("Line one\n\(scalar)Line two", maxBytes: 64) == .reject("control character"))
            #expect(TextCheck.check("Line one\(scalar)\nLine two", maxBytes: 64) == .reject("control character"))
        }
    }

    // MARK: - ASCII fields

    /// An email, a phone, a website, a handle, a signal.me link, a key and
    /// a stored host refuse every fusion at every gap: a mark on the `@`,
    /// the `+`, the `.`, the `/`, the `#`, the `-` of `xn--`, or a reph
    /// before one, alike.
    @Test func asciiFieldsRefuseEveryFusion() {
        for plain in ["first.last@example.com", "a+b@xn--mnchen-3ya.de", "FIRST@EXAMPLE.COM"] {
            sweep(plain, as: .ascii) { FieldValidator.email($0, limits: qr) }
            sweep(plain, as: .ascii) { FieldValidator.customValue($0, kind: .email, limits: qr) }
        }
        for plain in ["+15551234567", "+353871234567"] {
            sweep(plain, as: .ascii) { FieldValidator.phone($0, limits: qr) }
            sweep(plain, as: .ascii) { FieldValidator.customValue($0, kind: .phone, limits: qr) }
        }
        for plain in ["example.com/~bloom?x=1#y", "localhost:8080", "nnix.com", "EXAMPLE.COM/A"] {
            sweep(plain, as: .ascii) { FieldValidator.website($0, limits: qr) }
        }
        for plain in ["bloom", "bloom/coffee", "user@instance.social", "@user@instance.social", "a.b-c_d"] {
            sweep(plain, as: .ascii) { FieldValidator.handle($0, limits: qr) }
        }
        for plain in ["https://signal.me/#p/+15551234567", "https://signal.me/#eu/abc-_=", "HTTPS://SIGNAL.ME/#eu/abc"] {
            sweep(plain, as: .ascii) { FieldValidator.signalURL($0, limits: qr) }
        }
        for plain in ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGb", "SHA256:AbCdEf0123456789+/="] {
            sweep(plain, as: .ascii) { FieldValidator.customValue($0, kind: .key, limits: qr) }
        }
        let fingerprint = String(repeating: "0123456789abcdef", count: 2) + "89abcdef"
        for plain in ["tel:+1-555-123-4567", "TEL:+15551234567", "acct:bloom@merveilles.town",
                      "openpgp4fpr:" + fingerprint, "OPENPGP4FPR:" + fingerprint.uppercased()] {
            sweep(plain, as: .ascii) { URLPolicy.verdict(for: $0) }
            sweep(plain, as: .ascii) { FieldValidator.customValue($0, kind: .url, limits: qr) }
        }
        for plain in ["www.example.com", "xn--mnchen-3ya.de", "a-b.c1.d", "EXAMPLE.COM", "XN--MNCHEN-3YA.DE"] {
            sweep(plain, as: .ascii) { Confusables.domainVerdict($0) }
        }
    }

    // MARK: - URLs

    /// A web or mailto URL keeps its verdict and its frame, or is refused:
    /// a mark or a reph in the path, query, fragment or a header value is
    /// an IRI character and passes; on the scheme, the `//`, the host, the
    /// port, the address, a header name or inside a percent triplet it is
    /// refused. `isTappable` agrees with the verdict throughout.
    @Test(arguments: [
        "https://example.com:8080/path/to?q=1&r=%41#frag",
        "http://example.com/",
        "https://xn--mnchen-3ya.de/",
        "HTTPS://EXAMPLE.COM/",
        "https://example.com/?q=\u{263A}\u{FE0F}",
        "mailto:first.last@example.com?subject=Hi&body=There",
        "mailto:a@b?%53ubject=x",
        "MAILTO:a@b.ie",
    ])
    func urlsKeepTheirFrameOrRefuse(plain: String) {
        sweep(plain, as: .url) { url in
            let verdict = URLPolicy.verdict(for: url)
            #expect(URLPolicy.isTappable(url) == verdict.isAccepted, "\(url)")
            return verdict
        }
        sweep(plain, as: .url) { FieldValidator.customValue($0, kind: .url, limits: qr) }
    }

    /// A percent-encoded fusion is judged as the scalar it spells: a mark
    /// or a reph passes in a tail and is refused in an address, a host or
    /// a header name; the four invisibles are refused everywhere but on
    /// their base.
    @Test(arguments: [
        ("https://example.com/%CC%81", Verdict.ok),
        ("https://example.com/%E0%B5%8E", .ok),
        ("https://example.com/%EF%B8%8F", .reject("invisible character")),
        ("https://example.com/%E2%80%8D", .reject("invisible character")),
        ("https://example.com/%F3%A0%81%81", .reject("invisible character")),
        ("https://example.com/%D8%80", .reject("invisible character")),
        ("https://example.com/?q=%E2%98%BA%EF%B8%8F", .ok),
        ("mailto:a%CC%81@b.ie", .reject("non-ASCII character")),
        ("mailto:a%E0%B5%8E@b.ie", .reject("non-ASCII character")),
        ("mailto:a@b%CC%81.ie", .reject("non-ASCII host")),
        ("mailto:a@b%E0%B5%8E.ie", .reject("non-ASCII host")),
        ("mailto:a@b.ie?subject%E0%B5%8E=x", .reject("mailto header not allowed")),
        ("mailto:a@b.ie?subject=%CC%81x", .ok),
        ("acct:a%CC%81@b.ie", .reject("non-ASCII character")),
    ])
    func encodedFusionsAreJudgedDecoded(url: String, verdict: Verdict) {
        #expect(URLPolicy.verdict(for: url) == verdict)
    }

    // MARK: - Homographs

    /// A homograph host stays refused under every fusion, and whatever the
    /// rejection says it looks like is ASCII; the URL built on it gets the
    /// same verdict.
    @Test(arguments: ["\u{430}pple.com", "xn--pple-43d.com", "www.\u{430}pple.co.uk", "xn--80ak6aa92e.evil.com",
                      "\u{430}pple.\u{43C}\u{43E}\u{441}\u{43A}\u{432}\u{430}", "xn--pple-43d.xn--80adxhks"])
    func homographHostsStayRefusedAndNameASCII(plain: String) {
        #expect(!Confusables.domainVerdict(plain).isAccepted)
        for fusion in fusions(of: plain) {
            let verdict = Confusables.domainVerdict(fusion.text)
            #expect(!verdict.isAccepted, "\(fusion.name) in \(plain)")
            #expect(URLPolicy.verdict(for: "https://" + fusion.text + "/") == verdict, "\(fusion.name) in \(plain)")
            guard case .reject(let reason) = verdict, let named = lookAlike(in: reason) else { continue }
            #expect(named.allSatisfy { $0.isASCII }, "\(fusion.name) in \(plain): \(reason)")
        }
    }

    /// A Prepend letter is a letter: it starts or ends an honest decoded
    /// label (RFC 5891 forbids a leading mark; U+0D4E is Lo), keeps a
    /// homograph label from being one, and hides neither the dot after it
    /// nor the label before that dot. The number sign is a format control
    /// and refused as such.
    @Test func aPrependLetterIsALetter() {
        let apple = "\u{430}pple"
        #expect(Confusables.domainVerdict("xn--abc-wyk.com") == .warning("punycode host label"))
        #expect(Confusables.domainVerdict("xn--abc-zyk.com") == .warning("punycode host label"))
        #expect(Confusables.domainVerdict("xn--pple-43d221l.com") == .reject("mixed scripts in punycode label"))
        #expect(Confusables.domainVerdict(apple + "\u{D4E}.com") == .reject("non-ASCII host"))
        #expect(Confusables.domainVerdict("abc\u{D4E}.com") == .reject("non-ASCII host"))
        #expect(Confusables.homographSkeleton(apple + "\u{D4E}.com") == nil)
        #expect(Confusables.homographSkeleton(apple + ".\u{D4E}com") == "apple.\u{D4E}com")
        #expect(Confusables.domainVerdict(apple + ".\u{D4E}com") == .reject("label “\(apple)” looks like “apple”"))
        #expect(Confusables.domainVerdict(apple + "\u{D4E}.evil.com") == .reject("non-ASCII host"))
        #expect(Confusables.domainVerdict(apple + ".\u{600}com") == .reject("invisible character"))
        #expect(Confusables.domainVerdict(apple + "\u{600}.com") == .reject("invisible character"))
        #expect(FieldValidator.handle("user@\u{D4E}instance.social", limits: qr) == .reject("non-ASCII character"))
        #expect(FieldValidator.handle("user\u{D4E}@instance.social", limits: qr) == .reject("non-ASCII character"))
    }

    /// Scripts mix through a mark or a reph inside a word (both stay in
    /// the word), and not across a space. A ZWJ or a number sign inside a
    /// word never reaches the script rule: the scan refuses it first.
    @Test func scriptsMixThroughAMarkOrAReph() {
        let de = "\u{414}"
        #expect(Confusables.mixedScripts(in: de + "avid"))
        #expect(Confusables.mixedScripts(in: de + "\u{301}avid"))
        #expect(Confusables.mixedScripts(in: de + "\u{D4E}avid"))
        #expect(!Confusables.mixedScripts(in: "David \u{301}" + de + "\u{44D}\u{432}\u{438}\u{434}"))
        #expect(!Confusables.mixedScripts(in: "David\u{D4E} " + de))
        #expect(TextCheck.check(de + "\u{301}avid", maxBytes: 64) == .warning("mixed scripts"))
        #expect(TextCheck.check(de + "\u{D4E}avid", maxBytes: 64) == .warning("mixed scripts"))
        #expect(TextCheck.check(de + "\u{200D}avid", maxBytes: 64) == .reject("invisible character"))
        #expect(TextCheck.check(de + "\u{600}avid", maxBytes: 64) == .reject("invisible character"))
        #expect(TextCheck.check(de + "\u{FE0F}avid", maxBytes: 64) == .reject("invisible character"))
        #expect(TextCheck.check(de + "\u{E0041}avid", maxBytes: 64) == .reject("invisible character"))
    }

    // MARK: - Whitespace

    /// A mark or a reph beside a space leaves the space a space: a URL is
    /// refused for whitespace still, a name with an interior space keeps
    /// its verdict, a leading space is trimmed and the mark after it
    /// stays. After a trailing space the mark is the last scalar, so
    /// nothing trails and no warning is given, and a mark inside a run of
    /// spaces splits the run: pinned as design, since a floating accent
    /// draws, so nothing hides; the warnings are for what cannot be seen.
    @Test func aMarkBesideASpaceIsText() {
        for scalar in ["\u{301}", "\u{D4E}"] as [Unicode.Scalar] {
            #expect(URLPolicy.verdict(for: "https://example.com/a \(scalar)b") == .reject("whitespace"))
            #expect(URLPolicy.verdict(for: "https://example.com/a\(scalar) b") == .reject("whitespace"))
            #expect(URLPolicy.verdict(for: "mailto:a \(scalar)b@c.ie") == .reject("whitespace"))
            #expect(URLPolicy.verdict(for: "mailto:a%20\(scalar)b@c.ie") == .reject("whitespace"))
            #expect(TextCheck.check("David \(scalar)Emerson", maxBytes: 64) == .ok)
            #expect(TextCheck.check("David\(scalar) Emerson", maxBytes: 64) == .ok)
            #expect(TextCheck.check(" \(scalar)David", maxBytes: 64)
                == .warning("leading or trailing whitespace, use “\(scalar)David”"))
            #expect(TextCheck.check("David\(scalar) ", maxBytes: 64)
                == .warning("leading or trailing whitespace, use “David\(scalar)”"))
            #expect(TextCheck.check("David \(scalar)", maxBytes: 64) == .ok)
            #expect(TextCheck.check("a  \(scalar)  b", maxBytes: 64) == .ok)
        }
        #expect(TextCheck.check("a    b", maxBytes: 64) == .warning("run of spaces"))
        #expect(TextCheck.check(" \u{301} ", maxBytes: 64) == .reject("empty"))
        for scalar in fusing.dropFirst().prefix(3) {
            #expect(TextCheck.check(" \(scalar)", maxBytes: 64) == .reject("invisible character"), "\(hex(scalar))")
        }
        #expect(TextCheck.check("\u{600} ", maxBytes: 64) == .reject("invisible character"))
    }

    // MARK: - Octet caps

    /// Every cap counts UTF-8 bytes: one letter under two hundred acutes
    /// is one `Character` and 401 bytes, over every field cap, the host
    /// cap and, six times, the URL cap. At the boundary a 63-byte
    /// `Character` passes a 64-byte cap and a 65-byte one fails; a URL of
    /// 2,047 bytes passes and one of 2,049 fails. A local part of decoded
    /// marks is non-ASCII before it is long. An A-label is capped at 63
    /// bytes of punycode, whatever it decodes to: one letter and 55 acutes
    /// is one honest `Character`, a byte more is no label.
    @Test func capsCountBytesNotCharacters() {
        let marks = String(repeating: "\u{301}", count: 200)
        let zalgo = "a" + marks
        #expect(zalgo.count == 1)
        #expect(zalgo.utf8.count == 401)
        #expect(TextCheck.check(zalgo, maxBytes: 64) == .reject("over 64 bytes"))
        #expect(FieldValidator.name(zalgo, limits: qr) == .reject("over 64 bytes"))
        #expect(FieldValidator.company(zalgo, limits: qr) == .reject("over 64 bytes"))
        #expect(FieldValidator.customLabel(zalgo, limits: qr) == .reject("over 24 bytes"))
        #expect(FieldValidator.customValue(zalgo, kind: .text, limits: qr) == .reject("over 128 bytes"))
        #expect(FieldValidator.customValue(zalgo, kind: .key, limits: qr) == .reject("over 128 bytes"))
        #expect(FieldValidator.customValue("https://example.com/" + zalgo, kind: .url, limits: qr) == .reject("over 128 bytes"))
        #expect(FieldValidator.customValue(zalgo + "@b.com", kind: .email, limits: qr) == .reject("over 128 bytes"))
        #expect(FieldValidator.customValue("+1" + marks, kind: .phone, limits: qr) == .reject("over 128 bytes"))
        #expect(FieldValidator.email(zalgo + "@b.com", limits: qr) == .reject("over 254 bytes"))
        #expect(FieldValidator.phone("+1" + marks, limits: qr) == .reject("over 16 bytes"))
        #expect(FieldValidator.website(zalgo + ".com", limits: qr) == .reject("over 128 bytes"))
        #expect(FieldValidator.handle(zalgo, limits: qr) == .reject("over 64 bytes"))
        #expect(FieldValidator.signalURL("https://signal.me/#eu/" + zalgo, limits: qr) == .reject("over 128 bytes"))
        #expect(Confusables.domainVerdict(zalgo + ".com") == .reject("host over 253 bytes"))
        #expect(Confusables.domainVerdict("a" + String(repeating: "\u{301}", count: 100) + ".com") == .reject("non-ASCII host"))
        #expect(URLPolicy.verdict(for: "https://example.com/" + String(repeating: zalgo, count: 6)) == .reject("over 2048 bytes"))

        let sixtyThree = "a" + String(repeating: "\u{301}", count: 31)
        #expect(sixtyThree.count == 1 && sixtyThree.utf8.count == 63)
        #expect(TextCheck.check(sixtyThree, maxBytes: 64) == .ok)
        #expect(TextCheck.check(sixtyThree + "\u{301}", maxBytes: 64) == .reject("over 64 bytes"))
        #expect(FieldValidator.name(sixtyThree, limits: qr) == .ok)
        #expect(FieldValidator.name(sixtyThree + "\u{301}", limits: qr) == .reject("over 64 bytes"))

        let url = "https://example.com/a"
        #expect(URLPolicy.verdict(for: url + String(repeating: "\u{301}", count: 1013)) == .ok)
        #expect(URLPolicy.verdict(for: url + String(repeating: "\u{301}", count: 1014)) == .reject("over 2048 bytes"))

        let local = "mailto:a" + String(repeating: "%CC%81", count: 32) + "@b.com"
        #expect(URLPolicy.verdict(for: local) == .reject("non-ASCII character"))

        let acutes63 = "xn--a-xbb" + String(repeating: "a", count: 54)
        #expect(acutes63.utf8.count == 63)
        let decoded = Punycode.decode(Array(acutes63.utf8).dropFirst(4))
        #expect(decoded?.count == 1 && decoded?.unicodeScalars.count == 56)
        #expect(Confusables.domainVerdict(acutes63 + ".com") == .warning("punycode host label"))
        #expect(Confusables.domainVerdict(acutes63 + "a.com") == .reject("invalid host label"))
        #expect(Confusables.domainVerdict("xn--a-xbb" + String(repeating: "a", count: 199) + ".com") == .reject("invalid host label"))
        let umlauts63 = "xn--mnchen-3y" + String(repeating: "a", count: 50)
        #expect(umlauts63.utf8.count == 63)
        #expect(Confusables.domainVerdict(umlauts63 + ".de") == .warning("punycode host label"))
        #expect(Confusables.domainVerdict(umlauts63 + "a.de") == .reject("invalid host label"))
    }

    // MARK: - Case mapping

    /// Unicode case mapping changes the scalar count (`İ` to `i̇`, `ŉ` to
    /// `ʼN`, `ß` to `SS`) and folds look-alikes into ASCII (`ſ` to `S`,
    /// the Kelvin sign to `k`). Nothing in Validate maps the case of user
    /// text: a scheme, a mailto header name and the signal.me prefix are
    /// matched as ASCII bytes, so any of these letters in them is refused,
    /// named by its look-alike where the table has one.
    @Test func caseMappingIsASCIIOnly() {
        #expect("\u{130}".lowercased().unicodeScalars.count == 2)
        #expect("\u{149}".uppercased().unicodeScalars.count == 2)
        #expect("\u{DF}".uppercased() == "SS")
        #expect("\u{17F}".uppercased() == "S")
        #expect("\u{212A}".lowercased() == "k")

        #expect(URLPolicy.verdict(for: "MAILTO:a@b.ie") == .ok)
        #expect(URLPolicy.verdict(for: "MA\u{130}LTO:a@b.ie") == .reject("missing scheme"))
        #expect(URLPolicy.verdict(for: "HTTP\u{17F}://example.com/") == .reject("missing scheme"))
        #expect(URLPolicy.verdict(for: "\u{149}ttps://example.com/") == .reject("missing scheme"))
        #expect(URLPolicy.scheme(of: Array("MA\u{130}LTO:a@b".utf8)) == nil)
        #expect(URLPolicy.scheme(of: Array("MAILTO:a@b".utf8)) == "mailto")

        #expect(URLPolicy.verdict(for: "mailto:a@b.ie?SUBJECT=x&BODY=y") == .ok)
        #expect(URLPolicy.verdict(for: "mailto:a@b.ie?\u{17F}ubject=x") == .reject("mailto header not allowed"))
        #expect(URLPolicy.verdict(for: "mailto:a@b.ie?\u{DF}ody=x") == .reject("mailto header not allowed"))
        #expect(URLPolicy.verdict(for: "mailto:a@b.ie?\u{212A}=x") == .reject("mailto header not allowed"))

        let signal = "https://signal.me/#p/+15551234567"
        #expect(FieldValidator.signalURL("HTTPS://SIGNAL.ME/#p/+15551234567", limits: qr) == .ok)
        #expect(FieldValidator.signalURL("https://\u{17F}ignal.me/#p/+15551234567", limits: qr)
            == .reject("non-ASCII character, looks like “\(signal)”"))
        #expect(FieldValidator.signalURL("https://s\u{131}gnal.me/#p/+15551234567", limits: qr)
            == .reject("non-ASCII character, looks like “\(signal)”"))
        #expect(FieldValidator.signalURL("https://\u{DF}ignal.me/#p/+15551234567", limits: qr) == .reject("non-ASCII character"))

        #expect(Confusables.domainVerdict("\u{212A}.com") == .reject("non-ASCII host, looks like “K.com”"))
        #expect(Confusables.domainVerdict("\u{130}.com") == .reject("non-ASCII host"))
        #expect(Confusables.domainVerdict("XN--MNCHEN-3YA.DE") == .warning("punycode host label"))
        #expect(Confusables.domainVerdict("xn--MNCHEN-3YA.de") == .warning("punycode host label"))
        #expect(FieldValidator.email("FIRST.LAST@EXAMPLE.COM", limits: qr) == .ok)
        #expect(FieldValidator.email("f\u{130}rst@example.com", limits: qr) == .reject("non-ASCII character"))
        #expect(FieldValidator.handle("user@\u{130}nstance.social", limits: qr) == .reject("non-ASCII character"))
        #expect(FieldValidator.website("\u{DF}.example.com", limits: qr) == .reject("non-ASCII character"))
        #expect(FieldValidator.website("\u{149}.example.com", limits: qr) == .reject("non-ASCII character"))
    }
}
