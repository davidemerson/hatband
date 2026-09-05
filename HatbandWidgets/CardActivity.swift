import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

/// The Live Activity. Only the Lock Screen presentation carries the QR and
/// the name; compact, minimal, expanded and `.small` mirror to Watch,
/// CarPlay and a paired Mac, so they show a glyph and "Sharing" at most.
@MainActor struct CardActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HatbandAttributes.self) { context in
            CardActivityContent(context: context)
                .activityBackgroundTint(Theme.ground)
                .widgetURL(CardActivity.showURL(personaID: context.attributes.personaID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    SharingSummaryView(endsAt: context.state.endsAt)
                }
            } compactLeading: {
                SharingGlyphView()
            } compactTrailing: {
                Text("Sharing")
                    .font(.caption)
            } minimal: {
                SharingGlyphView()
            }
            .widgetURL(CardActivity.showURL(personaID: context.attributes.personaID))
        }
        .supplementalActivityFamilies([.small])
    }

    /// `hatband://show?persona=<hex>`, handled by `AppModel.handle(url:)`.
    nonisolated static func showURL(personaID: String) -> URL? {
        URL(string: "hatband://show?persona=" + personaID)
    }
}

/// Switches on the activity family: `.small` never shows the card.
@MainActor struct CardActivityContent: View {
    let context: ActivityViewContext<HatbandAttributes>
    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        switch activityFamily {
        case .small:
            SmallFamilyView()
        default:
            LockScreenCardView(presentation: presentation, color: context.attributes.color)
        }
    }

    private var presentation: Presentation {
        LiveActivityPresentation.decide(
            state: context.state,
            isStale: context.isStale,
            isLuminanceReduced: isLuminanceReduced,
            now: Date())
    }
}
