import Foundation  // canonical decomposition, for `homographLabel`

/// Look-alike detection for names and hosts, after UTS #39 in spirit but
/// with small tables: the stdlib exposes no Script property, and a business
/// card needs the well-known cases, not the full confusables list.
public enum Confusables {
    /// True when any word mixes letters from two of Latin, Cyrillic, Greek
    /// and Armenian, the scripts with look-alikes among themselves. Words
    /// split on whitespace and punctuation; digits, marks and format
    /// controls belong to no script and end no word (UAX #29 WB4), so a
    /// joiner cannot cut "Дavid" in two. Han, kana and Hangul are scripts
    /// of their own but never count: Japanese and Korean text carries
    /// Latin brand names routinely, and CJK has no Latin look-alikes.
    /// Mixing across words is fine, so a bilingual "David Дэвид" passes.
    public static func mixedScripts(in s: String) -> Bool {
        var scripts: Set<Script> = []
        for scalar in s.unicodeScalars {
            guard isWordInternal(scalar) else {
                scripts.removeAll()
                continue
            }
            if let script = Script.of(scalar), script.isConfusable {
                scripts.insert(script)
                if scripts.count > 1 { return true }
            }
        }
        return false
    }

    /// The string with well-known look-alikes replaced by the ASCII they
    /// imitate, or nil when it has none. Not a full skeleton: other
    /// non-ASCII stays as it is.
    public static func looksLikeASCII(_ s: String) -> String? {
        var out = String.UnicodeScalarView()
        var changed = false
        for scalar in s.unicodeScalars {
            if let ascii = asciiLookalike(scalar) {
                out.append(ascii)
                changed = true
            } else {
                out.append(scalar)
            }
        }
        return changed ? String(out) : nil
    }

    /// A host fit to show as a tappable link: ASCII labels per RFC 1123
    /// (1–63 of `a-z`, `0-9`, `-`, hyphen not at either end), at most 253
    /// bytes in all, any letter case (the canonical form is lowercase).
    /// Non-ASCII hosts are rejected outright; when a label is a homograph
    /// (see `homographProblem`) the message names the ASCII it resembles,
    /// so the user reads "looks like github.com", never punycode.
    /// An IP address is rejected in every spelling: RFC 3696 §2 (a top-level
    /// label is never all digits) plus the WHATWG URL "ends in a number"
    /// rule catch `127.0.0.1`, `2130706433`, `0x7f000001` and `0177.0.0.1`
    /// alike. An `xn--` label is decoded (RFC 3492) and judged on its own
    /// as the text it spells: a homograph is refused the way the raw form
    /// is, and so is a label that starts with a mark, holds a look-alike
    /// of `.` or `/`, or mixes scripts (`decodedLabelProblem`); an honest
    /// IDN is accepted with a warning, since a browser may render it as
    /// something else.
    public static func domainVerdict(_ host: String) -> Verdict {
        guard !host.isEmpty else { return .reject("empty host") }
        guard host.utf8.count <= 253 else { return .reject("host over 253 bytes") }
        if let problem = TextCheck.problem(in: host) { return .reject(problem) }
        guard host.utf8.allSatisfy({ $0 < 0x80 }) else {
            return .reject(homographProblem(labels(of: host)) ?? "non-ASCII host")
        }
        let labels = host.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        for label in labels {
            guard (1...63).contains(label.count),
                  label.first != UInt8(ascii: "-"), label.last != UInt8(ascii: "-"),
                  label.allSatisfy(isLabelByte)
            else { return .reject("invalid host label") }
        }
        if let last = labels.last, isNumber(last) { return .reject("IP address") }
        guard labels.contains(where: isPunycode) else { return .ok }
        var spelled: [String] = []
        var decoded: [String] = []
        for label in labels {
            guard isPunycode(label) else {
                spelled.append(String(decoding: label, as: UTF8.self))
                continue
            }
            guard let text = Punycode.decode(label.dropFirst(4)),
                  !text.unicodeScalars.contains(where: { $0.properties.isWhitespace })
            else { return .reject("invalid punycode label") }
            spelled.append(text)
            decoded.append(text)
        }
        for text in decoded {
            if let problem = TextCheck.problem(in: text) { return .reject(problem) }
        }
        if let problem = homographProblem(spelled) { return .reject(problem) }
        for text in decoded {
            if let problem = decodedLabelProblem(text) { return .reject(problem) }
        }
        return .warning("punycode host label")
    }

