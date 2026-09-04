import Testing
@testable import HatbandCore

/// Keys made on this machine with `ssh-keygen`; fingerprints and randomart
/// are what `ssh-keygen -lf` and `-lvf` printed for them.
private struct Fixture {
    let line: String
    let kind: SSHPublicKey.Kind
    let bits: Int
    let comment: String?
    let fingerprint: String
    let randomart: String
}

private let ed25519 = Fixture(
    line: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjJlVLb4OQSjA2M1WCE+kKq1u22L+67K93iFB3A20R3 bloom@eccles",
    kind: .ed25519, bits: 256, comment: "bloom@eccles",
    fingerprint: "SHA256:65484HXMQFf173b7DqGsTRS/a3rYtqM0gFGnF6fH/d0",
    randomart: """
    +--[ED25519 256]--+
    |          ..+.o  |
    |        ...o = o |
    |       .... + o o|
    |        .o . +  =|
    |        S+. . o E|
    |      . ..++ . + |
    |     . o..  *oo +|
    |      .o.. =..*+o|
    |       .=.. +*o=+|
    +----[SHA256]-----+
    """)

private let ecdsa256 = Fixture(
    line: "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPlnx2p7LH4G02PXQJ5HDPmfKIeP2Rzq9adOBa6F1LgVfT2p2J9Yk+4aN2pM+zoHfGrxuMm5h92a6M+PVrNTdoI= bloom@eccles",
    kind: .ecdsaP256, bits: 256, comment: "bloom@eccles",
    fingerprint: "SHA256:IlfC8vtWMxlZP73mawIBI9fekJd6fEthUHz7c5+4Uxg",
    randomart: """
    +---[ECDSA 256]---+
    |          . ..=. |
    |     . . + +.o +.|
    |    . o + +o*...+|
    |     o o  o+ Eo+.|
    |    . + S  oo =.+|
    |     o o  =. . *o|
    |      .  . o. = =|
    |       ..    + +.|
    |       ..    .=..|
    +----[SHA256]-----+
    """)

private let ecdsa384 = Fixture(
    line: "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBCvwJlB4p1vfvUhf2iOK1emWtOK1It+U9fXa1ePh3KHbVK1IelhktxyfX9/j+FZKXfeH7ODl5WeCbiKqyfc/ZJUbQBTbgLt73SHEc5xkb27br/g3XijgFlEEANLGDbvUmw==",
    kind: .ecdsaP384, bits: 384, comment: nil,
    fingerprint: "SHA256:ai8HqzAcxdQu2wV7XT3uT82AbFNNfTaS/tUOHv2dzKQ",
    randomart: """
    +---[ECDSA 384]---+
    |    ..       ..oo|
    |   o  o     .o+.=|
    |    o. o . o.+.++|
    |   .. o o . =.=.+|
    |  .  + oS  . +***|
    | . .. o.     Eo=B|
    |  +   oo       o |
    |   o .o..       .|
    |    .. o.        |
    +----[SHA256]-----+
    """)

private let ecdsa521 = Fixture(
    line: "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAEhmLhT9RLgQJkTcUUoqM4cPkYnvy/eCob+TFuWwszurGbgiduJybxEZzb8EDEp7gBRmH1gxuX/JIcbOFpVqE2DCgBawEboRsiKSMU8MG+njhDG4hI8Br1Z7zPoGo1PcvLRkNGB1WHFU+tt3KI1A6Z1kPZI7IHhWQbA+dcyB0dqVe5GDQ== p521 key",
    kind: .ecdsaP521, bits: 521, comment: "p521 key",
    fingerprint: "SHA256:7nthYaGEt5lClE+wEGzhtiR4aUnqXDAe4WigXglc2Nw",
    randomart: """
    +---[ECDSA 521]---+
    |o*Bo=+o+         |
    |**=*+E+.+ .      |
    |=+*=+..= = .     |
    |=oo+ .. * o      |
    | +  .  .S. .     |
    |       .  o      |
    |        .. .     |
    |       .  .      |
    |        oo       |
    +----[SHA256]-----+
    """)

