/// Display and tappable URIs built from stored forms. Stored forms are the
/// minimal text a card carries: an E.164 number, `host/path` without scheme,
/// a bare username or slug, `user@instance`. Every function here is total on
/// valid stored forms; `Normalize` is what produces them.
///
/// Everything in this file reads text as Unicode scalars, never as
/// `Character`s: a grapheme cluster fuses a combining mark, a joiner, a
/// variation selector or the scalar after a Prepend letter (U+0D4E and kin)
/// with its neighbour, so `Character.isLetter`, `isWhitespace`, `split`,
/// `hasPrefix` and `count` can all be fooled by one well-placed scalar.
public enum CanonicalURI {
    public static func phone(_ e164: String) -> String {
        "tel:" + e164
    }

    /// RFC 6068: characters outside `unreserved` and `some-delims` are
    /// percent-encoded so a `?` or `#` in a local part cannot smuggle headers.
    public static func email(_ address: String) -> String {
        var out = "mailto:"
        for byte in address.utf8 {
            if mailtoSafe.contains(byte) {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out += "%" + Hex.pair(byte)
            }
        }
        return out
    }

    public static func website(_ address: String, insecure: Bool = false) -> String {
        (insecure ? "http://" : "https://") + address
    }

    public static func github(_ user: String) -> String {
        "https://github.com/" + user
    }

    /// Personal slugs live under `/in/`; a stored `company/<slug>` keeps its prefix.
    public static func linkedin(_ slug: String) -> String {
        slug.starts(withScalars: "company/") ? "https://www.linkedin.com/" + slug : "https://www.linkedin.com/in/" + slug
    }

    /// The WebFinger account URI and the profile page. Nil when the stored
    /// form has no `@`; a leading `@` is tolerated. Split at the last `@`
    /// scalar, so a mark right after it belongs to the instance.
    public static func mastodon(_ handle: String) -> (account: String, profile: String)? {
        let handle = Substring(handle).droppingPrefix("@")
        let scalars = handle.unicodeScalars
        guard let at = scalars.lastIndex(of: "@"), at != scalars.startIndex, scalars.index(after: at) != scalars.endIndex
        else { return nil }
        let user = scalars[..<at]
        let instance = scalars[scalars.index(after: at)...]
        return ("acct:" + handle, "https://\(String(instance))/@\(String(user))")
    }

    public static func calendly(_ path: String) -> String {
        "https://calendly.com/" + path
    }

    /// The `OPENPGP4FPR:` scheme used by OpenKeychain and GnuPG's QR export.
    public static func gpgFingerprint(_ bytes: [UInt8]) -> String {
        "OPENPGP4FPR:" + Hex.encode(bytes)
    }

    private static let mailtoSafe: Set<UInt8> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$'()*+,;:@".utf8)
}

// MARK: - Normalizers

