import Foundation
import Testing
@testable import HatbandCore

// Adversarial review of the Interop module: parity with the tools it imitates
// (ssh-keygen, Foundation's Base64), hostile input, fixed points of the stored
// forms, and crash fuzzing. Fixtures were produced on this machine with
// OpenSSH 10.0p2; expected randomart is what `ssh-keygen -lvf` printed.

// MARK: - Helpers

private struct Xorshift {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func bytes(_ n: Int) -> [UInt8] { (0..<n).map { _ in UInt8(truncatingIfNeeded: next()) } }
}

/// Fragments that exercise every parser's edges: separators, schemes, hosts,
/// escapes, controls, format characters, case-mapping traps and wide glyphs.
private let fragments: [String] = [
    "a", "b", "z", "A", "Z", "0", "1", "9", "-", "_", ".", "..", "/", "//", ":", "://", "@", "@@", "#", "?", "&", "=", "%", "%2F", "%C3", "%ZZ", "+", "++",
    " ", "\t", "\n", "\r", "\r\n", "\u{0}", "\u{7f}", "\u{85}", "\u{a0}", "\u{200B}", "\u{202E}", "\u{FEFF}", "\u{2028}", "\u{2029}",
    "é", "e\u{301}", "ß", "İ", "ı", "\u{212A}", "水", "🎩", "\u{1F1EE}\u{1F1EA}", "ﬁ", "Ⅷ", "²", "Ｅ", "０",
    "https", "http", "HTTPS", "ftp", "javascript", "mailto", "tel", "sgnl", "0x", "OPENPGP4FPR", "in", "company", "users", "d", "eu", "p",
    "github.com", "linkedin.com", "calendly.com", "signal.me", "www", "com", "ie",
    "<", ">", "\"", "'", "\\", "[", "]", "(", ")", "{", "}", "|", "^", "`", "~", ";", ",", "*", "!", "$",
    "ssh-ed25519", "ssh-rsa", "ecdsa-sha2-nistp256", "sk-", "AAAA", "AAAAC3NzaC1lZDI1NTE5AAAAI", "==", "=",
    "BEGIN:VCARD", "END:VCARD", "VERSION:3.0", "N:", "FN:", "PHOTO;ENCODING=b:", "item1.URL:", "X-HATBAND-",
]

private func fuzzString(_ rng: inout Xorshift, maxFragments: Int = 12) -> String {
    (0..<rng.below(maxFragments)).map { _ in fragments[rng.below(fragments.count)] }.joined()
}

private func wireString(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(string: s, to: &out)
    return out
}

private func wireBytes(_ b: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(bytes: b, to: &out)
    return out
}

// MARK: - ssh-keygen parity

private struct Keygen: Sendable {
    let line: String
    let kind: SSHPublicKey.Kind
    let bits: Int
    let comment: String?
    let fingerprint: String
    let randomart: String
}

