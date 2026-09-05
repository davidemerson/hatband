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
    ("my\u{2010}site.com", "my-site.com"),                    // hyphen
    ("a\u{2013}b\u{2014}c\u{2015}d", "a-b-c-d"),               // en dash, em dash, horizontal bar
    ("\u{2212}1", "-1"), ("\u{FE63}", "-"), ("\u{2011}", "-"), ("\u{2012}", "-"),
    ("mixed ünï \u{430}nd cyrillic", "mixed ünï and cyrillic"),
])
func rendersASCIISkeleton(s: String, skeleton: String) {
    #expect(Confusables.looksLikeASCII(s) == skeleton)
}

@Test(arguments: ["", "github.com", "Leopold Bloom", "münchen", "\u{3A9}mega", "東京", "\u{41B}\u{436}", "😀", "\u{DF}", "\u{393}", "\u{2026}", "\u{B7}", "\u{2043}"])
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
    #expect(count == 94 + 1 + 5 + 8 + 74, "fullwidth block, ideographic space, dots and slashes, dashes, letters")
}

// MARK: - Hosts

@Test(arguments: [
    ("github.com", Verdict.ok),
    ("GitHub.com", .ok),
    ("GITHUB.COM", .ok),
    ("a", .ok),
    ("a.b", .ok),
    ("localhost", .ok),
    ("nnix.com", .ok),
    ("sub-domain.example.co.uk", .ok),
    ("a1-b2.c3", .ok),
    ("xn--mnchen-3ya.de", .warning("punycode host label")),
    ("XN--MNCHEN-3YA.DE", .warning("punycode host label")),
    ("", .reject("empty host")),
    ("127.0.0.1", .reject("IP address")),
    ("www.xn--80ak6aa92e.com", .reject("non-ASCII host, looks like “www.apple.com”")),
    ("my\u{2010}site.com", .reject("non-ASCII host, looks like “my-site.com”")),
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

/// Every IPv4 spelling a browser resolves (WHATWG URL §3.5) and the
/// all-digit top-level label RFC 3696 §2 rules out are addresses, not
/// names, by every path that reaches a host.
@Test(arguments: ["127.0.0.1", "0.0.0.0", "255.255.255.255", "256.256.256.256", "2130706433", "0x7f000001", "0X7F000001", "0x",
                  "0177.0.0.1", "0x7f.0.0.1", "1.0x7f", "example.123", "a.b.0", "1"])
func rejectsIPAddresses(host: String) {
    #expect(Confusables.domainVerdict(host) == .reject("IP address"))
    #expect(URLPolicy.verdict(for: "https://" + host) == .reject("IP address"))
    #expect(URLPolicy.verdict(for: "mailto:a@" + host) == .reject("IP address"))
    #expect(!URLPolicy.isTappable("https://" + host))
}

/// Hex needs `0x`; a label that merely has digits in it is a name.
@Test(arguments: ["1e3", "1x", "0xg", "x0", "123.com", "1.a", "a1", "1-1.a", "3com.com"])
func numericLookingNamesAreNames(host: String) {
    #expect(Confusables.domainVerdict(host) == .ok)
}

/// An `xn--` label is judged by what it spells: a homograph is refused with
/// the message its raw form gets, an honest IDN keeps the warning.
@Test(arguments: [
    ("xn--pple-43d.com", Verdict.reject("non-ASCII host, looks like “apple.com”")),
    ("xn--80ak6aa92e.com", .reject("non-ASCII host, looks like “apple.com”")),
    ("www.xn--80ak6aa92e.com", .reject("non-ASCII host, looks like “www.apple.com”")),
    ("xn--pypal-4ve.com", .reject("non-ASCII host, looks like “paypal.com”")),
    ("XN--PPLE-43D.COM", .reject("non-ASCII host, looks like “aPPLE.COM”")),
    ("xn--eastwest-3m3d.com", .reject("non-ASCII host, looks like “east-west.com”")),
    ("xn--mega-ukd.com", .reject("mixed scripts in punycode label")),        // Ωmega
    ("xn--ab-g1t.com", .reject("invisible character")),                       // a​b, a zero-width space between
    ("xn--a.com", .reject("control character")),                              // U+0080
    ("xn--b.com", .reject("invalid punycode label")),                         // ends inside a number
    ("xn--a_b.com", .reject("invalid host label")),
    ("xn--abc-.com", .reject("invalid host label")),
    ("xn--mnchen-3ya.de", .warning("punycode host label")),
    ("XN--MNCHEN-3YA.DE", .warning("punycode host label")),
    ("xn--9ca.fr", .warning("punycode host label")),                          // é
    ("xn--ghbgi.com", .warning("punycode host label")),                       // Arabic
    ("xn--tgb9bvy774f.ir", .warning("punycode host label")),                  // Persian, with a ZWNJ
    ("xn--i-7iq.ws", .warning("punycode host label")),                        // i❤
    ("xn--3b-ww4c5e180e575a65lsy2b.jp", .warning("punycode host label")),     // 3年B組金八先生
])
func judgesPunycodeHosts(host: String, verdict: Verdict) {
    #expect(Confusables.domainVerdict(host) == verdict)
    #expect(URLPolicy.verdict(for: "https://" + host) == verdict)
    #expect(URLPolicy.verdict(for: "mailto:a@" + host) == verdict)
}

// MARK: - Punycode

/// RFC 3492 §7.1 sample strings (A)–(S), then the labels that matter here.
@Test(arguments: [
    ("egbpdaj6bu4bxfgehfvwxn", "\u{644}\u{64A}\u{647}\u{645}\u{627}\u{628}\u{62A}\u{643}\u{644}\u{645}\u{648}\u{634}\u{639}\u{631}\u{628}\u{64A}\u{61F}"),
    ("ihqwcrb4cv8a8dqg056pqjye", "\u{4ED6}\u{4EEC}\u{4E3A}\u{4EC0}\u{4E48}\u{4E0D}\u{8BF4}\u{4E2D}\u{6587}"),
    ("ihqwctvzc91f659drss3x8bo0yb", "\u{4ED6}\u{5011}\u{7232}\u{4EC0}\u{9EBD}\u{4E0D}\u{8AAA}\u{4E2D}\u{6587}"),
    ("Proprostnemluvesky-uyb24dma41a", "Pro\u{10D}prost\u{11B}nemluv\u{ED}\u{10D}esky"),
    ("4dbcagdahymbxekheh6e0a7fei0b", "\u{5DC}\u{5DE}\u{5D4}\u{5D4}\u{5DD}\u{5E4}\u{5E9}\u{5D5}\u{5D8}\u{5DC}\u{5D0}\u{5DE}\u{5D3}\u{5D1}\u{5E8}\u{5D9}\u{5DD}\u{5E2}\u{5D1}\u{5E8}\u{5D9}\u{5EA}"),
    ("i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd",
     "\u{92F}\u{939}\u{932}\u{94B}\u{917}\u{939}\u{93F}\u{928}\u{94D}\u{926}\u{940}\u{915}\u{94D}\u{92F}\u{94B}\u{902}\u{928}\u{939}\u{940}\u{902}\u{92C}\u{94B}\u{932}\u{938}\u{915}\u{924}\u{947}\u{939}\u{948}\u{902}"),
    ("n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa",
     "\u{306A}\u{305C}\u{307F}\u{3093}\u{306A}\u{65E5}\u{672C}\u{8A9E}\u{3092}\u{8A71}\u{3057}\u{3066}\u{304F}\u{308C}\u{306A}\u{3044}\u{306E}\u{304B}"),
    ("989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c",
     "\u{C138}\u{ACC4}\u{C758}\u{BAA8}\u{B4E0}\u{C0AC}\u{B78C}\u{B4E4}\u{C774}\u{D55C}\u{AD6D}\u{C5B4}\u{B97C}\u{C774}\u{D574}\u{D55C}\u{B2E4}\u{BA74}\u{C5BC}\u{B9C8}\u{B098}\u{C88B}\u{C744}\u{AE4C}"),
    ("b1abfaaepdrnnbgefbaDotcwatmq2g4l",
     "\u{43F}\u{43E}\u{447}\u{435}\u{43C}\u{443}\u{436}\u{435}\u{43E}\u{43D}\u{438}\u{43D}\u{435}\u{433}\u{43E}\u{432}\u{43E}\u{440}\u{44F}\u{442}\u{43F}\u{43E}\u{440}\u{443}\u{441}\u{441}\u{43A}\u{438}"),
    ("PorqunopuedensimplementehablarenEspaol-fmd56a", "Porqu\u{E9}nopuedensimplementehablarenEspa\u{F1}ol"),
    ("TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g", "T\u{1EA1}isaoh\u{1ECD}kh\u{F4}ngth\u{1EC3}ch\u{1EC9}n\u{F3}iti\u{1EBF}ngVi\u{1EC7}t"),
    ("3B-ww4c5e180e575a65lsy2b", "3\u{5E74}B\u{7D44}\u{91D1}\u{516B}\u{5148}\u{751F}"),
    ("-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n", "\u{5B89}\u{5BA4}\u{5948}\u{7F8E}\u{6075}-with-SUPER-MONKEYS"),
    ("Hello-Another-Way--fc4qua05auwb3674vfr0b", "Hello-Another-Way-\u{305D}\u{308C}\u{305E}\u{308C}\u{306E}\u{5834}\u{6240}"),
    ("2-u9tlzr9756bt3uc0v", "\u{3072}\u{3068}\u{3064}\u{5C4B}\u{6839}\u{306E}\u{4E0B}2"),
    ("MajiKoi5-783gue6qz075azm5e", "Maji\u{3067}Koi\u{3059}\u{308B}5\u{79D2}\u{524D}"),
    ("de-jg4avhby1noc0d", "\u{30D1}\u{30D5}\u{30A3}\u{30FC}de\u{30EB}\u{30F3}\u{30D0}"),
    ("d9juau41awczczp", "\u{305D}\u{306E}\u{30B9}\u{30D4}\u{30FC}\u{30C9}\u{3067}"),
    ("-> $1.00 <--", "-> $1.00 <-"),
    ("pple-43d", "\u{430}pple"),
    ("80ak6aa92e", "\u{430}\u{440}\u{440}\u{4CF}\u{435}"),
    ("mnchen-3ya", "m\u{FC}nchen"),
    ("MNCHEN-3YA", "M\u{FC}NCHEN"),                                            // digits in either case
    ("a", "\u{80}"),
    ("abc-", "abc"),
    ("-", ""),
    ("", ""),
])
func decodesPunycode(encoded: String, decoded: String) {
    #expect(Punycode.decode(Array(encoded.utf8)) == decoded)
}

/// Input ending inside a number, a byte outside the digit alphabet, and a
/// code point that is not a scalar all fail rather than guess.
@Test(arguments: ["b", "8", "c8", "9999", "99999999999", "ZZZZZZZZZZZZZZ", "a_b", "a b", "\u{E9}", "\u{E9}-a",
                  "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", String(repeating: "9", count: 200)])
func refusesBadPunycode(encoded: String) {
    #expect(Punycode.decode(Array(encoded.utf8)) == nil)
}
