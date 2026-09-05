import Foundation

/// User settings, stored in the owner blob.
nonisolated struct Settings: Hashable, Sendable {
    var appLock = true
    var includeInBackup = false
    var homeWidget = false
    var showNameOnLockScreen = true
    var alwaysOnQR = false
    var durationMinutes = 120
    var lastPersonaID: [UInt8]?
}
