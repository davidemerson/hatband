/// A vCard 3.0 (RFC 2426) the way Contacts likes it: `N` and `FN`, a mobile
/// number, an internet email, labelled URLs as `item<n>.URL` pairs, a note,
/// an inline JPEG, and `X-HATBAND-*` lines for what the app wants back.
///
/// The RFC is defined on octets, so every scan here walks Unicode scalars,
/// never `Character`s: a `;` or `:` followed by a combining mark is still a
/// separator, and a value may begin with a mark.
public struct VCard: Sendable, Hashable {
    public struct Link: Sendable, Hashable {
        public var label: String
        public var url: String

        public init(label: String, url: String) {
            self.label = label
            self.url = url
        }
    }

    /// Rendered as `X-HATBAND-<NAME>:<value>`. The name is uppercased and
    /// reduced to letters, digits and hyphens when the extension is made.
    public struct Extension: Sendable, Hashable {
        public let name: String
        public var value: String

        public init(name: String, value: String) {
            self.name = VCard.propertyName(name)
            self.value = value
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case notAVCard
        case unsupportedVersion(String)
        case malformedLine(String)
    }

    public var formattedName: String
    public var familyName: String
    public var givenName: String
    public var organization: String?
    public var phone: String?
    public var email: String?
    public var links: [Link] = []
    public var note: String?
    public var photoJPEG: [UInt8]?
    public var extensions: [Extension] = []

    /// Splits the name into `N` components unless told otherwise: the last
    /// word is the family name, which is a guess Contacts lets the user fix.
    public init(formattedName: String, familyName: String? = nil, givenName: String? = nil) {
        self.formattedName = formattedName
        if let familyName, let givenName {
            self.familyName = familyName
            self.givenName = givenName
        } else {
            let words = formattedName.split(whereSeparator: \.isWhitespace)
            let guessedFamily = words.count > 1 ? String(words.last!) : ""
            let guessedGiven = words.count > 1 ? words.dropLast().joined(separator: " ") : String(words.first ?? "")
            self.familyName = familyName ?? guessedFamily
            self.givenName = givenName ?? guessedGiven
        }
    }

    // MARK: Rendering

    /// Lines end in CRLF and are folded at 75 octets on UTF-8 boundaries.
    /// Every value is escaped, so no input can start a line of its own.
    public var text: String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:" + [familyName, givenName, "", "", ""].map(Self.escape).joined(separator: ";"))
        lines.append("FN:" + Self.escape(formattedName))
        if let organization { lines.append("ORG:" + Self.escape(organization)) }
        if let phone { lines.append("TEL;TYPE=CELL:" + Self.escape(phone)) }
        if let email { lines.append("EMAIL;TYPE=INTERNET:" + Self.escape(email)) }
        for (index, link) in links.enumerated() {
            // URL is a `uri` value, which RFC 2426 §3.6.8 does not
            // backslash-escape. Escaping anyway is harmless to readers that
            // unescape, and it is what maps a line break to `\n` here.
            lines.append("item\(index + 1).URL:" + Self.escape(link.url))
            lines.append("item\(index + 1).X-ABLabel:" + Self.escape(link.label))
        }
        if let note { lines.append("NOTE:" + Self.escape(note)) }
        if let photoJPEG { lines.append("PHOTO;ENCODING=b;TYPE=JPEG:" + Base64.encode(photoJPEG)) }
        for ext in extensions {
            lines.append("X-HATBAND-" + ext.name + ":" + Self.escape(ext.value))
        }
        lines.append("END:VCARD")
        return lines.map { Self.fold($0) + "\r\n" }.joined()
    }

    public static let foldWidth = 75

