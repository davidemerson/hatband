import Security
import Testing
@testable import Hatband

struct KeyAccessTests {
    @Test func fourCombinations() {
        let deviceOnlyPresence = KeyAccess(thisDeviceOnly: true, userPresence: true)
        #expect(deviceOnlyPresence.accessible as String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(deviceOnlyPresence.flags == SecAccessControlCreateFlags.userPresence)

        let deviceOnlyPlain = KeyAccess(thisDeviceOnly: true, userPresence: false)
        #expect(deviceOnlyPlain.accessible as String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(deviceOnlyPlain.flags == nil)

        let migratingPresence = KeyAccess(thisDeviceOnly: false, userPresence: true)
        #expect(migratingPresence.accessible as String == kSecAttrAccessibleWhenUnlocked as String)
        #expect(migratingPresence.flags == SecAccessControlCreateFlags.userPresence)

        let migratingPlain = KeyAccess(thisDeviceOnly: false, userPresence: false)
        #expect(migratingPlain.accessible as String == kSecAttrAccessibleWhenUnlocked as String)
        #expect(migratingPlain.flags == nil)
    }

    @Test func databasePolicy() {
        #expect(KeyAccess.database(appLock: true, includeInBackup: false) == KeyAccess(thisDeviceOnly: true, userPresence: true))
        #expect(KeyAccess.database(appLock: false, includeInBackup: false) == KeyAccess(thisDeviceOnly: true, userPresence: false))
        #expect(KeyAccess.database(appLock: true, includeInBackup: true) == KeyAccess(thisDeviceOnly: false, userPresence: true))
        #expect(KeyAccess.database(appLock: false, includeInBackup: true) == KeyAccess(thisDeviceOnly: false, userPresence: false))
        #expect(KeyAccess.seed == KeyAccess(thisDeviceOnly: true, userPresence: false))
    }
}
