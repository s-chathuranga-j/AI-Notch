import XCTest
@testable import AINotch

/// The smarter Keychain fallback: no pointless prompt for a token that must
/// have expired, a reason that says what is actually going on, and a refresh
/// the moment Claude Code moves.
final class ClaudeKeychainFallbackTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testLifetimeIsLearnedFromIssueAndExpiry() {
        XCTAssertEqual(ClaudeKeychain.lifetime(expiresAt: t0.addingTimeInterval(8 * 3600), issuedAt: t0, previous: nil),
                       8 * 3600)
    }

    func testTheLongestLifetimeSeenIsKept() {
        XCTAssertEqual(ClaudeKeychain.lifetime(expiresAt: t0.addingTimeInterval(3600), issuedAt: t0, previous: 8 * 3600),
                       8 * 3600)
    }

    func testImplausibleLifetimesAreNotBelieved() {
        XCTAssertNil(ClaudeKeychain.lifetime(expiresAt: t0.addingTimeInterval(60), issuedAt: t0, previous: nil))
        XCTAssertNil(ClaudeKeychain.lifetime(expiresAt: t0.addingTimeInterval(-3600), issuedAt: t0, previous: nil))
        XCTAssertNil(ClaudeKeychain.lifetime(expiresAt: t0.addingTimeInterval(90 * 86400), issuedAt: t0, previous: nil))
    }

    func testATokenOlderThanItsLifetimeMustHaveExpired() {
        let lifetime: TimeInterval = 8 * 3600
        XCTAssertFalse(ClaudeKeychain.mustHaveExpired(issuedAt: t0, lifetime: lifetime, now: t0.addingTimeInterval(lifetime)))
        XCTAssertTrue(ClaudeKeychain.mustHaveExpired(issuedAt: t0, lifetime: lifetime, now: t0.addingTimeInterval(lifetime + 61)))
        XCTAssertFalse(ClaudeKeychain.mustHaveExpired(issuedAt: t0, lifetime: lifetime, now: t0.addingTimeInterval(3600)))
    }

    func testOnlyAMovedSourceTriggersARefresh() {
        XCTAssertFalse(UsageStore.sourceChanged(previous: nil, current: t0), "the first look is the baseline")
        XCTAssertFalse(UsageStore.sourceChanged(previous: t0, current: t0))
        XCTAssertTrue(UsageStore.sourceChanged(previous: t0, current: t0.addingTimeInterval(1)))
    }

    func testRateLimitReasonSaysWhenItTriesAgain() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let at = ISO8601DateFormatter().date(from: "2026-11-20T10:42:00Z")!
        let reason = UsageStore.rateLimitedReason(provider: "Claude", retryAt: at, calendar: calendar)
        XCTAssertTrue(reason.hasPrefix("Claude is limiting how often usage can be read."))
        XCTAssertTrue(reason.contains("10:42"), reason)
    }

    func testExpiredTokenReasonDoesNotSendPeopleToSignIn() {
        XCTAssertFalse(UsageStore.expiredTokenReason.contains("/login"))
        XCTAssertTrue(UsageStore.expiredTokenReason.contains("no password needed"))
    }
}
