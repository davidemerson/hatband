import HatbandCore
import SwiftUI

/// What a received card says, before anything is saved: each field with
/// its warning and a switch, what was left out, the outcome against People,
/// and the meeting: a coarse location, a place, a note, tags.
@MainActor struct ReviewSheet: View {
    let review: Review
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Review.Item]
    @State private var useLocation: Bool
    @State private var fix: Fix?
    @State private var locating = false
    @State private var label = ""
    @State private var note = ""
    @State private var tagText = ""
    @State private var tags: [String] = []
    @State private var acceptNewKey = false
    /// For a newer card from someone known: replace the stored card, or
    /// keep it and add the meeting alone.
    @State private var updateCard = true
    @State private var saving = false

    init(review: Review) {
        self.review = review
        _items = State(initialValue: review.items)
        _useLocation = State(initialValue: review.source.isInPerson)
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                outcomeSection
                fieldsSection
                if !review.dropped.isEmpty {
                    droppedSection
                }
                meetingSection
                tagsSection
            }
            .grounded()
            .navigationTitle(review.card.name ?? "Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .task(id: useLocation) {
            await locate()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            Label(signatureText, systemImage: signatureSymbol)
            if review.signature == .compact {
                Text("Lock Screen card. Ask for the full card for keys.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Issued")
                Spacer()
                Text(ReviewSheet.issuedText(review.card.issuedDay))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    @ViewBuilder private var outcomeSection: some View {
        Section {
            switch review.outcome {
            case .new:
                Label("New person", systemImage: "person.badge.plus")
            case .encounterOnly:
                Label("Already in People. This adds a meeting.", systemImage: "person.crop.circle.badge.checkmark")
            case .update(let changes):
                Label("Newer card from someone you know", systemImage: "arrow.triangle.2.circlepath")
                ForEach(Array(changes.enumerated()), id: \.offset) { entry in
                    changeRow(entry.element)
                }
            case .keyChanged:
                Label("Different key", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text("This card is signed by a key that is not the one you have for this person. Someone may be pretending to be them, or they may have a new phone. Check with them before trusting it.")
                    .font(.footnote)
                Toggle("Trust new key", isOn: $acceptNewKey)
            case .rejected(let reason):
                Label(reason, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }
            if ReviewSheet.offersMeetingOnly(review.outcome) {
                Picker("Newer card", selection: $updateCard) {
                    Text("Update card").tag(true)
                    Text("Add meeting only").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if !updateCard {
                    Text("The card you have stays as it is; only this meeting is added.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var fieldsSection: some View {
        Section("Card") {
            if items.isEmpty {
                Text("Nothing but an id.")
                    .foregroundStyle(.secondary)
            }
            ForEach($items) { $item in
                Toggle(isOn: $item.included) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(ReviewSheet.isMono(item.id) ? Theme.mono : .body)
                            .lineLimit(3)
                        if case .warning(let warning) = item.verdict {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private var droppedSection: some View {
        Section("Left out") {
            ForEach(review.dropped, id: \.self) { entry in
                Text(entry)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var meetingSection: some View {
        Section("Meeting") {
            Toggle(isOn: $useLocation) {
                Label(locationText, systemImage: "location")
            }
            TextField("Where (a place or an event)", text: $label)
            TextField("Note", text: $note)
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            ForEach(tags, id: \.self) { tag in
                HStack {
                    Text(tag)
                    Spacer()
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(tag)")
                }
            }
            TextField("Add a tag", text: $tagText)
                .onSubmit {
                    addTag()
                }
            let suggestions = model.tagNames.filter { !tags.contains($0) }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { name in
                            Button("+ " + name) {
                                tags.append(name)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func changeRow(_ change: Merge.Change) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(change.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let old = change.old {
                Text(old)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            Text(change.new ?? "Removed")
        }
    }

    // MARK: - State

    private var canSave: Bool {
        if case .rejected = review.outcome {
            return false
        }
        return !saving
    }

    private var signatureText: String {
        switch review.signature {
        case .valid: return "Signed by the card's key"
        case .invalid: return "The signature does not verify"
        case .unsigned: return "Unsigned card"
        case .compact: return "Lock Screen card"
        }
    }

    private var signatureSymbol: String {
        switch review.signature {
        case .valid: return "checkmark.seal"
        case .invalid: return "xmark.seal"
        case .unsigned: return "seal"
        case .compact: return "lock.iphone"
        }
    }

    private var locationText: String {
        guard useLocation else { return "Not noting where we met" }
        if locating {
            return "Finding a rough location…"
        }
        guard let fix else { return "No location" }
        return "Near " + ReviewSheet.coordinateText(fix)
    }

    private func locate() async {
        guard useLocation, fix == nil, !locating else { return }
        locating = true
        fix = await Location.coarseFix()
        locating = false
    }

    private func addTag() {
        let trimmed = tagText.trimmingCharacters(in: .whitespacesAndNewlines)
        tagText = ""
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        addTag()
        var accepted = review
        accepted.items = items
        accepted.updateCard = updateCard
        let chosenFix = useLocation ? fix : nil
        let place = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenTags = tags
        let trustNewKey = acceptNewKey
        Task {
            do {
                try await model.save(accepted, fix: chosenFix, label: place, note: text, tags: chosenTags,
                                     acceptNewKey: trustNewKey)
            } catch {
                model.error = AppError(error)
            }
            saving = false
        }
    }

    // MARK: - Formatting

    nonisolated static func isMono(_ id: String) -> Bool {
        id == CardFields.ssh || id == CardFields.gpgFingerprint || id == CardFields.signal
    }

    /// Only a newer card from someone known offers "Add meeting only".
    nonisolated static func offersMeetingOnly(_ outcome: Merge.Outcome) -> Bool {
        if case .update = outcome {
            return true
        }
        return false
    }

    /// `Day.civil` as yyyy-mm-dd.
    nonisolated static func issuedText(_ issuedDay: UInt32) -> String {
        let day = Day.civil(Int(issuedDay))
        return "\(day.year)-\(twoDigits(day.month))-\(twoDigits(day.day))"
    }

    /// Hundredths of a degree and a kilometre radius.
    nonisolated static func coordinateText(_ fix: Fix) -> String {
        let latitude = Double(fix.latitudeHundredths) / 100
        let longitude = Double(fix.longitudeHundredths) / 100
        let kilometres = max(1, (fix.accuracyMetres + 500) / 1000)
        return "\(latitude), \(longitude) (±\(kilometres) km)"
    }

    private nonisolated static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
