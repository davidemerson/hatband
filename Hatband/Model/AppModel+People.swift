import CryptoKit
import Foundation
import HatbandCore

/// What `handle(url:)` or `receive` found. Performed at once when `phase`
/// allows, otherwise kept in `AppModel.deferredOpen` until it does: an
/// `onOpenURL` can arrive before `load()` has read the owner, and a card
/// link tapped during onboarding has no store to save into yet.
nonisolated enum DeferredOpen: Equatable, Sendable {
    /// A decoded card and where it came from; becomes `pendingReview`.
    case card(Card, source: CardSource)
    /// A `.hatband-export`; becomes `pendingImport`.
    case export(Data)
    /// `hatband://show?persona=` or `hatband://scan`.
    case scheme(URL)
}

/// Receiving, reviewing, keeping and forgetting people. Every person body
/// is sealed under the database key before it touches the store.
extension AppModel {
    /// A URL or fragment from a scan, a photo, a link or a file share.
    func receive(text: String, source: CardSource) throws {
        let card: Card
        do {
            card = try HB1.decode(url: text)
        } catch {
            throw AppError(error)
        }
        perform(.card(card, source: source))
    }

    /// A `.hatband` file.
    func receive(fileBytes: [UInt8]) throws {
        let card: Card
        do {
            card = try HB1.decode(file: fileBytes)
        } catch {
            throw AppError(error)
        }
        perform(.card(card, source: .file))
    }

    /// The five kinds of URL the app opens: a `.hatband` file, a
    /// `.hatband-export` file, `hatband://show?persona=`, `hatband://scan`
    /// and an `https://hatband.link/#` link. Malformed input is reported at
    /// once; a valid open waits for `phase` when it must.
    func handle(url: URL) {
        do {
            if url.isFileURL {
                try handleFile(url)
            } else if url.scheme?.lowercased() == "hatband" {
                perform(.scheme(url))
            } else {
                try receive(text: url.absoluteString, source: .link)
            }
        } catch {
            self.error = AppError(error)
            Log.failure("open url", error)
        }
    }

    /// Performs `deferredOpen` if `phase` now allows it. Called when
    /// `load()` finishes, when onboarding completes and after a restore.
    func performDeferredOpen() {
        guard let open = deferredOpen, canPerform(open) else { return }
        deferredOpen = nil
        perform(open)
    }

    /// Unlocks first when locked. When unlocking reveals the person is
    /// already known, the review is rebuilt against them and shown again
    /// instead of saved, since the outcome the user saw was wrong.
    func save(_ review: Review, fix: Fix?, label: String, note: String, tags: [String],
              acceptNewKey: Bool = false) async throws {
        if case .rejected = review.outcome {
            throw AppError.invalidSignature
        }
        let key = try await requireKey()
        let existing = people.first { $0.personaID == review.card.personaID }
        if review.existing == nil, existing != nil {
            var rebuilt = Review.make(card: review.card, source: review.source, people: people)
            let excluded = Set(review.items.filter { !$0.included }.map { $0.id })
            for index in rebuilt.items.indices where excluded.contains(rebuilt.items[index].id) {
                rebuilt.items[index].included = false
            }
            pendingReview = rebuilt
            return
        }
        let person = Merge.apply(existing: existing, review: review, fix: fix, label: label, note: note,
                                 tags: tags, acceptNewKey: acceptNewKey, now: AppModel.wholeSecondsNow())
        try persist(person, key: key)
        replace(person)
        pendingReview = nil
        route.sheet = nil
        route.tab = .card
    }

    /// Re-seals and saves an edited person.
    func update(_ person: Person) throws {
        guard let key = dbKey else { throw AppError.storage("Unlock first.") }
        var updated = person
        updated.updatedAt = AppModel.wholeSecondsNow()
        try persist(updated, key: key)
        replace(updated)
    }

    /// Deletes the record now and keeps the person in `undo` for
    /// `undoWindow`.
    func forget(_ person: Person) throws {
        let store = try openedStore()
        if let record = try store.person(id: Data(person.personaID)) {
            store.delete(record)
            try store.save()
            store.reassertProtection()
        }
        people.removeAll { $0.personaID == person.personaID }
        undo = person
        undoGeneration += 1
        let generation = undoGeneration
        let window = undoWindow
        Task { [weak self] in
            try? await Task.sleep(for: window)
            // Only the timer of the latest forget clears the buffer: the
            // same person forgotten again after an undo gets a full window.
            guard let self, self.undoGeneration == generation else { return }
            self.undo = nil
        }
    }

    func restoreForgotten() throws {
        guard let person = undo else { return }
        guard let key = dbKey else { throw AppError.storage("Unlock first.") }
        try persist(person, key: key)
        replace(person)
        undo = nil
        undoGeneration += 1
    }

