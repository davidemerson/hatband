import Foundation
import Testing
@testable import Hatband

struct AppErrorTests {
    /// The frozen refusal value from `delete(persona:)` reaches the alert
    /// as a sentence, not as the internal token.
    /// A raw OSStatus in an alert is the app talking to its developer in
    /// front of a user. The four statuses someone can act on say what to do;
    /// the rest keep the number for a bug report.
    @Test func keychainFailuresReadAsSentences() {
        #expect(AppError.keychain(-25300).message.contains("Restore from an export"))
        #expect(AppError.keychain(-25308).message == "Unlock this iPhone and try again.")
        #expect(AppError.keychain(-25293).message.contains("Face ID"))
        #expect(AppError.keychain(-25291).message.contains("not available"))
        // Anything else keeps the number, in brackets, at the end of a sentence.
        #expect(AppError.keychain(-99999).message.contains("(-99999)"))
        for status in [-25300, -25308, -25293, -25291, -99999] as [OSStatus] {
            #expect(AppError.keychain(status).message.hasSuffix("."))
            #expect(!AppError.keychain(status).message.hasPrefix("Keychain error"))
        }
    }

    /// Every message is a sentence: the alert shows them one at a time and a
    /// missing full stop reads as a dropped word.
    @Test func everyMessageEndsInAFullStop() {
        let errors: [AppError] = [
            .notHatband, .unsupportedFormat, .invalidSignature, .tooLarge, .wrongPassphrase,
            .cancelled, .keychain(-1), .storage("Stored data is damaged."), .activitiesDisabled,
            .tooBigForLockScreen, .refused("Give the persona a label."),
        ]
        for error in errors {
            #expect(error.message.hasSuffix("."), "\(error) does not end in a full stop")
            #expect(!error.message.isEmpty)
        }
    }

    /// A refusal carries the reason the validator already wrote.
    @Test func aRefusalIsItsOwnReason() {
        #expect(AppError.refused("Give the persona a label.").message == "Give the persona a label.")
    }

    @Test func lastPersonaRefusalReadsAsASentence() {
        #expect(AppError.storage("last persona").message == "Keep at least one persona.")
        #expect(AppError.storage("last persona") == AppError.storage("last persona"))
    }

    /// An error no branch knows shows the platform's own sentence, never
    /// a type dump such as `CocoaError(_nsError: Error Domain=...)`.
    @Test func unknownErrorsShowTheirLocalizedText() {
        let error = CocoaError(.fileReadNoPermission)
        let mapped = AppError(error)
        #expect(mapped == .storage(error.localizedDescription))
        #expect(!mapped.message.contains("CocoaError"))
        #expect(!mapped.message.contains("Domain"))
        #expect(!mapped.message.isEmpty)
    }
}