/// Turns pasted input into a stored form or says precisely why it cannot.
///
/// Whitespace, controls, format characters and default ignorables ("hidden"
/// scalars) never reach a stored form: `website` and `email` refuse them by
/// name before parsing, and the field grammars of the other normalizers
/// (hostname labels, usernames, slugs, path segments) refuse them with the
/// field's own error, which is what their callers show.
public enum Normalize {
    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
        /// The grapheme holding the offending scalar, so a joiner or a mark
        /// is shown with the letter it clings to.
        case invalidCharacter(Character)
        case missingPlus
        case invalidCountryCode
        case tooShort
        case tooLong
        case missingAt
        case multipleAt
        case invalidLocalPart
        case invalidHost
        case unsupportedScheme(String)
        case userinfo
        case wrongHost(String)
        case invalidUsername
        case invalidPath
        case invalidHex
        case wrongLength(Int)
    }

    /// E.164 (ITU-T): `+`, then 8 to 15 digits, the first not zero. Spaces,
    /// dots, dashes and parentheses are formatting and are dropped.
    public static func phone(_ input: String) throws -> String {
        var text = Substring(input.trimmed())
        text = text.droppingPrefix("tel:", caseInsensitive: true)
        var digits = ""
        var sawPlus = false
        let scalars = text.unicodeScalars
        for index in scalars.indices {
            let scalar = scalars[index]
            if scalar.properties.isWhitespace || phoneFormatting.contains(scalar) { continue }
            if scalar == "+" && !sawPlus && digits.isEmpty {
                sawPlus = true
                continue
            }
            guard scalar.isASCIIDigit else { throw Error.invalidCharacter(text.grapheme(at: index)) }
            digits.unicodeScalars.append(scalar)
        }
        guard sawPlus || !digits.isEmpty else { throw Error.empty }
        guard sawPlus else { throw Error.missingPlus }
        guard digits.utf8.count >= 8 else { throw Error.tooShort }
        guard digits.utf8.count <= 15 else { throw Error.tooLong }
        guard digits.utf8.first != UInt8(ascii: "0") else { throw Error.invalidCountryCode }
        return "+" + digits
    }

    /// RFC 5322 `dot-atom` local part at an ASCII hostname, at most 254
    /// octets, domain lowercased. Quoted local parts and IP literals are
    /// not accepted; a `Name <addr>` wrapper and a `mailto:` prefix are.
    public static func email(_ input: String) throws -> String {
        var text = Substring(input.trimmed())
        let scalars = text.unicodeScalars
        if scalars.last == ">", let open = scalars.lastIndex(of: "<") {
            text = text[scalars.index(after: open)..<scalars.index(before: scalars.endIndex)].trimmed()
        }
        let hadScheme = text.starts(withScalars: "mailto:", caseInsensitive: true)
        text = text.droppingPrefix("mailto:", caseInsensitive: true)
        if hadScheme {
            if let query = text.unicodeScalars.firstIndex(of: "?") { text = text[..<query] }
            guard let decoded = PercentEncoding.decode(text) else { throw Error.invalidCharacter("%") }
            text = Substring(decoded)
        }
        guard !text.isEmpty else { throw Error.empty }
        // Printable ASCII only, which refuses every hidden scalar as well.
        if let bad = text.unicodeScalars.firstIndex(where: { !$0.isASCII || $0.isHidden }) {
            throw Error.invalidCharacter(text.grapheme(at: bad))
        }
        guard text.utf8.count <= 254 else { throw Error.tooLong }
        let parts = text.unicodeScalars.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw Error.missingAt }
        guard parts.count == 2 else { throw Error.multipleAt }
        let local = parts[0]
        guard !local.isEmpty, local.count <= 64, local.first != ".", local.last != ".", !local.containsAdjacent(".", "."),
              local.allSatisfy({ $0.isASCIIAlphanumeric || atextSymbols.contains($0) })
        else { throw Error.invalidLocalPart }
        guard let host = Hostname.normalized(Substring(parts[1])), host.utf8.allSatisfy({ $0 < 0x80 }) else { throw Error.invalidHost }
        return String(local) + "@" + host
    }

    /// Bare host, `host/path`, or an http(s) URL. The scheme goes into the
    /// flag, the host is lowercased and may be an IDN, the port is 1 to 65535
    /// without leading zeros. The path, query and fragment are kept as typed
    /// but must be ASCII with the RFC 3986 delimiters that need
    /// percent-encoding (space, `<>"\^{|}` and the backtick) already encoded,
    /// and every `%` starting a `%XX` triple. Whitespace, controls, format
    /// characters (U+200B, U+202E, U+FEFF and kin) and default ignorables
    /// (variation selectors, U+034F) are refused anywhere, by name.
    public static func website(_ input: String) throws -> (address: String, insecure: Bool) {
        let text = Substring(input.trimmed())
        guard !text.isEmpty else { throw Error.empty }
        if let hidden = hiddenCharacter(in: text) { throw Error.invalidCharacter(hidden) }
        let pasted = Pasted(text)
        var insecure = false
        switch pasted.scheme {
        case nil, "https"?: break
        case "http"?: insecure = true
        case let scheme?: throw Error.unsupportedScheme(scheme)
        }
        let authority = pasted.authority.unicodeScalars
        guard !authority.contains("@") else { throw Error.userinfo }
        var hostPart = pasted.authority
        var port = ""
        if let colon = authority.lastIndex(of: ":") {
            let digits = authority[authority.index(after: colon)...]
            guard (1...5).contains(digits.count), digits.first != "0", digits.allSatisfy(\.isASCIIDigit),
                  let number = Int(String(digits)), number <= 65535
            else { throw Error.invalidHost }
            port = ":" + String(digits)
            hostPart = pasted.authority[..<colon]
        }
        guard let host = Hostname.normalized(hostPart) else { throw Error.invalidHost }
        if let bad = pasted.rest.unicodeScalars.firstIndex(where: { !$0.isASCII || pathUnsafe.contains($0) }) {
            throw Error.invalidCharacter(pasted.rest.grapheme(at: bad))
        }
        guard PercentEncoding.isWellFormed(pasted.rest) else { throw Error.invalidCharacter("%") }
        let rest = pasted.rest.unicodeScalars.elementsEqual("/".unicodeScalars) ? "" : String(pasted.rest)
        return (host + port + rest, insecure)
    }

    /// `@user`, `user`, or a github.com profile URL. Usernames are 1 to 39
    /// ASCII letters, digits and single hyphens, not starting or ending with
    /// one. A reserved site path (`orgs`, `settings`, `login`, ...) is not a
    /// profile, whether it is a URL's first segment or typed alone.
    public static func github(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        var user = text
        if text.unicodeScalars.contains("/") || text.asciiLowercased().contains(scalars: "github.com") {
            let pasted = try Pasted(text, hosts: ["github.com", "www.github.com"])
            guard let first = pasted.pathSegments.first else { throw Error.invalidPath }
            guard !isReservedGithubPath(first) else { throw Error.invalidPath }
            user = first
        }
        let scalars = user.unicodeScalars
        guard scalars.count <= 39 else { throw Error.tooLong }
        guard !scalars.isEmpty, scalars.first != "-", scalars.last != "-", !scalars.containsAdjacent("-", "-"),
              scalars.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" }), !isReservedGithubPath(user)
        else { throw Error.invalidUsername }
        return String(user)
    }

    /// A slug, `in/<slug>`, `company/<slug>`, or any linkedin.com URL
    /// including locale subdomains and the mobile `mwlite/in/<slug>` path.
    /// Stored as the slug, or `company/<slug>`. A slug is at most 100 scalars
    /// and at least three letters, digits or hyphens: ASCII letters, digits
    /// and hyphens, or the letters, digits and marks a hostname label may
    /// carry, not starting with a mark or a hyphen and not ending with one.
    /// It is checked after percent-decoding, so an escaped `/`, `?`, `#`,
    /// `.` or space is refused wherever it lands.
    public static func linkedin(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        var kind = "in"
        var slug = text
        let lower = text.asciiLowercased()
        var segments: [Substring]?
        if lower.starts(withScalars: "in/") || lower.starts(withScalars: "company/") || lower.starts(withScalars: "mwlite/") {
            segments = Pasted.segments(of: text)
        } else if text.unicodeScalars.contains("/") || lower.contains(scalars: "linkedin.com") {
            segments = try Pasted(text, hosts: ["linkedin.com"], subdomains: true).pathSegments
        }
        if var segments {
            if segments.first?.equals(asciiCaseInsensitive: "mwlite") == true { segments.removeFirst() }
            guard segments.count >= 2 else { throw Error.invalidPath }
            if segments[0].equals(asciiCaseInsensitive: "in") {
                kind = "in"
            } else if segments[0].equals(asciiCaseInsensitive: "company") {
                kind = "company"
            } else {
                throw Error.invalidPath
            }
            slug = segments[1]
        }
        guard let decoded = PercentEncoding.decode(slug) else { throw Error.invalidPath }
        let scalars = decoded.unicodeScalars
        guard scalars.count <= 100 else { throw Error.tooLong }
        guard scalars.filter({ !$0.isMark }).count >= 3, scalars.first != "-", scalars.last != "-", scalars.first?.isMark == false,
              scalars.allSatisfy({ $0 == "-" || $0.isIDNALetterDigitOrMark })
        else { throw Error.invalidUsername }
        return kind == "company" ? "company/" + decoded : decoded
    }

    /// `@user@instance`, `user@instance`, `https://instance/@user` or
    /// `https://instance/users/user`, with or without a trailing slash.
    /// Stored as `user@instance`: 1 to 30 ASCII letters, digits and
    /// underscores at a hostname.
    public static func mastodon(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        let user: Substring
        let instance: Substring
        if text.unicodeScalars.contains("/") {
            let pasted = try Pasted(text, hosts: nil)
            let segments = pasted.pathSegments
            if segments.count == 1, segments[0].starts(withScalars: "@") {
                user = segments[0].droppingPrefix("@")
            } else if segments.count == 2, segments[0].unicodeScalars.elementsEqual("users".unicodeScalars) {
                user = segments[1]
            } else {
                throw Error.invalidPath
            }
            instance = pasted.authority
        } else {
            let parts = text.unicodeScalars.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { throw Error.missingAt }
            guard parts.count == 2 else { throw Error.multipleAt }
            user = Substring(parts[0])
            instance = Substring(parts[1])
        }
        let name = user.unicodeScalars
        guard !name.isEmpty, name.count <= 30, name.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "_" })
        else { throw Error.invalidUsername }
        guard let host = Hostname.normalized(instance) else { throw Error.invalidHost }
        return String(user) + "@" + host
    }

    /// A path or a calendly.com URL: `user`, `user/event`, or the shared
    /// `d/<code>/<slug>` form, each segment up to 64 ASCII letters, digits,
    /// hyphens and underscores. Query and fragment are UI state and dropped.
    public static func calendly(_ input: String) throws -> String {
        let text = Substring(input.trimmed())
        guard !text.isEmpty else { throw Error.empty }
        let lower = text.asciiLowercased()
        let segments: [Substring]
        if text.contains(scalars: "://") || lower.starts(withScalars: "calendly.com") || lower.starts(withScalars: "www.calendly.com") {
            segments = try Pasted(text, hosts: ["calendly.com", "www.calendly.com"]).pathSegments
        } else {
            segments = Pasted.segments(of: text)
        }
        guard !segments.isEmpty else { throw Error.empty }
        guard segments.count <= 3 else { throw Error.invalidPath }
        for segment in segments {
            let scalars = segment.unicodeScalars
            guard scalars.count <= 64, scalars.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" || $0 == "_" })
            else { throw Error.invalidPath }
        }
        return segments.joined(separator: "/")
    }

    /// 40 ASCII hex digits (v4) or 64 (v5/v6), with any spaces or colons, and
    /// an optional `0x` or `OPENPGP4FPR:` prefix.
    public static func gpgFingerprint(_ input: String) throws -> GPGFingerprint {
        var text = Substring(input.trimmed())
        text = text.droppingPrefix("OPENPGP4FPR:", caseInsensitive: true).trimmed()
        text = text.droppingPrefix("0x", caseInsensitive: true)
        var nibbles: [UInt8] = []
        let scalars = text.unicodeScalars
        for index in scalars.indices {
            let scalar = scalars[index]
            if scalar.properties.isWhitespace || scalar == ":" { continue }
            // Only ASCII hex counts; fullwidth digits have a value but are not hex.
            guard scalar.isASCII, let value = PercentEncoding.hexValue(UInt8(scalar.value)) else {
                throw Error.invalidCharacter(text.grapheme(at: index))
            }
            nibbles.append(value)
        }
        guard !nibbles.isEmpty else { throw Error.empty }
        guard nibbles.count % 2 == 0 else { throw Error.invalidHex }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(nibbles.count / 2)
        for i in stride(from: 0, to: nibbles.count, by: 2) {
            bytes.append(nibbles[i] << 4 | nibbles[i + 1])
        }
        return try GPGFingerprint(bytes: bytes)
    }

    /// The first hidden scalar in `text`, as the grapheme that holds it.
    static func hiddenCharacter(in text: Substring) -> Character? {
        text.unicodeScalars.firstIndex(where: \.isHidden).map { text.grapheme(at: $0) }
    }

    /// Reserved words are ASCII; a segment with any other scalar is not one.
    private static func isReservedGithubPath(_ segment: Substring) -> Bool {
        let lower = segment.asciiLowercased()
        return lower.utf8.allSatisfy({ $0 < 0x80 }) && githubReserved.contains(lower)
    }

    private static let phoneFormatting: Set<Unicode.Scalar> = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}", ".", "(", ")"]
    private static let atextSymbols: Set<Unicode.Scalar> = ["!", "#", "$", "%", "&", "'", "*", "+", "-", "/", "=", "?", "^", "_", "`", "{", "|", "}", "~", "."]
    /// Neither `pchar` nor a query/fragment character in RFC 3986 §3.3-3.5;
    /// whitespace is refused earlier.
    private static let pathUnsafe: Set<Unicode.Scalar> = ["<", ">", "\"", "\\", "^", "`", "{", "|", "}"]
    /// First path segments github.com uses for itself, not for profiles.
    private static let githubReserved: Set<String> = [
        "orgs", "settings", "login", "join", "marketplace", "explore", "topics", "features", "about", "pricing",
        "apps", "sponsors", "notifications", "new", "site", "security", "enterprise", "team", "collections",
        "events", "trending", "search", "issues", "pulls", "codespaces", "dashboard", "account", "sessions",
    ]
}

