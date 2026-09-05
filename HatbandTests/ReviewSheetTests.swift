import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// The review sheet's choice for a newer card from someone known: replace
/// the stored card (the default) or keep it and add the meeting alone.
/// Both paths run through `AppModel.save`.
@MainActor struct ReviewSheetTests {
    private let issuedDay: UInt32 = 2438

    private func onboarded(name: String, email: String) async throws -> AppModel {
        var profile = Profile()
        profile.name = name
        profile.email = email
        profile.company = "Freeman's Journal"
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: profile, appLock: false)
        return model
    }

    private func signedURL(from sharer: AppModel) throws -> String {
        let persona = try #require(sharer.personas.first)
        let card = CardBuilder.card(profile: sharer.profile, persona: persona, form: .fullQR, issuedDay: issuedDay)
        let key = try sharer.identity().personaSigningKey(index: persona.keyIndex)
        return HB1.url(for: try card.signed(with: key))
    }

    /// A scanner that knows the sharer at `seq` 1, with the sharer's
    /// newer card (`seq` 2, another email) pending review.
    private func knownWithNewerCard() async throws -> (scanner: AppModel, review: Review, url: String) {
        let sharer = try await onboarded(name: "Leopold Bloom", email: "bloom@example.ie")
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        try scanner.receive(text: try signedURL(from: sharer), source: .scan)
        try await scanner.save(try #require(scanner.pendingReview), fix: nil, label: "Dublin", note: "", tags: ["pub"])
        sharer.personas[0].seq = 2
        sharer.profile.email = "leopold@example.ie"
        let url = try signedURL(from: sharer)
        try scanner.receive(text: url, source: .link)
        let review = try #require(scanner.pendingReview)
        guard case .update = review.outcome else {
            Issue.record("expected .update, got \(review.outcome)")
            throw AppError.storage("no update")
        }
        return (scanner, review, url)
    }

    @Test func offeredOnlyForAnUpdate() throws {
        #expect(ReviewSheet.offersMeetingOnly(.update([])))
        #expect(!ReviewSheet.offersMeetingOnly(.new))
        #expect(!ReviewSheet.offersMeetingOnly(.encounterOnly))
        #expect(!ReviewSheet.offersMeetingOnly(.keyChanged))
        #expect(!ReviewSheet.offersMeetingOnly(.rejected("no")))
        #expect(Review.make(card: try Vectors.card("typical-signed"), source: .scan, people: []).updateCard)
    }

    @Test func updateCardIsTheDefaultAndReplacesTheStoredCard() async throws {
        let (scanner, review, _) = try await knownWithNewerCard()
        #expect(review.updateCard)
        try await scanner.save(review, fix: nil, label: "Again", note: "", tags: [])
        #expect(scanner.people.count == 1)
        let person = try #require(scanner.people.first)
        #expect(person.card.seq == 2)
        #expect(person.card.email == "leopold@example.ie")
        #expect(person.source == .link)
        #expect(person.encounters.count == 2)
        #expect(person.encounters.last?.label == "Again")
    }

    @Test func addMeetingOnlyKeepsTheStoredCard() async throws {
        let (scanner, review, url) = try await knownWithNewerCard()
        let before = try #require(scanner.people.first)
        var meetingOnly = review
        meetingOnly.updateCard = false
        let fix = Fix(latitude: 53.35, longitude: -6.26, accuracy: 4000)
        try await scanner.save(meetingOnly, fix: fix, label: "Again", note: "Later", tags: ["conference"])
        #expect(scanner.people.count == 1)
        let person = try #require(scanner.people.first)
        #expect(person.card == before.card)
        #expect(person.cardBytes == before.cardBytes)
        #expect(person.card.seq == 1)
        #expect(person.card.email == "bloom@example.ie")
        #expect(person.publicKey == before.publicKey)
        #expect(person.trust == .inPerson)
        #expect(person.source == .scan)
        #expect(person.encounters.count == 2)
        #expect(person.encounters.last?.label == "Again")
        #expect(person.encounters.last?.note == "Later")
        #expect(person.encounters.last?.fix == fix)
        #expect(person.tags == ["pub", "conference"])
        #expect(person.updatedAt >= before.updatedAt)
        #expect(scanner.pendingReview == nil)
        #expect(scanner.route.tab == .card)

        // Sealed to the store, and the newer card is still an update next time.
        let record = try #require(try scanner.store?.person(id: Data(person.personaID)))
        let key = try #require(scanner.dbKey)
        let aad = Sealer.aad(domain: Sealer.personDomain, id: Data(person.personaID))
        #expect(try PersonCodec.decode(try Sealer.open(record.sealed, key: key, aad: aad)) == person)
        try scanner.receive(text: url, source: .link)
        let again = try #require(scanner.pendingReview)
        guard case .update = again.outcome else {
            Issue.record("expected .update, got \(again.outcome)")
            return
        }
        #expect(again.updateCard)
    }

    /// The flag means nothing outside `.update`: a stranger is saved whole,
    /// a re-scan adds its meeting, and an accepted new key still replaces
    /// the card.
    @Test func flagIgnoredForOtherOutcomes() async throws {
        let sharer = try await onboarded(name: "Leopold Bloom", email: "bloom@example.ie")
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        let url = try signedURL(from: sharer)
        try scanner.receive(text: url, source: .scan)
        var fresh = try #require(scanner.pendingReview)
        #expect(fresh.outcome == .new)
        fresh.updateCard = false
        try await scanner.save(fresh, fix: nil, label: "", note: "", tags: [])
        #expect(scanner.people.first?.card.email == "bloom@example.ie")
        #expect(scanner.people.first?.encounters.count == 1)

        try scanner.receive(text: url, source: .scan)
        var same = try #require(scanner.pendingReview)
        #expect(same.outcome == .encounterOnly)
        same.updateCard = false
        try await scanner.save(same, fix: nil, label: "", note: "", tags: [])
        #expect(scanner.people.first?.encounters.count == 2)

        let card = try Vectors.card("typical-signed")
        let existing = pinnedPerson(card)
        var other = card
        other.seq = 9
        let stranger = try other.signed(with: try Identity(seed: Vectors.seed).personaSigningKey(index: 7))
        var review = Review.make(card: stranger, source: .scan, people: [existing])
        #expect(review.outcome == .keyChanged)
        review.updateCard = false
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let accepted = Merge.apply(existing: existing, review: review, fix: nil, label: "", note: "", tags: [],
                                   acceptNewKey: true, now: now)
        #expect(accepted.card.seq == 9)
        #expect(accepted.publicKey == stranger.publicKey)
        let kept = Merge.apply(existing: existing, review: review, fix: nil, label: "", note: "", tags: [],
                               acceptNewKey: false, now: now)
        #expect(kept.card == card)
    }

    /// `Merge.apply` itself honours the flag for `.update`.
    @Test func mergeApplyKeepsTheCardWhenAsked() throws {
        let card = try Vectors.card("typical-signed")
        let existing = pinnedPerson(card)
        var newer = card
        newer.seq = 2
        newer.company = "Evening Telegraph"
        let incoming = try newer.signed(with: try Identity(seed: Vectors.seed).personaSigningKey(index: 1))
        var review = Review.make(card: incoming, source: .link, people: [existing])
        guard case .update = review.outcome else {
            Issue.record("expected .update, got \(review.outcome)")
            return
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let replaced = Merge.apply(existing: existing, review: review, fix: nil, label: "", note: "", tags: [],
                                   acceptNewKey: false, now: now)
        #expect(replaced.card.company == "Evening Telegraph")
        #expect(replaced.card.seq == 2)
        #expect(replaced.source == .link)
        review.updateCard = false
        let kept = Merge.apply(existing: existing, review: review, fix: nil, label: "", note: "", tags: [],
                               acceptNewKey: false, now: now)
        #expect(kept.card == card)
        #expect(kept.cardBytes == existing.cardBytes)
        #expect(kept.source == .scan)
        #expect(kept.encounters.count == 1)
        #expect(kept.updatedAt == now)
    }
}
