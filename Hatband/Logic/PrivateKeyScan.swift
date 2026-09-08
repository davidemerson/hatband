import Foundation

/// Refusing a private key before it is stored, never mind shared. The key
/// boxes on the profile screen sit next to each other, and a card carries
/// what is in them into a QR code and a file: a private key pasted into the
/// wrong one would be signed and handed to whoever scans it.
///
/// Only the first line is read. A public key line never begins with armour,
/// while every private form does, so a public key whose comment happens to
/// say "private key" is not caught by mistake.
nonisolated enum PrivateKeyScan {
    /// PEM and OpenSSH armour: `-----BEGIN … PRIVATE KEY…-----`, which covers
    /// OPENSSH, RSA, DSA, EC, ENCRYPTED and PGP PRIVATE KEY BLOCK. PuTTY uses
    /// its own header and no armour at all.
    static func looksPrivate(_ text: String) -> Bool {
        let first = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { !$0.isNewline }
            .uppercased()
        if first.hasPrefix("PUTTY-USER-KEY-FILE") { return true }
        guard first.hasPrefix("-----BEGIN") else { return false }
        return first.contains("PRIVATE KEY")
    }

    static let refusal = "That is a private key. Paste the public one; a private key would go out on your card."
}
