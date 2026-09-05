import HatbandCore
import SwiftUI

/// Every persona: which one the card shows, a door to each editor, and
/// the way to add or delete one. Presented as a sheet, from the Card tab
/// or Settings; it brings its own `NavigationStack` and pushes the editors.
@MainActor struct PersonaListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var newLabel = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.personas, id: \.id) { persona in
                    NavigationLink {
                        PersonaEditorView(personaID: persona.id)
                    } label: {
                        row(persona)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Use") {
                            model.select(persona)
                        }
                        .tint(Theme.accent)
                    }
                    .deleteDisabled(model.personas.count < 2)
                }
                .onDelete(perform: delete)
            }
            .grounded()
            .navigationTitle("Personas")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newLabel = ""
                        adding = true
                    } label: {
                        Label("Add persona", systemImage: "plus")
                    }
                }
            }
            .alert("New persona", isPresented: $adding) {
                TextField("Label, such as Work", text: $newLabel)
                Button("Add persona") {
                    add(alias: false)
                }
                Button("Add alias") {
                    add(alias: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A persona shares a subset of your profile under its own key. An alias has a name and details of its own.")
            }
        }
    }

    private func row(_ persona: Persona) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.personaColor(persona.color))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Image(systemName: persona.isAlias ? Theme.flower : Theme.hat)
                .foregroundStyle(Theme.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(persona.label)
                Text(summary(persona))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if persona.id == model.selectedPersonaID {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Shown on the Card tab")
            }
        }
    }

    private func summary(_ persona: Persona) -> String {
        if persona.isAlias {
            return "Alias" + (persona.aliasProfile?.name.map { ": " + $0 } ?? "")
        }
        let count = persona.channels.intersection(model.profile.presentChannels).count
        return count == 1 ? "1 channel" : "\(count) channels"
    }

    private func add(alias: Bool) {
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        do {
            _ = try model.addPersona(label: label, alias: alias)
        } catch {
            model.error = AppError(error)
        }
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { model.personas[$0] }
        for persona in doomed {
            do {
                try model.delete(persona: persona)
            } catch {
                model.error = AppError(error)
            }
        }
    }
}
