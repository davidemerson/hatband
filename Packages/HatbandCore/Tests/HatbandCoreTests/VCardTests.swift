import Testing
@testable import HatbandCore

private func physicalLines(_ text: String) -> [String] {
    var lines = text.components(separatedBy: "\r\n")
    #expect(lines.last == "", "text ends with CRLF")
    lines.removeLast()
    return lines
}

private extension String {
    func components(separatedBy separator: String) -> [String] {
        var out: [String] = []
        var current = ""
        var rest = Substring(self)
        while let range = rest.range(of: separator) {
            current += rest[..<range.lowerBound]
            out.append(current)
            current = ""
            rest = rest[range.upperBound...]
        }
        out.append(current + rest)
        return out
    }
}

private extension Substring {
    func range(of needle: String) -> Range<Index>? {
        guard !needle.isEmpty else { return nil }
        var start = startIndex
        while start < endIndex {
            if self[start...].hasPrefix(needle) {
                return start..<index(start, offsetBy: needle.count)
            }
            start = index(after: start)
        }
        return nil
    }
}

private func maximalCard() -> VCard {
    var card = VCard(formattedName: "Leopold Bloom", familyName: "Bloom", givenName: "Leopold")
    card.organization = "Freeman's Journal"
    card.phone = "+353871234567"
    card.email = "henry.flower@example.ie"
    card.links = [
        VCard.Link(label: "Website", url: "http://nnix.com/~bloom"),
        VCard.Link(label: "GitHub", url: "https://github.com/lbloom"),
        VCard.Link(label: "LinkedIn", url: "https://www.linkedin.com/in/leopold-bloom"),
        VCard.Link(label: "Mastodon", url: "https://merveilles.town/@bloom"),
        VCard.Link(label: "Signal", url: "https://signal.me/#eu/" + Base64.encode([UInt8](repeating: 7, count: 48), url: true)),
        VCard.Link(label: "Calendly", url: "https://calendly.com/bloom/coffee"),
        VCard.Link(label: "GPG", url: "OPENPGP4FPR:EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"),
    ]
    card.note = "Met at Davy Byrne's, Bloomsday 2026.\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjJlVLb4OQSjA2M1WCE+kKq1u22L+67K93iFB3A20R3"
    card.photoJPEG = [0xff, 0xd8, 0xff, 0xe0] + (0..<600).map { UInt8(truncatingIfNeeded: $0) } + [0xff, 0xd9]
    card.extensions = [
        VCard.Extension(name: "PERSONA", value: "0102030405060708"),
        VCard.Extension(name: "KEY", value: Base64.encode([UInt8](repeating: 2, count: 32))),
        VCard.Extension(name: "issued-day", value: "2438"),
    ]
    return card
}

@Test func writesMinimalCard() {
    let card = VCard(formattedName: "Leopold Bloom")
    #expect(card.familyName == "Bloom")
    #expect(card.givenName == "Leopold")
    #expect(card.text == "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Bloom;Leopold;;;\r\nFN:Leopold Bloom\r\nEND:VCARD\r\n")
}

@Test func guessesNameComponents() {
    #expect(VCard(formattedName: "Cher").familyName == "")
    #expect(VCard(formattedName: "Cher").givenName == "Cher")
    #expect(VCard(formattedName: "  ").givenName == "")
    let three = VCard(formattedName: "Henry  Flower Bloom")
    #expect(three.familyName == "Bloom")
    #expect(three.givenName == "Henry Flower")
    let explicit = VCard(formattedName: "Xi Jinping", familyName: "Xi", givenName: "Jinping")
    #expect(explicit.text.contains("\r\nN:Xi;Jinping;;;\r\n"))
    let partial = VCard(formattedName: "Leopold Bloom", familyName: "Virag")
    #expect(partial.familyName == "Virag")
    #expect(partial.givenName == "Leopold")
}

