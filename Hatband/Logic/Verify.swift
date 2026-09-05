import Foundation
import HatbandCore

/// Checks over what a tapped fetch brought back. Each answers yes or no;
/// nothing here opens, stores or follows anything.
nonisolated enum Verify {
    /// Whether one line of a GitHub `.keys` page is the card's SSH key: the
    /// same kind and the same inline bytes, or for RSA the same fingerprint.
    static func githubKeys(_ text: String, matches field: SSHKeyField) -> Bool {
        for line in text.split(whereSeparator: { $0.isNewline }) {
            guard let key = try? SSHPublicKey(line: String(line)) else { continue }
            if key.kind.rawValue == field.kind, key.storedBytes == field.bytes {
                return true
            }
        }
        return false
    }

    /// Whether a binary OpenPGP certificate hashes to the card's fingerprint.
    static func certificate(_ bytes: [UInt8], matches fingerprint: [UInt8]) -> Bool {
        guard let hashed = OpenPGP.fingerprint(ofCertificate: bytes) else { return false }
        return hashed == fingerprint
    }

    /// Whether a Mastodon account lookup lists the website among its
    /// profile fields with a `verified_at` timestamp: the instance itself
    /// fetched the page and found the `rel="me"` link back.
    static func mastodonVerified(json: Data, website: String) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let fields = root["fields"] as? [[String: Any]]
        else { return false }
        let wanted = normalizedAddress(website)
        guard !wanted.isEmpty else { return false }
        for field in fields {
            guard let verified = field["verified_at"] as? String, !verified.isEmpty,
                  let value = field["value"] as? String
            else { continue }
            for href in hrefs(in: value) where normalizedAddress(href) == wanted {
                return true
            }
        }
        return false
    }

    /// Scheme and trailing slash dropped, ASCII case folded.
    static func normalizedAddress(_ url: String) -> String {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }

    /// Every `href="…"` value in a fragment of HTML.
    private static func hrefs(in html: String) -> [String] {
        var out: [String] = []
        for piece in html.components(separatedBy: "href=\"").dropFirst() {
            if let end = piece.firstIndex(of: "\"") {
                out.append(String(piece[..<end]))
            }
        }
        return out
    }
}
