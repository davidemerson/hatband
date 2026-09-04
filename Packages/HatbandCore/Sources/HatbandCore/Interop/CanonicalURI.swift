/// Display and tappable URIs built from stored forms. Stored forms are the
/// minimal text a card carries: an E.164 number, `host/path` without scheme,
/// a bare username or slug, `user@instance`. Every function here is total on
/// valid stored forms; `Normalize` is what produces them.
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
        slug.hasPrefix("company/") ? "https://www.linkedin.com/" + slug : "https://www.linkedin.com/in/" + slug
    }

    /// The WebFinger account URI and the profile page. Nil when the stored
    /// form has no `@`; a leading `@` is tolerated.
    public static func mastodon(_ handle: String) -> (account: String, profile: String)? {
        let handle = Substring(handle).droppingPrefix("@")
        guard let at = handle.lastIndex(of: "@"), at != handle.startIndex, handle.index(after: at) != handle.endIndex
        else { return nil }
        let user = handle[..<at]
        let instance = handle[handle.index(after: at)...]
        return ("acct:" + handle, "https://\(instance)/@\(user)")
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
public enum Normalize {
    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
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
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || phoneFormatting.contains(scalar) { continue }
            if scalar == "+" && !sawPlus && digits.isEmpty {
                sawPlus = true
                continue
            }
            guard scalar.isASCIIDigit else { throw Error.invalidCharacter(Character(scalar)) }
            digits.unicodeScalars.append(scalar)
        }
        guard sawPlus || !digits.isEmpty else { throw Error.empty }
        guard sawPlus else { throw Error.missingPlus }
        guard digits.count >= 8 else { throw Error.tooShort }
        guard digits.count <= 15 else { throw Error.tooLong }
        guard digits.first != "0" else { throw Error.invalidCountryCode }
        return "+" + digits
    }

    /// RFC 5322 `dot-atom` local part at an ASCII hostname, at most 254
    /// characters, domain lowercased. Quoted local parts and IP literals are
    /// not accepted; a `Name <addr>` wrapper and a `mailto:` prefix are.
    public static func email(_ input: String) throws -> String {
        var text = Substring(input.trimmed())
        let scalars = text.unicodeScalars
        if scalars.last == ">", let open = scalars.lastIndex(of: "<") {
            text = text[scalars.index(after: open)..<scalars.index(before: scalars.endIndex)].trimmed()
        }
        let hadScheme = text.lowercased().starts(withScalars: "mailto:")
        text = text.droppingPrefix("mailto:", caseInsensitive: true)
        if hadScheme {
            if let query = text.unicodeScalars.firstIndex(of: "?") { text = text[..<query] }
            guard let decoded = PercentEncoding.decode(text) else { throw Error.invalidCharacter("%") }
            text = Substring(decoded)
        }
        guard !text.isEmpty else { throw Error.empty }
        for ch in text where !ch.isASCII || ch.isControl || ch == " " { throw Error.invalidCharacter(ch) }
        guard text.count <= 254 else { throw Error.tooLong }
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw Error.missingAt }
        guard parts.count == 2 else { throw Error.multipleAt }
        let local = parts[0]
        guard !local.isEmpty, local.count <= 64, local.first != ".", local.last != ".",
              !local.contains(".."), local.allSatisfy({ $0.isASCIIAlphanumeric || atextSymbols.contains($0) })
        else { throw Error.invalidLocalPart }
        guard let host = Hostname.normalized(parts[1]), host.allSatisfy(\.isASCII) else { throw Error.invalidHost }
        return local + "@" + host
    }

    /// Bare host, `host/path`, or an http(s) URL. The scheme goes into the
    /// flag, the host is lowercased and may be an IDN, the port is 1 to 65535
    /// without leading zeros. The path, query and fragment are kept as typed
    /// but must be ASCII with the RFC 3986 delimiters that need
    /// percent-encoding (space, `<>"\^{|}` and the backtick) already encoded,
    /// and every `%` starting a `%XX` triple. Unicode format characters
    /// (U+200B, U+202E, U+FEFF and kin) are refused anywhere.
    public static func website(_ input: String) throws -> (address: String, insecure: Bool) {
        let text = Substring(input.trimmed())
        guard !text.isEmpty else { throw Error.empty }
        for ch in text where ch.isWhitespace || ch.isControl || ch.isFormat { throw Error.invalidCharacter(ch) }
        let pasted = Pasted(text)
        var insecure = false
        switch pasted.scheme {
        case nil, "https"?: break
        case "http"?: insecure = true
        case let scheme?: throw Error.unsupportedScheme(scheme)
        }
        guard !pasted.authority.unicodeScalars.contains("@") else { throw Error.userinfo }
        var hostPart = pasted.authority
        var port = ""
        if let colon = hostPart.unicodeScalars.lastIndex(of: ":") {
            let digits = hostPart[hostPart.unicodeScalars.index(after: colon)...]
            guard (1...5).contains(digits.count), digits.first != "0", digits.allSatisfy(\.isASCIIDigit),
                  let number = Int(digits), number <= 65535
            else { throw Error.invalidHost }
            port = ":" + digits
            hostPart = hostPart[..<colon]
        }
        guard let host = Hostname.normalized(hostPart) else { throw Error.invalidHost }
        for ch in pasted.rest where !ch.isASCII || pathUnsafe.contains(ch) { throw Error.invalidCharacter(ch) }
        guard PercentEncoding.isWellFormed(pasted.rest) else { throw Error.invalidCharacter("%") }
        let rest = pasted.rest == "/" ? "" : pasted.rest
        return (host + port + rest, insecure)
    }

    /// `@user`, `user`, or a github.com profile URL. Usernames are 1 to 39
    /// letters, digits and single hyphens, not starting or ending with one.
    /// A reserved site path (`orgs`, `settings`, `login`, ...) is not a
    /// profile, whether it is a URL's first segment or typed alone.
    public static func github(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        var user = text
        if text.unicodeScalars.contains("/") || text.lowercased().contains("github.com") {
            let pasted = try Pasted(text, hosts: ["github.com", "www.github.com"])
            guard let first = pasted.pathSegments.first else { throw Error.invalidPath }
            guard !githubReserved.contains(first.lowercased()) else { throw Error.invalidPath }
            user = first
        }
        guard user.count <= 39 else { throw Error.tooLong }
        guard !user.isEmpty, user.first != "-", user.last != "-", !user.contains("--"),
              user.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" }), !githubReserved.contains(user.lowercased())
        else { throw Error.invalidUsername }
        return String(user)
    }

    /// A slug, `in/<slug>`, `company/<slug>`, or any linkedin.com URL
    /// including locale subdomains and the mobile `mwlite/in/<slug>` path.
    /// Stored as the slug, or `company/<slug>`.
    public static func linkedin(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        var kind = "in"
        var slug = text
        let lower = text.lowercased()
        var segments: [Substring]?
        if lower.starts(withScalars: "in/") || lower.starts(withScalars: "company/") || lower.starts(withScalars: "mwlite/") {
            segments = Pasted.segments(of: text)
        } else if text.unicodeScalars.contains("/") || lower.contains("linkedin.com") {
            segments = try Pasted(text, hosts: ["linkedin.com"], subdomains: true).pathSegments
        }
        if var segments {
            if segments.first?.lowercased() == "mwlite" { segments.removeFirst() }
            guard segments.count >= 2 else { throw Error.invalidPath }
            kind = segments[0].lowercased()
            guard kind == "in" || kind == "company" else { throw Error.invalidPath }
            slug = segments[1]
        }
        guard let decoded = PercentEncoding.decode(slug) else { throw Error.invalidPath }
        guard decoded.count <= 100 else { throw Error.tooLong }
        guard decoded.count >= 3, decoded.first != "-", decoded.last != "-",
              decoded.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { throw Error.invalidUsername }
        return kind == "company" ? "company/" + decoded : decoded
    }

    /// `@user@instance`, `user@instance`, `https://instance/@user` or
    /// `https://instance/users/user`, with or without a trailing slash.
    /// Stored as `user@instance`.
    public static func mastodon(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        let user: Substring
        let instance: Substring
        if text.unicodeScalars.contains("/") {
            let pasted = try Pasted(text, hosts: nil)
            let segments = pasted.pathSegments
            if segments.count == 1, segments[0].unicodeScalars.first == "@" {
                user = segments[0].droppingPrefix("@")
            } else if segments.count == 2, segments[0] == "users" {
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
        guard !user.isEmpty, user.count <= 30, user.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "_" })
        else { throw Error.invalidUsername }
        guard let host = Hostname.normalized(instance) else { throw Error.invalidHost }
        return user + "@" + host
    }

    /// A path or a calendly.com URL: `user`, `user/event`, or the shared
    /// `d/<code>/<slug>` form. Query and fragment are UI state and dropped.
    public static func calendly(_ input: String) throws -> String {
        let text = Substring(input.trimmed())
        guard !text.isEmpty else { throw Error.empty }
        let segments: [Substring]
        if text.contains("://") || text.lowercased().hasPrefix("calendly.com") || text.lowercased().hasPrefix("www.calendly.com") {
            segments = try Pasted(text, hosts: ["calendly.com", "www.calendly.com"]).pathSegments
        } else {
            segments = Pasted.segments(of: text)
        }
        guard !segments.isEmpty else { throw Error.empty }
        guard segments.count <= 3 else { throw Error.invalidPath }
        for segment in segments {
            guard segment.count <= 64, segment.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" || $0 == "_" })
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
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == ":" { continue }
            // `hexDigitValue` also reads fullwidth forms; only ASCII counts.
            guard scalar.isASCII, let value = Character(scalar).hexDigitValue else { throw Error.invalidCharacter(Character(scalar)) }
            nibbles.append(UInt8(value))
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

    private static let phoneFormatting: Set<Unicode.Scalar> = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}", ".", "(", ")"]
    private static let atextSymbols: Set<Character> = ["!", "#", "$", "%", "&", "'", "*", "+", "-", "/", "=", "?", "^", "_", "`", "{", "|", "}", "~", "."]
    /// Neither `pchar` nor a query/fragment character in RFC 3986 §3.3-3.5;
    /// whitespace is refused earlier.
    private static let pathUnsafe: Set<Character> = ["<", ">", "\"", "\\", "^", "`", "{", "|", "}"]
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
    /// `sgnl:` scheme, or the same without a scheme.
    public static func parse(_ input: String) throws -> SignalLink {
        let text = Substring(input.trimmed())
        guard !text.isEmpty else { throw Normalize.Error.empty }
        for ch in text where ch.isWhitespace || ch.isControl { throw Normalize.Error.invalidCharacter(ch) }
        let pasted = Pasted(text)
        switch pasted.scheme {
        case nil, "https"?, "http"?, "sgnl"?: break
        case let scheme?: throw Normalize.Error.unsupportedScheme(scheme)
        }
        guard pasted.authority.lowercased() == "signal.me" else { throw Normalize.Error.wrongHost(String(pasted.authority)) }
        var rest = pasted.rest
        if rest.first == "/" { rest = rest.dropFirst() }
        guard rest.first == "#" else { throw Normalize.Error.invalidPath }
        rest = rest.dropFirst()
        if rest.hasPrefix("eu/") {
            let encoded = rest.dropFirst(3)
            guard let bytes = try? Base64.decode(encoded, url: true) else { throw Normalize.Error.invalidPath }
            return try SignalLink(username: bytes)
        }
        if rest.hasPrefix("p/") {
            return try SignalLink(phone: String(rest.dropFirst(2)))
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

/// A hostname as people type them: labels of letters, digits and hyphens,
/// at least two of them, the last one not numeric. Lowercased on the way out.
enum Hostname {
    static func normalized(_ input: Substring) -> String? {
        var text = input
        if text.last == "." { text = text.dropLast() }
        guard !text.isEmpty, text.count <= 253 else { return nil }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty, label.count <= 63, label.first != "-", label.last != "-",
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            else { return nil }
        }
        guard let last = labels.last, !last.allSatisfy(\.isNumber) else { return nil }
        return text.lowercased()
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
        if text.starts(withScalars: "//") {
            // Scheme-relative: nothing before `//` can be a scheme, so a later
            // colon is a port or part of the path.
            remainder = text.droppingPrefix("//")
        } else if let colon = text.unicodeScalars.firstIndex(of: ":") {
            let head = text[..<colon]
            let tail = text[text.unicodeScalars.index(after: colon)...]
            let looksLikeScheme = head.first?.isLetter == true
                && head.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "+" || $0 == "-" || $0 == "." })
            // `localhost:8080/x` is a host and port, not a scheme. So is
            // `mailto:1234/x`, which therefore fails as `invalidHost` rather
            // than `unsupportedScheme`.
            let port = tail.unicodeScalars.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            let looksLikePort = !port.isEmpty && port.allSatisfy(\.isASCIIDigit)
            if looksLikeScheme, tail.starts(withScalars: "//") {
                scheme = head.lowercased()
                remainder = tail.droppingPrefix("//")
            } else if looksLikeScheme, !head.contains("."), !tail.isEmpty, !looksLikePort {
                scheme = head.lowercased()
                remainder = tail
            }
        }
        let end = remainder.unicodeScalars.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? remainder.endIndex
        authority = remainder[..<end]
        rest = remainder[end...]
    }

    /// An http(s) URL on one of the given hosts (or any host when nil),
    /// with userinfo and other schemes refused.
    init(_ text: Substring, hosts: [String]?, subdomains: Bool = false) throws {
        self.init(text)
        switch scheme {
        case nil, "https"?, "http"?: break
        case let scheme?: throw Normalize.Error.unsupportedScheme(scheme)
        }
        guard !authority.unicodeScalars.contains("@") else { throw Normalize.Error.userinfo }
        let host = authority.lowercased()
        if let hosts {
            guard hosts.contains(host) || (subdomains && hosts.contains(where: { host.hasSuffix("." + $0) }))
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

    private static func hexValue(_ byte: UInt8) -> UInt8? {
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
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
    var isControl: Bool {
        unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
    /// Carries a Cf scalar: zero-width spaces, bidi overrides, a BOM, or a
    /// joiner fused to the preceding letter.
    var isFormat: Bool {
        unicodeScalars.contains { $0.properties.generalCategory == .format }
    }
}

extension StringProtocol {
    /// Strips whitespace and controls from both ends, scalar by scalar: a
    /// combining mark after a leading space is content, not whitespace.
    func trimmed() -> Substring {
        let blank = { (s: Unicode.Scalar) in s.properties.isWhitespace || s.properties.generalCategory == .control }
        var s = Substring(self).unicodeScalars.drop(while: blank)
        while let l = s.last, blank(l) { s = s.dropLast() }
        return Substring(s)
    }

    /// `hasPrefix` on scalars: a combining mark right after the prefix
    /// neither hides it nor gets dropped with it.
    func starts(withScalars prefix: String) -> Bool {
        unicodeScalars.starts(with: prefix.unicodeScalars)
    }
}

extension Substring {
    /// Drops an ASCII prefix, matched scalar by scalar.
    func droppingPrefix(_ prefix: String, caseInsensitive: Bool = false) -> Substring {
        let head = unicodeScalars.prefix(prefix.unicodeScalars.count)
        let matches = head.count == prefix.unicodeScalars.count && head.allSatisfy(\.isASCII)
            && (caseInsensitive ? String(head).lowercased() == prefix.lowercased() : head.elementsEqual(prefix.unicodeScalars))
        return matches ? self[head.endIndex...] : self
    }
}
