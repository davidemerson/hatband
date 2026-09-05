import Testing
@testable import HatbandCore

// A systematic sweep of the interop entry points under the cluster shapes
// that fool `Character`. Every scalar boundary of a plain input (so every
// delimiter, space, hidden scalar and limit edge) is followed by U+0301,
// U+FE0F, U+200D or U+E0041 and preceded by U+0D4E or U+0600, and the
// outcome is held to the plain input's: refused, or accepted as the plain
// stored form with the visible scalar (a mark or a Prepend letter) kept in
// place. A hidden scalar never reaches a stored form and is never dropped
// from one.

private let ed1Base64 = "AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7"
private let ed1 = "ssh-ed25519 " + ed1Base64 + " ed1"
private let hex40 = "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"
private let signalUser = Base64.encode([UInt8](repeating: 0x5a, count: 48), url: true)

/// U+0301 fuses with the scalar before it; so do U+FE0F (a variation
/// selector, default ignorable), U+200D (ZWJ, format) and U+E0041 (a tag
/// letter, format). U+0D4E is a Prepend letter and fuses with the scalar
/// after it; U+0600 is Prepend and a format character.
private let followers: [Unicode.Scalar] = ["\u{301}", "\u{FE0F}", "\u{200D}", "\u{E0041}"]
private let prependers: [Unicode.Scalar] = ["\u{0D4E}", "\u{0600}"]
private let probes = followers + prependers
private let visible: Set<Unicode.Scalar> = ["\u{301}", "\u{0D4E}"]
private let reph = "\u{0D4E}"
private let mark = "\u{301}"

private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

private enum Outcome: Equatable {
    case accepted([UInt32])
    case refused

    init(_ body: () throws -> String) {
        do { self = .accepted(scalars(try body())) } catch { self = .refused }
    }
}

/// `plain` with `scalar` inserted before each of its scalars and after the last.
private func injections(of scalar: Unicode.Scalar, into plain: String) -> [String] {
    let all = Array(plain.unicodeScalars)
    return (0...all.count).map { i in
        var view = String.UnicodeScalarView()
        view.append(contentsOf: all[..<i])
        view.append(scalar)
        view.append(contentsOf: all[i...])
        return String(view)
    }
}

private enum Verdict: Equatable {
    /// The injected input was refused.
    case refused
    /// Accepted as the plain stored form with the scalar inserted once.
    case kept
    /// Accepted as exactly the plain stored form: the scalar vanished.
    case dropped
    /// Accepted as something else, or accepted where the plain input was refused.
    case other([UInt32])
}

private func judge(plain: Outcome, injected: Outcome, scalar: Unicode.Scalar) -> Verdict {
    switch (plain, injected) {
    case (_, .refused): return .refused
    case (.refused, .accepted(let s)): return .other(s)
    case (.accepted(let p), .accepted(let s)):
        if s == p { return .dropped }
        if let i = s.firstIndex(of: scalar.value) {
            var without = s
            without.remove(at: i)
            if without == p { return .kept }
        }
        return .other(s)
    }
}

/// Runs `normalize` over every injection of every probe into every plain
/// input. A visible scalar must be refused or kept in place; a hidden one
/// must be refused (the plain inputs carry no region that is discarded, so
/// a dropped hidden scalar would mean it was silently swallowed).
private func sweep(_ plains: [String], _ normalize: (String) throws -> String,
                   sourceLocation: SourceLocation = #_sourceLocation) {
    for plain in plains {
        precondition(!plain.unicodeScalars.contains(where: probes.contains), "plain inputs must not carry a probe")
        let expected = Outcome { try normalize(plain) }
        for scalar in probes {
            for input in injections(of: scalar, into: plain) {
                let verdict = judge(plain: expected, injected: Outcome { try normalize(input) }, scalar: scalar)
                let allowed: [Verdict] = visible.contains(scalar) ? [.refused, .kept] : [.refused]
                #expect(allowed.contains(verdict), "\(scalars(input)) -> \(verdict)", sourceLocation: sourceLocation)
            }
        }
    }
}

/// Two scalars around one scalar of the plain input: a Prepend letter
/// before it and a mark after it (both visible, so the pair is refused or
/// kept whole), or a hidden scalar on either side of a visible one (always
/// refused, whichever side the hidden scalar fuses with).
private let sandwiches: [(before: Unicode.Scalar, after: Unicode.Scalar, visible: Bool)] = [
    ("\u{0D4E}", "\u{301}", true), ("\u{200B}", "\u{301}", false), ("\u{0D4E}", "\u{200B}", false),
    ("\u{0600}", "\u{301}", false), ("\u{0D4E}", "\u{FE0F}", false), ("\u{0D4E}", "\u{E0041}", false),
]

