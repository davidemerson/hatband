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
    /// form has no `@`.
    public static func mastodon(_ handle: String) -> (account: String, profile: String)? {
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
        for ch in text {
            if ch.isWhitespace || phoneFormatting.contains(ch) { continue }
            if ch == "+" && !sawPlus && digits.isEmpty {
                sawPlus = true
                continue
            }
            guard ch.isASCIIDigit else { throw Error.invalidCharacter(ch) }
            digits.append(ch)
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
        if text.last == ">", let open = text.lastIndex(of: "<") {
            text = text[text.index(after: open)..<text.index(before: text.endIndex)].trimmed()
        }
        let hadScheme = text.lowercased().hasPrefix("mailto:")
        text = text.droppingPrefix("mailto:", caseInsensitive: true)
        if hadScheme {
            if let query = text.firstIndex(of: "?") { text = text[..<query] }
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
    /// flag, the host is lowercased, the path and query are kept as typed.
    public static func website(_ input: String) throws -> (address: String, insecure: Bool) {
        let text = Substring(input.trimmed())
        guard !text.isEmpty else { throw Error.empty }
        for ch in text where ch.isWhitespace || ch.isControl { throw Error.invalidCharacter(ch) }
        let pasted = Pasted(text)
        var insecure = false
        switch pasted.scheme {
        case nil, "https"?: break
        case "http"?: insecure = true
        case let scheme?: throw Error.unsupportedScheme(scheme)
        }
        guard !pasted.authority.contains("@") else { throw Error.userinfo }
        var hostPart = pasted.authority
        var port = ""
        if let colon = hostPart.lastIndex(of: ":") {
            let digits = hostPart[hostPart.index(after: colon)...]
            guard !digits.isEmpty, digits.count <= 5, digits.allSatisfy(\.isASCIIDigit),
                  let number = Int(digits), number <= 65535
            else { throw Error.invalidHost }
            port = ":" + String(number)
            hostPart = hostPart[..<colon]
        }
        guard let host = Hostname.normalized(hostPart) else { throw Error.invalidHost }
        let rest = pasted.rest == "/" ? "" : pasted.rest
        return (host + port + rest, insecure)
    }

    /// `@user`, `user`, or a github.com profile URL. Usernames are 1 to 39
    /// letters, digits and hyphens, not starting or ending with a hyphen.
    public static func github(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        var user = text
        if text.contains("/") || text.lowercased().contains("github.com") {
            let pasted = try Pasted(text, hosts: ["github.com", "www.github.com"])
            guard let first = pasted.pathSegments.first else { throw Error.invalidPath }
            user = first
        }
        guard user.count <= 39 else { throw Error.tooLong }
        guard !user.isEmpty, user.first != "-", user.last != "-",
              user.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" })
        else { throw Error.invalidUsername }
        return String(user)
    }

    /// A slug, `in/<slug>`, `company/<slug>`, or any linkedin.com URL
    /// including locale subdomains. Stored as the slug, or `company/<slug>`.
    public static func linkedin(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        var kind = "in"
        var slug = text
        let lower = text.lowercased()
        var segments: [Substring]?
        if lower.hasPrefix("in/") || lower.hasPrefix("company/") {
            segments = Pasted.segments(of: text)
        } else if text.contains("/") || lower.contains("linkedin.com") {
            segments = try Pasted(text, hosts: ["linkedin.com"], subdomains: true).pathSegments
        }
        if let segments {
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
    /// `https://instance/users/user`. Stored as `user@instance`.
    public static func mastodon(_ input: String) throws -> String {
        let text = Substring(input.trimmed()).droppingPrefix("@")
        guard !text.isEmpty else { throw Error.empty }
        let user: Substring
        let instance: Substring
        if text.contains("/") {
            let pasted = try Pasted(text, hosts: nil)
            let segments = pasted.pathSegments
            if segments.count == 1, segments[0].first == "@" {
                user = segments[0].dropFirst()
            } else if segments.count == 2, segments[0] == "users" {
                user = segments[1]
            } else {
                throw Error.invalidPath
            }
            instance = pasted.authority
        } else {
            let parts = text.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { throw Error.missingAt }
            guard parts.count == 2 else { throw Error.multipleAt }
            user = parts[0]
            instance = parts[1]
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

    /// 40 hex digits (v4) or 64 (v5/v6), with any spaces or colons, and an
    /// optional `0x` or `OPENPGP4FPR:` prefix.
    public static func gpgFingerprint(_ input: String) throws -> GPGFingerprint {
        var text = Substring(input.trimmed())
        text = text.droppingPrefix("OPENPGP4FPR:", caseInsensitive: true).trimmed()
        text = text.droppingPrefix("0x", caseInsensitive: true)
        var nibbles: [UInt8] = []
        for ch in text {
            if ch.isWhitespace || ch == ":" { continue }
            guard let value = ch.hexDigitValue else { throw Error.invalidCharacter(ch) }
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

    private static let phoneFormatting: Set<Character> = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}", ".", "(", ")"]
    private static let atextSymbols: Set<Character> = ["!", "#", "$", "%", "&", "'", "*", "+", "-", "/", "=", "?", "^", "_", "`", "{", "|", "}", "~", "."]
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
struct Pasted {
    var scheme: String?
    var authority: Substring
    /// Path, query and fragment, starting with `/`, `?` or `#`; or empty.
    var rest: Substring

    init(_ text: Substring) {
        var remainder = text
        if let colon = text.firstIndex(of: ":") {
            let head = text[..<colon]
            let tail = text[text.index(after: colon)...]
            let looksLikeScheme = head.first?.isLetter == true
                && head.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "+" || $0 == "-" || $0 == "." })
            if looksLikeScheme, tail.hasPrefix("//") {
                scheme = head.lowercased()
                remainder = tail.dropFirst(2)
            } else if looksLikeScheme, !head.contains("."), !tail.isEmpty, !tail.allSatisfy(\.isASCIIDigit) {
                scheme = head.lowercased()
                remainder = tail
            }
        } else if text.hasPrefix("//") {
            remainder = text.dropFirst(2)
        }
        let end = remainder.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? remainder.endIndex
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
        guard !authority.contains("@") else { throw Normalize.Error.userinfo }
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
        let end = path.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? path.endIndex
        return path[..<end].split(separator: "/", omittingEmptySubsequences: true)
    }
}

enum PercentEncoding {
    /// Decodes `%XX` triples; nil when a triple is malformed or the result is
    /// not UTF-8. Text without `%` comes back unchanged.
    static func decode(_ text: Substring) -> String? {
        guard text.contains("%") else { return String(text) }
        var bytes: [UInt8] = []
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            if byte == UInt8(ascii: "%") {
                guard let high = iterator.next(), let low = iterator.next(),
                      let h = Character(Unicode.Scalar(high)).hexDigitValue,
                      let l = Character(Unicode.Scalar(low)).hexDigitValue
                else { return nil }
                bytes.append(UInt8(h << 4 | l))
            } else {
                bytes.append(byte)
            }
        }
        return String(validating: bytes, as: UTF8.self)
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
    var isControl: Bool {
        unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

extension StringProtocol {
    func trimmed() -> Substring {
        var s = Substring(self)
        while let f = s.first, f.isWhitespace || f.isControl { s = s.dropFirst() }
        while let l = s.last, l.isWhitespace || l.isControl { s = s.dropLast() }
        return s
    }
}

extension Substring {
    func droppingPrefix(_ prefix: String, caseInsensitive: Bool = false) -> Substring {
        let matches = caseInsensitive ? lowercased().hasPrefix(prefix.lowercased()) : hasPrefix(prefix)
        return matches ? dropFirst(prefix.count) : self
    }
}
