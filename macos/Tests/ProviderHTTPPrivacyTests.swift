import XCTest
@testable import AINotch

final class ProviderHTTPPrivacyTests: XCTestCase {
    func testRequestsHaveNoPersistentResponseCookieOrCredentialStore() {
        let config = ProviderHTTP.configuration()
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testRedirectsAreRejectedEvenToTheSameHost() {
        let delegate = ProviderHTTPDelegate()
        let session = ProviderHTTP.session(delegate: delegate)
        defer { session.invalidateAndCancel() }
        let origin = URL(string: "https://cursor.com/api/usage-summary")!
        let task = session.dataTask(with: origin)
        for target in ["https://example.invalid", "https://cursor.com/other", "http://cursor.com", "https://127.0.0.1"] {
            let response = HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!
            let completed = expectation(description: target)
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                newRequest: URLRequest(url: URL(string: target)!)) { redirected in
                XCTAssertNil(redirected)
                completed.fulfill()
            }
            wait(for: [completed], timeout: 1)
        }
        task.cancel()
    }

    func testOnlyExactHTTPSProviderDestinationsAreAllowed() {
        let hosts: Set<String> = ["cursor.com"]
        XCTAssertTrue(ProviderHTTP.permits(URL(string: "https://cursor.com/api/usage-summary"), hosts: hosts))
        for url in ["http://cursor.com", "https://cursor.com.evil.invalid", "https://evilcursor.com", "https://user:secret@cursor.com", "https://cursor.com:444", "https://127.0.0.1"] {
            XCTAssertFalse(ProviderHTTP.permits(URL(string: url), hosts: hosts), url)
        }
        XCTAssertTrue(ProviderHTTP.permits(URL(string: "https://127.0.0.1:8080/quota"), hosts: ["127.0.0.1"]))
    }
}
