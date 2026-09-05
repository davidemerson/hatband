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
                .onAppear { Diagnostics.subscribe() }
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhase(phase)
        }
    }
}
