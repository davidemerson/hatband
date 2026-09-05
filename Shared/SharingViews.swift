import Foundation
import SwiftUI

// The presentations that mirror to Apple Watch, CarPlay and a paired Mac:
// never the QR, never the name.

/// The hat glyph alone: compact leading and minimal Dynamic Island.
nonisolated struct SharingGlyphView: View {
    var body: some View {
        Image(systemName: Theme.hat)
            .foregroundStyle(Theme.accent)
    }
}

/// The `.small` supplemental family (Apple Watch Smart Stack, CarPlay).
nonisolated struct SmallFamilyView: View {
    var body: some View {
        HStack(spacing: 8) {
            SharingGlyphView()
            Text("Your card is on your iPhone")
                .font(.caption)
                .foregroundStyle(Theme.ink)
        }
        .padding(8)
    }
}

/// The expanded Dynamic Island: glyph, "Sharing", "until <time>".
nonisolated struct SharingSummaryView: View {
    let endsAt: Date

    var body: some View {
        HStack(spacing: 8) {
            SharingGlyphView()
            Text("Sharing")
                .font(.headline)
            Spacer(minLength: 0)
            Text("until ") + Text(endsAt, style: .time)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8)
    }
}
