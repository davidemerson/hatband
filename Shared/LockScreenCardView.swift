import HatbandCore
import SwiftUI

/// The Lock Screen (`.medium`) presentation of the Live Activity, at most
/// 156 pt tall: a 136 pt white panel with the QR, the hat glyph in the
/// persona colour, the name when shown, and "Scan to get my card". The
/// other branches carry a line of text and no QR.
nonisolated struct LockScreenCardView: View {
    let presentation: Presentation
    let color: UInt8

    static let panelSide: CGFloat = 136

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            switch presentation {
            case .card(let code, let name):
                panel(code)
                VStack(alignment: .leading, spacing: 6) {
                    glyph
                    if let name {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .privacySensitive()
                    }
                    Text("Scan to get my card")
                        .font(.subheadline)
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .dimmed:
                message("Tap to show card")
            case .expired:
                message("Card expired. Open Hatband.")
            case .unavailable:
                message("Open Hatband.")
            }
        }
        .padding(10)
    }

    private var glyph: some View {
        Image(systemName: Theme.hat)
            .font(.title3)
            .foregroundStyle(Theme.personaColor(color))
    }

    private func panel(_ code: QRCode) -> some View {
        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .fill(Color.white)
            .frame(width: LockScreenCardView.panelSide, height: LockScreenCardView.panelSide)
            .overlay {
                QRShape(code: code)
                    .fill(Color.black)
                    .padding(6)
            }
    }

    private func message(_ text: String) -> some View {
        HStack(spacing: 10) {
            glyph
            Text(text)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
    }
}
