// Emits the HB1 test vectors as JSON on stdout. Deterministic on Linux, where
// Ed25519 signing is; on Apple platforms signatures differ per run, so the
// checked-in file is regenerated on Linux only (scripts/gen-vectors.sh).
import HatbandCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

let seed = (0..<32).map { UInt8($0) }
let identity = try Identity(seed: seed)
let issuedDay: UInt32 = 2438 // 2026-09-04

struct Vector {
    var name: String
    var description: String
    var card: Card
    var keyIndex: UInt32?
    var tamper = false
}

func id(_ n: UInt8) -> [UInt8] { [UInt8](repeating: n, count: 8) }

var typical = Card(personaID: id(1), issuedDay: issuedDay)
typical.name = "Leopold Bloom"
typical.company = "Freeman's Journal"
typical.phone = "+353871234567"
typical.email = "henry.flower@example.ie"
typical.website = Website(address: "nnix.com")
typical.github = "lbloom"
typical.linkedin = "leopold-bloom"
typical.mastodon = "bloom@merveilles.town"
typical.calendly = "bloom/coffee"
typical.color = 2
typical.seq = 1

var maximal = typical
maximal.personaID = id(2)
maximal.signal = .username((0..<48).map { UInt8($0 &* 5 &+ 3) })
maximal.ssh = SSHKeyField(kind: 1, bytes: (0..<32).map { UInt8(0x40 + $0) })
maximal.gpgFingerprint = (0..<20).map { UInt8(0xa0 + $0) }
maximal.custom = [
    CustomField(label: "Pub", value: "Davy Byrne's", kind: .text),
    CustomField(label: "Matrix", value: "https://matrix.to/#/@bloom:example.ie", kind: .url),
    CustomField(label: "Fax", value: "+35318000000", kind: .phone),
]
maximal.website = Website(address: "example.org/~bloom", insecure: true)
maximal.seq = 7
maximal.minReader = 1

var compact = Card(personaID: id(1), issuedDay: issuedDay)
compact.flags.insert(.compact)
compact.name = "Leopold Bloom"
compact.color = 2
compact.seq = 1
compact = compact.withKeyFingerprint(of: identity.personaSigningKey(index: 1).publicKey.rawRepresentation.map { $0 })

var compactChannels = compact
compactChannels.email = "henry.flower@example.ie"
compactChannels.mastodon = "bloom@merveilles.town"

var file = maximal
file.personaID = id(3)
file.flags.insert(.photoAvailable)
file.photo = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01] + (0..<200).map { UInt8($0 & 0xff) } + [0xff, 0xd9]
file.gpgKey = [0x98, 0x33, 0x04] + (0..<120).map { UInt8(truncatingIfNeeded: $0 &* 7) }

var alias = Card(personaID: id(4), issuedDay: issuedDay)
alias.flags.insert(.alias)
alias.name = "Henry Flower"
alias.email = "henry@flower.ie"
alias.color = 9

var nfc = Card(personaID: id(5), issuedDay: issuedDay)
nfc.name = "Zo\u{eb} Bl\u{f6}m 水 🏳️‍🌈"
nfc.company = "Ærøskøbing & Søn"
var nfd = nfc
nfd.personaID = id(6)
nfd.name = "Zoe\u{308} Blo\u{308}m 水 🏳️‍🌈"

var empty = Card(personaID: id(7), issuedDay: 0)

