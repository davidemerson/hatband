/// Allow-list for links a scanned card may offer. Parsing is a strict
/// RFC 3986 split over bytes rather than Foundation's lenient `URL`, so
/// Linux and Apple agree and nothing is quietly repaired. Nothing here is
/// ever opened automatically; a verdict only decides what the UI may offer.
public enum URLPolicy {
    public static let maxBytes = 2048

    /// Schemes the system can open. `acct` and `OPENPGP4FPR` are accepted
    /// for display only.
    static let tappableSchemes: Set<String> = ["https", "http", "mailto", "tel"]

    /// RFC 6068 header fields a link may prefill. `to`, `cc` and `bcc` add
    /// recipients the card never showed (§3); the rest are for mail clients
    /// to ignore.
    static let mailtoHeaders: Set<String> = ["subject", "body"]

    /// `https` is fine; `http` warns; `mailto`, `tel`, `acct` and
    /// `OPENPGP4FPR` must parse as such. A `signal.me` link is plain https.
    /// Everything else is rejected, including any URL with userinfo,
    /// whitespace, a hidden character, or an untappable host.
    public static func verdict(for url: String) -> Verdict {
        guard url.utf8.count <= maxBytes else { return .reject("over \(maxBytes) bytes") }
        if let problem = TextCheck.problem(in: url) { return .reject(problem) }
        guard !url.unicodeScalars.contains(where: { $0.properties.isWhitespace }) else { return .reject("whitespace") }
        let bytes = Array(url.utf8)
        guard let scheme = scheme(of: bytes) else { return .reject("missing scheme") }
        let rest = bytes[(scheme.utf8.count + 1)...]
        switch scheme {
        case "https": return web(rest)
        case "http": return web(rest).merged(with: .warning("not encrypted"))
        case "mailto": return mailto(rest)
        case "tel": return isE164(rest.filter { !visualSeparators.contains($0) }) ? .ok : .reject("not an E.164 number")
        case "acct": return address(rest, or: "not an acct address")
        case "openpgp4fpr": return isFingerprint(rest) ? .ok : .reject("not an OpenPGP fingerprint")
        default: return .reject("scheme not allowed: \(scheme.prefix(32))")
        }
    }

    /// Accepted and openable by the system.
    public static func isTappable(_ url: String) -> Bool {
        guard verdict(for: url).isAccepted, let scheme = scheme(of: Array(url.utf8)) else { return false }
        return tappableSchemes.contains(scheme)
    }

    /// RFC 3986 §3.1, lowercased. Nil when the text does not start with one,
    /// or when a port follows the colon: by the grammar `example.com:80` has
    /// scheme `example.com`, but nobody means that.
    static func scheme(of bytes: [UInt8]) -> String? {
        guard let colon = bytes.firstIndex(of: UInt8(ascii: ":")), colon > 0,
              isASCIILetter(bytes[0]), bytes[..<colon].allSatisfy(isSchemeByte)
        else { return nil }
        let port = bytes[(colon + 1)...].prefix { !"/?#".utf8.contains($0) }
        guard !((1...5).contains(port.count) && port.allSatisfy(isDigit)) else { return nil }
        return String(decoding: bytes[..<colon], as: UTF8.self).lowercased()
    }

    /// `//host[:port][/path][?query][#fragment]`. The host must pass
    /// `Confusables.domainVerdict`, which refuses an IP address in any
    /// spelling and judges an `xn--` label by what it spells.
    private static func web(_ rest: ArraySlice<UInt8>) -> Verdict {
        guard rest.starts(with: "//".utf8) else { return .reject("malformed URL") }
        let afterSlashes = rest.dropFirst(2)
        let authorityEnd = afterSlashes.firstIndex { "/?#".utf8.contains($0) } ?? afterSlashes.endIndex
        let authority = afterSlashes[..<authorityEnd]
        guard !authority.contains(UInt8(ascii: "@")) else { return .reject("userinfo in URL") }
        let colon = authority.firstIndex(of: UInt8(ascii: ":")) ?? authority.endIndex
        let hostVerdict = Confusables.domainVerdict(String(decoding: authority[..<colon], as: UTF8.self))
        guard hostVerdict.isAccepted else { return hostVerdict }
        if colon < authority.endIndex {
            let port = authority[authority.index(after: colon)...]
            guard (1...5).contains(port.count), port.allSatisfy(isDigit),
                  let number = Int(String(decoding: port, as: UTF8.self)), (1...65535).contains(number)
            else { return .reject("invalid port") }
        }
        return hostVerdict.merged(with: tail(afterSlashes[authorityEnd...]))
    }

    /// RFC 6068: one address, then header fields after `?`, each named in
    /// `mailtoHeaders` (any case, percent-encoded or not).
    private static func mailto(_ rest: ArraySlice<UInt8>) -> Verdict {
        let end = rest.firstIndex(of: UInt8(ascii: "?")) ?? rest.endIndex
        let verdict = address(rest[..<end], or: "not an email address")
        guard verdict.isAccepted else { return verdict }
        let tailVerdict = tail(rest[end...])
        guard tailVerdict.isAccepted else { return tailVerdict }
        for field in rest[end...].dropFirst().split(separator: UInt8(ascii: "&")) {
            let name = percentDecoded(field.prefix { $0 != UInt8(ascii: "=") })
            guard mailtoHeaders.contains(String(decoding: name, as: UTF8.self).lowercased()) else {
                return .reject("mailto header not allowed")
            }
        }
        return verdict.merged(with: tailVerdict)
    }

