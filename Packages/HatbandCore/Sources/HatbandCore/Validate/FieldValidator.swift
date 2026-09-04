/// One check per field, composing `TextCheck`, `Confusables` and `URLPolicy`
/// under a `Limits` preset. Absent fields are never checked; a present one
/// must be usable as stored (see the HB1 field registry for stored forms).
public enum FieldValidator {
    public static func name(_ s: String, limits: Limits) -> Verdict {
        TextCheck.check(s, maxBytes: limits.name)
    }

    public static func company(_ s: String, limits: Limits) -> Verdict {
        TextCheck.check(s, maxBytes: limits.company)
    }

    public static func email(_ s: String, limits: Limits) -> Verdict {
        email(s, maxBytes: limits.email)
    }

    /// Stored form is strict E.164: `+` and digits, no separators.
    public static func phone(_ s: String, limits: Limits) -> Verdict {
        phone(s, maxBytes: limits.phone)
    }

    /// Stored without a scheme (`nnix.com/~bloom`); checked as its https URL.
    public static func website(_ s: String, limits: Limits) -> Verdict {
        if let failure = asciiPrelude(s, maxBytes: limits.website) { return failure }
        guard !s.utf8.starts(with: "//".utf8), !hasSchemeSeparator(s) else { return .reject("scheme in website") }
        return URLPolicy.verdict(for: "https://" + s)
    }

    /// A GitHub, LinkedIn or Calendly identifier (`bloom`, `bloom/coffee`),
    /// or a Mastodon `user@instance`. ASCII only: every one of these sites
    /// keeps its identifiers in ASCII, and a look-alike here is a phishing
    /// link.
    public static func handle(_ s: String, limits: Limits) -> Verdict {
        if let failure = asciiPrelude(s, maxBytes: limits.handle) { return failure }
        let bytes = Array(s.utf8)
        if let at = bytes.firstIndex(of: UInt8(ascii: "@")) {
            guard at > 0, isSlug(bytes[..<at]) else { return .reject("invalid handle") }
            return Confusables.domainVerdict(String(decoding: bytes[(at + 1)...], as: UTF8.self))
        }
        guard isSlug(bytes[...]) else { return .reject("invalid handle") }
        return .ok
    }

    /// A pasted `signal.me` link: `#p/+E.164` (discloses the number) or
    /// `#eu/<username token>`.
    public static func signalURL(_ s: String, limits: Limits) -> Verdict {
        if let failure = asciiPrelude(s, maxBytes: limits.signalURL) { return failure }
        let verdict = URLPolicy.verdict(for: s)
        guard verdict.isAccepted else { return verdict }
        let lower = s.lowercased()
        guard lower.hasPrefix("https://signal.me/#") else { return .reject("not a signal.me link") }
        let fragment = Array(s.utf8.dropFirst("https://signal.me/#".utf8.count))
        if fragment.starts(with: "p/".utf8), URLPolicy.isE164(fragment.dropFirst(2)) { return verdict }
        if fragment.starts(with: "eu/".utf8), fragment.count > 3, fragment.dropFirst(3).allSatisfy(isBase64URLByte) { return verdict }
        return .reject("not a signal.me link")
    }

    public static func customLabel(_ s: String, limits: Limits) -> Verdict {
        TextCheck.check(s, maxBytes: limits.customLabel)
    }

    /// Text may span lines (an address); the other kinds are checked as the
    /// link, address or number they claim to be. A key is printable ASCII,
    /// the shape of every `ssh-…`, `age1…` and fingerprint line.
    public static func customValue(_ s: String, kind: CustomKind, limits: Limits) -> Verdict {
        guard limits.customKinds.contains(kind) else { return .reject("kind not allowed") }
        switch kind {
        case .text:
            return TextCheck.check(s, maxBytes: limits.customValue, allowNewlines: true)
        case .url:
            guard s.utf8.count <= limits.customValue else { return .reject("over \(limits.customValue) bytes") }
            return URLPolicy.verdict(for: s)
        case .email:
            return email(s, maxBytes: limits.customValue)
        case .phone:
            return phone(s, maxBytes: limits.customValue)
        case .key:
            let verdict = TextCheck.check(s, maxBytes: limits.customValue)
            guard verdict.isAccepted else { return verdict }
            guard s.utf8.allSatisfy({ $0 < 0x80 }) else { return .reject("non-ASCII character") }
            return verdict
        }
    }

