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

/// Generic passwords in the data-protection keychain, one per `KeyName`.
@MainActor final class KeychainStore: KeyStore {
    private let service = "link.hatband.ios"

    init() {}

    private func base(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    func read(_ name: String, prompt: String?) throws -> Data? {
        var query = base(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        if let prompt {
            context.localizedReason = prompt
        }
        query[kSecUseAuthenticationContext as String] = context
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

    func write(_ name: String, _ data: Data, access: KeyAccess) throws {
        try delete(name)
        var attributes = base(name)
        attributes[kSecValueData as String] = data
        if let flags = access.flags {
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(nil, access.accessible, flags, &error) else {
                throw KeyStoreError.failed(errSecParam)
            }
            attributes[kSecAttrAccessControl as String] = control
        } else {
            attributes[kSecAttrAccessible as String] = access.accessible
        }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.failed(status) }
    }

    func delete(_ name: String) throws {
        let status = SecItemDelete(base(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreError.failed(status) }
    }
}
