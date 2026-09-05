import Foundation

/// The only things the app will ever fetch, each from a tapped button that
/// names `host`. `ExplicitFetch` accepts nothing else.
nonisolated enum FetchTarget: Equatable, Sendable {
    case wkdAdvanced(local: String, domain: String)
    case wkdDirect(local: String, domain: String)
    case keysOpenPGP(fingerprint: [UInt8])
    case githubKeys(user: String)
    case githubGPG(user: String)
    case mastodonLookup(user: String, instance: String)

    nonisolated enum Kind: CaseIterable, Sendable {
        case wkdAdvanced, wkdDirect, keysOpenPGP, githubKeys, githubGPG, mastodonLookup
    }

    var kind: Kind {
        switch self {
        case .wkdAdvanced: return .wkdAdvanced
        case .wkdDirect: return .wkdDirect
        case .keysOpenPGP: return .keysOpenPGP
        case .githubKeys: return .githubKeys
        case .githubGPG: return .githubGPG
        case .mastodonLookup: return .mastodonLookup
        }
    }

    /// The button label.
    var host: String {
        switch self {
        case .wkdAdvanced(_, let domain): return "openpgpkey." + domain.lowercased()
        case .wkdDirect(_, let domain): return domain.lowercased()
        case .keysOpenPGP: return "keys.openpgp.org"
        case .githubKeys, .githubGPG: return "github.com"
        case .mastodonLookup(_, let instance): return instance.lowercased()
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        switch self {
        case .wkdAdvanced(let local, let domain):
            components.path = "/.well-known/openpgpkey/" + domain.lowercased() + "/hu/" + OpenPGP.wkdHash(local: local)
            components.queryItems = [URLQueryItem(name: "l", value: local)]
        case .wkdDirect(let local, _):
            components.path = "/.well-known/openpgpkey/hu/" + OpenPGP.wkdHash(local: local)
            components.queryItems = [URLQueryItem(name: "l", value: local)]
        case .keysOpenPGP(let fingerprint):
            components.path = "/vks/v1/by-fingerprint/" + Hex.string(fingerprint).uppercased()
        case .githubKeys(let user):
            components.path = "/" + user + ".keys"
        case .githubGPG(let user):
            components.path = "/" + user + ".gpg"
        case .mastodonLookup(let user, let instance):
            components.path = "/api/v1/accounts/lookup"
            components.percentEncodedQuery = "acct=" + FetchTarget.encoded(user) + "%40" + FetchTarget.encoded(instance)
        }
        return components.url ?? FetchTarget.unusable
    }

    /// Returned only if a validated stored form somehow makes no URL; a
    /// file URL, which `ExplicitFetch` refuses.
    static let unusable = URL(fileURLWithPath: "/dev/null")

    /// RFC 3986 unreserved characters kept, everything else percent-encoded.
    private static func encoded(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