@Test func escapesReservedCharacters() throws {
    var card = VCard(formattedName: "Bloom, Leopold; \"Poldy\" \\ back", familyName: "Bloom;Virag", givenName: "Leopold,Paula")
    card.organization = "Freeman's Journal; Editorial, Dublin"
    card.note = "line1\r\nline2\nline3\rline4\u{2028}line5"
    card.links = [VCard.Link(label: "A,B;C", url: "https://example.com/a,b;c\\d")]
    let lines = physicalLines(card.text)
    #expect(lines.contains("N:Bloom\\;Virag;Leopold\\,Paula;;;"))
    #expect(lines.contains("FN:Bloom\\, Leopold\\; \"Poldy\" \\\\ back"))
    #expect(lines.contains("ORG:Freeman's Journal\\; Editorial\\, Dublin"))
    #expect(lines.contains("NOTE:line1\\nline2\\nline3\\nline4\\nline5"))
    #expect(lines.contains("item1.URL:https://example.com/a\\,b\\;c\\\\d"))
    #expect(lines.contains("item1.X-ABLabel:A\\,B\\;C"))
    #expect(lines.count == 9)
    // Line breaks come back as LF; everything else is exact.
    var expected = card
    expected.note = "line1\nline2\nline3\nline4\nline5"
    #expect(try VCard.parseBasic(card.text) == expected)
}

@Test func neutralisesCRLFInjection() throws {
    var card = VCard(formattedName: "Bloom\r\nEND:VCARD\r\nBEGIN:VCARD\r\nFN:Mallory")
    card.note = "x\r\nX-HATBAND-KEY:evil\r\n"
    card.email = "a@b.ie\nTEL:+1"
    card.extensions = [VCard.Extension(name: "K\r\nEY", value: "v\r\nFN:Mallory")]
    let text = card.text
    let lines = physicalLines(text)
    #expect(lines.filter { $0 == "BEGIN:VCARD" }.count == 1)
    #expect(lines.filter { $0 == "END:VCARD" }.count == 1)
    #expect(!lines.contains { $0.hasPrefix("TEL") })
    #expect(!lines.contains { $0.hasPrefix("FN:Mallory") })
    #expect(lines.filter { $0.hasPrefix("X-HATBAND-") } == ["X-HATBAND-KEY:v\\nFN:Mallory"])
    // Every LF is part of a CRLF, and every CRLF is followed by a property or a fold.
    let bytes = Array(text.utf8)
    for (i, byte) in bytes.enumerated() where byte == 0x0a {
        #expect(i > 0 && bytes[i - 1] == 0x0d)
    }
    #expect(!bytes.contains(0x00))
    let parsed = try VCard.parseBasic(text)
    #expect(parsed.formattedName == "Bloom\nEND:VCARD\nBEGIN:VCARD\nFN:Mallory")
    #expect(parsed.note == "x\nX-HATBAND-KEY:evil\n")
    #expect(parsed.email == "a@b.ie\nTEL:+1")
    #expect(parsed.extensions == [VCard.Extension(name: "KEY", value: "v\nFN:Mallory")])
}

@Test func foldsAtSeventyFiveOctets() throws {
    var card = VCard(formattedName: "Leopold Bloom")
    card.note = String(repeating: "abcdefghij", count: 20)
    let lines = physicalLines(card.text)
    #expect(lines.allSatisfy { $0.utf8.count <= 75 })
    let noteLines = lines.filter { $0.hasPrefix("NOTE:") || $0.hasPrefix(" ") }
    #expect(noteLines.count == 3)
    #expect(noteLines[0].utf8.count == 75)
    #expect(noteLines[1].utf8.count == 75)
    #expect(noteLines[1].hasPrefix(" "))
    #expect(noteLines[2].hasPrefix(" "))
    #expect(noteLines[0] + noteLines[1...].map { String($0.dropFirst()) }.joined() == "NOTE:" + card.note!)
    #expect(try VCard.parseBasic(card.text) == card)
    // Exactly 75 octets is not folded; 76 is.
    var edge = VCard(formattedName: "x")
    edge.note = String(repeating: "n", count: 70)
    #expect(physicalLines(edge.text).contains("NOTE:" + edge.note!))
    edge.note = String(repeating: "n", count: 71)
    #expect(physicalLines(edge.text).contains("NOTE:" + String(repeating: "n", count: 70)))
    #expect(physicalLines(edge.text).contains(" n"))
}

