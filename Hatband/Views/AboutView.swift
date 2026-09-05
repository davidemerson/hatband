import Foundation
import SwiftUI

/// Version and commit, the proofs, the license, MetricKit diagnostics kept
/// on the phone, and the Bloomsday line. With `PersonView`, the only place
/// that opens a URL.
@MainActor struct AboutView: View {
    static let repository = "https://github.com/davidemerson/hatband"
    static let bloomsday = "A card in the hatband, as on 16 June 1904."

    @Environment(\.openURL) private var openURL
    @State private var diagnostics: [URL] = []

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: Theme.hat)
                        .font(.largeTitle)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("Hatband")
                            .font(.headline)
                        MonoText(AboutView.build())
                    }
                }
                Text("A business card in your hat. No account, no server, nothing collected.")
                    .foregroundStyle(.secondary)
            }
            Section("Source and proofs, on github.com") {
                link("Source code", AboutView.repository)
                link("Wire format, in the README", AboutView.repository + "#wire-format-hb1")
                link("Security and threat model, in the README", AboutView.repository + "#security")
                link("Report a vulnerability privately", AboutView.repository + "/security/advisories/new")
                link("Sponsor the work", "https://github.com/sponsors/davidemerson")
            }
            Section("License") {
                Text("GPL-3.0-or-later, with permission to distribute through the App Store (COPYING.iOS). The format library is Apache-2.0; the wire format is CC-BY-4.0.")
                link("Read the license on github.com", AboutView.repository + "/blob/main/LICENSE")
            }
            Section {
                if diagnostics.isEmpty {
                    Text("None.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diagnostics, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent)
                                .font(Theme.mono)
                                .lineLimit(1)
                            Spacer()
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            Diagnostics.delete(diagnostics[offset])
                        }
                        diagnostics = Diagnostics.files()
                    }
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Crash and hang reports iOS hands to Hatband. They stay here, in full, until you share or delete them; nothing is sent on its own.")
            }
            Section {
                Text(AboutView.bloomsday)
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .navigationTitle("About")
        .onAppear {
            Diagnostics.subscribe()
            diagnostics = Diagnostics.files()
        }
    }

    private func link(_ title: String, _ address: String) -> some View {
        Button {
            if let url = URL(string: address) {
                openURL(url)
            }
        } label: {
            Label(title, systemImage: "arrow.up.right")
        }
    }

    /// `<version> (<commit>)` from Info.plist; `HatbandCommit` is set by
    /// the build (`dev` outside CI).
    nonisolated static func build() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let commit = info["HatbandCommit"] as? String ?? "dev"
        return version + " (" + commit + ")"
    }
}

/// What leaves your phone: `TrustFacts.egress`, each on a tap that names
/// its host, and what never happens.
@MainActor struct TrustView: View {
    var body: some View {
        List {
            Section {
                Text("Hatband has no server and no account. Nothing leaves this iPhone unless you tap a button that names where it goes. These are all of them.")
                    .foregroundStyle(.secondary)
            }
            Section("Only when you tap") {
                ForEach(Array(TrustFacts.egress.enumerated()), id: \.offset) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.element.host)
                            .font(Theme.mono)
                        Text(entry.element.when)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Never") {
                Text("No analytics, no crash reporting service, no push notifications, no iCloud. A card travels inside a QR code or a file; when someone without the app scans you, their browser reads the card from the link's fragment, which browsers never send to hatband.link.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("What leaves your phone")
    }
}