// MARK: - Signal

/// A `signal.me` contact link. Username links carry 48 opaque bytes; phone
/// links carry the number itself, which is why the editor warns about them.
public struct SignalLink: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case username([UInt8])
        case phone(String)
    }

    public static let usernameLength = 48
    public let kind: Kind

    public init(username: [UInt8]) throws {
        guard username.count == Self.usernameLength else { throw Normalize.Error.wrongLength(username.count) }
        kind = .username(username)
    }

    public init(phone e164: String) throws {
        kind = .phone(try Normalize.phone(e164))
    }

    /// Accepts `https://signal.me/#eu/…`, `https://signal.me/#p/+…`, the
    /// `sgnl:` scheme, or the same without a scheme. Whitespace and controls
    /// are refused by name; a format character cannot survive the base64 or
    /// the digits and is refused as a bad path or number.
    public static func parse(_ input: String) throws -> SignalLink {
        let text = Substring(input.trimmed())
        guard !text.isEmpty else { throw Normalize.Error.empty }
        if let bad = text.unicodeScalars.firstIndex(where: { $0.properties.isWhitespace || $0.isControl }) {
            throw Normalize.Error.invalidCharacter(text.grapheme(at: bad))
        }
        let pasted = Pasted(text)
        switch pasted.scheme {
        case nil, "https"?, "http"?, "sgnl"?: break
        case let scheme?: throw Normalize.Error.unsupportedScheme(scheme)
        }
        guard pasted.authority.equals(asciiCaseInsensitive: "signal.me") else { throw Normalize.Error.wrongHost(String(pasted.authority)) }
        var rest = pasted.rest.droppingPrefix("/")
        guard rest.starts(withScalars: "#") else { throw Normalize.Error.invalidPath }
        rest = rest.droppingPrefix("#")
        if rest.starts(withScalars: "eu/") {
            let encoded = rest.droppingPrefix("eu/")
            guard let bytes = try? Base64.decode(encoded, url: true) else { throw Normalize.Error.invalidPath }
            return try SignalLink(username: bytes)
        }
        if rest.starts(withScalars: "p/") {
            return try SignalLink(phone: String(rest.droppingPrefix("p/")))
        }
        throw Normalize.Error.invalidPath
    }

    /// The canonical URL, which is also the stored form.
    public var url: String {
        switch kind {
        case .username(let bytes): return "https://signal.me/#eu/" + Base64.encode(bytes, url: true)
        case .phone(let number): return "https://signal.me/#p/" + number
        }
    }

    public var disclosesPhoneNumber: Bool {
        if case .phone = kind { return true }
        return false
    }
}

