import Testing
@testable import HatbandCore

// MARK: - Mixed scripts

/// One word with letters from two of Latin, Cyrillic, Greek, Armenian.
@Test(arguments: [
    "p\u{430}ypal",            // Cyrillic а
    "g\u{456}thub",            // Cyrillic і
    "J\u{43E}hn Smith",        // Cyrillic о in the first word only
    "Alph\u{3B1}",             // Greek α
    "\u{3A9}mega",             // Greek Ω, not in the look-alike table
    "\u{540}\u{561}\u{575}k",  // Armenian + Latin
    "\u{420}\u{443}\u{441}skiy",
    "Ελλάδαa",
    "a1\u{431}",               // digits belong to no script and do not end a word
    "abc\u{434}\u{435}",
    "\u{411}\u{430}\u{301}\u{43D}\u{43A}a",  // combining mark stays in the word
    "東京 T\u{43E}kyo",          // Han is fine; Cyrillic о inside "Tоkyo" is not
])
func flagsMixedWords(s: String) {
    #expect(Confusables.mixedScripts(in: s))
}

/// Pure scripts, mixing across words, CJK with Latin, and Latin diacritics.
@Test(arguments: [
    "",
    "Leopold Bloom",
    "Лев Толстой",
    "Ελλάδα",
    "Հայաստան",
    "David Дэвид",       // bilingual name: one script per word
    "Ελένη Smith",
    "東京 Tokyo",
    "東京Tokyo",          // Han and Latin share a word: never flagged
    "ソニーSony",
    "Sonyソニー",
    "삼성 Samsung",
    "삼성Samsung",
    "東京タワー",          // Han + Katakana, as Japanese is written
    "\u{FF34}\u{FF4F}\u{FF4B}\u{FF59}\u{FF4F}東京",  // fullwidth Latin + Han
    "ünïcödé",
    "caf\u{E9}", "na\u{EF}ve", "Zo\u{EB}", "\u{C9}mile", "Stra\u{DF}e", "\u{FB01}le",
    "O'Brien", "Jean-Luc",
    "abc-где", "abc'где", "abc_где", "abc.где", "abc/где", "abc😀где", "abc,где", "abc(где)",
    "\u{411}\u{430}\u{301}\u{43D}\u{43A}",
    "x²", "Ⅻ", "😀", "👋🏽",
    "\u{131}", "\u{17F}", "\u{261}",  // Latin look-alikes alone are still Latin
    "abcعربي",          // Arabic has no Latin look-alikes and no table
    "abcעברית",
    "abcहिन्दी",
])
func passesSingleScriptWords(s: String) {
    #expect(!Confusables.mixedScripts(in: s))
}

@Test(arguments: [
    ("a", Confusables.Script.latin), ("Z", .latin), ("\u{DF}", .latin), ("\u{1C5}", .latin), ("\u{1D00}", .latin),
    ("\u{212A}", .latin), ("\u{FB01}", .latin), ("\u{FF21}", .latin), ("\u{261}", .latin), ("\u{2B0}", .latin),
    ("\u{44F}", .cyrillic), ("\u{416}", .cyrillic), ("\u{1D2B}", .cyrillic), ("\u{A641}", .cyrillic),
    ("\u{3C9}", .greek), ("\u{3A9}", .greek), ("\u{2126}", .greek), ("\u{1D26}", .greek), ("\u{1F00}", .greek),
    ("\u{561}", .armenian), ("\u{531}", .armenian), ("\u{FB13}", .armenian),
    ("東", .han), ("\u{3005}", .han), ("\u{20000}", .han),
    ("あ", .hiragana), ("ア", .katakana), ("\u{30FC}", .katakana), ("\u{FF71}", .katakana),
    ("한", .hangul), ("\u{1100}", .hangul),
])
func classifiesLetters(s: String, script: Confusables.Script) {
    #expect(Confusables.Script.of(s.unicodeScalars.first!) == script)
}

@Test(arguments: ["1", ".", " ", "-", "_", "\u{301}", "ع", "א", "ह", "Ⅻ", "²", "😀", "€", "\u{3007}", "$", "\u{FE0F}"])
func lettersOnlyHaveScripts(s: String) {
    #expect(Confusables.Script.of(s.unicodeScalars.first!) == nil)
}

@Test func onlyFourScriptsMix() {
    let mixing: [Confusables.Script] = [.latin, .cyrillic, .greek, .armenian]
    let free: [Confusables.Script] = [.han, .hiragana, .katakana, .hangul]
    let allMix = mixing.allSatisfy { $0.isConfusable }
    let noneFree = !free.contains { $0.isConfusable }
    #expect(allMix)
    #expect(noneFree)
}

// MARK: - Look-alikes