@Test(arguments: ["é", "水", "🎩", "ß", "Ω"])
func foldsOnUTF8Boundaries(unit: String) throws {
    for count in [20, 25, 37, 38, 75, 76, 200] {
        var card = VCard(formattedName: "x")
        card.note = String(repeating: unit, count: count)
        let text = card.text
        for line in physicalLines(text) {
            #expect(line.utf8.count <= 75)
            #expect(String(validating: Array(line.utf8), as: UTF8.self) != nil)
            #expect(String(validating: Array(line.utf8), as: UTF8.self)?.unicodeScalars.count == line.unicodeScalars.count)
        }
        #expect(try VCard.parseBasic(text) == card)
    }
}

@Test func foldsMixedWidthText() throws {
    var card = VCard(formattedName: "x")
    card.note = (0..<120).map { $0 % 3 == 0 ? "水" : ($0 % 3 == 1 ? "é" : "a") }.joined()
    let lines = physicalLines(card.text)
    #expect(lines.allSatisfy { $0.utf8.count <= 75 })
    #expect(lines.filter { $0.hasPrefix(" ") }.count >= 3)
    #expect(try VCard.parseBasic(card.text) == card)
}

@Test func embedsPhoto() throws {
    var card = VCard(formattedName: "x")
    card.photoJPEG = Array(UInt8.min...UInt8.max)
    let lines = physicalLines(card.text)
    let index = try #require(lines.firstIndex { $0.hasPrefix("PHOTO;ENCODING=b;TYPE=JPEG:") })
    var base64 = String(lines[index].dropFirst("PHOTO;ENCODING=b;TYPE=JPEG:".count))
    var next = index + 1
    while lines[next].hasPrefix(" ") {
        base64 += lines[next].dropFirst()
        next += 1
    }
    #expect(try Base64.decode(base64) == card.photoJPEG)
    #expect(lines.allSatisfy { $0.utf8.count <= 75 })
    #expect(try VCard.parseBasic(card.text) == card)
}

@Test func writesExtensions() {
    var card = VCard(formattedName: "x")
    card.extensions = [
        VCard.Extension(name: "Persona-ID", value: "a,b"),
        VCard.Extension(name: "seq", value: "12"),
        VCard.Extension(name: "weird name!", value: ""),
    ]
    let lines = physicalLines(card.text)
    #expect(lines.contains("X-HATBAND-PERSONA-ID:a\\,b"))
    #expect(lines.contains("X-HATBAND-SEQ:12"))
    #expect(lines.contains("X-HATBAND-WEIRDNAME:"))
}

@Test func roundTripsMaximalCard() throws {
    let card = maximalCard()
    let text = card.text
    let lines = physicalLines(text)
    #expect(lines.first == "BEGIN:VCARD")
    #expect(lines[1] == "VERSION:3.0")
    #expect(lines.last == "END:VCARD")
    #expect(lines.allSatisfy { $0.utf8.count <= 75 })
    #expect(lines.contains("TEL;TYPE=CELL:+353871234567"))
    #expect(lines.contains("EMAIL;TYPE=INTERNET:henry.flower@example.ie"))
    #expect(lines.contains("item7.URL:OPENPGP4FPR:EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"))
    #expect(lines.contains("item7.X-ABLabel:GPG"))
    #expect(lines.contains("X-HATBAND-ISSUED-DAY:2438"))
    let parsed = try VCard.parseBasic(text)
    #expect(parsed == card)
    #expect(parsed.links.count == 7)
    #expect(card.extensions.map(\.name) == ["PERSONA", "KEY", "ISSUED-DAY"])
    #expect(try VCard.parseBasic(parsed.text) == parsed)
}

