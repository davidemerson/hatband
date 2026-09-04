#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// An OpenSSH public key: the wire blob of RFC 4253 §6.6, its type, and the
/// raw key material a card can carry inline. RSA keys are too large for a
/// QR code, so they travel as a SHA-256 fingerprint only.
public struct SSHPublicKey: Sendable, Hashable {
    /// The one-byte code that precedes key bytes in HB1 key 11.
    public enum Kind: UInt8, CaseIterable, Sendable {
        case ed25519 = 0x01
        case ecdsaP256 = 0x02
        case ecdsaP384 = 0x03
        case ecdsaP521 = 0x04
        case rsa = 0x10

        public init?(typeName: String) {
            guard let kind = Kind.allCases.first(where: { $0.typeName == typeName }) else { return nil }
            self = kind
        }

        /// The first field of an authorized_keys line.
        public var typeName: String {
            switch self {
            case .ed25519: return "ssh-ed25519"
            case .ecdsaP256: return "ecdsa-sha2-nistp256"
            case .ecdsaP384: return "ecdsa-sha2-nistp384"
            case .ecdsaP521: return "ecdsa-sha2-nistp521"
            case .rsa: return "ssh-rsa"
            }
        }

        /// Length of the inline material: the Ed25519 key, or an uncompressed
        /// point `04 || X || Y`. Nil for RSA.
        public var inlineLength: Int? {
            switch self {
            case .ed25519: return 32
            case .ecdsaP256: return 65
            case .ecdsaP384: return 97
            case .ecdsaP521: return 133
            case .rsa: return nil
            }
        }

        var curveName: String? {
            switch self {
            case .ecdsaP256: return "nistp256"
            case .ecdsaP384: return "nistp384"
            case .ecdsaP521: return "nistp521"
            case .ed25519, .rsa: return nil
            }
        }

        /// What `ssh-keygen -l` prints in parentheses.
        var label: String {
            switch self {
            case .ed25519: return "ED25519"
            case .ecdsaP256, .ecdsaP384, .ecdsaP521: return "ECDSA"
            case .rsa: return "RSA"
            }
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case malformedLine
        case invalidBase64
        /// An authorized_keys options field precedes the type; options are
        /// recognised the way sshd skips them, and refused.
        case optionsNotSupported
        case unsupportedType(String)
        /// FIDO keys need the authenticator; a card cannot vouch for one.
        case securityKey(String)
        case typeMismatch
        case malformedBlob
        case wrongKeyLength(Int)
        case invalidPoint
        case trailingBytes
        /// RSA has no inline form; only its fingerprint is stored.
        case notInlinable
    }

    public let kind: Kind
    /// The RFC 4253 blob, what the base64 field encodes and fingerprints cover.
    public let blob: [UInt8]
    /// Raw key material for Ed25519 and ECDSA; nil for RSA.
    public let inlineBytes: [UInt8]?
    /// Key size as `ssh-keygen -l` reports it.
    public let bits: Int
    public let comment: String?
    /// SHA-256 of the blob, the OpenSSH fingerprint.
    public let fingerprintSHA256: [UInt8]

    // MARK: Parsing

    /// An authorized_keys line: `<type> <base64> [comment]`. A leading
    /// options field (`no-pty,command="..." ssh-ed25519 ...`) is refused.
    public init(line: String) throws {
        let text = line.trimmed()
        guard !text.isEmpty, !text.contains(where: \.isNewline) else { throw Error.malformedLine }
        let fields = text.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard fields.count >= 2 else { throw Error.malformedLine }
        let typeName = String(fields[0])
        guard let kind = Kind(typeName: typeName) else {
            if typeName.hasPrefix("sk-") { throw Error.securityKey(typeName) }
            throw Self.startsWithKeyType(Self.afterOptions(text)) ? Error.optionsNotSupported : Error.unsupportedType(typeName)
        }
        guard let blob = try? Base64.decode(fields[1]) else { throw Error.invalidBase64 }
        try self.init(blob: blob, comment: fields.count == 3 ? String(fields[2].trimmed()) : nil)
        guard self.kind == kind else { throw Error.typeMismatch }
    }

    /// What follows one options field, skipped as sshd does: up to
    /// whitespace, except inside double quotes, where `\"` is a literal.
    private static func afterOptions(_ text: Substring) -> Substring {
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex, quoted || !text[index].isWhitespace {
            let next = text.index(after: index)
            if text[index] == "\\", next < text.endIndex, text[next] == "\"" {
                index = next
            } else if text[index] == "\"" {
                quoted.toggle()
            }
            index = text.index(after: index)
        }
        return text[index...].drop(while: \.isWhitespace)
    }

