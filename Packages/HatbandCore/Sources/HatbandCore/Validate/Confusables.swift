/// Look-alike detection for names and hosts, after UTS #39 in spirit but
/// with small tables: the stdlib exposes no Script property, and a business
/// card needs the well-known cases, not the full confusables list.
public enum Confusables {
    /// True when any word mixes letters from two of Latin, Cyrillic, Greek
    /// and Armenian, the scripts with look-alikes among themselves. Words
    /// split on whitespace and punctuation; digits and marks belong to no
    /// script. Han, kana and Hangul are scripts of their own but never
    /// count: Japanese and Korean text carries Latin brand names routinely,
    /// and CJK has no Latin look-alikes. Mixing across words is fine, so a
    /// bilingual "David Дэвид" passes.
    public static func mixedScripts(in s: String) -> Bool {
        var scripts: Set<Script> = []
        for scalar in s.unicodeScalars {
            guard isWordCharacter(scalar.properties.generalCategory) else {
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
    /// Non-ASCII hosts are rejected outright; the message names the ASCII
    /// host they resemble so the user reads "looks like github.com", never
    /// punycode. An `xn--` label is accepted with a warning: the text on the
    /// card is not deceptive, but a browser may render it as something else.
    public static func domainVerdict(_ host: String) -> Verdict {
        guard !host.isEmpty else { return .reject("empty host") }
        guard host.utf8.count <= 253 else { return .reject("host over 253 bytes") }
        if let problem = TextCheck.problem(in: host) { return .reject(problem) }
        guard host.utf8.allSatisfy({ $0 < 0x80 }) else {
            if let skeleton = looksLikeASCII(host) {
                return .reject("non-ASCII host, looks like “\(skeleton)”")
            }
            return .reject("non-ASCII host")
        }
        var punycode = false
        for label in host.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false) {
            guard (1...63).contains(label.count),
                  label.first != UInt8(ascii: "-"), label.last != UInt8(ascii: "-"),
                  label.allSatisfy(isLabelByte)
            else { return .reject("invalid host label") }
            if label.count > 4, label.prefix(4).elementsEqual("xn--".utf8, by: { $0 | 0x20 == $1 }) {
                punycode = true
            }
        }
        return punycode ? .warning("punycode host label") : .ok
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

    /// Letters, marks and numbers stay in a word; everything else ends it.
    private static func isWordCharacter(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// The ASCII a scalar is routinely mistaken for. Cyrillic and Greek
    /// letters that share a glyph with Latin, a few Latin and Armenian
    /// forms, the fullwidth block, and the dots and slashes that pass for
    /// `.` and `/` inside a host.
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
        // One dot leader, ideographic full stop; division and fraction slashes
        case 0x2024, 0x3002: ascii = UInt8(ascii: ".")
        case 0x2044, 0x2215: ascii = UInt8(ascii: "/")
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