@Test func readsContactsStyleCards() throws {
    // What Contacts exports: LF endings in places, parameters in lower case,
    // Apple's magic labels, and properties we do not model.
    let text = """
    BEGIN:VCARD
    VERSION:3.0
    PRODID:-//Apple Inc.//iPhone OS 26.0//EN
    N:Bloom;Leopold;Paula;Mr.;
    FN:Leopold Bloom
    ORG:Freeman's Journal;Advertising
    TITLE:Canvasser
    item1.EMAIL;type=INTERNET;type=pref:henry.flower@example.ie
    item1.X-ABLabel:_$!<Other>!$_
    TEL;type=CELL;type=VOICE;type=pref:+353 87 123 4567
    TEL;type=HOME;type=VOICE:+353 1 234 5678
    item2.URL;type=pref:https://nnix.com/
    item2.X-ABLabel:_$!<HomePage>!$_
    item3.URL:https://github.com/lbloom
    item3.X-ABLabel:GitHub
    NOTE:Met at Davy Byrne's\\, Bloomsday.\\nSecond line.
    X-HATBAND-PERSONA:0102030405060708
    END:VCARD
    """
    let card = try VCard.parseBasic(text.components(separatedBy: "\n").joined(separator: "\r\n"))
    #expect(card.formattedName == "Leopold Bloom")
    #expect(card.familyName == "Bloom")
    #expect(card.givenName == "Leopold")
    #expect(card.organization == "Freeman's Journal")
    #expect(card.phone == "+353 87 123 4567")
    #expect(card.email == "henry.flower@example.ie")
    #expect(card.links == [VCard.Link(label: "_$!<HomePage>!$_", url: "https://nnix.com/"), VCard.Link(label: "GitHub", url: "https://github.com/lbloom")])
    #expect(card.note == "Met at Davy Byrne's, Bloomsday.\nSecond line.")
    #expect(card.extensions == [VCard.Extension(name: "PERSONA", value: "0102030405060708")])
    // Bare LF and folded lines are accepted too.
    let folded = "BEGIN:VCARD\nVERSION:3.0\nN:Bloom;Leo\n pold;;;\nFN:Leopold Bl\n\toom\nEND:VCARD\n"
    let unfolded = try VCard.parseBasic(folded)
    #expect(unfolded.givenName == "Leopold")
    #expect(unfolded.formattedName == "Leopold Bloom")
}

private let badVCards: [(String, VCard.Error)] = [
    ("", VCard.Error.notAVCard), ("FN:x", .notAVCard), ("BEGIN:VCARD\r\nFN:x\r\n", .notAVCard),
    ("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n", .notAVCard),
    ("BEGIN:VCARD\r\nVERSION:2.1\r\nFN:x\r\nEND:VCARD\r\n", .unsupportedVersion("2.1")),
    ("BEGIN:VCARD\r\nVERSION:4.0\r\nEND:VCARD\r\n", .unsupportedVersion("4.0")),
    ("BEGIN:VCARD\r\nVERSION:3.0\r\nno colon here\r\nEND:VCARD\r\n", .malformedLine("no colon here")),
    ("BEGIN:VCARD\r\nVERSION:3.0\r\nFN;X=\"a:b\r\nEND:VCARD\r\n", .malformedLine("FN;X=\"a:b")),
]

@Test(arguments: badVCards)
func rejectsBadInput(text: String, error: VCard.Error) {
    #expect(throws: error) { try VCard.parseBasic(text) }
}

@Test func skipsPhotosThatAreNotInlineBase64() throws {
    func card(_ photo: String) throws -> VCard {
        try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\n" + photo + "\r\nEND:VCARD\r\n")
    }
    // A reference, even one that happens to be base64, is not a photo.
    #expect(try card("PHOTO;VALUE=uri:https://nnix.com/bloom.jpg").photoJPEG == nil)
    #expect(try card("PHOTO;value=\"uri\";type=jpeg:AAAA").photoJPEG == nil)
    #expect(try card("PHOTO;TYPE=JPEG;VALUE=URI:AAAA").photoJPEG == nil)
    // Malformed data is skipped rather than refused; the rest of the card is read.
    #expect(try card("PHOTO;ENCODING=b;TYPE=JPEG:not*base64").photoJPEG == nil)
    #expect(try card("PHOTO;ENCODING=b:").photoJPEG == [])
    #expect(try card("PHOTO;ENCODING=b;TYPE=JPEG:AAAA").photoJPEG == [0, 0, 0])
    #expect(try card("PHOTO;VALUE=uri:https://nnix.com/bloom.jpg").formattedName == "x")
}

