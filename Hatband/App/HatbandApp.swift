import Foundation
import SwiftUI

/// Builds the live model and forwards scene phases and URLs. Never
/// touches the store: that opens inside `AppModel.load()`.
@main
struct HatbandApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .onOpenURL { url in
                    model.handle(url: url)
                }
                // A universal link does not always arrive as a URL open. The
                // Camera app hands its QR to the system as a web activity, and
                // without this the app came to the front having been told
                // nothing: one scan, and then you had to scan again from
                // inside. Both paths land on `handle`, which ignores a repeat.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        model.handle(url: url)
                    }
                }
                .onAppear { Diagnostics.subscribe() }
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhase(phase)
        }
    }
}