// MARK: - GPG

/// An OpenPGP fingerprint: 20 bytes for v4 keys, 32 for v5 and v6.
public struct GPGFingerprint: Sendable, Hashable {
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == 20 || bytes.count == 32 else { throw Normalize.Error.wrongLength(bytes.count) }
        self.bytes = bytes
    }

    public var isV4: Bool { bytes.count == 20 }

    /// Uppercase, no separators: the form `gpg --fingerprint` compares against.
    public var hex: String { Hex.encode(bytes) }

    /// GnuPG's display form: groups of four with a double space between the
    /// halves, ten groups for v4 and sixteen for the longer fingerprints.
    public var formatted: String {
        let text = hex
        var groups: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 4)
            groups.append(String(text[index..<next]))
            index = next
        }
        let half = groups.count / 2
        return groups[..<half].joined(separator: " ") + "  " + groups[half...].joined(separator: " ")
    }

    public var uri: String { CanonicalURI.gpgFingerprint(bytes) }
}

// MARK: - Helpers

enum Hex {
    static func encode(_ bytes: [UInt8]) -> String {
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes { out += pair(byte) }
        return out
    }

    static func pair(_ byte: UInt8) -> String {
        let digits = Array("0123456789ABCDEF".utf8)
        return String(decoding: [digits[Int(byte >> 4)], digits[Int(byte & 0xf)]], as: UTF8.self)
    }
}

