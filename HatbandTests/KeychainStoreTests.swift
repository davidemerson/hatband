import Foundation
import Security
import Testing
@testable import Hatband

/// The attribute dictionaries `KeychainStore` builds, checked without a
/// keychain; and, where the test host offers one, a real item written,
/// rewritten under other protection, and read back.
@MainActor struct KeychainStoreTests {
    @Test func baseAttributesNameTheItem() {
        let base = KeychainStore.baseAttributes(name: "dbkey")
        #expect(base[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(base[kSecAttrService as String] as? String == "link.hatband.ios")
        #expect(base[kSecAttrAccount as String] as? String == "dbkey")
        #expect(base[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(base[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(base[kSecValueData as String] == nil)
        #expect(base[kSecAttrAccessible as String] == nil)
        #expect(base[kSecAttrAccessControl as String] == nil)
    }

    /// An access control only with user presence, `kSecAttrAccessible`
    /// otherwise, the constant following `thisDeviceOnly` in both.
    @Test func protectionFollowsAccess() throws {
        let plain = try KeychainStore.protectionAttributes(.seed)
        #expect(plain[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(plain[kSecAttrAccessControl as String] == nil)
        #expect(plain.count == 1)

        let migrating = try KeychainStore.protectionAttributes(.database(appLock: false, includeInBackup: true))
        #expect(migrating[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlocked as String)
        #expect(migrating[kSecAttrAccessControl as String] == nil)

        let guarded = try KeychainStore.protectionAttributes(.database(appLock: true, includeInBackup: false))
        #expect(guarded[kSecAttrAccessible as String] == nil)
        #expect(guarded[kSecAttrAccessControl as String] != nil)
        #expect(guarded.count == 1)
    }

    /// Everything `SecItemAdd` needs is in hand before any item is touched.
    @Test func addAttributesCarryProtectionAndData() throws {
        let protection = try KeychainStore.protectionAttributes(.database(appLock: true, includeInBackup: true))
        let adding = KeychainStore.addAttributes(name: "dbkey", data: Data([1, 2, 3]), protection: protection)
        #expect(adding[kSecAttrAccount as String] as? String == "dbkey")
        #expect(adding[kSecAttrService as String] as? String == "link.hatband.ios")
        #expect(adding[kSecValueData as String] as? Data == Data([1, 2, 3]))
        #expect(adding[kSecAttrAccessControl as String] != nil)
        #expect(adding[kSecAttrAccessible as String] == nil)
        #expect(adding.count == KeychainStore.baseAttributes(name: "dbkey").count + 2)

        let plain = KeychainStore.addAttributes(name: "seed", data: Data([9]), protection: try KeychainStore.protectionAttributes(.seed))
        #expect(plain[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(plain[kSecAttrAccessControl as String] == nil)
    }

    /// What an in-place update must leave behind to count: the constant,
    /// and an access control exactly when user presence is asked for. An
    /// update cannot drop a control, so that case must read as a mismatch.
    @Test func protectionMatchesExactly() throws {
        let control = try #require(
            KeychainStore.protectionAttributes(.database(appLock: true, includeInBackup: false))[kSecAttrAccessControl as String])
        let guarded: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
            kSecAttrAccessControl as String: control,
        ]
        #expect(KeychainStore.protectionMatches(guarded, .database(appLock: true, includeInBackup: false)))
        #expect(!KeychainStore.protectionMatches(guarded, .database(appLock: false, includeInBackup: false)), "a control left behind")
        #expect(!KeychainStore.protectionMatches(guarded, .database(appLock: true, includeInBackup: true)))

        let plain: [String: Any] = [kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked as String]
        #expect(KeychainStore.protectionMatches(plain, .database(appLock: false, includeInBackup: true)))
        #expect(!KeychainStore.protectionMatches(plain, .database(appLock: true, includeInBackup: true)), "no control yet")
        #expect(!KeychainStore.protectionMatches(plain, .seed))
        #expect(!KeychainStore.protectionMatches([:], .seed))
    }

    /// Through the real store, without user presence so nothing prompts:
    /// written, read off the main actor, rewritten under other
    /// accessibility with the data replaced, and deleted. Returns early
    /// where the host has no usable keychain.
    @Test func roundTripRewritesUnderNewAccess() async throws {
        let store = KeychainStore()
        let name = "test-" + UUID().uuidString
        defer { try? store.delete(name) }
        do {
            try store.write(name, Data([1, 2, 3]), access: .seed)
        } catch {
            return
        }
        #expect(try await store.read(name, prompt: nil) == Data([1, 2, 3]))
        let written = try #require(KeychainStore.storedAttributes(name: name))
        #expect(KeychainStore.protectionMatches(written, .seed))

        try store.write(name, Data([4, 5, 6]), access: .database(appLock: false, includeInBackup: true))
        #expect(try await store.read(name, prompt: nil) == Data([4, 5, 6]))
        let rewritten = try #require(KeychainStore.storedAttributes(name: name))
        #expect(KeychainStore.protectionMatches(rewritten, .database(appLock: false, includeInBackup: true)))
        #expect(!KeychainStore.protectionMatches(rewritten, .seed))

        try store.delete(name)
        #expect(try await store.read(name, prompt: nil) == nil)
        #expect(KeychainStore.storedAttributes(name: name) == nil)
        try store.delete(name)
    }
}