/// Sixteen keys made here with `ssh-keygen -t ...`, including the 1024-bit
/// floor, an odd 1025-bit modulus, and one Ed25519 key chosen so that the
/// bishop's walk ends where it started.
private let keygenFixtures: [Keygen] = [
    Keygen(
        line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhSfU3PSOUJOi1pkHP8PHFYZ4L8LkGzswU5Ks3CWbn7 ed1",
        kind: .ed25519, bits: 256, comment: "ed1",
        fingerprint: "SHA256:oqfjdO+BgMuSm2lusmTp5kmOa3B6+1a0j8PFvjZcFeY",
        randomart: """
    +--[ED25519 256]--+
    |                 |
    |            o    |
    |           o .   |
    |   .  .     E    |
    |  . ...oS  .     |
    |.oo. oooo .      |
    |+Bo oo+*..       |
    |XXo.o++.*.       |
    |/X.=+. ++o       |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQiIFvNDl1eUn4UxU3vokmNmSHk9Q71xgIFyMBzY7bf ed2",
        kind: .ed25519, bits: 256, comment: "ed2",
        fingerprint: "SHA256:sOviCNgGXc77/J4SkIs1SRAXoaUnv9dmp9K7xY89Mjw",
        randomart: """
    +--[ED25519 256]--+
    |  oo=o           |
    |   =.            |
    |  +.oo.          |
    | . B*  o         |
    |. .o++. S        |
    |.o. .o.o .       |
    |o o o oo+.+      |
    | o ..=oo.=E+.    |
    |  ....+=Bo.+o.   |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOXH8MYDkgrGLmaASTBaEpuBYgeIFi4GMR4pihtsXmUm ed3",
        kind: .ed25519, bits: 256, comment: "ed3",
        fingerprint: "SHA256:7x8Zq7x++6ghP4uOhIVX9cr2fE8AzbhiCuPuw+b2vqc",
        randomart: """
    +--[ED25519 256]--+
    |          .      |
    |         . . +   |
    |        .   + o  |
    |     . . . . o   |
    |    . = S * o .  |
    |     = o = + + . |
    |    ..o o o * . .|
    |     o=. *oo.+ o |
    |     ===E=XB+o. .|
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHfcNfpm5OBbxkdExTnsL9uIzQWA3WAGCgIU/nQqyPQQ ed4",
        kind: .ed25519, bits: 256, comment: "ed4",
        fingerprint: "SHA256:ClTpGeG8/9rmkmCyhOdkbv6X0RML6uIuuu0wDGrIook",
        randomart: """
    +--[ED25519 256]--+
    |      oo         |
    |     +o          |
    |    ..oo         |
    |   .  o.. .      |
    |.  .. ..So o     |
    |* . *.+o. +      |
    |*+ B =...+ .     |
    |==. * . =o.      |
    |E+o*+o...=+      |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzR63N2o/7mAKL2trnXmvJxTijcDYjWQ5uHFNw3n1si ed5",
        kind: .ed25519, bits: 256, comment: "ed5",
        fingerprint: "SHA256:xSP1jeZd9TcAQwqy7BpwfT8hdEx3H02UjU+5D8q3Le8",
        randomart: """
    +--[ED25519 256]--+
    |     . oooo=.o =O|
    |    o + o+o.oo+oB|
    | . . + o.o+ + .==|
    |  o . . oo.+ ..o+|
    |   . .  So ......|
    |    o     . o . .|
    |   .         . o |
    |              o .|
    |               +E|
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFBNCY4F183MN3g2NlykfgWF7wymu/L29rRcFwk3hICL ed6",
        kind: .ed25519, bits: 256, comment: "ed6",
        fingerprint: "SHA256:JqKtpQ5mwoh2zyN/5cgtuhUm9emX+R3gzKuWAps8uTs",
        randomart: """
    +--[ED25519 256]--+
    |                 |
    |                 |
    |       .         |
    |      . . .      |
    |    ...oSo   .   |
    |+  o .o+o.  * .  |
    |==..o o.X. +.+ . |
    |=..=o..E +.o. o .|
    | .+ o*=o* o..o . |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBN4ZoPHcRtH8cPaFMqeyvWItgJsh46y/yYjHSPYt9xMmxSYlbKkoMG21F3tih1v0lM0rr9WE5G5JZYM0lYbnQkc= ec256_1",
        kind: .ecdsaP256, bits: 256, comment: "ec256_1",
        fingerprint: "SHA256:oOtFSh87tLt7Q30y+ry5h71jXzrWkMIQC6AQL4x2Dlk",
        randomart: """
    +---[ECDSA 256]---+
    |  oE  ..         |
    | ooo .  . .      |
    |.+o.o .  . o     |
    |. +. . .  o      |
    |   .o + S. o   . |
    |   . * +. + + o  |
    |    o *. . * . o.|
    |   . . o+...= oo.|
    |    . ++ o*=.=o. |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEIydkc6gjDp40nRgqpvu4iUPFn37+8IUPz3ju+sKFTjot/ggXMIUeT6yAdcXkfS9XQs/fnMQGmopVSGhqxT+8s= ec256_2",
        kind: .ecdsaP256, bits: 256, comment: "ec256_2",
        fingerprint: "SHA256:8CDzhX+LpF9u5S1p64HkCaFuYkQ0ekXfB/RyX+8+gGQ",
        randomart: """
    +---[ECDSA 256]---+
    |    o.o  .o      |
    |   o o o . o     |
    |  . = + + o +   .|
    |   o + B . E . ..|
    |    . o S = . . .|
    |   . . o * =.. . |
    |    o + . *o.o. .|
    |   . o . o. =..o |
    |        ...ooo  o|
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBIaIe8kfgEwICRZ+BIJu0Zi8JKPkQsRlcECzPKQRzaviLPM/0tf69Y9dODhc0MHIN2qvRKvj/0pwa9j55NAPwXl2bEW5lQDfwd79O5yim64m+lvlrshLJsJfqH9E/0P8gw== ec384_1",
        kind: .ecdsaP384, bits: 384, comment: "ec384_1",
        fingerprint: "SHA256:GppOOWjU9haSpX5Xqi7m03azB4hDHdNp8amIzcrsRKM",
        randomart: """
    +---[ECDSA 384]---+
    |       ..o       |
    |      o +. .     |
    |     ..+  o      |
    |   ..B.. .       |
    |  ..X.*.S .      |
    | . OoO.+.o       |
    |  E %o= o.       |
    | . =++ooo .      |
    |   o+=o..+       |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBMaQ1gkfy+hRTR1RoWhHyDwpZToWSkxSjOBweM/xYnuACCnE3fbB6SYpsBC4AAIcM4Lm2aiGomQB3wdgwpsOgF1Rsxe3RHUrJ5wICIp5+tsAZVrkGlCNYZWeuMQi7ntpYw== ec384_2",
        kind: .ecdsaP384, bits: 384, comment: "ec384_2",
        fingerprint: "SHA256:QSb8lgreNq9f8uh4X0mjGDvF+UZhrX0Zn9q5xR2GY+k",
        randomart: """
    +---[ECDSA 384]---+
    |     .. o        |
    |      .+     .   |
    |       ...  o .. |
    |    .   +o o +o =|
    |   . o oS + ==.=o|
    |    . =  = =oo=o+|
    |     . o= o =E o+|
    |       .o* o    o|
    |      o=+.o    . |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBABr+21bRVzfa/3PRCzySOqZsoQ60BTTLXtCAAZTrLVuzkmj0jhLJEgvEKdrlLrha2kei60o36dS4TfBqd5dILIlaQAdE67TGyppJHJ1ulUb4KUsQXrKzMyURIiDhYnHw5drPF5LjfJJRRwRW2vlNTGOp90uVKxqThxvYkAItXlgzkNV3Q== ec521_1",
        kind: .ecdsaP521, bits: 521, comment: "ec521_1",
        fingerprint: "SHA256:zhh2Ap8ILrSfUu8vxzbvf94/4oZOflsVjbFrCqbUXvU",
        randomart: """
    +---[ECDSA 521]---+
    |              .  |
    |               +.|
    | .. .         +..|
    |.... + . .   . o.|
    |..... * S + . o E|
    | .o o. O + o o  .|
    | . o .o + ..o  . |
    |  . .. =  o. =o. |
    |     .=.+oo+*+o.+|
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAB0VuyBKZLfHgDcwy+dDvKcceYeJRjcrr62kSLyOnxWU2uJgzbJ82GCO2lHRRW4UTa6zRZ8GUfJrGSQgh6a5qbKMAErYhKRJJfOdH6jnb+ftQVde2B1GNyX7mMa0mENnHqAaye2MJPWIkANCeEON+ALtS7EdlhjQR771wmxHNEFNnaCGQ== ec521_2",
        kind: .ecdsaP521, bits: 521, comment: "ec521_2",
        fingerprint: "SHA256:x9IviYXtx0F1I+oMCXFe7vpThVg6W1EUhNXLtqkUUfU",
        randomart: """
    +---[ECDSA 521]---+
    |       o.. . .OO*|
    |        + + .*..+|
    |         + o= = E|
    |         === + = |
    |        S *+= + o|
    |         *.= + o |
    |        ..+ * .  |
    |          .+ .   |
    |           ..    |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCau0u34Onl/abF+jI3VZAyGKjJg5XfgOSeGz3PEXQI7yiSinRo8b3GnR4iRorsvF+dxD5kX8eZTe5J7g3cjL4/dORWyceqyXzcxluFEUB++vAyOPu8PZT1yO0uJo5trzD2Y+HjtXu8hk0oUjJ+MvrQ2lBb8BHJJEzOwQFLN3x/CRUX9ipIfBB/XaW5Xzu4WcKywDtzQ9wFdbbDvvzsrL+goHaW4ISQJu20UtoeC/cyjSXnwHrkqwvFqD4XF8ovSeCCLdwRtfXD6PC6L3EADDz+82OeRJyDcQkuBeLjHrT8kLDNYEe7XxTGQvw8puRFBf1yjgNLFXRteQXkLI4S6HHuyC7DFK+6QDTsJQCfekGbAbMIMtGy+x3forteX8vnQWl6Eiz7SBKbT3Cki1YN/4ak6F0dN1iNeranOPnyPY0UYEdYQ6fdENPL1IXsRVJb1ihKhjWyFXC+Q5ivWEbBP6gKOZZuybPdEa/7QjHqOemhi40j2wN/cyCGYVkvKu0sXrtUBk3V4+ZwROIIrLdbNWLIXsYsjNFM/pzlS+WyHG+Gv5boS7nyTh6f7sfPT4Sk5Z4Y58w7kNo/ZTJCCJDoTzBEzF6lVdvDaVQCcsD2q77QNmmkjo/WO+wc7vbWqo+kdKxczfn4iI4xDm/ClpRDSbzeOsKCZCkxEOEQou9kaudkxw== rsa4096",
        kind: .rsa, bits: 4096, comment: "rsa4096",
        fingerprint: "SHA256:pubwcUIAZ38mJrL71p1rqfNZ6dtNwPSzoVZH0RwzeKo",
        randomart: """
    +---[RSA 4096]----+
    |  . o         .*o|
    |   + .       . .*|
    |  . o + o   . o .|
    |   o + +   o o . |
    |  .   . S   + = .|
    |   . . o   E + = |
    |  . ..=..oo o o  |
    |   ..=o+=+ o o   |
    |   .. +=+.o.. .  |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDNOwJy+Yt8lgKl5xmPKO5Bfijqu9Z18sUoXEaB83Gu1/pzkVf2kgZJDh2uR+LlTaiw/iElAQ/k6EcrJRO50y/TXDafHN6MEvB/Yej3NdafnwNHCtvX6DaKZNC5sQjTBdmCP1wH+2xgBgONU7iY1cBifX4OZ9nF3ZQirFo7scDYtw== rsa1024",
        kind: .rsa, bits: 1024, comment: "rsa1024",
        fingerprint: "SHA256:Q7sSlvf1iopRBhWwt1Xz3OoN/8uHzjYDENVMYllT37k",
        randomart: """
    +---[RSA 1024]----+
    |      ..o. .**+..|
    |       o  .o.=oo+|
    |      o o ..  o.+|
    |       = +.    ..|
    |      + S  .. oE |
    |     . = + ..o + |
    |      o . .  .o.o|
    |       +   . o* o|
    |      . ... .oo=+|
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQF02rmHv/cUQ+QMJWwMy+O/ggOndwsuo8t9kLiUhWGZaRUhCj/UrHrKzUefPlC/RbIdFCm3qtqMBPRHhOPGTAaEwsTQvAHQw7+UpowP54uGBdXZQ8O5PCl07/afjP6YxHXn7RmhlHDCb7Z3sbFedkfQRrj8BKBHnxeZ+IXGmRnLYw== rsa1025",
        kind: .rsa, bits: 1025, comment: "rsa1025",
        fingerprint: "SHA256:doK3hiQmdH6SDq4UZFdDrE6KHDyEl9DtbXihnLgDbXg",
        randomart: """
    +---[RSA 1025]----+
    |oo oo+           |
    |..+ o.o          |
    |o*.=o= .         |
    |==E=*.+.         |
    |o=O.*o+ S .      |
    |.++* = + +       |
    | .... . o        |
    |..     .         |
    |.                |
    +----[SHA256]-----+
    """),
    Keygen(
        line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6crekENE2EZ3o46kEUccu6rQ9CDBDi75q0EgY2baU0 centre",
        kind: .ed25519, bits: 256, comment: "centre",
        fingerprint: "SHA256:FSGyNVuexRfgJZMZOoAWfhQJDcu1FplcHuCJI9OZvS0",
        randomart: """
    +--[ED25519 256]--+
    |      =B@B*o*=o. |
    |     +o&*% B++.  |
    |    o.@ O B ..   |
    |     o + + .     |
    |        E .      |
    |         .       |
    |                 |
    |                 |
    |                 |
    +----[SHA256]-----+
    """),
]

@Test(arguments: keygenFixtures.indices)
func keygenParity(index: Int) throws {
    let fixture = keygenFixtures[index]
    let key = try SSHPublicKey(line: fixture.line)
    #expect(key.kind == fixture.kind)
    #expect(key.bits == fixture.bits)
    #expect(key.comment == fixture.comment)
    #expect(key.fingerprintString == fixture.fingerprint)
    #expect(key.authorizedKeysLine() == fixture.line)
    #expect(key.randomart == fixture.randomart)
    #expect(key.storedBytes.count == (fixture.kind.inlineLength ?? 32))
    if let inline = key.inlineBytes {
        let rebuilt = try SSHPublicKey(kind: fixture.kind, inlineBytes: inline, comment: fixture.comment)
        #expect(rebuilt == key)
        #expect(rebuilt.randomart == fixture.randomart)
    }
    // ssh-keygen accepts the base64 field without its padding; so do we, and
    // the line we write back is the padded original.
    let fields = fixture.line.split(separator: " ", maxSplits: 2)
    let unpadded = String(fields[1].prefix { $0 != "=" })
    let loose = try SSHPublicKey(line: "\(fields[0]) \(unpadded)" + (fields.count == 3 ? " \(fields[2])" : ""))
    #expect(loose == key)
    #expect(loose.authorizedKeysLine() == fixture.line)
}

