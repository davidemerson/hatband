import Testing
@testable import HatbandCore

private let id: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]

private func compact(name: String, email: String? = nil, mastodon: String? = nil) -> Card {
    var card = Card(personaID: id, issuedDay: 2438)
    card.flags.insert(.compact)
    card.name = name
    card.email = email
    card.mastodon = mastodon
    card.keyFingerprint = [9, 9, 9, 9, 9, 9, 9, 9]
    card.color = 3
    return card
}

@Test func nameOnlyCompactCardIsAVersionSixSymbol() {
    let budget = Budget(card: compact(name: "Leopold Bloom"))
    #expect(budget.bytes < 50)
    #expect(budget.version != nil && budget.version! <= 6)
    #expect(budget.fitsLockScreen && budget.fitsFullQR)
}

@Test func twoChannelsStayOnTheLockScreen() {
    let budget = Budget(card: compact(name: "Leopold Paula Bloom", email: "henry.flower@example.ie", mastodon: "bloom@merveilles.town"))
    #expect(budget.version != nil && budget.version! <= Budget.lockScreenMaxVersion)
    #expect(budget.fitsLockScreen)
}

@Test func signedFullCardLeavesTheLockScreenButFitsTheApp() {
    var card = Card(personaID: id, issuedDay: 2438)
    card.name = "Leopold Bloom"
    card.company = "Freeman's Journal"
    card.phone = "+353871234567"
    card.email = "henry.flower@example.ie"
    card.website = Website(address: "nnix.com")
    card.github = "lbloom"
    card.mastodon = "bloom@merveilles.town"
    card.ssh = SSHKeyField(kind: 1, bytes: [UInt8](repeating: 9, count: 32))
    card.gpgFingerprint = [UInt8](repeating: 0xab, count: 20)
    card.publicKey = [UInt8](repeating: 2, count: 32)
    card.signature = [UInt8](repeating: 3, count: 64)
    let budget = Budget(card: card)
    #expect(budget.bytes > 200)
    #expect(!budget.fitsLockScreen)
    #expect(budget.fitsFullQR)
    #expect(budget.version! <= 16)
}

@Test func oversizeCardHasNoVersion() {
    var card = Card(personaID: id, issuedDay: 0)
    card.custom = (0..<20).map { CustomField(label: "f\($0)", value: String(repeating: "x", count: 120)) }
    let budget = Budget(card: card)
    #expect(budget.version == nil)
    #expect(!budget.fitsLockScreen && !budget.fitsFullQR)
}

@Test func qrCodesRespectTheirTier() throws {
    let small = compact(name: "Henry Flower")
    let lock = try #require(try Budget.qrCode(for: small, form: .lockScreen))
    #expect(lock.version <= Budget.lockScreenMaxVersion)
    #expect(lock.errorCorrection != .low, "boost never drops below medium")
    var big = Card(personaID: id, issuedDay: 0)
    big.custom = (0..<8).map { CustomField(label: "f\($0)", value: String(repeating: "y", count: 60)) }
    #expect(try Budget.qrCode(for: big, form: .lockScreen) == nil)
    #expect(try Budget.qrCode(for: big, form: .fullQR) != nil)
    #expect(try Budget.qrCode(for: big, form: .file) == nil)
}

@Test func urlCharactersAreQRAlphanumericAfterThePrefix() {
    let url = HB1.url(for: compact(name: "Bloom"))
    let segments = QRSegment.segments(forURL: url)
    #expect(segments.count == 2)
}