/// A hostname on IDNA 2008's lines (RFC 5891 §4.2, RFC 5892): labels split
/// on U+002E only, each 1 to 63 octets of UTF-8 and the whole at most 253;
/// a label holds letters, digits, marks and ASCII hyphens, with no hyphen at
/// either end and no mark first. At least two labels, the last not all
/// digits. Whitespace, controls, format characters, default ignorables,
/// punctuation, symbols and the dot look-alikes are refused, never folded.
/// ASCII letters are lowercased, as is any scalar whose lowercase is a
/// single scalar; IDNA's mapping step and the look-alike verdict stay with
/// `Validate`.
enum Hostname {
    static let maxOctets = 253
    static let maxLabelOctets = 63
    /// Dots IDNA's mapping folds to U+002E; refused here rather than folded.
    static let dotLookalikes: Set<Unicode.Scalar> = ["\u{2024}", "\u{3002}", "\u{FF0E}", "\u{FF61}"]

    static func normalized(_ input: Substring) -> String? {
        var scalars = input.unicodeScalars
        if scalars.last == "." { scalars = scalars.dropLast() }
        let labels = scalars.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let last = labels.last, !last.allSatisfy(\.isDigit) else { return nil }
        var out = ""
        for (i, label) in labels.enumerated() {
            guard let normalizedLabel = normalizedLabel(label) else { return nil }
            if i > 0 { out += "." }
            out += normalizedLabel
        }
        guard out.utf8.count <= maxOctets else { return nil }
        return out
    }

