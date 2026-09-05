import Foundation

/// The four tabs.
nonisolated enum Tab: Hashable {
    case card, people, places, settings
}

/// Sheets presented over the tabs. Review and import sheets are driven by
/// `AppModel.pendingReview` and `pendingImport`, not by this.
nonisolated enum Sheet: String, Identifiable, Hashable {
    case scan, sharing, inspector, print, profile, personas, about, importFile
    var id: String { rawValue }
}

/// Where the UI is.
nonisolated struct Route: Equatable {
    var tab: Tab = .card
    var sheet: Sheet?
    /// People stack: `Person.id`.
    var person: String?
    /// Pushed from `PersonaListView`.
    var editingPersona: [UInt8]?
}
