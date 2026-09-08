import HatbandCore
import SwiftUI

/// Bytes, characters and QR version of a card, with how close it sits to the
/// form's limit said in words. Colour was the only thing separating a card
/// near its limit from one nowhere near it, which meant nothing to a reader
/// who cannot see it, and nothing at all in greyscale.
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
            Text(ByteMeter.versionText(budget, form: form))
        }
        .font(Theme.mono)
        .foregroundStyle(ByteMeter.tone(budget, form: form))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ByteMeter.spoken(budget, form: form))
    }

    nonisolated static func limit(_ form: CardForm) -> Int {
        form == .lockScreen ? Budget.lockScreenMaxVersion : Budget.fullQRMaxVersion
    }

    /// The version, and whether it is close to the limit. "Near the limit" is
    /// the part the colour used to carry on its own.
    nonisolated static func versionText(_ budget: Budget, form: CardForm) -> String {
        guard let version = budget.version, version <= limit(form) else {
            return form == .lockScreen ? "too big for the Lock Screen" : "share as a file"
        }
        return near(version, form: form) ? "QR v\(version), near the limit" : "QR v\(version)"
    }

    /// Read aloud as a sentence rather than three numbers run together: the
    /// combined form said "412 B 88 chars QR v8".
    nonisolated static func spoken(_ budget: Budget, form: CardForm) -> String {
        let size = "\(budget.bytes) bytes, \(budget.characters) characters"
        guard let version = budget.version, version <= limit(form) else {
            return form == .lockScreen
                ? "\(size). Too big for the Lock Screen."
                : "\(size). Too big for a QR code; share it as a file."
        }
        return near(version, form: form)
            ? "\(size). QR version \(version), near the limit."
            : "\(size). QR version \(version)."
    }

    /// Colour is reinforcement now, not the message.
    nonisolated static func tone(_ budget: Budget, form: CardForm) -> Color {
        guard let version = budget.version, version <= limit(form) else { return .red }
        return near(version, form: form) ? .orange : Theme.tertiary
    }

    private nonisolated static func near(_ version: Int, form: CardForm) -> Bool {
        form == .lockScreen ? version > 8 : version > 20
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
                .accessibilityHidden(true)
            content
        }
    }
}

/// Keys, ids and metadata in SF Mono. Not selectable: a copy goes
/// through `Pasteboard` (local, expiring), which the system Copy menu
/// would bypass.
@MainActor struct MonoText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.mono)
    }
}

/// A passphrase entry that can be shown in the clear: generated
/// passphrases are read off paper, so the words must be checkable.
@MainActor struct PassphraseField: View {
    let title: String
    @Binding var text: String
    @State private var revealed = false

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        HStack {
            Group {
                if revealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .font(Theme.mono)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(PassphraseField.toggleLabel(revealed: revealed))
        }
    }

    /// The reveal button's VoiceOver label.
    nonisolated static func toggleLabel(revealed: Bool) -> String {
        revealed ? "Hide passphrase" : "Show passphrase"
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

/// `PrivacyCover` over a presented sheet. A sheet is presented above
/// `RootView`, so the cover there never reaches it; every sheet root
/// wears this instead.
@MainActor struct PrivacyCovered: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        ZStack {
            content
            if model.covered {
                PrivacyCover()
            }
        }
    }
}

/// Copy, and say so. Every copy in the app went through `Pasteboard` and
/// then said nothing, so the only way to know it worked was to paste
/// somewhere else. The clipboard clears itself after a minute; that is said
/// once in a footer near the button rather than on the button, which would
/// be a sentence you read a hundred times.
@MainActor struct CopyButton: View {
    let text: String
    /// The label a reader hears, and sees when the button carries a title.
    let label: String
    /// Nil for the icon-only form used beside a row.
    var title: String?
    @State private var copied = false

    var body: some View {
        Button {
            Pasteboard.copy(text)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            if let title {
                Text(copied ? "Copied" : title)
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
        .accessibilityLabel(copied ? "Copied" : label)
    }
}

extension View {
    /// The privacy cover over this view while `AppModel.covered`.
    @MainActor func privacyCovered() -> some View {
        modifier(PrivacyCovered())
    }

    /// The nnix ground behind a `List` or `Form`, in place of the system
    /// grouped background. Rows keep their own surface.
    @MainActor func grounded() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.ground)
    }
}

/// A fingerprint as uppercase hex in groups of four, eight to a line.
@MainActor struct FingerprintText: View {
    let bytes: [UInt8]

    var body: some View {
        Text(FingerprintText.display(bytes))
            .font(Theme.mono)
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
