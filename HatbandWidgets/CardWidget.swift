import CoreGraphics
import Foundation
import HatbandCore
import SwiftUI
import WidgetKit

/// One entry: the feed as read, or nil when the widget is off.
nonisolated struct CardEntry: TimelineEntry {
    let date: Date
    let feed: WidgetFeed?
}

/// Reads `card-widget.json` from the App Group container. Called off the
/// main actor by WidgetKit; one entry, never reloaded on its own.
nonisolated struct CardProvider: TimelineProvider {
    func placeholder(in context: Context) -> CardEntry {
        CardEntry(date: Date(), feed: CardProvider.sampleFeed())
    }

    func getSnapshot(in context: Context, completion: @escaping (CardEntry) -> Void) {
        completion(CardEntry(date: Date(), feed: WidgetFeed.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CardEntry>) -> Void) {
        let entry = CardEntry(date: Date(), feed: WidgetFeed.read())
        completion(Timeline(entries: [entry], policy: .never))
    }

    /// A name-only compact card for the widget gallery.
    static func sampleFeed() -> WidgetFeed {
        var card = Card(personaID: [0, 0, 0, 0, 0, 0, 0, 0], issuedDay: 0)
        card.flags.insert(.compact)
        card.name = "Your name"
        card.color = 1
        return WidgetFeed(url: HB1.url(for: card), name: card.name, color: card.color, writtenAt: Date())
    }
}

/// The medium Home Screen widget: the selected persona's compact QR on a
/// white panel, the hat glyph, the name when shown.
@MainActor struct CardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.kind, provider: CardProvider()) { entry in
            CardWidgetView(entry: entry)
        }
        .configurationDisplayName("Your card")
        .description("Your Hatband card, ready to scan.")
        .supportedFamilies([.systemMedium])
    }
}

@MainActor struct CardWidgetView: View {
    let entry: CardEntry

    var body: some View {
        Group {
            if let feed = entry.feed, let image = CardWidgetView.image(for: feed) {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Color.white)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .interpolation(.none)
                                .widgetAccentedRenderingMode(.fullColor)
                                .aspectRatio(1, contentMode: .fit)
                                .padding(6)
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: Theme.hat)
                            .font(.title3)
                            .foregroundStyle(Theme.personaColor(feed.color))
                        if let name = feed.name {
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
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: Theme.hat)
                        .font(.title3)
                        .foregroundStyle(Theme.tertiary)
                    Text("Turn on the widget in Hatband settings")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .containerBackground(Theme.ground, for: .widget)
    }

    /// The feed's URL at the Lock Screen version limit, or nil.
    nonisolated static func image(for feed: WidgetFeed) -> CGImage? {
        guard let code = CardQR.code(for: feed.url, form: .lockScreen) else { return nil }
        return QRBitmap.cgImage(code, pixelsPerModule: 4)
    }
}
