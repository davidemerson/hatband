import Foundation
import HatbandCore

/// Every error the UI shows. Library errors map onto it in `init(_:)`.
nonisolated enum AppError: Error, Equatable {
    case notHatband
    case unsupportedFormat
    case invalidSignature
    case tooLarge
    case wrongPassphrase
    case cancelled
    case keychain(OSStatus)
    case storage(String)
    case activitiesDisabled
    case tooBigForLockScreen

    /// `HB1.Error`, `KeyStoreError`, `ExportError` and `CodecError` onto `AppError`;
    /// an `AppError` passes through; anything else is `.storage`.
    init(_ error: any Error) {
        if let known = error as? AppError {
            self = known
        } else if let hb1 = error as? HB1.Error {
            switch hb1 {
            case .notHatband, .badMagic: self = .notHatband
            case .unsupportedFormat: self = .unsupportedFormat
            case .tooLarge: self = .tooLarge
            }
        } else if let key = error as? KeyStoreError {
            switch key {
            case .cancelled: self = .cancelled
            case .notAvailable: self = .storage("Keychain not available")
            case .failed(let status): self = .keychain(status)
            }
        } else if let export = error as? ExportError {
            switch export {
            case .wrongPassphraseOrTampered: self = .wrongPassphrase
            case .tooLarge: self = .tooLarge
            case .malformed, .unsupportedVersion, .unsupportedKDF, .iterationsOutOfRange: self = .unsupportedFormat
            }
        } else if let codec = error as? CodecError {
            switch codec {
            case .malformed: self = .storage("Stored data is damaged")
            case .unsupportedVersion(let version): self = .storage("Stored data version \(version) is newer than this app")
            }
        } else {
            // The platform's own sentence, never a type dump.
            self = .storage(error.localizedDescription)
        }
    }

    /// One line for an alert.
    var message: String {
        switch self {
        case .notHatband: return "That is not a Hatband card."
        case .unsupportedFormat: return "This card was made by a newer Hatband."
        case .invalidSignature: return "The card's signature does not verify."
        case .tooLarge: return "The card is too large."
        case .wrongPassphrase: return "Wrong passphrase, or the file was changed."
        case .cancelled: return "Cancelled."
        case .keychain(let status): return "Keychain error \(status)."
        case .storage("last persona"): return "Keep at least one persona."
        case .storage(let detail): return detail
        case .activitiesDisabled: return "Live Activities are off for Hatband in Settings."
        case .tooBigForLockScreen: return "The name alone does not fit the Lock Screen card."
        }
    }
}
