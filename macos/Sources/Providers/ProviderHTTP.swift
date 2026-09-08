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

/// How long to wait after a 429, for the providers that poll an endpoint known
/// to throttle: a minute, doubling per consecutive limit, capped so it always
/// recovers on its own. The server's own hint is honoured only as a
/// floor-raiser — a `Retry-After` of two seconds is not a reason to poll
/// harder than the schedule already does.
enum ProviderBackoff {
    static func wait(forAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let floor: TimeInterval = 60
        let ceiling: TimeInterval = 15 * 60
        let doubled = floor * pow(2, Double(min(attempt, 4)))
        return min(ceiling, max(doubled, retryAfter ?? 0))
    }

    /// `Retry-After` is either a number of seconds or an HTTP date.
    static func retryAfter(from response: URLResponse?) -> TimeInterval? {
        guard let header = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces)
        else { return nil }

        if let seconds = TimeInterval(header) { return max(0, seconds) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}