private func sandwichSweep(_ plains: [String], _ normalize: (String) throws -> String,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    for plain in plains {
        let expected = Outcome { try normalize(plain) }
        let all = Array(plain.unicodeScalars)
        for (before, after, visible) in sandwiches {
            for i in all.indices {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: all[..<i])
                view.append(before)
                view.append(all[i])
                view.append(after)
                view.append(contentsOf: all[(i + 1)...])
                let input = String(view)
                let outcome = Outcome { try normalize(input) }
                // Judge the pair by removing both scalars once.
                let verdict: Verdict
                switch (expected, outcome) {
                case (_, .refused): verdict = .refused
                case (.refused, .accepted(let s)): verdict = .other(s)
                case (.accepted(let p), .accepted(let s)):
                    var without = s
                    if let b = without.firstIndex(of: before.value) { without.remove(at: b) }
                    if let a = without.firstIndex(of: after.value) { without.remove(at: a) }
                    verdict = s == p ? .dropped : without == p && s.count == p.count + 2 ? .kept : .other(s)
                }
                let allowed: [Verdict] = visible ? [.refused, .kept] : [.refused]
                #expect(allowed.contains(verdict), "\(scalars(input)) -> \(verdict)", sourceLocation: sourceLocation)
            }
        }
    }
}

// MARK: - Normalizers

@Test func phoneSweep() throws {
    sweep(["+353871234567", "+353 87 123 4567", "tel:+353-87-123-4567", "TEL:+1 (415) 555-2671", "+353.87.123.4567"]) { try Normalize.phone($0) }
    sandwichSweep(["+353 87 123 4567", "tel:+353-87-123-4567"]) { try Normalize.phone($0) }
    // Every probe between the plus and the first digit, and after the last digit, is refused by name.
    for scalar in probes {
        #expect(throws: Normalize.Error.self) { try Normalize.phone("+\(scalar)353871234567") }
        #expect(throws: Normalize.Error.self) { try Normalize.phone("+353871234567\(scalar)") }
        #expect(throws: Normalize.Error.self) { try Normalize.phone("\(scalar)+353871234567") }
    }
}

@Test func emailSweep() throws {
    sweep(["bloom@nnix.com", "mailto:bloom@nnix.com", "MAILTO:Bloom@NNIX.com", "a.b+c@nnix.ie", "mailto:a%2Bb@x.ie"]) { try Normalize.email($0) }
    sandwichSweep(["bloom@nnix.com", "mailto:a%2Bb@x.ie"]) { try Normalize.email($0) }
    // The display name and the query are discarded wholesale, probes and all.
    for scalar in probes {
        #expect(try Normalize.email("Leo\(scalar)pold \(scalar)<bloom@nnix.com>") == "bloom@nnix.com")
        #expect(try Normalize.email("mailto:bloom@nnix.com?subject=\(scalar)x") == "bloom@nnix.com")
        // But a probe after the closing angle bracket, or before the query, is content.
        #expect(throws: Normalize.Error.self) { try Normalize.email("Leopold <bloom@nnix.com>\(scalar)") }
        #expect(throws: Normalize.Error.self) { try Normalize.email("mailto:bloom@nnix.com\(scalar)?subject=x") }
    }
}

@Test func websiteSweep() throws {
    sweep(["nnix.com", "NNIX.com/Path", "https://nnix.com:8080/p?q=1#f", "http://nnix.com", "//nnix.com/x",
           "nnix.com/a/b%20c", "МОСКВА.РФ", "bücher.de", "xn--bcher-kva.de", "a.b.c.d.ie", "1-2.com"]) { try Normalize.website($0).address }
    sandwichSweep(["nnix.com", "https://nnix.com:8080/p?q=1#f", "//NNIX.com/x", "МОСКВА.РФ"]) { try Normalize.website($0).address }
    // The trailing dot is dropped from the plain form; a probe after it is either refused or a one-letter label.
    for scalar in followers + ["\u{0600}"] {
        #expect(throws: Normalize.Error.self) { try Normalize.website("nnix.com.\(scalar)") }
    }
    #expect(try Normalize.website("nnix.com.\(reph)").address == "nnix.com.\(reph)")
}

@Test func githubSweep() throws {
    sweep(["bloom", "@bloom", "github.com/bloom", "https://github.com/bloom", "HTTPS://WWW.GITHUB.COM/Bloom", "b-l-o-o-m1"]) { try Normalize.github($0) }
    sandwichSweep(["@bloom", "https://github.com/bloom"]) { try Normalize.github($0) }
    // Segments after the first are discarded, probes and all; the query too.
    for scalar in probes {
        #expect(try Normalize.github("https://github.com/bloom/\(scalar)repo") == "bloom")
        #expect(try Normalize.github("https://github.com/bloom?\(scalar)") == "bloom")
        #expect(throws: Normalize.Error.self) { try Normalize.github("https://github.com/bloom\(scalar)/repo") }
    }
}

