import Foundation

/// Provider requests neither persist responses/cookies nor follow redirects.
/// A provider URL change must be reviewed instead of forwarding credentials.
class ProviderHTTPDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum ProviderHTTP {
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    static func session(delegate: ProviderHTTPDelegate = ProviderHTTPDelegate()) -> URLSession {
        URLSession(configuration: configuration(), delegate: delegate, delegateQueue: nil)
    }

    static func permits(_ url: URL?, hosts: Set<String>) -> Bool {
        guard let url, url.scheme == "https", let host = url.host,
              hosts.contains(host), url.user == nil, url.password == nil else { return false }
        return hosts == ["127.0.0.1"] || url.port == nil || url.port == 443
    }

    static func data(for request: URLRequest, using session: URLSession,
                     hosts: Set<String>) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard permits(request.url, hosts: hosts) else { throw URLError(.unsupportedURL) }
        let result = try await session.data(for: request)
        try Task.checkCancellation()
        guard permits(result.1.url, hosts: hosts) else { throw URLError(.unsupportedURL) }
        return result
    }
}
