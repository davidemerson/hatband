import Foundation

/// Every way bytes leave the phone, for the trust page: one row per
/// `FetchTarget.Kind`, then Safari for a tapped link and Apple's map
/// tiles when the Where tab is chosen. Each follows a tap, and the row
/// names the host.
nonisolated enum TrustFacts {
    nonisolated struct Egress: Equatable, Sendable {
        let host: String
        let when: String
    }

    static let egress: [Egress] = FetchTarget.Kind.allCases.map { egress(for: $0) } + [safari, maps]

    static let safari = Egress(
        host: "Safari",
        when: "You tap a link on someone's card. Safari opens it; Hatband itself fetches nothing.")

    static let maps = Egress(
        host: "Apple Maps",
        when: "You tap the Where tab. The map asks Apple for tiles around the coarse positions Hatband kept, nothing finer; the timeline under it needs nothing from anywhere.")

    static func egress(for kind: FetchTarget.Kind) -> Egress {
        switch kind {
        case .wkdAdvanced:
            return Egress(
                host: "openpgpkey.<their email domain>",
                when: "You tap Fetch key (WKD) on a person whose card carries a GPG fingerprint and an email address.")
        case .wkdDirect:
            return Egress(
                host: "<their email domain>",
                when: "The same tap, when the openpgpkey subdomain has no key to offer.")
        case .keysOpenPGP:
            return Egress(
                host: "keys.openpgp.org",
                when: "You tap Fetch key from keys.openpgp.org on a person with a GPG fingerprint.")
        case .githubKeys:
            return Egress(
                host: "github.com",
                when: "You tap Verify on a GitHub username whose card carries an SSH key.")
        case .githubGPG:
            return Egress(
                host: "github.com",
                when: "You tap Fetch key from GitHub on a person with a GitHub username and a GPG fingerprint.")
        case .mastodonLookup:
            return Egress(
                host: "<their Mastodon instance>",
                when: "You tap Verify on a Mastodon address, to ask the instance whether it vouches for the website on the card.")
        }
    }
}
