import Foundation

/// Where the two secrets live. `KeychainStore` in the app, `MemoryKeyStore` in tests.
@MainActor protocol KeyStore: AnyObject {
    /// Nil when absent. `prompt` is shown when the item needs user presence.
    func read(_ name: String, prompt: String?) throws -> Data?
    /// Delete then add, so access changes take effect.
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