    /// `local@host`: an RFC 5322 dot-atom of at most 64 bytes and a host
    /// that passes `domainVerdict`. Non-ASCII (RFC 6531) is rejected: it
    /// cannot be shown as a tappable link without an IDNA step we do not do.
    static func address(_ bytes: ArraySlice<UInt8>, or failure: String) -> Verdict {
        guard let at = bytes.firstIndex(of: UInt8(ascii: "@")), bytes.lastIndex(of: UInt8(ascii: "@")) == at
        else { return .reject(failure) }
        let local = bytes[..<at]
        guard local.allSatisfy({ $0 < 0x80 }) else { return .reject("non-ASCII character") }
        guard (1...64).contains(local.count), local.allSatisfy(isAtextOrDot),
              local.first != UInt8(ascii: "."), local.last != UInt8(ascii: "."), !hasDoubleDot(local)
        else { return .reject(failure) }
        return Confusables.domainVerdict(String(decoding: bytes[bytes.index(after: at)...], as: UTF8.self))
    }

    /// RFC 3966 global number: `+` and 2–15 digits, the first non-zero.
    static func isE164(_ bytes: some Collection<UInt8>) -> Bool {
        guard bytes.first == UInt8(ascii: "+") else { return false }
        let digits = bytes.dropFirst()
        return (2...15).contains(digits.count) && digits.allSatisfy(isDigit) && digits.first != UInt8(ascii: "0")
    }

    /// Path, query and fragment: RFC 3986 characters, valid percent triplets,
    /// and any non-ASCII that passed the scan (an IRI, RFC 3987). What the
    /// triplets encode gets the scan the raw text had: `%00`, `%0D%0A` and
    /// `%E2%80%AE` hide the same things.
    private static func tail(_ bytes: ArraySlice<UInt8>) -> Verdict {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let b = bytes[index]
            if b == UInt8(ascii: "%") {
                guard bytes.distance(from: index, to: bytes.endIndex) >= 3,
                      isHexDigit(bytes[index + 1]), isHexDigit(bytes[index + 2])
                else { return .reject("bad percent-encoding") }
                index += 3
                continue
            }
            guard b >= 0x80 || isTailByte(b) else { return .reject("invalid character in URL") }
            index += 1
        }
        if let problem = TextCheck.problem(in: String(decoding: percentDecoded(bytes), as: UTF8.self)) {
            return .reject(problem)
        }
        return .ok
    }

    /// Each `%XX` replaced by its octet; `tail` has vetted every triplet.
    private static func percentDecoded(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if bytes[index] == UInt8(ascii: "%"), bytes.distance(from: index, to: bytes.endIndex) >= 3,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                out.append(high << 4 | low)
                index += 3
            } else {
                out.append(bytes[index])
                index += 1
            }
        }
        return out
    }

    /// 40 hex digits (v4) or 64 (v6), either case.
    private static func isFingerprint(_ bytes: ArraySlice<UInt8>) -> Bool {
        (bytes.count == 40 || bytes.count == 64) && bytes.allSatisfy(isHexDigit)
    }

    /// RFC 3966 §5.1.1 visual separators, ignored in a `tel:` number.
    private static let visualSeparators: Set<UInt8> = Set("-.()".utf8)

    private static func hasDoubleDot(_ bytes: ArraySlice<UInt8>) -> Bool {
        var previous: UInt8 = 0
        for b in bytes {
            if b == UInt8(ascii: "."), previous == b { return true }
            previous = b
        }
        return false
    }

    private static func isASCIILetter(_ b: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(b) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(b)
    }

    private static func isDigit(_ b: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b)
    }

    private static func isHexDigit(_ b: UInt8) -> Bool {
        hexValue(b) != nil
    }

    private static func hexValue(_ b: UInt8) -> UInt8? {
        switch b {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return b - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return b - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return b - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    private static func isSchemeByte(_ b: UInt8) -> Bool {
        isASCIILetter(b) || isDigit(b) || "+-.".utf8.contains(b)
    }

    /// RFC 5322 atext plus `.`, less `/`: no real address uses it, and
    /// dropping it rejects the common `mailto://` mistake.
    private static func isAtextOrDot(_ b: UInt8) -> Bool {
        isASCIILetter(b) || isDigit(b) || "!#$%&'*+-=?^_`{|}~.".utf8.contains(b)
    }

    /// RFC 3986 unreserved, reserved and `%`.
    private static func isTailByte(_ b: UInt8) -> Bool {
        isASCIILetter(b) || isDigit(b) || "-._~:/?#[]@!$&'()*+,;=%".utf8.contains(b)
    }
}