@Test func linkedinSweep() throws {
    sweep(["bloom", "@bloom", "in/bloom", "IN/Bloom", "company/acme", "mwlite/in/bloom", "https://linkedin.com/in/bloom",
           "https://linkedin.com/company/acme", "http://linkedin.com/mwlite/in/bloom", "in/bl%C3%BCm", "https://linkedin.com/in/bl%C3%BCm"]) { try Normalize.linkedin($0) }
    sandwichSweep(["in/bloom", "https://linkedin.com/company/acme", "mwlite/in/bloom"]) { try Normalize.linkedin($0) }
    // Percent-encoded probes land in the decoded slug and are judged there.
    for scalar in probes {
        let encoded = scalar.utf8.map { "%" + Hex.pair($0) }.joined()
        let verdict = judge(plain: .accepted(scalars("bloom")), injected: Outcome { try Normalize.linkedin("in/bl\(encoded)oom") }, scalar: scalar)
        #expect(visible.contains(scalar) ? verdict == .kept : verdict == .refused, "\(scalars(encoded)) -> \(verdict)")
        #expect(throws: Normalize.Error.self) { try Normalize.linkedin("in/\(encoded)%2Fbloom") }
        #expect(throws: Normalize.Error.self) { try Normalize.linkedin("in/bloom%2F\(encoded)") }
    }
    // Everything a stored slug can carry survives its own canonical URI.
    for slug in ["bl\(reph)oom", "e\(mark)amonn", "\(reph)bloom", "company/a\(mark)cme", "İstanbul", "straße", "ŉab"] {
        let stored = try? Normalize.linkedin(slug)
        #expect(stored == slug, "\(scalars(slug))")
        #expect((try? Normalize.linkedin(CanonicalURI.linkedin(slug))) == slug, "\(scalars(slug))")
    }
}

@Test func mastodonSweep() throws {
    sweep(["bloom@nnix.com", "@bloom@nnix.com", "https://nnix.com/@bloom", "https://nnix.com/users/bloom", "nnix.com/@bloom",
           "https://nnix.com/@bloom/", "bloom@МОСКВА.РФ", "b_loom@a.b.ie"]) { try Normalize.mastodon($0) }
    sandwichSweep(["@bloom@nnix.com", "https://nnix.com/@bloom", "nnix.com/users/bloom"]) { try Normalize.mastodon($0) }
    // The canonical URIs of kept forms split at the last `@` scalar.
    let canonical = CanonicalURI.mastodon("bloom@nn\(reph)ix.co\(mark)m")
    #expect(canonical?.account == "acct:bloom@nn\(reph)ix.co\(mark)m")
    #expect(canonical?.profile == "https://nn\(reph)ix.co\(mark)m/@bloom")
}

@Test func calendlySweep() throws {
    sweep(["bloom", "bloom/coffee", "calendly.com/bloom", "https://calendly.com/bloom/coffee", "d/abc-123/slug_x",
           "www.calendly.com/bloom", "CALENDLY.COM/Bloom"]) { try Normalize.calendly($0) }
    sandwichSweep(["bloom/coffee", "https://calendly.com/bloom/coffee"]) { try Normalize.calendly($0) }
    for scalar in probes {
        #expect(try Normalize.calendly("https://calendly.com/bloom?month=\(scalar)") == "bloom")
        #expect(throws: Normalize.Error.self) { try Normalize.calendly("https://calendly.com/bloom\(scalar)?month=x") }
    }
}

@Test func gpgFingerprintSweep() throws {
    sweep([hex40, "EF6E 286D DA85 EA2A 4BA7  DE68 4E2C 6E87 9329 8290", "0x" + hex40, "OPENPGP4FPR:" + hex40, "openpgp4fpr: 0x" + hex40.lowercased(),
           "EF:6E:28:6D:DA:85:EA:2A:4B:A7:DE:68:4E:2C:6E:87:93:29:82:90"]) { try Normalize.gpgFingerprint($0).hex }
    sandwichSweep(["OPENPGP4FPR:0x" + hex40, "EF6E 286D DA85 EA2A 4BA7  DE68 4E2C 6E87 9329 8290"]) { try Normalize.gpgFingerprint($0).hex }
}

@Test func signalSweep() throws {
    sweep(["https://signal.me/#eu/" + signalUser, "sgnl://signal.me/#eu/" + signalUser, "signal.me/#eu/" + signalUser,
           "https://signal.me/#p/+353871234567", "SIGNAL.ME/#p/+353871234567"]) { try SignalLink.parse($0).url }
    sandwichSweep(["sgnl://signal.me/#eu/" + signalUser, "signal.me/#p/+353871234567"]) { try SignalLink.parse($0).url }
}

// MARK: - SSH

/// The type and key fields refuse every probe; the comment keeps every
/// probe verbatim, hidden or not, since it is free text and not stored.
@Test func sshLineSweep() throws {
    sweep(["ssh-ed25519 " + ed1Base64, "ssh-ed25519\t" + ed1Base64, "  ssh-ed25519 \t " + ed1Base64]) {
        let key = try SSHPublicKey(line: $0)
        return Hex.encode(key.blob) + "|" + (key.comment ?? "")
    }
    let key = try SSHPublicKey(line: ed1)
    let commentStart = ed1.unicodeScalars.count - 3
    for scalar in probes {
        for (offset, input) in injections(of: scalar, into: ed1).enumerated() {
            if offset >= commentStart {
                let parsed = try SSHPublicKey(line: input)
                var comment = "ed1".unicodeScalars
                comment.insert(scalar, at: comment.index(comment.startIndex, offsetBy: offset - commentStart))
                #expect(parsed.blob == key.blob && parsed.comment.map(scalars) == scalars(String(comment)), "\(scalars(input))")
                #expect(try SSHPublicKey(line: parsed.authorizedKeysLine()) == parsed, "\(scalars(input))")
            } else {
                #expect(throws: SSHPublicKey.Error.self, "\(scalars(input))") { try SSHPublicKey(line: input) }
            }
        }
    }
}

