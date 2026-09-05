import Foundation
import SwiftData

/// The owner blob: profile, personas and settings, plaintext inside the
/// Class A store.
@Model final class OwnerRecord {
    var blob: Data

    init(blob: Data) {
        self.blob = blob
    }
}

/// One scanned person: sealed body, plus the two columns the app sorts
/// and matches on.
@Model final class PersonRecord {
    var personaID: Data
    var updatedAt: Date
    var sealed: Data

    init(personaID: Data, updatedAt: Date, sealed: Data) {
        self.personaID = personaID
        self.updatedAt = updatedAt
        self.sealed = sealed
    }
}

enum Records {
    static let schema = Schema([OwnerRecord.self, PersonRecord.self])
}
