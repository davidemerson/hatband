import Testing
@testable import HatbandCore

private func profile() -> Profile {
    var p = Profile()
    p.name = "Leopold Bloom"
    p.company = "Freeman's Journal"
    p.phone = "+353871234567"
    p.email = "bloom@example.ie"
    p.website = Website(address: "nnix.com")
    p.mastodon = "bloom@merveilles.town"
    p.ssh = SSHKeyField(kind: 1, bytes: [UInt8](repeating: 1, count: 32))
    p.gpgFingerprint = [UInt8](repeating: 2, count: 20)
    p.gpgKey = [UInt8](repeating: 3, count: 500)
    p.photo = [UInt8](repeating: 4, count: 100)
    p.custom = [CustomField(label: "Pub", value: "Davy Byrne's"), CustomField(label: "Matrix", value: "@b:x", kind: .url)]
    return p
}

private let work = Persona(id: [1, 1, 1, 1, 1, 1, 1, 1], label: "Work", keyIndex: 0, color: 2,
                           channels: [.email, .website, .ssh, .gpgFingerprint], customLabels: ["Matrix"],
                           lockScreenChannels: [.email, .mastodon, .phone], seq: 3)

@Test func lockScreenTierIsCompactAndMinimal() {
    let card = CardBuilder.card(profile: profile(), persona: work, form: .lockScreen, issuedDay: 10)
    #expect(card.isCompact)
    #expect(card.name == "Leopold Bloom")
    #expect(card.company == nil)
    #expect(card.email == "bloom@example.ie")
    #expect(card.mastodon == "bloom@merveilles.town")
    #expect(card.phone == nil, "a third lock screen channel is dropped")
    #expect(card.ssh == nil)
    #expect(card.custom.isEmpty)
    #expect(card.photo == nil && card.gpgKey == nil)
    #expect(!card.flags.contains(.photoAvailable))
    #expect(card.color == 2 && card.seq == 3 && card.personaID == work.id && card.issuedDay == 10)
}

@Test func nameOnlyPersonaStaysUnder50Bytes() {
    let persona = Persona(id: work.id, label: "Work", keyIndex: 0, color: 9)
    let card = CardBuilder.card(profile: profile(), persona: persona, form: .lockScreen, issuedDay: 2438)
    #expect(HB1.encodedSize(of: card) < 50)
}

@Test func fullQRFollowsPersonaChoicesAndDropsHeavyFields() {
    let card = CardBuilder.card(profile: profile(), persona: work, form: .fullQR, issuedDay: 10)
    #expect(!card.isCompact)
    #expect(card.company == "Freeman's Journal")
    #expect(card.email != nil && card.website != nil && card.ssh != nil && card.gpgFingerprint != nil)
    #expect(card.phone == nil && card.mastodon == nil, "channels not in the persona are absent")
    #expect(card.custom.map(\.label) == ["Matrix"])
    #expect(card.flags.contains(.photoAvailable))
    #expect(card.photo == nil && card.gpgKey == nil)
}

@Test func fileFormCarriesHeavyFields() {
    let card = CardBuilder.card(profile: profile(), persona: work, form: .file, issuedDay: 10)
    #expect(card.photo?.count == 100)
    #expect(card.gpgKey?.count == 500)
    #expect(card.flags.contains(.photoAvailable))
    var noPhoto = work
    noPhoto.includePhoto = false
    let stripped = CardBuilder.card(profile: profile(), persona: noPhoto, form: .file, issuedDay: 10)
    #expect(stripped.photo == nil && !stripped.flags.contains(.photoAvailable))
}

@Test func aliasPersonaUsesOnlyItsOwnProfile() {
    var flower = Profile()
    flower.name = "Henry Flower"
    flower.email = "henry@flower.ie"
    let alias = Persona(id: [9, 9, 9, 9, 9, 9, 9, 9], label: "Henry Flower", keyIndex: 3, aliasProfile: flower)
    for form in CardForm.allCases {
        let card = CardBuilder.card(profile: profile(), persona: alias, form: form, issuedDay: 1)
        #expect(card.flags.contains(.alias))
        #expect(card.name == "Henry Flower")
        #expect(card.phone == nil && card.company == nil && card.ssh == nil)
        #expect(card.email == (form == .lockScreen ? nil : "henry@flower.ie"))
    }
}

@Test func displayNameOverrides() {
    var p = work
    p.displayName = "L. Bloom"
    #expect(CardBuilder.card(profile: profile(), persona: p, form: .fullQR, issuedDay: 1).name == "L. Bloom")
}

@Test func presentChannels() {
    #expect(profile().presentChannels == [.phone, .email, .website, .mastodon, .ssh, .gpgFingerprint])
    #expect(Profile().presentChannels.isEmpty)
}

@Test func paletteIndexIsSafe() {
    #expect(Palette.colors.count == 10)
    #expect(Palette.color(at: 255).name == "ink")
    #expect(Palette.color(at: 1).name == "dark blue")
    #expect(Set(Palette.colors.map(\.name)).count == Palette.colors.count)
    for c in Palette.colors {
        #expect(c.light.count == 7 && c.dark.count == 7 && c.light.hasPrefix("#"))
    }
}

@Test(arguments: [
    (2020, 1, 1, 0), (2020, 1, 2, 1), (2020, 3, 1, 60), (2021, 1, 1, 366),
    (2026, 9, 4, 2438), (2019, 12, 31, -1), (2100, 3, 1, 29279), (2000, 2, 29, -7246),
])
func dayNumbers(year: Int, month: Int, day: Int, number: Int) {
    #expect(Day.number(year: year, month: month, day: day) == number)
    let civil = Day.civil(number)
    #expect(civil.year == year && civil.month == month && civil.day == day)
}

@Test func dayNumbersAreContiguous() {
    var previous = Day.civil(-1000)
    for n in -999...5000 {
        let c = Day.civil(n)
        #expect(Day.number(year: c.year, month: c.month, day: c.day) == n)
        #expect(c != previous)
        previous = c
    }
}