/// An allowed_signers entry stays four fields whatever the principal and
/// namespace carry: no field separator, comma, quote, backslash, control or
/// line break survives in them, and the key still reads back.
@Test func allowedSignersSweep() throws {
    let key = try SSHPublicKey(line: ed1)
    let hostile = "bl,oom\"@nn\\ix.com \t\r\n\u{85}\u{2028}#x"
    let principalSeparators: Set<Unicode.Scalar> = [",", "\"", "\\", "\u{2028}", "\u{2029}"]
    for scalar in probes {
        for injected in injections(of: scalar, into: hostile) {
            for (principal, namespace) in [(injected, "git"), ("bloom@nnix.com", injected), (injected, injected)] {
                let line = key.allowedSignersLine(principal: principal, namespace: namespace)
                let fields = line.unicodeScalars.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { String($0) }
                #expect(fields.count == 4, "\(scalars(line))")
                #expect(!fields[0].unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.isControl || principalSeparators.contains($0) }))
                #expect(fields[0].unicodeScalars.first != "#")
                #expect(fields[1].starts(withScalars: "namespaces=\"") && fields[1].unicodeScalars.last == "\"")
                #expect(!fields[1].unicodeScalars.dropFirst(12).dropLast().contains(where: { $0 == "\"" || $0 == "\\" || $0.properties.isWhitespace || $0.isControl }))
                #expect(try SSHPublicKey(line: fields[2] + " " + fields[3]).blob == key.blob)
            }
        }
    }
    // A visible probe is kept in both fields; a hidden one too, since sshsig
    // reads them byte by byte and neither is a separator there.
    for scalar in probes {
        let line = key.allowedSignersLine(principal: "bl\(scalar)oom@nnix.com", namespace: "gi\(scalar)t")
        #expect(line == "bl\(scalar)oom@nnix.com namespaces=\"gi\(scalar)t\" ssh-ed25519 " + ed1Base64)
    }
}

// MARK: - vCard

/// Every field round-trips scalar for scalar through `text` and
/// `parseBasic`, with a probe at every position of a value that already
/// exercises escaping, line breaks and a fold.
@Test func vCardRoundTripSweep() throws {
    let base = "Leo;pold, Bloom\\ 7\r\nEccles\tSt" + String(repeating: "é", count: 40)
    for scalar in probes {
        for value in injections(of: scalar, into: base) {
            var card = VCard(formattedName: value, familyName: value, givenName: value)
            card.organization = value
            card.phone = value
            card.email = value
            card.note = value
            card.links = [VCard.Link(label: value, url: value)]
            card.extensions = [VCard.Extension(name: "k", value: value)]
            let parsed = try VCard.parseBasic(card.text)
            let expected = scalars(value.replacingLineBreaks())
            for (field, got) in [("FN", parsed.formattedName), ("family", parsed.familyName), ("given", parsed.givenName),
                                 ("ORG", parsed.organization ?? ""), ("TEL", parsed.phone ?? ""), ("EMAIL", parsed.email ?? ""),
                                 ("NOTE", parsed.note ?? ""), ("label", parsed.links.first?.label ?? ""), ("url", parsed.links.first?.url ?? ""),
                                 ("ext", parsed.extensions.first?.value ?? "")] {
                #expect(scalars(got) == expected, "\(field) \(scalars(value))")
            }
            #expect(parsed.extensions.first?.name == "K")
            for line in card.text.unicodeScalars.split(separator: "\n").map({ Substring($0) }) {
                #expect(line.utf8.count <= VCard.foldWidth + 1, "\(scalars(String(line)))")
            }
        }
    }
}

/// A fold lands on every side of every probe.
@Test func vCardFoldsAroundProbes() throws {
    for scalar in probes {
        for pad in 60...78 {
            var card = VCard(formattedName: "x")
            card.note = String(repeating: "a", count: pad) + String(scalar) + "b" + String(scalar)
            #expect(scalars(try VCard.parseBasic(card.text).note ?? "") == scalars(card.note!), "\(scalar.value) at \(pad)")
        }
    }
}

