// STUB: replaced by package E
import Foundation
import HatbandCore

extension AppModel {
    nonisolated enum ImportMode {
        case restore, merge
    }

    nonisolated struct ImportSummary: Equatable {
        var personas: Int
        var people: Int
        var encounters: Int
        var keyChanges: Int
    }

    func exportData(passphrase: String) async throws -> Data {
        throw AppError.storage("stub")
    }

    func importData(_ data: Data, passphrase: String, mode: ImportMode) async throws -> ImportSummary {
        throw AppError.storage("stub")
    }

    func setAppLock(_ on: Bool) async throws {
    }

    func setIncludeInBackup(_ on: Bool) async throws {
    }

    func setHomeWidget(_ on: Bool) throws {
    }

    func eraseEverything() async {
    }
}