    /// The labels of a host, split on U+002E at the scalar level. A mark at
    /// the start of a label fuses with the dot before it into one
    /// `Character`, so a `String.split` would miss that dot and judge the
    /// two labels as one.
    private static func labels(of host: String) -> [String] {
        host.unicodeScalars.split(separator: ".", omittingEmptySubsequences: false).map { String($0) }
    }

    /// The host with each homograph label replaced by the ASCII it
    /// imitates (`homographLabel`), or nil when no label is one.
    static func homographSkeleton(_ host: String) -> String? {
        let labels = labels(of: host)
        guard labels.contains(where: { homographLabel($0) != nil }) else { return nil }
        return labels.map { homographLabel($0) ?? $0 }.joined(separator: ".")
    }

    /// Why a host with a homograph label is refused, or nil when no label
    /// is one. What the message says the host looks like is always ASCII:
    /// the whole host when its other labels are ASCII (`аpple.evil.com`
    /// looks like `apple.evil.com`), else the offending label alone
    /// (`аpple.москва`: label `аpple` looks like `apple`), so an honest
    /// label is never named as something it is not.
    static func homographProblem(_ labels: [String]) -> String? {
        var skeletons: [String] = []
        var offender: (label: String, ascii: String)?
        for label in labels {
            guard let ascii = homographLabel(label) else {
                skeletons.append(label)
                continue
            }
            skeletons.append(ascii)
            if offender == nil { offender = (label, ascii) }
        }
        guard let offender else { return nil }
        let skeleton = skeletons.joined(separator: ".")
        guard skeleton.utf8.allSatisfy({ $0 < 0x80 }) else {
            return "label “\(offender.label)” looks like “\(offender.ascii)”"
        }
        return "non-ASCII host, looks like “\(skeleton)”"
    }

    /// The ASCII a label imitates when every scalar in it is ASCII or has
    /// an ASCII twin, at least one a twin (`аpple`, `gіthub`, `ｇｉｔｈｕｂ`,
    /// `аррӏе́`). Judged on the label's canonical decomposition (NFD), so
    /// the rule is closed under canonical equivalence: a precomposed
    /// letter is its base and marks (`ѐ` is `е` then U+0300, so `аррӏѐ`
    /// is `apple` in either spelling), and a singleton whose decomposition
    /// is ASCII (the Kelvin sign is `K`) is a twin. A mark (Mn, Mc, Me)
    /// belongs to the scalar before it and is dropped: `applé` is `apple`
    /// to the eye. Nil for an honest label, one keeping a letter no ASCII
    /// host has (`москва`, `ελλάδα`, `münchen`; UTS #39 §4, whole-script
    /// confusables), and for one with nothing before a mark.
    static func homographLabel(_ label: String) -> String? {
        var skeleton = String.UnicodeScalarView()
        var twins = false
        for scalar in label.unicodeScalars {
            if scalar.isASCII {
                skeleton.append(scalar)
                continue
            }
            // Scalar by scalar is the label's NFD: canonical reordering only
            // moves marks, and marks are dropped.
            let decomposed = String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars
            if decomposed.count == 1, let single = decomposed.first, single.isASCII {
                skeleton.append(single)
                twins = true
                continue
            }
            for part in decomposed {
                if part.isASCII {
                    skeleton.append(part)
                } else if let twin = asciiLookalike(part) {
                    skeleton.append(twin)
                    twins = true
                } else if isMark(part), !skeleton.isEmpty {
                    continue
                } else {
                    return nil
                }
            }
        }
        return twins ? String(skeleton) : nil
    }