    private static func normalizedLabel(_ label: Substring.UnicodeScalarView) -> String? {
        guard let first = label.first, first != "-", label.last != "-", !first.isMark else { return nil }
        var out = ""
        for scalar in label {
            guard scalar == "-" || scalar.isIDNALetterDigitOrMark else { return nil }
            out.unicodeScalars.append(lowercased(scalar))
        }
        guard out.utf8.count <= maxLabelOctets else { return nil }
        return out
    }

    /// ASCII case folded; another script's letter only when its lowercase
    /// is one scalar (U+212A becomes `k`, U+0130 stays as it is).
    private static func lowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.isASCII { return scalar.asciiLowercased }
        let mapping = scalar.properties.lowercaseMapping.unicodeScalars
        return mapping.count == 1 ? mapping.first! : scalar
    }
}

/// A pasted address split into scheme, authority and the rest, without
/// Foundation's URL parser, which is lenient where we want to be strict.
/// Delimiters are matched as scalars, so a combining mark after `/`, `:`
/// or `@` cannot hide the delimiter and move it into the authority.
struct Pasted {
    var scheme: String?
    var authority: Substring
    /// Path, query and fragment, starting with `/`, `?` or `#`; or empty.
    var rest: Substring

    init(_ text: Substring) {
        var remainder = text
        let scalars = text.unicodeScalars
        if text.starts(withScalars: "//") {
            // Scheme-relative: nothing before `//` can be a scheme, so a later
            // colon is a port or part of the path.
            remainder = text.droppingPrefix("//")
        } else if let colon = scalars.firstIndex(of: ":") {
            let head = text[..<colon]
            let tail = text[scalars.index(after: colon)...]
            let name = head.unicodeScalars
            let looksLikeScheme = name.first?.isASCIILetter == true
                && name.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "+" || $0 == "-" || $0 == "." })
            // `localhost:8080/x` is a host and port, not a scheme. So is
            // `mailto:1234/x`, which therefore fails as `invalidHost` rather
            // than `unsupportedScheme`.
            let port = tail.unicodeScalars.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            let looksLikePort = !port.isEmpty && port.allSatisfy(\.isASCIIDigit)
            if looksLikeScheme, tail.starts(withScalars: "//") {
                scheme = head.asciiLowercased()
                remainder = tail.droppingPrefix("//")
            } else if looksLikeScheme, !name.contains("."), !tail.isEmpty, !looksLikePort {
                scheme = head.asciiLowercased()
                remainder = tail
            }
        }
        let end = remainder.unicodeScalars.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? remainder.endIndex
        authority = remainder[..<end]
        rest = remainder[end...]
    }

    /// An http(s) URL on one of the given hosts (or any host when nil),
    /// with userinfo and other schemes refused. Hosts are compared scalar
    /// by scalar after ASCII case folding: `linkedin.com` spelt with a
    /// Kelvin sign or a mark is another host.
    init(_ text: Substring, hosts: [String]?, subdomains: Bool = false) throws {
        self.init(text)
        switch scheme {
        case nil, "https"?, "http"?: break
        case let scheme?: throw Normalize.Error.unsupportedScheme(scheme)
        }
        guard !authority.unicodeScalars.contains("@") else { throw Normalize.Error.userinfo }
        if let hosts {
            let host = authority.asciiLowercased()
            guard hosts.contains(where: { host.unicodeScalars.elementsEqual($0.unicodeScalars) || subdomains && host.ends(withScalars: "." + $0) })
            else { throw Normalize.Error.wrongHost(String(authority)) }
        } else {
            guard Hostname.normalized(authority) != nil else { throw Normalize.Error.invalidHost }
        }
    }

    /// Path segments before any query or fragment, empty ones dropped.
    var pathSegments: [Substring] {
        Self.segments(of: rest)
    }

    static func segments(of path: Substring) -> [Substring] {
        let end = path.unicodeScalars.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? path.endIndex
        return path[..<end].unicodeScalars.split(separator: "/", omittingEmptySubsequences: true).map { Substring($0) }
    }
}

