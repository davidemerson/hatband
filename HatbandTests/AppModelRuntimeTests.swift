import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// Runtime paths the simulator suite did not reach: an open that lands
/// before the model is ready, the undo timer across a repeat forget, a
/// running Lock Screen session after a settings change, and `Fix` on
/// input that is not a place.
@MainActor struct AppModelRuntimeTests {
    private let issuedDay: UInt32 = 2438

    private func sampleProfile(name: String = "Leopold Bloom") -> Profile {
        var profile = Profile()
        profile.name = name
        profile.email = "bloom@example.ie"
        return profile
    }

    private func onboarded(name: String = "Leopold Bloom", appLock: Bool = false) async throws -> AppModel {
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: sampleProfile(name: name), appLock: appLock)
        return model
    }

    /// A second model over the same store and keys, not yet loaded: the
    /// state of a cold launch.
    private func relaunched(_ model: AppModel) throws -> AppModel {
        let store = try #require(model.store)
        let again = AppModel(keys: model.keys, makeStore: { store })
        again.protectedDataAvailable = { true }
        return again
    }

    private func signedLink(from sharer: AppModel) throws -> URL {
        let persona = try #require(sharer.personas.first)
        let card = CardBuilder.card(profile: sharer.profile, persona: persona, form: .fullQR, issuedDay: issuedDay)
        let key = try sharer.identity().personaSigningKey(index: persona.keyIndex)
        return try #require(URL(string: HB1.url(for: try card.signed(with: key))))
    }

    @discardableResult
    private func scanAndSave(_ scanner: AppModel, _ url: URL) async throws -> Person {
        try scanner.receive(text: url.absoluteString, source: .scan)
        let review = try #require(scanner.pendingReview)
        try await scanner.save(review, fix: nil, label: "", note: "", tags: [])
        return try #require(scanner.people.first)
    }

    // MARK: - Opens that arrive before the model is ready

    @Test func cardLinkBeforeLoadWaitsUntilOnboardingIsDone() async throws {
        let sharer = try await onboarded()
        let link = try signedLink(from: sharer)
        let fresh = try AppModel.inMemory()
        #expect(fresh.phase == .loading)
        fresh.handle(url: link)
        #expect(fresh.pendingReview == nil)
        #expect(fresh.error == nil)
        #expect(fresh.deferredOpen != nil)

        await fresh.load()
        #expect(fresh.phase == .onboarding)
        #expect(fresh.pendingReview == nil, "nothing to save into during onboarding")

        try fresh.finishOnboarding(profile: sampleProfile(name: "Henry Flower"), appLock: false)
        let review = try #require(fresh.pendingReview)
        #expect(review.source == .link)
        #expect(review.card.name == "Leopold Bloom")
        #expect(review.outcome == .new)
        #expect(fresh.deferredOpen == nil)
    }

    @Test func cardLinkBeforeLoadShowsOnceLoaded() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower")
        let again = try relaunched(scanner)
        again.handle(url: try signedLink(from: sharer))
        #expect(again.pendingReview == nil)
        await again.load()
        #expect(again.phase == .ready)
        #expect(again.pendingReview?.card.name == "Leopold Bloom")
        #expect(again.deferredOpen == nil)
    }

    @Test func showSchemeBeforeLoadSelectsThatPersonaAfterLoad() async throws {
        let model = try await onboarded()
        let personal = try #require(model.personas.first)
        let work = try model.addPersona(label: "Work", alias: false)
        model.select(personal)
        #expect(model.selectedPersonaID == personal.id)

        // The Live Activity tap on a cold launch: the URL lands before the
        // owner is read.
        let again = try relaunched(model)
        again.route.tab = .settings
        again.handle(url: try #require(URL(string: "hatband://show?persona=" + Hex.string(work.id))))
        #expect(again.selectedPersonaID == nil)
        await again.load()
        #expect(again.selectedPersonaID == work.id)
        #expect(again.route.tab == .card)
        #expect(again.route.sheet == nil)
        #expect(again.deferredOpen == nil)

        let third = try relaunched(again)
        third.handle(url: try #require(URL(string: "hatband://scan")))
        #expect(third.route.sheet == nil)
        await third.load()
        #expect(third.route.tab == .card)
        #expect(third.route.sheet == .scan)
    }

    @Test func exportBeforeLoadImportsAtOnboarding() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Open-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("backup.hatband-export")
        try Data([1, 2, 3]).write(to: file)

        let fresh = try AppModel.inMemory()
        fresh.handle(url: file)
        #expect(fresh.pendingImport == nil)
        #expect(fresh.error == nil)
        await fresh.load()
        #expect(fresh.phase == .onboarding)
        #expect(fresh.pendingImport == Data([1, 2, 3]), "a restore is exactly what onboarding is for")
        #expect(fresh.deferredOpen == nil)
    }

    @Test func malformedOpenIsReportedAtOnce() async throws {
        let fresh = try AppModel.inMemory()
        fresh.handle(url: try #require(URL(string: "https://example.org/nothing")))
        #expect(fresh.error == .notHatband)
        #expect(fresh.deferredOpen == nil)
    }

    @Test func laterOpenReplacesEarlierAndEraseDropsIt() async throws {
        let sharer = try await onboarded()
        let other = try await onboarded(name: "Molly")
        let fresh = try AppModel.inMemory()
        fresh.handle(url: try signedLink(from: sharer))
        fresh.handle(url: try signedLink(from: other))
        guard case .card(let card, let source)? = fresh.deferredOpen else {
            Issue.record("expected a deferred card, got \(String(describing: fresh.deferredOpen))")
            return
        }
        #expect(card.name == "Molly")
        #expect(source == .link)

        let model = try await onboarded()
        model.deferredOpen = fresh.deferredOpen
        await model.eraseEverything()
        #expect(model.deferredOpen == nil)
        #expect(model.pendingReview == nil)
    }

    // MARK: - Undo

    @Test func forgetAgainAfterRestoreKeepsFullWindow() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower")
        scanner.undoWindow = .milliseconds(1_000)
        let person = try await scanAndSave(scanner, try signedLink(from: sharer))

        try scanner.forget(person)
        try await Task.sleep(for: .milliseconds(400))
        try scanner.restoreForgotten()
        #expect(scanner.people == [person])
        try scanner.forget(person)
        #expect(scanner.undo == person)

        // About 1.1 s in: the first forget's timer (1.0 s) has fired, the
        // second window (ends about 1.4 s) has not.
        try await Task.sleep(for: .milliseconds(700))
        #expect(scanner.undo == person, "a repeat forget keeps its own full window")
        try scanner.restoreForgotten()
        #expect(scanner.people == [person])
        #expect(try scanner.store?.people().count == 1)

        try scanner.forget(person)
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(scanner.undo == nil)
        #expect(scanner.people.isEmpty)
    }

    // MARK: - Sharing

    @Test func updateSharingActivityWithoutActivityIsANoOp() async throws {
        let model = try await onboarded()
        let persona = try #require(model.personas.first)
        await model.updateSharingActivity()
        #expect(model.sharing == nil)
        model.sharing = AppModel.Sharing(personaID: persona.id, endsAt: Date().addingTimeInterval(600))
        model.settings.showNameOnLockScreen = false
        await model.updateSharingActivity()
        #expect(model.sharing?.personaID == persona.id)
        #expect(model.error == nil)
        // The content a refreshed activity would carry follows the setting.
        let content = try model.sharingContent(for: persona, minutes: 30, now: Date())
        #expect(content.state.name == nil)
    }
}