private let rsa2048 = Fixture(
    line: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCt2R275NqvPYjb0kwPfmRUZ/sD+I4fMhj/8eQZrBo+xGRFe2s6MaQ5Z0kH/YKR/vFsaVUrm673zmbc8VMK3tYJpyjwzkCIj12wUdw4uq5l6e60CBsqt5FKXVTK+XlOpzHcKULFyrreCRXwzJw5Y6lMZDHVw0Dr8fQ8tRzt1t/SUdyReVLa/o13uuHJ9mhK7DhtKUtxFvySiS1DlFtawg6WZnlqoDl32LWYoqZLCU1ff4UN0WevMv11kAfu9suRZOJmcudCQUthwNTO5V0AdccJKjr/qfDYmpfgqujh8R8sTptHJvYmRJLVa712QS79Y3Pka2CpPlsT4o36LCejzye5 bloom@eccles",
    kind: .rsa, bits: 2048, comment: "bloom@eccles",
    fingerprint: "SHA256:nIVCzgBG5xXFGykORvfmyRRGRP3wCXAGaV8Ls9JGuYE",
    randomart: """
    +---[RSA 2048]----+
    | .+o+ =BXBo.     |
    | . ooB.oE=X .    |
    |   ..o+o=*.% o   |
    |      .Bo+* =    |
    |        So       |
    |                 |
    |                 |
    |                 |
    |                 |
    +----[SHA256]-----+
    """)

private let rsa3072 = Fixture(
    line: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCtG+AmGOYgMUFS0IsIMQgHPmrU3iRhvOVUIm2NKB95wHeY6kcNqsgcckZiXDSUNJUL9cQcHlhOp0L6F+3+RNRtXK8vlImZWd1lHgYImHZ9mvF+Rvg2QzoQDBtg/SKb8dBYciMVCIYfifwDQ0ZhEvyQ3JWC3diYwxEnzy7VzHuSLEuwASUeqiKMCd1QORSqKPb05oP7i1I0VVsSwWg22b5fbgrS+MA5CvRfuTtqmk+MqfuKK2gXoKGs7zdJptNbodTuyzkxepuh8zjLZp/KUjjCY97eYpQtirqJDE0o+rROjW3vrY4dRqEJ1WUTn+ipfB68IdL+nLkmOHuVYD2ASo0m/0nVj2sUdaOVFwkMKsFER5M+wbqq42h7Yzg5qZ6z5yb5EguvLySR1SHTK6MCzp7LPzFINxJI8ZyYimlBklXPNldLlnxl9OaGhQ53/jdKWruf9mTkyiywTs9aUYVOnc9h80I2bAKWyZ84NzKSWBEFMHH6zq+6Zsh9hPvZ5XKfPtM=",
    kind: .rsa, bits: 3072, comment: nil,
    fingerprint: "SHA256:ICCi6bffQuSXmUUYIJHWtABIzrU8h9koncizZZSmDbg",
    randomart: """
    +---[RSA 3072]----+
    |*oo**o..o        |
    |O+**X... .       |
    |oO*%.+. .        |
    |E.*.oo . .       |
    | o .o   S        |
    |  . .o =         |
    |   .. .          |
    |    ...          |
    |     ...         |
    +----[SHA256]-----+
    """)

private let fixtures = [ed25519, ecdsa256, ecdsa384, ecdsa521, rsa2048, rsa3072]

private func blob(_ fixture: Fixture) -> [UInt8] {
    try! Base64.decode(fixture.line.split(separator: " ")[1])
}

private func string(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(string: s, to: &out)
    return out
}

private func field(_ b: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(bytes: b, to: &out)
    return out
}

@Test(arguments: fixtures.indices)
func parsesKeygenOutput(index: Int) throws {
    let fixture = fixtures[index]
    let key = try SSHPublicKey(line: fixture.line)
    #expect(key.kind == fixture.kind)
    #expect(key.bits == fixture.bits)
    #expect(key.comment == fixture.comment)
    #expect(key.fingerprintString == fixture.fingerprint)
    #expect(key.fingerprintSHA256.count == 32)
    #expect(key.blob == blob(fixture))
    #expect(key.authorizedKeysLine() == fixture.line)
    #expect(key.randomart == fixture.randomart)
    #expect(try SSHPublicKey(blob: key.blob, comment: fixture.comment) == key)
    #expect(try SSHPublicKey(line: "  " + fixture.line + "\n") == key)
    let fields = fixture.line.split(separator: " ", maxSplits: 2)
    let loose = fields[0] + "\t " + fields[1] + (fields.count == 3 ? "   " + fields[2] : "")
    #expect(try SSHPublicKey(line: String(loose)) == key, "any whitespace separates the fields")
}