    /// Most recently updated first; every whitespace-separated term must
    /// appear somewhere in the person's text.
    func people(matching query: String) -> [Person] {
        // Newest first; on equal timestamps (the codec keeps whole seconds)
        // the later entry in `people` wins, which is save order.
        let sorted = people.enumerated()
            .sorted { a, b in
                a.element.updatedAt != b.element.updatedAt
                    ? a.element.updatedAt > b.element.updatedAt
                    : a.offset > b.offset
            }
            .map(\.element)
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        guard !terms.isEmpty else { return sorted }
        return sorted.filter { person in
            let text = AppModel.searchText(for: person)
            return terms.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    var tagNames: [String] {
        Array(Set(people.flatMap { $0.tags })).sorted()
    }

    func vcard(for person: Person, met: String?) -> VCard {
        Links.vcard(for: person, met: met)
    }

    /// Keeps a fetched certificate only when it hashes to the card's
    /// fingerprint and fits the file cap.
    func storeVerifiedGPGKey(_ bytes: [UInt8], for person: Person) throws {
        guard let fingerprint = person.card.gpgFingerprint, Verify.certificate(bytes, matches: fingerprint) else {
            throw AppError.storage("The key does not match the card's fingerprint.")
        }
        guard FieldValidator.gpgKey(byteCount: bytes.count, limits: .file).isAccepted else {
            throw AppError.tooLarge
        }
        var updated = person
        updated.gpgKey = bytes
        try update(updated)
    }

    /// Name, company, channels, custom fields, tags, notes and places.
    nonisolated static func searchText(for person: Person) -> String {
        var parts: [String] = []
        let card = person.card
        for value in [card.name, card.company, card.phone, card.email, card.github, card.linkedin, card.mastodon, card.calendly] {
            if let value {
                parts.append(value)
            }
        }
        if let website = card.website {
            parts.append(website.address)
        }
        for field in card.custom {
            parts.append(field.label + " " + field.value)
        }
        parts.append(contentsOf: person.tags)
        parts.append(person.note)
        for encounter in person.encounters {
            parts.append(encounter.label)
            parts.append(encounter.note)
        }
        return parts.joined(separator: "\n")
    }

    /// The codec stores whole seconds; keeping memory the same means a
    /// reload compares equal.
    nonisolated static func wholeSecondsNow() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    // MARK: - Private

    private func handleFile(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        switch url.pathExtension.lowercased() {
        case HB1.fileExtension:
            guard data.count <= HB1.maxBytes + HB1.fileMagic.count else { throw AppError.tooLarge }
            try receive(fileBytes: Array(data))
        case "hatband-export":
            perform(.export(data))
        default:
            throw AppError.notHatband
        }
    }

    /// An export can be restored from onboarding; everything else needs the
    /// owner loaded, so a `hatband://show` tap on a cold launch selects the
    /// persona it names instead of an empty list.
    private func canPerform(_ open: DeferredOpen) -> Bool {
        switch open {
        case .export:
            return phase == .onboarding || phase == .ready
        case .card, .scheme:
            return phase == .ready
        }
    }

    /// Acts on the open now, or keeps it for `performDeferredOpen()`. A
    /// later open replaces an earlier one still waiting.
    private func perform(_ open: DeferredOpen) {
        guard canPerform(open) else {
            deferredOpen = open
            return
        }
        switch open {
        case .card(let card, let source):
            pendingReview = Review.make(card: card, source: source, people: people)
        case .export(let data):
            pendingImport = data
        case .scheme(let url):
            handleScheme(url)
        }
    }

    private func handleScheme(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch components?.host?.lowercased() {
        case "show":
            let hex = components?.queryItems?.first { $0.name == "persona" }?.value ?? ""
            if let id = Hex.bytes(hex), let persona = personas.first(where: { $0.id == id }) {
                select(persona)
            }
            route.sheet = nil
            route.tab = .card
        case "scan":
            route.tab = .card
            route.sheet = .scan
        default:
            break
        }
    }

    /// `PersonCodec.encode` → `Sealer.seal` under the database key with the
    /// person domain and persona id → `PersonRecord` (insert or update) →
    /// `store.save()` → `reassertProtection()`.
    private func persist(_ person: Person, key: SymmetricKey) throws {
        let store = try openedStore()
        let id = Data(person.personaID)
        let aad = Sealer.aad(domain: Sealer.personDomain, id: id)
        let sealed = try Sealer.seal(PersonCodec.encode(person), key: key, aad: aad)
        if let record = try store.person(id: id) {
            record.sealed = sealed
            record.updatedAt = person.updatedAt
        } else {
            store.insert(PersonRecord(personaID: id, updatedAt: person.updatedAt, sealed: sealed))
        }
        try store.save()
        store.reassertProtection()
    }

    private func replace(_ person: Person) {
        if let index = people.firstIndex(where: { $0.personaID == person.personaID }) {
            people[index] = person
        } else {
            people.append(person)
        }
    }

    private func openedStore() throws -> Store {
        guard let store else { throw AppError.storage("The store is not open.") }
        return store
    }
}
