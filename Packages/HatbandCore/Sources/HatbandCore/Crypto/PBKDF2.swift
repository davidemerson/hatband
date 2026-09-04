#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// PBKDF2 with HMAC-SHA-256 (RFC 8018 §5.2) on the CryptoKit HMAC, which
/// neither CryptoKit nor swift-crypto exposes on its own.
public enum PBKDF2 {
    public static let hashLength = 32

    /// `iterations` must be positive. Output is prefix-consistent: a shorter
    /// key is the head of a longer one derived from the same inputs.
    public static func deriveKey(password: [UInt8], salt: [UInt8], iterations: Int, keyLength: Int) -> [UInt8] {
        precondition(iterations > 0, "PBKDF2 needs at least one iteration")
        precondition(keyLength >= 0, "PBKDF2 key length cannot be negative")
        // Keyed once; every PRF call continues from a copy of this state
        // (RFC 2104 §4), which is what makes the loop affordable.
        let prf = HMAC<SHA256>(key: SymmetricKey(data: password))
        var out: [UInt8] = []
        out.reserveCapacity(keyLength)
        var block: UInt32 = 1
        while out.count < keyLength {
            var first = prf
            first.update(data: salt)
            first.update(data: bigEndian(block))
            var u = [UInt8](repeating: 0, count: hashLength)
            first.finalize().withUnsafeBytes { code in
                for i in 0..<hashLength { u[i] = code[i] }
            }
            var t = u
            for _ in 1..<iterations {
                var mac = prf
                mac.update(data: u)
                mac.finalize().withUnsafeBytes { code in
                    for i in 0..<hashLength {
                        u[i] = code[i]
                        t[i] ^= code[i]
                    }
                }
            }
            out.append(contentsOf: t)
            block += 1
        }
        out.removeLast(out.count - keyLength)
        return out
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16),
         UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }
}
