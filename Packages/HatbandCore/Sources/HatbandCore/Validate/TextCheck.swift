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
    /// and host checks so every string gets the same scan.
    static func problem(_ scalar: Unicode.Scalar, allowNewlines: Bool = false) -> String? {
        switch scalar.value {
        case 0x0A where allowNewlines:
            return nil
        case 0x00...0x1F, 0x7F...0x9F:
            return "control character"
        // Bidi controls (UAX #9) reverse the displayed text.
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
            return "bidirectional control character"
        // Zero-width and other invisibles: soft hyphen, grapheme joiner,
        // Mongolian vowel separator, ZW space/non-joiner/joiner, line and
        // paragraph separators, word joiner and invisible operators,
        // deprecated format controls, BOM, interlinear annotation, and the
        // tag block that smuggles ASCII into text nobody can see.
        case 0x00AD, 0x034F, 0x180E, 0x200B...0x200D, 0x2028, 0x2029, 0x2060...0x2064,
             0x206A...0x206F, 0xFEFF, 0xFFF9...0xFFFB, 0xE0000...0xE007F:
            return "invisible character"
        default:
            switch scalar.properties.generalCategory {
            // Noncharacters (U+FDD0–U+FDEF, U+xxFFFE/F) are unassigned.
            // Assignment follows the stdlib's Unicode version.
            case .unassigned, .privateUse, .surrogate:
                return "unassigned or private-use character"
            default:
                return nil
            }
        }
    }

    static func problem(in s: String, allowNewlines: Bool = false) -> String? {
        for scalar in s.unicodeScalars {
            if let problem = problem(scalar, allowNewlines: allowNewlines) { return problem }
        }
        return nil
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
