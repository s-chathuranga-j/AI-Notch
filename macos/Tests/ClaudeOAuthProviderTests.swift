import XCTest
import Security
@testable import AINotch

final class ClaudeKeychainPromptTests: XCTestCase {
    func testFailedSilentReadRestoresInteractionForTheNextExplicitRead() throws {
        var original: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&original), errSecSuccess)
        defer { SecKeychainSetUserInteractionAllowed(original.boolValue) }
        XCTAssertEqual(SecKeychainSetUserInteractionAllowed(true), errSecSuccess)

        XCTAssertThrowsError(try KeychainItem.withInteraction(allowed: false) {
            var allowed: DarwinBoolean = true
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertFalse(allowed.boolValue)
            throw UsageProviderError.accessDenied
        })
        try KeychainItem.withInteraction(allowed: true) {
            var allowed: DarwinBoolean = false
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertTrue(allowed.boolValue)
        }
    }
}

/// The token path of `ClaudeOAuthProvider`.
///
/// It had no tests at all — only the pure helpers (`backoff`, `retryAfter`) were
/// covered — which is how a back-off that re-stamped itself on every failed tick
/// shipped and locked the provider until the app was restarted.
///
/// Every assertion here is about one question: **after a failure, does the next
/// tick actually go and ask again?** Hence the counters. Asserting on the returned
/// error is not enough — the broken version returned exactly the right error while
/// never touching the keychain or the network.
final class ClaudeOAuthProviderTests: XCTestCase {

    override func tearDown() {
        StubEndpoint.reset([])
        super.tearDown()
    }

    /// A 401 must not stop the next tick from trying.
    ///
    /// The endpoint rejects the token and then starts answering again — a token
    /// rotated behind the app's back. This is the manual repro (a local server
    /// switched from 401 to 200) reduced to a test.
    func testA401DoesNotStopTheNextTickFromTrying() async throws {
        StubEndpoint.reset([
            .init(status: 401),                       // the tick's first attempt
            .init(status: 401),                       // its one retry on unauthorized
            .init(status: 200, body: Self.usagePayload)
        ])
        let source = CredentialSource(readable: true)
        let provider = makeProvider(source: source)

        await assertNeedsAuth(from: provider)
        XCTAssertEqual(StubEndpoint.requestCount, 2, "the retry on 401 did not happen")

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(StubEndpoint.requestCount, 3,
                       "the next tick never reached the endpoint")
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.windows.first?.id, "session")
    }

    /// A keychain read that failed must not stop the next tick from reading again.
    ///
    /// This is what happened in the field: the Mac was in dark wake, the keychain
    /// answered `-25320` ("no UI possible"), and that fell through to `needsAuth`.
    /// The credential was readable again seconds later; the provider never looked.
    func testAKeychainFailureDoesNotStopTheNextTickFromReading() async throws {
        StubEndpoint.reset([.init(status: 200, body: Self.usagePayload)])
        let source = CredentialSource(readable: false)
        let provider = makeProvider(source: source)

        await assertNeedsAuth(from: provider)
        XCTAssertEqual(source.reads, 1)
        XCTAssertEqual(StubEndpoint.requestCount, 0,
                       "it went to the network without a token")

        source.makeReadable()   // the machine woke up

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(source.reads, 2, "the next tick never went back to the keychain")
        XCTAssertEqual(snapshot.status, .ok)
    }

    /// Failing repeatedly must not become failing silently.
    ///
    /// The bug's signature was a request count frozen at two while the poll kept
    /// firing every 60 seconds. Three ticks against a rejecting endpoint have to
    /// produce three attempts, not one.
    func testItKeepsAskingWhileTheEndpointKeepsRejecting() async {
        StubEndpoint.reset(Array(repeating: .init(status: 401), count: 6))
        let provider = makeProvider(source: CredentialSource(readable: true))

        for _ in 0..<3 { await assertNeedsAuth(from: provider) }

        XCTAssertEqual(StubEndpoint.requestCount, 6,
                       "the provider stopped asking after the first failure")
    }

    // MARK: - Helpers

    func testResetShowsZeroAndEmptyResponseDoesNotReplaceIt() async throws {
        StubEndpoint.reset([
            .init(status: 200, body: Data("""
                {"five_hour":{"utilization":0,"resets_at":null}}
                """.utf8)),
            .init(status: 200, body: Data("{}".utf8))
        ])
        let provider = makeProvider(source: CredentialSource(readable: true))
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.headlineText, "0%")
        XCTAssertNil(snapshot.headline?.resetsAt)
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("An empty response must not be accepted as a fresh reading")
        } catch UsageProviderError.noUsageReading {
            // The store can retain the last real reading.
        }
    }

    @MainActor
    func testExpiredClaudeLoginExplainsHowToRecoverAndKeepsHistory() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClaudeExpiryTests.\(UUID())"))
        let archive = UsageArchive(defaults: defaults)
        let provider = ClaudeOAuthProvider(session: StubEndpoint.session(), archive: archive) {
            ClaudeCredentials(accessToken: "expired", expiresAt: .distantPast, subscriptionType: "max")
        }
        let reading = ProviderSnapshot(id: provider.id, displayName: "Claude", glyph: .claude,
                                       fidelity: .official, status: .ok,
                                       windows: [LimitWindow(id: "session", label: "Session", usedFraction: 1)])
        let fetchedAt = Date(timeIntervalSinceReferenceDate: 1000)
        archive.save([provider.id: (reading, fetchedAt)])
        let store = UsageStore(providers: [provider], archive: archive)

        await store.refresh()

        let snapshot = try XCTUnwrap(store.snapshots.first)
        XCTAssertEqual(snapshot.status.staleSince, fetchedAt)
        XCTAssertNil(snapshot.ringFraction)
        XCTAssertTrue(snapshot.statusMessage?.contains("Claude Code sign-in expired") == true)
        XCTAssertTrue(snapshot.statusMessage?.contains("Last reading: 100%") == true)
    }

    func testStatusLineSkipsDirectRefreshUntilTheReadingIsStale() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ClaudeProfile(slug: "test", configDirectory: directory)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClaudeFallbackTests.\(UUID())"))
        let provider = ClaudeOAuthProvider(profile: profile, session: StubEndpoint.session(),
                                           archive: UsageArchive(defaults: defaults), preferStatusLine: true) {
            ClaudeCredentials(accessToken: "fixture", expiresAt: .distantFuture, subscriptionType: "max")
        }
        StubEndpoint.reset([.init(status: 200, body: Self.usagePayload)])
        let collector = ClaudeStatusLineProvider(profile: profile)
        let reset = Date().addingTimeInterval(3600).timeIntervalSince1970
        let input = Data("""
        {"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":\(reset)}}}
        """.utf8)
        try collector.save(input: input)
        let local = try await provider.fetchSnapshot()
        XCTAssertEqual(local.headlineText, "12%")
        XCTAssertEqual(StubEndpoint.requestCount, 0)

        try collector.save(input: input, now: Date().addingTimeInterval(-16 * 60))
        let remote = try await provider.fetchSnapshot()
        XCTAssertEqual(remote.headlineText, "42%")
        XCTAssertEqual(StubEndpoint.requestCount, 1)
    }

    private static let usagePayload = Data("""
    {"limits":[{"kind":"session","percent":42,"resets_at":"2099-01-01T00:00:00Z"}]}
    """.utf8)

    private func makeProvider(source: CredentialSource) -> ClaudeOAuthProvider {
        // A private defaults suite per test: the archive persists the 429 back-off
        // deadline, and a leaked one would silently skip fetches in the next test.
        let name = "ClaudeOAuthProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        return ClaudeOAuthProvider(session: StubEndpoint.session(),
                                   archive: UsageArchive(defaults: defaults),
                                   loadCredentials: { try source.read() })
    }

    private func assertNeedsAuth(from provider: ClaudeOAuthProvider,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) async {
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected needsAuth, got a snapshot", file: file, line: line)
        } catch UsageProviderError.needsAuth {
            // expected
        } catch {
            XCTFail("expected needsAuth, got \(error)", file: file, line: line)
        }
    }
}

