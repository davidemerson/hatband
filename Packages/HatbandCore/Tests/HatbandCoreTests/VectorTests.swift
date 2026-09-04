import Foundation
import Testing
@testable import HatbandCore

/// The checked-in vectors are what every other implementation is tested
/// against; this proves the Swift side still agrees with them.
private let vectorsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("spec/vectors/cards.json")

private func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var iterator = hex.makeIterator()
    while let high = iterator.next(), let low = iterator.next() {
        out.append(UInt8(String([high, low]), radix: 16)!)
    }
    return out
}

private func loadVectors() throws -> [[String: Any]] {
    let data = try Data(contentsOf: vectorsURL)
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(root["format"] as? String == "HB1")
    #expect(root["urlPrefix"] as? String == HB1.urlPrefix)
    return try #require(root["vectors"] as? [[String: Any]])
}

/// Renders a CBOR value the way the generator does, for comparison with "map".
private func jsonValue(_ v: CBOR) -> Any {
    switch v {
    case .unsigned(let u): return u
    case .negative(let n): return -Int64(n) - 1
    case .text(let s): return s
    case .bytes(let b): return ["hex": b.map { let s = String($0, radix: 16); return s.count == 1 ? "0" + s : s }.joined()]
    case .array(let a): return a.map(jsonValue)
    case .bool(let b): return b
    case .null: return NSNull()
    case .map(let m):
        var out: [String: Any] = [:]
        for (k, val) in m { out[k.unsignedValue.map(String.init) ?? k.textValue ?? "?"] = jsonValue(val) }
        return out
    }
}

@Test func vectorsRoundTripInEveryForm() throws {
    let vectors = try loadVectors()
    #expect(vectors.count >= 10)
    for vector in vectors {
        let name = try #require(vector["name"] as? String)
        let cbor = bytes(try #require(vector["cbor"] as? String))
        let card = try HB1.decode(cbor: cbor)
        #expect(card.cbor.encoded == cbor, "\(name): canonical re-encode")
        #expect(try HB1.decode(url: try #require(vector["url"] as? String)) == card, "\(name): url")
        #expect(try HB1.decode(file: bytes(try #require(vector["file"] as? String))) == card, "\(name): file")
        #expect(card.signingBytes == bytes(try #require(vector["signingBytes"] as? String)), "\(name): signing bytes")
        #expect(HB1.url(for: card) == vector["url"] as? String, "\(name): url form")
        let expectedMap = try #require(vector["map"] as? [String: Any])
        let actualMap = try #require(jsonValue(card.cbor) as? [String: Any])
        #expect(NSDictionary(dictionary: actualMap).isEqual(to: expectedMap), "\(name): map")
        if let valid = vector["valid"] as? Bool {
            #expect(card.publicKey?.count == 32 && card.signature?.count == 64, "\(name): signed shape")
            #expect(card.signatureIsValid == valid, "\(name): signature")
            #expect(bytes(try #require(vector["publicKey"] as? String)) == card.publicKey, "\(name): key")
        } else {
            #expect(card.signature == nil, "\(name): unsigned")
        }
        let budget = try #require(vector["budget"] as? [String: Any])
        #expect(budget["bytes"] as? Int == cbor.count, "\(name): size")
        #expect((budget["qrVersion"] as? Int) == Budget(card: card).version, "\(name): version")
    }
}

@Test func signedVectorsUseTheDocumentedSeed() throws {
    let vectors = try loadVectors()
    let identity = try Identity(seed: (0..<32).map { UInt8($0) })
    for vector in vectors where vector["keyIndex"] is Int {
        let index = UInt32(vector["keyIndex"] as! Int)
        let card = try HB1.decode(cbor: bytes(vector["cbor"] as! String))
        let expected = identity.personaSigningKey(index: index).publicKey.rawRepresentation.map { $0 }
        #expect(card.publicKey == expected, "\(vector["name"]!): persona key \(index)")
        if card.flags.contains(.compact) {
            #expect(card.keyFingerprint == Card.keyFingerprint(for: expected))
        }
    }
    let compact = try #require(vectors.first { $0["name"] as? String == "compact-name-only" })
    let card = try HB1.decode(cbor: bytes(compact["cbor"] as! String))
    #expect(card.keyFingerprint == Card.keyFingerprint(for: identity.personaSigningKey(index: 1).publicKey.rawRepresentation.map { $0 }))
}

@Test func tamperedVectorDoesNotVerify() throws {
    let vectors = try loadVectors()
    let tampered = try #require(vectors.first { $0["name"] as? String == "tampered-signature" })
    #expect(tampered["valid"] as? Bool == false)
    let card = try HB1.decode(cbor: bytes(tampered["cbor"] as! String))
    #expect(!card.signatureIsValid)
}
