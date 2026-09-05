import Foundation
import SwiftUI

/// The passphrase sheet for `pendingImport`. Restores while onboarding,
/// merges otherwise; shows what came in.
@MainActor struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var working = false
    @State private var problem: String?
    @State private var summary: AppModel.ImportSummary?
    /// The mode a run used; `phase` moves on once a restore succeeds.
    @State private var ranMode: AppModel.ImportMode?

    private var mode: AppModel.ImportMode {
        ranMode ?? (model.phase == .onboarding ? .restore : .merge)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let summary {
                    summarySection(summary)
                } else {
                    entrySection
                }
            }
            .grounded()
            .navigationTitle(mode == .restore ? "Restore" : "Merge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(summary == nil ? "Cancel" : "Done") {
                        dismiss()
                    }
                    .disabled(working)
                }
            }
        }
        .interactiveDismissDisabled(working)
    }

    private var entrySection: some View {
        Group {
            Section {
                Text(mode == .restore
                     ? "This export becomes this iPhone's Hatband: card, personas, signing seed and the people you had scanned."
                     : "Your identity here stays. Personas and people from the export are added; a newer copy of a person replaces an older one, and meetings are combined.")
                    .foregroundStyle(.secondary)
            }
            Section("Passphrase") {
                PassphraseField("The words you were given", text: $passphrase)
            }
            Section {
                Button(working ? "Opening…" : (mode == .restore ? "Restore" : "Merge")) {
                    run()
                }
                .disabled(working || passphrase.isEmpty)
                if let problem {
                    Text(problem)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func summarySection(_ summary: AppModel.ImportSummary) -> some View {
        Group {
            Section(mode == .restore ? "Restored" : "Merged") {
                LabeledContent("Personas", value: String(summary.personas))
                LabeledContent("People", value: String(summary.people))
                LabeledContent("Meetings", value: String(summary.encounters))
                if summary.keyChanges > 0 {
                    LabeledContent("Keys kept", value: String(summary.keyChanges))
                }
            }
            if summary.keyChanges > 0 {
                Section {
                    Text("For \(summary.keyChanges) of these people the export carried a different key. The key pinned on this iPhone stays; their card was not replaced.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func run() {
        guard let data = model.pendingImport else { return }
        let mode = mode
        let passphrase = passphrase
        ranMode = mode
        working = true
        problem = nil
        Task {
            do {
                summary = try await model.importData(data, passphrase: passphrase, mode: mode)
            } catch {
                let failure = AppError(error)
                if failure == .wrongPassphrase {
                    problem = "Wrong passphrase, or the file was changed. Check the words and try again."
                } else {
                    problem = failure.message
                }
            }
            working = false
        }
    }
}
