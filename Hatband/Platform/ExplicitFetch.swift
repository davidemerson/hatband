import Foundation

/// The only `URLSession`. One tapped button, one host named on it, one
/// request: ephemeral, no cookies, no cache, 15 seconds, TLS 1.2 or later,
/// redirects only within the same https host, 256 KB.
nonisolated enum ExplicitFetch {
    nonisolated enum Error: Swift.Error, Equatable {
        case notHTTPS
        case noResponse
        case status(Int)
        case tooLarge
    }

    static let timeout: TimeInterval = 15

    static func get(_ target: FetchTarget, maxBytes: Int = 262_144) async throws -> Data {
        let url = target.url
        guard url.scheme?.lowercased() == "https" else { throw Error.notHTTPS }
        let session = URLSession(configuration: configuration(), delegate: RedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(accept(for: target), forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.noResponse }
        guard http.statusCode == 200 else { throw Error.status(http.statusCode) }
        guard http.expectedContentLength <= Int64(maxBytes) else { throw Error.tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= maxBytes else { throw Error.tooLarge }
        }
        return data
    }

    /// Same host, both https. Pure.
    static func allowsRedirect(from: URL, to: URL) -> Bool {
        guard from.scheme?.lowercased() == "https", to.scheme?.lowercased() == "https",
              let source = from.host(percentEncoded: false)?.lowercased(),
              let destination = to.host(percentEncoded: false)?.lowercased()
        else { return false }
        return source == destination
    }

    // MARK: - Private

    private static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.waitsForConnectivity = false
        return configuration
    }

    /// WKD answers binary, the key servers armored text, Mastodon JSON.
    private static func accept(for target: FetchTarget) -> String {
        switch target.kind {
        case .wkdAdvanced, .wkdDirect: return "application/octet-stream"
        case .keysOpenPGP, .githubGPG: return "application/pgp-keys, text/plain"
        case .githubKeys: return "text/plain"
        case .mastodonLookup: return "application/json"
        }
    }
}

/// Refuses every redirect `allowsRedirect` does not allow; the task then
/// ends on the redirect response, which is not 200.
nonisolated final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let from = response.url, let to = request.url, ExplicitFetch.allowsRedirect(from: from, to: to) else {
            return nil
        }
        return request
    }
}