/// Probes on the structural scalars of a parsed card: the frame, the
/// property name, the colon, a parameter, a component separator, a fold.
@Test func vCardStructureSweep() throws {
    func card(_ lines: [String]) throws -> VCard {
        try VCard.parseBasic((["BEGIN:VCARD", "VERSION:3.0"] + lines + ["END:VCARD"]).map { $0 + "\r\n" }.joined())
    }
    for scalar in probes {
        let s = String(scalar)
        #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("BEGIN:VCARD\(s)\r\nVERSION:3.0\r\nEND:VCARD\r\n") }
        #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("\(s)BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\n") }
        #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\(s)\r\n") }
        #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("BEGIN\(s):VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\n") }
        #expect(throws: VCard.Error.unsupportedVersion("\(s)3.0")) { try card(["VERSION:\(s)3.0"]) }
        // A value begins right after the colon scalar.
        #expect(scalars(try card(["FN:\(s)x"]).formattedName) == scalars("\(s)x"))
        // A name with a probe is another property, skipped without error.
        #expect(try card(["FN\(s):x", "FN:y"]).formattedName == "y")
        #expect(try card(["FN\(s):x"]).formattedName == "")
        // A parameter with a probe is still a parameter of TEL.
        #expect(try card(["TEL;TYPE=CELL\(s):+353871234567"]).phone == "+353871234567")
        #expect(try card(["TEL;\(s)TYPE=CELL:+353871234567"]).phone == "+353871234567")
        // Components split on the `;` scalar; a probe starts the next one.
        let named = try card(["N:Bloom;\(s)Leopold;;;"])
        #expect(named.familyName == "Bloom" && scalars(named.givenName) == scalars("\(s)Leopold"))
        let escaped = try card(["N:Bloom\\;\(s)Leopold"])
        #expect(scalars(escaped.familyName) == scalars("Bloom;\(s)Leopold") && escaped.givenName == "")
        // A fold continues at the space scalar; a probe before the space is a new, malformed line.
        #expect(scalars(try card(["NOTE:ab", " \(s)cd"]).note ?? "") == scalars("ab\(s)cd"))
        #expect(throws: VCard.Error.malformedLine("\(s) cd")) { try card(["NOTE:ab", "\(s) cd"]) }
        // The group ends at the dot scalar; the pair only matches when both carry the probe.
        let linked = try card(["item1\(s).URL:https://nnix.com", "item1\(s).X-ABLabel:Web", "item2.URL:https://x.ie", "item2\(s).X-ABLabel:No"])
        #expect(linked.links == [VCard.Link(label: "Web", url: "https://nnix.com"), VCard.Link(label: "", url: "https://x.ie")])
        // A photo's base64 refuses the probe; VALUE=URI with a probe is not VALUE=URI, so the data is read.
        #expect(try card(["PHOTO;ENCODING=b;TYPE=JPEG:AAEC\(s)Aw=="]).photoJPEG == nil)
        #expect(try card(["PHOTO;VALUE=URI\(s):AAECAw=="]).photoJPEG == [0, 1, 2, 3])
        #expect(try card(["PHOTO;VALUE=URI:AAECAw=="]).photoJPEG == nil)
        // Extension names are reduced to ASCII; the value keeps the probe.
        let extended = try card(["X-HATBAND-K\(s)EY:v\(s)"])
        #expect(extended.extensions.map(\.name) == ["KEY"] && extended.extensions.map { scalars($0.value) } == [scalars("v\(s)")])
    }
}

@Test func vCardNameSplitSweep() throws {
    for scalar in probes {
        let s = String(scalar)
        let card = VCard(formattedName: "Leopold\(s) \(s)Bloom")
        #expect(scalars(card.givenName) == scalars("Leopold\(s)") && scalars(card.familyName) == scalars("\(s)Bloom"))
        #expect(scalars(VCard(formattedName: "\(s) Bloom").givenName) == scalars(s))
        #expect(scalars(VCard(formattedName: "Bloom \(s)").familyName) == scalars(s))
    }
}

// MARK: - Limits in octets, scalars and marks

/// Two hundred marks on one letter overrun every bounded field.
@Test func twoHundredMarksOverrunEveryLimit() throws {
    let heavy = "a" + String(repeating: mark, count: 200)
    #expect(heavy.count == 1 && heavy.utf8.count == 401)
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(heavy + ".com") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("nnix." + heavy) }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.mastodon("bloom@" + heavy + ".com") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.mastodon("https://" + heavy + ".com/@bloom") }
    #expect(throws: Normalize.Error.invalidUsername) { try Normalize.mastodon(heavy + "@nnix.com") }
    #expect(throws: Normalize.Error.tooLong) { try Normalize.linkedin(heavy) }
    #expect(throws: Normalize.Error.tooLong) { try Normalize.linkedin("in/" + heavy) }
    #expect(throws: Normalize.Error.tooLong) { try Normalize.github(heavy) }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.calendly(heavy) }
    #expect(throws: Normalize.Error.self) { try Normalize.email(heavy + "@nnix.com") }
    #expect(throws: Normalize.Error.self) { try Normalize.phone("+353" + heavy) }
    #expect(throws: Normalize.Error.self) { try Normalize.gpgFingerprint(heavy + hex40) }
    #expect(throws: Normalize.Error.self) { try SignalLink.parse("https://signal.me/#eu/" + heavy) }
    #expect(throws: Normalize.Error.self) { try Normalize.website("nnix.com/" + heavy) }
    #expect(Hostname.normalized(Substring(heavy + ".com")) == nil)
    #expect(Hostname.normalized(Substring("nnix." + heavy)) == nil)
    // Where marks are content they are kept whole.
    #expect((try? SSHPublicKey(line: ed1 + heavy))?.comment.map(scalars) == scalars("ed1" + heavy))
    #expect(scalars((try? VCard.parseBasic(VCard(formattedName: heavy).text))?.formattedName ?? "") == scalars(heavy))
    // Thirty-one marks fit a label at 63 octets; thirty-two do not. A Prepend letter is three octets.
    #expect(Hostname.normalized(Substring("a" + String(repeating: mark, count: 31) + ".com")) != nil)
    #expect(Hostname.normalized(Substring("a" + String(repeating: mark, count: 32) + ".com")) == nil)
    #expect(Hostname.normalized(Substring(String(repeating: "a", count: 61) + mark + ".com")) != nil)
    #expect(Hostname.normalized(Substring(String(repeating: "a", count: 62) + mark + ".com")) == nil)
    #expect(Hostname.normalized(Substring(String(repeating: "a", count: 60) + reph + ".com")) != nil)
    #expect(Hostname.normalized(Substring(String(repeating: "a", count: 61) + reph + ".com")) == nil)
}

