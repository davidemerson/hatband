import Foundation
import Testing
@testable import Hatband

struct AppErrorTests {
    /// The frozen refusal value from `delete(persona:)` reaches the alert
    /// as a sentence, not as the internal token.
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
