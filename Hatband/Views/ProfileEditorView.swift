import Foundation
import HatbandCore
import PhotosUI
import SwiftUI
import UIKit

/// The canonical profile, or an alias persona's own. Every field commits
/// through `Normalize` and `FieldValidator`: nothing is stored until it
/// normalises, and warnings stay on screen. Lives inside whatever stack
/// presents it.
@MainActor struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Nil for the canonical profile, saved through the model; otherwise
    /// the alias profile, handed back through `onDone`.
    private let alias: Profile?
    private let onDone: ((Profile) -> Void)?
    @State private var draft = ProfileDraft()
    @State private var loaded = false
    @State private var problems: [String: String] = [:]
    @State private var warnings: [String: String] = [:]
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var saving = false

    init() {
        alias = nil
        onDone = nil
    }

    init(alias: Profile, onDone: @escaping (Profile) -> Void) {
        self.alias = alias
        self.onDone = onDone
    }

    var body: some View {
        Form {
            identitySection
            channelsSection
            keysSection
            customSection
        }
        .navigationTitle(alias == nil ? "Profile" : "Alias")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    done()
                }
                .disabled(saving)
            }
        }
        .onAppear {
            if !loaded {
                draft = ProfileDraft(profile: alias ?? model.profile)
                loaded = true
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            load(item)
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Name") {
            field("Name", text: $draft.name, key: "name", content: .name)
            field("Company", text: $draft.company, key: "company", content: .organizationName)
            photoRow
        }
    }

    private var channelsSection: some View {
        Section("Channels") {
            field("Phone, +353 87 123 4567", text: $draft.phone, key: "phone", content: .telephoneNumber, keyboard: .phonePad)
            field("Email", text: $draft.email, key: "email", content: .emailAddress, keyboard: .emailAddress, lowercase: true)
            field("Website", text: $draft.website, key: "website", content: .URL, keyboard: .URL, lowercase: true)
            field("GitHub user or URL", text: $draft.github, key: "github", lowercase: true)
            field("LinkedIn slug or URL", text: $draft.linkedin, key: "linkedin", lowercase: true)
            field("Mastodon, @user@instance", text: $draft.mastodon, key: "mastodon", lowercase: true)
            field("Signal link, signal.me/#…", text: $draft.signal, key: "signal", keyboard: .URL, lowercase: true)
            if let warning = signalWarning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            field("Calendly path or URL", text: $draft.calendly, key: "calendly", lowercase: true)
        }
    }

    private var keysSection: some View {
        Section {
            TextField("SSH public key line", text: $draft.ssh, axis: .vertical)
                .font(Theme.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            note(for: "ssh")
            if let stored = draft.storedSSH, draft.ssh.isEmpty {
                HStack {
                    Text("RSA key, stored as " + SSHPublicKey.fingerprintString(sha256: stored.bytes))
                        .font(.footnote)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        draft.storedSSH = nil
                    }
                    .buttonStyle(.borderless)
                }
            }
            TextField("GPG fingerprint", text: $draft.gpgFingerprint)
                .font(Theme.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            note(for: "gpgFingerprint")
            TextField("GPG public key, armored", text: $draft.gpgKey, axis: .vertical)
                .font(Theme.mono)
                .lineLimit(2...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            note(for: "gpgKey")
            if let key = draft.storedGPGKey, draft.gpgKey.isEmpty {
                HStack {
                    Text("Key on file, \(key.count) bytes")
                        .font(.footnote)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        draft.storedGPGKey = nil
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Keys")
        } footer: {
            Text("Ed25519 and ECDSA keys go in the code; RSA travels as a fingerprint. A GPG key is kept only when it hashes to the fingerprint, and rides in file and link shares.")
        }
    }

    private var customSection: some View {
        Section {
            ForEach($draft.custom) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Label", text: $item.label)
                        Picker("Kind", selection: $item.kind) {
                            ForEach(CustomKind.allCases, id: \.self) { kind in
                                Text(ProfileEditorView.kindName(kind)).tag(kind)
                            }
                        }
                        .labelsHidden()
                    }
                    TextField("Value", text: $item.value, axis: .vertical)
                        .textInputAutocapitalization(item.kind == .text ? nil : TextInputAutocapitalization.never)
                        .autocorrectionDisabled(item.kind != .text)
                    note(for: "custom-\(item.id.uuidString)")
                }
            }
            .onDelete { offsets in
                draft.custom.remove(atOffsets: offsets)
            }
            Button {
                draft.custom.append(ProfileDraft.CustomDraft(id: UUID(), label: "", value: "", kind: .text))
            } label: {
                Label("Add field", systemImage: "plus")
            }
            note(for: "custom")
        } header: {
            Text("Custom fields")
        } footer: {
            Text("Up to \(Limits.file.customFields) fields, labels to 24 bytes. A QR code carries values to 128 bytes; files and links to 1024.")
        }
    }

    // MARK: - Pieces

    @ViewBuilder private func field(_ title: String, text: Binding<String>, key: String,
                                    content: UITextContentType? = nil, keyboard: UIKeyboardType = .default,
                                    lowercase: Bool = false) -> some View {
        TextField(title, text: text)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(lowercase ? TextInputAutocapitalization.never : nil)
            .autocorrectionDisabled(lowercase)
        note(for: key)
    }

    @ViewBuilder private func note(for key: String) -> some View {
        if let problem = problems[key] {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(.red)
        } else if let warning = warnings[key] {
            Text(warning)
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var photoRow: some View {
        HStack(spacing: 12) {
            if let photo = draft.photo, let image = UIImage(data: Data(photo)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            }
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label(draft.photo == nil ? "Choose photo" : "Change photo", systemImage: "person.crop.square")
            }
            .buttonStyle(.borderless)
            if draft.photo != nil {
                Spacer()
                Button("Remove", role: .destructive) {
                    draft.photo = nil
                }
                .buttonStyle(.borderless)
            }
        }
        note(for: "photo")
        Text("Never in a QR code; carried by file and link shares, at most 256 pixels and 12 KB, stripped of camera data.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// Shown whenever the link is the phone form, whether or not the
    /// phone field is filled in.
    private var signalWarning: String? {
        guard let link = try? SignalLink.parse(draft.signal), link.disclosesPhoneNumber else { return nil }
        return "This Signal link contains your phone number. Anyone who scans the card gets it, even when the phone field is left out."
    }

    static func kindName(_ kind: CustomKind) -> String {
        switch kind {
        case .text: return "Text"
        case .url: return "Link"
        case .email: return "Email"
        case .phone: return "Phone"
        case .key: return "Key"
        }
    }

    // MARK: - Actions

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    problems["photo"] = "That photo could not be read."
                    pickedPhoto = nil
                    return
                }
                guard let jpeg = Photo.thumbnailJPEG(from: data),
                      FieldValidator.photo(byteCount: jpeg.count, limits: .file).isAccepted
                else {
                    problems["photo"] = "That photo could not be made small enough."
                    pickedPhoto = nil
                    return
                }
                draft.photo = jpeg
                problems["photo"] = nil
            } catch {
                problems["photo"] = "That photo could not be read."
            }
            pickedPhoto = nil
        }
    }

    private func done() {
        let result = draft.commit()
        problems = result.problems
        warnings = result.warnings
        guard let profile = result.profile else { return }
        if let onDone {
            onDone(profile)
            dismiss()
            return
        }
        saving = true
        Task {
            do {
                try await model.saveProfile(profile)
                dismiss()
            } catch {
                model.error = AppError(error)
            }
            saving = false
        }
    }
}