/// The 253-octet host limit counts the stored form: a mark or a Prepend
/// letter at the edge tips it, and so does one more ASCII letter.
@Test func hostLimitCountsStoredOctets() throws {
    let label = String(repeating: "a", count: 63)
    let host = [label, label, label, String(repeating: "a", count: 61)].joined(separator: ".")
    #expect(host.utf8.count == 253)
    #expect(Hostname.normalized(Substring(host)) == host)
    #expect(Hostname.normalized(Substring(host + "a")) == nil)
    #expect(Hostname.normalized(Substring(host + mark)) == nil)
    #expect(Hostname.normalized(Substring(host + reph)) == nil)
    #expect(Hostname.normalized(Substring(reph + host)) == nil)
    let shorter = [label, label, label, String(repeating: "a", count: 59)].joined(separator: ".")
    #expect(Hostname.normalized(Substring(shorter + mark)) == shorter + mark)
    #expect(Hostname.normalized(Substring(shorter + "a" + mark)) == nil)
    #expect(Hostname.normalized(Substring(String(shorter.dropLast()) + reph)) == String(shorter.dropLast()) + reph)
    #expect(Hostname.normalized(Substring(shorter + reph)) == nil)
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(host + mark) }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.mastodon("bloom@" + host + mark) }
    #expect(try Normalize.website(shorter + mark).address == shorter + mark)
}

/// Each ASCII-only field's limit counts scalars, which are octets there;
/// a probe at the edge is refused, never counted or ignored.
@Test func asciiFieldLimitsAtTheEdge() throws {
    let local64 = String(repeating: "a", count: 64)
    #expect(try Normalize.email(local64 + "@nnix.com") == local64 + "@nnix.com")
    #expect(throws: Normalize.Error.invalidLocalPart) { try Normalize.email(local64 + "a@nnix.com") }
    let host189 = [String(repeating: "b", count: 63), String(repeating: "b", count: 63), String(repeating: "b", count: 61)].joined(separator: ".")
    #expect((local64 + "@" + host189).utf8.count == 254)
    #expect(try Normalize.email(local64 + "@" + host189) == local64 + "@" + host189)
    #expect(throws: Normalize.Error.tooLong) { try Normalize.email(local64 + "@" + host189 + "b") }
    #expect(try Normalize.phone("+" + String(repeating: "1", count: 15)) == "+" + String(repeating: "1", count: 15))
    #expect(throws: Normalize.Error.tooLong) { try Normalize.phone("+" + String(repeating: "1", count: 16)) }
    #expect(try Normalize.phone("+12345678") == "+12345678")
    #expect(throws: Normalize.Error.tooShort) { try Normalize.phone("+1234567") }
    #expect(try Normalize.github(String(repeating: "a", count: 39)) == String(repeating: "a", count: 39))
    #expect(throws: Normalize.Error.tooLong) { try Normalize.github(String(repeating: "a", count: 40)) }
    #expect(try Normalize.mastodon(String(repeating: "a", count: 30) + "@nnix.com") == String(repeating: "a", count: 30) + "@nnix.com")
    #expect(throws: Normalize.Error.invalidUsername) { try Normalize.mastodon(String(repeating: "a", count: 31) + "@nnix.com") }
    #expect(try Normalize.calendly(String(repeating: "a", count: 64)) == String(repeating: "a", count: 64))
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.calendly(String(repeating: "a", count: 65)) }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.calendly("a/b/c/d") }
    #expect(try Normalize.linkedin(String(repeating: "a", count: 100)) == String(repeating: "a", count: 100))
    #expect(throws: Normalize.Error.tooLong) { try Normalize.linkedin(String(repeating: "a", count: 101)) }
    for scalar in probes {
        let s = String(scalar)
        #expect(throws: Normalize.Error.self, "\(scalar.value)") { try Normalize.email(String(repeating: "a", count: 63) + s + "@nnix.com") }
        #expect(throws: Normalize.Error.self, "\(scalar.value)") { try Normalize.phone("+" + String(repeating: "1", count: 14) + s) }
        #expect(throws: Normalize.Error.self, "\(scalar.value)") { try Normalize.github(String(repeating: "a", count: 38) + s) }
        #expect(throws: Normalize.Error.self, "\(scalar.value)") { try Normalize.mastodon(String(repeating: "a", count: 29) + s + "@nnix.com") }
        #expect(throws: Normalize.Error.self, "\(scalar.value)") { try Normalize.calendly(String(repeating: "a", count: 63) + s) }
        #expect(throws: Normalize.Error.self, "\(scalar.value)") { try Normalize.calendly("a/b/c/" + s) }
        // The linkedin limit is one hundred scalars; the two visible probes are slug scalars.
        let verdict = judge(plain: .accepted(scalars(String(repeating: "a", count: 99))),
                            injected: Outcome { try Normalize.linkedin(String(repeating: "a", count: 99) + s) }, scalar: scalar)
        #expect(visible.contains(scalar) ? verdict == .kept : verdict == .refused, "\(scalar.value) -> \(verdict)")
        #expect(throws: Normalize.Error.tooLong, "\(scalar.value)") { try Normalize.linkedin(String(repeating: "a", count: 100) + s) }
    }
}

