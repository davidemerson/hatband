import HatbandCore
import SwiftUI

/// The list the `+` menu shows: one row per persona, tap to put the card in
/// the message. Everything here was signed by the app; this process cannot
/// sign, so it offers what it was given and nothing else.
@MainActor struct CardPickerView: View {
    let cards: [ShareFeed.Card]
    let send: (ShareFeed.Card) -> Void

    var body: some View {
        if cards.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: Theme.hat)
                    .font(.largeTitle)
                    .foregroundStyle(Theme.tertiary)
                    .accessibilityHidden(true)
                Text("No card yet")
                    .font(.headline)
                Text("Open Hatband and make a persona, then come back.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(cards, id: \.personaID) { card in
                        Button {
                            send(card)
                        } label: {
                            row(card)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .background(Theme.ground)
        }
    }

    private func row(_ card: ShareFeed.Card) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Theme.hat)
                .foregroundStyle(Theme.personaColor(card.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name ?? card.label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                if let company = card.company {
                    Text(company)
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(Theme.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityLabel("Send \(card.name ?? card.label)'s card")
    }
}
