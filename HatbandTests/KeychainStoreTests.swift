import Foundation
import Security
import Testing
@testable import Hatband

/// The attribute dictionaries `KeychainStore` builds, checked without a
/// keychain; and, where the test host offers one, a real item written,
/// rewritten under other protection, and read back.
@MainActor struct KeychainStoreTests {
    /// A replacement deletes before it adds, which is the one moment the
    /// item is not there. If the add is refused the old protection goes back,
    /// so a failed App lock toggle cannot leave the phone with no database
    /// key and every scanned person unreadable.
    @Test func restoringPutsBackTheProtectionTheItemHad() throws {
        let data = Data([0xC0, 0xFF, 0xEE])

        // An item behind an access control goes back behind the same object.
        let control = try #require(SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil))
        let controlled = KeychainStore.restoreAttributes(
            name: "k", data: data, from: [kSecAttrAccessControl as String: control])
        #expect(controlled?[kSecAttrAccessControl as String] != nil)
        #expect(controlled?[kSecAttrAccessible as String] == nil)
        #expect(controlled?[kSecValueData as String] as? Data == data)

        // A plain item goes back at the accessibility it had.
        let plain = KeychainStore.restoreAttributes(
            name: "k", data: data,
            from: [kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String])
        #expect(plain?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(plain?[kSecAttrAccessControl as String] == nil)

        // Attributes that say nothing about protection offer nothing to restore.
        #expect(KeychainStore.restoreAttributes(name: "k", data: data, from: [:]) == nil)
    }

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

    /// The shape `isConstrained` reads, pinned against the real Keychain.
    /// iOS 26 returns an access control for every item, so the classification
    /// rests entirely on whether that control lists constraints: a plain item
    /// is its protection class alone, a guarded one appends them after a
    /// semicolon. Returns early where the host has no usable keychain.
    @Test func accessControlDescribesItsConstraints() throws {
        let store = KeychainStore()

        let plainName = "plain-" + UUID().uuidString
        defer { try? store.delete(plainName) }
        do {
            try store.write(plainName, Data([1]), access: .seed)
        } catch {
            return
        }
        let plain = try #require(KeychainStore.storedAttributes(name: plainName))
        if let control = plain[kSecAttrAccessControl as String] {
            #expect(!KeychainStore.isConstrained(control), "a plain item came back constrained")
        }
        #expect(KeychainStore.protectionMatches(plain, .seed))
        #expect(!KeychainStore.protectionMatches(plain, .database(appLock: true, includeInBackup: false)))

        let guardedName = "guarded-" + UUID().uuidString
        defer { try? store.delete(guardedName) }
        let guardedAccess = KeyAccess.database(appLock: true, includeInBackup: false)
        try store.write(guardedName, Data([2]), access: guardedAccess)
        let guarded = try #require(KeychainStore.storedAttributes(name: guardedName))
        let control = try #require(guarded[kSecAttrAccessControl as String],
                                   "user presence has to reach the item as a control")
        #expect(KeychainStore.isConstrained(control))
        #expect(KeychainStore.protectionMatches(guarded, guardedAccess))
        #expect(!KeychainStore.protectionMatches(guarded, .seed), "presence read as no presence")
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
