import Testing
@testable import HatbandCore

// A second look at the closed scalar sweep nits, with cases of its own:
// NFC/NFD pairs across Cyrillic, Greek and Latin, every kind of UAX #29
// WB4 scalar inside a word, whitespace with marks of several scripts and
// categories, marks on hyphens and digits, hidden scalars in linkedin.com
// subdomains, curve names on the wire, and vCard property names.

private let qr = Limits.qr
private let reph = "\u{D4E}"

private func wire(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(string: s, to: &out)
    return out
}

private func wire(_ b: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(bytes: b, to: &out)
    return out
}

private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

@Suite struct SweepNitsReview {
    // MARK: - 1. Homographs under canonical equivalence

    /// A precomposed letter whose base is a twin, and its base-plus-mark
    /// spelling: one skeleton, one verdict, raw and as the punycode of each
    /// spelling. Cyrillic (ё, ӑ, ї, Ї), Greek (ά, ΐ, ώ, and the Extended
    /// Greek oxia form whose NFD is the tonos form's) and Latin (ẛ, whose
    /// base is the long s).
    @Test(arguments: [
        ("\u{430}\u{440}\u{440}\u{4CF}\u{451}", "\u{430}\u{440}\u{440}\u{4CF}\u{435}\u{308}", "apple", "xn--80a6aa2e97a", "xn--ssa50dpa7ba27f"),
        ("\u{4D1}pple", "\u{430}\u{306}pple", "apple", "xn--pple-4re", "xn--pple-kwc10p"),
        ("g\u{457}thub", "g\u{456}\u{308}thub", "github", "xn--gthub-t2e", "xn--gthub-egd15u"),
        ("\u{407}van", "\u{406}\u{308}van", "Ivan", "xn--van-h7c", "xn--van-cec38j"),
        ("\u{3AC}pple", "\u{3B1}\u{301}pple", "apple", "xn--pple-9kd", "xn--pple-uvc96h"),
        ("\u{390}pple", "\u{3B9}\u{308}\u{301}pple", "ipple", "xn--pple-9gd", "xn--pple-uvc5b37g"),
        ("\u{1F71}pple", "\u{3B1}\u{301}pple", "apple", "xn--pple-ul6a", "xn--pple-uvc96h"),
        ("\u{3CE}eb", "\u{3C9}\u{301}eb", "web", "xn--eb-scc", "xn--eb-7tb31f"),
        ("\u{1E9B}potify", "\u{17F}\u{307}potify", "spotify", "xn--potify-ob8b", "xn--potify-9pb052a"),
    ])
    func precomposedAndDecomposedTwinsShareAVerdict(nfc: String, nfd: String, ascii: String, punyNFC: String, punyNFD: String) {
        #expect(nfc == nfd && scalars(nfc) != scalars(nfd), "the pair must be canonically equivalent and spelt apart")
        #expect(Confusables.homographLabel(nfc) == ascii)
        #expect(Confusables.homographLabel(nfd) == ascii)
        #expect(Punycode.decode(Array(punyNFC.utf8.dropFirst(4)))?.unicodeScalars.elementsEqual(nfc.unicodeScalars) == true)
        #expect(Punycode.decode(Array(punyNFD.utf8.dropFirst(4)))?.unicodeScalars.elementsEqual(nfd.unicodeScalars) == true)
        let verdict = Verdict.reject("non-ASCII host, looks like “\(ascii).com”")
        for host in [nfc + ".com", nfd + ".com", punyNFC + ".com", punyNFD + ".com"] {
            #expect(Confusables.domainVerdict(host) == verdict, "\(host)")
            #expect(URLPolicy.verdict(for: "https://" + host + "/") == verdict, "\(host)")
            #expect(URLPolicy.verdict(for: "mailto:a@" + host) == verdict, "\(host)")
            #expect(URLPolicy.verdict(for: "acct:a@" + host) == verdict, "\(host)")
        }
        for host in [punyNFC + ".com", punyNFD + ".com"] {
            #expect(FieldValidator.website(host + "/x", limits: qr) == verdict, "\(host)")
            #expect(FieldValidator.email("a@" + host, limits: qr) == verdict, "\(host)")
            #expect(FieldValidator.handle("a@" + host, limits: qr) == verdict, "\(host)")
        }
        // In any ASCII case (the skeleton keeps the label's ASCII case).
        #expect(!Confusables.domainVerdict(punyNFC.uppercased() + ".COM").isAccepted)
        #expect(!Confusables.domainVerdict(punyNFD.uppercased() + ".COM").isAccepted)
        // One spelling per label, and the skeleton names both.
        #expect(Confusables.domainVerdict(nfc + "." + nfd + ".com") == .reject("non-ASCII host, looks like “\(ascii).\(ascii).com”"))
        #expect(Confusables.domainVerdict(punyNFC + "." + punyNFD + ".com") == .reject("non-ASCII host, looks like “\(ascii).\(ascii).com”"))
        #expect(Confusables.domainVerdict(nfd + ".\u{43C}\u{43E}\u{441}\u{43A}\u{432}\u{430}") == .reject("label “\(nfd)” looks like “\(ascii)”"))
    }

