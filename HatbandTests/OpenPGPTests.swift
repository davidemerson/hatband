import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct OpenPGPTests {
    /// RFC 9580 Appendix A.3, whose primary key fingerprint is
    /// CB186C4F0609A697E4D52DFA6C722B0C1F1E27C18A56708F6525EC27BAD9ACC9.
    private static let sampleA3Body = """
        xioGY4d/4xsAAAAg+U2nu0jWCmHlZ3BqZYfQMxmZu52JGggkLq2EVD34laPCsQYf
        GwoAAABCBYJjh3/jAwsJBwUVCg4IDAIWAAKbAwIeCSIhBssYbE8GCaaX5NUt+mxy
        KwwfHifBilZwj2Ul7Ce62azJBScJAgcCAAAAAK0oIBA+LX0ifsDm185Ecds2v8lw
        gyU2kCcUmKfvBXbAf6rhRYWzuQOwEn7E/aLwIwRaLsdry0+VcallHhSu4RN6HWaE
        QsiPlR4zxP/TP7mhfVEe7XWPxtnMUMtf15OyA51YBM4qBmOHf+MZAAAAIIaTJINn
        +eUBXbki+PSAld2nhJh/LVmFsS+60WyvXkQ1wpsGGBsKAAAALAWCY4d/4wKbDCIh
        BssYbE8GCaaX5NUt+mxyKwwfHifBilZwj2Ul7Ce62azJAAAAAAQBIKbpGG2dWTX8
        j+VjFM21J0hqWlEg+bdiojWnKfA5AQpWUWtnNwDEM0g12vYxoWM8Y81W+bHBw805
        I8kWVkXU6vFOi+HWvv/ira7ofJu16NnoUkhclkUrk0mXubZvyl4GBg==
        """

    private static let sampleA3 = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n" + sampleA3Body + "\n-----END PGP PUBLIC KEY BLOCK-----\n"

    private static let sampleA3Fingerprint = "CB186C4F0609A697E4D52DFA6C722B0C1F1E27C18A56708F6525EC27BAD9ACC9"

    /// The A.3 binary, decoded without the armor parser.
    private static func sampleA3Binary() throws -> [UInt8] {
        try Base64.decode(sampleA3Body.filter { !$0.isWhitespace })
    }

    /// A version 4 public-key body: version, creation time, algorithm 22, key bytes.
    private static let v4Body: [UInt8] = [4, 0, 0, 0, 0, 22] + (1...32).map { UInt8($0) }

    @Test func v4FingerprintFraming() {
        let packet = [0x98, UInt8(OpenPGPTests.v4Body.count)] + OpenPGPTests.v4Body
        let fingerprint = OpenPGP.fingerprint(ofCertificate: packet)
        // SHA-1 over 0x99, the two-octet length and the body, computed independently.
        #expect(fingerprint.map { Hex.string($0) } == "a58df50a90c69c78972ea22dccdf7ce3cf0238eb")
        #expect(fingerprint?.count == 20)
        // The new-format header and a two-octet old-format length frame the same body.
        let newFormat = [0xC6, UInt8(OpenPGPTests.v4Body.count)] + OpenPGPTests.v4Body
        #expect(OpenPGP.fingerprint(ofCertificate: newFormat) == fingerprint)
        let twoOctet = [0x99, 0, UInt8(OpenPGPTests.v4Body.count)] + OpenPGPTests.v4Body
        #expect(OpenPGP.fingerprint(ofCertificate: twoOctet) == fingerprint)
        // Trailing packets are ignored; a truncated body is refused.
        #expect(OpenPGP.fingerprint(ofCertificate: packet + [0x88, 1, 0]) == fingerprint)
        #expect(OpenPGP.fingerprint(ofCertificate: Array(packet.dropLast())) == nil)
    }

    @Test func v6FingerprintMatchesRFC9580SampleA3() throws {
        let binary = try OpenPGPTests.sampleA3Binary()
        let fingerprint = try #require(OpenPGP.fingerprint(ofCertificate: binary))
        #expect(fingerprint.count == 32)
        #expect(Hex.string(fingerprint).uppercased() == OpenPGPTests.sampleA3Fingerprint)
        let armored = try #require(OpenPGP.dearmor(OpenPGPTests.sampleA3))
        #expect(OpenPGP.fingerprint(ofCertificate: armored) == fingerprint)
    }

    @Test func refusesNonKeyPacket() {
        let body = OpenPGPTests.v4Body
        // Tag 2 (signature) and tag 14 (public subkey), old and new format.
        #expect(OpenPGP.fingerprint(ofCertificate: [0x88, UInt8(body.count)] + body) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0xB8, UInt8(body.count)] + body) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0xC2, UInt8(body.count)] + body) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0xCE, UInt8(body.count)] + body) == nil)
        // Not a packet at all, or an unknown key version.
        #expect(OpenPGP.fingerprint(ofCertificate: []) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0x06, 2, 4, 0]) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0x98, 2, 5, 0]) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0x98, 0]) == nil)
    }

    @Test func refusesPartialLength() {
        let body = OpenPGPTests.v4Body
        // New format: first octets 224 to 254 are partial body lengths.
        #expect(OpenPGP.fingerprint(ofCertificate: [0xC6, 0xE0] + body) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0xC6, 0xFE] + body) == nil)
        // Old format: length type 3 is indeterminate.
        #expect(OpenPGP.fingerprint(ofCertificate: [0x9B] + body) == nil)
        // A header with no length octet.
        #expect(OpenPGP.fingerprint(ofCertificate: [0xC6]) == nil)
        #expect(OpenPGP.fingerprint(ofCertificate: [0xC6, 0xFF, 0, 0]) == nil)
    }

    @Test func dearmorSample() throws {
        let binary = try OpenPGPTests.sampleA3Binary()
        #expect(binary.count == 424)
        #expect(OpenPGP.dearmor(OpenPGPTests.sampleA3) == binary)
        // Headers, a matching CRC-24 line, CRLF endings and surrounding text.
        let crc = "=" + Base64.encode(OpenPGP.crc24(binary))
        #expect(crc == "=n06I")
        let dressed = "Here is my key:\r\n-----BEGIN PGP PUBLIC KEY BLOCK-----\r\nComment: RFC 9580 A.3\r\nVersion: test\r\n\r\n"
            + OpenPGPTests.sampleA3Body.replacingOccurrences(of: "\n", with: "\r\n")
            + "\r\n" + crc + "\r\n-----END PGP PUBLIC KEY BLOCK-----\r\n"
        #expect(OpenPGP.dearmor(dressed) == binary)
        // No BEGIN line, no END line, or an empty body.
        #expect(OpenPGP.dearmor(OpenPGPTests.sampleA3Body) == nil)
        #expect(OpenPGP.dearmor("-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n" + OpenPGPTests.sampleA3Body) == nil)
        #expect(OpenPGP.dearmor("-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n-----END PGP PUBLIC KEY BLOCK-----\n") == nil)
    }

    @Test func dearmorRejectsBadCRC() throws {
        let binary = try OpenPGPTests.sampleA3Binary()
        let good = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n" + OpenPGPTests.sampleA3Body + "\n=n06I\n-----END PGP PUBLIC KEY BLOCK-----\n"
        #expect(OpenPGP.dearmor(good) == binary)
        let wrong = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n" + OpenPGPTests.sampleA3Body + "\n=n06J\n-----END PGP PUBLIC KEY BLOCK-----\n"
        #expect(OpenPGP.dearmor(wrong) == nil)
        let malformed = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n" + OpenPGPTests.sampleA3Body + "\n=n0\n-----END PGP PUBLIC KEY BLOCK-----\n"
        #expect(OpenPGP.dearmor(malformed) == nil)
        #expect(OpenPGP.crc24([]) == [0xB7, 0x04, 0xCE])
    }

    @Test func wkdHashJoeDoe() {
        #expect(OpenPGP.wkdHash(local: "Joe.Doe") == "iy9q119eutrkn8s1mk4r39qejnbu3n5q")
        #expect(OpenPGP.wkdHash(local: "joe.doe") == "iy9q119eutrkn8s1mk4r39qejnbu3n5q")
        #expect(OpenPGP.wkdHash(local: "Joe.Doe").count == 32)
        #expect(OpenPGP.zBase32([]) == "")
        #expect(OpenPGP.zBase32([0]) == "yy")
    }
}