enum PercentEncoding {
    /// Decodes `%XX` triples; nil when a triple is malformed or the result is
    /// not UTF-8. Text without `%` comes back unchanged.
    static func decode(_ text: Substring) -> String? {
        guard text.utf8.contains(UInt8(ascii: "%")) else { return String(text) }
        var bytes: [UInt8] = []
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            if byte == UInt8(ascii: "%") {
                guard let high = iterator.next(), let low = iterator.next(),
                      let h = hexValue(high), let l = hexValue(low)
                else { return nil }
                bytes.append(h << 4 | l)
            } else {
                bytes.append(byte)
            }
        }
        return String(validating: bytes, as: UTF8.self)
    }

    /// RFC 3986 §2.1: every `%` starts a `%` HEXDIG HEXDIG triple.
    static func isWellFormed(_ text: Substring) -> Bool {
        let bytes = Array(text.utf8)
        for (i, byte) in bytes.enumerated() where byte == UInt8(ascii: "%") {
            guard i + 2 < bytes.count, hexValue(bytes[i + 1]) != nil, hexValue(bytes[i + 2]) != nil else { return false }
        }
        return true
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        default: return nil
        }
    }
}

extension Unicode.Scalar {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
    var isASCIILetter: Bool { ("a"..."z").contains(self) || ("A"..."Z").contains(self) }
    var isASCIIAlphanumeric: Bool { isASCIILetter || isASCIIDigit }
    var isControl: Bool { properties.generalCategory == .control }
    /// `A`-`Z` folded; everything else untouched.
    var asciiLowercased: Unicode.Scalar {
        ("A"..."Z").contains(self) ? Unicode.Scalar(UInt8(value + 0x20)) : self
    }
    /// `a`-`z` folded; everything else untouched.
    var asciiUppercased: Unicode.Scalar {
        ("a"..."z").contains(self) ? Unicode.Scalar(UInt8(value - 0x20)) : self
    }
    /// Whitespace, a control, a format character or a default ignorable:
    /// nothing an address may carry, and often nothing a display shows.
    var isHidden: Bool {
        let category = properties.generalCategory
        return properties.isWhitespace || category == .control || category == .format || properties.isDefaultIgnorableCodePoint
    }
    /// Mn or Mc: extends the scalar before it, so it can never come first.
    var isMark: Bool {
        let category = properties.generalCategory
        return category == .nonspacingMark || category == .spacingMark
    }
    /// An ASCII digit or any Nd.
    var isDigit: Bool { isASCIIDigit || properties.generalCategory == .decimalNumber }
    /// What RFC 5892 lets into a label besides the hyphen: ASCII letters and
    /// digits, and beyond ASCII the categories Lu Ll Lt Lm Lo, Nd, Mn and
    /// Mc, minus every default ignorable and the dot look-alikes.
    var isIDNALetterDigitOrMark: Bool {
        if isASCII { return isASCIIAlphanumeric }
        guard !properties.isDefaultIgnorableCodePoint, !Hostname.dotLookalikes.contains(self) else { return false }
        switch properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .nonspacingMark, .spacingMark:
            return true
        default:
            return false
        }
    }
}

