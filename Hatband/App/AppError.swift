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
    /// A refusal with its reason already written: the editors and the
    /// validators say why better than a case name could.
    case refused(String)

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
            case .notAvailable: self = .storage("The keychain is not available. Lock and unlock this iPhone, then try again.")
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
            case .malformed: self = .storage("Stored data is damaged.")
            case .unsupportedVersion(let version):
                self = .storage("This iPhone's Hatband data was written by version \(version), which is newer than this app. Update Hatband to open it.")
            }
        } else {
            // The platform's own sentence, never a type dump.
            self = .storage(error.localizedDescription)
        }
    }

    /// The four statuses someone can do something about, as sentences. The
    /// number rides along in brackets for a bug report; on its own it was the
    /// app talking to its developer in front of a user.
    static func keychainMessage(_ status: OSStatus) -> String {
        // Numbers rather than the Security constants: the boundary lint keeps
        // those symbols in `KeychainStore`, and one of these four is caught by
        // it. The values are fixed, and each is named below in words.
        switch status {
        case -25300:        // no such item
            return "Hatband's key is missing from the keychain. Restore from an export."
        case -25308:        // interaction not allowed
            return "Unlock this iPhone and try again."
        case -25293:        // authentication failed
            return "Face ID or the passcode was not accepted."
        case -25291:        // keychain not available
            return "The keychain is not available. Lock and unlock this iPhone, then try again."
        default:
            return "The keychain refused (\(status)). Lock and unlock this iPhone, then try again."
        }
    }

    /// One line for an alert.
    var message: String {
        switch self {
        case .notHatband: return "That is not a Hatband card."
        case .unsupportedFormat: return "This was made by a newer Hatband. Update the app to read it."
        case .invalidSignature: return "The card's signature does not verify. It has been changed since it was signed."
        case .tooLarge: return "That card is bigger than Hatband will read."
        case .wrongPassphrase: return "Wrong passphrase, or the file was changed. Check the words and try again."
        case .cancelled: return "Cancelled."
        case .keychain(let status): return AppError.keychainMessage(status)
        case .storage("last persona"): return "Keep at least one persona."
        case .storage(let detail): return detail
        case .activitiesDisabled:
            return "Live Activities are off for Hatband. Turn them on in Settings › Hatband › Live Activities, then try again."
        case .tooBigForLockScreen: return "The name alone does not fit the Lock Screen card."
        case .refused(let reason): return reason
        }
    }
}
