import Testing
@testable import HatbandCore

// Nits from the review of the scalar sweep, closed: a hostname's hyphen
// and digit rules are judged with trailing marks set aside; a linkedin.com
// subdomain is judged as a hostname before it is discarded; an ECDSA curve
// name on the wire is compared byte for byte; and a vCard property name
// is case-folded as ASCII only.

private let mark = "\u{301}"
private let reph = "\u{0D4E}"
private let ecdsa256 = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPlnx2p7LH4G02PXQJ5HDPmfKIeP2Rzq9adOBa6F1LgVfT2p2J9Yk+4aN2pM+zoHfGrxuMm5h92a6M+PVrNTdoI= bloom@eccles"
private let ecdsa384 = "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBCvwJlB4p1vfvUhf2iOK1emWtOK1It+U9fXa1ePh3KHbVK1IelhktxyfX9/j+FZKXfeH7ODl5WeCbiKqyfc/ZJUbQBTbgLt73SHEc5xkb27br/g3XijgFlEEANLGDbvUmw=="
private let ecdsa521 = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAEhmLhT9RLgQJkTcUUoqM4cPkYnvy/eCob+TFuWwszurGbgiduJybxEZzb8EDEp7gBRmH1gxuX/JIcbOFpVqE2DCgBawEboRsiKSMU8MG+njhDG4hI8Br1Z7zPoGo1PcvLRkNGB1WHFU+tt3KI1A6Z1kPZI7IHhWQbA+dcyB0dqVe5GDQ== p521 key"

private func wire(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(string: s, to: &out)
    return out
}

private func wire(_ b: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    WireReader.append(bytes: b, to: &out)
    return out
}

@Suite struct InteropSweepNits {
    // MARK: - Hostname

