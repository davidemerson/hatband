import Testing
@testable import Hatband

struct TrustFactsTests {
    @Test func oneEgressPerFetchKindPlusSafariAndMaps() {
        let egress = TrustFacts.egress
        #expect(egress.count == FetchTarget.Kind.allCases.count + 2)
        for kind in FetchTarget.Kind.allCases {
            #expect(egress.contains(TrustFacts.egress(for: kind)), "\(kind) is missing")
        }
        #expect(Array(egress.suffix(2)) == [TrustFacts.safari, TrustFacts.maps])
        #expect(egress.allSatisfy { !$0.host.isEmpty && !$0.when.isEmpty })
    }

    @Test func hostsNameWhereBytesGo() {
        let hosts = TrustFacts.egress.map { $0.host }
        #expect(hosts.contains("keys.openpgp.org"))
        #expect(hosts.filter { $0 == "github.com" }.count == 2)
        #expect(hosts.contains { $0.hasPrefix("openpgpkey.") })
        #expect(hosts.contains { $0.contains("Mastodon") })
        #expect(hosts.contains("Safari"))
        #expect(hosts.contains("Apple Maps"))
        #expect(TrustFacts.egress.allSatisfy { $0.when.contains("tap") })
    }

    /// The page quotes the button, and the button is built from the same
    /// words, so the two cannot drift. They had: the page said "Fetch key
    /// (WKD)" and "Verify" long after the buttons were renamed, and the only
    /// test on the text asked whether it contained the word "tap".
    @Test func everyRowQuotesTheButtonThatDoesIt() {
        for kind in FetchTarget.Kind.allCases {
            let row = TrustFacts.egress(for: kind)
            let title = kind.title(host: TrustFacts.placeholderHost(for: kind))
            #expect(row.when.contains(title), "\(kind) does not quote its button")
            #expect(row.when.hasPrefix("You tap "))
            #expect(row.when.hasSuffix("."))
        }
    }

    /// A real target's button says the same thing with the host filled in,
    /// which is what the person screen shows.
    @Test func aRealTargetTitlesItsOwnButton() {
        #expect(FetchTarget.githubKeys(user: "lbloom").buttonTitle == "Check github.com for this SSH key")
        #expect(FetchTarget.githubGPG(user: "lbloom").buttonTitle == "Check github.com for this GPG key")
        #expect(FetchTarget.keysOpenPGP(fingerprint: []).buttonTitle == "Fetch key from keys.openpgp.org")
        #expect(FetchTarget.mastodonLookup(user: "bloom", instance: "merveilles.town").buttonTitle
                == "Check merveilles.town for a verified link")
        #expect(FetchTarget.wkdDirect(local: "bloom", domain: "example.ie").buttonTitle
                == "Fetch key from example.ie")
    }

    /// Where has no hand-off button:    /// Where has no hand-off button: opening the tab is what fetches
    /// Apple's tiles, and the row says exactly that.
    @Test func mapsRowDescribesTheTileLoad() {
        #expect(TrustFacts.maps.host == "Apple Maps")
        #expect(TrustFacts.maps.when.contains("Where tab"))
    }

    /// Where opens a map, which loads Apple's tiles; there is no hand-off
    /// to the Maps app, so the row must not describe one.
    @Test func mapsDescribesTileLoadingOnWhere() {
        #expect(TrustFacts.maps.when.contains("Where"))
        #expect(TrustFacts.maps.when.contains("tiles"))
        #expect(!TrustFacts.maps.when.contains("Maps opens"))
    }
}
