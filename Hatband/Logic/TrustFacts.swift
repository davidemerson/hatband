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
        let host = placeholderHost(for: kind)
        return Egress(host: host, when: "You tap " + kind.title(host: host) + " " + occasion(for: kind))
    }

    /// What the row can say about a host it cannot know: the real one is the
    /// person's email domain, or their instance.
    static func placeholderHost(for kind: FetchTarget.Kind) -> String {
        switch kind {
        case .wkdAdvanced: return "openpgpkey.<their email domain>"
        case .wkdDirect: return "<their email domain>"
        case .keysOpenPGP: return "keys.openpgp.org"
        case .githubKeys, .githubGPG: return "github.com"
        case .mastodonLookup: return "<their Mastodon instance>"
        }
    }

    /// Where the button is and what has to be on the card for it to appear.
    private static func occasion(for kind: FetchTarget.Kind) -> String {
        switch kind {
        case .wkdAdvanced, .wkdDirect:
            return "on a person whose card carries a GPG fingerprint and an email address. The two are separate buttons; neither falls back to the other."
        case .keysOpenPGP:
            return "on a person whose card carries a GPG fingerprint."
        case .githubKeys:
            return "on a person whose card carries a GitHub username and an SSH key, or beside your own GitHub username while you edit your profile."
        case .githubGPG:
            return "on a person whose card carries a GitHub username and a GPG fingerprint."
        case .mastodonLookup:
            return "on a person whose card carries a Mastodon address and a website, or beside your own address while you edit your profile."
        }
    }
}