    private static func startsWithKeyType(_ text: Substring) -> Bool {
        let name = text.prefix { !$0.isWhitespace }
        return Kind(typeName: String(name)) != nil || name.hasPrefix("sk-")
    }

    /// Decodes a wire blob and checks the key material is well formed.
    public init(blob: [UInt8], comment: String? = nil) throws {
        var reader = WireReader(bytes: blob)
        let typeName = try reader.string()
        guard let kind = Kind(typeName: typeName) else {
            throw typeName.hasPrefix("sk-") ? Error.securityKey(typeName) : Error.unsupportedType(typeName)
        }
        var inline: [UInt8]?
        var bits = 0
        switch kind {
        case .ed25519:
            let key = try reader.field()
            guard key.count == 32 else { throw Error.wrongKeyLength(key.count) }
            inline = key
            bits = 256
        case .ecdsaP256, .ecdsaP384, .ecdsaP521:
            guard try reader.string() == kind.curveName else { throw Error.malformedBlob }
            let point = try reader.field()
            try Self.checkPoint(point, kind: kind)
            inline = point
            bits = (kind.inlineLength! - 1) / 2 * 8
            if kind == .ecdsaP521 { bits = 521 }
        case .rsa:
            _ = try reader.mpint()
            let modulus = try reader.mpint()
            bits = modulus.count * 8 - modulus.first!.leadingZeroBitCount
        }
        guard reader.isAtEnd else { throw Error.trailingBytes }
        self.init(kind: kind, blob: blob, inlineBytes: inline, bits: bits, comment: comment)
    }

    /// Rebuilds the blob from the material a card carries.
    public init(kind: Kind, inlineBytes: [UInt8], comment: String? = nil) throws {
        guard let length = kind.inlineLength else { throw Error.notInlinable }
        guard inlineBytes.count == length else { throw Error.wrongKeyLength(inlineBytes.count) }
        var blob: [UInt8] = []
        WireReader.append(string: kind.typeName, to: &blob)
        if let curve = kind.curveName {
            try Self.checkPoint(inlineBytes, kind: kind)
            WireReader.append(string: curve, to: &blob)
        }
        WireReader.append(bytes: inlineBytes, to: &blob)
        try self.init(blob: blob, comment: comment)
    }

    private init(kind: Kind, blob: [UInt8], inlineBytes: [UInt8]?, bits: Int, comment: String?) {
        self.kind = kind
        self.blob = blob
        self.inlineBytes = inlineBytes
        self.bits = bits
        self.comment = comment
        fingerprintSHA256 = Array(SHA256.hash(data: blob))
    }

    private static func checkPoint(_ point: [UInt8], kind: Kind) throws {
        guard point.count == kind.inlineLength else { throw Error.wrongKeyLength(point.count) }
        guard point.first == 0x04 else { throw Error.invalidPoint }
        let onCurve: Bool
        switch kind {
        case .ecdsaP256: onCurve = (try? P256.Signing.PublicKey(x963Representation: point)) != nil
        case .ecdsaP384: onCurve = (try? P384.Signing.PublicKey(x963Representation: point)) != nil
        case .ecdsaP521: onCurve = (try? P521.Signing.PublicKey(x963Representation: point)) != nil
        case .ed25519, .rsa: onCurve = false
        }
        guard onCurve else { throw Error.invalidPoint }
    }

    // MARK: Output

    /// What a card stores after the kind byte: the key itself, or for RSA
    /// its fingerprint.
    public var storedBytes: [UInt8] {
        inlineBytes ?? fingerprintSHA256
    }

    /// `SHA256:` and unpadded base64, as `ssh-keygen -l` prints it.
    public var fingerprintString: String {
        Self.fingerprintString(sha256: fingerprintSHA256)
    }

    public static func fingerprintString(sha256: [UInt8]) -> String {
        var text = Base64.encode(sha256)
        while text.last == "=" { text.removeLast() }
        return "SHA256:" + text
    }

    public var base64: String {
        Base64.encode(blob)
    }

    /// `<type> <base64> [comment]`. Controls and line breaks in the comment
    /// are dropped so a hostile name cannot inject a second line, and the
    /// result always re-parses with `init(line:)`.
    public func authorizedKeysLine(comment: String? = nil) -> String {
        var line = kind.typeName + " " + base64
        if let comment = (comment ?? self.comment).map(Self.oneLine), !comment.isEmpty {
            line += " " + comment
        }
        return line
    }

