import CryptoKit
import Foundation

/// AES-GCM sealing of person bodies under the database key. The additional
/// data binds a domain and the persona id, so a blob cannot be moved
/// between rows or tables.
nonisolated enum Sealer {
    static let personDomain = "hatband/person/v1"

    /// Domain UTF-8, one zero byte, then the id.
    static func aad(domain: String, id: Data) -> Data {
        var out = Data(domain.utf8)
        out.append(0)
        out.append(id)
        return out
    }

    /// Combined form: nonce, ciphertext, tag. A fresh nonce every call.
    static func seal(_ plaintext: [UInt8], key: SymmetricKey, aad: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        guard let combined = box.combined else { throw AppError.storage("seal") }
        return combined
    }

    static func open(_ combined: Data, key: SymmetricKey, aad: Data) throws -> [UInt8] {
        let box = try AES.GCM.SealedBox(combined: combined)
        return Array(try AES.GCM.open(box, using: key, authenticating: aad))
    }
}