    /// RFC 2426 §2.4.2: backslash, comma and semicolon get a backslash and
    /// a line break (CRLF counted once) becomes the two characters `\n`. The
    /// other C0 controls except HTAB, and DEL, are dropped: they are not
    /// VALUE-CHARs and some readers treat them as line breaks.
    static func escape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.utf8.count)
        var previous: Unicode.Scalar = " "
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case ",": out += "\\,"
            case ";": out += "\\;"
            case "\n" where previous == "\r": break
            case "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}": out += "\\n"
            case _ where isDropped(scalar): break
            default: out.unicodeScalars.append(scalar)
            }
            previous = scalar
        }
        return out
    }

    private static func isDropped(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value < 0x20 && scalar.value != 0x09) || scalar.value == 0x7f
    }

    /// RFC 2425 §5.8.1: continuation lines start with a single space, and a
    /// multi-byte character is never split.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > foldWidth else { return line }
        var out = ""
        var current = 0
        var limit = foldWidth
        for scalar in line.unicodeScalars {
            let width = scalar.utf8.count
            if current + width > limit {
                out += "\r\n "
                current = 0
                limit = foldWidth - 1
            }
            out.unicodeScalars.append(scalar)
            current += width
        }
        return out
    }

    static func propertyName(_ name: String) -> String {
        String(name.uppercased().filter { $0.isASCIIAlphanumeric || $0 == "-" })
    }

    // MARK: Parsing

    /// Reads back what `text` writes: N, FN, ORG, the first TEL and EMAIL,
    /// labelled URLs, NOTE, a base64 photo and X-HATBAND lines. Anything
    /// else, including a `VALUE=uri` photo, is skipped. Accepts LF as well
    /// as CRLF and unfolds continuations.
    public static func parseBasic(_ text: String) throws -> VCard {
        var logical: [String] = []
        for raw in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.last == "\r" ? raw.dropLast() : raw
            // A fold may land right before a combining mark, so the space is
            // a scalar, not the first grapheme.
            if let first = line.first, first == " " || first == "\t", !logical.isEmpty {
                logical[logical.count - 1] += String(line.dropFirst())
            } else if !line.isEmpty {
                logical.append(String(line))
            }
        }
        guard logical.first?.uppercased() == "BEGIN:VCARD", logical.last?.uppercased() == "END:VCARD" else {
            throw Error.notAVCard
        }
        var card = VCard(formattedName: "", familyName: "", givenName: "")
        var labels: [String: String] = [:]
        var urls: [(group: String, url: String)] = []
        let extensionPrefix = "X-HATBAND-".unicodeScalars
        for line in logical.dropFirst().dropLast() {
            guard case let (head, value)? = splitProperty(line) else { throw Error.malformedLine(line) }
            let params = head.unicodeScalars.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
            var name = params[0].uppercased()
            var group = ""
            if let dot = name.unicodeScalars.firstIndex(of: ".") {
                group = String(name[..<dot])
                name = String(name.unicodeScalars[name.unicodeScalars.index(after: dot)...])
            }
            switch name {
            case "VERSION":
                guard value == "3.0" else { throw Error.unsupportedVersion(value) }
            case "N":
                let parts = splitComponents(value)
                card.familyName = parts.count > 0 ? parts[0] : ""
                card.givenName = parts.count > 1 ? parts[1] : ""
            case "FN": card.formattedName = unescape(value)
            case "ORG": card.organization = splitComponents(value).first
            case "TEL": if card.phone == nil { card.phone = unescape(value) }
            case "EMAIL": if card.email == nil { card.email = unescape(value) }
            case "URL": urls.append((group, unescape(value)))
            case "X-ABLABEL": labels[group] = unescape(value)
            case "NOTE": card.note = unescape(value)
            case "PHOTO":
                // `VALUE=uri` is a reference, not data; that and anything
                // else that is not base64 is skipped rather than refused.
                let unquoted = params.dropFirst().map { param in String(param.uppercased().unicodeScalars.filter { $0 != "\"" }) }
                guard !unquoted.contains("VALUE=URI"), let bytes = try? Base64.decode(value.filter { !$0.isWhitespace }) else { break }
                card.photoJPEG = bytes
            default:
                if name.unicodeScalars.starts(with: extensionPrefix) {
                    let rest = String(name.unicodeScalars.dropFirst(extensionPrefix.count))
                    card.extensions.append(Extension(name: rest, value: unescape(value)))
                }
            }
        }
        card.links = urls.map { Link(label: labels[$0.group] ?? "", url: $0.url) }
        return card
    }

    /// Name and parameters, then the value: split at the first colon outside
    /// a double-quoted parameter value (RFC 2426 §4 `quoted-string`). Nil
    /// when there is no such colon.
    static func splitProperty(_ line: String) -> (head: Substring, value: String)? {
        let scalars = line.unicodeScalars
        var quoted = false
        for index in scalars.indices {
            switch scalars[index] {
            case "\"": quoted.toggle()
            case ":" where !quoted: return (line[..<index], String(scalars[scalars.index(after: index)...]))
            default: break
            }
        }
        return nil
    }

    /// Splits on unescaped semicolons, then unescapes each component.
    static func splitComponents(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for scalar in value.unicodeScalars {
            if !escaped, scalar == ";" {
                parts.append(current)
                current = ""
                continue
            }
            current.unicodeScalars.append(scalar)
            escaped = !escaped && scalar == "\\"
        }
        parts.append(current)
        return parts.map(unescape)
    }

    static func unescape(_ value: String) -> String {
        var out = ""
        var escaped = false
        for scalar in value.unicodeScalars {
            if escaped {
                out.unicodeScalars.append(scalar == "n" || scalar == "N" ? "\n" : scalar)
                escaped = false
            } else if scalar == "\\" {
                escaped = true
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        if escaped { out += "\\" }
        return out
    }
}