/// Stands in for the keychain, and counts reads.
///
/// "Did it go back and ask?" is the whole question, and only a counter answers it.
private final class CredentialSource: @unchecked Sendable {
    private let lock = NSLock()
    private var readable: Bool
    private var readCount = 0

    init(readable: Bool) { self.readable = readable }

    var reads: Int {
        lock.lock(); defer { lock.unlock() }
        return readCount
    }

    func makeReadable() {
        lock.lock(); readable = true; lock.unlock()
    }

    func read() throws -> ClaudeCredentials {
        lock.lock()
        readCount += 1
        let allowed = readable
        lock.unlock()

        // The shape a dark-wake or not-found read takes by the time it leaves
        // `ClaudeCredentials.read()`.
        guard allowed else { throw UsageProviderError.needsAuth }
        return ClaudeCredentials(accessToken: "token",
                                 expiresAt: .distantFuture,
                                 subscriptionType: "max")
    }
}

/// Canned answers for the usage endpoint, and a count of how many requests
/// actually arrived. The repo had no URL stubbing, which is why nothing above
/// `retryAfter(from:)` was ever tested.
private final class StubEndpoint: URLProtocol {
    struct Answer {
        let status: Int
        var body: Data = Data()
    }

    private static let lock = NSLock()
    private static var queued: [Answer] = []
    private static var served = 0

    static func reset(_ answers: [Answer]) {
        lock.lock(); queued = answers; served = 0; lock.unlock()
    }

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return served
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubEndpoint.self]
        return URLSession(configuration: configuration)
    }

    private static func next() -> Answer {
        lock.lock(); defer { lock.unlock() }
        served += 1
        // Running dry is a test bug, and a 500 says so more clearly than a crash
        // inside URLSession's callback would.
        return queued.isEmpty ? Answer(status: 500) : queued.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answer = Self.next()
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: answer.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
