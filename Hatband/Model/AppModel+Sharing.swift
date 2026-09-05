// STUB: replaced by package C
import Foundation
import HatbandCore

extension AppModel {
    func startSharing(persona: Persona, minutes: Int) async throws {
        throw AppError.storage("stub")
    }

    func stopSharing() async {
    }

    func reconcileActivities() async {
    }

    func updateActivity(for persona: Persona) async {
    }

    func refreshWidget() {
    }

    func sharingContent(for persona: Persona, minutes: Int, now: Date) throws
        -> (attributes: HatbandAttributes, state: HatbandAttributes.ContentState) {
        throw AppError.storage("stub")
    }
}
