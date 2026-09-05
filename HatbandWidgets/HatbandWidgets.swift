// STUB: replaced by package C
import SwiftUI
import WidgetKit

@main
struct HatbandWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "link.hatband.card", provider: PlaceholderProvider()) { _ in
            Text("Hatband")
        }
        .supportedFamilies([.systemMedium])
    }
}