    /// Why a decoded label is refused when no label is a homograph: it
    /// starts with a mark (RFC 5891 §4.2.3.2 forbids one; drawn, the mark
    /// lands on the dot before it), it holds a scalar that passes for `.`
    /// or `/` (UTS #46 maps U+3002, U+FF0E and U+FF61 to a dot, so no
    /// honest A-label spells one), or it mixes scripts.
    private static func decodedLabelProblem(_ text: String) -> String? {
        if text.unicodeScalars.first.map(isMark) == true { return "hidden character in punycode label" }
        if text.unicodeScalars.contains(where: isSeparatorLookalike) { return "look-alike dot or slash in punycode label" }
        if mixedScripts(in: text) { return "mixed scripts in punycode label" }
        return nil
    }

    /// Passes for `.` or `/` (`asciiLookalike`).
    private static func isSeparatorLookalike(_ scalar: Unicode.Scalar) -> Bool {
        guard let ascii = asciiLookalike(scalar) else { return false }
        return ascii == "." || ascii == "/"
    }

    /// Mn, Mc or Me: drawn on the scalar before it.
    static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// `xn--` and something after it, in any case.
    private static func isPunycode(_ label: some Collection<UInt8>) -> Bool {
        label.count > 4 && label.prefix(4).elementsEqual("xn--".utf8, by: { $0 | 0x20 == $1 })
    }

    /// All digits, or `0x` and hex digits: what a browser resolves as an
    /// IPv4 address (WHATWG URL §3.5).
    private static func isNumber(_ label: some Collection<UInt8>) -> Bool {
        if label.allSatisfy(isDigit) { return true }
        guard label.count >= 2, label.first == UInt8(ascii: "0"),
              label.dropFirst().first.map({ $0 | 0x20 }) == UInt8(ascii: "x")
        else { return false }
        return label.dropFirst(2).allSatisfy(isHexDigit)
    }

    private static func isLabelByte(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    private static func isDigit(_ b: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b)
    }

    private static func isHexDigit(_ b: UInt8) -> Bool {
        isDigit(b) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(b) || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(b)
    }

