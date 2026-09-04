import Testing
@testable import HatbandCore

private let personaID: [UInt8] = [8, 7, 6, 5, 4, 3, 2, 1]

private func card() -> Card {
    var c = Card(personaID: personaID, issuedDay: 2438)
    c.name = "Henry Flower"
    c.email = "henry@flower.ie"
    c.color = 1
    return c
}

@Test func urlFormIsPrefixedTaggedBase32() throws {
    let url = HB1.url(for: card())
    #expect(url.hasPrefix("https://hatband.link/#1"))
    let fragment = url.dropFirst("https://hatband.link/#1".count)
    #expect(fragment.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0) })
    #expect(try HB1.decode(url: url) == card())
}

@Test(arguments: [
    "HTTPS://HATBAND.LINK/#",
    "https://Hatband.Link/#",
    "  https://hatband.link/#",
    "#",
    "",
])
func decodesUrlVariants(prefix: String) throws {
    let body = String(HB1.url(for: card()).dropFirst(HB1.urlPrefix.count))
    #expect(try HB1.decode(url: prefix + body + (prefix.hasPrefix(" ") ? " " : "")) == card())
    #expect(try HB1.decode(url: prefix + body.lowercased()) == card())
}

@Test func rejectsForeignAndFutureForms() {
    let body = String(HB1.url(for: card()).dropFirst(HB1.urlPrefix.count))
    #expect(throws: HB1.Error.notHatband) { try HB1.decode(url: "https://example.com/#" + body) }
    #expect(throws: HB1.Error.notHatband) { try HB1.decode(url: "https://hatband.link/card#" + body) }
    #expect(throws: HB1.Error.notHatband) { try HB1.decode(url: "http://hatband.link/#" + body) }
    #expect(throws: HB1.Error.unsupportedFormat("9")) { try HB1.decode(url: "https://hatband.link/#9" + body.dropFirst()) }
    #expect(throws: HB1.Error.notHatband) { try HB1.decode(url: "https://hatband.link/#") }
    #expect(throws: HB1.Error.notHatband) { try HB1.decode(url: "https://hatband.link/#1!!" ) }
    #expect(throws: HB1.Error.notHatband) { try HB1.decode(url: "BEGIN:VCARD") }
}

@Test func fileFormHasMagic() throws {
    let bytes = HB1.fileBytes(for: card())
    #expect(Array(bytes.prefix(4)) == [0x48, 0x42, 0x31, 0x00])
    #expect(try HB1.decode(file: bytes) == card())
    #expect(throws: HB1.Error.badMagic) { try HB1.decode(file: Array(bytes.dropFirst())) }
    #expect(throws: HB1.Error.badMagic) { try HB1.decode(file: []) }
}

@Test func enforcesSizeCeiling() {
    var big = card()
    big.photo = [UInt8](repeating: 0, count: HB1.maxBytes)
    let bytes = big.cbor.encoded
    #expect(throws: HB1.Error.tooLarge(bytes.count)) { try HB1.decode(cbor: bytes) }
    #expect(throws: HB1.Error.tooLarge(bytes.count)) { try HB1.decode(file: HB1.fileMagic + bytes) }
}

@Test func cborErrorsSurface() {
    #expect(throws: CBORError.self) { try HB1.decode(cbor: [0xff]) }
    #expect(throws: CardError.notAMap) { try HB1.decode(cbor: [0x00]) }
}

@Test func encodedSizeMatchesCBOR() {
    #expect(HB1.encodedSize(of: card()) == card().cbor.encoded.count)
    // Typical unsigned name+email card stays well inside the compact budget.
    #expect(HB1.encodedSize(of: card()) < 60)
}
