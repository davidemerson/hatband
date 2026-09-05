import Testing
@testable import HatbandCore

private let personaID: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]

private func fullCard() -> Card {
    var card = Card(personaID: personaID, issuedDay: 2438)
    card.name = "Leopold Bloom"
    card.company = "Freeman's Journal"
    card.phone = "+353871234567"
    card.email = "henry.flower@example.ie"
    card.website = Website(address: "nnix.com/~bloom", insecure: true)
    card.github = "lbloom"
    card.linkedin = "leopold-bloom"
    card.mastodon = "bloom@merveilles.town"
    card.signal = .username([UInt8](repeating: 7, count: 48))
    card.calendly = "bloom/coffee"
    card.ssh = SSHKeyField(kind: 1, bytes: [UInt8](repeating: 9, count: 32))
    card.gpgFingerprint = [UInt8](repeating: 0xab, count: 20)
    card.custom = [CustomField(label: "Pub", value: "Davy Byrne's", kind: .text),
                   CustomField(label: "Matrix", value: "@bloom:example.ie", kind: .url)]
    card.publicKey = [UInt8](repeating: 2, count: 32)
    card.signature = [UInt8](repeating: 3, count: 64)
    card.color = 4
    card.seq = 12
    card.minReader = 1
    card.photo = [0xff, 0xd8, 0xff, 0xe0]
    card.gpgKey = [0x98, 0x33, 0x04]
    return card
}

@Test func roundTripsEveryField() throws {
    let card = fullCard()
    let decoded = try Card(cbor: CBOR.decode(card.cbor.encoded))
    #expect(decoded == card)
    #expect(decoded.website?.insecure == true)
    #expect(!decoded.flags.contains(.insecureWebsite), "the bit lives in Website.insecure")
    #expect(card.cbor[FieldKey.flags.rawValue]?.unsignedValue == CardFlags.insecureWebsite.rawValue)
}

@Test func minimalCardIsTiny() throws {
    let card = Card(personaID: personaID, issuedDay: 0)
    let bytes = card.cbor.encoded
    // a2 10 48 <8 bytes> 11 00
    #expect(bytes.count == 13)
    #expect(try Card(cbor: CBOR.decode(bytes)) == card)
}

@Test func defaultsAreOmitted() {
    var card = Card(personaID: personaID, issuedDay: 1)
    #expect(card.cbor[FieldKey.flags.rawValue] == nil)
    #expect(card.cbor[FieldKey.color.rawValue] == nil)
    #expect(card.cbor[FieldKey.seq.rawValue] == nil)
    card.color = 1
    card.seq = 1
    card.flags.insert(.compact)
    #expect(card.cbor[FieldKey.flags.rawValue] == 1)
    #expect(card.cbor[FieldKey.color.rawValue] == 1)
    #expect(card.cbor[FieldKey.seq.rawValue] == 1)
}

@Test func ignoresUnknownKeysAndFlagBits() throws {
    var map = fullCard().cbor.mapValue!
    map[99] = "future"
    map[.unsigned(FieldKey.flags.rawValue)] = .unsigned(1 << 40 | 1)
    let decoded = try Card(cbor: .map(map))
    #expect(decoded.name == "Leopold Bloom")
    #expect(decoded.flags.contains(.compact))
    #expect(decoded.flags.rawValue & (1 << 40) != 0)
    #expect(decoded.unknown == [99: "future"])
}

/// Unknown entries ride through a decode and re-encode untouched, so the
/// canonical bytes, and any signature over them, survive a reader that
/// predates the key.
@Test func unknownKeysSurviveRoundTrip() throws {
    var map = fullCard().cbor.mapValue!
    map[27] = .bytes([1, 2, 3])
    map["x-vendor"] = ["a", 1]
    let bytes = CBOR.map(map).encoded
    let decoded = try Card(cbor: CBOR.decode(bytes))
    #expect(decoded.cbor.encoded == bytes)
    #expect(decoded.unknown.count == 2)
    var stripped = decoded
    stripped.unknown = [:]
    #expect(stripped.cbor.encoded != bytes)
    #expect(stripped == fullCard())
}

@Test(arguments: [
    (FieldKey.name, CBOR.unsigned(1), CardError.wrongType(.name)),
    (.personaID, .bytes([1, 2, 3]), .wrongLength(.personaID, expected: [8], actual: 3)),
    (.publicKey, .bytes([UInt8](repeating: 0, count: 31)), .wrongLength(.publicKey, expected: [32], actual: 31)),
    (.signature, .bytes([UInt8](repeating: 0, count: 65)), .wrongLength(.signature, expected: [64], actual: 65)),
    (.keyFingerprint, .bytes([1]), .wrongLength(.keyFingerprint, expected: [8], actual: 1)),
    (.gpgFingerprint, .bytes([UInt8](repeating: 0, count: 21)), .wrongLength(.gpgFingerprint, expected: [20, 32], actual: 21)),
    (.signal, .bytes([1, 2]), .wrongLength(.signal, expected: [48], actual: 2)),
    (.signal, .unsigned(5), .wrongType(.signal)),
    (.ssh, .bytes([1]), .wrongLength(.ssh, expected: [2], actual: 1)),
    (.custom, .array([["only-label"]]), .badCustomField),
    (.custom, .array([["l", "v", 9]]), .badCustomField),
    (.custom, .text("x"), .wrongType(.custom)),
    (.issuedDay, .unsigned(UInt64(UInt32.max) + 1), .outOfRange(.issuedDay)),
    (.color, .unsigned(256), .outOfRange(.color)),
    (.issuedDay, .negative(0), .wrongType(.issuedDay)),
])
func rejectsWrongShapes(key: FieldKey, value: CBOR, error: CardError) {
    var map = fullCard().cbor.mapValue!
    map[.unsigned(key.rawValue)] = value
    #expect(throws: error) { try Card(cbor: .map(map)) }
}

@Test func requiresIdentityAndDate() {
    #expect(throws: CardError.missing(.personaID)) { try Card(cbor: [17: 5]) }
    #expect(throws: CardError.missing(.issuedDay)) { try Card(cbor: [16: .bytes(personaID)]) }
    #expect(throws: CardError.notAMap) { try Card(cbor: [1, 2]) }
}

@Test func signingBytesExcludeSignature() {
    let card = fullCard()
    let signing = card.signingBytes
    #expect(!signing.isEmpty)
    var unsigned = card
    unsigned.signature = nil
    #expect(signing == unsigned.cbor.encoded)
    #expect(signing != card.cbor.encoded)
    let resigned = unsigned.withSignature([UInt8](repeating: 3, count: 64), publicKey: card.publicKey!)
    #expect(resigned == card)
}
