// STUB: replaced by package B
import Foundation
import HatbandCore

extension AppModel {
    func issuedDay() -> UInt32 {
        0
    }

    func card(for persona: Persona, form: CardForm) throws -> Card {
        throw AppError.storage("stub")
    }

    func qr(for persona: Persona, form: CardForm) throws -> QRCode? {
        nil
    }

    func budget(for persona: Persona, form: CardForm) throws -> Budget {
        throw AppError.storage("stub")
    }

    func url(for persona: Persona, form: CardForm) throws -> String {
        throw AppError.storage("stub")
    }

    func fileBytes(for persona: Persona) throws -> [UInt8] {
        throw AppError.storage("stub")
    }

    var selectedPersona: Persona? {
        personas.first { $0.id == selectedPersonaID }
    }

    func select(_ persona: Persona) {
    }

    func addPersona(label: String, alias: Bool) throws -> Persona {
        throw AppError.storage("stub")
    }

    func update(_ persona: Persona) async throws {
    }

    func delete(persona: Persona) throws {
    }
}
