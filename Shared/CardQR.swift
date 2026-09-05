import Foundation
import HatbandCore

/// The QR symbol for a card URL in a given form, at the form's version
/// limit. Nil when the URL does not fit, and always nil for `.file`.
nonisolated enum CardQR {
    static func code(for url: String, form: CardForm) -> QRCode? {
        let maxVersion: Int
        switch form {
        case .lockScreen:
            maxVersion = Budget.lockScreenMaxVersion
        case .fullQR:
            maxVersion = Budget.fullQRMaxVersion
        case .file:
            return nil
        }
        do {
            return try QRCode.encode(
                QRSegment.segments(forURL: url),
                errorCorrection: Budget.errorCorrection,
                maxVersion: maxVersion)
        } catch {
            return nil
        }
    }
}