    public static func customCount(_ count: Int, limits: Limits) -> Verdict {
        count <= limits.customFields ? .ok : .reject("more than \(limits.customFields) custom fields")
    }

    public static func photo(byteCount: Int, limits: Limits) -> Verdict {
        blob(byteCount, cap: limits.photoBytes, what: "photo")
    }

    public static func gpgKey(byteCount: Int, limits: Limits) -> Verdict {
        blob(byteCount, cap: limits.gpgKeyBytes, what: "key")
    }

    public static func payload(byteCount: Int, limits: Limits) -> Verdict {
        byteCount <= limits.payloadBytes ? .ok : .reject("over \(limits.payloadBytes) bytes")
    }

    public static func nesting(depth: Int, limits: Limits) -> Verdict {
        depth <= limits.nesting ? .ok : .reject("nested deeper than \(limits.nesting)")
    }

    // MARK: - Shared

    /// For ASCII-only fields: non-empty, within the cap, nothing hidden, and
    /// nothing outside ASCII, naming the look-alike when there is one. Nil
    /// when the field passes.
    private static func asciiPrelude(_ s: String, maxBytes: Int) -> Verdict? {
        guard !s.isEmpty else { return .reject("empty") }
        guard s.utf8.count <= maxBytes else { return .reject("over \(maxBytes) bytes") }
        if let problem = TextCheck.problem(in: s) { return .reject(problem) }
        guard s.utf8.allSatisfy({ $0 < 0x80 }) else {
            if let skeleton = Confusables.looksLikeASCII(s) {
                return .reject("non-ASCII character, looks like “\(skeleton)”")
            }
            return .reject("non-ASCII character")
        }
        return nil
    }

    private static func email(_ s: String, maxBytes: Int) -> Verdict {
        if let failure = asciiPrelude(s, maxBytes: maxBytes) { return failure }
        return URLPolicy.address(Array(s.utf8)[...], or: "not an email address")
    }

    private static func phone(_ s: String, maxBytes: Int) -> Verdict {
        if let failure = asciiPrelude(s, maxBytes: maxBytes) { return failure }
        return URLPolicy.isE164(s.utf8) ? .ok : .reject("not an E.164 number")
    }

    private static func blob(_ count: Int, cap: Int, what: String) -> Verdict {
        guard cap > 0 else { return .reject("no \(what) in this form") }
        guard count > 0 else { return .reject("empty") }
        guard count <= cap else { return .reject("\(what) over \(cap) bytes") }
        return .ok
    }

    /// Letters, digits and `_`, separated by single `.`, `-` or `/`
    /// (Calendly paths), starting and ending on a word character.
    private static func isSlug(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard let first = bytes.first, let last = bytes.last, isWordByte(first), isWordByte(last) else { return false }
        var afterSeparator = false
        for b in bytes {
            if isWordByte(b) {
                afterSeparator = false
                continue
            }
            guard "._-/".utf8.contains(b), !afterSeparator else { return false }
            afterSeparator = true
        }
        return true
    }

    private static func hasSchemeSeparator(_ s: String) -> Bool {
        var seen = 0
        for b in s.utf8 {
            switch (seen, b) {
            case (_, UInt8(ascii: ":")): seen = 1
            case (1, UInt8(ascii: "/")): seen = 2
            case (2, UInt8(ascii: "/")): return true
            default: seen = 0
            }
        }
        return false
    }

    private static func isWordByte(_ b: UInt8) -> Bool {
        isAlphanumeric(b) || b == UInt8(ascii: "_")
    }

    private static func isAlphanumeric(_ b: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(b) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(b)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b)
    }

    private static func isBase64URLByte(_ b: UInt8) -> Bool {
        isAlphanumeric(b) || b == UInt8(ascii: "-") || b == UInt8(ascii: "_") || b == UInt8(ascii: "=")
    }
}
