import CryptoKit
import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// Two phones: a sharer whose card is built with `CardBuilder` and signed
/// with `identity()`, and a scanner that receives it.
@MainActor struct AppModelPeopleTests {
    private let prompt = "Unlock the people you have scanned."
    private let issuedDay: UInt32 = 2438

    private func profile(name: String, email: String) -> Profile {
        var profile = Profile()
        profile.name = name
        profile.email = email
        profile.phone = "+353871234567"
        profile.company = "Freeman's Journal"
        return profile
    }

    private func onboarded(name: String = "Leopold Bloom", email: String = "bloom@example.ie",
                           appLock: Bool = false, mutate: (inout Profile) -> Void = { _ in }) async throws -> AppModel {
        var profile = profile(name: name, email: email)
        mutate(&profile)
        let model = try AppModel.inMemory()
        await model.load()
        try model.finishOnboarding(profile: profile, appLock: appLock)
        return model
    }

    private func keys(of model: AppModel) throws -> MemoryKeyStore {
        try #require(model.keys as? MemoryKeyStore)
    }

    private func signedCard(from sharer: AppModel, form: CardForm = .fullQR, keyIndex: UInt32? = nil) throws -> Card {
        let persona = try #require(sharer.personas.first)
        let card = CardBuilder.card(profile: sharer.profile, persona: persona, form: form, issuedDay: issuedDay)
        let key = try sharer.identity().personaSigningKey(index: keyIndex ?? persona.keyIndex)
        return try card.signed(with: key)
    }

    private func signedURL(from sharer: AppModel, keyIndex: UInt32? = nil) throws -> String {
        HB1.url(for: try signedCard(from: sharer, keyIndex: keyIndex))
    }

    private func compactURL(from sharer: AppModel) throws -> String {
        let persona = try #require(sharer.personas.first)
        let card = CardBuilder.card(profile: sharer.profile, persona: persona, form: .lockScreen, issuedDay: issuedDay)
        let key = try sharer.identity().personaSigningKey(index: persona.keyIndex)
        return HB1.url(for: card.withKeyFingerprint(of: Array(key.publicKey.rawRepresentation)))
    }

    private func sharerPublicKey(_ sharer: AppModel) throws -> [UInt8] {
        let persona = try #require(sharer.personas.first)
        return Array(try sharer.identity().personaSigningKey(index: persona.keyIndex).publicKey.rawRepresentation)
    }

    @discardableResult
    private func scanAndSave(_ scanner: AppModel, _ text: String, source: CardSource = .scan, fix: Fix? = nil,
                             label: String = "", tags: [String] = [], acceptNewKey: Bool = false) async throws -> Review {
        try scanner.receive(text: text, source: source)
        let review = try #require(scanner.pendingReview)
        try await scanner.save(review, fix: fix, label: label, note: "", tags: tags, acceptNewKey: acceptNewKey)
        return review
    }

    // MARK: - Receiving and saving

