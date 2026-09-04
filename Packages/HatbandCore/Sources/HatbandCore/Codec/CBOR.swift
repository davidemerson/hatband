/// A CBOR value (RFC 8949) limited to what HB1 needs: integers, byte and text
/// strings, arrays, maps, booleans and null. Encoding is deterministic per
/// RFC 8949 §4.2.1 and decoding rejects anything that is not.
public indirect enum CBOR: Hashable, Sendable {
    case unsigned(UInt64)
    /// Encodes the integer `-1 - value`.
    case negative(UInt64)
    case bytes([UInt8])
    case text(String)
    case array([CBOR])
    case map([CBOR: CBOR])
    case bool(Bool)
    case null
}

public enum CBORError: Error, Equatable, Sendable {
    case truncated
    case notShortestForm
    case indefiniteLength
    case unsupported(majorType: UInt8, info: UInt8)
    case invalidUTF8
    case mapKeysNotOrdered
    case trailingBytes
    case tooDeep
}

// MARK: - Encoding

extension CBOR {
    /// Deterministic encoding: shortest integer forms, map keys sorted by
    /// their encoded bytes, no indefinite lengths.
    public var encoded: [UInt8] {
        var out: [UInt8] = []
        encode(into: &out)
        return out
    }

    private func encode(into out: inout [UInt8]) {
        switch self {
        case .unsigned(let v):
            CBOR.header(major: 0, value: v, into: &out)
        case .negative(let v):
            CBOR.header(major: 1, value: v, into: &out)
        case .bytes(let b):
            CBOR.header(major: 2, value: UInt64(b.count), into: &out)
            out.append(contentsOf: b)
        case .text(let s):
            let utf8 = Array(s.utf8)
            CBOR.header(major: 3, value: UInt64(utf8.count), into: &out)
            out.append(contentsOf: utf8)
        case .array(let a):
            CBOR.header(major: 4, value: UInt64(a.count), into: &out)
            for item in a { item.encode(into: &out) }
        case .map(let m):
            CBOR.header(major: 5, value: UInt64(m.count), into: &out)
            let entries = m
                .map { (key: $0.key.encoded, value: $0.value) }
                .sorted { $0.key.lexicographicallyPrecedes($1.key) }
            for entry in entries {
                out.append(contentsOf: entry.key)
                entry.value.encode(into: &out)
            }
        case .bool(let b):
            out.append(b ? 0xf5 : 0xf4)
        case .null:
            out.append(0xf6)
        }
    }

    private static func header(major: UInt8, value: UInt64, into out: inout [UInt8]) {
        let m = major << 5
        switch value {
        case 0..<24:
            out.append(m | UInt8(value))
        case 24...0xff:
            out.append(m | 24)
            out.append(UInt8(value))
        case 0x100...0xffff:
            out.append(m | 25)
            appendBigEndian(value, bytes: 2, into: &out)
        case 0x1_0000...0xffff_ffff:
            out.append(m | 26)
            appendBigEndian(value, bytes: 4, into: &out)
        default:
            out.append(m | 27)
            appendBigEndian(value, bytes: 8, into: &out)
        }
    }

    private static func appendBigEndian(_ value: UInt64, bytes: Int, into out: inout [UInt8]) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            out.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}

// MARK: - Decoding

extension CBOR {
    /// Nesting deeper than this is rejected; HB1 never exceeds three levels.
    public static let maxDepth = 32

