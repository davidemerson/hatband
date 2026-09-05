import Foundation
import HatbandCore

/// What the Lock Screen presentation shows.
nonisolated enum Presentation: Equatable {
    case card(QRCode, name: String?)
    case dimmed
    case expired
    case unavailable
}

/// The one decision the Live Activity view makes, kept pure so it can be
/// tested with fixed dates.
nonisolated enum LiveActivityPresentation {
    /// Expired if `isStale` or `now >= endsAt`; dimmed if the display is in
    /// its luminance-reduced state and the user did not opt into Always-On;
    /// otherwise the card, or `unavailable` when the URL does not draw at
    /// the Lock Screen version limit.
    static func decide(state: HatbandAttributes.ContentState, isStale: Bool, isLuminanceReduced: Bool, now: Date) -> Presentation {
        if isStale || now >= state.endsAt {
            return .expired
        }
        if isLuminanceReduced && !state.alwaysOn {
            return .dimmed
        }
        guard let code = CardQR.code(for: state.url, form: .lockScreen) else {
            return .unavailable
        }
        return .card(code, name: state.name)
    }
}