    /// A git `gpg.ssh.allowedSignersFile` entry: the principal (an email),
    /// the namespace restriction, and the key. A principal with nothing left
    /// after sanitising becomes `*`, the OpenSSH wildcard, so the line stays
    /// well formed.
    public func allowedSignersLine(principal: String, namespace: String = "git") -> String {
        var principal = Self.oneLine(principal).filter { !$0.isWhitespace && $0 != "," }
        if principal.isEmpty { principal = "*" }
        let namespace = Self.oneLine(namespace).filter { !$0.isWhitespace && $0 != "\"" }
        return "\(principal) namespaces=\"\(namespace)\" \(kind.typeName) \(base64)"
    }

    /// Drops controls and everything `isNewline` matches, including U+2028
    /// and U+2029, which are not controls but which `init(line:)` refuses.
    private static func oneLine(_ text: String) -> String {
        text.filter { !$0.isControl && !$0.isNewline }
    }

    // MARK: Randomart

    /// OpenSSH's drunken bishop picture of the fingerprint, with the same
    /// header and footer `ssh-keygen -lv` prints.
    public var randomart: String {
        Self.randomart(fingerprint: fingerprintSHA256, title: "[\(kind.label) \(bits)]")
    }

    /// The bishop starts in the centre of a 17x9 field and takes one
    /// diagonal step per two bits of the fingerprint, low bits first, counting
    /// visits. `S` marks the start and `E` the end.
    public static func randomart(fingerprint: [UInt8], title: String, footer: String = "[SHA256]") -> String {
        let symbols = Array(" .o+=*BOX@%&#/^SE")
        let width = 17, height = 9
        var field = [[Int]](repeating: [Int](repeating: 0, count: height), count: width)
        var x = width / 2, y = height / 2
        for byte in fingerprint {
            var input = byte
            for _ in 0..<4 {
                x += input & 1 != 0 ? 1 : -1
                y += input & 2 != 0 ? 1 : -1
                x = min(max(x, 0), width - 1)
                y = min(max(y, 0), height - 1)
                if field[x][y] < symbols.count - 3 { field[x][y] += 1 }
                input >>= 2
            }
        }
        field[width / 2][height / 2] = symbols.count - 2
        field[x][y] = symbols.count - 1

        func border(_ text: String) -> String {
            // OpenSSH formats the label into a 17-byte buffer, so at most 16
            // characters fit; a longer one is dropped.
            let label = text.count < width ? text : ""
            let lead = (width - label.count) / 2
            return "+" + String(repeating: "-", count: lead) + label
                + String(repeating: "-", count: width - lead - label.count) + "+"
        }
        var lines = [border(title)]
        for row in 0..<height {
            lines.append("|" + String((0..<width).map { symbols[field[$0][row]] }) + "|")
        }
        lines.append(border(footer))
        return lines.joined(separator: "\n")
    }
}

/// RFC 4251 §5 primitives: `string` is a big-endian uint32 length and bytes;
/// `mpint` is a string holding a two's-complement integer without redundant
/// leading bytes.
struct WireReader {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool { offset == bytes.count }

    mutating func field() throws -> [UInt8] {
        guard bytes.count - offset >= 4 else { throw SSHPublicKey.Error.malformedBlob }
        let length = bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        offset += 4
        guard bytes.count - offset >= length else { throw SSHPublicKey.Error.malformedBlob }
        defer { offset += length }
        return Array(bytes[offset..<offset + length])
    }

    mutating func string() throws -> String {
        guard let text = String(validating: try field(), as: UTF8.self) else { throw SSHPublicKey.Error.malformedBlob }
        return text
    }

    /// A positive mpint, minimally encoded.
    mutating func mpint() throws -> [UInt8] {
        let value = try field()
        guard let first = value.first, first & 0x80 == 0 else { throw SSHPublicKey.Error.malformedBlob }
        if first == 0 {
            guard value.count > 1, value[1] & 0x80 != 0 else { throw SSHPublicKey.Error.malformedBlob }
            return Array(value.dropFirst())
        }
        return value
    }

    static func append(bytes: [UInt8], to out: inout [UInt8]) {
        let n = UInt32(bytes.count)
        out.append(contentsOf: [UInt8(n >> 24), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)])
        out.append(contentsOf: bytes)
    }

    static func append(string: String, to out: inout [UInt8]) {
        append(bytes: Array(string.utf8), to: &out)
    }
}
