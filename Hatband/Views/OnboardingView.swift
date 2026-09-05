import Contacts
import HatbandCore
import SwiftUI
import UniformTypeIdentifiers

/// "Name and address?": type it in, pick from Contacts, or restore from an
/// export. Continue calls `finishOnboarding`.
@MainActor struct OnboardingView: View {
    private enum Door {
        case type
    }

    @Environment(AppModel.self) private var model
    @State private var profile = Profile()
    @State private var door: Door?
    @State private var name = ""
    @State private var company = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var problem: String?
    @State private var appLock = false
    @State private var pickingContact = false
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Name and address?")
                        .font(.title2.bold())
                    Text("Only what you choose goes on your card, and it stays on this iPhone.")
                        .foregroundStyle(.secondary)
                }
                Section("Start with") {
                    Button("Type it in") {
                        door = .type
                    }
                    Button("Pick from Contacts") {
                        pickingContact = true
                    }
                    Button("Restore from export") {
                        importing = true
                    }
                }
                if door == .type {
                    Section("Your card") {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                        TextField("Company", text: $company)
                            .textContentType(.organizationName)
                        TextField("Phone, +353 87 123 4567", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    }
                }
                Section {
                    Toggle("Lock scanned people behind Face ID or passcode", isOn: $appLock)
                } footer: {
                    Text("Showing your own card never asks.")
                }
                Section {
                    Button("Continue") {
                        finish()
                    }
                    .disabled(door == nil)
                    if let problem {
                        Text(problem)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Hatband")
        }
        .onAppear {
            appLock = model.canUseAppLock()
        }
        .sheet(isPresented: $pickingContact) {
            ContactPicker { contact in
                profile = ContactImport.profile(from: contact, into: profile)
                name = profile.name ?? ""
                company = profile.company ?? ""
                phone = profile.phone ?? ""
                email = profile.email ?? ""
                door = .type
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.hatbandExport]) { result in
            restore(result)
        }
    }

    private func finish() {
        guard let committed = committedProfile() else { return }
        do {
            try model.finishOnboarding(profile: committed, appLock: appLock)
        } catch {
            model.error = AppError(error)
        }
    }

    /// The typed fields over whatever Contacts supplied, each normalised.
    private func committedProfile() -> Profile? {
        var result = profile
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, FieldValidator.name(trimmedName, limits: .file).isAccepted else {
            problem = "A name is needed, up to 64 bytes."
            return nil
        }
        result.name = trimmedName
        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCompany.isEmpty {
            result.company = nil
        } else {
            guard FieldValidator.company(trimmedCompany, limits: .file).isAccepted else {
                problem = "The company name is too long."
                return nil
            }
            result.company = trimmedCompany
        }
        if phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.phone = nil
        } else {
            guard let normalized = try? Normalize.phone(phone) else {
                problem = "Check the phone number. Use the international form, starting with +."
                return nil
            }
            result.phone = normalized
        }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.email = nil
        } else {
            guard let normalized = try? Normalize.email(email) else {
                problem = "Check the email address."
                return nil
            }
            result.email = normalized
        }
        problem = nil
        return result
    }

    private func restore(_ result: Result<URL, any Error>) {
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