/// OpenSSH marks the start cell first and the end cell second, so a walk that
/// ends in the centre shows `E` and no `S` (sshkey.c, `fingerprint_randomart`).
/// The `centre` key above was chosen for exactly that walk; `ssh-keygen -lv`
/// prints `E` in the middle of row five.
@Test func randomartEndMarkerWinsOverStart() throws {
    let key = try SSHPublicKey(line: keygenFixtures.last!.line)
    let rows = key.randomart.split(separator: "\n")
    #expect(rows[5] == "|        E .      |")
    // Borders carry letters of their own; only the field may be checked.
    #expect(!rows[1...9].joined().contains("S"))
    // A single byte whose four moves form a closed diamond ends at the start.
    let diamond = SSHPublicKey.randomart(fingerprint: [0b1011_0001], title: "[TEST]")
    let diamondRows = diamond.split(separator: "\n")
    #expect(diamondRows[5] == "|        E        |")
    #expect(!diamondRows[1...9].joined().contains("S"))
}

/// Synthetic walks checked against a reference implementation that reproduces
/// every `ssh-keygen -lv` fixture above: the visit-count cap at `^`, clamping
/// in every corner, and inputs of unusual length.
private let syntheticArt: [(fingerprint: [UInt8], art: String)] = [
    ([UInt8](repeating: 0x11, count: 32), """
    +-----[TEST]------+
    |        E^       |
    |         .       |
    |        .        |
    |         .       |
    |        S        |
    |                 |
    |                 |
    |                 |
    |                 |
    +----[SHA256]-----+
    """),
    ([UInt8](repeating: 0xff, count: 32), """
    +-----[TEST]------+
    |                 |
    |                 |
    |                 |
    |                 |
    |        S        |
    |         .       |
    |          .      |
    |           .     |
    |            ....E|
    +----[SHA256]-----+
    """),
    (Array(0..<7), """
    +-----[TEST]------+
    |E=o.o.           |
    |.o   .           |
    |      .          |
    |       .         |
    |        S        |
    |                 |
    |                 |
    |                 |
    |                 |
    +----[SHA256]-----+
    """),
    ((0..<300).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }, """
    +-----[TEST]------+
    |   ..+=@/^Bo.    |
    |  . =+&^^^OX     |
    |   .B#^^^^^+B    |
    |   .X^^^^^@^     |
    |   +*^E^S^^=     |
    |  +.O^^^^^&X     |
    |   =X^^^^^^*.    |
    |  . @O^^^^OX.    |
    |   .+X=B%@B=+    |
    +----[SHA256]-----+
    """),
]

@Test(arguments: syntheticArt.indices)
func randomartSyntheticWalks(index: Int) {
    let (fingerprint, art) = syntheticArt[index]
    #expect(SSHPublicKey.randomart(fingerprint: fingerprint, title: "[TEST]") == art)
}

@Test(arguments: [0, 1, 2, 31, 32, 33, 64, 300])
func randomartAlwaysHasTheSameShape(length: Int) {
    var rng = Xorshift(state: UInt64(length) &* 0x9E37_79B9 | 1)
    for _ in 0..<20 {
        let art = SSHPublicKey.randomart(fingerprint: rng.bytes(length), title: "[X]")
        let rows = art.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(rows.count == 11)
        #expect(rows.allSatisfy { $0.count == 19 })
        #expect(rows.dropFirst().dropLast().allSatisfy { $0.first == "|" && $0.last == "|" })
        #expect(rows.first!.first == "+" && rows.last!.last == "+")
        #expect(art.filter { $0 == "S" }.count + art.filter { $0 == "E" }.count >= 1)
        #expect(art.unicodeScalars.allSatisfy { " .o+=*BOX@%&#/^SE|+-[]HA256\n".unicodeScalars.contains($0) })
    }
}

// MARK: - ssh-keygen divergences that are deliberate

@Test func rejectsWhatKeygenToleratesOnPurpose() throws {
    let ed1 = keygenFixtures[0]
    let key = try SSHPublicKey(line: ed1.line)
    let inline = try #require(key.inlineBytes)
    // A FIDO key line: ssh-keygen prints an ED25519-SK fingerprint; the card
    // cannot vouch for the authenticator, so it is refused by name.
    let sk = "sk-ssh-ed25519@openssh.com " + Base64.encode(wireString("sk-ssh-ed25519@openssh.com") + wireBytes(inline) + wireString("ssh:")) + " c"
    #expect(throws: SSHPublicKey.Error.securityKey("sk-ssh-ed25519@openssh.com")) { try SSHPublicKey(line: sk) }
    #expect(throws: SSHPublicKey.Error.securityKey("sk-ecdsa-sha2-nistp256@openssh.com")) {
        try SSHPublicKey(blob: wireString("sk-ecdsa-sha2-nistp256@openssh.com") + wireString("nistp256"))
    }
    // ssh-keygen skips a leading options field; we recognise it and refuse.
    #expect(throws: SSHPublicKey.Error.optionsNotSupported) {
        try SSHPublicKey(line: "no-pty,command=\"x\" " + ed1.line)
    }
    #expect(throws: SSHPublicKey.Error.optionsNotSupported) {
        try SSHPublicKey(line: "from=\"a b\",command=\"echo \\\"ssh-rsa\\\"\" " + ed1.line)
    }
    // A key whose base64 says one type and whose blob says another.
    #expect(throws: SSHPublicKey.Error.typeMismatch) {
        try SSHPublicKey(line: "ssh-ed25519 " + Base64.encode(try SSHPublicKey(line: keygenFixtures[6].line).blob))
    }
}

// MARK: - SSH wire blobs

@Test func rejectsHostileBlobs() throws {
    let ed1 = try SSHPublicKey(line: keygenFixtures[0].line)
    let p256 = try SSHPublicKey(line: keygenFixtures[6].line)
    let p384 = try SSHPublicKey(line: keygenFixtures[8].line)
    // Type strings that are not UTF-8, or carry a NUL, never match a kind.
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireBytes([0xff, 0xfe, 0x00]) + wireBytes(ed1.inlineBytes!)) }
    #expect(throws: SSHPublicKey.Error.unsupportedType("ssh-ed25519\u{0}")) { try SSHPublicKey(blob: wireString("ssh-ed25519\u{0}") + wireBytes(ed1.inlineBytes!)) }
    #expect(throws: SSHPublicKey.Error.unsupportedType("")) { try SSHPublicKey(blob: wireString("")) }
    #expect(throws: SSHPublicKey.Error.unsupportedType("SSH-ED25519")) { try SSHPublicKey(blob: wireString("SSH-ED25519") + wireBytes(ed1.inlineBytes!)) }
    // Length prefixes that overrun, wrap, or fall one short.
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: [0x80, 0, 0, 0]) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: [0, 0, 0, 12] + Array("ssh-ed25519".utf8)) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireString("ssh-ed25519") + [0, 0, 0, 33] + [UInt8](repeating: 1, count: 32)) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireString("ssh-ed25519") + [0, 0, 0]) }
    // Anything after the last field is refused, even a zero-length string.
    #expect(throws: SSHPublicKey.Error.trailingBytes) { try SSHPublicKey(blob: ed1.blob + [0, 0, 0, 0]) }
    #expect(throws: SSHPublicKey.Error.trailingBytes) { try SSHPublicKey(blob: p256.blob + [0]) }
    // ECDSA: the point at infinity, a compressed point, a point on the other
    // curve, and a swapped curve name.
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(1)) { try SSHPublicKey(blob: wireString("ecdsa-sha2-nistp256") + wireString("nistp256") + wireBytes([0x00])) }
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(33)) { try SSHPublicKey(blob: wireString("ecdsa-sha2-nistp256") + wireString("nistp256") + wireBytes([0x02] + p256.inlineBytes![1...32])) }
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(97)) { try SSHPublicKey(kind: .ecdsaP521, inlineBytes: p384.inlineBytes!) }
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(65)) { try SSHPublicKey(blob: wireString("ecdsa-sha2-nistp384") + wireString("nistp384") + wireBytes(p256.inlineBytes!)) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireString("ecdsa-sha2-nistp384") + wireString("nistp256") + wireBytes(p384.inlineBytes!)) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireString("ecdsa-sha2-nistp256") + wireString("NISTP256") + wireBytes(p256.inlineBytes!)) }
    var offCurve = p384.inlineBytes!
    offCurve[96] ^= 0x01
    #expect(throws: SSHPublicKey.Error.invalidPoint) { try SSHPublicKey(kind: .ecdsaP384, inlineBytes: offCurve) }
    var flipped = p256.inlineBytes!
    flipped[0] = 0x04
    flipped[1] ^= 0x80
    #expect(throws: SSHPublicKey.Error.invalidPoint) { try SSHPublicKey(kind: .ecdsaP256, inlineBytes: flipped) }
    // RSA: a negative exponent, a negative modulus, a zero modulus.
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireString("ssh-rsa") + wireBytes([0x81]) + wireBytes([0x7f])) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireString("ssh-rsa") + wireBytes([0x03]) + wireBytes([0xff, 0x01])) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: wireString("ssh-rsa") + wireBytes([0x03]) + wireBytes([])) }
    #expect(throws: SSHPublicKey.Error.trailingBytes) { try SSHPublicKey(blob: wireString("ssh-rsa") + wireBytes([0x03]) + wireBytes([0x05]) + wireBytes([0x07])) }
    // Ed25519: any 32 bytes are accepted, as ssh-keygen does; 31 or 33 are not.
    #expect(throws: Never.self) { try SSHPublicKey(blob: wireString("ssh-ed25519") + wireBytes([UInt8](repeating: 0xff, count: 32))) }
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(31)) { try SSHPublicKey(blob: wireString("ssh-ed25519") + wireBytes([UInt8](repeating: 0xff, count: 31))) }
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(33)) { try SSHPublicKey(kind: .ed25519, inlineBytes: [UInt8](repeating: 0xff, count: 33)) }
}

