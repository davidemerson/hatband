import Foundation
import HatbandCore
@testable import Hatband

/// Anchors `Bundle(for:)` to the test bundle, where cards.json lives.
final class VectorsAnchor {}

/// The checked-in HB1 vectors, read from the test bundle.
nonisolated enum Vectors {
    enum Failure: Error {
        case missing(String)
        case malformed(String)
    }

    /// The seed every signed vector was made with.
    static let seed: [UInt8] = (0..<32).map { UInt8($0) }

    static func all() throws -> [[String: Any]] {
        let bundle = Bundle(for: VectorsAnchor.self)
        guard let url = bundle.url(forResource: "cards", withExtension: "json") else {
            throw Failure.missing("cards.json")
        }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vectors = root["vectors"] as? [[String: Any]]
        else { throw Failure.malformed("cards.json") }
        return vectors
    }

    static func vector(_ name: String) throws -> [String: Any] {
        guard let vector = try all().first(where: { $0["name"] as? String == name }) else {
            throw Failure.missing(name)
        }
        return vector
    }

    /// The card's canonical CBOR.
    static func cbor(_ name: String) throws -> [UInt8] {
        guard let hex = try vector(name)["cbor"] as? String, let bytes = Hex.bytes(hex) else {
            throw Failure.malformed(name)
        }
        return bytes
    }

    static func card(_ name: String) throws -> Card {
        try HB1.decode(cbor: try cbor(name))
    }

    static func url(_ name: String) throws -> String {
        guard let url = try vector(name)["url"] as? String else { throw Failure.malformed(name) }
        return url
    }
}
