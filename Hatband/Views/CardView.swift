import HatbandCore
import SwiftUI

/// The Card tab: the full-QR code of the selected persona in a white
/// panel, its meter, and the doors to scanning, sharing, printing, the
/// Lock Screen and the inspector.
@MainActor struct CardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Read from `Screen.isCaptured` on appear and on every scene change.
    @State private var captured = false

    var body: some View {
        let shown = rendered()
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    personaMenu
                    panel(shown)
                    details(shown)
                    Text("Only the person who scans you keeps a record of this meeting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .background(Theme.ground)
            .navigationTitle("Card")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.route.sheet = .scan
                    } label: {
                        Label("Scan", systemImage: "qrcode.viewfinder")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    shareMenu(shown)
                    Button {
                        model.route.sheet = .print
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    Button {
                        model.route.sheet = .sharing
                    } label: {
                        Label("Lock Screen", systemImage: "lock.iphone")
                    }
                    Button {
                        model.route.sheet = .inspector
                    } label: {
                        Label("Inspector", systemImage: "info.circle")
                    }
                }
            }
        }
        .onAppear {
            captured = Screen.isCaptured
            Screen.raiseBrightness()
        }
        .onDisappear {
            Screen.restoreBrightness()
        }
        .onChange(of: scenePhase) { _, _ in
            captured = Screen.isCaptured
        }
        .sheet(item: sheet) { which in
            presented(which)
        }
    }

    // MARK: - Pieces

    private var selected: Persona? {
        model.selectedPersona
    }

    private var personaMenu: some View {
        Menu {
            ForEach(model.personas, id: \.id) { persona in
                Button {
                    model.select(persona)
                } label: {
                    Label(persona.label, systemImage: persona.isAlias ? Theme.flower : Theme.hat)
                }
            }
            Divider()
            Button("Personas…") {
                model.route.sheet = .personas
            }
            Button("Profile…") {
                model.route.sheet = .profile
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected?.isAlias == true ? Theme.flower : Theme.hat)
                    .foregroundStyle(Theme.personaColor(selected?.color ?? 0))
                Text(selected?.label ?? "Persona")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .foregroundStyle(Theme.ink)
        }
    }

    /// The white panel: the code, a cover while the screen is captured,
    /// or the reason there is no code.
    private func panel(_ shown: Rendered) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(.white)
            if captured {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.title)
                    Text("Hidden while the screen is recorded or mirrored.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.black)
                .padding()
            } else if let code = shown.code {
                QRShape(code: code)
                    .fill(.black)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(12)
                    .accessibilityLabel("Your card as a QR code")
            } else {
                Text(shown.problem ?? "This card is too big for a QR code. Share it as a file.")
                    .font(.footnote)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 360)
    }

    private func details(_ shown: Rendered) -> some View {
        VStack(spacing: 4) {
            if let name = shown.card?.name {
                Text(name)
                    .font(.title3.bold())
            }
            if let company = shown.card?.company {
                Text(company)
                    .foregroundStyle(.secondary)
            }
            if let budget = shown.budget {
                ByteMeter(budget: budget, form: .fullQR)
            }
        }
    }

    /// The link form as text, and the `.hatband` file.
    private func shareMenu(_ shown: Rendered) -> some View {
        Menu {
            if let persona = selected, let url = try? model.url(for: persona, form: .file),
               let bytes = try? model.fileBytes(for: persona) {
                ShareLink(item: url) {
                    Label("Share as link", systemImage: "link")
                }
                ShareLink(item: CardFile(bytes: bytes, name: CardView.fileBase(shown.card?.name ?? persona.label) + ".hatband"),
                          preview: SharePreview("Hatband card")) {
                    Label("Share as file", systemImage: "doc")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder private func presented(_ sheet: Sheet) -> some View {
        switch sheet {
        case .scan:
            ScanView()
        case .sharing:
            SharingSheet()
        case .inspector:
            InspectorView()
        case .print:
            PrintSheet()
        case .profile:
            NavigationStack {
                ProfileEditorView()
            }
        case .personas:
            NavigationStack {
                PersonaListView()
            }
        case .about, .importFile:
            EmptyView()
        }
    }

    /// Only the Card tab presents these sheets; dismissing clears the route.
    private var sheet: Binding<Sheet?> {
        Binding(
            get: { model.route.tab == .card ? model.route.sheet : nil },
            set: { value in
                if value == nil {
                    model.route.sheet = nil
                }
            })
    }

    // MARK: - Rendering

    struct Rendered {
        var card: Card?
        var code: QRCode?
        var budget: Budget?
        var problem: String?
    }

    /// The full-QR card of the selected persona and its code.
    private func rendered() -> Rendered {
        guard let persona = selected else { return Rendered(problem: "Add a persona to show a card.") }
        do {
            let card = try model.card(for: persona, form: .fullQR)
            let code = try Budget.qrCode(for: card, form: .fullQR)
            return Rendered(card: card, code: code, budget: Budget(card: card), problem: nil)
        } catch {
            return Rendered(problem: AppError(error).message)
        }
    }

    /// A file name from a card name: slashes and colons become dashes.
    static func fileBase(_ name: String) -> String {
        let cleaned = String(name.map { $0 == "/" || $0 == ":" ? "-" : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "card" : cleaned
    }
}

/// SVG, PNG and PDF of the code on show, rendered once when the sheet
/// appears and offered through the share sheet.
@MainActor private struct PrintSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var files: Files?
    @State private var problem: String?

    private struct Files {
        var svg: SVGFile
        var png: PNGFile?
        var pdf: PDFFile?
    }

    var body: some View {
        NavigationStack {
            List {
                if let files {
                    Section {
                        ShareLink(item: files.svg, preview: SharePreview("SVG")) {
                            Label("SVG", systemImage: "square.on.square")
                        }
                        if let png = files.png {
                            ShareLink(item: png, preview: SharePreview("PNG")) {
                                Label("PNG, 1024 pixels", systemImage: "photo")
                            }
                        }
                        if let pdf = files.pdf {
                            ShareLink(item: pdf, preview: SharePreview("PDF card")) {
                                Label("PDF card", systemImage: "doc.richtext")
                            }
                        }
                    } footer: {
                        Text("Rendered on this iPhone. Each file carries the full signed card.")
                    }
                } else if let problem {
                    Text(problem)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Print")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            render()
        }
    }

    private func render() {
        guard files == nil else { return }
        guard let persona = model.selectedPersona else {
            problem = "Add a persona to print a card."
            return
        }
        do {
            let card = try model.card(for: persona, form: .fullQR)
            guard let code = try Budget.qrCode(for: card, form: .fullQR) else {
                problem = "This card is too big for a QR code. Share it as a file instead."
                return
            }
            let base = CardView.fileBase(card.name ?? persona.label)
            let png = PrintExport.png(code).map { PNGFile(bytes: $0, name: base + ".png") }
            let pdf = PrintExport.pdf(code: code, name: card.name, company: card.company, color: card.color)
                .map { PDFFile(bytes: $0, name: base + ".pdf") }
            files = Files(svg: SVGFile(bytes: PrintExport.svg(code), name: base + ".svg"), png: png, pdf: pdf)
        } catch {
            problem = AppError(error).message
        }
    }
}