    /// Strict decoding. Fails on non-shortest integers, indefinite lengths,
    /// tags, floats, invalid UTF-8, unordered or duplicate map keys, and
    /// trailing bytes.
    public static func decode(_ bytes: [UInt8]) throws -> CBOR {
        var parser = Parser(bytes: bytes)
        let value = try parser.item(depth: 0)
        guard parser.offset == bytes.count else { throw CBORError.trailingBytes }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var offset = 0

        var remaining: Int { bytes.count - offset }

        mutating func byte() throws -> UInt8 {
            guard remaining >= 1 else { throw CBORError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard remaining >= count else { throw CBORError.truncated }
            defer { offset += count }
            return bytes[offset..<offset + count]
        }

        mutating func argument(major: UInt8, info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24:
                return UInt64(info)
            case 24:
                let v = UInt64(try byte())
                guard v >= 24 else { throw CBORError.notShortestForm }
                return v
            case 25:
                let v = try bigEndian(bytes: 2)
                guard v > 0xff else { throw CBORError.notShortestForm }
                return v
            case 26:
                let v = try bigEndian(bytes: 4)
                guard v > 0xffff else { throw CBORError.notShortestForm }
                return v
            case 27:
                let v = try bigEndian(bytes: 8)
                guard v > 0xffff_ffff else { throw CBORError.notShortestForm }
                return v
            case 31:
                throw CBORError.indefiniteLength
            default:
                throw CBORError.unsupported(majorType: major, info: info)
            }
        }

        mutating func bigEndian(bytes count: Int) throws -> UInt64 {
            let slice = try take(count)
            return slice.reduce(0) { ($0 << 8) | UInt64($1) }
        }

        /// A length argument bounded by the bytes that remain, so a hostile
        /// header cannot make us allocate for content that is not there.
        mutating func length(major: UInt8, info: UInt8) throws -> Int {
            let v = try argument(major: major, info: info)
            guard v <= UInt64(remaining) else { throw CBORError.truncated }
            return Int(v)
        }

        mutating func item(depth: Int) throws -> CBOR {
            guard depth <= CBOR.maxDepth else { throw CBORError.tooDeep }
            let initial = try byte()
            let major = initial >> 5
            let info = initial & 0x1f
            switch major {
            case 0:
                return .unsigned(try argument(major: major, info: info))
            case 1:
                return .negative(try argument(major: major, info: info))
            case 2:
                let n = try length(major: major, info: info)
                return .bytes(Array(try take(n)))
            case 3:
                let n = try length(major: major, info: info)
                guard let s = String(validating: try take(n), as: UTF8.self) else {
                    throw CBORError.invalidUTF8
                }
                return .text(s)
            case 4:
                let n = try length(major: major, info: info)
                var array: [CBOR] = []
                array.reserveCapacity(n)
                for _ in 0..<n { array.append(try item(depth: depth + 1)) }
                return .array(array)
            case 5:
                let n = try length(major: major, info: info)
                var map: [CBOR: CBOR] = [:]
                map.reserveCapacity(n)
                var previousKey: ArraySlice<UInt8>?
                for _ in 0..<n {
                    let start = offset
                    let key = try item(depth: depth + 1)
                    let keyBytes = bytes[start..<offset]
                    if let previous = previousKey, !previous.lexicographicallyPrecedes(keyBytes) {
                        throw CBORError.mapKeysNotOrdered
                    }
                    previousKey = keyBytes
                    map[key] = try item(depth: depth + 1)
                }
                return .map(map)
            case 7:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                default: throw CBORError.unsupported(majorType: major, info: info)
                }
            default:
                throw CBORError.unsupported(majorType: major, info: info)
            }
        }
    }
}

// MARK: - Literals and accessors

extension CBOR: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = value >= 0 ? .unsigned(UInt64(value)) : .negative(UInt64(~value))
    }
}

extension CBOR: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
}

extension CBOR: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension CBOR: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: CBOR...) { self = .array(elements) }
}

extension CBOR: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (CBOR, CBOR)...) {
        var map: [CBOR: CBOR] = [:]
        for (key, value) in elements {
            precondition(map.updateValue(value, forKey: key) == nil, "duplicate CBOR map key")
        }
        self = .map(map)
    }
}

extension CBOR {
    public var unsignedValue: UInt64? {
        if case .unsigned(let v) = self { return v }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .unsigned(let v): return Int(exactly: v)
        case .negative(let v): return v < UInt64(Int.max) ? -1 - Int(v) : nil
        default: return nil
        }
    }

    public var bytesValue: [UInt8]? {
        if case .bytes(let v) = self { return v }
        return nil
    }

    public var textValue: String? {
        if case .text(let v) = self { return v }
        return nil
    }

    public var arrayValue: [CBOR]? {
        if case .array(let v) = self { return v }
        return nil
    }

    public var mapValue: [CBOR: CBOR]? {
        if case .map(let v) = self { return v }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    /// Map lookup by integer key, the shape every HB1 card uses.
    public subscript(key: UInt64) -> CBOR? {
        mapValue?[.unsigned(key)]
    }
}
