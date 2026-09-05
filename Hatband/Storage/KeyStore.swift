import Foundation

/// Where the two secrets live. `KeychainStore` in the app, `MemoryKeyStore` in tests.
@MainActor protocol KeyStore: AnyObject {
    /// Nil when absent. `prompt` is shown when the item needs user presence;
    /// the call suspends until the prompt is answered and never blocks the
    /// main thread.
    func read(_ name: String, prompt: String?) async throws -> Data?
    /// Creates the item, or rewrites it under `access`. The old item stays
    /// until the new one is in place, so a failure loses nothing.
    func write(_ name: String, _ data: Data, access: KeyAccess) throws
    func delete(_ name: String) throws
}

nonisolated enum KeyStoreError: Error, Equatable {
    case cancelled
    case notAvailable
    case failed(OSStatus)
}

nonisolated enum KeyName {
    static let seed = "seed"
    static let database = "dbkey"
    /// Next persona key index; indices are never reused.
    static let personaIndex = "persona-index"
}
