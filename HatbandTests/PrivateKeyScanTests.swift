import Foundation
import HatbandCore
import Testing
@testable import Hatband

/// A card carries what the key boxes hold into a QR code and a file. A
/// private key pasted into one would be signed and handed to whoever scans
/// it, so it is refused at the box.
struct PrivateKeyScanTests {
    @Test func everyPrivateKeyArmourIsCaught() {
        for armour in [
            "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEA\n-----END OPENSSH PRIVATE KEY-----",
            "-----BEGIN RSA PRIVATE KEY-----\nMIIEow==\n-----END RSA PRIVATE KEY-----",
            "-----BEGIN EC PRIVATE KEY-----\nMHcCAQ==\n-----END EC PRIVATE KEY-----",
            "-----BEGIN DSA PRIVATE KEY-----\nMIIBuw==\n-----END DSA PRIVATE KEY-----",
            "-----BEGIN PRIVATE KEY-----\nMIIEvQ==\n-----END PRIVATE KEY-----",
            "-----BEGIN ENCRYPTED PRIVATE KEY-----\nMIIFHD==\n-----END ENCRYPTED PRIVATE KEY-----",
            "-----BEGIN PGP PRIVATE KEY BLOCK-----\n\nlQVYBGY=\n-----END PGP PRIVATE KEY BLOCK-----",
            "PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none",
            "   \n\n-----BEGIN OPENSSH PRIVATE KEY-----\nb3Bl\n",
            "-----begin openssh private key-----\nb3Bl\n",
        ] {
            #expect(PrivateKeyScan.looksPrivate(armour), "not caught: \(armour.prefix(40))")
        }
    }

    /// Public keys pass, including the awkward one: a comment that says
    /// "private key". Only the first line is read, and a public key line
    /// never begins with armour.
    @Test func publicKeysAndTheirCommentsPass() {
        for line in [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB1234567890abcdefghijklmnopqrstuvwxyz bloom@dublin",
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB1234 backup of my private key",
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQ== bloom",
            "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY= bloom",
            "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nmDMEZ=\n-----END PGP PUBLIC KEY BLOCK-----",
            "", "   ",
        ] {
            #expect(!PrivateKeyScan.looksPrivate(line), "wrongly refused: \(line.prefix(40))")
        }
    }
}
