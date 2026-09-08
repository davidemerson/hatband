import HatbandCore
import SwiftUI
import UIKit

/// One person: links with their domains, keys in mono, verification and
/// key fetches labelled with the host they touch, meetings, tags, Add to
/// Contacts, and Forget.
@MainActor struct PersonView: View {
    let personID: String
    @Environment(AppModel.self) private var model

    init(personID: String) {
        self.personID = personID
    }

    var body: some View {
        if let person = model.people.first(where: { $0.id == personID }) {
            PersonDetail(person: person)
                .id(person.id)
        } else {
            ContentUnavailableView("Forgotten", systemImage: "person.slash",
                                   description: Text("This person is no longer on your phone."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.ground)
        }
    }

    /// The three things this screen edits, put onto the model's copy of the
    /// person. `edited` is a snapshot taken when the view appeared and is
    /// never refreshed, so writing it whole would undo anything stored behind
    /// this screen: a GPG key fetched from the same screen, or a newer card
    /// merged from a review while this one is still on the stack.
    nonisolated static func committed(_ edited: Person, onto current: Person) -> Person {
        var candidate = current
        candidate.note = edited.note
        candidate.tags = edited.tags
        candidate.encounters = edited.encounters
        return candidate
    }

    /// Edits are committed as the scene leaves the foreground: at
    /// `.inactive`, which comes before `.background` and the lock that
    /// empties `people`, and again at `.background` for good measure.
    nonisolated static func commitsEdits(entering phase: ScenePhase) -> Bool {
        phase != .active
    }

    /// Whether a fetch that has just come back may be shown and stored: only
    /// while unlocked and while the person is still on the phone. A lock or
    /// a Forget during the fetch drops the answer.
    nonisolated static func keepsFetchResult(locked: Bool, people: [Person], personID: String) -> Bool {
        !locked && people.contains { $0.id == personID }
    }
}

/// Holds the editable copy; commits on submit, on leaving, when the scene
/// leaves the foreground, and on every action that is not typing.
@MainActor private struct PersonDetail: View {
    let person: Person
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var edited: Person
    @State private var newTag = ""
    @State private var busy: FetchTarget.Kind?
    @State private var messages: [String] = []
    @State private var showingContact = false
    @State private var confirmingForget = false
    /// Held until confirmed. The person has a dialog and ten seconds of undo;
    /// a meeting had neither, and it carries the place and note you typed.
    @State private var pendingMeetingDelete: IndexSet?

    init(person: Person) {
        self.person = person
        _edited = State(initialValue: person)
    }

    private var card: Card { person.card }

