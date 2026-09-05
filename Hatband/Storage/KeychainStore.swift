import Foundation
import LocalAuthentication
import Security

nonisolated extension KeyAccess {
    /// Follows `thisDeviceOnly` in both the access-control and plain branches.
    var accessible: CFString {
        thisDeviceOnly ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly : kSecAttrAccessibleWhenUnlocked
    }

    var flags: SecAccessControlCreateFlags? {
        userPresence ? .userPresence : nil
    }
}

/// An `LAContext` in a box, so a read can hand it to the Security call off
/// the main actor and the write that follows can reuse it. `LAContext` is
/// usable from any thread; the box never reaches a third place.
nonisolated private final class AuthContext: @unchecked Sendable {
    let context: LAContext

    /// `silent` never shows UI: a call that would need a prompt fails with
    /// `errSecInteractionNotAllowed` instead.
    init(prompt: String?, silent: Bool = false) {
        context = LAContext()
        if let prompt {
            context.localizedReason = prompt
        }
        context.interactionNotAllowed = silent
    }
}

/// Generic passwords in the data-protection keychain, one per `KeyName`.
/// A read runs off the main actor: behind user presence it returns once
/// Face ID or the passcode has answered. A write never prompts.
@MainActor final class KeychainStore: KeyStore {
    nonisolated static let service = "link.hatband.ios"

    /// The context that satisfied the last prompting read, kept for the
    /// write that follows and consumed by it: rewriting the database key
    /// under new access asks once, at the read.
    private var authenticated: AuthContext?

    init() {}

    func read(_ name: String, prompt: String?) async throws -> Data? {
        let auth = AuthContext(prompt: prompt)
        let data = try await KeychainStore.copyMatching(name: name, auth: auth)
        if prompt != nil {
            authenticated = auth
        }
        return data
    }

    /// Updates the item in place, so a failure leaves the old one, and adds
    /// it when absent. An update the Keychain refuses, or one that leaves
    /// other protection than asked for (an access control it will not
    /// drop), ends in a replacement: delete, then an add whose attributes
    /// were built before anything was touched.
    func write(_ name: String, _ data: Data, access: KeyAccess) throws {
        let protection = try KeychainStore.protectionAttributes(access)
        let adding = KeychainStore.addAttributes(name: name, data: data, protection: protection)
        var changes = protection
        changes[kSecValueData as String] = data
        let auth = authenticated ?? AuthContext(prompt: nil, silent: true)
        authenticated = nil
        // On the main thread a context that has not authenticated must
        // fail rather than prompt; the item is then replaced instead.
        auth.context.interactionNotAllowed = true
        var query = KeychainStore.baseAttributes(name: name)
        query[kSecUseAuthenticationContext as String] = auth.context
        switch SecItemUpdate(query as CFDictionary, changes as CFDictionary) {
        case errSecSuccess:
            if let stored = KeychainStore.storedAttributes(name: name), KeychainStore.protectionMatches(stored, access) {
                return
            }
        case errSecItemNotFound:
            try KeychainStore.add(adding)
            return
        default:
            break
        }
        try delete(name)
        try KeychainStore.add(adding)
    }

    func delete(_ name: String) throws {
        let status = SecItemDelete(KeychainStore.baseAttributes(name: name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreError.failed(status) }
    }

    // MARK: - Attributes

    /// Class, service and account: what names the item in every call.
    nonisolated static func baseAttributes(name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    /// `kSecAttrAccessControl` with user presence, `kSecAttrAccessible`
    /// without; the accessibility constant follows `thisDeviceOnly` in both.
    nonisolated static func protectionAttributes(_ access: KeyAccess) throws -> [String: Any] {
        if let flags = access.flags {
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(nil, access.accessible, flags, &error) else {
                throw KeyStoreError.failed(errSecParam)
            }
            return [kSecAttrAccessControl as String: control]
        }
        return [kSecAttrAccessible as String: access.accessible]
    }

    /// Everything `SecItemAdd` needs.
    nonisolated static func addAttributes(name: String, data: Data, protection: [String: Any]) -> [String: Any] {
        var attributes = baseAttributes(name: name)
        attributes.merge(protection) { _, new in new }
        attributes[kSecValueData as String] = data
        return attributes
    }

    /// Whether stored attributes carry exactly the protection `access` asks
    /// for: its accessibility constant, and an access control only with
    /// user presence.
    nonisolated static func protectionMatches(_ attributes: [String: Any], _ access: KeyAccess) -> Bool {
        let accessible = attributes[kSecAttrAccessible as String] as? String
        let controlled = attributes[kSecAttrAccessControl as String] != nil
        return accessible == (access.accessible as String) && controlled == access.userPresence
    }

    /// The item's attributes without its data, read silently: nil when
    /// absent, or when the Keychain would have to prompt for them.
    nonisolated static func storedAttributes(name: String) -> [String: Any]? {
        var query = baseAttributes(name: name)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = AuthContext(prompt: nil, silent: true).context
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    // MARK: - Security calls

    /// The read, off the main actor: with user presence on the item it
    /// returns once the prompt has been answered.
    @concurrent nonisolated private static func copyMatching(name: String, auth: AuthContext) async throws -> Data? {
        var query = baseAttributes(name: name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = auth.context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed:
            throw KeyStoreError.cancelled
        case errSecInteractionNotAllowed:
            throw KeyStoreError.notAvailable
        default:
            throw KeyStoreError.failed(status)
        }
    }

    nonisolated private static func add(_ attributes: [String: Any]) throws {
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.failed(status) }
    }
}
