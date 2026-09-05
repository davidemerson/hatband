import Foundation

/// The test double: records every prompt and can fail one read.
@MainActor final class MemoryKeyStore: KeyStore {
    var items: [String: (data: Data, access: KeyAccess)] = [:]
    /// Every prompt shown, for assertions.
    var prompts: [String] = []
    /// Thrown by the next `read`, then cleared.
    var failNextRead: KeyStoreError?
    /// Test hook: "read <name>", "write <name>", "delete <name>".
    var onEvent: ((String) -> Void)?

    init() {}

    func read(_ name: String, prompt: String?) throws -> Data? {
        onEvent?("read " + name)
        if let prompt { prompts.append(prompt) }
        if let failure = failNextRead {
            failNextRead = nil
            throw failure
        }
        return items[name]?.data
    }

    func write(_ name: String, _ data: Data, access: KeyAccess) throws {
        onEvent?("write " + name)
        items[name] = (data: data, access: access)
    }

    func delete(_ name: String) throws {
        onEvent?("delete " + name)
        items[name] = nil
    }
}
