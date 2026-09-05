// STUB: replaced by package D
import Foundation
import HatbandCore

/// Where a card came from. Wire values 0 to 3.
nonisolated enum CardSource: UInt8, Sendable {
    case scan, photo, file, link
}

/// What the review sheet shows before anything is saved.
nonisolated struct Review: Identifiable, Equatable {
    let id: UUID
}
