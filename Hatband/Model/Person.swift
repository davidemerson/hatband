import Foundation
import HatbandCore

/// How a person's key came to be pinned. Wire values 0, 1, 2.
nonisolated enum Trust: Hashable, Sendable {
    case inPerson
    case byFile
    case keyChanged(previous: [UInt8])
}

/// A coarse location: hundredths of a degree and whole metres. The only
/// initializer rounds, so nothing finer is ever stored, and clamps, so a
/// value that is not a place (NaN, infinity, a corrupt record decoded as
/// `Int.max`) can never trap the `Int` conversion.
nonisolated struct Fix: Hashable, Sendable {
    /// Earth's circumference: no fix is less certain than that.
    static let maxAccuracyMetres: Double = 40_075_000

    let latitudeHundredths: Int
    let longitudeHundredths: Int
    let accuracyMetres: Int

    init(latitude: Double, longitude: Double, accuracy: Double) {
        latitudeHundredths = Fix.hundredths(latitude, limit: 90)
        longitudeHundredths = Fix.hundredths(longitude, limit: 180)
        accuracyMetres = Fix.metres(accuracy)
    }

    /// Non-finite counts as zero; beyond the limit is the limit.
    private static func hundredths(_ degrees: Double, limit: Double) -> Int {
        guard degrees.isFinite else { return 0 }
        return Int((min(max(degrees, -limit), limit) * 100).rounded())
    }

    private static func metres(_ accuracy: Double) -> Int {
        guard accuracy.isFinite else { return 0 }
        return Int(min(max(accuracy, 0), maxAccuracyMetres).rounded())
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
    /// The received card's bytes, signature and all; never rewritten.
    var cardBytes: [UInt8]
    var card: Card
    var publicKey: [UInt8]?
    var keyFingerprint: [UInt8]?
    var trust: Trust
    var source: CardSource
    var tags: [String]
    var note: String
    var gpgKey: [UInt8]?
    /// A photo from an earlier card, kept when a later one arrived without
    /// (no QR carries one). Nil while `card.photo` is the latest. Held here,
    /// not in `cardBytes`, which stay exactly what was signed.
    var photo: [UInt8]? = nil
    var createdAt: Date
    var updatedAt: Date
    var encounters: [Encounter]

    /// The photo to show: the kept one, else the card's own.
    var currentPhoto: [UInt8]? { photo ?? card.photo }
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
