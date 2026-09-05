import CryptoKit
import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct VerifyTests {
    /// RFC 9580 Appendix A.3: the sample version 6 certificate, and the
    /// fingerprint it states for the primary key.
    static let sampleCertificateArmor = [
        "xioGY4d/4xsAAAAg+U2nu0jWCmHlZ3BqZYfQMxmZu52JGggkLq2EVD34laPCsQYf",
        "GwoAAABCBYJjh3/jAwsJBwUVCg4IDAIWAAKbAwIeCSIhBssYbE8GCaaX5NUt+mxy",
        "KwwfHifBilZwj2Ul7Ce62azJBScJAgcCAAAAAK0oIBA+LX0ifsDm185Ecds2v8lw",
        "gyU2kCcUmKfvBXbAf6rhRYWzuQOwEn7E/aLwIwRaLsdry0+VcallHhSu4RN6HWaE",
        "QsiPlR4zxP/TP7mhfVEe7XWPxtnMUMtf15OyA51YBM4qBmOHf+MZAAAAIIaTJINn",
        "+eUBXbki+PSAld2nhJh/LVmFsS+60WyvXkQ1wpsGGBsKAAAALAWCY4d/4wKbDCIh",
        "BssYbE8GCaaX5NUt+mxyKwwfHifBilZwj2Ul7Ce62azJAAAAAAQBIKbpGG2dWTX8",
        "j+VjFM21J0hqWlEg+bdiojWnKfA5AQpWUWtnNwDEM0g12vYxoWM8Y81W+bHBw805",
        "I8kWVkXU6vFOi+HWvv/ira7ofJu16NnoUkhclkUrk0mXubZvyl4GBg==",
    ].joined()
    static let sampleFingerprintHex = "CB186C4F0609A697E4D52DFA6C722B0C1F1E27C18A56708F6525EC27BAD9ACC9"

    private func ed25519Line(comment: String? = nil) throws -> (line: String, field: SSHKeyField) {
        let raw = Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        let key = try SSHPublicKey(kind: .ed25519, inlineBytes: raw)
        return (key.authorizedKeysLine(comment: comment), SSHKeyField(kind: SSHPublicKey.Kind.ed25519.rawValue, bytes: raw))
    }

    /// An RFC 4253 `ssh-rsa` blob: the type, then e and n as mpints.
    private func rsaBlob() -> [UInt8] {
        func field(_ bytes: [UInt8]) -> [UInt8] {
            let n = UInt32(bytes.count)
            return [UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)] + bytes
        }
        let modulus: [UInt8] = [0x7f] + (1...255).map { UInt8($0 & 0xff) }
        return field(Array("ssh-rsa".utf8)) + field([0x01, 0x00, 0x01]) + field(modulus)
    }

    @Test func githubKeysMatchesSecondLine() throws {
        let first = try ed25519Line(comment: "laptop")
        let second = try ed25519Line(comment: "phone")
        let text = first.line + "\n" + second.line + "\n"
        #expect(Verify.githubKeys(text, matches: second.field))
        #expect(Verify.githubKeys(text, matches: first.field))
    }

    @Test func githubKeysNoMatch() throws {
        let listed = try ed25519Line()
        let wanted = try ed25519Line()
        #expect(!Verify.githubKeys(listed.line + "\n", matches: wanted.field))
        #expect(!Verify.githubKeys("", matches: wanted.field))
        #expect(!Verify.githubKeys("not a key\n<html></html>", matches: wanted.field))
        let wrongKind = SSHKeyField(kind: SSHPublicKey.Kind.rsa.rawValue, bytes: listed.field.bytes)
        #expect(!Verify.githubKeys(listed.line, matches: wrongKind))
    }

    @Test func rsaMatchesByFingerprint() throws {
        let blob = rsaBlob()
        let key = try SSHPublicKey(blob: blob)
        #expect(key.kind == .rsa)
        let line = "ssh-rsa " + Base64.encode(blob) + " bloom@example.ie"
        let field = SSHKeyField(kind: SSHPublicKey.Kind.rsa.rawValue, bytes: key.fingerprintSHA256)
        #expect(Verify.githubKeys("junk\n" + line, matches: field))
        let other = SSHKeyField(kind: SSHPublicKey.Kind.rsa.rawValue, bytes: [UInt8](repeating: 1, count: 32))
        #expect(!Verify.githubKeys(line, matches: other))
    }

    @Test func certificateMatchesFingerprint() throws {
        let bytes = try Base64.decode(VerifyTests.sampleCertificateArmor)
        let fingerprint = try #require(Hex.bytes(VerifyTests.sampleFingerprintHex))
        #expect(fingerprint.count == 32)
        #expect(Verify.certificate(bytes, matches: fingerprint))
        var wrong = fingerprint
        wrong[0] ^= 1
        #expect(!Verify.certificate(bytes, matches: wrong))
        #expect(!Verify.certificate([], matches: fingerprint))
        let synthetic = syntheticV4Certificate()
        #expect(Verify.certificate(synthetic.packet, matches: synthetic.fingerprint))
        #expect(!Verify.certificate(synthetic.packet, matches: fingerprint))
    }

    private func lookup(verifiedAt: String?, href: String = "https://nnix.com/~bloom") -> Data {
        let verified = verifiedAt.map { "\"" + $0 + "\"" } ?? "null"
        let value = "<a href=\\\"" + href + "\\\" rel=\\\"me nofollow\\\">nnix.com/~bloom</a>"
        let json = "{\"id\":\"1\",\"acct\":\"bloom\",\"fields\":[{\"name\":\"Web\",\"value\":\"" + value
            + "\",\"verified_at\":" + verified + "},{\"name\":\"Pub\",\"value\":\"Davy Byrne's\",\"verified_at\":null}]}"
        return Data(json.utf8)
    }

    @Test func mastodonVerifiedAtTrue() {
        let json = lookup(verifiedAt: "2026-06-16T08:00:00.000Z")
        #expect(Verify.mastodonVerified(json: json, website: "https://nnix.com/~bloom"))
        #expect(Verify.mastodonVerified(json: json, website: "https://NNIX.com/~bloom/"))
        #expect(!Verify.mastodonVerified(json: json, website: "https://example.org"))
        #expect(!Verify.mastodonVerified(json: json, website: "https://evilnnix.com/~bloom"))
    }

    @Test func verifiedAtNullFalse() {
        #expect(!Verify.mastodonVerified(json: lookup(verifiedAt: nil), website: "https://nnix.com/~bloom"))
        #expect(!Verify.mastodonVerified(json: lookup(verifiedAt: ""), website: "https://nnix.com/~bloom"))
    }

    @Test func malformedJSONFalse() {
        #expect(!Verify.mastodonVerified(json: Data("{".utf8), website: "https://nnix.com/~bloom"))
        #expect(!Verify.mastodonVerified(json: Data("[]".utf8), website: "https://nnix.com/~bloom"))
        #expect(!Verify.mastodonVerified(json: Data("{\"fields\":\"no\"}".utf8), website: "https://nnix.com/~bloom"))
        #expect(!Verify.mastodonVerified(json: Data(), website: "https://nnix.com/~bloom"))
    }
}