    /// Canonical reordering: two marks in either order, on a twin, are the
    /// same label to Swift and to the rule.
    @Test func markOrderDoesNotChangeTheSkeleton() {
        let a = "\u{430}\u{301}\u{323}pple", b = "\u{430}\u{323}\u{301}pple"
        #expect(a == b && scalars(a) != scalars(b))
        #expect(Confusables.homographLabel(a) == "apple")
        #expect(Confusables.homographLabel(b) == "apple")
        #expect(Confusables.domainVerdict("xn--pple-uvc8rs3e.com") == .reject("non-ASCII host, looks like “apple.com”"))
        #expect(Confusables.domainVerdict("xn--pple-uvc7rt3e.com") == .reject("non-ASCII host, looks like “apple.com”"))
        // A mark that itself decomposes to two marks, on a twin and first.
        #expect(Confusables.homographLabel("\u{430}\u{344}pple") == "apple")
        #expect(Confusables.homographLabel("\u{430}\u{F73}pple") == "apple")
        #expect(Confusables.homographLabel("\u{344}\u{430}pple") == nil)
        #expect(Confusables.homographLabel("\u{F73}apple") == nil)
    }

    /// An honest letter stays honest in both spellings: a Latin base with
    /// a mark (é, ü, ệ in canonical and non-canonical mark order, Ḱ with an
    /// ASCII K), a Greek or Cyrillic base that is no twin (έ, ѝ, й), and
    /// the ligatures and sharp s that decompose only by compatibility.
    @Test(arguments: [
        "caf\u{E9}", "cafe\u{301}", "m\u{FC}nchen", "mu\u{308}nchen",
        "vi\u{1EC7}t", "vie\u{323}\u{302}t", "vie\u{302}\u{323}t",
        "\u{1E30}elvin", "K\u{301}elvin", "\u{130}stanbul", "I\u{307}stanbul",
        "\u{3AD}\u{3BB}\u{3BB}", "\u{3B5}\u{301}\u{3BB}\u{3BB}", "\u{45D}", "\u{438}\u{300}", "\u{439}", "\u{438}\u{306}",
        "\u{FB01}le", "stra\u{DF}e", "\u{1E9E}", "\u{AC00}", "\u{1100}\u{1161}", "\u{2126}hm",
    ])
    func honestLettersStayHonestInBothSpellings(label: String) {
        #expect(Confusables.homographLabel(label) == nil, "\(label)")
        #expect(Confusables.domainVerdict(label + ".com") == .reject("non-ASCII host"), "\(label)")
    }

    /// The Kelvin sign is a twin of `K` in every spelling of its own, and
    /// remains one with a mark on it, even though its NFC with an acute is
    /// Ḱ (U+1E30), an honest letter: a singleton whose decomposition is
    /// ASCII is judged as the ASCII, so the rule is not closed under
    /// canonical equivalence there, and cannot be without `Kelvin.com`
    /// naming itself a homograph. The raw forms are refused either way;
    /// as punycode the honest Ḱ is accepted with the IDN warning and the
    /// Kelvin sign is named.
    @Test func kelvinSignIsATwinWithOrWithoutAMark() {
        #expect("\u{212A}elvin" == "Kelvin")
        #expect("\u{212A}\u{301}elvin" == "\u{1E30}elvin")
        #expect(Confusables.homographLabel("\u{212A}elvin") == "Kelvin")
        #expect(Confusables.homographLabel("\u{212A}\u{301}elvin") == "Kelvin")
        #expect(Confusables.homographLabel("Kelvin") == nil)
        #expect(Confusables.homographLabel("\u{1E30}elvin") == nil)
        #expect(Confusables.domainVerdict("\u{212A}\u{301}elvin.com") == .reject("non-ASCII host, looks like “Kelvin.com”"))
        #expect(Confusables.domainVerdict("\u{1E30}elvin.com") == .reject("non-ASCII host"))
        #expect(Confusables.domainVerdict("xn--elvin-5ed0615c.com") == .reject("non-ASCII host, looks like “Kelvin.com”"))
        #expect(Confusables.domainVerdict("xn--elvin-4h1b.com") == .warning("punycode host label"))
        #expect(Punycode.decode(Array("elvin-5ed0615c".utf8))?.unicodeScalars.elementsEqual("\u{212A}\u{301}elvin".unicodeScalars) == true)
        #expect(Punycode.decode(Array("elvin-4h1b".utf8))?.unicodeScalars.elementsEqual("\u{1E30}elvin".unicodeScalars) == true)
        // The other ASCII singletons, U+037E (;) and U+1FEF (`), are
        // punctuation no host holds; they are refused raw and decoded,
        // whatever the message names.
        for host in ["app\u{37E}le.com", "apple\u{1FEF}.com", "xn--apple-o0d.com", "xn--apple-wo3b.com"] {
            #expect(!Confusables.domainVerdict(host).isAccepted, "\(host)")
            #expect(!URLPolicy.verdict(for: "https://" + host + "/").isAccepted, "\(host)")
        }
    }