    /// A mark on a trailing hyphen, or on the digits of a last label, is
    /// drawn on it and changes nothing: the marked spellings are refused
    /// as the plain ones are. A mark inside the label, or a letter after
    /// the digit (the Prepend one included), still makes a name.
    @Test(arguments: ["\u{301}", "\u{903}", "\u{301}\u{301}", "\u{301}\u{903}"])
    func trailingMarksHideNeitherHyphenNorDigits(marks: String) throws {
        for host in ["nnix.com-\(marks)", "nnix-\(marks).com", "nnix.1\(marks)", "1.2.3.4\(marks)", "nnix.\u{661}\u{662}\(marks)", "nnix.\(marks)"] {
            #expect(Hostname.normalized(Substring(host)) == nil, "\(host)")
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.website(host) }
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.website("https://" + host + "/path") }
            #expect(throws: Normalize.Error.invalidHost, "\(host)") { try Normalize.mastodon("bloom@" + host) }
        }
        for host in ["nnix.1\(marks)a", "nnix.a\(marks)-1.com", "nnix.c\(marks)om", "nnix.\u{661}\(marks)a", "n\(marks)-\(marks)n.com"] {
            #expect(Hostname.normalized(Substring(host)) == host, "\(host)")
            #expect(try Normalize.website(host).address == host, "\(host)")
        }
        #expect(Hostname.normalized(Substring("nnix.1" + reph)) == "nnix.1" + reph)
        #expect(Hostname.normalized("nnix.1a") == "nnix.1a")
        #expect(Hostname.normalized("nnix.com-") == nil)
        #expect(Hostname.normalized("nnix.1") == nil)
    }

    // MARK: - LinkedIn subdomains

    /// What precedes `.linkedin.com` is a hostname or the URL is refused:
    /// a hidden scalar, a space, a punctuation mark, an empty label or a
    /// hyphen at a label's end there is `invalidHost`, not silently dropped.
    /// An honest subdomain, a mark inside a label or a Prepend letter
    /// included, is discarded as before and only the slug is stored.
    @Test func linkedinSubdomainsAreJudgedBeforeTheyAreDiscarded() throws {
        for bad in ["\u{200B}", "\u{200D}", "\u{200C}", "\u{FE0F}", "\u{E0041}", "\u{600}", "\u{202E}", "\u{34F}",
                    " ", "\u{A0}", "\u{3000}", "_", "%20", "!", "\u{3002}", "\u{FF0E}", "\u{2024}", "\u{B2}"] {
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("https://ie\(bad).linkedin.com/in/bloom") }
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("https://\(bad).linkedin.com/in/bloom") }
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("https://ie\(bad).www.linkedin.com/in/bloom") }
        }
        for bad in ["a b", "\(mark)", "ie-", "-ie", "", "ie.", ".ie", "ie..uk", String(repeating: "a", count: 64)] {
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("https://\(bad).linkedin.com/in/bloom") }
            #expect(throws: Normalize.Error.invalidHost, "\(bad.debugDescription)") { try Normalize.linkedin("\(bad).linkedin.com/in/bloom") }
        }
        for good in ["ie", "www", "IE", "ie\(mark)", reph, "ie.\(reph)", "uk.www", "a-b", "1a", "xn--mnchen-3ya", String(repeating: "a", count: 63)] {
            #expect(try Normalize.linkedin("https://\(good).linkedin.com/in/bloom") == "bloom", "\(good.debugDescription)")
            #expect(try Normalize.linkedin("\(good).linkedin.com/company/acme") == "company/acme", "\(good.debugDescription)")
        }
        #expect(try Normalize.linkedin("https://linkedin.com/in/bloom") == "bloom")
        #expect(try Normalize.linkedin("https://LinkedIn.com/in/bloom") == "bloom")
        // Another host is named as such before its labels are judged.
        #expect(throws: Normalize.Error.wrongHost("ie linkedin.com")) { try Normalize.linkedin("https://ie linkedin.com/in/bloom") }
        #expect(throws: Normalize.Error.wrongHost("ie.linkedin.com\(mark)")) { try Normalize.linkedin("https://ie.linkedin.com\(mark)/in/bloom") }
        #expect(throws: Normalize.Error.wrongHost("ie.linkedin.com:443")) { try Normalize.linkedin("https://ie.linkedin.com:443/in/bloom") }
    }

    // MARK: - SSH curve names

    /// The curve name in an ECDSA blob is compared byte for byte, as sshd
    /// compares it: a mark, a joiner, a fullwidth digit or another case
    /// makes another string, whatever `String` equality would say.
    @Test func curveNameIsComparedAsBytes() throws {
        for (line, kind, curve) in [(ecdsa256, SSHPublicKey.Kind.ecdsaP256, "nistp256"), (ecdsa384, .ecdsaP384, "nistp384"), (ecdsa521, .ecdsaP521, "nistp521")] {
            let key = try SSHPublicKey(line: line)
            let point = try #require(key.inlineBytes)
            #expect(try SSHPublicKey(blob: wire(kind.typeName) + wire(curve) + wire(point)).kind == kind)
            for wrong in [curve + "\u{301}", "\u{301}" + curve, curve + "\u{200D}", curve + "\u{FE0F}", curve + "\u{E0041}",
                          curve.uppercased(), String(curve.dropLast()) + "\u{FF10}", curve + " ", " " + curve, curve + "\0", ""] {
                #expect(throws: SSHPublicKey.Error.malformedBlob, "\(wrong.debugDescription)") {
                    try SSHPublicKey(blob: wire(kind.typeName) + wire(wrong) + wire(point))
                }
            }
            // Bytes that are not UTF-8 are refused the same way.
            #expect(throws: SSHPublicKey.Error.malformedBlob) {
                try SSHPublicKey(blob: wire(kind.typeName) + wire(Array(curve.utf8) + [0xFF]) + wire(point))
            }
        }
    }

    // MARK: - vCard property names

    /// Case folding is ASCII only: `ß` and `ﬁ` are dropped, never spelt
    /// out as `SS` and `FI`; `ſ` and `ı`, whose full uppercase is ASCII,
    /// are dropped too. A mark on an ASCII letter is dropped and the
    /// letter kept, as before.
    @Test func propertyNamesFoldCaseAsASCII() throws {
        #expect("\u{DF}-\u{FB01}".uppercased() == "SS-FI")  // why not the full mapping
        #expect(VCard.propertyName("\u{DF}-\u{FB01}") == "-")
        #expect(VCard.propertyName("stra\u{DF}e") == "STRAE")
        #expect(VCard.propertyName("\u{FB01}le") == "LE")
        #expect(VCard.propertyName("\u{17F}eq") == "EQ")
        #expect(VCard.propertyName("\u{131}d") == "D")
        #expect(VCard.propertyName("\u{149}ab") == "AB")
        #expect(VCard.propertyName("\u{212A}ey") == "EY")
        #expect(VCard.propertyName("key-1") == "KEY-1")
        #expect(VCard.propertyName("e\(mark)tat") == "ETAT")
        #expect(VCard.propertyName("\u{E9}tat") == "TAT")
        #expect(VCard.propertyName("\(reph)seq") == "SEQ")
        #expect(VCard.Extension(name: "\u{17F}eq", value: "").name == "EQ")
        var card = VCard(formattedName: "x")
        card.extensions = [VCard.Extension(name: "\u{DF}-\u{FB01}", value: "v")]
        #expect(card.text.contains("X-HATBAND--:v"))
        #expect(try VCard.parseBasic(card.text).extensions == card.extensions)
    }
}
