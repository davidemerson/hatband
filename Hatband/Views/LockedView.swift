import SwiftUI

/// Shown on People, Where and Settings while `locked`.
@MainActor struct LockedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock")
                .font(.largeTitle)
                .foregroundStyle(Theme.tertiary)
            Text("Locked")
                .font(.headline)
            Text("The people you have scanned stay behind Face ID or your passcode.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Unlock") {
                Task {
                    _ = await model.unlock()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