@Test(arguments: fixtures.indices)
func inlineMaterialMatchesKind(index: Int) throws {
    let fixture = fixtures[index]
    let key = try SSHPublicKey(line: fixture.line)
    if fixture.kind == .rsa {
        #expect(key.inlineBytes == nil)
        #expect(key.storedBytes == key.fingerprintSHA256)
        #expect(throws: SSHPublicKey.Error.notInlinable) { try SSHPublicKey(kind: .rsa, inlineBytes: key.fingerprintSHA256) }
        #expect(SSHPublicKey.fingerprintString(sha256: key.storedBytes) == fixture.fingerprint)
    } else {
        let inline = try #require(key.inlineBytes)
        #expect(inline.count == fixture.kind.inlineLength)
        #expect(key.storedBytes == inline)
        let rebuilt = try SSHPublicKey(kind: fixture.kind, inlineBytes: inline)
        #expect(rebuilt.blob == key.blob)
        #expect(rebuilt.fingerprintString == fixture.fingerprint)
        #expect(rebuilt.comment == nil)
        #expect(rebuilt.authorizedKeysLine(comment: fixture.comment) == fixture.line)
        #expect(rebuilt.randomart == fixture.randomart)
    }
}

@Test func kindCodesAreFixed() {
    #expect(SSHPublicKey.Kind.ed25519.rawValue == 0x01)
    #expect(SSHPublicKey.Kind.ecdsaP256.rawValue == 0x02)
    #expect(SSHPublicKey.Kind.ecdsaP384.rawValue == 0x03)
    #expect(SSHPublicKey.Kind.ecdsaP521.rawValue == 0x04)
    #expect(SSHPublicKey.Kind.rsa.rawValue == 0x10)
    for kind in SSHPublicKey.Kind.allCases {
        #expect(SSHPublicKey.Kind(typeName: kind.typeName) == kind)
    }
    #expect(SSHPublicKey.Kind(typeName: "ssh-dss") == nil)
}

@Test func writesGitAllowedSigners() throws {
    let key = try SSHPublicKey(line: ed25519.line)
    let base64 = ed25519.line.split(separator: " ")[1]
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com") == "bloom@nnix.com namespaces=\"git\" ssh-ed25519 \(base64)")
    #expect(key.allowedSignersLine(principal: "bloom@nnix.com", namespace: "file") == "bloom@nnix.com namespaces=\"file\" ssh-ed25519 \(base64)")
    // A hostile principal cannot add a second principal or break the line.
    #expect(key.allowedSignersLine(principal: "a@x.ie,*\n b@x.ie", namespace: "git\" x=\"y") == "a@x.ie*b@x.ie namespaces=\"gitx=y\" ssh-ed25519 \(base64)")
}

@Test func commentsCannotInjectLines() throws {
    let key = try SSHPublicKey(line: ed25519.line)
    let base64 = ed25519.line.split(separator: " ")[1]
    #expect(key.authorizedKeysLine(comment: "Leopold Bloom") == "ssh-ed25519 \(base64) Leopold Bloom")
    #expect(key.authorizedKeysLine(comment: "x\nssh-rsa AAAA evil\r\u{0}") == "ssh-ed25519 \(base64) xssh-rsa AAAA evil")
    #expect(key.authorizedKeysLine(comment: "\n") == "ssh-ed25519 \(base64)")
    #expect(key.authorizedKeysLine(comment: "") == "ssh-ed25519 \(base64)")
}