    /// A label that is no homograph but mixes scripts through a mark or a
    /// precomposed letter is refused for the mixing, in both spellings.
    @Test func mixedScriptPunycodeLabelsAreRefusedInBothSpellings() {
        for host in ["xn--avid-kbe.com", "xn--avid-pvc58p.com", "xn--avid-uvc55p.com"] {
            #expect(Confusables.domainVerdict(host) == .reject("mixed scripts in punycode label"), "\(host)")
            #expect(URLPolicy.verdict(for: "https://" + host + "/") == .reject("mixed scripts in punycode label"), "\(host)")
        }
        #expect(Punycode.decode(Array("avid-kbe".utf8))?.unicodeScalars.elementsEqual("\u{45D}avid".unicodeScalars) == true)
        #expect(Punycode.decode(Array("avid-pvc58p".utf8))?.unicodeScalars.elementsEqual("\u{438}\u{300}avid".unicodeScalars) == true)
        #expect(Punycode.decode(Array("avid-uvc55p".utf8))?.unicodeScalars.elementsEqual("\u{434}\u{301}avid".unicodeScalars) == true)
    }

    // MARK: - 2. Words under UAX #29 WB4

    /// Every kind of scalar WB4 skips over keeps a word going: the whole
    /// of Cf (joiners, the soft hyphen, the word joiner, the BOM, the bidi
    /// controls, the Arabic, Syriac and Kaithi signs, the interlinear
    /// annotation controls, the musical and shorthand controls, the tags)
    /// and Extend (Mn, Mc, Me, the default-ignorable marks, the emoji
    /// modifiers, the halfwidth voiced sound mark). Several in a row too,
    /// and at either end of the word. U+200B is WB Other, not Format, in
    /// UAX #29; keeping it in the word is the stricter reading, and
    /// `TextCheck` refuses it before the script rule anyway.
    @Test(arguments: [
        "\u{200D}", "\u{200C}", "\u{200B}", "\u{AD}", "\u{2060}", "\u{2061}", "\u{FEFF}",
        "\u{61C}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202E}", "\u{2066}", "\u{2069}",
        "\u{600}", "\u{605}", "\u{6DD}", "\u{70F}", "\u{8E2}", "\u{110BD}", "\u{110CD}",
        "\u{FFF9}", "\u{FFFA}", "\u{FFFB}", "\u{13430}", "\u{1BCA0}", "\u{1D173}", "\u{1D17A}",
        "\u{E0001}", "\u{E0020}", "\u{E0041}", "\u{E007F}",
        "\u{301}", "\u{308}", "\u{5B4}", "\u{E31}", "\u{903}", "\u{93E}", "\u{BBE}", "\u{20DD}", "\u{20E0}",
        "\u{FE0F}", "\u{34F}", "\u{180B}", "\u{1F3FB}", "\u{1F3FF}", "\u{FF9E}",
        "\u{200D}\u{301}\u{200C}", "\u{E0041}\u{E0042}\u{E007F}", "\u{903}\u{1F3FB}\u{AD}",
    ])
    func wb4ScalarsKeepAWordGoing(inner: String) {
        let de = "\u{414}", e = "\u{44D}"
        #expect(Confusables.mixedScripts(in: de + inner + "avid"), "\(inner.debugDescription)")
        #expect(Confusables.mixedScripts(in: "pa" + inner + "\u{443}"), "\(inner.debugDescription)")
        #expect(Confusables.mixedScripts(in: "\u{3B1}" + inner + "b"), "\(inner.debugDescription)")
        #expect(Confusables.mixedScripts(in: "a" + inner + "\u{562}"), "\(inner.debugDescription)")
        #expect(Confusables.mixedScripts(in: "\u{3B1}" + inner + "\u{430}"), "\(inner.debugDescription)")
        #expect(Confusables.mixedScripts(in: inner + de + "avid"), "\(inner.debugDescription)")
        #expect(Confusables.mixedScripts(in: de + "avid" + inner), "\(inner.debugDescription)")
        #expect(Confusables.mixedScripts(in: de + "1" + inner + "avid"), "\(inner.debugDescription)")
        // One script through it, a bilingual pair across a space, and
        // scripts that never count, are as they were.
        #expect(!Confusables.mixedScripts(in: "Da" + inner + "vid"), "\(inner.debugDescription)")
        #expect(!Confusables.mixedScripts(in: de + inner + e), "\(inner.debugDescription)")
        #expect(!Confusables.mixedScripts(in: "David " + inner + de + e), "\(inner.debugDescription)")
        #expect(!Confusables.mixedScripts(in: "David" + inner + " " + de + e), "\(inner.debugDescription)")
        #expect(!Confusables.mixedScripts(in: "\u{6771}\u{4EAC}" + inner + "Tokyo"), "\(inner.debugDescription)")
        #expect(!Confusables.mixedScripts(in: "D" + inner + "\u{5D0}"), "\(inner.debugDescription)")
    }

    /// What is not letter, number, Extend or Format still ends a word:
    /// spaces of every kind, line and paragraph separators, controls,
    /// punctuation, symbols that are not emoji modifiers, and private use.
    @Test(arguments: [
        " ", "\u{A0}", "\u{1680}", "\u{2003}", "\u{3000}", "\u{2028}", "\u{2029}", "\0", "\t", "\n", "\u{85}",
        ".", "-", "\u{2019}", "\u{2E}", "\u{2B50}", "\u{20AC}", "\u{1F600}", "\u{1F1EE}", "\u{FFFD}", "\u{E000}", "\u{2192}", "\u{A9}",
    ])
    func otherScalarsStillEndAWord(separator: String) {
        #expect(!Confusables.mixedScripts(in: "\u{414}" + separator + "avid"), "\(separator.debugDescription)")
        #expect(!Confusables.mixedScripts(in: "\u{3B1}" + separator + "b"), "\(separator.debugDescription)")
    }