    var body: some View {
        List {
            headerSection
            linksSection
            keysSection
            if hasVerifications {
                verifySection
            }
            meetingsSection
            notesSection
            contactsSection
            forgetSection
        }
        .grounded()
        .navigationTitle(card.name ?? "Card")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            commit()
        }
        .onChange(of: scenePhase) { _, phase in
            if PersonView.commitsEdits(entering: phase) {
                commit()
            }
        }
        .sheet(isPresented: $showingContact) {
            UnknownContactView(person: person, met: person.encounters.first?.date)
                .privacyCovered()
        }
        .confirmationDialog("Delete this meeting?", isPresented: meetingDeletePresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingMeetingDelete {
                    edited.encounters.remove(atOffsets: pendingMeetingDelete)
                    commit()
                }
                pendingMeetingDelete = nil
            }
            Button("Keep", role: .cancel) { pendingMeetingDelete = nil }
        } message: {
            Text("The day, the place and the note go with it. There is no undo for a meeting.")
        }
        .confirmationDialog("Forget \(card.name ?? "this person")?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                forget()
            }
        } message: {
            Text("The card and every meeting go. You have ten seconds to undo.")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                if let photo = person.currentPhoto, let image = UIImage(data: Data(photo)) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(card.name ?? "Unnamed")
                            .font(.title2.bold())
                        if card.flags.contains(.alias) {
                            Image(systemName: Theme.flower)
                                .foregroundStyle(Theme.tertiary)
                                .accessibilityLabel("Alias")
                        }
                    }
                    if let company = card.company {
                        Text(company)
                            .foregroundStyle(.secondary)
                    }
                    Text(trustText)
                        .font(Theme.mono)
                        .foregroundStyle(trustIsWarning ? .red : Theme.tertiary)
                    Text("Card issued " + ReviewSheet.issuedText(card.issuedDay))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .listRowBackground(
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.personaColor(card.color))
                        .frame(width: 4)
                    Color.clear
                }
            )
        }
    }

    private var linksSection: some View {
        Section("Links") {
            let rows = Links.rows(for: card)
            if rows.isEmpty {
                Text("No contact details on this card.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                linkRow(row)
            }
        }
    }

    private func linkRow(_ row: Links.Row) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = row.url, let destination = URL(string: url) {
                    Link(destination: destination) {
                        Text(row.text)
                            .font(row.mono ? Theme.mono : .body)
                            .underline()
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(row.text)
                        .font(row.mono ? Theme.mono : .body)
                }
                if let domain = row.domain {
                    Text(domain)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Spacer()
            CopyButton(text: row.text, label: "Copy " + row.label)
        }
        .buttonStyle(.borderless)
    }

    private var keysSection: some View {
        Section("Keys") {
            if let key = person.publicKey, let fingerprint = KeyFingerprint(publicKey: key) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Card key fingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FingerprintText(bytes: fingerprint.full)
                }
            } else if let short = person.keyFingerprint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lock Screen key fingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FingerprintText(bytes: short)
                }
            } else {
                Text("No key on this card.")
                    .foregroundStyle(.secondary)
            }
            if case .keyChanged(let previous) = person.trust, !previous.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FingerprintText(bytes: PersonDetail.fingerprintBytes(previous))
                }
            }
            if let ssh = card.ssh, let kind = SSHPublicKey.Kind(rawValue: ssh.kind), kind != .rsa,
               let key = try? SSHPublicKey(kind: kind, inlineBytes: ssh.bytes) {
                CopyButton(text: key.authorizedKeysLine(), label: "Copy authorized_keys line",
                           title: "Copy authorized_keys line")
                if let email = card.email {
                    CopyButton(text: key.allowedSignersLine(principal: email),
                               label: "Copy allowed_signers line", title: "Copy allowed_signers line")
                }
            }
            if let gpgKey = person.gpgKey {
                Label("GPG key on file, \(gpgKey.count) bytes", systemImage: "key")
                    .foregroundStyle(.secondary)
            } else if let fingerprint = card.gpgFingerprint {
                if let email = card.email, let at = email.lastIndex(of: "@") {
                    let local = String(email[..<at])
                    let domain = String(email[email.index(after: at)...])
                    fetchKeyButton(.wkdAdvanced(local: local, domain: domain), fingerprint: fingerprint)
                    fetchKeyButton(.wkdDirect(local: local, domain: domain), fingerprint: fingerprint)
                }
                fetchKeyButton(.keysOpenPGP(fingerprint: fingerprint), fingerprint: fingerprint)
            }
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasVerifications: Bool {
        (card.github != nil && (card.ssh != nil || card.gpgFingerprint != nil))
            || (card.mastodon != nil && card.website != nil)
    }

    private var verifySection: some View {
        Section("Verify") {
            if let user = card.github, let ssh = card.ssh {
                fetchButton(FetchTarget.githubKeys(user: user).buttonTitle, .githubKeys(user: user)) { data in
                    let listed = Verify.githubKeys(String(decoding: data, as: UTF8.self), matches: ssh)
                    return listed ? "github.com lists this SSH key." : "github.com does not list this SSH key."
                }
            }
            if let user = card.github, let fingerprint = card.gpgFingerprint {
                fetchButton(FetchTarget.githubGPG(user: user).buttonTitle, .githubGPG(user: user)) { data in
                    guard let bytes = OpenPGP.dearmor(String(decoding: data, as: UTF8.self)) else {
                        return "github.com did not return a key."
                    }
                    guard Verify.certificate(bytes, matches: fingerprint) else {
                        return "github.com serves a key with a different fingerprint."
                    }
                    store(bytes)
                    return "github.com serves a key with this fingerprint."
                }
            }
            if let handle = card.mastodon, let parts = PersonDetail.mastodonParts(handle), let website = card.website {
                let target = FetchTarget.mastodonLookup(user: parts.user, instance: parts.instance)
                fetchButton(target.buttonTitle, target) { data in
                    let site = CanonicalURI.website(website.address, insecure: website.insecure)
                    let verified = Verify.mastodonVerified(json: data, website: site)
                    return verified ? "\(target.host) verified the website link." : "\(target.host) has not verified the website."
                }
            }
        }
    }

    private var meetingsSection: some View {
        Section("Meetings") {
            ForEach($edited.encounters) { $encounter in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(encounter.date, style: .date)
                        Text(encounter.date, style: .time)
                    }
                    .font(Theme.mono)
                    .foregroundStyle(Theme.tertiary)
                    TextField("Where", text: $encounter.label)
                        .onSubmit {
                            commit()
                        }
                    TextField("Note", text: $encounter.note)
                        .onSubmit {
                            commit()
                        }
                    Text(encounter.fix.map { "Near " + ReviewSheet.coordinateText($0) } ?? "No location")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .onDelete { pendingMeetingDelete = $0 }
        }
    }

    private var notesSection: some View {
        Section("Notes and tags") {
            TextField("Note", text: $edited.note, axis: .vertical)
                .onSubmit {
                    commit()
                }
            ForEach(edited.tags, id: \.self) { tag in
                HStack {
                    Text(tag)
                    Spacer()
                    Button {
                        edited.tags.removeAll { $0 == tag }
                        commit()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(tag)")
                }
            }
            TextField("Add a tag", text: $newTag)
                .onSubmit {
                    let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    newTag = ""
                    guard !trimmed.isEmpty, !edited.tags.contains(trimmed) else { return }
                    edited.tags.append(trimmed)
                    commit()
                }
        }
    }

    private var contactsSection: some View {
        Section {
            Button {
                showingContact = true
            } label: {
                Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus")
            }
            ShareLink(item: vcardFile, preview: SharePreview(card.name ?? "Card")) {
                Label("Share as vCard", systemImage: "square.and.arrow.up")
            }
        } footer: {
            Text("Both send the name, company, numbers, addresses and links. The vCard also carries the day you met, your note and any key. Neither sends where you were.")
        }
    }

    private var forgetSection: some View {
        Section {
            Button("Forget", role: .destructive) {
                confirmingForget = true
            }
        }
    }

    // MARK: - Pieces

    private func fetchKeyButton(_ target: FetchTarget, fingerprint: [UInt8]) -> some View {
        fetchButton(target.buttonTitle, target) { data in
            let text = String(decoding: data, as: UTF8.self)
            let bytes = text.contains("-----BEGIN PGP") ? OpenPGP.dearmor(text) : Array(data)
            guard let bytes else { return "\(target.host) did not return a key." }
            guard Verify.certificate(bytes, matches: fingerprint) else {
                return "\(target.host) returned a key with a different fingerprint."
            }
            store(bytes)
            return "Key fetched from \(target.host) and kept."
        }
    }

    private func fetchButton(_ title: String, _ target: FetchTarget, check: @escaping @MainActor (Data) -> String) -> some View {
        Button {
            fetch(target, check: check)
        } label: {
            HStack {
                Label(title, systemImage: "network")
                if busy == target.kind {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(busy != nil)
    }

    // MARK: - Actions

    /// The answer is dropped, unshown and unstored, when a lock or a
    /// Forget happened while it was out.
    private func fetch(_ target: FetchTarget, check: @escaping @MainActor (Data) -> String) {
        busy = target.kind
        Task {
            do {
                let data = try await ExplicitFetch.get(target)
                if PersonView.keepsFetchResult(locked: model.locked, people: model.people, personID: person.id) {
                    messages.append(check(data))
                }
            } catch {
                messages.append("\(target.host): \(PersonDetail.describe(error))")
            }
            busy = nil
        }
    }

    /// Only onto the person as they are now: still on the phone, still
    /// without a key.
    private func store(_ bytes: [UInt8]) {
        guard !model.locked, let current = model.people.first(where: { $0.id == person.id }), current.gpgKey == nil else {
            return
        }
        do {
            try model.storeVerifiedGPGKey(bytes, for: current)
        } catch {
            model.error = AppError(error)
        }
    }

    private var meetingDeletePresented: Binding<Bool> {
        Binding(get: { pendingMeetingDelete != nil }, set: { if !$0 { pendingMeetingDelete = nil } })
    }

    private func commit() {
        guard let current = model.people.first(where: { $0.id == person.id }) else { return }
        let candidate = PersonView.committed(edited, onto: current)
        guard candidate != current else { return }
        do {
            try model.update(candidate)
        } catch {
            model.error = AppError(error)
        }
    }

    private func forget() {
        do {
            try model.forget(person)
            model.route.person = nil
        } catch {
            model.error = AppError(error)
        }
    }

    // MARK: - Text

    /// The note says the day you met and nothing else, as the footer
    /// above promises: never the place.
    private var vcardFile: VCardFile {
        let met = person.encounters.first.map { Links.metNote(for: $0) }
        let text = model.vcard(for: person, met: met).text
        return VCardFile(bytes: Array(text.utf8), name: CardView.fileBase(card.name ?? "") + ".vcf")
    }

    private var trustText: String {
        switch person.trust {
        case .inPerson:
            return "Met in person, " + (person.createdAt.formatted(date: .abbreviated, time: .omitted))
        case .byFile:
            return "Received as a file or link, " + (person.createdAt.formatted(date: .abbreviated, time: .omitted))
        case .keyChanged:
            return "Key changed and accepted by you"
        }
    }

    private var trustIsWarning: Bool {
        if case .keyChanged = person.trust {
            return true
        }
        return false
    }

    /// `user@instance`, a leading `@` tolerated, split at the last `@`.
    nonisolated static func mastodonParts(_ handle: String) -> (user: String, instance: String)? {
        let text = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        guard let at = text.lastIndex(of: "@"), at != text.startIndex, text.index(after: at) != text.endIndex else {
            return nil
        }
        return (String(text[..<at]), String(text[text.index(after: at)...]))
    }

    /// A stored pin is a 32-byte key or an 8-byte fingerprint.
    nonisolated private static func fingerprintBytes(_ previous: [UInt8]) -> [UInt8] {
        if let fingerprint = KeyFingerprint(publicKey: previous) {
            return fingerprint.full
        }
        return previous
    }

    nonisolated private static func describe(_ error: any Error) -> String {
        if let fetch = error as? ExplicitFetch.Error {
            switch fetch {
            case .notHTTPS: return "not an https address."
            case .noResponse: return "no response."
            case .status(let code): return "answered \(code)."
            case .tooLarge: return "answer too large."
            }
        }
        return "could not be reached."
    }
}
