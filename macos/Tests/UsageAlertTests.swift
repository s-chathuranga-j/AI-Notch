import XCTest
@testable import AINotch

final class UsageAlertTests: XCTestCase {
    private func snapshot(_ id: String, session: Double?, weekly: Double? = 0.1,
                          status: ProviderStatus = .ok) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id, displayName: id, glyph: .claude, fidelity: .official, status: status,
            windows: [
                LimitWindow(id: "session", label: "Session", usedFraction: session),
                LimitWindow(id: "weekly", label: "Weekly", usedFraction: weekly),
            ]
        )
    }

    func testAnnouncesOnceWhenALimitReachesNinetyPercent() {
        var tracker = UsageAlertTracker()
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.89)]), [])
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.90)]), ["claude"])
        // Still high on the next refresh: not announced again.
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.95)]), [])
    }

    func testReArmsAfterTheWindowResets() {
        var tracker = UsageAlertTracker()
        _ = tracker.newAlerts(in: [snapshot("claude", session: 0.92)])
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.05)]), [])
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.91)]), ["claude"])
    }

    func testAnyWindowCountsAndEachProviderIsNamedOnce() {
        var tracker = UsageAlertTracker()
        let alerts = tracker.newAlerts(in: [
            snapshot("claude", session: 0.95, weekly: 0.97),
            snapshot("codex", session: 0.2, weekly: 0.93),
        ])
        XCTAssertEqual(alerts, ["claude", "codex"])
    }

    func testStaleReadingsNeitherAlertNorReArm() {
        var tracker = UsageAlertTracker()
        let stale = ProviderStatus.stale(since: Date())
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.99, status: stale)]), [])
        _ = tracker.newAlerts(in: [snapshot("claude", session: 0.95)])
        // A stale low reading is history, not a reset.
        _ = tracker.newAlerts(in: [snapshot("claude", session: 0.01, status: stale)])
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.96)]), [])
    }

    func testAlertDurationIsClamped() {
        XCTAssertEqual(Preferences.clampAlertSeconds(0), Preferences.alertSecondsRange.lowerBound)
        XCTAssertEqual(Preferences.clampAlertSeconds(10), 10)
        XCTAssertEqual(Preferences.clampAlertSeconds(999), Preferences.alertSecondsRange.upperBound)
    }
}