@Test func inlineRoundTripIsExactForEveryInlineKind() throws {
    var rng = Xorshift(state: 77)
    for _ in 0..<50 {
        let bytes = rng.bytes(32)
        let key = try SSHPublicKey(kind: .ed25519, inlineBytes: bytes)
        #expect(key.blob == wireString("ssh-ed25519") + wireBytes(bytes))
        #expect(key.inlineBytes == bytes)
        #expect(try SSHPublicKey(line: key.authorizedKeysLine()) == key)
        #expect(try SSHPublicKey(blob: key.blob) == key)
        #expect(key.fingerprintString.hasPrefix("SHA256:") && key.fingerprintString.count == 50)
        #expect(!key.fingerprintString.contains("="))
    }
    for index in [6, 7, 8, 9, 10, 11] {
        let key = try SSHPublicKey(line: keygenFixtures[index].line)
        let rebuilt = try SSHPublicKey(kind: key.kind, inlineBytes: key.inlineBytes!)
        #expect(rebuilt.blob == key.blob)
        #expect(rebuilt.fingerprintSHA256 == key.fingerprintSHA256)
        #expect(rebuilt.bits == key.bits)
    }
}

@Test func emittedLinesSurviveHostileCommentsAndPrincipals() throws {
    let key = try SSHPublicKey(line: keygenFixtures[0].line)
    let base64 = keygenFixtures[0].line.split(separator: " ")[1]
    // C0 and C1 controls, CRLF and the Unicode line and paragraph separators
    // are dropped; what remains parses back.
    for comment in ["a\u{0}b", "\u{1b}[31mred", "x\r\ny", "x\u{85}y", "\u{7f}", "tab\tkept", "nbsp\u{a0}kept", "水 🎩",
                    "x\u{2028}y", "x\u{2029}ssh-rsa AAAA", "\u{2028}", "\u{0b}\u{0c}"] {
        let line = key.authorizedKeysLine(comment: comment)
        #expect(!line.unicodeScalars.contains { $0.properties.generalCategory == .control })
        #expect(!line.contains { $0.isNewline })
        #expect(line.hasPrefix("ssh-ed25519 \(base64)"))
        let back = try SSHPublicKey(line: line)
        #expect(back.blob == key.blob)
    }
    // A principal cannot smuggle a second principal, an option, or a newline,
    // and one with nothing left becomes the wildcard rather than a bad line.
    for principal in ["a@x.ie,b@x.ie", "a@x.ie cert-authority", "a@x.ie\nb@x.ie ssh-rsa AAAA", "a@x.ie\tvalid-before=\"0\"", "a@x.ie\u{2028}b",
                      "", ",,", "\n\u{2029}", "\u{0}"] {
        let line = key.allowedSignersLine(principal: principal)
        let fields = line.split(separator: " ")
        #expect(fields.count == 4, "\(line)")
        #expect(fields[1] == "namespaces=\"git\"")
        #expect(fields[2] == "ssh-ed25519")
        #expect(fields[3] == base64)
        #expect(!fields[0].contains(","))
        #expect(!line.contains { $0.isNewline })
        #expect(principal.contains("@") || fields[0] == "*", "\(line)")
    }
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: "git\"\nx").split(separator: " ")[1] == "namespaces=\"gitx\"")
}

// MARK: - Base64

@Test func base64AgreesWithFoundation() throws {
    var rng = Xorshift(state: 0xB64)
    for _ in 0..<1500 {
        let bytes = rng.bytes(rng.below(200))
        let data = Data(bytes)
        #expect(Base64.encode(bytes) == data.base64EncodedString())
        #expect(try Base64.decode(data.base64EncodedString()) == bytes)
        #expect(Data(base64Encoded: Base64.encode(bytes)).map(Array.init) == bytes)
        let url = Base64.encode(bytes, url: true)
        let expectedURL = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        #expect(url == expectedURL)
        #expect(try Base64.decode(url, url: true) == bytes)
    }
}

@Test func base64RejectsEveryByteOutsideTheAlphabet() {
    for byte in UInt8.min...UInt8.max {
        let text = "QUJD" + String(decoding: [byte], as: UTF8.self)
        let isStandard = byte.isASCIIAlnum || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "/")
        let isURL = byte.isASCIIAlnum || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
        // Five characters is an impossible length, so a valid byte fails on
        // length and an invalid one on the alphabet; `=` fails on padding.
        if byte == UInt8(ascii: "=") {
            #expect(throws: Base64.Error.invalidPadding) { try Base64.decode(text) }
        } else {
            #expect(throws: isStandard ? Base64.Error.invalidLength : .invalidCharacter) { try Base64.decode(text) }
            #expect(throws: isURL ? Base64.Error.invalidLength : .invalidCharacter) { try Base64.decode(text, url: true) }
        }
    }
}

private extension UInt8 {
    var isASCIIAlnum: Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
    }
}

// MARK: - Normalizers: hostile input

private let smuggledWebsites: [(String, Normalize.Error)] = [
    ("JavaScript:alert(1)", .unsupportedScheme("javascript")),
    ("JAVASCRIPT://nnix.com", .unsupportedScheme("javascript")),
    (" \tjavascript:alert(1)\n", .unsupportedScheme("javascript")),
    ("java\u{0}script:alert(1)", .invalidCharacter("\u{0}")),
    ("vbscript:x", .unsupportedScheme("vbscript")),
    ("about:blank", .unsupportedScheme("about")),
    ("blob:https://nnix.com/x", .unsupportedScheme("blob")),
    ("sgnl://signal.me/#p/+1", .unsupportedScheme("sgnl")),
    ("https+x://nnix.com", .unsupportedScheme("https+x")),
    ("https://nnix.com\\@evil.com/", .userinfo),
    ("https://nnix.com%2F@evil.com/", .userinfo),
    ("https://nnix.com:80@evil.com/", .userinfo),
    ("https://:@nnix.com", .userinfo),
    ("https://nnix.com\u{FF0F}evil.com", .invalidHost),
    ("https://nnix.com\u{2044}evil.com", .invalidHost),
    ("https://nnix.com..", .invalidHost),
    ("https://nnix.com:", .invalidHost),
    ("https://nnix.com:-1", .invalidHost),
    ("https://nnix.com:65536", .invalidHost),
    ("https://nnix.com:8080:80", .invalidHost),
    ("https://nnix.com:0", .invalidHost),
    ("https://nnix.com:0443", .invalidHost),
    ("https://[2001:db8::1]/", .invalidHost),
    ("https://0x7f.0.0.1", .invalidHost),
    ("https://2130706433", .invalidHost),
    ("localhost:8080/x", .invalidHost),
    ("localhost:8080?x", .invalidHost),
    ("https://nnix.com/\u{85}x", .invalidCharacter("\u{85}")),
    ("https://nnix.com/x\u{2028}y", .invalidCharacter("\u{2028}")),
    ("https://nnix.com/x\u{7f}y", .invalidCharacter("\u{7f}")),
    ("https://nnix.com/x\u{a0}y", .invalidCharacter("\u{a0}")),
    // Format characters are named wherever they sit; a ZWJ is fused to its letter.
    ("https://nnix\u{200B}.com", .invalidCharacter("\u{200B}")),
    ("https://nnix.com\u{202E}", .invalidCharacter("\u{202E}")),
    ("\u{FEFF}nnix.com", .invalidCharacter("\u{FEFF}")),
    ("https://nnix.com/x\u{200B}y", .invalidCharacter("\u{200B}")),
    ("https://nnix.com/x\u{200D}y", .invalidCharacter("x\u{200D}")),
    ("https://nnix.com/?q=\u{2066}x\u{2069}", .invalidCharacter("\u{2066}")),
    // RFC 3986: what a browser would percent-encode is refused, not encoded.
    ("https://nnix.com/<script>", .invalidCharacter("<")),
    ("https://nnix.com/x?y=\"z\"", .invalidCharacter("\"")),
    ("https://nnix.com/x\\y", .invalidCharacter("\\")),
    ("https://nnix.com/{x}", .invalidCharacter("{")),
    ("https://nnix.com/x|y", .invalidCharacter("|")),
    ("https://nnix.com/`x`", .invalidCharacter("`")),
    ("https://nnix.com/^", .invalidCharacter("^")),
    ("https://nnix.com/Straße", .invalidCharacter("ß")),
    ("https://nnix.com/\u{FF0F}evil.com", .invalidCharacter("\u{FF0F}")),
    ("https://nnix.com/#\u{2044}", .invalidCharacter("\u{2044}")),
]

