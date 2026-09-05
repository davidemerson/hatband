// STUB: replaced by package D
import Foundation
import HatbandCore

extension AppModel {
    func receive(text: String, source: CardSource) throws {
    }

    func receive(fileBytes: [UInt8]) throws {
    }

    func handle(url: URL) {
    }

    func save(_ review: Review, fix: Fix?, label: String, note: String, tags: [String],
              acceptNewKey: Bool = false) async throws {
    }

    func update(_ person: Person) throws {
    }

    func forget(_ person: Person) throws {
    }

    func restoreForgotten() throws {
    }

    func people(matching query: String) -> [Person] {
        people
    }

    var tagNames: [String] {
        []
    }

    func vcard(for person: Person, met: String?) -> VCard {
        VCard(formattedName: person.card.name ?? "")
    }

    func storeVerifiedGPGKey(_ bytes: [UInt8], for person: Person) throws {
    }
}
