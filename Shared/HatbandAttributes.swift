import ActivityKit
import Foundation

/// The Live Activity. One source file in both targets; never renamed or
/// moved into a framework, since ActivityKit matches by type name.
nonisolated struct HatbandAttributes: ActivityAttributes {
    /// 16 hex chars; matches activities to personas.
    var personaID: String
    /// Palette index.
    var color: UInt8

    nonisolated struct ContentState: Codable, Hashable {
        /// Compact-tier HB1 URL, unsigned by construction.
        var url: String
        /// Nil means "show name" off.
        var name: String?
        var alwaysOn: Bool
        /// Also the staleDate.
        var endsAt: Date
    }
}