    @Test func otherPhoneReceivesAndSavesNewPerson() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        scanner.route.tab = .people
        try scanner.receive(text: try signedURL(from: sharer), source: .scan)
        let review = try #require(scanner.pendingReview)
        #expect(review.outcome == .new)
        #expect(review.signature == .valid)
        #expect(review.source == .scan)
        #expect(review.card.name == "Leopold Bloom")
        let fix = Fix(latitude: 53.3498, longitude: -6.2603, accuracy: 4000)
        try await scanner.save(review, fix: fix, label: "Dublin", note: "Davy Byrne's", tags: ["pub"])
        #expect(scanner.people.count == 1)
        let person = try #require(scanner.people.first)
        #expect(person.trust == .inPerson)
        #expect(person.source == .scan)
        #expect(person.publicKey == (try sharerPublicKey(sharer)))
        #expect(person.card.name == "Leopold Bloom")
        #expect(person.card.email == "bloom@example.ie")
        #expect(person.encounters.count == 1)
        #expect(person.encounters.first?.fix == fix)
        #expect(person.encounters.first?.label == "Dublin")
        #expect(person.encounters.first?.note == "Davy Byrne's")
        #expect(person.tags == ["pub"])
        #expect(scanner.route.tab == .card)
        #expect(scanner.pendingReview == nil)
        #expect(try scanner.store?.people().count == 1)
        #expect(try scanner.store?.person(id: Data(person.personaID)) != nil)
    }

    @Test func saveWhileLockedUnlocksFirst() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie", appLock: true)
        scanner.lock()
        #expect(scanner.locked)
        try await scanAndSave(scanner, try signedURL(from: sharer))
        #expect(try keys(of: scanner).prompts.contains(prompt))
        #expect(!scanner.locked)
        #expect(scanner.people.count == 1)
        #expect(try scanner.store?.people().count == 1)
    }

    @Test func rescanSameSeqAddsEncounterOnly() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        let url = try signedURL(from: sharer)
        try await scanAndSave(scanner, url)
        let second = try await scanAndSave(scanner, url, label: "Again")
        #expect(second.outcome == .encounterOnly)
        #expect(scanner.people.count == 1)
        #expect(scanner.people.first?.encounters.count == 2)
        #expect(scanner.people.first?.encounters.last?.label == "Again")
        #expect(try scanner.store?.people().count == 1)
    }

    @Test func higherSeqUpdatesCard() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        try await scanAndSave(scanner, try signedURL(from: sharer))
        sharer.personas[0].seq = 2
        sharer.profile.email = "leopold@example.ie"
        let review = try await scanAndSave(scanner, try signedURL(from: sharer), source: .link)
        guard case .update(let changes) = review.outcome else {
            Issue.record("expected .update, got \(review.outcome)")
            return
        }
        #expect(changes.contains(Merge.Change(label: "Email", old: "bloom@example.ie", new: "leopold@example.ie")))
        #expect(scanner.people.count == 1)
        let person = try #require(scanner.people.first)
        #expect(person.card.email == "leopold@example.ie")
        #expect(person.card.seq == 2)
        #expect(person.encounters.count == 2)
        #expect(person.trust == .inPerson)
        #expect(person.publicKey == (try sharerPublicKey(sharer)))
    }

    @Test func differentKeyIsKeyChangedUntilAccepted() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        try await scanAndSave(scanner, try signedURL(from: sharer))
        let original = try sharerPublicKey(sharer)
        sharer.personas[0].seq = 3
        let stranger = try signedURL(from: sharer, keyIndex: 7)
        let refused = try await scanAndSave(scanner, stranger)
        #expect(refused.outcome == .keyChanged)
        var person = try #require(scanner.people.first)
        #expect(person.publicKey == original)
        #expect(person.trust == .inPerson)
        #expect(person.card.seq == 1)
        #expect(person.encounters.count == 2)

        let accepted = try await scanAndSave(scanner, stranger, acceptNewKey: true)
        #expect(accepted.outcome == .keyChanged)
        person = try #require(scanner.people.first)
        let newKey = try signedCard(from: sharer, keyIndex: 7).publicKey
        #expect(person.publicKey == newKey)
        #expect(person.trust == .keyChanged(previous: original))
        #expect(person.card.seq == 3)
        #expect(scanner.people.count == 1)
    }

    @Test func compactScanOfKnownPersonIsEncounterOnly() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        try await scanAndSave(scanner, try signedURL(from: sharer))
        let review = try await scanAndSave(scanner, try compactURL(from: sharer))
        #expect(review.signature == .compact)
        #expect(review.outcome == .encounterOnly)
        let person = try #require(scanner.people.first)
        #expect(person.encounters.count == 2)
        #expect(!person.card.isCompact)
        #expect(person.card.email == "bloom@example.ie")
    }

    @Test func compactScanOfUnknownPersonPinsFingerprint() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        let review = try await scanAndSave(scanner, try compactURL(from: sharer))
        #expect(review.outcome == .new)
        var person = try #require(scanner.people.first)
        let key = try sharerPublicKey(sharer)
        #expect(person.publicKey == nil)
        #expect(person.keyFingerprint == KeyFingerprint(publicKey: key)?.short)
        #expect(person.card.isCompact)
        #expect(person.trust == .inPerson)

        let full = try await scanAndSave(scanner, try signedURL(from: sharer))
        guard case .update = full.outcome else {
            Issue.record("the full card should replace the Lock Screen one, got \(full.outcome)")
            return
        }
        person = try #require(scanner.people.first)
        #expect(person.publicKey == key)
        #expect(!person.card.isCompact)
        #expect(scanner.people.count == 1)
    }

    @Test func fileBytesKeepPhoto() async throws {
        let photo: [UInt8] = [0xff, 0xd8, 0xff, 0xe0] + (0..<300).map { UInt8($0 & 0xff) } + [0xff, 0xd9]
        let sharer = try await onboarded { $0.photo = photo }
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        let card = try signedCard(from: sharer, form: .file)
        #expect(card.photo == photo)
        try scanner.receive(fileBytes: HB1.fileBytes(for: card))
        let review = try #require(scanner.pendingReview)
        #expect(review.source == .file)
        #expect(review.card.photo == photo)
        #expect(review.items.contains { $0.id == "photo" })
        try await scanner.save(review, fix: nil, label: "", note: "", tags: [])
        let person = try #require(scanner.people.first)
        #expect(person.card.photo == photo)
        #expect(person.trust == .byFile)
        #expect(person.source == .file)
    }

    @Test func garbageThrowsNotHatband() async throws {
        let scanner = try await onboarded()
        #expect(throws: AppError.notHatband) {
            try scanner.receive(text: "hello", source: .scan)
        }
        #expect(throws: AppError.notHatband) {
            try scanner.receive(text: "https://example.org/#1AAAA", source: .link)
        }
        #expect(throws: AppError.notHatband) {
            try scanner.receive(fileBytes: [1, 2, 3])
        }
        #expect(scanner.pendingReview == nil)
    }

    @Test func unsupportedTagThrows() async throws {
        let scanner = try await onboarded()
        #expect(throws: AppError.unsupportedFormat) {
            try scanner.receive(text: "https://hatband.link/#9AAAA", source: .scan)
        }
        #expect(scanner.pendingReview == nil)
    }

    @Test func handleURLRoutesEveryKind() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        let persona = try #require(scanner.personas.first)

        scanner.route.tab = .settings
        scanner.route.sheet = .about
        scanner.handle(url: try #require(URL(string: "hatband://show?persona=" + Hex.string(persona.id))))
        #expect(scanner.route.tab == .card)
        #expect(scanner.route.sheet == nil)
        #expect(scanner.selectedPersonaID == persona.id)
        #expect(scanner.error == nil)

        scanner.route.tab = .people
        scanner.handle(url: try #require(URL(string: "hatband://scan")))
        #expect(scanner.route.tab == .card)
        #expect(scanner.route.sheet == .scan)

        scanner.handle(url: try #require(URL(string: try signedURL(from: sharer))))
        #expect(scanner.pendingReview?.source == .link)
        #expect(scanner.pendingReview?.card.name == "Leopold Bloom")
        scanner.pendingReview = nil

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Handle-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cardFile = directory.appendingPathComponent("bloom.hatband")
        try Data(HB1.fileBytes(for: try signedCard(from: sharer, form: .file))).write(to: cardFile)
        scanner.handle(url: cardFile)
        #expect(scanner.pendingReview?.source == .file)
        #expect(scanner.pendingReview?.card.name == "Leopold Bloom")

        let exportFile = directory.appendingPathComponent("backup.hatband-export")
        try Data([1, 2, 3]).write(to: exportFile)
        scanner.handle(url: exportFile)
        #expect(scanner.pendingImport == Data([1, 2, 3]))
        #expect(scanner.error == nil)

        scanner.handle(url: try #require(URL(string: "https://example.org/nothing")))
        #expect(scanner.error == .notHatband)
    }

    /// Every vector arrives through `handle(url:)` as a link and as a
    /// `.hatband` file, and through `receive(text:)` in each spelling
    /// `HB1.decode(url:)` accepts, with the signature class the vector has.
    @Test func handleURLAcceptsEveryVectorForm() async throws {
        let scanner = try await onboarded()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vectors-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for vector in try Vectors.all() {
            let name = try #require(vector["name"] as? String)
            let card = try Vectors.card(name)
            let url = try Vectors.url(name)
            let expected: Review.Signature = card.isCompact ? .compact
                : !card.isSigned ? .unsigned
                : name == "tampered-signature" ? .invalid : .valid

            scanner.pendingReview = nil
            scanner.handle(url: try #require(URL(string: url)))
            #expect(scanner.error == nil, "\(name)")
            #expect(scanner.pendingReview?.source == .link, "\(name)")
            #expect(scanner.pendingReview?.card == card, "\(name)")
            #expect(scanner.pendingReview?.signature == expected, "\(name)")

            let fragment = String(url.dropFirst(HB1.urlPrefix.count))
            for text in [url.uppercased(), "#" + fragment, fragment, "  " + url + "\n"] {
                scanner.pendingReview = nil
                try scanner.receive(text: text, source: .scan)
                #expect(scanner.pendingReview?.card == card, "\(name)")
                #expect(scanner.pendingReview?.source == .scan, "\(name)")
            }

            scanner.pendingReview = nil
            let fileHex = try #require(vector["file"] as? String)
            let bytes = try #require(Hex.bytes(fileHex))
            #expect(bytes.starts(with: HB1.fileMagic))
            let file = directory.appendingPathComponent(name + ".hatband")
            try Data(bytes).write(to: file)
            scanner.handle(url: file)
            #expect(scanner.error == nil, "\(name)")
            #expect(scanner.pendingReview?.source == .file, "\(name)")
            #expect(scanner.pendingReview?.card == card, "\(name)")
            #expect(scanner.pendingReview?.signature == expected, "\(name)")
        }
        // The tampered vector is shown as rejected, never saved.
        try scanner.receive(text: try Vectors.url("tampered-signature"), source: .scan)
        let rejected = try #require(scanner.pendingReview)
        guard case .rejected = rejected.outcome else {
            Issue.record("expected .rejected, got \(rejected.outcome)")
            return
        }
        await #expect(throws: AppError.invalidSignature) {
            try await scanner.save(rejected, fix: nil, label: "", note: "", tags: [])
        }
        #expect(scanner.people.isEmpty)
    }

    // MARK: - Forgetting

    @Test func forgetThenRestore() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        try await scanAndSave(scanner, try signedURL(from: sharer), tags: ["pub"])
        let person = try #require(scanner.people.first)
        try scanner.forget(person)
        #expect(scanner.people.isEmpty)
        #expect(try scanner.store?.people().isEmpty == true)
        #expect(scanner.undo == person)
        try scanner.restoreForgotten()
        #expect(scanner.undo == nil)
        #expect(scanner.people == [person])
        #expect(try scanner.store?.people().count == 1)
        try scanner.restoreForgotten()
        #expect(scanner.people.count == 1)
    }

    @Test func forgetExpiresAfterWindow() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie")
        try await scanAndSave(scanner, try signedURL(from: sharer))
        let person = try #require(scanner.people.first)
        try scanner.forget(person)
        #expect(scanner.undo != nil)
        try await Task.sleep(for: .milliseconds(400))
        #expect(scanner.undo == nil)
        #expect(scanner.people.isEmpty)
        #expect(try scanner.store?.people().isEmpty == true)
        try scanner.restoreForgotten()
        #expect(scanner.people.isEmpty)
    }

    /// An answer that comes back after a Forget must not put the record
    /// back, and one that comes back after a lock has no key to seal with.
    @Test func updateAfterForgetOrLockIsRefused() async throws {
        let certificate = syntheticV4Certificate()
        let sharer = try await onboarded { $0.gpgFingerprint = certificate.fingerprint }
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie", appLock: true)
        scanner.undoWindow = .seconds(5)
        try await scanAndSave(scanner, try signedURL(from: sharer))
        let person = try #require(scanner.people.first)
        try scanner.forget(person)
        #expect(throws: AppError.storage("This person is no longer on your phone.")) {
            try scanner.storeVerifiedGPGKey(certificate.packet, for: person)
        }
        var edited = person
        edited.note = "late"
        #expect(throws: AppError.storage("This person is no longer on your phone.")) {
            try scanner.update(edited)
        }
        #expect(scanner.people.isEmpty)
        #expect(try scanner.store?.people().isEmpty == true)
        try scanner.restoreForgotten()
        #expect(scanner.people == [person])

        scanner.lock()
        #expect(throws: AppError.storage("Unlock first.")) {
            try scanner.storeVerifiedGPGKey(certificate.packet, for: person)
        }
        #expect(await scanner.unlock())
        #expect(scanner.people.first?.gpgKey == nil)
        #expect(scanner.people.first?.note == "")
    }

    // MARK: - Index and re-sealing

    @Test func searchAndTags() async throws {
        let bloom = try await onboarded()
        let flower = try await onboarded(name: "Henry Flower", email: "henry@flower.ie") { $0.company = "Westland Row" }
        let scanner = try await onboarded(name: "Molly", email: "molly@example.ie")
        try await scanAndSave(scanner, try signedURL(from: bloom), label: "Dublin", tags: ["pub", "conference"])
        try await scanAndSave(scanner, try signedURL(from: flower), label: "Sandymount", tags: ["conference"])
        #expect(scanner.people.count == 2)
        #expect(scanner.tagNames == ["conference", "pub"])
        #expect(scanner.people(matching: "").count == 2)
        #expect(scanner.people(matching: "flower").map { $0.card.name } == ["Henry Flower"])
        #expect(scanner.people(matching: "FLOWER westland").map { $0.card.name } == ["Henry Flower"])
        #expect(scanner.people(matching: "pub").map { $0.card.name } == ["Leopold Bloom"])
        #expect(scanner.people(matching: "sandymount").map { $0.card.name } == ["Henry Flower"])
        #expect(scanner.people(matching: "bloom@example").map { $0.card.name } == ["Leopold Bloom"])
        #expect(scanner.people(matching: "nobody").isEmpty)
        #expect(scanner.people(matching: "").first?.card.name == "Henry Flower")
    }

    @Test func lockHidesUnlockReloadsFromRecords() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie", appLock: true)
        let fix = Fix(latitude: 53.3498, longitude: -6.2603, accuracy: 4000)
        try await scanAndSave(scanner, try signedURL(from: sharer), fix: fix, label: "Dublin", tags: ["pub"])
        let saved = try #require(scanner.people.first)
        scanner.lock()
        #expect(scanner.people.isEmpty)
        #expect(scanner.locked)
        #expect(await scanner.unlock())
        #expect(scanner.people == [saved])
        let record = try #require(try scanner.store?.person(id: Data(saved.personaID)))
        #expect(record.updatedAt == saved.updatedAt)
        let key = try #require(scanner.dbKey)
        let aad = Sealer.aad(domain: Sealer.personDomain, id: Data(saved.personaID))
        #expect(try PersonCodec.decode(try Sealer.open(record.sealed, key: key, aad: aad)) == saved)
        #expect(throws: (any Error).self) {
            try Sealer.open(record.sealed, key: SymmetricKey(size: .bits256), aad: aad)
        }
    }

    @Test func updatePersonPersists() async throws {
        let sharer = try await onboarded()
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie", appLock: true)
        try await scanAndSave(scanner, try signedURL(from: sharer))
        var person = try #require(scanner.people.first)
        person.note = "Met at the pub"
        person.tags = ["pub", "2026"]
        person.encounters[0].label = "Davy Byrne's"
        let before = try #require(try scanner.store?.person(id: Data(person.personaID))?.sealed)
        try scanner.update(person)
        let after = try #require(try scanner.store?.person(id: Data(person.personaID))?.sealed)
        #expect(before != after)
        #expect(scanner.people.first?.note == "Met at the pub")
        scanner.lock()
        #expect(await scanner.unlock())
        let reloaded = try #require(scanner.people.first)
        #expect(reloaded.note == "Met at the pub")
        #expect(reloaded.tags == ["pub", "2026"])
        #expect(reloaded.encounters.first?.label == "Davy Byrne's")
        #expect(reloaded.updatedAt >= person.updatedAt)
        #expect(try scanner.store?.people().count == 1)
    }

    @Test func storeVerifiedGPGKeyReseals() async throws {
        let certificate = syntheticV4Certificate()
        let sharer = try await onboarded { $0.gpgFingerprint = certificate.fingerprint }
        let scanner = try await onboarded(name: "Henry Flower", email: "henry@flower.ie", appLock: true)
        try await scanAndSave(scanner, try signedURL(from: sharer))
        let person = try #require(scanner.people.first)
        #expect(person.card.gpgFingerprint == certificate.fingerprint)
        #expect(person.gpgKey == nil)
        #expect(throws: AppError.self) {
            try scanner.storeVerifiedGPGKey([1, 2, 3], for: person)
        }
        #expect(scanner.people.first?.gpgKey == nil)
        let before = try #require(try scanner.store?.person(id: Data(person.personaID))?.sealed)
        try scanner.storeVerifiedGPGKey(certificate.packet, for: person)
        #expect(scanner.people.first?.gpgKey == certificate.packet)
        let after = try #require(try scanner.store?.person(id: Data(person.personaID))?.sealed)
        #expect(before != after)
        scanner.lock()
        #expect(await scanner.unlock())
        #expect(scanner.people.first?.gpgKey == certificate.packet)
    }
}