// MARK: - Case mapping that changes the scalar count

private let caseShifters = ["İ", "ß", "ŉ", "ǰ", "ﬁ", "ẞ", "\u{212A}", "\u{2126}", "ſ", "Σ", "ΐ", "Ǆ", "ǅ"]

/// Hosts lowercase scalar by scalar and only when the result is one scalar,
/// so the stored form never grows, is stable under a second pass, and the
/// octet limit counts what is stored.
@Test func hostCaseMappingKeepsScalarCount() throws {
    for letter in caseShifters {
        let input = "x\(letter)y.com"
        let stored = try Normalize.website(input).address
        #expect(scalars(stored).count == scalars(input).count, "\(scalars(input)) -> \(scalars(stored))")
        #expect(try Normalize.website(stored).address == stored, "\(scalars(input))")
        #expect(try Normalize.mastodon("bloom@" + input) == "bloom@" + stored, "\(scalars(input))")
        #expect(try Normalize.website(CanonicalURI.website(stored)).address == stored)
        #expect(throws: Normalize.Error.self, "\(scalars(input))") { try Normalize.email("bloom@" + input) }
        #expect(throws: Normalize.Error.self, "\(scalars(input))") { try Normalize.github(letter + "ab") }
        #expect(throws: Normalize.Error.self, "\(scalars(input))") { try Normalize.calendly(letter + "ab") }
        #expect(throws: Normalize.Error.self, "\(scalars(input))") { try Normalize.mastodon(letter + "ab@nnix.com") }
        // Slugs keep their case, so they store exactly what was typed.
        #expect(try Normalize.linkedin(letter + "ab") == letter + "ab")
    }
    #expect(try Normalize.website("İstanbul.com").address == "İstanbul.com")
    #expect(try Normalize.website("straẞe.de").address == "straße.de")
    #expect(try Normalize.website("\u{2126}mega.gr").address == "\u{3C9}mega.gr")
    #expect(try Normalize.website("ΟΔΥΣΣΕΥΣ.gr").address == "οδυσσευσ.gr")
    // The label limit is met by the stored form: sixty-three Kelvin signs store as sixty-three `k`s.
    #expect(try Normalize.website(String(repeating: "\u{212A}", count: 63) + ".com").address == String(repeating: "k", count: 63) + ".com")
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(String(repeating: "\u{212A}", count: 64) + ".com") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website(String(repeating: "İ", count: 32) + ".com") }
    #expect(try Normalize.website(String(repeating: "İ", count: 31) + ".com").address == String(repeating: "İ", count: 31) + ".com")
}

/// Keywords fold ASCII case only: no case shifter reaches a scheme, a host
/// name, a route word, a type name or a property name.
@Test func keywordsFoldASCIIOnly() throws {
    #expect(throws: Normalize.Error.self) { try Normalize.website("HTTPſ://nnix.com") }
    #expect(throws: Normalize.Error.wrongHost("\u{212A}elvin:")) { try Normalize.github("\u{212A}elvin://github.com/bloom") }
    #expect(throws: Normalize.Error.self) { try Normalize.linkedin("ı\u{307}n/bloom") }
    #expect(throws: Normalize.Error.self) { try Normalize.linkedin("İN/bloom") }
    #expect(throws: Normalize.Error.invalidPath) { try Normalize.mastodon("https://nnix.com/USERS/bloom") }
    #expect(throws: Normalize.Error.self) { try Normalize.calendly("CALENDLY.COM/bloom/ſ") }
    #expect(throws: Normalize.Error.wrongHost("ſignal.me")) { try SignalLink.parse("https://ſignal.me/#p/+353871234567") }
    #expect(throws: SSHPublicKey.Error.unsupportedType("SSH-ED25519")) { try SSHPublicKey(line: "SSH-ED25519 " + ed1Base64) }
    #expect(throws: SSHPublicKey.Error.unsupportedType("ssh-ed25519\u{212A}")) { try SSHPublicKey(line: "ssh-ed25519\u{212A} " + ed1Base64) }
    #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("BEGİN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\n") }
    #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0\r\nſND:VCARD\r\n") }
    for letter in caseShifters {
        let name = VCard.propertyName(letter + "-k")
        #expect(name.unicodeScalars.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" }, "\(scalars(letter)) -> \(scalars(name))")
    }
}

