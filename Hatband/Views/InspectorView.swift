import HatbandCore
import SwiftUI

/// "What's in this QR": every field of the exact card on the Card tab,
/// its envelope, and its size.
@MainActor struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The card on show, rebuilt when `inspectedKey` changes and never in
    /// `body`: building it reads the seed and signs.
    @State private var shown: MeasuredCard?

    var body: some View {
        NavigationStack {
            List {
                if model.selectedPersona == nil {
                    Text("Add a persona to show a card.")
                } else if let shown {
                    sections(shown)
                }
            }
            .grounded()
            .navigationTitle("What's in this QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: inspectedKey, initial: true) { _, _ in
            shown = model.selectedPersona.map { model.measure($0, form: .fullQR) }
        }
    }

    /// What the shown card depends on; nil without a persona.
    private var inspectedKey: BudgetKey? {
        model.selectedPersona.map { model.budgetKey(for: $0) }
    }

    @ViewBuilder private func sections(_ shown: MeasuredCard) -> some View {
        if let card = shown.card {
            Section("Fields") {
                if let name = card.name {
                    row("Name", name)
                }
                if let company = card.company {
                    row("Company", company)
                }
                ForEach(Links.rows(for: card)) { link in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if link.mono {
                            MonoText(link.text)
                        } else {
                            Text(link.text)
                        }
                        if let domain = link.domain {
                            Text(domain)
                                .font(.caption2)
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                }
            }
            Section("Envelope") {
                row("Persona id", Hex.string(card.personaID), mono: true)
                row("Issued", InspectorView.civil(card.issuedDay), mono: true)
                row("Sequence", String(card.seq))
                row("Colour", Palette.color(at: card.color).name)
                if card.flags.contains(.alias) {
                    row("Alias", "This card belongs to an alias persona.")
                }
                if card.flags.contains(.photoAvailable) {
                    row("Photo", "Not in the code; carried by file and link shares.")
                }
                if let key = card.publicKey {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signing key fingerprint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FingerprintText(bytes: KeyFingerprint(publicKey: key)?.full ?? key)
                    }
                }
                row("Signature", card.signatureIsValid ? "Valid, made on this iPhone." : "None.")
            }
            Section("Size") {
                if let budget = shown.budget {
                    row("Bytes", String(budget.bytes))
                    row("Characters in the link", String(budget.characters))
                    row("QR version", budget.version.map { String($0) } ?? "Too big for any QR code.")
                    ByteMeter(budget: budget, form: .fullQR)
                }
            }
        } else {
            Text(shown.problem?.message ?? "No card.")
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if mono {
                MonoText(value)
            } else {
                Text(value)
            }
        }
    }

    /// `issuedDay` as `yyyy-mm-dd`.
    static func civil(_ day: UInt32) -> String {
        let date = Day.civil(Int(day))
        let month = date.month < 10 ? "0\(date.month)" : "\(date.month)"
        let dayText = date.day < 10 ? "0\(date.day)" : "\(date.day)"
        return "\(date.year)-\(month)-\(dayText)"
    }
}
