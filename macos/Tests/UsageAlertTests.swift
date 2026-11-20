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

    private func crossed(_ tracker: inout UsageAlertTracker, _ snapshots: [ProviderSnapshot],
                         _ levels: Set<Int> = [90]) -> [Int] {
        tracker.update(snapshots, thresholds: levels).crossed.map(\.threshold)
    }

    func testEachChosenThresholdAlertsAsItIsCrossed() {
        var tracker = UsageAlertTracker()
        let levels: Set<Int> = [75, 90, 100]
        XCTAssertEqual(crossed(&tracker, [snapshot("c", session: 0.76)], levels), [75])
        XCTAssertEqual(crossed(&tracker, [snapshot("c", session: 0.80)], levels), [])
        // Jumping past two reports the highest.
        XCTAssertEqual(crossed(&tracker, [snapshot("c", session: 1.0)], levels), [100])
    }

    func testAResetIsReportedOnceAndReArms() {
        var tracker = UsageAlertTracker()
        _ = tracker.update([snapshot("claude", session: 0.93)])
        let reset = tracker.update([snapshot("claude", session: 0.04)])
        XCTAssertEqual(reset.crossed, [])
        XCTAssertEqual(reset.recovered.map(\.label), ["Session"])
        XCTAssertEqual(tracker.update([snapshot("claude", session: 0.03)]).recovered, [], "only once")
        XCTAssertEqual(crossed(&tracker, [snapshot("claude", session: 0.91)]), [90])
    }

    func testAWindowThatNeverAlertedDoesNotAnnounceAReset() {
        var tracker = UsageAlertTracker()
        _ = tracker.update([snapshot("c", session: 0.6)])
        XCTAssertEqual(tracker.update([snapshot("c", session: 0.02)]).recovered, [])
    }

    func testEasingBelowTheThresholdIsNotAReset() {
        var tracker = UsageAlertTracker()
        _ = tracker.update([snapshot("c", session: 0.92)])
        XCTAssertEqual(tracker.update([snapshot("c", session: 0.85)]).recovered, [])
    }

    func testProvidersAreTrackedIndependentlyAndCanBeForgotten() {
        var tracker = UsageAlertTracker()
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.95)]), ["claude"])
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude-work", session: 0.95)]), ["claude-work"])
        tracker.forget(providerID: "claude")
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude", session: 0.95)]), ["claude"])
        XCTAssertEqual(tracker.newAlerts(in: [snapshot("claude-work", session: 0.95)]), [])
    }

    func testAPaceWarningFiresOnceWhenTheWindowRunsOutBeforeTheResetWithinTheHour() {
        var tracker = UsageAlertTracker()
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let soon = UsageForecast(eta: now.addingTimeInterval(30 * 60), beforeReset: true, perHour: 20)
        func pace(_ used: Double, _ forecast: UsageForecast) -> Bool {
            tracker.pace(providerID: "c", windowID: "session", usedFraction: used,
                         forecast: forecast, now: now)
        }
        XCTAssertFalse(pace(0.4, soon), "too little used yet")
        XCTAssertFalse(pace(0.6, UsageForecast(eta: soon.eta, beforeReset: false, perHour: 20)))
        XCTAssertFalse(pace(0.6, UsageForecast(eta: now.addingTimeInterval(3 * 3600),
                                               beforeReset: true, perHour: 20)))
        XCTAssertTrue(pace(0.6, soon))
        XCTAssertFalse(pace(0.7, soon))
        _ = tracker.update([snapshot("c", session: 0.05)])
        XCTAssertTrue(pace(0.6, soon), "re-armed after a reset")
    }

    func testNoticesPreferALimitThenPaceThenReset() {
        var tracker = UsageAlertTracker()
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let soon = UsageForecast(eta: now.addingTimeInterval(20 * 60), beforeReset: true, perHour: 30)
        let forecasts = ["claude": ["session": soon]]

        let limit = tracker.notices(for: [snapshot("claude", session: 0.92)],
                                    paceAlerts: true, forecasts: forecasts, now: now)
        XCTAssertEqual(limit.map(\.kind), [.limit], "a crossing beats the pace")

        let reset = tracker.notices(for: [snapshot("claude", session: 0.1)],
                                    paceAlerts: true, forecasts: [:], now: now)
        XCTAssertEqual(reset.map(\.kind), [.reset])
        XCTAssertEqual(reset.first?.title, "claude is back")

        let pace = tracker.notices(for: [snapshot("claude", session: 0.6)],
                                   paceAlerts: true, forecasts: forecasts, now: now)
        XCTAssertEqual(pace.map(\.kind), [.pace])
        XCTAssertEqual(tracker.notices(for: [snapshot("claude", session: 0.62)],
                                       paceAlerts: true, forecasts: forecasts, now: now), [])

        var off = UsageAlertTracker()
        XCTAssertEqual(off.notices(for: [snapshot("claude", session: 0.6)],
                                   paceAlerts: false, forecasts: forecasts, now: now), [])
    }

    func testWhenSeveralWindowsCrossTheMostSeriousIsNamed() {
        var tracker = UsageAlertTracker()
        let notices = tracker.notices(for: [snapshot("claude", session: 0.92, weekly: 1.0)],
                                      thresholds: [90, 100], paceAlerts: false, forecasts: [:])
        XCTAssertEqual(notices.map(\.label), ["Weekly"])

        var tied = UsageAlertTracker()
        let same = tied.notices(for: [snapshot("claude", session: 0.97, weekly: 0.93)],
                                paceAlerts: false, forecasts: [:])
        XCTAssertEqual(same.map(\.label), ["Session"], "same level: the more used one")
    }

    func testThresholdsAreCleaned() {
        XCTAssertEqual(UsageAlertTracker.clean([100, 75, 42]), [75, 100])
        XCTAssertEqual(UsageAlertTracker.clean([]), [90])
    }

    func testQuietHoursIncludingOnesThatWrapMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int, _ m: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: h, minute: m))!
        }
        let night = QuietHours(isEnabled: true, start: QuietHours.minutes("22:00")!,
                               end: QuietHours.minutes("07:30")!)
        XCTAssertTrue(night.contains(at(23), calendar: calendar))
        XCTAssertTrue(night.contains(at(3), calendar: calendar))
        XCTAssertFalse(night.contains(at(7, 30), calendar: calendar))
        XCTAssertFalse(night.contains(at(12), calendar: calendar))
        XCTAssertTrue(QuietHours(isEnabled: true, start: 12 * 60, end: 13 * 60)
            .contains(at(12, 15), calendar: calendar))
        var off = night
        off.isEnabled = false
        XCTAssertFalse(off.contains(at(23), calendar: calendar))
        XCTAssertFalse(QuietHours(isEnabled: true, start: 600, end: 600).contains(at(10), calendar: calendar))
        XCTAssertNil(QuietHours.minutes("9"))
        XCTAssertNil(QuietHours.minutes("24:00"))
        XCTAssertEqual(QuietHours.minutes("9:05"), 9 * 60 + 5)
    }

    @MainActor
    func testAlertPreferencesPersistAndAreCleaned() {
        let name = "UsageAlertTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let fresh = Preferences(defaults: defaults)
        XCTAssertEqual(fresh.usageAlertThresholds, [90])
        XCTAssertTrue(fresh.paceAlertsEnabled)
        XCTAssertFalse(fresh.quietHoursEnabled)
        XCTAssertFalse(fresh.systemNotificationsEnabled)

        fresh.usageAlertThresholds = [75, 100, 13]
        fresh.quietHoursEnabled = true
        fresh.quietHoursStart = 23 * 60
        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.usageAlertThresholds, [75, 100])
        XCTAssertTrue(again.quietHours.isEnabled)
        XCTAssertEqual(again.quietHours.start, 23 * 60)
    }

    /// Alerts off, or quiet hours, do not tell the tracker — so a limit still
    /// high when they end is announced then, not lost.
    @MainActor
    func testAHeldBackLimitIsAnnouncedOnceAlertsMaySpeak() {
        let watch = UsageWatch(file: nil)
        let high = [snapshot("claude", session: 0.95)]
        XCTAssertEqual(watch.receive(high, record: false, judge: false,
                                     thresholds: [90], paceAlerts: true), [])
        XCTAssertEqual(watch.receive(high, record: false, judge: true,
                                     thresholds: [90], paceAlerts: true).map(\.kind), [.limit])
        XCTAssertEqual(watch.receive(high, record: false, judge: true,
                                     thresholds: [90], paceAlerts: true), [])
    }

    /// While muted the state follows the readings down: a reset during the
    /// mute is not announced afterwards, and a fresh crossing still is.
    func testMutedReadingsReArmWithoutAnnouncingAnything() {
        var tracker = UsageAlertTracker()
        _ = tracker.update([snapshot("c", session: 0.95)])
        let muted = tracker.update([snapshot("c", session: 0.1)], silent: true)
        XCTAssertEqual(muted, UsageAlertTracker.Result())
        XCTAssertEqual(tracker.update([snapshot("c", session: 0.1)]).recovered, [],
                       "a reset that happened while muted is old news")
        XCTAssertEqual(crossed(&tracker, [snapshot("c", session: 0.92)]), [90])

        // Climbing while muted raises nothing, so it is announced on unmute.
        var climbing = UsageAlertTracker()
        _ = climbing.update([snapshot("c", session: 0.95)], silent: true)
        XCTAssertEqual(crossed(&climbing, [snapshot("c", session: 0.95)]), [90])
    }

    func testAlertDurationIsClamped() {
        XCTAssertEqual(Preferences.clampAlertSeconds(0), Preferences.alertSecondsRange.lowerBound)
        XCTAssertEqual(Preferences.clampAlertSeconds(10), 10)
        XCTAssertEqual(Preferences.clampAlertSeconds(999), Preferences.alertSecondsRange.upperBound)
    }
}
