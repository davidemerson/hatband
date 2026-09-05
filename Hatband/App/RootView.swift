import SwiftUI

/// Phase switch, the four tabs, the privacy cover, and the review, import
/// and error presentations.
@MainActor struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            switch model.phase {
            case .loading:
                ProgressView()
            case .protectedDataUnavailable:
                Text("Unlock your iPhone to open Hatband.")
                    .padding()
            case .storeUnavailable:
                VStack(spacing: 12) {
                    Text("Hatband cannot open its storage.")
                    Button("Try again") {
                        Task { await model.load() }
                    }
                }
                .padding()
            case .onboarding:
                OnboardingView()
            case .ready:
                TabView(selection: $model.route.tab) {
                    SwiftUI.Tab("Card", systemImage: Theme.hat, value: Tab.card) {
                        CardView()
                    }
                    SwiftUI.Tab("People", systemImage: "person.2", value: Tab.people) {
                        if model.locked {
                            LockedView()
                        } else {
                            PeopleView()
                        }
                    }
                    SwiftUI.Tab("Where", systemImage: "map", value: Tab.places) {
                        if model.locked {
                            LockedView()
                        } else {
                            WhereView()
                        }
                    }
                    SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                        if model.locked {
                            LockedView()
                        } else {
                            SettingsView()
                        }
                    }
                }
            }
            if model.covered {
                PrivacyCover()
            }
        }
        .sheet(item: $model.pendingReview) { review in
            ReviewSheet(review: review)
        }
        .sheet(isPresented: importPresented) {
            ImportSheet()
        }
        .alert("Hatband", isPresented: errorPresented) {
            Button("OK") {}
        } message: {
            Text(model.error?.message ?? "")
        }
    }

    private var importPresented: Binding<Bool> {
        Binding(
            get: { model.pendingImport != nil },
            set: { shown in
                if !shown {
                    model.pendingImport = nil
                }
            })
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.error != nil },
            set: { shown in
                if !shown {
                    model.error = nil
                }
            })
    }
}
