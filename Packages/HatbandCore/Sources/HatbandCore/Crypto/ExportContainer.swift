import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum ExportError: Swift.Error, Equatable, Sendable {
    case malformed
    case unsupportedVersion
    case unsupportedKDF
    case iterationsOutOfRange
    case wrongPassphraseOrTampered
    /// Plaintext over `maxPlaintextSize`; refused before the KDF.
    case tooLarge
}

/// The `.hatband-export` container: a deterministic CBOR map
/// `{0: version, 1: kdf, 2: iterations, 3: salt, 4: nonce, 5: ciphertext || tag}`
/// sealed with ChaCha20-Poly1305 (RFC 8439) under a key from PBKDF2-HMAC-SHA256.
/// The encoded header, the map without key 5, is the additional data, so a
/// changed iteration count, salt or nonce fails authentication instead of
/// silently deriving a different key.
public enum ExportContainer {
    public static let formatVersion: UInt64 = 1
    /// PBKDF2-HMAC-SHA256, the only KDF defined.
    public static let kdfPBKDF2: UInt64 = 1
    public static let defaultIterations = 600_000
    /// Enforced on seal and open: enough work to slow guessing, little
    /// enough that a hostile header cannot pin the CPU for minutes.
    public static let iterationRange = 100_000...10_000_000
    /// Rejected on open before decoding. Every card is under 32 KB in every
    /// form, so no honest export comes near this.
    public static let maxContainerSize = 32 * 1024 * 1024
    /// The most `seal` accepts: what `maxContainerSize` leaves after the
    /// header and tag, so every container sealed here also opens.
    public static let maxPlaintextSize = maxContainerSize - headerLength - tagLength

    static let saltLength = 16
    static let nonceLength = 12
    static let keyLength = 32
    static let tagLength = 16
    /// The map header through the body's length prefix: fixed at 49 bytes
    /// once the iteration count takes four bytes (it always does within
    /// `iterationRange`) and the body is 64 KiB or more.
    static let headerLength = 49
    /// Initial bytes of a definite-length map of up to 23 entries (RFC 8949
    /// §3.1). This version has six; the range leaves room for a later one
    /// to be answered `unsupportedVersion` rather than `malformed`.
    static let mapInitialBytes: ClosedRange<UInt8> = 0xa0...0xb7

    /// Fresh salt and nonce every call, so sealing the same bytes twice
    /// gives two unrelated containers.
    public static func seal(_ plaintext: [UInt8], passphrase: String, iterations: Int = defaultIterations) throws -> [UInt8] {
        guard iterationRange.contains(iterations) else { throw ExportError.iterationsOutOfRange }
        guard plaintext.count <= maxPlaintextSize else { throw ExportError.tooLarge }
        let salt = randomBytes(count: saltLength)
        let nonce = randomBytes(count: nonceLength)
        var map = header(iterations: iterations, salt: salt, nonce: nonce)
        let box = try ChaChaPoly.seal(plaintext, using: key(passphrase: passphrase, salt: salt, iterations: iterations),
                                      nonce: ChaChaPoly.Nonce(data: nonce), authenticating: CBOR.map(map).encoded)
        map[5] = .bytes(Array(box.ciphertext) + Array(box.tag))
        return CBOR.map(map).encoded
    }

    /// Checks the header before running the KDF, so a bad version, KDF or
    /// iteration count costs nothing; the size and the initial byte are
    /// checked before decoding, so anything not shaped like a small map
    /// costs nothing either. Anything the AEAD rejects, including a wrong
    /// passphrase, is `wrongPassphraseOrTampered`: the two are not
    /// distinguishable and should not be.
    public static func open(_ container: [UInt8], passphrase: String) throws -> [UInt8] {
        guard container.count <= maxContainerSize, let first = container.first, mapInitialBytes.contains(first),
              let value = try? CBOR.decode(container), let map = value.mapValue, let version = value[0]?.unsignedValue
        else { throw ExportError.malformed }
        guard version == formatVersion else { throw ExportError.unsupportedVersion }
        guard map.count == 6, let kdf = value[1]?.unsignedValue, let count = value[2]?.unsignedValue,
              let salt = value[3]?.bytesValue, let nonce = value[4]?.bytesValue, let body = value[5]?.bytesValue
        else { throw ExportError.malformed }
        guard kdf == kdfPBKDF2 else { throw ExportError.unsupportedKDF }
        guard let iterations = Int(exactly: count), iterationRange.contains(iterations) else {
            throw ExportError.iterationsOutOfRange
        }
        guard salt.count == saltLength, nonce.count == nonceLength, body.count >= tagLength else {
            throw ExportError.malformed
        }
        let additionalData = CBOR.map(header(iterations: iterations, salt: salt, nonce: nonce)).encoded
        do {
            let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce),
                                               ciphertext: body[..<(body.count - tagLength)],
                                               tag: body[(body.count - tagLength)...])
            return Array(try ChaChaPoly.open(box, using: key(passphrase: passphrase, salt: salt, iterations: iterations),
                                             authenticating: additionalData))
        } catch {
            throw ExportError.wrongPassphraseOrTampered
        }
    }

    private static func header(iterations: Int, salt: [UInt8], nonce: [UInt8]) -> [CBOR: CBOR] {
        [0: .unsigned(formatVersion), 1: .unsigned(kdfPBKDF2), 2: .unsigned(UInt64(iterations)),
         3: .bytes(salt), 4: .bytes(nonce)]
    }

    /// PBKDF2 over the NFKD form of the passphrase, so the same words typed
    /// with a different Unicode composition still open the container.
    private static func key(passphrase: String, salt: [UInt8], iterations: Int) -> SymmetricKey {
        let normalized = Array(passphrase.decomposedStringWithCompatibilityMapping.utf8)
        return SymmetricKey(data: PBKDF2.deriveKey(password: normalized, salt: salt,
                                                   iterations: iterations, keyLength: keyLength))
    }
}