private let badMalformedLines: [(String, SSHPublicKey.Error)] = [
    ("", SSHPublicKey.Error.malformedLine), ("   ", .malformedLine), ("ssh-ed25519", .malformedLine),
    (ed25519.line + "\nssh-rsa AAAA", .malformedLine),
    ("ssh-ed25519 not-base64! c", .invalidBase64), ("ssh-ed25519 AAAA=AAAA", .invalidBase64),
    ("ssh-dss AAAAB3NzaC1kc3MAAACBAP c", .unsupportedType("ssh-dss")),
    ("ssh-ed25519-cert-v01@openssh.com AAAA", .unsupportedType("ssh-ed25519-cert-v01@openssh.com")),
    ("command=\"x\" " + ed25519.line, .unsupportedType("command=\"x\"")),
    ("sk-ssh-ed25519@openssh.com AAAA", .securityKey("sk-ssh-ed25519@openssh.com")),
    ("sk-ecdsa-sha2-nistp256@openssh.com AAAA", .securityKey("sk-ecdsa-sha2-nistp256@openssh.com")),
    ("ssh-rsa " + ed25519.line.split(separator: " ")[1], .typeMismatch),
    ("ecdsa-sha2-nistp384 " + ecdsa256.line.split(separator: " ")[1], .typeMismatch),
]

@Test(arguments: badMalformedLines)
func rejectsMalformedLines(line: String, error: SSHPublicKey.Error) {
    #expect(throws: error) { try SSHPublicKey(line: line) }
}

@Test func rejectsMalformedBlobs() throws {
    let ed = blob(ed25519)
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: []) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: [0, 0, 0]) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: Array(ed.dropLast())) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: Array(ed.prefix(15))) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: [0xff, 0xff, 0xff, 0xff]) }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: field([0xff, 0xfe])) }
    #expect(throws: SSHPublicKey.Error.trailingBytes) { try SSHPublicKey(blob: ed + [0]) }
    #expect(throws: SSHPublicKey.Error.unsupportedType("ssh-dss")) { try SSHPublicKey(blob: string("ssh-dss")) }
    #expect(throws: SSHPublicKey.Error.securityKey("sk-ssh-ed25519@openssh.com")) {
        try SSHPublicKey(blob: string("sk-ssh-ed25519@openssh.com") + field([UInt8](repeating: 1, count: 32)))
    }
    // The base64 in the line says ed25519 but the blob says rsa.
    #expect(throws: SSHPublicKey.Error.typeMismatch) {
        try SSHPublicKey(line: "ssh-ed25519 " + Base64.encode(blob(rsa2048)))
    }
}

@Test func rejectsWrongEd25519Length() {
    for count in [0, 31, 33, 64] {
        #expect(throws: SSHPublicKey.Error.wrongKeyLength(count)) {
            try SSHPublicKey(blob: string("ssh-ed25519") + field([UInt8](repeating: 7, count: count)))
        }
        #expect(throws: SSHPublicKey.Error.wrongKeyLength(count)) {
            try SSHPublicKey(kind: .ed25519, inlineBytes: [UInt8](repeating: 7, count: count))
        }
    }
    #expect(throws: Never.self) { try SSHPublicKey(kind: .ed25519, inlineBytes: [UInt8](repeating: 7, count: 32)) }
}

