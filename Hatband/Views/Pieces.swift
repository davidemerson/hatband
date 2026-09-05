import HatbandCore
import SwiftUI

/// Bytes, characters and QR version of a card, coloured by how close it
/// sits to the form's limit. Past the limit it says what to do instead.
@MainActor struct ByteMeter: View {
    let budget: Budget
    var form: CardForm = .fullQR
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(budget.bytes) B")
            if !compact {
                Text("\(budget.characters) chars")
            }
            Text(versionText)
        }
        .font(Theme.mono)
        .foregroundStyle(tone)
    }

    private var limit: Int {
        form == .lockScreen ? Budget.lockScreenMaxVersion : Budget.fullQRMaxVersion
    }

    private var versionText: String {
        guard let version = budget.version, version <= limit else {
            return form == .lockScreen ? "too big for the Lock Screen" : "share as a file"
        }
        return "QR v\(version)"
    }

    private var tone: Color {
        guard let version = budget.version, version <= limit else { return .red }
        if form == .lockScreen, version > 8 {
            return .orange
        }
        if form != .lockScreen, version > 20 {
            return .orange
        }
        return Theme.tertiary
    }
}

/// A list row with the `+` marker.
@MainActor struct PlusRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("+")
                .font(Theme.mono)
                .foregroundStyle(Theme.tertiary)
            content
        }
    }
}

/// Keys, ids and metadata in SF Mono.
@MainActor struct MonoText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.mono)
            .textSelection(.enabled)
    }
}

/// Over everything while the scene is inactive or the screen is captured.
@MainActor struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.ground
            Image(systemName: Theme.hat)
                .font(.system(size: 48))
                .foregroundStyle(Theme.tertiary)
        }
        .ignoresSafeArea()
    }
}

/// A fingerprint as uppercase hex in groups of four, eight to a line.
@MainActor struct FingerprintText: View {
    let bytes: [UInt8]

    var body: some View {
        Text(FingerprintText.display(bytes))
            .font(Theme.mono)
            .textSelection(.enabled)
    }

    nonisolated static func display(_ bytes: [UInt8]) -> String {
        let digits = Array(Hex.string(bytes).uppercased())
        var groups: [String] = []
        var index = 0
        while index < digits.count {
            let end = min(index + 4, digits.count)
            groups.append(String(digits[index..<end]))
            index = end
        }
        var lines: [String] = []
        var start = 0
        while start < groups.count {
            let end = min(start + 8, groups.count)
            lines.append(groups[start..<end].joined(separator: " "))
            start = end
        }
        return lines.joined(separator: "\n")
    }
}
