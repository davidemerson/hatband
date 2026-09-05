import Foundation
import Testing
@testable import Hatband

struct FetchTargetTests {
    @Test func wkdAdvancedJoeDoe() {
        let target = FetchTarget.wkdAdvanced(local: "Joe.Doe", domain: "example.org")
        #expect(target.url.absoluteString
            == "https://openpgpkey.example.org/.well-known/openpgpkey/example.org/hu/iy9q119eutrkn8s1mk4r39qejnbu3n5q?l=Joe.Doe")
        #expect(target.host == "openpgpkey.example.org")
        #expect(target.kind == .wkdAdvanced)
    }

    @Test func wkdDirect() {
        let target = FetchTarget.wkdDirect(local: "Joe.Doe", domain: "Example.org")
        #expect(target.url.absoluteString == "https://example.org/.well-known/openpgpkey/hu/iy9q119eutrkn8s1mk4r39qejnbu3n5q?l=Joe.Doe")
        #expect(target.host == "example.org")
        #expect(target.kind == .wkdDirect)
    }

    @Test func keysOpenPGPHexLength() {
        let v4 = FetchTarget.keysOpenPGP(fingerprint: (0..<20).map { UInt8(0xa0 + $0) })
        let v4Path = v4.url.absoluteString
        #expect(v4Path.hasPrefix("https://keys.openpgp.org/vks/v1/by-fingerprint/"))
        let v4Hex = v4Path.dropFirst("https://keys.openpgp.org/vks/v1/by-fingerprint/".count)
        #expect(v4Hex.count == 40)
        #expect(v4Hex == "A0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3")
        let v6 = FetchTarget.keysOpenPGP(fingerprint: [UInt8](repeating: 0xcb, count: 32))
        let v6Hex = v6.url.absoluteString.dropFirst("https://keys.openpgp.org/vks/v1/by-fingerprint/".count)
        #expect(v6Hex.count == 64)
        #expect(v6Hex.allSatisfy { $0.isHexDigit && !$0.isLowercase })
        #expect(v6.host == "keys.openpgp.org")
    }

    @Test func githubKeys() {
        let target = FetchTarget.githubKeys(user: "lbloom")
        #expect(target.url.absoluteString == "https://github.com/lbloom.keys")
        #expect(target.host == "github.com")
        #expect(target.kind == .githubKeys)
    }

    @Test func githubGPG() {
        let target = FetchTarget.githubGPG(user: "lbloom")
        #expect(target.url.absoluteString == "https://github.com/lbloom.gpg")
        #expect(target.host == "github.com")
        #expect(target.kind == .githubGPG)
    }

    @Test func mastodonLookupEncodesAcct() {
        let target = FetchTarget.mastodonLookup(user: "bloom", instance: "merveilles.town")
        #expect(target.url.absoluteString == "https://merveilles.town/api/v1/accounts/lookup?acct=bloom%40merveilles.town")
        #expect(target.host == "merveilles.town")
        #expect(target.kind == .mastodonLookup)
        let odd = FetchTarget.mastodonLookup(user: "a b", instance: "merveilles.town")
        #expect(odd.url.absoluteString == "https://merveilles.town/api/v1/accounts/lookup?acct=a%20b%40merveilles.town")
    }

    @Test func hostPerCase() {
        #expect(FetchTarget.wkdAdvanced(local: "a", domain: "Example.ORG").host == "openpgpkey.example.org")
        #expect(FetchTarget.wkdDirect(local: "a", domain: "example.org").host == "example.org")
        #expect(FetchTarget.keysOpenPGP(fingerprint: []).host == "keys.openpgp.org")
        #expect(FetchTarget.githubKeys(user: "x").host == "github.com")
        #expect(FetchTarget.githubGPG(user: "x").host == "github.com")
        #expect(FetchTarget.mastodonLookup(user: "x", instance: "Merveilles.town").host == "merveilles.town")
        for target in samples {
            #expect(target.url.host(percentEncoded: false) == target.host)
            #expect(target.url.scheme == "https")
        }
    }

    @Test func kindCoversEveryCase() {
        #expect(FetchTarget.Kind.allCases.count == 6)
        #expect(Set(samples.map { $0.kind }) == Set(FetchTarget.Kind.allCases))
    }

    @Test func redirectPolicy() throws {
        let origin = try #require(URL(string: "https://keys.openpgp.org/vks/v1/by-fingerprint/AA"))
        let samePath = try #require(URL(string: "https://keys.openpgp.org/other"))
        let sameHostUpper = try #require(URL(string: "https://KEYS.openpgp.org/other"))
        let otherHost = try #require(URL(string: "https://example.org/"))
        let downgrade = try #require(URL(string: "http://keys.openpgp.org/other"))
        let plainOrigin = try #require(URL(string: "http://keys.openpgp.org/x"))
        #expect(ExplicitFetch.allowsRedirect(from: origin, to: samePath))
        #expect(ExplicitFetch.allowsRedirect(from: origin, to: sameHostUpper))
        #expect(!ExplicitFetch.allowsRedirect(from: origin, to: otherHost))
        #expect(!ExplicitFetch.allowsRedirect(from: origin, to: downgrade))
        #expect(!ExplicitFetch.allowsRedirect(from: plainOrigin, to: origin))
        #expect(!ExplicitFetch.allowsRedirect(from: origin, to: FetchTarget.unusable))
    }

    private var samples: [FetchTarget] {
        [
            .wkdAdvanced(local: "Joe.Doe", domain: "example.org"),
            .wkdDirect(local: "Joe.Doe", domain: "example.org"),
            .keysOpenPGP(fingerprint: [UInt8](repeating: 1, count: 20)),
            .githubKeys(user: "lbloom"),
            .githubGPG(user: "lbloom"),
            .mastodonLookup(user: "bloom", instance: "merveilles.town"),
        ]
    }
}
