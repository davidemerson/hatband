import SwiftUI
import WidgetKit

/// The Home Screen widget and the Live Activity.
@main
struct HatbandWidgetBundle: WidgetBundle {
    var body: some Widget {
        CardWidget()
        CardActivity()
    }
}