let vectors: [Vector] = [
    Vector(name: "minimal", description: "Only the required keys: persona id and issued day.", card: empty, keyIndex: nil),
    Vector(name: "compact-name-only", description: "Lock Screen tier as built by default: name, key fingerprint, colour, seq. Unsigned.", card: compact, keyIndex: nil),
    Vector(name: "compact-two-channels", description: "Lock Screen tier with the two optional channels.", card: compactChannels, keyIndex: nil),
    Vector(name: "typical-signed", description: "A signed full card with the common channels.", card: typical, keyIndex: 1),
    Vector(name: "maximal-qr-signed", description: "Every channel, custom fields, http website, signed; the largest card meant for a QR.", card: maximal, keyIndex: 2),
    Vector(name: "file-with-photo-and-key", description: "File/URL form carrying a photo and a GPG key; never a QR.", card: file, keyIndex: 3),
    Vector(name: "alias-signed", description: "An alias persona (Henry Flower).", card: alias, keyIndex: 4),
    Vector(name: "unicode-nfc", description: "Precomposed accents, CJK and an emoji ZWJ sequence; bytes are stored as given.", card: nfc, keyIndex: 5),
    Vector(name: "unicode-nfd", description: "The same name decomposed; a different card on the wire.", card: nfd, keyIndex: 6),
    Vector(name: "tampered-signature", description: "typical-signed with one bit of the signature flipped; must not verify.", card: typical, keyIndex: 1, tamper: true),
]

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { let s = String($0, radix: 16); return s.count == 1 ? "0" + s : s }.joined()
}

func jsonString(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case let c where c.value < 0x20:
            let h = String(c.value, radix: 16)
            out += "\\u" + String(repeating: "0", count: 4 - h.count) + h
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

/// The map as JSON: text as strings, integers as numbers, bytes as {"hex": ...},
/// custom fields as arrays. Keys are decimal strings in numeric order.
func jsonMap(_ value: CBOR) -> String {
    func render(_ v: CBOR) -> String {
        switch v {
        case .unsigned(let u): return String(u)
        case .negative(let n): return "-" + String(n + 1)
        case .text(let s): return jsonString(s)
        case .bytes(let b): return "{\"hex\":\"" + hex(b) + "\"}"
        case .array(let a): return "[" + a.map(render).joined(separator: ",") + "]"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .map(let m):
            let keys = m.keys.sorted { $0.encoded.lexicographicallyPrecedes($1.encoded) }
            return "{" + keys.map { key in
                let name = key.unsignedValue.map(String.init) ?? key.textValue ?? hex(key.encoded)
                return jsonString(name) + ":" + render(m[key]!)
            }.joined(separator: ",") + "}"
        }
    }
    return render(value)
}

// Plain appends: one long `+` chain is too slow for the type checker.
var out = "{\n  \"format\": \"HB1\",\n  \"version\": 1,\n"
out += "  \"urlPrefix\": " + jsonString(HB1.urlPrefix) + ",\n"
out += "  \"fileMagic\": \"" + hex(HB1.fileMagic) + "\",\n"
out += "  \"identitySeed\": \"" + hex(seed) + "\",\n"
out += "  \"signingDomain\": " + jsonString("hatband-card-v1") + ",\n"
out += "  \"vectors\": [\n"
for (i, v) in vectors.enumerated() {
    var card = v.card
    if let index = v.keyIndex {
        card = try card.signed(with: identity.personaSigningKey(index: index))
    }
    if v.tamper {
        card.signature![0] ^= 0x01
    }
    let cbor = card.cbor.encoded
    var fields: [(String, String)] = [
        ("name", jsonString(v.name)),
        ("description", jsonString(v.description)),
        ("keyIndex", v.keyIndex.map(String.init) ?? "null"),
        ("valid", card.publicKey == nil ? "null" : (card.signatureIsValid ? "true" : "false")),
        ("map", jsonMap(card.cbor)),
        ("cbor", "\"" + hex(cbor) + "\""),
        ("url", jsonString(HB1.url(for: card))),
        ("file", "\"" + hex(HB1.fileBytes(for: card)) + "\""),
        ("signingBytes", "\"" + hex(card.signingBytes) + "\""),
    ]
    if let key = card.publicKey { fields.append(("publicKey", "\"" + hex(key) + "\"")) }
    if let sig = card.signature { fields.append(("signature", "\"" + hex(sig) + "\"")) }
    let version = Budget(card: card).version.map(String.init) ?? "null"
    fields.append(("budget", "{\"bytes\":\(cbor.count),\"qrVersion\":\(version)}"))
    let body = fields.map { "      " + jsonString($0.0) + ": " + $0.1 }.joined(separator: ",\n")
    out += "    {\n"
    out += body
    out += i == vectors.count - 1 ? "\n    }\n" : "\n    },\n"
}
out += "  ]\n}\n"
print(out, terminator: "")