/// The editor's text, and the profile it commits to.
nonisolated struct ProfileDraft: Equatable {
    struct CustomDraft: Identifiable, Equatable {
        let id: UUID
        var label: String
        var value: String
        var kind: CustomKind
    }

    struct Commit {
        /// Nil while any field has a problem.
        var profile: Profile?
        var problems: [String: String]
        var warnings: [String: String]
    }

    var name = ""
    var company = ""
    var phone = ""
    var email = ""
    var website = ""
    var github = ""
    var linkedin = ""
    var mastodon = ""
    var signal = ""
    var calendly = ""
    var ssh = ""
    var gpgFingerprint = ""
    var gpgKey = ""
    var photo: [UInt8]?
    var custom: [CustomDraft] = []
    /// An RSA key has no line to show; it stays here until removed.
    var storedSSH: SSHKeyField?
    /// The certificate already on file, kept until removed or replaced.
    var storedGPGKey: [UInt8]?

    init() {}

    init(profile: Profile) {
        name = profile.name ?? ""
        company = profile.company ?? ""
        phone = profile.phone ?? ""
        email = profile.email ?? ""
        if let site = profile.website {
            website = site.insecure ? "http://" + site.address : site.address
        }
        github = profile.github ?? ""
        linkedin = profile.linkedin ?? ""
        mastodon = profile.mastodon ?? ""
        calendly = profile.calendly ?? ""
        switch profile.signal {
        case .username(let bytes)?:
            signal = (try? SignalLink(username: bytes))?.url ?? ""
        case .phone(let number)?:
            signal = (try? SignalLink(phone: number))?.url ?? ""
        case nil:
            break
        }
        if let field = profile.ssh {
            if let line = Links.authorizedKeysLine(field) {
                ssh = line
            } else {
                storedSSH = field
            }
        }
        if let bytes = profile.gpgFingerprint {
            gpgFingerprint = (try? GPGFingerprint(bytes: bytes))?.formatted ?? ""
        }
        storedGPGKey = profile.gpgKey
        photo = profile.photo
        custom = profile.custom.map { CustomDraft(id: UUID(), label: $0.label, value: $0.value, kind: $0.kind) }
    }

    /// The profile the fields describe, or what is wrong with them, field
    /// by field. A blank field is an absent one.
    func commit() -> Commit {
        var profile = Profile()
        var problems: [String: String] = [:]
        var warnings: [String: String] = [:]

        func apply(_ verdict: Verdict, _ key: String) -> Bool {
            switch verdict {
            case .ok:
                return true
            case .warning(let text):
                warnings[key] = text
                return true
            case .reject(let text):
                problems[key] = text
                return false
            }
        }

        let trimmedName = ProfileDraft.trim(name)
        if trimmedName.isEmpty {
            problems["name"] = "A name is needed."
        } else if apply(FieldValidator.name(trimmedName, limits: .file), "name") {
            profile.name = trimmedName
        }
        let trimmedCompany = ProfileDraft.trim(company)
        if !trimmedCompany.isEmpty, apply(FieldValidator.company(trimmedCompany, limits: .file), "company") {
            profile.company = trimmedCompany
        }
        if !ProfileDraft.trim(phone).isEmpty {
            do {
                profile.phone = try Normalize.phone(phone)
            } catch {
                problems["phone"] = ProfileDraft.describe(error)
            }
        }
        if !ProfileDraft.trim(email).isEmpty {
            do {
                profile.email = try Normalize.email(email)
            } catch {
                problems["email"] = ProfileDraft.describe(error)
            }
        }
        if !ProfileDraft.trim(website).isEmpty {
            do {
                let site = try Normalize.website(website)
                profile.website = Website(address: site.address, insecure: site.insecure)
                if site.insecure {
                    warnings["website"] = "Reachable only over http; the card says so."
                }
            } catch {
                problems["website"] = ProfileDraft.describe(error)
            }
        }
        if !ProfileDraft.trim(github).isEmpty {
            do {
                profile.github = try Normalize.github(github)
            } catch {
                problems["github"] = ProfileDraft.describe(error)
            }
        }
        if !ProfileDraft.trim(linkedin).isEmpty {
            do {
                profile.linkedin = try Normalize.linkedin(linkedin)
            } catch {
                problems["linkedin"] = ProfileDraft.describe(error)
            }
        }
        if !ProfileDraft.trim(mastodon).isEmpty {
            do {
                profile.mastodon = try Normalize.mastodon(mastodon)
            } catch {
                problems["mastodon"] = ProfileDraft.describe(error)
            }
        }
        if !ProfileDraft.trim(calendly).isEmpty {
            do {
                profile.calendly = try Normalize.calendly(calendly)
            } catch {
                problems["calendly"] = ProfileDraft.describe(error)
            }
        }
        if !ProfileDraft.trim(signal).isEmpty {
            do {
                let link = try SignalLink.parse(signal)
                switch link.kind {
                case .username(let bytes):
                    profile.signal = .username(bytes)
                case .phone(let number):
                    profile.signal = .phone(number)
                }
            } catch {
                problems["signal"] = ProfileDraft.describe(error)
            }
        }

        if !ProfileDraft.trim(ssh).isEmpty {
            do {
                let key = try SSHPublicKey(line: ssh)
                profile.ssh = SSHKeyField(kind: key.kind.rawValue, bytes: key.storedBytes)
            } catch {
                problems["ssh"] = ProfileDraft.describeSSH(error)
            }
        } else {
            profile.ssh = storedSSH
        }

        var fingerprint: [UInt8]?
        if !ProfileDraft.trim(gpgFingerprint).isEmpty {
            do {
                fingerprint = try Normalize.gpgFingerprint(gpgFingerprint).bytes
                profile.gpgFingerprint = fingerprint
            } catch {
                problems["gpgFingerprint"] = ProfileDraft.describe(error)
            }
        }
        var certificate = storedGPGKey
        if !ProfileDraft.trim(gpgKey).isEmpty {
            certificate = OpenPGP.dearmor(gpgKey)
            if certificate == nil {
                problems["gpgKey"] = "Not an armored OpenPGP public key."
            }
        }
        if let certificate, apply(FieldValidator.gpgKey(byteCount: certificate.count, limits: .file), "gpgKey"),
           problems["gpgFingerprint"] == nil {
            if let fingerprint {
                if OpenPGP.fingerprint(ofCertificate: certificate) == fingerprint {
                    profile.gpgKey = certificate
                } else {
                    problems["gpgKey"] = "This key does not hash to the fingerprint above."
                }
            } else {
                problems["gpgKey"] = "Enter the key's fingerprint first."
            }
        }

        if let photo, apply(FieldValidator.photo(byteCount: photo.count, limits: .file), "photo") {
            profile.photo = photo
        }

        _ = apply(FieldValidator.customCount(custom.count, limits: .file), "custom")
        var fields: [CustomField] = []
        for item in custom {
            let key = "custom-\(item.id.uuidString)"
            let label = ProfileDraft.trim(item.label)
            var value = ProfileDraft.trim(item.value)
            guard apply(FieldValidator.customLabel(label, limits: .file), key) else { continue }
            if item.kind == .phone, let number = try? Normalize.phone(value) {
                value = number
            }
            if item.kind == .email, let address = try? Normalize.email(value) {
                value = address
            }
            guard apply(FieldValidator.customValue(value, kind: item.kind, limits: .file), key) else { continue }
            fields.append(CustomField(label: label, value: value, kind: item.kind))
        }
        profile.custom = fields

        return Commit(profile: problems.isEmpty ? profile : nil, problems: problems, warnings: warnings)
    }

    // MARK: - Words

    static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func describe(_ error: any Error) -> String {
        guard let error = error as? Normalize.Error else { return String(describing: error) }
        switch error {
        case .empty: return "Empty."
        case .invalidCharacter(let character): return "Cannot contain “\(character)”."
        case .missingPlus: return "Start with + and the country code."
        case .invalidCountryCode: return "The country code cannot start with 0."
        case .tooShort: return "Too short."
        case .tooLong: return "Too long."
        case .missingAt: return "Needs an @."
        case .multipleAt: return "Only one @."
        case .invalidLocalPart: return "The part before the @ is not valid."
        case .invalidHost: return "Not a valid host name."
        case .unsupportedScheme(let scheme): return "\(scheme): links are not allowed."
        case .userinfo: return "No user name or password in a link."
        case .wrongHost(let host): return "Not the site expected here: \(host)."
        case .invalidUsername: return "Not a valid user name."
        case .invalidPath: return "Not a valid path."
        case .invalidHex: return "Hex digits only, an even number of them."
        case .wrongLength(let count): return "Wrong length: \(count)."
        }
    }

    static func describeSSH(_ error: any Error) -> String {
        guard let error = error as? SSHPublicKey.Error else { return String(describing: error) }
        switch error {
        case .malformedLine: return "Paste the whole line: type, base64 and comment."
        case .invalidBase64: return "The key data is not valid base64."
        case .optionsNotSupported: return "Remove the options before the key type."
        case .unsupportedType(let type): return "\(type) keys are not supported."
        case .securityKey: return "Security-key (FIDO) keys cannot be carried on a card."
        case .typeMismatch: return "The type does not match the key data."
        case .malformedBlob: return "The key data is malformed."
        case .wrongKeyLength(let count): return "Wrong key length: \(count) bytes."
        case .invalidPoint: return "The key is not a point on its curve."
        case .trailingBytes: return "The key data has trailing bytes."
        case .notInlinable: return "RSA keys travel as a fingerprint only."
        }
    }
}