    /// Letters and numbers stay in a word, and so does what UAX #29 WB4
    /// skips over: Extend (marks, emoji modifiers) and Format (Cf: ZWJ,
    /// ZWNJ, U+0600–U+0605 and kin). Everything else ends it.
    private static func isWordInternal(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark, .format,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return scalar.properties.isEmojiModifier
        }
    }

    /// The ASCII a scalar is routinely mistaken for. Cyrillic and Greek
    /// letters that share a glyph with Latin, a few Latin and Armenian
    /// forms, the fullwidth block, the dashes that pass for `-`, and the
    /// dots and slashes that pass for `.` and `/` inside a host.
    static func asciiLookalike(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let ascii: UInt8
        switch scalar.value {
        // Cyrillic lowercase: а е о р с у х ѕ і ј һ ӏ ԁ ԛ ԝ
        case 0x0430: ascii = UInt8(ascii: "a")
        case 0x0435: ascii = UInt8(ascii: "e")
        case 0x043E: ascii = UInt8(ascii: "o")
        case 0x0440: ascii = UInt8(ascii: "p")
        case 0x0441: ascii = UInt8(ascii: "c")
        case 0x0443: ascii = UInt8(ascii: "y")
        case 0x0445: ascii = UInt8(ascii: "x")
        case 0x0455: ascii = UInt8(ascii: "s")
        case 0x0456: ascii = UInt8(ascii: "i")
        case 0x0458: ascii = UInt8(ascii: "j")
        case 0x04BB: ascii = UInt8(ascii: "h")
        case 0x04CF: ascii = UInt8(ascii: "l")
        case 0x0501: ascii = UInt8(ascii: "d")
        case 0x051B: ascii = UInt8(ascii: "q")
        case 0x051D: ascii = UInt8(ascii: "w")
        // Cyrillic uppercase: А В Е З К М Н О Р С Т У Х Ѕ І Ј Һ Ӏ Ԁ Ԛ Ԝ
        case 0x0410: ascii = UInt8(ascii: "A")
        case 0x0412: ascii = UInt8(ascii: "B")
        case 0x0415: ascii = UInt8(ascii: "E")
        case 0x0417: ascii = UInt8(ascii: "3")
        case 0x041A: ascii = UInt8(ascii: "K")
        case 0x041C: ascii = UInt8(ascii: "M")
        case 0x041D: ascii = UInt8(ascii: "H")
        case 0x041E: ascii = UInt8(ascii: "O")
        case 0x0420: ascii = UInt8(ascii: "P")
        case 0x0421: ascii = UInt8(ascii: "C")
        case 0x0422: ascii = UInt8(ascii: "T")
        case 0x0423: ascii = UInt8(ascii: "Y")
        case 0x0425: ascii = UInt8(ascii: "X")
        case 0x0405: ascii = UInt8(ascii: "S")
        case 0x0406: ascii = UInt8(ascii: "I")
        case 0x0408: ascii = UInt8(ascii: "J")
        case 0x04BA: ascii = UInt8(ascii: "H")
        case 0x04C0: ascii = UInt8(ascii: "I")
        case 0x0500: ascii = UInt8(ascii: "D")
        case 0x051A: ascii = UInt8(ascii: "Q")
        case 0x051C: ascii = UInt8(ascii: "W")
        // Greek lowercase: α ι κ ν ο ρ τ υ χ ω ϲ ϳ
        case 0x03B1: ascii = UInt8(ascii: "a")
        case 0x03B9: ascii = UInt8(ascii: "i")
        case 0x03BA: ascii = UInt8(ascii: "k")
        case 0x03BD: ascii = UInt8(ascii: "v")
        case 0x03BF: ascii = UInt8(ascii: "o")
        case 0x03C1: ascii = UInt8(ascii: "p")
        case 0x03C4: ascii = UInt8(ascii: "t")
        case 0x03C5: ascii = UInt8(ascii: "u")
        case 0x03C7: ascii = UInt8(ascii: "x")
        case 0x03C9: ascii = UInt8(ascii: "w")
        case 0x03F2: ascii = UInt8(ascii: "c")
        case 0x03F3: ascii = UInt8(ascii: "j")
        // Greek uppercase: Α Β Ε Ζ Η Ι Κ Μ Ν Ο Ρ Τ Υ Χ
        case 0x0391: ascii = UInt8(ascii: "A")
        case 0x0392: ascii = UInt8(ascii: "B")
        case 0x0395: ascii = UInt8(ascii: "E")
        case 0x0396: ascii = UInt8(ascii: "Z")
        case 0x0397: ascii = UInt8(ascii: "H")
        case 0x0399: ascii = UInt8(ascii: "I")
        case 0x039A: ascii = UInt8(ascii: "K")
        case 0x039C: ascii = UInt8(ascii: "M")
        case 0x039D: ascii = UInt8(ascii: "N")
        case 0x039F: ascii = UInt8(ascii: "O")
        case 0x03A1: ascii = UInt8(ascii: "P")
        case 0x03A4: ascii = UInt8(ascii: "T")
        case 0x03A5: ascii = UInt8(ascii: "Y")
        case 0x03A7: ascii = UInt8(ascii: "X")
        // Latin: ı ſ ȷ ɡ ℓ, the Kelvin sign
        case 0x0131: ascii = UInt8(ascii: "i")
        case 0x017F: ascii = UInt8(ascii: "s")
        case 0x0237: ascii = UInt8(ascii: "j")
        case 0x0261: ascii = UInt8(ascii: "g")
        case 0x2113: ascii = UInt8(ascii: "l")
        case 0x212A: ascii = UInt8(ascii: "K")
        // Armenian: հ ո ս օ Տ Օ
        case 0x0570: ascii = UInt8(ascii: "h")
        case 0x0578: ascii = UInt8(ascii: "n")
        case 0x057D: ascii = UInt8(ascii: "u")
        case 0x0585: ascii = UInt8(ascii: "o")
        case 0x054F: ascii = UInt8(ascii: "S")
        case 0x0555: ascii = UInt8(ascii: "O")
        // Fullwidth ASCII and ideographic space
        case 0xFF01...0xFF5E: ascii = UInt8(scalar.value - 0xFEE0)
        case 0x3000: ascii = UInt8(ascii: " ")
        // One dot leader, ideographic and halfwidth ideographic full stops;
        // division and fraction slashes
        case 0x2024, 0x3002, 0xFF61: ascii = UInt8(ascii: ".")
        case 0x2044, 0x2215: ascii = UInt8(ascii: "/")
        // Hyphen through horizontal bar, minus sign, small hyphen-minus
        case 0x2010...0x2015, 0x2212, 0xFE63: ascii = UInt8(ascii: "-")
        default: return nil
        }
        return Unicode.Scalar(ascii)
    }
}