@Test(arguments: smuggledWebsites)
func websiteRejectsSmuggling(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.website(input) }
}

private let spoofedHandles: [(String, Normalize.Error)] = [
    ("https://github.com@evil.com/bloom", .userinfo),
    ("https://evil.com/github.com/bloom", .wrongHost("evil.com")),
    ("https://github.com\u{2044}evil.com/bloom", .wrongHost("github.com\u{2044}evil.com")),
    ("https://GITHUB.COM.evil.com/bloom", .wrongHost("GITHUB.COM.evil.com")),
    ("https://github.com/bloom\u{200B}", .invalidUsername),
    ("https://github.com/bloom%2Fevil", .invalidUsername),
    ("https://github.com/blo\u{0}om", .invalidUsername),
    ("https://github.com/\u{FF42}loom", .invalidUsername),
    ("blo\u{a0}om", .invalidUsername),
    ("@\u{200B}bloom", .invalidUsername),
    ("blo--om", .invalidUsername),
    ("https://github.com/blo--om", .invalidUsername),
    ("https://github.com/orgs/bloom", .invalidPath),
    ("https://github.com/Settings", .invalidPath),
    ("github.com/login?return_to=/bloom", .invalidPath),
]

@Test(arguments: spoofedHandles)
func githubRejectsSpoofing(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.github(input) }
}

private let spoofedLinkedIn: [(String, Normalize.Error)] = [
    ("https://linkedin.com@evil.com/in/bloom", .userinfo),
    ("https://evil.com/linkedin.com/in/bloom", .wrongHost("evil.com")),
    ("https://xlinkedin.com/in/bloom", .wrongHost("xlinkedin.com")),
    ("https://linkedin.com.evil/in/bloom", .wrongHost("linkedin.com.evil")),
    ("https://www.linkedin.com/in/bloom\u{202E}x", .invalidUsername),
    ("https://www.linkedin.com/in/%E2%80%8Bbloom", .invalidUsername),
    ("https://www.linkedin.com/in/%0Abloom", .invalidUsername),
    ("https://www.linkedin.com/in/bloom%2F..%2Fx", .invalidUsername),
    ("https://www.linkedin.com/in/%C0%AF", .invalidPath),
    ("https://www.linkedin.com/in/%", .invalidPath),
    ("https://www.linkedin.com/in/%4", .invalidPath),
    ("in/bl oom", .invalidUsername),
    ("in/bl\u{0}oom", .invalidUsername),
]

@Test(arguments: spoofedLinkedIn)
func linkedinRejectsSpoofing(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.linkedin(input) }
}

private let spoofedMastodon: [(String, Normalize.Error)] = [
    ("bloom@merveilles.town\u{200B}", .invalidHost),
    ("bloom@merveilles\u{2024}town", .invalidHost),
    ("bloom@xn--\u{0}.town", .invalidHost),
    ("https://merveilles.town@evil.com/@bloom", .userinfo),
    ("https://merveilles.town/@bloom@other.host", .invalidUsername),
    ("https://merveilles.town/@bloom%0A", .invalidUsername),
    ("https://merveilles.town/users/bloom/followers", .invalidPath),
    ("https://merveilles.town/@bloom/../x", .invalidPath),
    ("bl\u{0}oom@merveilles.town", .invalidUsername),
    ("\u{FF42}loom@merveilles.town", .invalidUsername),
    ("bloom@merveilles.123", .invalidHost),
    ("bloom@[::1]", .invalidHost),
]

@Test(arguments: spoofedMastodon)
func mastodonRejectsSpoofing(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.mastodon(input) }
}

private let spoofedCalendly: [(String, Normalize.Error)] = [
    ("https://calendly.com@evil.com/bloom", .userinfo),
    ("https://calendly.community/bloom", .wrongHost("calendly.community")),
    ("https://calendly.com:443/bloom", .wrongHost("calendly.com:443")),
    ("https://calendly.com/bloom%2F..%2Fx", .invalidPath),
    ("https://calendly.com/bloom/\u{200B}", .invalidPath),
    ("evil.com/bloom", .invalidPath),
    ("\u{FF42}loom", .invalidPath),
    ("bloom/coffee/2026-09-04T10:00:00", .invalidPath),
    ("bloom//coffee//x//y", .invalidPath),
]

@Test(arguments: spoofedCalendly)
func calendlyRejectsSpoofing(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.calendly(input) }
}

private let spoofedEmails: [(String, Normalize.Error)] = [
    ("bloom@nnix.com\u{200B}", .invalidCharacter("\u{200B}")),
    ("bloom@nnix\u{2024}com", .invalidCharacter("\u{2024}")),
    ("bloom@nn\u{ad}ix.com", .invalidCharacter("\u{ad}")),
    ("bloom@\u{FF4E}nix.com", .invalidCharacter("\u{FF4E}")),
    ("bloom@nnix\u{0}.com", .invalidCharacter("\u{0}")),
    ("bloom\\@x@nnix.com", .multipleAt),
    ("\"bloom@x\"@nnix.com", .multipleAt),
    ("bloom@nnix.com>", .invalidHost),
    ("<bloom@nnix.com", .invalidLocalPart),
    ("bloom@nnix.com (comment)", .invalidCharacter(" ")),
    ("bloom@nnix.com;x@y.ie", .multipleAt),
    ("bloom@nnix.com,x@y.ie", .multipleAt),
    ("bloom@nnix.com?subject=x", .invalidHost),
    ("bloom@nnix.com:25", .invalidHost),
    ("bloom@nnix.com/x", .invalidHost),
]

@Test(arguments: spoofedEmails)
func emailRejectsSpoofing(input: String, error: Normalize.Error) {
    #expect(throws: error) { try Normalize.email(input) }
}

@Test func trailingControlsAreTrimmedNotSmuggled() throws {
    // Trailing controls are treated as whitespace and dropped; a control in
    // the middle is an error. Either way the stored form is clean.
    #expect(try Normalize.phone("+353871234567\u{0}") == "+353871234567")
    #expect(try Normalize.phone("\u{0}+353871234567") == "+353871234567")
    #expect(throws: Normalize.Error.invalidCharacter("\u{0}")) { try Normalize.phone("+3538712\u{0}34567") }
    #expect(try Normalize.gpgFingerprint("EF6E286DDA85EA2A4BA7DE684E2C6E8793298290\u{7f}").hex == "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290")
    #expect(try Normalize.github("bloom\u{1b}") == "bloom")
    #expect(throws: Normalize.Error.invalidUsername) { try Normalize.github("blo\u{1b}om") }
}

// MARK: - Normalizers: fixed points