    /// Through `TextCheck`: a hidden joiner is refused before the script
    /// rule speaks; a drawn mark or an emoji modifier inside the word
    /// reaches it and the warning names the look-alike with the mark kept.
    @Test func textCheckOrdersHiddenBeforeMixed() {
        for hidden in ["\u{200D}", "\u{200C}", "\u{200B}", "\u{AD}", "\u{FEFF}", "\u{E0041}", "\u{600}", "\u{FE0F}", "\u{34F}"] {
            #expect(TextCheck.check("\u{422}\(hidden)om", maxBytes: 64) == .reject("invisible character"), "\(hidden.debugDescription)")
        }
        for bidi in ["\u{61C}", "\u{200E}", "\u{202E}", "\u{2066}"] {
            #expect(TextCheck.check("\u{422}\(bidi)om", maxBytes: 64) == .reject("bidirectional control character"), "\(bidi.debugDescription)")
        }
        for drawn in ["\u{301}", "\u{903}", "\u{20DD}", "\u{1F3FB}"] {
            #expect(TextCheck.check("\u{422}\(drawn)om", maxBytes: 64) == .warning("mixed scripts, looks like “T\(drawn)om”"), "\(drawn.debugDescription)")
            #expect(FieldValidator.name("\u{422}\(drawn)om", limits: qr) == .warning("mixed scripts, looks like “T\(drawn)om”"), "\(drawn.debugDescription)")
        }
        #expect(TextCheck.check("\u{414}\u{301}avid", maxBytes: 64) == .warning("mixed scripts"))
        #expect(TextCheck.check("David \u{414}\u{301}\u{44D}", maxBytes: 64) == .ok)
    }

    // MARK: - 3. Whitespace with marks

    private static let spaces = [" ", "\u{A0}", "\u{2003}", "\u{3000}", "\u{1680}", "\u{202F}", "\u{205F}", "\u{2007}"]
    private static let marks = ["\u{301}", "\u{903}", "\u{20DD}", "\u{5B4}", "\u{E31}", "\u{F71}", "\u{1AB0}", "\u{301}\u{308}\u{323}", "\u{93E}\u{20E0}"]

    /// Every whitespace scalar with every kind of drawn mark, Mn of five
    /// scripts, Mc and Me, one or several: the mark goes with the space at
    /// either end, the suggestion drops both, a mark on the letter stays,
    /// and a run of spaces is counted through the marks without them.
    @Test func everySpaceTakesEveryDrawnMark() {
        let trailing = Verdict.warning("leading or trailing whitespace, use “David”")
        for space in Self.spaces {
            for mark in Self.marks {
                let tag = "\(space.debugDescription) \(mark.debugDescription)"
                #expect(TextCheck.check("David\(space)\(mark)", maxBytes: 64) == trailing, "\(tag)")
                #expect(TextCheck.check("\(space)\(mark)David", maxBytes: 64) == trailing, "\(tag)")
                #expect(TextCheck.check("\(space)\(mark)David\(space)\(mark)", maxBytes: 64) == trailing, "\(tag)")
                #expect(TextCheck.check("\(space)\(mark)\(space)\(mark)David\(space)\(mark)\(space)\(mark)", maxBytes: 64) == trailing, "\(tag)")
                #expect(TextCheck.check("David\(mark)\(space)", maxBytes: 64) == .warning("leading or trailing whitespace, use “David\(mark)”"), "\(tag)")
                #expect(TextCheck.check("\(space)David\(mark)", maxBytes: 64) == .warning("leading or trailing whitespace, use “David\(mark)”"), "\(tag)")
                #expect(TextCheck.check("a\(space)\(mark)\(space)\(mark)\(space)\(mark)\(space)\(mark)b", maxBytes: 64) == .warning("run of spaces"), "\(tag)")
                #expect(TextCheck.check("a\(space)\(mark)\(space)\(mark)\(space)\(mark)b", maxBytes: 64) == .ok, "\(tag)")
                #expect(TextCheck.check("a\(space)\(mark)\(mark)\(mark)\(mark)b", maxBytes: 64) == .ok, "\(tag)")
                #expect(TextCheck.check("\(space)\(mark)", maxBytes: 64) == .reject("empty"), "\(tag)")
                #expect(TextCheck.check("\(mark)\(space)", maxBytes: 64) == .reject("empty"), "\(tag)")
                #expect(TextCheck.check("\(space)\(mark)\(space)\(mark)", maxBytes: 64) == .reject("empty"), "\(tag)")
                #expect(TextCheck.check("\(mark)\(space)\(mark)\(space)\(mark)", maxBytes: 64) == .reject("empty"), "\(tag)")
            }
        }
    }