@Test func splitsAtTheFirstColonOutsideQuotes() throws {
    // RFC 2426 §4: a quoted parameter value may hold a colon.
    let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nitem1.URL;X-Q=\"a:b\":https://nnix.com/a:b\r\nitem1.X-ABLabel:Web\r\n"
        + "TEL;TYPE=\"cell:x\";TYPE=pref:+1\r\nFN;X-Q=\"\":Leopold\r\nEND:VCARD\r\n"
    let card = try VCard.parseBasic(text)
    #expect(card.links == [VCard.Link(label: "Web", url: "https://nnix.com/a:b")])
    #expect(card.phone == "+1")
    #expect(card.formattedName == "Leopold")
    #expect(VCard.splitProperty("N;X=\"a:b\":c:d")?.head == "N;X=\"a:b\"")
    #expect(VCard.splitProperty("N;X=\"a:b\":c:d")?.value == "c:d")
    #expect(VCard.splitProperty("N:")?.head == "N")
    #expect(VCard.splitProperty("N:")?.value == "")
    #expect(VCard.splitProperty("FN;X=\"a:b") == nil)
    #expect(VCard.splitProperty("no colon") == nil)
}

/// RFC 2426 works on octets: a combining mark after `;`, `.` or `:` in a
/// header does not fuse with it, and a Greek question mark (U+037E, which
/// Swift's `==` treats as equal to `;`) is not a semicolon.
@Test func headersAndEscapesAreScalarBased() throws {
    let text = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:x\r\nTEL;\u{301}TYPE=CELL:+1\r\nitem1.URL;X=\u{301}:https://nnix.com\r\n"
        + "item1.X-ABLabel:\u{301}Web\r\nX-HATBAND-\u{301}KEY:v\r\nEND:VCARD\r\n"
    let card = try VCard.parseBasic(text)
    #expect(card.phone == "+1")
    #expect(card.links == [VCard.Link(label: "\u{301}Web", url: "https://nnix.com")])
    #expect(card.extensions == [VCard.Extension(name: "KEY", value: "v")])
    #expect(VCard.escape("\u{037E}").utf8.elementsEqual("\u{037E}".utf8))
    #expect(VCard.splitComponents("a\u{037E}b").map { Array($0.utf8) } == [Array("a\u{037E}b".utf8)])
    #expect(VCard.unescape("\\\u{301}") == "\u{301}")
    #expect(VCard.escape("\r\n\u{301}") == "\\n\u{301}")
}

@Test func escapeDropsControlsButKeepsTabs() throws {
    #expect(VCard.escape("a\u{0}b\u{1b}c\u{0b}d\u{0c}e\u{7f}f") == "abcdef")
    #expect(VCard.escape("\u{1}\u{1f}") == "")
    #expect(VCard.escape("a\tb c") == "a\tb c")
    #expect(VCard.escape("a\u{1b}[31m,b\n") == "a[31m\\,b\\n")
    var card = VCard(formattedName: "Leo\u{0}pold\u{1b}[0m Bloom")
    card.note = "tab\tkept\u{7f}"
    let parsed = try VCard.parseBasic(card.text)
    #expect(parsed.formattedName == "Leopold[0m Bloom")
    #expect(parsed.givenName == "Leopold[0m")
    #expect(parsed.note == "tab\tkept")
}

@Test func unescapesLeniently() {
    #expect(VCard.unescape("a\\,b\\;c\\\\d\\ne\\Nf") == "a,b;c\\d\ne\nf")
    #expect(VCard.unescape("trailing\\") == "trailing\\")
    #expect(VCard.unescape("\\x") == "x")
    #expect(VCard.splitComponents("a\\;b;c;;d") == ["a;b", "c", "", "d"])
    #expect(VCard.splitComponents("") == [""])
    #expect(VCard.escape("") == "")
    #expect(VCard.escape("plain text 水") == "plain text 水")
}
