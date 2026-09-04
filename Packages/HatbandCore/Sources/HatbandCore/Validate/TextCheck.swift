/// Character-level rules for every text a card carries. Rejections are for
/// what can hide, spoof or break rendering; warnings for what merely looks
/// off. Swift strings cannot hold unpaired surrogates, so those never arrive.
public enum TextCheck {
    /// `s` must be non-blank and at most `maxBytes` of UTF-8. `\n` is a
    /// control character unless `allowNewlines`; `\r` always is.
    public static func check(_ s: String, maxBytes: Int, allowNewlines: Bool = false) -> Verdict {
        let scalars = s.unicodeScalars
        let trimmed = trimmed(scalars)
        guard !trimmed.isEmpty else { return .reject("empty") }
        guard s.utf8.count <= maxBytes else { return .reject("over \(maxBytes) bytes") }
        if let problem = problem(in: s, allowNewlines: allowNewlines) { return .reject(problem) }
        // Marks and selectors alone draw nothing: empty to the eye.
        guard trimmed.contains(where: isVisible) else { return .reject("empty") }

        var verdict = Verdict.ok
        if Confusables.mixedScripts(in: s) {
            if let skeleton = Confusables.looksLikeASCII(String(trimmed)) {
                verdict = .warning("mixed scripts, looks like “\(skeleton)”")
            } else {
                verdict = .warning("mixed scripts")
            }
        }
        if trimmed.startIndex != scalars.startIndex || trimmed.endIndex != scalars.endIndex {
            verdict = verdict.merged(with: .warning("leading or trailing whitespace, use “\(String(trimmed))”"))
        }
        if hasSpaceRun(scalars) {
            verdict = verdict.merged(with: .warning("run of spaces"))
        }
        return verdict
    }

    /// Why a scalar is never allowed in card text, or nil. Shared by the URL
    /// and host checks so every string gets the same scan. Three invisibles
    /// are allowed in context by `problem(in:)`, never alone.
    static func problem(_ scalar: Unicode.Scalar, allowNewlines: Bool = false) -> String? {
        switch scalar.value {
        case 0x0A where allowNewlines:
            return nil
        case 0x00...0x1F, 0x7F...0x9F:
            return "control character"
        // Bidi controls (UAX #9) reverse the displayed text.
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
            return "bidirectional control character"
        // Line and paragraph separators, and the blank Braille cell: a
        // symbol that draws nothing.
        case 0x2028, 0x2029, 0x2800:
            return "invisible character"
        default:
            switch scalar.properties.generalCategory {
            // Noncharacters (U+FDD0–U+FDEF, U+xxFFFE/F) are unassigned.
            // Assignment follows the stdlib's Unicode version.
            case .unassigned, .privateUse, .surrogate:
                return "unassigned or private-use character"
            // Format controls are layout instructions, not text: soft hyphen,
            // zero-width space and joiners, BOM, interlinear annotation, the
            // hieroglyph and shorthand controls, and the tag block that
            // smuggles ASCII into text nobody can see.
            case .format:
                return "invisible character"
            default:
                // Default_Ignorable_Code_Point (UAX #44) beyond Cf: Hangul
                // fillers, the grapheme joiner, Khmer and Mongolian selectors
                // and variation selectors render as nothing, so they can hide
                // anything.
                return scalar.properties.isDefaultIgnorableCodePoint ? "invisible character" : nil
            }
        }
    }

    /// The first problem in `s`, or nil. Three invisibles are allowed where
    /// they do their job and nowhere else: a variation selector (U+FE00–FE0F,
    /// U+E0100–E01EF) right after a scalar that is not itself ignorable, a
    /// ZWJ between two pictographs (the rainbow flag, a family), and a ZWNJ
    /// between two Arabic letters (Persian and Urdu spell with it; RFC 5892
    /// Appendix A.1 allows the same).
    static func problem(in s: String, allowNewlines: Bool = false) -> String? {
        let scalars = s.unicodeScalars
        var previous: Unicode.Scalar?
        var base: Unicode.Scalar?  // the last scalar that was not a mark or selector
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            index = scalars.index(after: index)
            let next = index < scalars.endIndex ? scalars[index] : nil
            let allowed: Bool
            switch scalar.value {
            case 0xFE00...0xFE0F, 0xE0100...0xE01EF:
                allowed = previous.map { !$0.properties.isDefaultIgnorableCodePoint } ?? false
            case 0x200D:
                allowed = base.map(isPictograph) == true && next.map(isPictograph) == true
            case 0x200C:
                allowed = base.map(isArabicLetter) == true && next.map(isArabicLetter) == true
            default:
                if let problem = problem(scalar, allowNewlines: allowNewlines) { return problem }
                allowed = true
            }
            guard allowed else { return "invisible character" }
            previous = scalar
            if !attaches(scalar) { base = scalar }
        }
        return nil
    }

    /// Marks and variation selectors belong to the scalar before them.
    private static func attaches(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xFE00...0xFE0F, 0xE0100...0xE01EF: return true
        default: return scalar.properties.generalCategory == .nonspacingMark
        }
    }

    /// Extended_Pictographic, near enough: the stdlib has no such property,
    /// and every emoji outside ASCII (`#`, `*`, the digits) is one.
    private static func isPictograph(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x80 && scalar.properties.isEmoji
    }

    /// A letter in one of the Arabic blocks.
    private static func isArabicLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
            default: return false
            }
        default:
            return false
        }
    }

    /// Draws something of its own: not whitespace, a mark, a format control
    /// or a default-ignorable.
    private static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
        guard !scalar.properties.isWhitespace, !scalar.properties.isDefaultIgnorableCodePoint else { return false }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .format: return false
        default: return true
        }
    }

    /// Unicode White_Space stripped from both ends.
    private static func trimmed(_ scalars: String.UnicodeScalarView) -> String.UnicodeScalarView.SubSequence {
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, scalars[start].properties.isWhitespace { start = scalars.index(after: start) }
        while start < end, scalars[scalars.index(before: end)].properties.isWhitespace { end = scalars.index(before: end) }
        return scalars[start..<end]
    }

    /// More than three consecutive spaces of any kind, newlines aside.
    private static func hasSpaceRun(_ scalars: String.UnicodeScalarView) -> Bool {
        var run = 0
        for scalar in scalars {
            if scalar.properties.isWhitespace, scalar.value != 0x0A {
                run += 1
                if run > 3 { return true }
            } else {
                run = 0
            }
        }
        return false
    }
}
