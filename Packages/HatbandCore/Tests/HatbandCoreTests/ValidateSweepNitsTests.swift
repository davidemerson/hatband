import Testing
@testable import HatbandCore

// Nits from the review of the scalar sweep, closed: the homograph rule is
// judged on the label's canonical decomposition, so a precomposed letter
// and its base-plus-mark spelling get one verdict; a Format or Extend
// scalar keeps a word going for the script rule (UAX #29 WB4); and a mark
// after whitespace belongs to that whitespace for the trimming and
// run-of-spaces warnings.

private let qr = Limits.qr

@Suite struct ValidateSweepNits {
    // MARK: - Canonical equivalence

    /// `аррӏѐ` with U+0450 precomposed, and with U+0435 U+0300 instead:
    /// canonically equivalent, and the same host to the eye.
    private static let precomposed = "\u{430}\u{440}\u{440}\u{4CF}\u{450}"
    private static let decomposed = "\u{430}\u{440}\u{440}\u{4CF}\u{435}\u{300}"
    private static let apple = Verdict.reject("non-ASCII host, looks like “apple.com”")

    /// Both spellings reject as `apple.com`, raw and as punycode, by every
    /// path that reaches a host.
    @Test func homographRuleIsClosedUnderCanonicalEquivalence() {
        let pre = Self.precomposed, dec = Self.decomposed
        #expect(pre == dec && !pre.unicodeScalars.elementsEqual(dec.unicodeScalars))
        #expect(Confusables.homographLabel(pre) == "apple")
        #expect(Confusables.homographLabel(dec) == "apple")
        for host in [pre + ".com", dec + ".com", "xn--80a6aa8dw8a.com", "xn--ksa12dpa7ba27f.com"] {
            #expect(Confusables.domainVerdict(host) == Self.apple, "\(host)")
            #expect(URLPolicy.verdict(for: "https://" + host + "/") == Self.apple, "\(host)")
            #expect(URLPolicy.verdict(for: "mailto:a@" + host) == Self.apple, "\(host)")
        }
        // The fields refuse a raw non-ASCII host before the domain verdict;
        // the punycode forms reach it.
        for host in ["xn--80a6aa8dw8a.com", "xn--ksa12dpa7ba27f.com"] {
            #expect(FieldValidator.website(host, limits: qr) == Self.apple, "\(host)")
            #expect(FieldValidator.email("a@" + host, limits: qr) == Self.apple, "\(host)")
            #expect(FieldValidator.handle("a@" + host, limits: qr) == Self.apple, "\(host)")
        }
        // The punycode is what it claims to be.
        #expect(Punycode.decode(Array("80a6aa8dw8a".utf8))?.unicodeScalars.elementsEqual(pre.unicodeScalars) == true)
        #expect(Punycode.decode(Array("ksa12dpa7ba27f".utf8))?.unicodeScalars.elementsEqual(dec.unicodeScalars) == true)
        // Under a look-alike-free top level the label alone is named.
        #expect(Confusables.domainVerdict(pre + ".москва") == .reject("label “\(pre)” looks like “apple”"))
        #expect(Confusables.domainVerdict(dec + ".москва") == .reject("label “\(dec)” looks like “apple”"))
    }

    /// The decomposition changes no verdict a precomposed letter had on
    /// its own merits: a base with a mark is not a twin (`café` is honest
    /// in both spellings, `münchen` still), a Hangul syllable is jamo, and
    /// a singleton to ASCII (the Kelvin sign) stays the twin it was.
    @Test func precomposedLettersKeepTheirVerdict() {
        for label in ["caf\u{E9}", "cafe\u{301}", "m\u{FC}nchen", "mu\u{308}nchen", "\u{AC00}", "\u{212B}ngstr\u{F6}m", "\u{130}"] {
            #expect(Confusables.homographLabel(label) == nil, "\(label)")
            #expect(Confusables.domainVerdict(label + ".com") == .reject("non-ASCII host"), "\(label)")
        }
        for label in ["\u{441}\u{430}f\u{E9}", "\u{441}\u{430}fe\u{301}"] {
            #expect(Confusables.homographLabel(label) == "cafe", "\(label)")
            #expect(Confusables.domainVerdict(label + ".com") == .reject("non-ASCII host, looks like “cafe.com”"), "\(label)")
        }
        #expect(Confusables.domainVerdict("\u{212A}elvin.com") == .reject("non-ASCII host, looks like “Kelvin.com”"))
        #expect(Confusables.domainVerdict("xn--elvin-r74b.com") == .reject("non-ASCII host, looks like “Kelvin.com”"))
        #expect(Confusables.domainVerdict("xn--mnchen-3ya.de") == .warning("punycode host label"))
        #expect(Confusables.domainVerdict("xn--caf-dma.com") == .warning("punycode host label"))
        // A mark first has nothing to sit on, decomposed or not.
        #expect(Confusables.homographLabel("\u{300}\u{430}pple") == nil)
        #expect(Confusables.homographLabel("\u{450}pple") == "epple", "ѐ first: е then U+0300, a twin and its mark")
    }

    // MARK: - Words