/// For callers that hold a `Character` (the tests do); the interop code
/// itself reads scalars. Each answers for every scalar in the cluster.
extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
    var isControl: Bool { unicodeScalars.contains(where: \.isControl) }
    /// Carries a Cf scalar: zero-width spaces, bidi overrides, a BOM, or a
    /// joiner fused to the preceding letter.
    var isFormat: Bool { unicodeScalars.contains { $0.properties.generalCategory == .format } }
}

extension Sequence where Element == Unicode.Scalar {
    /// True when `first` is immediately followed by `second` somewhere.
    func containsAdjacent(_ first: Unicode.Scalar, _ second: Unicode.Scalar) -> Bool {
        var previous: Unicode.Scalar?
        for scalar in self {
            if previous == first && scalar == second { return true }
            previous = scalar
        }
        return false
    }
}

extension StringProtocol {
    /// Strips whitespace and controls from both ends, scalar by scalar: a
    /// combining mark after a leading space is content, not whitespace.
    func trimmed() -> Substring {
        let blank = { (s: Unicode.Scalar) in s.properties.isWhitespace || s.isControl }
        var s = Substring(self).unicodeScalars.drop(while: blank)
        while let l = s.last, blank(l) { s = s.dropLast() }
        return Substring(s)
    }

    /// `hasPrefix` on scalars: a combining mark right after the prefix
    /// neither hides it nor gets dropped with it. Case folding is ASCII
    /// only, so a non-ASCII scalar never matches an ASCII prefix.
    func starts(withScalars prefix: String, caseInsensitive: Bool = false) -> Bool {
        let head = unicodeScalars.prefix(prefix.unicodeScalars.count)
        guard head.count == prefix.unicodeScalars.count else { return false }
        return zip(head, prefix.unicodeScalars).allSatisfy {
            caseInsensitive ? $0.asciiLowercased == $1.asciiLowercased : $0 == $1
        }
    }

    /// `hasSuffix` on scalars.
    func ends(withScalars suffix: String) -> Bool {
        unicodeScalars.reversed().starts(with: suffix.unicodeScalars.reversed())
    }

    /// `contains` on scalars: the needle must appear as the same scalars in
    /// the same order, whatever graphemes they fall into.
    func contains(scalars needle: String) -> Bool {
        let haystack = unicodeScalars
        let pattern = needle.unicodeScalars
        guard !pattern.isEmpty else { return true }
        var index = haystack.startIndex
        while index < haystack.endIndex {
            if haystack[index...].starts(with: pattern) { return true }
            index = haystack.index(after: index)
        }
        return false
    }

    /// Scalar equality after ASCII case folding; `other` is lowercase ASCII.
    func equals(asciiCaseInsensitive other: String) -> Bool {
        unicodeScalars.count == other.unicodeScalars.count
            && zip(unicodeScalars, other.unicodeScalars).allSatisfy { $0.asciiLowercased == $1 }
    }

    /// `A`-`Z` lowercased and every other scalar untouched: the folding a
    /// scheme, a host comparison or a keyword needs, without the full
    /// mapping that turns U+0130 into two scalars or U+212A into `k`.
    func asciiLowercased() -> String {
        var out = ""
        out.unicodeScalars.append(contentsOf: unicodeScalars.lazy.map(\.asciiLowercased))
        return out
    }

    /// `a`-`z` uppercased and every other scalar untouched.
    func asciiUppercased() -> String {
        var out = ""
        out.unicodeScalars.append(contentsOf: unicodeScalars.lazy.map(\.asciiUppercased))
        return out
    }
}

extension Substring {
    /// Drops an ASCII prefix, matched scalar by scalar.
    func droppingPrefix(_ prefix: String, caseInsensitive: Bool = false) -> Substring {
        guard starts(withScalars: prefix, caseInsensitive: caseInsensitive) else { return self }
        return self[unicodeScalars.index(startIndex, offsetBy: prefix.unicodeScalars.count)...]
    }

    /// The grapheme cluster holding the scalar at `index`, which must lie
    /// inside the substring: what an error shows for a scalar that is only
    /// visible through the letter it clings to.
    func grapheme(at index: String.Index) -> Character {
        var start = startIndex
        while self.index(after: start) <= index { start = self.index(after: start) }
        return self[start]
    }
}