    /// The fields that take free text agree, and the whitespace warning
    /// composes with the others as before: mixed scripts first, then the
    /// whitespace, then a run; the look-alike is of the trimmed text.
    @Test func fieldsAndCompositionAgree() {
        let trailing = Verdict.warning("leading or trailing whitespace, use “David”")
        #expect(FieldValidator.name("David \u{301}", limits: qr) == trailing)
        #expect(FieldValidator.company(" \u{903}David", limits: qr) == trailing)
        #expect(FieldValidator.customLabel("David\u{A0}\u{20DD}", limits: qr) == trailing)
        #expect(FieldValidator.customValue("David \u{301}", kind: .text, limits: qr) == trailing)
        #expect(FieldValidator.customValue("David\n \u{301}", kind: .text, limits: qr) == trailing)
        #expect(FieldValidator.customValue("David \u{301}\n", kind: .text, limits: qr) == trailing)
        #expect(FieldValidator.customValue(" \u{301}\nDavid", kind: .text, limits: qr) == trailing)
        #expect(TextCheck.check(" \u{301}\u{422}om", maxBytes: 64)
            == .warning("mixed scripts, looks like “Tom”; leading or trailing whitespace, use “\u{422}om”"))
        #expect(TextCheck.check("\u{422}om \u{301}", maxBytes: 64)
            == .warning("mixed scripts, looks like “Tom”; leading or trailing whitespace, use “\u{422}om”"))
        #expect(TextCheck.check(" \u{301}a    b \u{301}", maxBytes: 64)
            == .warning("leading or trailing whitespace, use “a    b”; run of spaces"))
        #expect(TextCheck.check(" \u{301}\u{422}om    b \u{301}", maxBytes: 64)
            == .warning("mixed scripts, looks like “Tom    b”; leading or trailing whitespace, use “\u{422}om    b”; run of spaces"))
        // A run of spaces broken by a newline stays broken with marks on the spaces.
        #expect(TextCheck.check("a  \u{301}\n  \u{301}b", maxBytes: 64, allowNewlines: true) == .ok)
        #expect(TextCheck.check("a \u{301}\n \u{301}\n \u{301}\n \u{301}b", maxBytes: 64, allowNewlines: true) == .ok)
    }

    /// What is not a drawn mark is not whitespace's: a default-ignorable
    /// mark after a space is still the invisible character it was, a
    /// control is a control, a Prepend letter is text, and a mark before a
    /// leading space has nothing to sit on and is not trimmed.
    @Test func undrawnScalarsAfterWhitespaceKeepTheirVerdict() {
        for invisible in ["\u{FE0F}", "\u{FE00}", "\u{34F}", "\u{180B}", "\u{E0100}"] {
            #expect(TextCheck.check(" \(invisible)David", maxBytes: 64) == .reject("invisible character"), "\(invisible.debugDescription)")
            #expect(TextCheck.check("David \(invisible)", maxBytes: 64) == .reject("invisible character"), "\(invisible.debugDescription)")
            #expect(TextCheck.check("David \u{301}\(invisible)", maxBytes: 64) == .reject("invisible character"), "\(invisible.debugDescription)")
            #expect(TextCheck.check("David \(invisible)\u{301}", maxBytes: 64) == .reject("invisible character"), "\(invisible.debugDescription)")
        }
        #expect(TextCheck.check("David\t\u{301}", maxBytes: 64) == .reject("control character"))
        #expect(TextCheck.check("David\u{85}\u{301}", maxBytes: 64) == .reject("control character"))
        #expect(TextCheck.check("David\u{2028}\u{301}", maxBytes: 64) == .reject("invisible character"))
        #expect(TextCheck.check("David\n\u{301}", maxBytes: 64) == .reject("control character"))
        #expect(TextCheck.check("David \(reph)", maxBytes: 64) == .ok)
        #expect(TextCheck.check("\(reph) David", maxBytes: 64) == .ok)
        #expect(TextCheck.check("\u{301} David", maxBytes: 64) == .ok)
        #expect(TextCheck.check("David \u{301}\(reph)", maxBytes: 64) == .ok)
        #expect(TextCheck.check("David \u{1F3FB}", maxBytes: 64) == .ok)
    }

    // MARK: - 4. Hostnames: marks on hyphens and digits

    private static func hyphenForms(_ marks: String) -> [String] {
        ["nnix.com-\(marks)", "nnix-\(marks).com", "NNIX.COM-\(marks)", "nnix.\(marks)", "nnix.-\(marks)", "nnix.\(marks)-"]
    }
    private static func digitForms(_ marks: String) -> [String] {
        ["nnix.1\(marks)", "nnix.12\(marks)", "1.2.3.4\(marks)", "nnix.\u{661}\u{662}\(marks)", "nnix.\u{FF11}\(marks)", "nnix.\u{966}\(marks)"]
    }

    /// Trailing label marks of any script, Mn or Mc, one or several, hide
    /// neither a trailing hyphen nor an all-digit last label of any digit
    /// script, by every entry point that takes a host. The digit rule is
    /// the last label's alone, so the digit forms are still fine labels
    /// inside a linkedin.com subdomain; the hyphen forms are not.
    @Test(arguments: ["\u{301}", "\u{903}", "\u{5B4}", "\u{E31}", "\u{F71}", "\u{301}\u{308}\u{323}", "\u{903}\u{93E}"])
    func trailingMarksHideNothing(marks: String) throws {
        for host in Self.hyphenForms(marks) + Self.digitForms(marks) {
            #expect(Hostname.normalized(Substring(host)) == nil, "\(host.debugDescription)")
            #expect(throws: Normalize.Error.invalidHost, "\(host.debugDescription)") { try Normalize.website(host) }
            #expect(throws: Normalize.Error.invalidHost, "\(host.debugDescription)") { try Normalize.website("http://" + host + ":8080/") }
            #expect(throws: Normalize.Error.invalidHost, "\(host.debugDescription)") { try Normalize.mastodon("bloom@" + host) }
            #expect(throws: Normalize.Error.invalidHost, "\(host.debugDescription)") { try Normalize.mastodon("https://" + host + "/@bloom") }
            #expect(throws: Normalize.Error.self, "\(host.debugDescription)") { try Normalize.email("bloom@" + host) }
        }
        for host in Self.hyphenForms(marks) {
            #expect(throws: Normalize.Error.invalidHost, "\(host.debugDescription)") { try Normalize.linkedin("https://" + host + ".linkedin.com/in/bloom") }
        }
        for host in Self.digitForms(marks) {
            #expect(try Normalize.linkedin("https://" + host + ".linkedin.com/in/bloom") == "bloom", "\(host.debugDescription)")
        }
    }

    /// A mark no label may hold (a variation selector, an enclosing mark)
    /// refuses the label wherever it lands, hyphen or digit or not.
    @Test(arguments: ["\u{FE0F}", "\u{20DD}", "\u{34F}"])
    func nonLabelMarksRefuseTheLabel(mark: String) {
        for host in Self.hyphenForms(mark) + Self.digitForms(mark) + ["nnix.c\(mark)om", "nnix.1\(mark)a"] {
            #expect(Hostname.normalized(Substring(host)) == nil, "\(host.debugDescription)")
            #expect(throws: Normalize.Error.self, "\(host.debugDescription)") { try Normalize.website(host) }
            #expect(throws: Normalize.Error.invalidHost, "\(host.debugDescription)") { try Normalize.linkedin("https://" + host + ".linkedin.com/in/bloom") }
        }
    }

    /// The plain forms and the marked forms fail the same way.
    @Test func markedFormsFailLikePlainOnes() {
        for host in ["nnix.com-\u{301}", "nnix.1\u{301}", "1.2.3.4\u{301}", "nnix.\u{661}\u{903}", "nnix.com-", "nnix.1", "1.2.3.4", "nnix.\u{661}"] {
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.website(host) }
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.website("https://" + host + "/path?q#f") }
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.mastodon("bloom@" + host) }
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.mastodon("https://" + host + "/users/bloom") }
        }
        for host in ["nnix.com-\u{301}", "nnix.com-", "-nnix.com", "-\u{301}nnix.com"] {
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.linkedin("https://" + host + ".linkedin.com/in/bloom") }
        }
    }

    /// A mark inside a label is that label's: on a letter before the
    /// hyphen, between letters, on a digit that a letter follows. A Prepend
    /// letter after the hyphen or the digit makes a name. Lowercasing
    /// leaves marks in place.
    @Test func interiorMarksAndLettersStillMakeAName() throws {
        for (host, normalized) in [
            ("nnix.co\u{301}m", "nnix.co\u{301}m"), ("nnix.a\u{903}-b.com", "nnix.a\u{903}-b.com"), ("n\u{301}-\u{301}n.com", "n\u{301}-\u{301}n.com"),
            ("nnix.1\u{301}a", "nnix.1\u{301}a"), ("nnix.\u{661}\u{301}a", "nnix.\u{661}\u{301}a"), ("nnix.com-\(reph)", "nnix.com-\(reph)"),
            ("nnix.1\(reph)", "nnix.1\(reph)"), ("NNIX.CO\u{301}M", "nnix.co\u{301}m"), ("\u{212A}\u{301}.com", "k\u{301}.com"),
        ] {
            #expect(Hostname.normalized(Substring(host)) == normalized, "\(host)")
            #expect(try Normalize.website(host).address == normalized, "\(host)")
        }
    }

    /// A mark between the digits of a last label is drawn on a digit as a
    /// trailing one is, and hides the all-digit label the same way: `4́4`
    /// is `44` to the eye, as `4́` is `4`. The closure sets aside trailing
    /// marks only, so `nnix.11́` is refused while `nnix.1́1` is accepted;
    /// the rule it states (a mark on a digit changes what is drawn, not
    /// what the label is) wants every mark set aside. Fails until it is.
    @Test func interiorMarksOnAnAllDigitLabelAreJudgedLikeTrailingOnes() {
        #expect(Hostname.normalized("nnix.11\u{301}") == nil)
        #expect(Hostname.normalized("1.2.3.44\u{301}") == nil)
        for host in ["nnix.1\u{301}1", "1.2.3.4\u{301}4", "nnix.\u{661}\u{301}\u{662}", "nnix.1\u{903}\u{301}23", "nnix.1\u{301}2\u{301}3\u{301}"] {
            #expect(Hostname.normalized(Substring(host)) == nil, "\(host)")
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.website(host) }
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.mastodon("bloom@" + host) }
        }
    }

    // MARK: - 5. LinkedIn subdomains

    /// Hidden scalars anywhere in a multi-label subdomain, a control, a
    /// percent-escape, an IP literal, an empty label or an over-long name
    /// are `invalidHost`; a mark that leaves the suffix is `wrongHost`;
    /// honest subdomains in any case, with marks, Prepend letters or
    /// A-labels, are discarded and the slug kept.
    @Test func subdomainsAreJudgedAsHostnames() throws {
        for bad in ["a\u{200B}b.c", "a.b\u{FEFF}", "ie\u{301}\u{200D}", "ie\u{200D}\u{301}", "ie\t", "\u{FE0F}ie", "ie%C3%A9", "[::1]", "ie.", ".ie", "ie..uk",
                    "ie-.uk", "ie.-uk", "ie.\u{301}uk", "ie.\u{301}", "a\u{2024}b", "a\u{FF0E}b", "ie\u{A0}", "ie\u{85}",
                    String(repeating: "a", count: 64), [String](repeating: String(repeating: "a", count: 60), count: 4).joined(separator: ".")] {
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("https://\(bad).linkedin.com/in/bloom") }
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("http://\(bad).www.linkedin.com/company/acme") }
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("\(bad).linkedin.com/in/bloom") }
        }
        for good in ["IE\u{301}", "\(reph)ie", "ie\(reph)", "xn--80a6aa8dw8a", "a.b.c.d", "a1-b2.c3", "ie.1", "1\u{301}.2", "\u{130}", "\u{212A}"] {
            #expect(try Normalize.linkedin("https://\(good).linkedin.com/in/bloom") == "bloom", "\(good.debugDescription)")
            #expect(try Normalize.linkedin("https://\(good).LINKEDIN.COM/company/acme") == "company/acme", "\(good.debugDescription)")
        }
        #expect(throws: Normalize.Error.wrongHost("ie.\u{301}linkedin.com")) { try Normalize.linkedin("https://ie.\u{301}linkedin.com/in/bloom") }
        #expect(throws: Normalize.Error.wrongHost("ie\u{3002}linkedin.com")) { try Normalize.linkedin("https://ie\u{3002}linkedin.com/in/bloom") }
        #expect(throws: Normalize.Error.wrongHost("ie.linkedin.com.")) { try Normalize.linkedin("https://ie.linkedin.com./in/bloom") }
        #expect(throws: Normalize.Error.wrongHost("ie.linkedin.com\u{200B}")) { try Normalize.linkedin("https://ie.linkedin.com\u{200B}/in/bloom") }
        // The exact-host callers are unchanged by the extra judgement.
        #expect(try Normalize.github("https://GitHub.com/bloom") == "bloom")
        #expect(throws: Normalize.Error.wrongHost("github.com\u{301}")) { try Normalize.github("https://github.com\u{301}/bloom") }
        #expect(throws: Normalize.Error.wrongHost("www\u{200B}.github.com")) { try Normalize.github("https://www\u{200B}.github.com/bloom") }
        #expect(try Normalize.calendly("https://Calendly.com/bloom/coffee") == "bloom/coffee")
    }

    // MARK: - 6. Curve names on the wire

    private static let ecdsa256 = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPlnx2p7LH4G02PXQJ5HDPmfKIeP2Rzq9adOBa6F1LgVfT2p2J9Yk+4aN2pM+zoHfGrxuMm5h92a6M+PVrNTdoI= bloom@eccles"
    private static let ecdsa384 = "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBCvwJlB4p1vfvUhf2iOK1emWtOK1It+U9fXa1ePh3KHbVK1IelhktxyfX9/j+FZKXfeH7ODl5WeCbiKqyfc/ZJUbQBTbgLt73SHEc5xkb27br/g3XijgFlEEANLGDbvUmw=="
    private static let ecdsa521 = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAEhmLhT9RLgQJkTcUUoqM4cPkYnvy/eCob+TFuWwszurGbgiduJybxEZzb8EDEp7gBRmH1gxuX/JIcbOFpVqE2DCgBawEboRsiKSMU8MG+njhDG4hI8Br1Z7zPoGo1PcvLRkNGB1WHFU+tt3KI1A6Z1kPZI7IHhWQbA+dcyB0dqVe5GDQ== p521 key"

    /// Byte for byte: a look-alike letter (dotless i, long s, fullwidth),
    /// a hidden scalar anywhere, a control, a BOM, another curve's name, a
    /// prefix or suffix, an overlong or truncated UTF-8 byte, all refuse
    /// the blob, from bytes and from a base64 line alike; the honest name
    /// passes and round-trips.
    @Test func curveNamesAreByteExact() throws {
        for (line, kind, curve) in [(Self.ecdsa256, SSHPublicKey.Kind.ecdsaP256, "nistp256"), (Self.ecdsa384, .ecdsaP384, "nistp384"), (Self.ecdsa521, .ecdsaP521, "nistp521")] {
            let key = try SSHPublicKey(line: line)
            let point = try #require(key.inlineBytes)
            let good = wire(kind.typeName) + wire(curve) + wire(point)
            #expect(try SSHPublicKey(blob: good).kind == kind)
            #expect(try SSHPublicKey(blob: good).blob == key.blob)
            #expect(try SSHPublicKey(kind: kind, inlineBytes: point).blob == key.blob)
            #expect(try SSHPublicKey(line: kind.typeName + " " + Base64.encode(good)).inlineBytes == point)
            let others = ["nistp256", "nistp384", "nistp521"].filter { $0 != curve }
            let wrongs = others + [
                "n\u{131}stp" + curve.dropFirst(5), "ni\u{17F}tp" + curve.dropFirst(5), "\u{FF4E}" + curve.dropFirst(),
                "nis\u{200B}tp" + curve.dropFirst(5), "nistp\u{AD}" + curve.dropFirst(5), "\u{FEFF}" + curve, curve + "\u{FEFF}",
                "\0" + curve, curve + "\r\n", curve + "\t", "x" + curve, curve + "x", String(curve.dropLast()), String(curve.dropFirst()),
                curve.uppercased(), "NISTP" + curve.dropFirst(5), "", " ",
            ]
            for wrong in wrongs {
                let blob = wire(kind.typeName) + wire(wrong) + wire(point)
                #expect(throws: SSHPublicKey.Error.malformedBlob, "\(wrong.debugDescription)") { try SSHPublicKey(blob: blob) }
                #expect(throws: SSHPublicKey.Error.malformedBlob, "\(wrong.debugDescription)") { try SSHPublicKey(line: kind.typeName + " " + Base64.encode(blob)) }
            }
            for bytes in [Array(curve.utf8) + [0xFF], [0xC0, 0x80] + Array(curve.utf8.dropFirst()), Array(curve.utf8.dropLast()) + [0xE2, 0x82],
                          Array(curve.utf8) + [0x00], [0x00] + Array(curve.utf8), [0xEF, 0xBB, 0xBF] + Array(curve.utf8)] {
                let blob = wire(kind.typeName) + wire(bytes) + wire(point)
                #expect(throws: SSHPublicKey.Error.malformedBlob, "\(bytes)") { try SSHPublicKey(blob: blob) }
            }
            // The curve name is read before the point, so a bad name with a
            // bad point is still the name's fault.
            #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wire(kind.typeName) + wire(curve + "\u{301}") + wire([UInt8](repeating: 0, count: 3))) }
            // The honest name with the wrong point is the point's.
            #expect(throws: SSHPublicKey.Error.wrongKeyLength(3)) { try SSHPublicKey(blob: wire(kind.typeName) + wire(curve) + wire([UInt8](repeating: 0, count: 3))) }
        }
    }

    // MARK: - 7. vCard property names

    /// ASCII case folding only: a letter whose full uppercase is ASCII
    /// (ı, ſ, ŉ, ǰ, the ligatures, ß in both cases, the Kelvin sign, the
    /// fullwidth letters, dz digraphs) is dropped, never spelt out; `a`-`z`
    /// and the ASCII digits and hyphens stay; the mapping is idempotent
    /// and round-trips through the vCard text.
    @Test func propertyNamesFoldASCIIOnly() throws {
        for (name, expected) in [
            ("\u{131}", ""), ("\u{17F}", ""), ("\u{149}", ""), ("\u{1F0}", ""), ("\u{FB01}", ""), ("\u{FB06}", ""), ("\u{DF}", ""), ("\u{1E9E}", ""),
            ("\u{212A}", ""), ("\u{FF41}\u{FF42}", ""), ("\u{1C6}", ""), ("\u{1C4}", ""), ("\u{130}", ""), ("\u{E9}", ""), ("\u{3B1}", ""), ("\u{430}", ""),
            ("e\u{301}", "E"), ("\u{301}e", "E"), ("a\u{200D}b", "AB"), ("a b", "AB"), ("a_b", "AB"), ("a.b", "AB"), ("-", "-"), ("--", "--"),
            ("seq", "SEQ"), ("Seq-1", "SEQ-1"), ("x-hatband-foo", "X-HATBAND-FOO"), ("0123456789", "0123456789"),
            ("stra\u{DF}e", "STRAE"), ("\u{17F}tra\u{DF}e", "TRAE"), ("ma\u{DF}-\u{FB01}le", "MA-LE"), ("\u{131}\u{FB01}", ""),
        ] {
            #expect(VCard.propertyName(name) == expected, "\(name.debugDescription)")
            #expect(VCard.propertyName(VCard.propertyName(name)) == expected, "\(name.debugDescription)")
            #expect(VCard.Extension(name: name, value: "v").name == expected, "\(name.debugDescription)")
        }
        #expect("\u{131}\u{17F}\u{149}\u{1F0}\u{FB01}\u{DF}\u{212A}".uppercased() == "ISʼNJ\u{30C}FISSK", "why ASCII folding: the full mapping spells these out")
        var card = VCard(formattedName: "x")
        card.extensions = [VCard.Extension(name: "\u{17F}eq", value: "1"), VCard.Extension(name: "stra\u{DF}e", value: "2"), VCard.Extension(name: "\u{DF}", value: "3")]
        #expect(card.text.contains("X-HATBAND-EQ:1"))
        #expect(card.text.contains("X-HATBAND-STRAE:2"))
        #expect(card.text.contains("X-HATBAND-:3"))
        #expect(!card.text.contains("SEQ"))
        #expect(!card.text.contains("SS"))
        #expect(try VCard.parseBasic(card.text).extensions == card.extensions)
    }
}
