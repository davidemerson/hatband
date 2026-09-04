/// A vCard 3.0 (RFC 2426) the way Contacts likes it: `N` and `FN`, a mobile
/// number, an internet email, labelled URLs as `item<n>.URL` pairs, a note,
/// an inline JPEG, and `X-HATBAND-*` lines for what the app wants back.
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
    /// a line break becomes the two characters `\n`. The other C0 controls
    /// except HTAB, and DEL, are dropped: they are not VALUE-CHARs and some
    /// readers treat them as line breaks.
    static func escape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.utf8.count)
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case ",": out += "\\,"
            case ";": out += "\\;"
            case "\r\n", "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}": out += "\\n"
            default:
                for scalar in ch.unicodeScalars where !Self.isDropped(scalar) { out.unicodeScalars.append(scalar) }
            }
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
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\r\n" || $0 == "\n" }) {
            // Scalars, not graphemes: a fold may land before a combining mark.
            if let first = raw.unicodeScalars.first, first == " " || first == "\t", !logical.isEmpty {
                logical[logical.count - 1] += String(Substring(raw.unicodeScalars.dropFirst()))
            } else if !raw.isEmpty {
                logical.append(String(raw))
            }
        }
        guard logical.first?.uppercased() == "BEGIN:VCARD", logical.last?.uppercased() == "END:VCARD" else {
            throw Error.notAVCard
        }
        var card = VCard(formattedName: "", familyName: "", givenName: "")
        var labels: [String: String] = [:]
        var urls: [(group: String, url: String)] = []
        for line in logical.dropFirst().dropLast() {
            guard case let (head, value)? = splitProperty(line) else { throw Error.malformedLine(line) }
            let nameAndParams = head.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            var name = nameAndParams[0].uppercased()
            var group = ""
            if let dot = name.firstIndex(of: ".") {
                group = String(name[..<dot])
                name = String(name[name.index(after: dot)...])
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
                let params = head.split(separator: ";").dropFirst().map { $0.uppercased().filter { $0 != "\"" } }
                guard !params.contains("VALUE=URI"), let bytes = try? Base64.decode(value.filter { !$0.isWhitespace }) else { break }
                card.photoJPEG = bytes
            default:
                if name.hasPrefix("X-HATBAND-") {
                    card.extensions.append(Extension(name: String(name.dropFirst("X-HATBAND-".count)), value: unescape(value)))
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
        var quoted = false
        for index in line.indices {
            switch line[index] {
            case "\"": quoted.toggle()
            case ":" where !quoted: return (line[..<index], String(line[line.index(after: index)...]))
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
        for ch in value {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                current.append(ch)
                escaped = true
            } else if ch == ";" {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts.map(unescape)
    }

    static func unescape(_ value: String) -> String {
        var out = ""
        var escaped = false
        for ch in value {
            if escaped {
                switch ch {
                case "n", "N": out.append("\n")
                default: out.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                out.append(ch)
            }
        }
        if escaped { out.append("\\") }
        return out
    }
}
