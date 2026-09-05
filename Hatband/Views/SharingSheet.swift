import HatbandCore
import SwiftUI

/// Start or stop the Lock Screen card: a duration, the name and Always-On
/// toggles (persisted in settings), what the compact card carries, and
/// its meter.
@MainActor struct SharingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 120
    @State private var showName = true
    @State private var alwaysOn = false
    @State private var working = false
    @State private var problem: String?
    /// What the compact card carries, rebuilt when `summaryKey` changes
    /// and never in `body`: building it reads the seed.
    @State private var summary: Summary?

    var body: some View {
        NavigationStack {
            Form {
                Section("For how long") {
                    Picker("Duration", selection: $minutes) {
                        Text("30 min").tag(30)
                        Text("2 hours").tag(120)
                        Text("8 hours").tag(480)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Show my name", isOn: $showName)
                    Toggle("Keep the code on the Always-On display", isOn: $alwaysOn)
                } footer: {
                    Text("The card on the Lock Screen is compact: your name, up to two channels and your key fingerprint. Choose the channels in the persona editor.")
                }
                Section("Lock Screen card") {
                    if model.selectedPersona == nil {
                        Text("Add a persona first.")
                    } else if let summary {
                        summaryRows(summary)
                    }
                }
                Section {
                    if let sharing = model.sharing {
                        Text("Sharing until \(Text(sharing.endsAt, style: .time).font(Theme.mono))")
                        Button("Stop sharing", role: .destructive) {
                            stop()
                        }
                        .disabled(working)
                    } else {
                        Button(working ? "Starting…" : "Show on Lock Screen") {
                            start()
                        }
                        .disabled(working || model.selectedPersona == nil)
                    }
                    if let problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Sharing starts and stops only from here. The card leaves the Lock Screen when the time is up.")
                }
            }
            .grounded()
            .navigationTitle("Lock Screen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let stored = model.settings.durationMinutes
            minutes = [30, 120, 480].contains(stored) ? stored : 120
            showName = model.settings.showNameOnLockScreen
            alwaysOn = model.settings.alwaysOnQR
        }
        .onChange(of: summaryKey, initial: true) { _, _ in
            summary = model.selectedPersona.map { measure($0) }
        }
        .onChange(of: showName) { _, value in
            if model.settings.showNameOnLockScreen != value {
                model.settings.showNameOnLockScreen = value
                persist()
                Task { await model.updateSharingActivity() }
            }
        }
        .onChange(of: alwaysOn) { _, value in
            if model.settings.alwaysOnQR != value {
                model.settings.alwaysOnQR = value
                persist()
                Task { await model.updateSharingActivity() }
            }
        }
        .onChange(of: minutes) { _, value in
            if model.settings.durationMinutes != value {
                model.settings.durationMinutes = value
                persist()
            }
        }
    }

    // MARK: - Pieces

    private struct Summary {
        var channels: [String] = []
        var budget: Budget?
        var problem: String?
    }

    @ViewBuilder private func summaryRows(_ digest: Summary) -> some View {
        if let problem = digest.problem {
            Text(problem)
                .foregroundStyle(.red)
        } else {
            Text(showName ? "Name shown" : "Name hidden")
            Text(digest.channels.isEmpty ? "No channels" : "Channels: " + digest.channels.joined(separator: ", "))
                .foregroundStyle(.secondary)
            if let budget = digest.budget {
                ByteMeter(budget: budget, form: .lockScreen, compact: true)
            }
        }
    }

    /// What the compact card depends on; nil without a persona.
    private var summaryKey: BudgetKey? {
        model.selectedPersona.map { model.budgetKey(for: $0) }
    }

    /// What the trimmed compact card carries, and its meter.
    private func measure(_ persona: Persona) -> Summary {
        let measured = model.measure(persona, form: .lockScreen)
        guard let card = measured.card, let budget = measured.budget else {
            return Summary(problem: (measured.problem ?? .tooBigForLockScreen).message)
        }
        return Summary(channels: Links.rows(for: card).map { $0.label }, budget: budget, problem: nil)
    }

    private func persist() {
        Task {
            do {
                try await model.applyLockScreenPreferences()
            } catch {
                model.error = AppError(error)
            }
        }
    }

    private func start() {
        guard let persona = model.selectedPersona else { return }
        working = true
        problem = nil
        Task {
            do {
                try await model.startSharing(persona: persona, minutes: minutes)
            } catch {
                let mapped = AppError(error)
                if mapped == .activitiesDisabled {
                    problem = "Live Activities are off for Hatband. Turn them on in Settings › Hatband › Live Activities, then try again."
                } else {
                    problem = mapped.message
                }
            }
            working = false
        }
    }

    private func stop() {
        working = true
        problem = nil
        Task {
            await model.stopSharing()
            working = false
        }
    }
}
