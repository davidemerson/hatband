import Foundation

/// The protection a Keychain item gets. `KeychainStore` maps it onto
/// Security constants; this half is pure.
nonisolated struct KeyAccess: Equatable, Sendable {
    var thisDeviceOnly: Bool
    var userPresence: Bool

    /// The identity seed: never leaves the device, never prompts.
    static let seed = KeyAccess(thisDeviceOnly: true, userPresence: false)

    /// The database key: prompts when app lock is on; travels in backups
    /// only when the user opts in.
    static func database(appLock: Bool, includeInBackup: Bool) -> KeyAccess {
        KeyAccess(thisDeviceOnly: !includeInBackup, userPresence: appLock)
    }
}