extension Confusables {
    enum Script: Hashable, Sendable {
        case latin, cyrillic, greek, armenian, han, hiragana, katakana, hangul

        /// Has look-alikes in the other three.
        var isConfusable: Bool {
            switch self {
            case .latin, .cyrillic, .greek, .armenian: return true
            case .han, .hiragana, .katakana, .hangul: return false
            }
        }

        /// The script of a letter, by block. Nil for anything that is not a
        /// letter of a tabulated script: digits, marks, punctuation, and
        /// every other script.
        static func of(_ scalar: Unicode.Scalar) -> Script? {
            guard isLetter(scalar.properties.generalCategory) else { return nil }
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A, 0x00AA, 0x00BA, 0x00C0...0x00D6, 0x00D8...0x00F6,
                 0x00F8...0x02B8, 0x02E0...0x02E4,
                 0x1D00...0x1D25, 0x1D2C...0x1D5C, 0x1D62...0x1D65, 0x1D6B...0x1D77, 0x1D79...0x1DBE,
                 0x1E00...0x1EFF, 0x2071, 0x207F, 0x2090...0x209C, 0x212A, 0x212B, 0x2C60...0x2C7F,
                 0xA722...0xA787, 0xA78B...0xA7FF, 0xAB30...0xAB5A, 0xAB5C...0xAB64, 0xAB66...0xAB69,
                 0xFB00...0xFB06, 0xFF21...0xFF3A, 0xFF41...0xFF5A, 0x10780...0x107BA, 0x1DF00...0x1DF1E:
                return .latin
            case 0x0400...0x0481, 0x048A...0x052F, 0x1C80...0x1C88, 0x1D2B, 0x1D78,
                 0xA640...0xA66E, 0xA680...0xA69D, 0x1E030...0x1E08F:
                return .cyrillic
            case 0x0370...0x0373, 0x0376, 0x0377, 0x037A...0x037D, 0x037F, 0x0386, 0x0388...0x03FF,
                 0x1D26...0x1D2A, 0x1D5D...0x1D61, 0x1D66...0x1D6A, 0x1DBF, 0x1F00...0x1FFF, 0x2126, 0xAB65:
                return .greek
            case 0x0531...0x0556, 0x0559...0x0588, 0xFB13...0xFB17:
                return .armenian
            case 0x2E80...0x2FDF, 0x3005, 0x3007, 0x3021...0x3029, 0x3038...0x303B, 0x3400...0x4DBF,
                 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3134F:
                return .han
            case 0x3041...0x309F, 0x1B001...0x1B11F, 0x1B150...0x1B152:
                return .hiragana
            case 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F, 0x1B000, 0x1B164...0x1B167:
                return .katakana
            case 0x1100...0x11FF, 0x3131...0x318E, 0xA960...0xA97F, 0xAC00...0xD7FF, 0xFFA0...0xFFDC:
                return .hangul
            default:
                return nil
            }
        }

        private static func isLetter(_ category: Unicode.GeneralCategory) -> Bool {
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                return true
            default:
                return false
            }
        }
    }
}
