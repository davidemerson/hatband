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
}