/// Every stored form the normalizers accept must be a fixed point of its own
/// normalizer, and its canonical URI must normalize back to it.
@Test func storedFormsAreFixedPoints() throws {
    var rng = Xorshift(state: 0xF1_7ED)
    var seen = [String: Int]()
    for _ in 0..<15_000 {
        let s = fuzzString(&rng)
        if let phone = try? Normalize.phone(s) {
            seen["phone", default: 0] += 1
            #expect(try Normalize.phone(phone) == phone)
            #expect(try Normalize.phone(CanonicalURI.phone(phone)) == phone)
            #expect(phone.hasPrefix("+") && phone.dropFirst().allSatisfy(\.isASCIIDigit) && (9...16).contains(phone.count))
        }
        if let email = try? Normalize.email(s) {
            seen["email", default: 0] += 1
            #expect(try Normalize.email(email) == email)
            // Local parts that `mailto:` percent-encodes are covered by
            // mailtoInputIsPercentDecoded; the rest must round-trip here.
            if !email.contains(where: { "#%&/=?^`{|}".contains($0) }) {
                #expect(try Normalize.email(CanonicalURI.email(email)) == email)
            }
            #expect(email.allSatisfy { $0.isASCII && !$0.isControl && $0 != " " })
            #expect(email.filter { $0 == "@" }.count == 1)
        }
        if let site = try? Normalize.website(s) {
            seen["website", default: 0] += 1
            let again = try Normalize.website(CanonicalURI.website(site.address, insecure: site.insecure))
            #expect(again.address == site.address && again.insecure == site.insecure, "\(s)")
            let direct = try Normalize.website(site.address)
            #expect(direct.address == site.address && direct.insecure == false)
            // The authority never carries a scheme or userinfo; a path may.
            let authority = site.address.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            #expect(!authority.contains(":") || authority.split(separator: ":").count == 2)
            #expect(!authority.contains("@") && !site.address.hasPrefix("//"))
            #expect(!site.address.contains { $0.isWhitespace || $0.isControl || $0.isFormat })
            // Only the host may be non-ASCII; the rest is already percent-encoded.
            #expect(site.address[authority.endIndex...].allSatisfy { $0.isASCII && !"<>\"\\^`{|}".contains($0) })
        }
        if let user = try? Normalize.github(s) {
            seen["github", default: 0] += 1
            #expect(try Normalize.github(user) == user)
            #expect(try Normalize.github(CanonicalURI.github(user)) == user)
            #expect((1...39).contains(user.count) && user.first != "-" && user.last != "-")
            #expect(user.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" })
        }
        if let slug = try? Normalize.linkedin(s) {
            seen["linkedin", default: 0] += 1
            #expect(try Normalize.linkedin(slug) == slug, "\(s)")
            #expect(try Normalize.linkedin(CanonicalURI.linkedin(slug)) == slug, "\(s)")
            let bare = slug.hasPrefix("company/") ? String(slug.dropFirst(8)) : slug
            #expect((3...100).contains(bare.count) && !bare.contains("/") && !bare.contains("%"))
            #expect(bare.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        }
        if let handle = try? Normalize.mastodon(s) {
            seen["mastodon", default: 0] += 1
            #expect(try Normalize.mastodon(handle) == handle)
            let canonical = try #require(CanonicalURI.mastodon(handle))
            #expect(try Normalize.mastodon(canonical.profile) == handle)
            #expect(canonical.account == "acct:" + handle)
            #expect(handle.filter { $0 == "@" }.count == 1 && handle.first != "@")
        }
        if let path = try? Normalize.calendly(s) {
            seen["calendly", default: 0] += 1
            #expect(try Normalize.calendly(path) == path, "\(s)")
            #expect(try Normalize.calendly(CanonicalURI.calendly(path)) == path, "\(s)")
            #expect(path.first != "/" && path.last != "/" && !path.contains("//"))
            #expect(path.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" || $0 == "_" || $0 == "/" })
        }
        if let fingerprint = try? Normalize.gpgFingerprint(s) {
            seen["gpg", default: 0] += 1
            #expect(try Normalize.gpgFingerprint(fingerprint.hex) == fingerprint)
            #expect(try Normalize.gpgFingerprint(fingerprint.formatted) == fingerprint)
            #expect(try Normalize.gpgFingerprint(fingerprint.uri) == fingerprint)
        }
        if let link = try? SignalLink.parse(s) {
            seen["signal", default: 0] += 1
            #expect(try SignalLink.parse(link.url) == link)
        }
    }
    // The alphabet must actually reach the accepting paths for this to mean anything.
    for name in ["email", "website", "github", "linkedin", "calendly"] {
        #expect(seen[name, default: 0] > 0, "\(name)")
    }
    // The fuzz alphabet rarely forms a handle; check the fixed point directly.
    for handle in ["bloom@merveilles.town", "Bloom_1@m.social", "a@xn--mller-kva.de", String(repeating: "z", count: 30) + "@a.b.c.d.ie"] {
        #expect(try Normalize.mastodon(handle) == handle)
        let canonical = try #require(CanonicalURI.mastodon(handle))
        #expect(try Normalize.mastodon(canonical.profile) == handle)
        #expect(try Normalize.mastodon(canonical.profile + "/") == handle)
        #expect(try Normalize.mastodon("@" + handle) == handle)
        #expect(try Normalize.mastodon(canonical.profile.replacingOccurrences(of: "/@", with: "/users/")) == handle)
        #expect(try Normalize.mastodon(canonical.profile.replacingOccurrences(of: "/@", with: "/users/") + "/") == handle)
        // The `@user@instance` spelling people paste is not a different account.
        let prefixed = try #require(CanonicalURI.mastodon("@" + handle))
        #expect(prefixed.account == canonical.account && prefixed.profile == canonical.profile)
    }
}

/// RFC 6068 §2: a `mailto:` URI carries the address percent-encoded, so the
/// prefix is only safe to strip if the rest is decoded. `Normalize.email`
/// strips without decoding and so stores a different address than the one
/// pasted; the canonical URI of a legal local part does not normalize back.
@Test func mailtoInputIsPercentDecoded() throws {
    #expect(try Normalize.email("mailto:first%2Blast@x.ie") == "first+last@x.ie")
    // The RFC's own example: decoded and then refused as a quoted local part,
    // or decoded and kept; never stored still encoded.
    #expect((try? Normalize.email("mailto:%22not%40me%22@example.org")) != "%22not%40me%22@example.org")
    for local in ["a#b", "a%b", "a&b", "a/b", "a=b", "a?b", "a^b", "a`b", "a{b}", "a|b"] {
        let email = local + "@x.ie"
        #expect(try Normalize.email(email) == email)
        #expect(try Normalize.email(CanonicalURI.email(email)) == email, "\(email)")
    }
}

@Test func canonicalMailtoEncodesEveryReservedByte() {
    // RFC 6068 §2: only unreserved and some-delims may appear raw.
    let raw = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$'()*+,;:@".utf8)
    for byte in UInt8(0x21)...UInt8(0x7e) {
        let uri = CanonicalURI.email(String(decoding: [byte], as: UTF8.self) + "@x.ie")
        let body = uri.dropFirst("mailto:".count)
        if raw.contains(byte) {
            #expect(body.utf8.first == byte)
        } else {
            #expect(body.hasPrefix("%" + Hex.pair(byte)), "\(String(decoding: [byte], as: UTF8.self))")
        }
    }
    #expect(CanonicalURI.email("a?b#c&d=e/f%g@x.ie") == "mailto:a%3Fb%23c%26d%3De%2Ff%25g@x.ie")
    #expect(!CanonicalURI.email("a?subject=hi&body=x@x.ie").contains("?"))
}

// MARK: - GPG fingerprints

@Test func fingerprintsRoundTripThroughEverySpelling() throws {
    var rng = Xorshift(state: 0x9F9)
    for length in [20, 32] {
        for _ in 0..<100 {
            let bytes = rng.bytes(length)
            let fingerprint = try GPGFingerprint(bytes: bytes)
            #expect(fingerprint.hex.count == length * 2)
            #expect(fingerprint.hex.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isUppercase) })
            #expect(fingerprint.formatted.count == length * 2 + length / 2)
            #expect(fingerprint.formatted.contains("  ") && fingerprint.formatted.split(separator: "  ").count == 2)
            #expect(fingerprint.formatted.split(separator: " ").allSatisfy { $0.count == 4 })
            for spelling in [fingerprint.hex, fingerprint.hex.lowercased(), fingerprint.formatted, fingerprint.uri,
                             "0x" + fingerprint.hex, fingerprint.hex.map(String.init).joined(separator: ":"),
                             fingerprint.formatted.replacingOccurrences(of: " ", with: "\t")] {
                #expect(try Normalize.gpgFingerprint(spelling).bytes == bytes, "\(spelling)")
            }
        }
    }
    let torV4 = "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"
    #expect(throws: Normalize.Error.wrongLength(33)) { try Normalize.gpgFingerprint(torV4 + torV4.prefix(26)) }
    #expect(throws: Normalize.Error.invalidHex) { try Normalize.gpgFingerprint(String(torV4.prefix(39))) }
    #expect(throws: Normalize.Error.invalidCharacter("x")) { try Normalize.gpgFingerprint("0x0x" + torV4) }
    #expect(throws: Normalize.Error.invalidCharacter("O")) { try Normalize.gpgFingerprint("OPENPGP4FPR:OPENPGP4FPR:" + torV4) }
    #expect(throws: Normalize.Error.invalidCharacter("\u{200B}")) { try Normalize.gpgFingerprint(torV4.prefix(20) + "\u{200B}" + torV4.dropFirst(20)) }
    #expect(throws: Normalize.Error.invalidCharacter("-")) { try Normalize.gpgFingerprint(torV4.prefix(20) + "-" + torV4.dropFirst(20)) }
    // Fullwidth digits and letters satisfy `hexDigitValue` but are not hex.
    for wide in ["\u{FF10}", "\u{FF19}", "\u{FF21}", "\u{FF26}", "\u{FF41}", "\u{FF46}"] {
        #expect(throws: Normalize.Error.invalidCharacter(Character(wide))) { try Normalize.gpgFingerprint(torV4.prefix(20) + wide + torV4.dropFirst(21)) }
    }
}

// MARK: - Signal

@Test func signalUsernameLinksAreOpaqueButExact() throws {
    var rng = Xorshift(state: 0x516)
    for _ in 0..<100 {
        let bytes = rng.bytes(48)
        let link = try SignalLink(username: bytes)
        #expect(link.url.count == 22 + 64)
        #expect(!link.url.contains("=") && !link.url.contains("+") && !link.url.contains("/", after: 22))
        #expect(try SignalLink.parse(link.url) == link)
        #expect(try SignalLink.parse("sgnl://signal.me/#eu/" + link.url.dropFirst(22)) == link)
        #expect(!link.disclosesPhoneNumber)
        // Flipping one character changes the bytes or breaks the link, never both silently.
        var chars = Array(link.url)
        chars[30] = chars[30] == "A" ? "B" : "A"
        if let flipped = try? SignalLink.parse(String(chars)) {
            #expect(flipped != link)
        }
    }
    let encoded = Base64.encode([UInt8](repeating: 0x5a, count: 48), url: true)
    for bad in ["https://signal.me/#EU/" + encoded, "https://signal.me/#eu/" + encoded + "==", "https://signal.me/#eu/" + encoded + "/",
                "https://signal.me/#eu/" + encoded + "?x", "https://signal.me/x#eu/" + encoded, "https://signal.me//#eu/" + encoded,
                "https://signal.me/#eu/\u{200B}" + encoded, "https://signal.me/#eu/" + encoded.replacingOccurrences(of: "W", with: "+")] {
        #expect(throws: Normalize.Error.invalidPath) { try SignalLink.parse(bad) }
    }
    #expect(throws: Normalize.Error.wrongHost("www.signal.me")) { try SignalLink.parse("https://www.signal.me/#eu/" + encoded) }
    #expect(throws: Normalize.Error.wrongHost("signal.me:443")) { try SignalLink.parse("https://signal.me:443/#eu/" + encoded) }
    #expect(throws: Normalize.Error.wrongHost("signal.me@evil.com")) { try SignalLink.parse("https://signal.me@evil.com/#eu/" + encoded) }
    #expect(throws: Normalize.Error.unsupportedScheme("javascript")) { try SignalLink.parse("javascript://signal.me/#eu/" + encoded) }
    #expect(throws: Normalize.Error.invalidCharacter("\u{0}")) { try SignalLink.parse("https://signal.me/#eu/\u{0}" + encoded) }
}

@Test func signalPhoneLinksDiscloseAndNormalize() throws {
    let link = try SignalLink.parse("SGNL://SIGNAL.ME/#p/+353.(87)-123-4567")
    #expect(link.disclosesPhoneNumber)
    #expect(link.url == "https://signal.me/#p/+353871234567")
    #expect(link.kind == .phone("+353871234567"))
    #expect(throws: Normalize.Error.invalidCharacter("?")) { try SignalLink.parse("https://signal.me/#p/+353871234567?x") }
    #expect(throws: Normalize.Error.invalidCharacter("%")) { try SignalLink.parse("https://signal.me/#p/%2B353871234567") }
    #expect(throws: Normalize.Error.tooLong) { try SignalLink.parse("https://signal.me/#p/+3538712345671234") }
    #expect(throws: Normalize.Error.invalidCountryCode) { try SignalLink.parse("https://signal.me/#p/+0353871234567") }
}

private extension String {
    func contains(_ ch: Character, after offset: Int) -> Bool {
        dropFirst(offset).contains(ch)
    }
}

// MARK: - vCard

/// What a value looks like after `escape` and `parseBasic`: line breaks
/// become LF, and C0 controls other than HTAB, and DEL, are gone.
private func valueAfterEscape(_ s: String) -> String {
    var out = ""
    for ch in s {
        if ["\r\n", "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"].contains(ch) {
            out.append("\n")
        } else {
            out.unicodeScalars.append(contentsOf: ch.unicodeScalars.filter { ($0.value >= 0x20 || $0.value == 0x09) && $0.value != 0x7f })
        }
    }
    return out
}

private func physical(_ text: String) -> [Substring] {
    text.split(separator: "\r\n", omittingEmptySubsequences: false).dropLast()
}

/// The full alphabet, grapheme extenders included: a fold that lands in front
/// of a combining mark must unfold cleanly (see vCardUnfoldsBeforeCombiningMarks).
private func vCardFuzzString(_ rng: inout Xorshift, maxFragments: Int = 12) -> String {
    fuzzString(&rng, maxFragments: maxFragments)
}

@Test func vCardRoundTripsUnderFuzz() throws {
    var rng = Xorshift(state: 0xCA4D)
    for _ in 0..<600 {
        var card = VCard(formattedName: vCardFuzzString(&rng))
        if rng.below(2) == 0 { card.organization = vCardFuzzString(&rng) }
        if rng.below(2) == 0 { card.phone = vCardFuzzString(&rng) }
        if rng.below(2) == 0 { card.email = vCardFuzzString(&rng) }
        if rng.below(2) == 0 { card.note = vCardFuzzString(&rng, maxFragments: 60) }
        if rng.below(3) == 0 { card.photoJPEG = rng.bytes(rng.below(400)) }
        for _ in 0..<rng.below(4) { card.links.append(VCard.Link(label: vCardFuzzString(&rng), url: vCardFuzzString(&rng))) }
        for _ in 0..<rng.below(4) { card.extensions.append(VCard.Extension(name: vCardFuzzString(&rng), value: vCardFuzzString(&rng))) }
        let text = card.text
        // Only CRLF breaks lines, every line is at most 75 octets and valid
        // UTF-8, and the envelope is exactly one card.
        let bytes = Array(text.utf8)
        for (i, byte) in bytes.enumerated() {
            if byte == 0x0a { #expect(i > 0 && bytes[i - 1] == 0x0d) }
            if byte == 0x0d { #expect(i + 1 < bytes.count && bytes[i + 1] == 0x0a) }
        }
        let lines = physical(text)
        #expect(lines.allSatisfy { $0.utf8.count <= 75 && String(validating: Array($0.utf8), as: UTF8.self) != nil })
        #expect(lines.first == "BEGIN:VCARD" && lines[1] == "VERSION:3.0" && lines.last == "END:VCARD")
        #expect(lines.filter { $0.uppercased() == "BEGIN:VCARD" || $0.uppercased() == "END:VCARD" }.count == 2)
        // A fold may land anywhere, even inside a long property name, so the
        // colon is only guaranteed after unfolding.
        var logical: [String] = []
        for line in lines {
            if line.unicodeScalars.first == " ", !logical.isEmpty {
                logical[logical.count - 1] += String(line.unicodeScalars.dropFirst())
            } else {
                logical.append(String(line))
            }
        }
        #expect(logical.allSatisfy { $0.contains(":") })
        #expect(!lines.contains { $0.unicodeScalars.count == 1 && $0.unicodeScalars.first == " " })
        var expected = card
        expected.formattedName = valueAfterEscape(card.formattedName)
        expected.familyName = valueAfterEscape(card.familyName)
        expected.givenName = valueAfterEscape(card.givenName)
        expected.organization = card.organization.map(valueAfterEscape)
        expected.phone = card.phone.map(valueAfterEscape)
        expected.email = card.email.map(valueAfterEscape)
        expected.note = card.note.map(valueAfterEscape)
        expected.links = card.links.map { VCard.Link(label: valueAfterEscape($0.label), url: valueAfterEscape($0.url)) }
        expected.extensions = card.extensions.map { VCard.Extension(name: $0.name, value: valueAfterEscape($0.value)) }
        let parsed = try VCard.parseBasic(text)
        #expect(parsed == expected)
        #expect(try VCard.parseBasic(text.replacingOccurrences(of: "\r\n", with: "\n")) == expected)
        #expect(parsed.text == expected.text)
    }
}

/// RFC 2425 §5.8.1 folds between any two characters and unfolds by removing
/// CRLF plus one whitespace octet. `fold` works on scalars, so a fold may land
/// in front of a combining mark; `parseBasic` must unfold on scalars too, or
/// it would see a first *grapheme* of space-plus-mark, not a space, and read
/// the continuation as a new property. Decomposed accents and emoji with
/// variation selectors or ZWJ exercise it.
@Test func vCardUnfoldsBeforeCombiningMarks() throws {
    let cases: [(String, String)] = [
        // NOTE: + 69 a + e = 75 octets; U+0301 starts the continuation.
        ("decomposed accent", String(repeating: "a", count: 69) + "e\u{301}x"),
        // NOTE: + 66 a + U+1F3F3 = 75 octets; U+FE0F ZWJ U+1F308 follow.
        ("rainbow flag", String(repeating: "a", count: 66) + "🏳\u{FE0F}\u{200D}🌈"),
        // NOTE: + 66 a + U+1F468 = 75; ZWJ starts the continuation.
        ("family", String(repeating: "a", count: 66) + "👨\u{200D}👩\u{200D}👧"),
    ]
    for (name, note) in cases {
        var card = VCard(formattedName: "x")
        card.note = note
        let text = card.text
        let lines = physical(text)
        #expect(lines.allSatisfy { $0.utf8.count <= 75 })
        #expect(lines.contains { $0.unicodeScalars.first == " " }, "\(name): the note was folded")
        let parsed = try VCard.parseBasic(text)
        #expect(parsed.note == note, "\(name)")
        #expect(parsed == card, "\(name)")
    }
}

@Test func vCardEscapesSplitAcrossFoldsSurvive() throws {
    // The backslash lands on octet 75 and its partner on the next line.
    for (suffix, plain) in [(",", ","), (";", ";"), ("\\", "\\"), ("\n", "\n")] {
        var card = VCard(formattedName: "x")
        card.note = String(repeating: "a", count: 69) + suffix + "tail"
        let lines = physical(card.text)
        let note = try #require(lines.firstIndex { $0.hasPrefix("NOTE:") })
        #expect(lines[note].utf8.count == 75)
        #expect(lines[note].last == "\\")
        #expect(lines[note + 1].hasPrefix(" "))
        #expect(try VCard.parseBasic(card.text).note == String(repeating: "a", count: 69) + plain + "tail")
    }
    // A four-byte scalar that would straddle the boundary moves whole.
    var card = VCard(formattedName: "x")
    card.note = String(repeating: "a", count: 68) + "🎩" + "b"
    let lines = physical(card.text)
    #expect(lines.contains { $0.utf8.count == 73 && $0.hasPrefix("NOTE:") })
    #expect(lines.contains(" 🎩b"))
    #expect(try VCard.parseBasic(card.text) == card)
}

@Test func vCardControlsCannotForgeLines() throws {
    // Every line-break character Swift knows, mixed with other controls, ends
    // up as `\n` in one value; nothing becomes a property of its own.
    let breaks = ["\r", "\n", "\r\n", "\u{85}", "\u{2028}", "\u{2029}", "\u{0b}", "\u{0c}", "\r\u{0b}\n", "\n\u{301}", "\r\u{200D}\n"]
    for br in breaks {
        var card = VCard(formattedName: "Bloom" + br + "FN:Mallory" + br + "END:VCARD" + br + "BEGIN:VCARD")
        card.note = br + "X-HATBAND-KEY:evil" + br
        card.links = [VCard.Link(label: "l" + br + "item9.URL:https://evil", url: "https://x" + br + "PHOTO;ENCODING=b:AAAA")]
        card.extensions = [VCard.Extension(name: "K" + br + "EY", value: "v" + br + "TEL:+1")]
        let lines = physical(card.text)
        #expect(lines.filter { $0 == "BEGIN:VCARD" }.count == 1)
        #expect(lines.filter { $0 == "END:VCARD" }.count == 1)
        #expect(lines.filter { $0.hasPrefix("FN:") }.count == 1)
        #expect(!lines.contains { $0.hasPrefix("TEL") || $0.hasPrefix("PHOTO") || $0.hasPrefix("item9") || $0.hasPrefix("X-HATBAND-KEY:evil") })
        #expect(lines.filter { $0.hasPrefix("X-HATBAND-") }.count == 1)
        let parsed = try VCard.parseBasic(card.text)
        #expect(parsed.links.count == 1)
        #expect(parsed.extensions.map(\.name) == ["KEY"])
        #expect(parsed.photoJPEG == nil && parsed.phone == nil)
    }
}

@Test func vCardExtensionNamesAreSanitized() {
    #expect(VCard.Extension(name: "a:b;c.d,e f\r\ng", value: "").name == "ABCDEFG")
    #expect(VCard.Extension(name: "item1.URL", value: "").name == "ITEM1URL")
    #expect(VCard.Extension(name: "ß-ﬁ", value: "").name == "-", "ASCII case folding: never SS-FI")
    #expect(VCard.Extension(name: "水", value: "").name == "")
    var card = VCard(formattedName: "x")
    card.extensions = [VCard.Extension(name: "", value: "empty"), VCard.Extension(name: "SEQ", value: "1"), VCard.Extension(name: "SEQ", value: "2")]
    let lines = physical(card.text)
    #expect(lines.contains("X-HATBAND-:empty"))
    #expect(lines.filter { $0.hasPrefix("X-HATBAND-SEQ:") }.count == 2)
    #expect((try? VCard.parseBasic(card.text))?.extensions == card.extensions)
}

@Test func vCardReadsFoldedPhotoAndOddInput() throws {
    let photo = (0..<777).map { UInt8(truncatingIfNeeded: $0 &* 31) }
    var card = VCard(formattedName: "Leopold Bloom")
    card.photoJPEG = photo
    let text = card.text
    let photoLines = physical(text).drop { !$0.hasPrefix("PHOTO;") }.prefix { $0.hasPrefix("PHOTO;") || $0.hasPrefix(" ") }
    #expect(photoLines.count == (Base64.encode(photo).count + "PHOTO;ENCODING=b;TYPE=JPEG:".count + 73) / 74)
    #expect(photoLines.allSatisfy { $0.utf8.count <= 75 })
    #expect(try VCard.parseBasic(text).photoJPEG == photo)
    // Tab continuations, lower-case names, N with one component, a colon in
    // a value, and a group we do not model.
    let odd = "begin:vcard\nversion:3.0\nn:Bloom\nfn:Leopold\n\t Bloom\nitem1.url:https://nnix.com/a:b\nitem1.x-ablabel:Web\nitem2.tel:+1\nemail;type=home:a@b.ie\nend:vcard\n"
    let parsed = try VCard.parseBasic(odd)
    #expect(parsed.familyName == "Bloom" && parsed.givenName == "")
    #expect(parsed.formattedName == "Leopold Bloom")
    #expect(parsed.links == [VCard.Link(label: "Web", url: "https://nnix.com/a:b")])
    #expect(parsed.phone == "+1" && parsed.email == "a@b.ie")
    #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\nFN:x\r\n") }
    #expect(throws: VCard.Error.notAVCard) { try VCard.parseBasic(" BEGIN:VCARD\r\nEND:VCARD\r\n") }
    #expect(throws: VCard.Error.unsupportedVersion("3.0 ")) { try VCard.parseBasic("BEGIN:VCARD\r\nVERSION:3.0 \r\nEND:VCARD\r\n") }
    #expect(try VCard.parseBasic("BEGIN:VCARD\r\n\t\r\nEND:VCARD\r\n") == VCard(formattedName: "", familyName: "", givenName: ""), "a lone tab is an empty continuation")
    #expect(throws: VCard.Error.malformedLine(";")) { try VCard.parseBasic("BEGIN:VCARD\r\n;\r\nEND:VCARD\r\n") }
}

@Test func vCardMaximalCardStaysUnderTheFileCap() throws {
    var card = VCard(formattedName: String(repeating: "Leopold Paula Bloom ", count: 3))
    card.organization = String(repeating: "Freeman's Journal; ", count: 4)
    card.phone = "+353871234567"
    card.email = String(repeating: "a", count: 64) + "@" + String(repeating: "b", count: 63) + ".ie"
    card.note = String(repeating: "水🎩é,;\\\n", count: 300)
    card.photoJPEG = (0..<12_288).map { UInt8(truncatingIfNeeded: $0) }
    card.links = (1...12).map { VCard.Link(label: "Link \($0)", url: "https://example.com/" + String(repeating: "p", count: 128)) }
    card.extensions = (1...8).map { VCard.Extension(name: "F\($0)", value: String(repeating: "v", count: 128)) }
    let text = card.text
    #expect(text.utf8.count < 32_768)
    #expect(physical(text).allSatisfy { $0.utf8.count <= 75 })
    var expected = card
    expected.note = valueAfterEscape(card.note!)
    #expect(try VCard.parseBasic(text) == expected)
}

// MARK: - Crash fuzz

/// Nothing here may trap: every parser is total on arbitrary text and bytes.
@Test func nothingTrapsOnGarbage() {
    var rng = Xorshift(state: 0xDEAD_BEEF)
    for _ in 0..<12_000 {
        let s = fuzzString(&rng)
        _ = try? Normalize.phone(s)
        _ = try? Normalize.email(s)
        _ = try? Normalize.website(s)
        _ = try? Normalize.github(s)
        _ = try? Normalize.linkedin(s)
        _ = try? Normalize.mastodon(s)
        _ = try? Normalize.calendly(s)
        _ = try? Normalize.gpgFingerprint(s)
        _ = try? SignalLink.parse(s)
        _ = try? SSHPublicKey(line: s)
        _ = try? VCard.parseBasic(s)
        _ = try? Base64.decode(s)
        _ = try? Base64.decode(s, url: true)
        _ = PercentEncoding.decode(Substring(s))
        _ = Hostname.normalized(Substring(s))
        _ = Pasted(Substring(s))
        _ = CanonicalURI.email(s)
        _ = CanonicalURI.mastodon(s)
        _ = VCard.fold(VCard.escape(s))
        _ = VCard.splitProperty(s)
        _ = VCard.splitComponents(s).map(VCard.unescape)
        _ = VCard(formattedName: s).text
    }
    let types = ["ssh-ed25519", "ssh-rsa", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "sk-ssh-ed25519@openssh.com"]
    for _ in 0..<6000 {
        var blob = rng.bytes(rng.below(180))
        if rng.below(2) == 0 { blob = wireString(types[rng.below(types.count)]) + blob }
        if rng.below(3) == 0 { blob = wireString("ecdsa-sha2-nistp256") + wireString("nistp256") + [0, 0, 0, 65] + blob }
        _ = try? SSHPublicKey(blob: blob)
        _ = SSHPublicKey.randomart(fingerprint: blob, title: fuzzString(&rng, maxFragments: 4), footer: fuzzString(&rng, maxFragments: 4))
    }
}
