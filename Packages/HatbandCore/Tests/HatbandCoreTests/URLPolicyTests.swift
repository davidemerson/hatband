import Testing
@testable import HatbandCore

private let fingerprint40 = "D8692E4DD0D4B4C7A1E30A1F3F1B2C4D5E6F7A8B"
private let fingerprint64 = fingerprint40 + "0123456789ABCDEF01234567"

@Test(arguments: [
    ("https://github.com", Verdict.ok),
    ("https://github.com/", .ok),
    ("https://github.com/lbloom?tab=repositories#top", .ok),
    ("HTTPS://GitHub.com", .ok),
    ("https://host:443", .ok),
    ("https://host:1", .ok),
    ("https://host:65535/x", .ok),
    ("https://localhost:8080/x", .ok),
    ("https://example.com/a%2Fb%20c", .ok),
    ("https://example.com/%C3%A9%F0%9F%98%80", .ok),
    ("https://example.com/?next=https://evil.com", .ok),
    ("https://example.com/Stra\u{DF}e", .ok),
    ("https://example.com/~bloom/(1),2;3=4&5+6*7!8$9'", .ok),
    ("https://de.wikipedia.org/wiki/Ulysses_(Roman)", .ok),
    ("https://signal.me/#p/+1555", .ok),
    ("https://signal.me/#eu/abc-_=", .ok),
    ("http://example.com", .warning("not encrypted")),
    ("HTTP://example.com/x", .warning("not encrypted")),
    ("https://xn--mnchen-3ya.de", .warning("punycode host label")),
    ("http://xn--mnchen-3ya.de", .warning("punycode host label; not encrypted")),
])
func acceptsWebLinks(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    ("javascript:alert(1)", Verdict.reject("scheme not allowed: javascript")),
    ("JAVASCRIPT:alert(1)", .reject("scheme not allowed: javascript")),
    ("JAVASCRIPT:", .reject("scheme not allowed: javascript")),
    ("data:text/html,<script>", .reject("scheme not allowed: data")),
    ("file:///etc/passwd", .reject("scheme not allowed: file")),
    ("ftp://example.com", .reject("scheme not allowed: ftp")),
    ("sgnl://signal.me/#p/+1555", .reject("scheme not allowed: sgnl")),
    ("ssh://git@github.com", .reject("scheme not allowed: ssh")),
    ("xmpp:a@b", .reject("scheme not allowed: xmpp")),
    ("hatband:x", .reject("scheme not allowed: hatband")),
    ("a+b-c.d:x", .reject("scheme not allowed: a+b-c.d")),
    ("example.com", .reject("missing scheme")),
    ("//example.com", .reject("missing scheme")),
    ("", .reject("missing scheme")),
    (":", .reject("missing scheme")),
    ("1http://x", .reject("missing scheme")),
    ("example.com/path:80", .reject("missing scheme")),
    ("example.com:80", .reject("missing scheme")),                   // a port, not a path after scheme `example.com`
    ("example.com:8080/x", .reject("missing scheme")),
    ("localhost:8080", .reject("missing scheme")),
    ("example.com:abc", .reject("scheme not allowed: example.com")),  // the grammar's answer when no port follows
    ("ht tp://x", .reject("whitespace")),
])
func rejectsOtherSchemes(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    (" https://x", Verdict.reject("whitespace")),
    ("https://x ", .reject("whitespace")),
    ("https://exam ple.com", .reject("whitespace")),
    ("https://example.com/path with space", .reject("whitespace")),
    ("https://x\u{A0}.com", .reject("whitespace")),
    ("https://x\u{3000}.com", .reject("whitespace")),
    ("https://x\n", .reject("control character")),
    ("https://x\u{0}", .reject("control character")),
    ("https://x\u{200B}.com", .reject("invisible character")),
    ("https://x\u{FEFF}.com", .reject("invisible character")),
    ("https://x\u{202E}", .reject("bidirectional control character")),
    ("https://x\u{E000}", .reject("unassigned or private-use character")),
])
func rejectsHiddenCharacters(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    ("https://user:pw@host", Verdict.reject("userinfo in URL")),
    ("https://user@host", .reject("userinfo in URL")),
    ("https://@host", .reject("userinfo in URL")),
    ("https://host:0", .reject("invalid port")),
    ("https://host:65536", .reject("invalid port")),
    ("https://host:", .reject("invalid port")),
    ("https://host:4a", .reject("invalid port")),
    ("https://host:443:1", .reject("invalid port")),
    ("https://host:123456", .reject("invalid port")),
    ("https://[::1]", .reject("invalid host label")),
    ("https://[::1]:443", .reject("invalid host label")),
    ("https://", .reject("empty host")),
    ("https:///path", .reject("empty host")),
    ("https://?q", .reject("empty host")),
    ("https:example.com", .reject("malformed URL")),
    ("https:/example.com", .reject("malformed URL")),
    ("https:", .reject("malformed URL")),
    ("https:443", .reject("malformed URL")),
    ("https://g\u{456}thub.com", .reject("non-ASCII host, looks like “github.com”")),
    ("https://\u{430}pple.com/", .reject("non-ASCII host, looks like “apple.com”")),
    ("https://münchen.de", .reject("non-ASCII host")),
    ("https://-example.com", .reject("invalid host label")),
    ("https://example-.com", .reject("invalid host label")),
    ("https://example..com", .reject("invalid host label")),
    ("https://.example.com", .reject("invalid host label")),
    ("https://example.com.", .reject("invalid host label")),
    ("https://ex_ample.com", .reject("invalid host label")),
    ("https://example.com\\evil", .reject("invalid host label")),
    ("https://127.0.0.1", .reject("IP address")),
    ("https://2130706433/", .reject("IP address")),
    ("https://0x7f000001:443", .reject("IP address")),
    ("https://example.123", .reject("IP address")),
    ("https://xn--pple-43d.com", .reject("non-ASCII host, looks like “apple.com”")),
    ("https://xn--b.com", .reject("invalid punycode label")),
])
func rejectsBadAuthorities(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    ("https://example.com/<script>", Verdict.reject("invalid character in URL")),
    ("https://example.com/\"", .reject("invalid character in URL")),
    ("https://example.com/a|b", .reject("invalid character in URL")),
    ("https://example.com/a\\b", .reject("invalid character in URL")),
    ("https://example.com/a^b", .reject("invalid character in URL")),
    ("https://example.com/a`b", .reject("invalid character in URL")),
    ("https://example.com/{a}", .reject("invalid character in URL")),
    ("https://example.com/%zz", .reject("bad percent-encoding")),
    ("https://example.com/%2", .reject("bad percent-encoding")),
    ("https://example.com/%", .reject("bad percent-encoding")),
    ("https://example.com/?%G0", .reject("bad percent-encoding")),
    ("https://example.com/%00", .reject("control character")),                    // what a triplet hides is scanned too
    ("https://example.com/%0d%0a", .reject("control character")),
    ("https://example.com/%E2%80%AE", .reject("bidirectional control character")),
    ("https://example.com/?%E2%80%8B", .reject("invisible character")),
    ("https://example.com/#%EE%80%80", .reject("unassigned or private-use character")),
])
func rejectsBadPaths(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    ("mailto:a@b", Verdict.ok),
    ("mailto:a@b?subject=x", .ok),
    ("mailto:a@b?subject=x&body=y%20z", .ok),
    ("mailto:henry.flower@example.ie", .ok),
    ("mailto:henry+flower@example.ie", .ok),
    ("MAILTO:A@B", .ok),
    ("mailto:a@xn--mnchen-3ya.de", .warning("punycode host label")),
    ("mailto:a@b?subject=x y", .reject("whitespace")),
    ("mailto:a", .reject("not an email address")),
    ("mailto:12345", .reject("not an email address")),
    ("mailto:", .reject("not an email address")),
    ("mailto:a@b@c", .reject("not an email address")),
    ("mailto:@b", .reject("not an email address")),
    ("mailto:.a@b", .reject("not an email address")),
    ("mailto:a.@b", .reject("not an email address")),
    ("mailto:a..b@c", .reject("not an email address")),
    ("mailto://a@b", .reject("not an email address")),
    ("mailto:a(b)@c", .reject("not an email address")),
    ("mailto:\"a\"@c", .reject("not an email address")),
    ("mailto:a@", .reject("empty host")),
    ("mailto:a@-b", .reject("invalid host label")),
    ("mailto:a@b?%zz", .reject("bad percent-encoding")),
    ("mailto:ünï@b", .reject("non-ASCII character")),
    ("mailto:a@münchen.de", .reject("non-ASCII host")),
    ("mailto:a@g\u{456}thub.com", .reject("non-ASCII host, looks like “github.com”")),
    ("mailto:a@b?body=x", .ok),
    ("mailto:a@b?Subject=x&BODY=y", .ok),
    ("mailto:a@b?%53ubject=x", .ok),
    ("mailto:a@b?subject=a=b&", .ok),
    ("mailto:a@b?bcc=spy@evil.com", .reject("mailto header not allowed")),
    ("mailto:a@b?to=x", .reject("mailto header not allowed")),
    ("mailto:a@b?cc=x&subject=hi", .reject("mailto header not allowed")),
    ("mailto:a@b?subject=x&BCC=y", .reject("mailto header not allowed")),
    ("mailto:a@b?%62cc=x", .reject("mailto header not allowed")),
    ("mailto:a@b?in-reply-to=x", .reject("mailto header not allowed")),
    ("mailto:a@b?x", .reject("mailto header not allowed")),
    ("mailto:a@b?subject=%0D%0Abcc:x", .reject("control character")),
    ("mailto:a@127.0.0.1", .reject("IP address")),
])
func judgesMailto(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    ("tel:+1-555", Verdict.ok),
    ("tel:+15551234567", .ok),
    ("tel:+353871234567", .ok),
    ("tel:+1(555)123.4567", .ok),
    ("tel:+123456789012345", .ok),
    ("TEL:+1555", .ok),
    ("tel:+12", .ok),
    ("tel:+1 555", .reject("whitespace")),
    ("tel:5551234", .reject("not an E.164 number")),
    ("tel:555", .reject("not an E.164 number")),                    // a known scheme, not a host and port
    ("tel:+0123", .reject("not an E.164 number")),
    ("tel:+1", .reject("not an E.164 number")),
    ("tel:+1234567890123456", .reject("not an E.164 number")),
    ("tel:+1-555;ext=1", .reject("not an E.164 number")),
    ("tel:++1555", .reject("not an E.164 number")),
    ("tel:+1555x", .reject("not an E.164 number")),
    ("tel:", .reject("not an E.164 number")),
    ("tel:\u{FF0B}\u{FF11}\u{FF15}\u{FF15}\u{FF15}", .reject("not an E.164 number")),
])
func judgesTel(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test(arguments: [
    ("acct:bloom@merveilles.town", Verdict.ok),
    ("acct:henry_flower@example.ie", .ok),
    ("acct:bloom", .reject("not an acct address")),
    ("acct:@x", .reject("not an acct address")),
    ("acct:bloom@", .reject("empty host")),
    ("acct:bloom@m\u{430}stodon.social", .reject("non-ASCII host, looks like “mastodon.social”")),
])
func judgesAcct(url: String, verdict: Verdict) {
    #expect(URLPolicy.verdict(for: url) == verdict)
}

@Test func judgesFingerprints() {
    #expect(URLPolicy.verdict(for: "OPENPGP4FPR:" + fingerprint40) == .ok)
    #expect(URLPolicy.verdict(for: "openpgp4fpr:" + fingerprint40.lowercased()) == .ok)
    #expect(URLPolicy.verdict(for: "OPENPGP4FPR:" + fingerprint64) == .ok)
    let bad = Verdict.reject("not an OpenPGP fingerprint")
    #expect(URLPolicy.verdict(for: "OPENPGP4FPR:" + fingerprint40.dropLast()) == bad)
    #expect(URLPolicy.verdict(for: "OPENPGP4FPR:" + fingerprint40 + "0") == bad)
    #expect(URLPolicy.verdict(for: "OPENPGP4FPR:" + fingerprint40.dropLast() + "G") == bad)
    #expect(URLPolicy.verdict(for: "OPENPGP4FPR:") == bad)
    #expect(URLPolicy.verdict(for: "OPENPGP4FPR:" + fingerprint40 + " ") == .reject("whitespace"))
    #expect(!URLPolicy.isTappable("OPENPGP4FPR:" + fingerprint40))
}

@Test(arguments: [
    ("https://github.com", true),
    ("http://example.com", true),
    ("mailto:a@b", true),
    ("tel:+1555", true),
    ("https://xn--mnchen-3ya.de", true),
    ("acct:bloom@merveilles.town", false),
    ("javascript:alert(1)", false),
    ("https://g\u{456}thub.com", false),
    ("https://user@host", false),
    ("", false),
    (" https://x", false),
    ("github.com", false),
    ("https://127.0.0.1", false),
    ("https://xn--pple-43d.com", false),
    ("mailto:a@b?bcc=x", false),
])
func decidesTappability(url: String, tappable: Bool) {
    #expect(URLPolicy.isTappable(url) == tappable)
}

@Test func lengthCapCountsBytes() {
    let prefix = "https://example.com/"
    let exact = prefix + String(repeating: "a", count: URLPolicy.maxBytes - prefix.utf8.count)
    #expect(exact.utf8.count == 2048)
    #expect(URLPolicy.verdict(for: exact) == .ok)
    #expect(URLPolicy.verdict(for: exact + "a") == .reject("over 2048 bytes"))
    let multibyte = prefix + String(repeating: "a", count: URLPolicy.maxBytes - prefix.utf8.count - 1) + "\u{E9}"
    #expect(multibyte.count == 2048)
    #expect(multibyte.utf8.count == 2049)
    #expect(URLPolicy.verdict(for: multibyte) == .reject("over 2048 bytes"))
    // The cap comes before every other check, so a huge hostile string is cheap.
    #expect(URLPolicy.verdict(for: String(repeating: "\u{202E}", count: 1000)) == .reject("over 2048 bytes"))
}

@Test func schemeParsing() {
    #expect(URLPolicy.scheme(of: Array("https://x".utf8)) == "https")
    #expect(URLPolicy.scheme(of: Array("HTTPS://x".utf8)) == "https")
    #expect(URLPolicy.scheme(of: Array("a+b-c.d:".utf8)) == "a+b-c.d")
    #expect(URLPolicy.scheme(of: Array("+a:".utf8)) == nil)
    #expect(URLPolicy.scheme(of: Array("a b:".utf8)) == nil)
    #expect(URLPolicy.scheme(of: Array("a/b:".utf8)) == nil)
    #expect(URLPolicy.scheme(of: Array(":x".utf8)) == nil)
    #expect(URLPolicy.scheme(of: []) == nil)
    #expect(URLPolicy.scheme(of: Array("example.com:80".utf8)) == nil, "host and port")
    #expect(URLPolicy.scheme(of: Array("example.com:80/x".utf8)) == nil)
    #expect(URLPolicy.scheme(of: Array("example.com:123456".utf8)) == "example.com", "six digits are no port")
    #expect(URLPolicy.scheme(of: Array("tel:5551234".utf8)) == "tel")
    #expect(URLPolicy.scheme(of: Array("tel:555".utf8)) == "tel", "a known scheme, whatever follows")
    #expect(URLPolicy.scheme(of: Array("mailto:12345".utf8)) == "mailto")
    #expect(URLPolicy.scheme(of: Array("ACCT:1".utf8)) == "acct")
    #expect(URLPolicy.scheme(of: Array("https:443".utf8)) == "https")
    #expect(URLPolicy.scheme(of: Array("https://host:443".utf8)) == "https")
    let long = String(repeating: "z", count: 100) + ":"
    #expect(URLPolicy.verdict(for: long) == .reject("scheme not allowed: " + String(repeating: "z", count: 32)))
}

@Test func e164Shape() {
    #expect(URLPolicy.isE164("+12".utf8))
    #expect(URLPolicy.isE164("+123456789012345".utf8))
    #expect(!URLPolicy.isE164("+1".utf8))
    #expect(!URLPolicy.isE164("+1234567890123456".utf8))
    #expect(!URLPolicy.isE164("+0".utf8))
    #expect(!URLPolicy.isE164("12".utf8))
    #expect(!URLPolicy.isE164("".utf8))
    #expect(!URLPolicy.isE164("+".utf8))
    #expect(!URLPolicy.isE164("+-1".utf8))
    #expect(!URLPolicy.isE164("+1 2".utf8))
}
