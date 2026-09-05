import HatbandCore
import SwiftUI

/// One persona: label, display name, colour, the profile channels it
/// shares (or, for an alias, its own profile), up to two Lock Screen
/// channels, and live meters for both codes. Done commits through
/// `AppModel.update(_:)`, which bumps `seq` only when something changed.
@MainActor struct PersonaEditorView: View {
    /// A colour swatch's tap target, the HIG minimum, and the disc in it.
    nonisolated static let swatchTarget: CGFloat = 44
    nonisolated static let swatchDiameter: CGFloat = 28

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let personaID: [UInt8]
    @State private var draft: Persona?
    @State private var problem: String?
    @State private var saving = false
    /// The two meters, rebuilt when `meterKey` changes and never in `body`:
    /// measuring reads the seed and signs.
    @State private var meters: [CardForm: MeasuredCard] = [:]

    var body: some View {
        Form {
            if let bound = Binding($draft) {
                sections(bound)
            } else {
                Text("This persona is gone.")
            }
            if let problem {
                Section {
                    Text(problem)
                        .foregroundStyle(.red)
                }
            }
        }
        .grounded()
        .navigationTitle(draft?.label ?? "Persona")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    save()
                }
                .disabled(saving || draft == nil)
            }
        }
        .onAppear {
            if draft == nil {
                draft = model.personas.first { $0.id == personaID }
            }
            model.route.editingPersona = personaID
        }
        .onDisappear {
            if model.route.editingPersona == personaID {
                model.route.editingPersona = nil
            }
        }
        .onChange(of: meterKey, initial: true) { _, _ in
            measure()
        }
    }

    // MARK: - Sections

    @ViewBuilder private func sections(_ persona: Binding<Persona>) -> some View {
        Section("Persona") {
            TextField("Label", text: persona.label)
            TextField("Name on the card (optional)", text: optionalText(persona.displayName))
                .textContentType(.name)
        }
        Section("Colour") {
            colours(persona)
        }
        Section {
            Toggle("Alias", isOn: aliasBinding(persona))
            if persona.wrappedValue.isAlias {
                NavigationLink("Alias details") {
                    ProfileEditorView(alias: persona.wrappedValue.aliasProfile ?? Profile()) { edited in
                        draft?.aliasProfile = edited
                    }
                }
            }
        } footer: {
            Text("An alias carries a name and details of its own; nothing from your profile goes on its card.")
        }
        if !persona.wrappedValue.isAlias {
            Section("From your profile") {
                if model.profile.company != nil {
                    Toggle("Company", isOn: persona.includeCompany)
                }
                if model.profile.photo != nil {
                    Toggle("Photo, in file and link shares", isOn: persona.includePhoto)
                }
                ForEach(availableChannels, id: \.self) { key in
                    Toggle(Links.label(for: key), isOn: channelBinding(persona, key))
                }
                ForEach(model.profile.custom, id: \.label) { field in
                    Toggle(field.label, isOn: customBinding(persona, field.label))
                }
            }
        }
        Section {
            Picker("First", selection: lockBinding(persona, slot: 0)) {
                lockOptions(persona)
            }
            Picker("Second", selection: lockBinding(persona, slot: 1)) {
                lockOptions(persona)
            }
        } header: {
            Text("Lock Screen channels")
        } footer: {
            Text("Your name is always on the Lock Screen card. Channels that do not fit are dropped, last first.")
        }
        Section("Size") {
            meter(form: .fullQR, title: "Full card")
            meter(form: .lockScreen, title: "Lock Screen")
        }
    }

    /// The palette in a wrapping grid: each swatch a 44 pt target named
    /// for VoiceOver, the chosen one ringed in ink.
    private func colours(_ persona: Binding<Persona>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: PersonaEditorView.swatchTarget), spacing: 4)],
                  alignment: .leading, spacing: 4) {
            ForEach(0..<Palette.colors.count, id: \.self) { index in
                let selected = persona.wrappedValue.color == UInt8(index)
                Button {
                    persona.wrappedValue.color = UInt8(index)
                } label: {
                    Circle()
                        .fill(Theme.personaColor(UInt8(index)))
                        .frame(width: PersonaEditorView.swatchDiameter, height: PersonaEditorView.swatchDiameter)
                        .overlay {
                            Circle()
                                .strokeBorder(Theme.ink, lineWidth: selected ? 2 : 0)
                        }
                        .frame(width: PersonaEditorView.swatchTarget, height: PersonaEditorView.swatchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PersonaEditorView.swatchLabel(index))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    /// The VoiceOver name of a swatch: the palette colour's name.
    nonisolated static func swatchLabel(_ index: Int) -> String {
        Palette.color(at: UInt8(clamping: index)).name
    }

    @ViewBuilder private func lockOptions(_ persona: Binding<Persona>) -> some View {
        Text("None").tag(nil as FieldKey?)
        ForEach(lockCandidates(persona.wrappedValue), id: \.self) { key in
            Text(Links.label(for: key)).tag(key as FieldKey?)
        }
    }

    @ViewBuilder private func meter(form: CardForm, title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let budget = meters[form]?.budget {
                ByteMeter(budget: budget, form: form, compact: true)
            } else if meters[form] != nil {
                Text(form == .lockScreen ? "too big for the Lock Screen" : "cannot build")
                    .font(Theme.mono)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Meters

    /// What the meters depend on; nil until the draft is loaded.
    private var meterKey: BudgetKey? {
        draft.map { model.budgetKey(for: $0) }
    }

    private func measure() {
        guard let draft else {
            meters = [:]
            return
        }
        meters = [.fullQR: model.measure(draft, form: .fullQR), .lockScreen: model.measure(draft, form: .lockScreen)]
    }

    // MARK: - Choices

    /// Profile channels that have a value.
    private var availableChannels: [FieldKey] {
        FieldKey.channels.filter { model.profile.presentChannels.contains($0) }
    }

    /// Channels the compact card may carry: what the persona shares.
    private func lockCandidates(_ persona: Persona) -> [FieldKey] {
        let present = persona.aliasProfile?.presentChannels ?? persona.channels.intersection(model.profile.presentChannels)
        return FieldKey.channels.filter { present.contains($0) }
    }

    // MARK: - Bindings

    private func optionalText(_ base: Binding<String?>) -> Binding<String> {
        Binding(
            get: { base.wrappedValue ?? "" },
            set: { base.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func aliasBinding(_ persona: Binding<Persona>) -> Binding<Bool> {
        Binding(
            get: { persona.wrappedValue.isAlias },
            set: { on in
                if on {
                    if persona.wrappedValue.aliasProfile == nil {
                        persona.wrappedValue.aliasProfile = Profile()
                    }
                } else {
                    persona.wrappedValue.aliasProfile = nil
                }
                persona.wrappedValue.lockScreenChannels = []
            })
    }

    private func channelBinding(_ persona: Binding<Persona>, _ key: FieldKey) -> Binding<Bool> {
        Binding(
            get: { persona.wrappedValue.channels.contains(key) },
            set: { on in
                if on {
                    persona.wrappedValue.channels.insert(key)
                } else {
                    persona.wrappedValue.channels.remove(key)
                    persona.wrappedValue.lockScreenChannels.removeAll { $0 == key }
                }
            })
    }

    private func customBinding(_ persona: Binding<Persona>, _ label: String) -> Binding<Bool> {
        Binding(
            get: { persona.wrappedValue.customLabels.contains(label) },
            set: { on in
                if on {
                    persona.wrappedValue.customLabels.insert(label)
                } else {
                    persona.wrappedValue.customLabels.remove(label)
                }
            })
    }

    /// Slot 0 or 1 of `lockScreenChannels`; choosing the same channel
    /// twice keeps it once.
    private func lockBinding(_ persona: Binding<Persona>, slot: Int) -> Binding<FieldKey?> {
        Binding(
            get: {
                let channels = persona.wrappedValue.lockScreenChannels
                return channels.count > slot ? channels[slot] : nil
            },
            set: { value in
                var slots: [FieldKey?] = [nil, nil]
                let current = persona.wrappedValue.lockScreenChannels
                for (index, key) in current.prefix(2).enumerated() {
                    slots[index] = key
                }
                slots[slot] = value
                var next: [FieldKey] = []
                for key in slots {
                    if let key, !next.contains(key) {
                        next.append(key)
                    }
                }
                persona.wrappedValue.lockScreenChannels = next
            })
    }

    // MARK: - Done

    private func save() {
        guard let draft else {
            dismiss()
            return
        }
        let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            problem = "Give the persona a label."
            return
        }
        if let displayName = draft.displayName, !FieldValidator.name(displayName, limits: .file).isAccepted {
            problem = "The name on the card is too long or has characters a card cannot carry."
            return
        }
        if draft.isAlias, (draft.aliasProfile?.name ?? "").isEmpty {
            problem = "An alias needs a name: open Alias details."
            return
        }
        var committed = draft
        committed.label = label
        saving = true
        problem = nil
        Task {
            do {
                try await model.update(committed)
                dismiss()
            } catch {
                problem = AppError(error).message
            }
            saving = false
        }
    }
}