// MARK: - Errors name the grapheme, and never trap

/// The `invalidCharacter` payload is the grapheme holding the offending
/// scalar even when that grapheme straddles the start of a sliced input.
@Test func errorGraphemesAtSliceBoundaries() throws {
    #expect(throws: Normalize.Error.invalidCharacter(Character(mark))) { try Normalize.phone("tel:\(mark)+353871234567") }
    #expect(throws: Normalize.Error.invalidCharacter(Character(mark))) { try Normalize.phone("\(mark)+353871234567") }
    #expect(throws: Normalize.Error.invalidCharacter(Character(mark))) { try Normalize.email("mailto:\(mark)bloom@nnix.com") }
    #expect(throws: Normalize.Error.invalidCharacter(Character(mark))) { try Normalize.email("<\(mark)bloom@nnix.com>") }
    #expect(throws: Normalize.Error.invalidCharacter(Character(mark))) { try Normalize.gpgFingerprint("0x\(mark)" + hex40) }
    #expect(throws: Normalize.Error.invalidCharacter(Character("/\(mark)"))) { try Normalize.website("nnix.com/\(mark)") }
    #expect(throws: Normalize.Error.invalidCharacter(Character(" \(mark)"))) { try Normalize.website("nnix.com \(mark)") }
    #expect(throws: Normalize.Error.invalidCharacter(Character("\(reph)\u{200D}"))) { try Normalize.website("nnix.com/\(reph)\u{200D}") }
    #expect(throws: Normalize.Error.invalidCharacter(Character(mark))) { try SignalLink.parse("sgnl://signal.me/#p/\(mark)+353871234567") }
}

private extension String {
    /// What `VCard.escape` makes of a line break, for comparing round trips.
    func replacingLineBreaks() -> String {
        var out = ""
        var previous: Unicode.Scalar = " "
        for scalar in unicodeScalars {
            switch scalar {
            case "\n" where previous == "\r": break
            case "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}": out.unicodeScalars.append("\n")
            default: out.unicodeScalars.append(scalar)
            }
            previous = scalar
        }
        return out
    }
}

// MARK: - Observations, pinned

/// Scalar-correct per RFC 5891 §4.2.3.1 and the digit rule, and so
/// accepted: a mark after a trailing hyphen or after an all-digit last label
/// makes a label that neither ends with a hyphen nor is all digits. The
/// plain spellings are refused. Both are valid U-labels; whether a mark
/// that hides a hyphen or a number should be judged is `Validate`'s
/// look-alike verdict, and this records the interop layer's answer.
@Test func marksAfterHyphenOrDigitsMakeAnotherLabel() throws {
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("nnix.com-") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("nnix.1") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("1.2.3.4") }
    #expect(try Normalize.website("nnix.com-\(mark)").address == "nnix.com-\(mark)")
    #expect(try Normalize.website("nnix.1\(mark)").address == "nnix.1\(mark)")
    #expect(try Normalize.website("1.2.3.4\(mark)").address == "1.2.3.4\(mark)")
    // The Prepend letter is a letter, so the same holds for it, as for any letter.
    #expect(try Normalize.website("nnix.1\(reph)").address == "nnix.1\(reph)")
    // A hyphen after a leading mark is still refused, in that order.
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("nnix.\(mark)-com") }
    #expect(throws: Normalize.Error.invalidHost) { try Normalize.website("nnix.-\(mark)com") }
}

/// `Pasted(hosts:subdomains:)` matches the suffix and discards whatever
/// precedes `.linkedin.com` without judging it as a hostname, so a probe
/// there vanishes with the subdomain. Only the slug is stored, so nothing
/// hidden reaches the card; recorded as the one place a hidden scalar is
/// dropped from an accepted URL.
@Test func linkedinSubdomainsAreDiscardedUnjudged() throws {
    for scalar in probes {
        #expect(try Normalize.linkedin("https://ie\(scalar).linkedin.com/in/bloom") == "bloom")
        #expect(try Normalize.linkedin("https://\(scalar).linkedin.com/in/bloom") == "bloom")
    }
    #expect(try Normalize.linkedin("https://a b.linkedin.com/in/bloom") == "bloom")
    // The apex and the slug are still judged scalar by scalar.
    #expect(throws: Normalize.Error.wrongHost("ie.linkedin.com\(mark)")) { try Normalize.linkedin("https://ie.linkedin.com\(mark)/in/bloom") }
    #expect(throws: Normalize.Error.wrongHost("ie.linkedin\(reph).com")) { try Normalize.linkedin("https://ie.linkedin\(reph).com/in/bloom") }
}