/// `Fix` never traps, whatever CoreLocation or a decoded record hands it.
struct FixClampTests {
    @Test func nonFiniteInputCountsAsZero() {
        let fix = Fix(latitude: .nan, longitude: .infinity, accuracy: -.infinity)
        #expect(fix.latitudeHundredths == 0)
        #expect(fix.longitudeHundredths == 0)
        #expect(fix.accuracyMetres == 0)
    }

    @Test func outOfRangeInputClamps() {
        let fix = Fix(latitude: 1e300, longitude: -1e300, accuracy: 1e300)
        #expect(fix.latitudeHundredths == 9000)
        #expect(fix.longitudeHundredths == -18000)
        #expect(fix.accuracyMetres == Int(Fix.maxAccuracyMetres))
        let negative = Fix(latitude: -91, longitude: 181, accuracy: -5)
        #expect(negative.latitudeHundredths == -9000)
        #expect(negative.longitudeHundredths == 18000)
        #expect(negative.accuracyMetres == 0)
        let ordinary = Fix(latitude: 53.3498, longitude: -6.2603, accuracy: 4321.4)
        #expect(ordinary.latitudeHundredths == 5335)
        #expect(ordinary.longitudeHundredths == -626)
        #expect(ordinary.accuracyMetres == 4321)
    }

    /// A person body whose encounter carries `Int.max` hundredths, as a
    /// damaged or hostile export could: decoding must not trap.
    @Test func personCodecSurvivesExtremeHundredths() throws {
        let cardBytes = try Vectors.cbor("typical-signed")
        let encounter: CBOR = .map([
            .unsigned(0): .bytes(PersonCodec.uuidBytes(UUID())),
            .unsigned(1): .unsigned(1_700_000_000),
            .unsigned(2): .unsigned(UInt64(Int.max)),
            .unsigned(3): .negative(UInt64(Int.max)),
            .unsigned(4): .unsigned(UInt64.max),
            .unsigned(5): .text("Nowhere"),
            .unsigned(6): .text(""),
        ])
        let body: CBOR = .map([
            .unsigned(0): .unsigned(PersonCodec.version),
            .unsigned(1): .bytes(cardBytes),
            .unsigned(4): .unsigned(0),
            .unsigned(6): .array([]),
            .unsigned(7): .text(""),
            .unsigned(9): .unsigned(1_700_000_000),
            .unsigned(10): .unsigned(1_700_000_000),
            .unsigned(11): .unsigned(0),
            .unsigned(12): .array([encounter]),
        ])
        let person = try PersonCodec.decode(body.encoded)
        let fix = try #require(person.encounters.first?.fix)
        #expect(fix.latitudeHundredths == 9000)
        #expect(fix.longitudeHundredths == -18000)
        #expect(fix.accuracyMetres == 0, "UInt64.max is not an Int, so the accuracy reads as unknown")
        #expect(try PersonCodec.decode(PersonCodec.encode(person)) == person)
    }
}
