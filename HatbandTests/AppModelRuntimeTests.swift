import Foundation
import HatbandCore
import Testing
import UIKit
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

    // MARK: - Lifecycle

    /// Two `.active` phases before the first has settled, as a cold launch
    /// under a system prompt produces, share one load: one store is made.
    @Test func overlappingActivationsLoadOnce() async throws {
        var stores = 0
        let model = AppModel(keys: MemoryKeyStore(), makeStore: {
            stores += 1
            return try Store.inMemory()
        })
        model.protectedDataAvailable = { false }
        let first = Task { await model.activate() }
        let second = Task { await model.activate() }
        var spins = 0
        while model.phase != .protectedDataUnavailable, spins < 1000 {
            await Task.yield()
            spins += 1
        }
        #expect(model.phase == .protectedDataUnavailable)
        model.protectedDataAvailable = { true }
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        await first.value
        await second.value
        #expect(stores == 1)
        #expect(model.phase == .onboarding)
        #expect(model.store != nil)
        // With the store open, a later activation reconciles and loads no more.
        await model.activate()
        #expect(stores == 1)
        #expect(model.phase == .onboarding)
    }

    /// Two unlocks while the prompt is up share it: one prompt, one answer.
    @Test func overlappingUnlocksShareOnePrompt() async throws {
        let model = try await onboarded(appLock: true)
        let keys = try #require(model.keys as? MemoryKeyStore)
        model.lock()
        keys.readDelay = .milliseconds(50)
        let first = Task { await model.unlock() }
        let second = Task { await model.unlock() }
        let results = await [first.value, second.value]
        #expect(results == [true, true])
        #expect(keys.prompts == ["Unlock the people you have scanned."])
        #expect(!model.locked)
        #expect(model.dbKey != nil)
    }

    /// The forget buffer holds a decrypted person; the lock empties it,
    /// and the forget stands. Without app lock there is nothing to empty.
    @Test func lockDropsTheUndoBuffer() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", appLock: true)
        scanner.undoWindow = .seconds(5)
        let person = try await scanAndSave(scanner, try signedLink(from: sharer))
        try scanner.forget(person)
        #expect(scanner.undo == person)
        scanner.lock()
        #expect(scanner.undo == nil)
        #expect(scanner.people.isEmpty)
        try scanner.restoreForgotten()
        #expect(scanner.undo == nil)
        #expect(await scanner.unlock())
        #expect(scanner.people.isEmpty)
        #expect(try scanner.store?.people().isEmpty == true)

        let open = try await onboarded(name: "Molly")
        open.undoWindow = .seconds(5)
        let other = try await scanAndSave(open, try signedLink(from: sharer))
        try open.forget(other)
        open.lock()
        #expect(!open.locked)
        #expect(open.undo == other)
    }

    /// The identity is read once, at load, never through a prompt, and is
    /// in hand before `.ready`; building a card reads nothing more.
    @Test func identityIsReadAtLoadWithoutAPrompt() async throws {
        let model = try await onboarded(appLock: true)
        let keys = try #require(model.keys as? MemoryKeyStore)
        var reads: [String] = []
        keys.onEvent = { event in
            if event.hasPrefix("read ") {
                reads.append(event)
            }
        }
        let again = try relaunched(model)
        #expect(throws: AppError.self) {
            try again.identity()
        }
        await again.load()
        #expect(again.phase == .ready)
        #expect(try again.identity() == model.identity())
        #expect(reads == ["read seed", "read persona-index"])
        #expect(keys.prompts.isEmpty)
        let persona = try #require(again.personas.first)
        #expect(try again.card(for: persona, form: .fullQR).signatureIsValid)
        #expect(reads.count == 2)
    }

    /// A seed the Keychain would not give at load is said on the Card tab,
    /// not as an alert, and read again at the next activation.
    @Test func failedSeedReadIsRetriedOnActivation() async throws {
        let model = try await onboarded(appLock: true)
        let keys = try #require(model.keys as? MemoryKeyStore)
        let again = try relaunched(model)
        keys.failNextRead = .notAvailable
        await again.load()
        #expect(again.phase == .ready)
        #expect(again.error == nil)
        #expect(throws: AppError.storage("No identity")) {
            try again.identity()
        }
        await again.activate()
        #expect(try again.identity() == model.identity())
    }

    /// A counter the Keychain would not give is never guessed: adding a
    /// persona waits for a read that succeeds, so no index is reused.
    @Test func unreadPersonaCounterRefusesToAllot() async throws {
        let model = try await onboarded()
        _ = try model.addPersona(label: "Work", alias: false)
        let keys = try #require(model.keys as? MemoryKeyStore)
        #expect(keys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 2]))
        let again = try relaunched(model)
        keys.onEvent = { event in
            if event == "read persona-index" {
                keys.failNextRead = .notAvailable
            }
        }
        await again.load()
        keys.onEvent = nil
        #expect(again.phase == .ready)
        #expect(!again.locked)
        #expect(!again.personaIndexKnown)
        #expect(throws: AppError.self) {
            try again.addPersona(label: "Club", alias: false)
        }
        #expect(again.personas.count == 2)
        await again.activate()
        #expect(again.personaIndexKnown)
        #expect(again.personaIndexCounter == 2)
        #expect(try again.addPersona(label: "Club", alias: false).keyIndex == 2)
        #expect(keys.items[KeyName.personaIndex]?.data == Data([0, 0, 0, 3]))
    }

    /// A Keychain write that fails leaves the key and the setting as they
    /// were, on this launch and the next.
    @Test func failedKeyRewriteChangesNothing() async throws {
        let model = try await onboarded(appLock: true)
        let keys = try #require(model.keys as? MemoryKeyStore)
        let before = try #require(keys.items[KeyName.database])
        keys.failNextWrite = .failed(-25299)
        await #expect(throws: AppError.keychain(-25299)) {
            try await model.setAppLock(false)
        }
        #expect(keys.items[KeyName.database]?.data == before.data)
        #expect(keys.items[KeyName.database]?.access == before.access)
        #expect(model.settings.appLock)
        let again = try relaunched(model)
        await again.load()
        #expect(again.settings.appLock)
        #expect(again.locked)
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