@Test(arguments: [
    ("g\u{456}thub.com", "github.com"),
    ("\u{430}pple.com", "apple.com"),
    ("p\u{430}ypal", "paypal"),
    ("g\u{43E}\u{43E}gle\u{2024}com", "google.com"),          // Cyrillic о and one dot leader
    ("\u{FF47}\u{FF49}\u{FF54}\u{FF48}\u{FF55}\u{FF42}\u{FF0E}\u{FF43}\u{FF4F}\u{FF4D}", "github.com"),
    ("\u{FF28}\u{FF45}\u{FF4C}\u{FF4C}\u{FF4F}\u{3000}\u{FF37}\u{FF4F}\u{FF52}\u{FF4C}\u{FF44}", "Hello World"),
    ("github\u{3002}com", "github.com"),
    ("\u{421}\u{430}\u{440}\u{430}", "Capa"),                 // all Cyrillic, every letter a look-alike
    ("\u{455}\u{441}\u{43E}\u{440}\u{435}", "scope"),
    ("\u{391}\u{392}\u{393}", "AB\u{393}"),                   // Γ has no ASCII twin and stays
    ("\u{3B1}/\u{3B2}", "a/\u{3B2}"),
    ("1\u{2215}2", "1/2"), ("a\u{2044}b", "a/b"),
    ("\u{131}\u{237}", "ij"), ("\u{17F}", "s"), ("\u{261}", "g"), ("\u{2113}", "l"), ("\u{212A}", "K"),
    ("\u{585}", "o"), ("\u{578}", "n"), ("\u{57D}", "u"), ("\u{570}", "h"), ("\u{54F}", "S"), ("\u{555}", "O"),
    ("\u{417}", "3"),
    ("mixed ünï \u{430}nd cyrillic", "mixed ünï and cyrillic"),
])
func rendersASCIISkeleton(s: String, skeleton: String) {
    #expect(Confusables.looksLikeASCII(s) == skeleton)
}

@Test(arguments: ["", "github.com", "Leopold Bloom", "münchen", "\u{3A9}mega", "東京", "\u{41B}\u{436}", "😀", "\u{DF}", "\u{393}", "\u{2014}"])
func noSkeletonWithoutLookalikes(s: String) {
    #expect(Confusables.looksLikeASCII(s) == nil)
}

/// Every table entry maps to one ASCII scalar, the table never rewrites
/// ASCII, and a skeleton has no look-alikes left in it.
@Test func lookalikeTableIsASCIIOnlyAndAcyclic() {
    var count = 0
    for value in UInt32(0)...0x10FFFF {
        guard let scalar = Unicode.Scalar(value) else { continue }
        guard let ascii = Confusables.asciiLookalike(scalar) else { continue }
        count += 1
        #expect(scalar.value >= 0x80, "ASCII must not be rewritten")
        #expect(ascii.isASCII)
        #expect(Confusables.asciiLookalike(ascii) == nil)
    }
    #expect(count == 94 + 1 + 4 + 74, "fullwidth block, ideographic space, dots and slashes, letters")
}

// MARK: - Hosts

@Test(arguments: [
    ("github.com", Verdict.ok),
    ("GitHub.com", .ok),
    ("GITHUB.COM", .ok),
    ("a", .ok),
    ("a.b", .ok),
    ("127.0.0.1", .ok),
    ("nnix.com", .ok),
    ("sub-domain.example.co.uk", .ok),
    ("a1-b2.c3", .ok),
    ("xn--mnchen-3ya.de", .warning("punycode host label")),
    ("XN--MNCHEN-3YA.DE", .warning("punycode host label")),
    ("www.xn--80ak6aa92e.com", .warning("punycode host label")),
    ("", .reject("empty host")),
    ("g\u{456}thub.com", .reject("non-ASCII host, looks like “github.com”")),
    ("\u{430}pple.com", .reject("non-ASCII host, looks like “apple.com”")),
    ("\u{FF47}\u{FF49}\u{FF54}\u{FF48}\u{FF55}\u{FF42}.com", .reject("non-ASCII host, looks like “github.com”")),
    ("g\u{43E}\u{43E}gle\u{2024}com", .reject("non-ASCII host, looks like “google.com”")),
    ("münchen.de", .reject("non-ASCII host")),
    ("東京.jp", .reject("non-ASCII host")),
    ("example.com\u{0}", .reject("control character")),
    ("exa\u{200B}mple.com", .reject("invisible character")),
    ("example.com\u{202E}", .reject("bidirectional control character")),
    ("-a.com", .reject("invalid host label")),
    ("a-.com", .reject("invalid host label")),
    ("a..com", .reject("invalid host label")),
    (".a", .reject("invalid host label")),
    ("a.", .reject("invalid host label")),
    (".", .reject("invalid host label")),
    ("a_b.com", .reject("invalid host label")),
    ("a b.com", .reject("invalid host label")),
    ("a/b", .reject("invalid host label")),
    ("[::1]", .reject("invalid host label")),
    ("a:80", .reject("invalid host label")),
    ("xn--", .reject("invalid host label")),
    ("user@host", .reject("invalid host label")),
])
func judgesHosts(host: String, verdict: Verdict) {
    #expect(Confusables.domainVerdict(host) == verdict)
}

@Test func hostLabelAndTotalLengthBoundaries() {
    let label63 = String(repeating: "a", count: 63)
    #expect(Confusables.domainVerdict(label63 + ".com") == .ok)
    #expect(Confusables.domainVerdict(label63 + "a.com") == .reject("invalid host label"))
    let host253 = [label63, label63, label63, String(repeating: "b", count: 61)].joined(separator: ".")
    #expect(host253.utf8.count == 253)
    #expect(Confusables.domainVerdict(host253) == .ok)
    let host254 = [label63, label63, label63, String(repeating: "b", count: 62)].joined(separator: ".")
    #expect(host254.utf8.count == 254)
    #expect(Confusables.domainVerdict(host254) == .reject("host over 253 bytes"))
    // Bytes, not characters: a long non-ASCII host is over before it is non-ASCII.
    let cyrillic = String(repeating: "\u{44F}", count: 127)
    #expect(cyrillic.utf8.count == 254)
    #expect(Confusables.domainVerdict(cyrillic) == .reject("host over 253 bytes"))
}
