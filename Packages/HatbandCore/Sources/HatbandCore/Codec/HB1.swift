/// The HB1 wire forms: a URL whose fragment is a format tag plus Base32 of the
/// card's CBOR, and a file that is the CBOR behind a four-byte magic.
public enum HB1 {
    public static let host = "hatband.link"
    public static let urlPrefix = "https://\(host)/#"
    /// Not a Base32 character, so the fragment is self-describing. Only
    /// `0`, `1`, `8` and `9` are outside the alphabet; those are the tags.
    public static let formatTag: Character = "1"
    static let possibleTags: Set<Character> = ["0", "1", "8", "9"]
    public static let fileMagic: [UInt8] = [0x48, 0x42, 0x31, 0x00]
    public static let fileExtension = "hatband"

    public enum Error: Swift.Error, Equatable, Sendable {
        case notHatband
        case unsupportedFormat(Character)
        case badMagic
        case tooLarge(Int)
    }

    /// Hard ceiling on any form, in CBOR bytes. Tiers are checked elsewhere.
    public static let maxBytes = 32_768

    public static func url(for card: Card) -> String {
        urlPrefix + String(formatTag) + Base32.encode(card.cbor.encoded)
    }

    public static func fileBytes(for card: Card) -> [UInt8] {
        fileMagic + card.cbor.encoded
    }

    /// Accepts the full URL (any case in scheme and host), the bare fragment
    /// after `#`, or the fragment with a leading `#`.
    public static func decode(url text: String) throws -> Card {
        var s = Substring(text.trimmingWhitespace())
        if s.first == "#" {
            s = s.dropFirst()
        } else if let hash = s.firstIndex(of: "#") {
            let head = s[..<hash].lowercased()
            guard head == urlPrefix.dropLast() else { throw Error.notHatband }
            s = s[s.index(after: hash)...]
        }
        guard let tag = s.first, possibleTags.contains(tag) else { throw Error.notHatband }
        guard tag == formatTag else { throw Error.unsupportedFormat(tag) }
        let body: [UInt8]
        do {
            body = try Base32.decode(s.dropFirst())
        } catch {
            throw Error.notHatband
        }
        return try decode(cbor: body)
    }

    public static func decode(file bytes: [UInt8]) throws -> Card {
        guard bytes.starts(with: fileMagic) else { throw Error.badMagic }
        return try decode(cbor: Array(bytes.dropFirst(fileMagic.count)))
    }

    public static func decode(cbor bytes: [UInt8]) throws -> Card {
        guard bytes.count <= maxBytes else { throw Error.tooLarge(bytes.count) }
        return try Card(cbor: CBOR.decode(bytes))
    }

    /// Size of the card's CBOR, the number every budget is measured in.
    public static func encodedSize(of card: Card) -> Int {
        card.cbor.encoded.count
    }
}

private extension String {
    func trimmingWhitespace() -> Substring {
        var s = Substring(self)
        while let f = s.first, f.isWhitespace { s = s.dropFirst() }
        while let l = s.last, l.isWhitespace { s = s.dropLast() }
        return s
    }
}
