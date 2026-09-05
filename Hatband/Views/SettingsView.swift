import Foundation
import HatbandCore
import SwiftUI
import UniformTypeIdentifiers

/// Protection, the card, export and import, erase, trust and about.
/// `LockedView` while locked.
@MainActor struct SettingsView: View {
    private enum Page: Hashable {
        case export, trust, about
    }

    @Environment(AppModel.self) private var model
    @State private var path: [Page] = []
    @State private var importing = false
    @State private var confirmingErase = false
    @State private var editingProfile = false
    @State private var editingPersonas = false

    var body: some View {
        if model.locked {
            LockedView()
        } else {
            NavigationStack(path: $path) {
                List {
                    ProtectionSections()
                    Section("Your card") {
                        Button("Profile") {
                            editingProfile = true
                        }
                        Button("Personas") {
                            editingPersonas = true
                        }
                    }
                    Section {
                        NavigationLink("Export", value: Page.export)
                        Button("Import from an export…") {
                            importing = true
                        }
                    } footer: {
                        Text("An export holds everything, sealed with a passphrase. Import one to restore a new iPhone or to merge an older copy into this one.")
                    }
                    Section {
                        Button("Erase everything", role: .destructive) {
                            confirmingErase = true
                        }
                    }
                    Section {
                        NavigationLink("What leaves your phone", value: Page.trust)
                        NavigationLink("About", value: Page.about)
                    }
                }
                .navigationTitle("Settings")
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .export:
                        ExportView()
                    case .trust:
                        TrustView()
                    case .about:
                        AboutView()
                    }
                }
                .sheet(isPresented: $editingProfile) {
                    ProfileEditorView()
                }
                .sheet(isPresented: $editingPersonas) {
                    PersonaListView()
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.hatbandExport]) { result in
                    receiveImport(result)
                }
                .confirmationDialog("Erase everything?", isPresented: $confirmingErase, titleVisibility: .visible) {
                    Button("Export first") {
                        path = [.export]
                    }
                    Button("Erase", role: .destructive) {
                        Task {
                            await model.eraseEverything()
                        }
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text("Your card, personas, signing seed and every person you have scanned leave this iPhone. People who scanned you keep their copy. There is no way back but an export made first.")
                }
            }
            .onAppear {
                Diagnostics.subscribe()
            }
        }
    }

    private func receiveImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                model.pendingImport = try Data(contentsOf: url)
            } catch {
                model.error = AppError(error)
            }
        case .failure(let error):
            model.error = AppError(error)
        }
    }
}

/// App lock, backup and the widget, each a toggle that goes through the
/// model and reports a refusal.
@MainActor private struct ProtectionSections: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.canUseAppLock() {
            Section {
                Toggle("App lock", isOn: appLock)
            } header: {
                Text("Protection")
            } footer: {
                Text("Face ID or your passcode before the people you have scanned. Showing your own card never asks.")
            }
        }
        Section {
            Toggle("Include in backup", isOn: includeInBackup)
        } footer: {
            Text("Puts the people you have scanned, and the key that opens them, into iCloud and computer backups. Apple can read an iCloud backup unless Advanced Data Protection is on for your account. Off, they exist on this iPhone alone.")
        }
        Section {
            Toggle("Home Screen widget", isOn: homeWidget)
        } footer: {
            Text("Your card on the Home Screen. The widget keeps a compact copy of it, readable once this iPhone has been unlocked since restart.")
        }
    }

    private var appLock: Binding<Bool> {
        Binding(
            get: { model.settings.appLock },
            set: { on in
                Task {
                    await apply {
                        try await model.setAppLock(on)
                    }
                }
            })
    }

    private var includeInBackup: Binding<Bool> {
        Binding(
            get: { model.settings.includeInBackup },
            set: { on in
                Task {
                    await apply {
                        try await model.setIncludeInBackup(on)
                    }
                }
            })
    }

    private var homeWidget: Binding<Bool> {
        Binding(
            get: { model.settings.homeWidget },
            set: { on in
                do {
                    try model.setHomeWidget(on)
                } catch {
                    model.error = AppError(error)
                }
            })
    }

    private func apply(_ change: () async throws -> Void) async {
        do {
            try await change()
        } catch {
            model.error = AppError(error)
        }
    }
}

/// A generated passphrase to copy, or a typed one of at least twelve
/// characters; then the sealed file to share.
@MainActor private struct ExportView: View {
    private static let minimumLength = 12

    @Environment(AppModel.self) private var model
    @State private var generated = Passphrase.generate()
    @State private var useOwn = false
    @State private var own = ""
    @State private var file: ExportFile?
    @State private var working = false

    private var passphrase: String {
        useOwn ? own : generated
    }

    private var ready: Bool {
        !useOwn || own.count >= ExportView.minimumLength
    }

    var body: some View {
        Form {
            Section {
                if useOwn {
                    SecureField("At least \(ExportView.minimumLength) characters", text: $own)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    MonoText(generated)
                    Button("Copy") {
                        Pasteboard.copy(generated)
                    }
                    Button("Other words") {
                        generated = Passphrase.generate()
                    }
                }
                Toggle("Use my own", isOn: $useOwn)
            } header: {
                Text("Passphrase")
            } footer: {
                Text("Write it down. The export opens only with this passphrase; there is no other way in, and no one to ask.")
            }
            Section {
                if let file {
                    ShareLink(item: file, preview: SharePreview(file.name)) {
                        Label("Save or send the export", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button(working ? "Sealing…" : "Create export") {
                        create()
                    }
                    .disabled(!ready || working)
                }
            } footer: {
                Text("Everything: your card, personas, signing seed, the people you have scanned and where you met them, sealed on this iPhone. Whoever has the file and the passphrase has all of it.")
            }
        }
        .navigationTitle("Export")
        .onChange(of: passphrase) {
            file = nil
        }
    }

    private func create() {
        let passphrase = passphrase
        working = true
        Task {
            do {
                let data = try await model.exportData(passphrase: passphrase)
                file = ExportFile(bytes: Array(data), name: ExportView.fileName(for: Date()))
            } catch {
                model.error = AppError(error)
            }
            working = false
        }
    }

    /// `Hatband-<date>.hatband-export`.
    nonisolated static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Hatband-" + formatter.string(from: date) + ".hatband-export"
    }
}