    /// Format (Cf) and Extend scalars neither end a word nor start one,
    /// per UAX #29 WB4, so a joiner or a number sign inside "Дavid" leaves
    /// the Cyrillic and the Latin in one word. `TextCheck` refuses the
    /// hidden ones first; the script rule answers on its own here.
    @Test(arguments: [
        "\u{200D}", "\u{200C}", "\u{600}", "\u{601}", "\u{602}", "\u{603}", "\u{604}", "\u{605}",
        "\u{AD}", "\u{2060}", "\u{FEFF}", "\u{E0041}", "\u{110BD}",
        "\u{301}", "\u{903}", "\u{20DD}", "\u{1F3FB}",
    ])
    func formatAndExtendScalarsStayInAWord(joiner: String) {
        let de = "\u{414}"
        #expect(Confusables.mixedScripts(in: de + joiner + "avid"), "\(joiner.debugDescription)")
        #expect(Confusables.mixedScripts(in: "pay" + joiner + "\u{43F}\u{430}\u{43B}"), "\(joiner.debugDescription)")
        #expect(Confusables.mixedScripts(in: "\u{3B1}" + joiner + "b"), "\(joiner.debugDescription)")
        #expect(Confusables.mixedScripts(in: "a" + joiner + joiner + "\u{562}"), "\(joiner.debugDescription)")
        // Across a space the word still ends, joiner or not.
        #expect(!Confusables.mixedScripts(in: "David" + joiner + " " + de + "\u{44D}"), "\(joiner.debugDescription)")
        #expect(!Confusables.mixedScripts(in: "David " + joiner + de + "\u{44D}"), "\(joiner.debugDescription)")
        // One script through a joiner is still one script.
        #expect(!Confusables.mixedScripts(in: "Da" + joiner + "vid"), "\(joiner.debugDescription)")
    }

    /// What ended a word before still does: whitespace, punctuation,
    /// symbols that are not emoji modifiers.
    @Test(arguments: [" ", "\u{A0}", "\u{2009}", "-", "\u{2019}", ".", "😀", "\u{20AC}", "\u{FFFD}", "\u{2B50}", "\u{1F1EE}"])
    func punctuationStillEndsAWord(separator: String) {
        #expect(!Confusables.mixedScripts(in: "\u{414}" + separator + "avid"), "\(separator.debugDescription)")
    }

    // MARK: - Whitespace

    /// A mark (Mn, Mc or Me) after whitespace is drawn on it and is part of
    /// it: a trailing space keeps trailing through the mark, the suggested
    /// text drops both, and a run of spaces runs on through the mark
    /// without growing by it.
    @Test(arguments: ["\u{301}", "\u{903}", "\u{20DD}"])
    func aMarkAfterWhitespaceIsWhitespace(mark: String) {
        let trailing = Verdict.warning("leading or trailing whitespace, use “David”")
        #expect(TextCheck.check("David \(mark)", maxBytes: 64) == trailing)
        #expect(TextCheck.check("David \(mark)\(mark)", maxBytes: 64) == trailing)
        #expect(TextCheck.check("David \(mark) ", maxBytes: 64) == trailing)
        #expect(TextCheck.check("David \(mark) \(mark)", maxBytes: 64) == trailing)
        #expect(TextCheck.check("David\u{A0}\(mark)", maxBytes: 64) == trailing)
        #expect(TextCheck.check(" \(mark)David", maxBytes: 64) == trailing)
        #expect(TextCheck.check(" \(mark)\(mark)David", maxBytes: 64) == trailing)
        #expect(TextCheck.check("\u{3000}\(mark) David", maxBytes: 64) == trailing)
        #expect(TextCheck.check(" \(mark)David \(mark)", maxBytes: 64) == trailing)
        #expect(FieldValidator.name("David \(mark)", limits: qr) == trailing)
        // A mark on the letter is the letter's, and stays in the suggestion.
        #expect(TextCheck.check("David\(mark) ", maxBytes: 64) == .warning("leading or trailing whitespace, use “David\(mark)”"))
        #expect(TextCheck.check(" David\(mark)", maxBytes: 64) == .warning("leading or trailing whitespace, use “David\(mark)”"))
        // Runs: the mark neither splits the run nor counts as a space.
        #expect(TextCheck.check("a  \(mark)  b", maxBytes: 64) == .warning("run of spaces"))
        #expect(TextCheck.check("a   \(mark) b", maxBytes: 64) == .warning("run of spaces"))
        #expect(TextCheck.check("a \(mark) \(mark) \(mark) \(mark)b", maxBytes: 64) == .warning("run of spaces"))
        #expect(TextCheck.check("a   \(mark)b", maxBytes: 64) == .ok)
        #expect(TextCheck.check("a \(mark) \(mark) \(mark)b", maxBytes: 64) == .ok)
        #expect(TextCheck.check("a\(mark)   b", maxBytes: 64) == .ok)
        #expect(TextCheck.check(" \(mark)a    b \(mark)", maxBytes: 64)
            == .warning("leading or trailing whitespace, use “a    b”; run of spaces"))
        // Nothing but whitespace and marks is empty, as before.
        #expect(TextCheck.check(" \(mark) ", maxBytes: 64) == .reject("empty"))
        #expect(TextCheck.check("\(mark) ", maxBytes: 64) == .reject("empty"))
        // A newline is not part of a run, mark or not.
        #expect(TextCheck.check("a\n\(mark)\n\(mark)\n\(mark)\n\(mark)b", maxBytes: 64, allowNewlines: true) == .ok)
    }
}
