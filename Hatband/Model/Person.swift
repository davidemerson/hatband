import Foundation
import HatbandCore

/// How a person's key came to be pinned. Wire values 0, 1, 2.
nonisolated enum Trust: Hashable, Sendable {
    case inPerson
    case byFile
    case keyChanged(previous: [UInt8])
}

/// A coarse location: hundredths of a degree and whole metres. The only
/// initializer rounds, so nothing finer is ever stored.
nonisolated struct Fix: Hashable, Sendable {
    let latitudeHundredths: Int
    let longitudeHundredths: Int
    let accuracyMetres: Int

    init(latitude: Double, longitude: Double, accuracy: Double) {
        latitudeHundredths = Int((latitude * 100).rounded())
        longitudeHundredths = Int((longitude * 100).rounded())
        accuracyMetres = Int(accuracy.rounded())
    }
}

/// One meeting.
nonisolated struct Encounter: Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var fix: Fix?
    var label: String
    var note: String
}

/// A scanned person: the card as received plus what the user added.
nonisolated struct Person: Identifiable, Hashable, Sendable {
    var id: String { Hex.string(personaID) }
    var personaID: [UInt8]
    var cardBytes: [UInt8]
    var card: Card
    var publicKey: [UInt8]?
    var keyFingerprint: [UInt8]?
    var trust: Trust
    var source: CardSource
    var tags: [String]
    var note: String
    var gpgKey: [UInt8]?
    var createdAt: Date
    var updatedAt: Date
    var encounters: [Encounter]
}

/// Lowercase hex, the form persona ids take in routes and `Person.id`.
nonisolated enum Hex {
    private static let digits = Array("0123456789abcdef".utf8)

    static func string(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Nil unless the text is an even number of hex digits, either case.
    static func bytes(_ text: String) -> [UInt8]? {
        let characters = Array(text)
        guard characters.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = characters[index].hexDigitValue, let low = characters[index + 1].hexDigitValue else { return nil }
            out.append(UInt8(high * 16 + low))
            index += 2
        }
        return out
    }
}