@Test func rejectsBadCurvePoints() throws {
    let key = try SSHPublicKey(line: ecdsa256.line)
    let point = try #require(key.inlineBytes)
    var offCurve = point
    offCurve[64] ^= 1
    #expect(throws: SSHPublicKey.Error.invalidPoint) { try SSHPublicKey(kind: .ecdsaP256, inlineBytes: offCurve) }
    #expect(throws: SSHPublicKey.Error.invalidPoint) {
        try SSHPublicKey(blob: string("ecdsa-sha2-nistp256") + string("nistp256") + field(offCurve))
    }
    var compressed = point
    compressed[0] = 0x02
    #expect(throws: SSHPublicKey.Error.invalidPoint) { try SSHPublicKey(kind: .ecdsaP256, inlineBytes: compressed) }
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(33)) { try SSHPublicKey(kind: .ecdsaP256, inlineBytes: Array(point.prefix(33))) }
    #expect(throws: SSHPublicKey.Error.wrongKeyLength(65)) { try SSHPublicKey(kind: .ecdsaP384, inlineBytes: point) }
    // A P-256 point is not a P-384 point even at the right length.
    let p384 = try #require(try SSHPublicKey(line: ecdsa384.line).inlineBytes)
    var wrongCurve = p384
    wrongCurve[1] ^= 0x80
    #expect(throws: SSHPublicKey.Error.invalidPoint) { try SSHPublicKey(kind: .ecdsaP384, inlineBytes: wrongCurve) }
    // Curve name must agree with the type.
    #expect(throws: SSHPublicKey.Error.malformedBlob) {
        try SSHPublicKey(blob: string("ecdsa-sha2-nistp256") + string("nistp384") + field(point))
    }
    // Every generated ECDSA key is a valid point; a zeroed one is not.
    for kind in [SSHPublicKey.Kind.ecdsaP256, .ecdsaP384, .ecdsaP521] {
        var zero = [UInt8](repeating: 0, count: kind.inlineLength!)
        zero[0] = 0x04
        #expect(throws: SSHPublicKey.Error.invalidPoint) { try SSHPublicKey(kind: kind, inlineBytes: zero) }
    }
}

@Test func rejectsNonMinimalRSA() throws {
    let modulus = [UInt8](repeating: 0xab, count: 256)
    let good = string("ssh-rsa") + field([0x01, 0x00, 0x01]) + field([0x00] + modulus)
    let key = try SSHPublicKey(blob: good)
    #expect(key.kind == .rsa)
    #expect(key.bits == 2048)
    #expect(throws: SSHPublicKey.Error.malformedBlob) {
        try SSHPublicKey(blob: string("ssh-rsa") + field([0x00, 0x01, 0x00, 0x01]) + field([0x00] + modulus))
    }
    #expect(throws: SSHPublicKey.Error.malformedBlob) {
        try SSHPublicKey(blob: string("ssh-rsa") + field([0x01, 0x00, 0x01]) + field(modulus))
    }
    #expect(throws: SSHPublicKey.Error.malformedBlob) {
        try SSHPublicKey(blob: string("ssh-rsa") + field([]) + field([0x00] + modulus))
    }
    #expect(throws: SSHPublicKey.Error.malformedBlob) {
        try SSHPublicKey(blob: string("ssh-rsa") + field([0x01, 0x00, 0x01]) + field([0x00, 0x00, 0x80]))
    }
    #expect(throws: SSHPublicKey.Error.malformedBlob) {
        try SSHPublicKey(blob: string("ssh-rsa") + field([0x01, 0x00, 0x01]) + field([0x00]))
    }
    #expect(throws: SSHPublicKey.Error.malformedBlob) { try SSHPublicKey(blob: string("ssh-rsa") + field([0x01, 0x00, 0x01])) }
    let small = try SSHPublicKey(blob: string("ssh-rsa") + field([0x03]) + field([0x05]))
    #expect(small.bits == 3)
}

@Test func randomartFollowsTheDrunkenBishop() {
    let zero = SSHPublicKey.randomart(fingerprint: [UInt8](repeating: 0, count: 32), title: "[ZERO]")
    // Every step is (-1, -1): the bishop walks to the corner and stays.
    let lines = zero.split(separator: "\n").map(String.init)
    #expect(lines.count == 11)
    #expect(lines[0] == "+-----[ZERO]------+")
    #expect(lines[1] == "|E....            |")
    #expect(lines[2] == "|     .           |")
    #expect(lines[3] == "|      .          |")
    #expect(lines[4] == "|       .         |")
    #expect(lines[5] == "|        S        |")
    #expect(lines[10] == "+----[SHA256]-----+")
    #expect(lines.allSatisfy { $0.count == 19 })
    // A title that does not fit is dropped, as OpenSSH does.
    let long = SSHPublicKey.randomart(fingerprint: [], title: "[A TITLE THAT IS TOO LONG]", footer: "[MD5]")
    #expect(long.hasPrefix("+-----------------+\n"))
    #expect(long.hasSuffix("+------[MD5]------+"))
    // An empty fingerprint starts and ends in the centre; E is marked last, as in OpenSSH.
    #expect(long.split(separator: "\n")[5] == "|        E        |")
}
