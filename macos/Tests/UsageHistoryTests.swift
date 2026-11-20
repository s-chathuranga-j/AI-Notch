import XCTest
import SwiftUI
@testable import AINotch

final class UsageHistoryTests: XCTestCase {
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private var t0: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
    }

    private func snapshot(_ percent: Double, id: String = "c",
                          status: ProviderStatus = .ok) -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: id, glyph: .claude, fidelity: .official,
                         status: status,
                         windows: [LimitWindow(id: "session", label: "Session",
                                               usedFraction: percent / 100)])
    }

    private func samples(_ pairs: [(TimeInterval, Double)]) -> [UsageSample] {
        pairs.map { UsageSample(at: t0.addingTimeInterval($0.0), percent: $0.1) }
    }

    private func percents(_ history: UsageHistory, id: String = "c") -> [Double] {
        history.samples(providerID: id, windowID: "session").map { ($0.percent * 1000).rounded() / 1000 }
    }

    func testThinsReadingsWithTrueTimestampsAndKeepsDrops() {
        var history = UsageHistory()
        for m in [0.0, 1, 2, 3, 4, 6] {
            history.add(snapshot(10 + m), now: t0.addingTimeInterval(m * minute))
        }
        XCTAssertEqual(percents(history), [10, 14, 16])
        XCTAssertEqual(history.samples(providerID: "c", windowID: "session").map { $0.at.timeIntervalSince(t0) },
                       [0, 4 * minute, 6 * minute])

        history.add(snapshot(2), now: t0.addingTimeInterval(7 * minute))
        XCTAssertEqual(percents(history).last, 2)
        XCTAssertEqual(percents(history).count, 4, "a drop is a new sample")
    }

    func testAReadingIsStampedWhenItWasMeasuredAndNotRecordedTwice() {
        var history = UsageHistory()
        var reading = snapshot(40)
        reading.observedAt = t0
        history.add(reading, now: t0.addingTimeInterval(2 * minute))
        XCTAssertFalse(history.add(reading, now: t0.addingTimeInterval(9 * minute)),
                       "the same reading, re-published later, is not a new sample")
        XCTAssertEqual(history.samples(providerID: "c", windowID: "session").map(\.at), [t0])
    }

    func testIgnoresStaleReadingsPrunesForgetsAndRoundTrips() throws {
        var history = UsageHistory()
        XCTAssertFalse(history.add(snapshot(50, status: .stale(since: t0)), now: t0))
        history.add(snapshot(10), now: t0)
        history.add(snapshot(20), now: t0.addingTimeInterval(9 * day))
        XCTAssertEqual(percents(history), [20])

        let data = try JSONEncoder().encode(history)
        var copy = try JSONDecoder().decode(UsageHistory.self, from: data)
        XCTAssertEqual(copy, history)
        XCTAssertTrue(copy.forget(providerID: "c"))
        XCTAssertEqual(copy.samples(providerID: "c", windowID: "session"), [])

        let damaged = Data(#"{"series":{"bad":"x","ok":[[1,2],["a",3]]}}"#.utf8)
        let lenient = try JSONDecoder().decode(UsageHistory.self, from: damaged)
        XCTAssertEqual(lenient.series["ok"]?.map(\.percent), [2])
        XCTAssertNil(lenient.series["bad"])
    }

    func testTheFileHoldsOnlyPercentagesAndTimes() throws {
        var history = UsageHistory()
        history.add(snapshot(42, id: "claude-work"), now: t0)
        let json = String(decoding: try JSONEncoder().encode(history), as: UTF8.self)
        XCTAssertFalse(json.contains("Session"), "a label is not needed to forecast")
        XCTAssertTrue(json.contains("\"version\":1"))
    }

    func testTheHistoryFileRoundTrips() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = UsageHistoryFile(url: url)
        XCTAssertEqual(file.load(), UsageHistory())
        var history = UsageHistory()
        history.add(snapshot(30), now: Date(timeIntervalSince1970: 1_700_000_000))
        file.save(history)
        XCTAssertEqual(file.load(), history)
    }

    func testTheForecastExtendsTheRecentPaceToFull() throws {
        // One point a minute: 60% at +20 min reaches 100% at +60 min, before a
        // reset at +3 h.
        let s = samples([0, 10, 20].map { ($0 * minute, 40 + $0) })
        let now = t0.addingTimeInterval(20 * minute)
        let f = try XCTUnwrap(UsageInsights.forecast(s, now: now, resetsAt: t0.addingTimeInterval(3 * hour)))
        XCTAssertEqual(f.eta.timeIntervalSince(t0), 60 * minute, accuracy: 1)
        XCTAssertEqual(f.beforeReset, true)
        XCTAssertEqual(f.perHour, 60)
        XCTAssertEqual(UsageInsights.forecast(s, now: now, resetsAt: t0.addingTimeInterval(30 * minute))?.beforeReset,
                       false)
        XCTAssertNotNil(UsageInsights.forecast(s, now: now, resetsAt: nil))
        XCTAssertNil(UsageInsights.forecast(s, now: now, resetsAt: nil)?.beforeReset)
    }

    func testNoForecastWithoutARealRecentRisingPace() {
        XCTAssertNil(UsageInsights.forecast(samples([(0, 40), (5 * minute, 50)]),
                                            now: t0.addingTimeInterval(5 * minute)), "under 15 minutes")
        XCTAssertNil(UsageInsights.forecast(samples([(0, 40), (20 * minute, 40)]),
                                            now: t0.addingTimeInterval(20 * minute)), "flat")
        XCTAssertNil(UsageInsights.forecast(samples([(0, 40), (20 * minute, 60)]),
                                            now: t0.addingTimeInterval(2 * hour)), "last reading too old")
        XCTAssertNil(UsageInsights.forecast(samples([(0, 40), (20 * minute, 40.2)]),
                                            now: t0.addingTimeInterval(20 * minute)), "beyond two days")
    }

    func testTheForecastOnlyUsesSamplesSinceTheLastReset() throws {
        let s = samples([(0, 90), (10 * minute, 95), (20 * minute, 5), (30 * minute, 15), (40 * minute, 25)])
        let f = try XCTUnwrap(UsageInsights.forecast(s, now: t0.addingTimeInterval(40 * minute)))
        XCTAssertEqual(f.eta.timeIntervalSince(t0), 40 * minute + 75 * minute, accuracy: 1)
    }

    func testDailyPeaksCoverSevenLocalDaysWithGapsLeftEmpty() {
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: t0)!
        let s = [UsageSample(at: morning, percent: 30),
                 UsageSample(at: morning.addingTimeInterval(hour), percent: 55),
                 UsageSample(at: morning.addingTimeInterval(-2 * day), percent: 80)]
        let peaks = UsageInsights.dailyPeaks(s, now: t0, calendar: calendar)
        XCTAssertEqual(peaks.count, 7)
        XCTAssertEqual(peaks.last?.peak, 55)
        XCTAssertEqual(peaks[4].peak, 80)
        XCTAssertNil(peaks[5].peak)
        XCTAssertEqual(peaks.last?.day, calendar.startOfDay(for: t0))
    }

    func testInsightsNeedTwoDaysForPeaksAndARisingPaceForAForecast() {
        var history = UsageHistory()
        history.add(snapshot(70), now: t0.addingTimeInterval(-day))
        var today = UsageHistory()
        // Steady climb over the last 30 minutes.
        for m in stride(from: 0.0, through: 30, by: 6) {
            history.add(snapshot(50 + m), now: t0.addingTimeInterval(m * minute))
            today.add(snapshot(50 + m), now: t0.addingTimeInterval(m * minute))
        }
        let now = t0.addingTimeInterval(30 * minute)
        let insights = ProviderInsights.make(for: snapshot(80), history: today,
                                             now: now, calendar: calendar)
        XCTAssertNotNil(insights?.forecasts["session"])
        XCTAssertNil(insights?.peaks, "one day is not a trend")

        let withYesterday = ProviderInsights.make(for: snapshot(80), history: history,
                                                  now: now, calendar: calendar)
        XCTAssertEqual(withYesterday?.peaks?.count, 7)
        XCTAssertEqual(withYesterday?.peaksLabel, "Session")
        XCTAssertNotNil(withYesterday?.forecasts["session"], "a drop from yesterday is a reset, not noise")
        XCTAssertNil(ProviderInsights.make(for: snapshot(80, status: .stale(since: t0)),
                                           history: history, now: now, calendar: calendar))
    }

    func testForecastCopy() {
        let now = t0
        let soon = UsageForecast(eta: now.addingTimeInterval(30), beforeReset: true, perHour: 50)
        XCTAssertEqual(ForecastCopy.text(for: soon, now: now, calendar: calendar),
                       "At this pace: out any minute, before reset")
        let later = UsageForecast(eta: now.addingTimeInterval(hour), beforeReset: nil, perHour: 5)
        XCTAssertTrue(ForecastCopy.text(for: later, now: now, calendar: calendar)
            .hasPrefix("At this pace: out ~"))
    }
}

/// The forecasts and the chart are drawn only while the card still fits the
/// panel's budget, and every part of the app agrees on the height.
final class TooltipInsightLayoutTests: XCTestCase {
    private func snapshot(windows: Int) -> ProviderSnapshot {
        ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                         fidelity: .official, status: .ok,
                         windows: (0..<windows).map {
                             LimitWindow(id: "w\($0)", label: "W\($0)", usedFraction: 0.6)
                         })
    }

    private func insights(windows: Int, peaks: Bool) -> ProviderInsights {
        var i = ProviderInsights()
        for n in 0..<windows {
            i.forecasts["w\(n)"] = UsageForecast(eta: Date().addingTimeInterval(1800),
                                                 beforeReset: true, perHour: 20)
        }
        if peaks {
            i.peaks = (0..<7).map { DailyPeak(day: Date(), peak: Double($0 * 10)) }
            i.peaksLabel = "W0"
        }
        return i
    }

    func testAFewWindowsShowEverything() {
        let content = NotchLayout.cardContent(for: snapshot(windows: 2),
                                              insights: insights(windows: 2, peaks: true),
                                              sessionCount: 0, now: Date())
        XCTAssertEqual(content.forecastIDs, ["w0", "w1"])
        XCTAssertTrue(content.showsPeaks)
        XCTAssertEqual(content.height,
                       NotchLayout.cardHeight(windowCount: 2) + 2 * NotchLayout.forecastLineHeight
                           + NotchLayout.peaksChartHeight, accuracy: 0.01)
    }

    func testNoInsightsMeansTheShippedHeight() {
        let content = NotchLayout.cardContent(for: snapshot(windows: 2), insights: nil,
                                              sessionCount: 1, now: Date())
        XCTAssertEqual(content.height, NotchLayout.cardHeight(windowCount: 2, sessionCount: 1))
        XCTAssertFalse(content.showsPeaks)
    }

    func testTheExtrasNeverPushACardPastItsBudget() {
        for cap in 0...NotchLayout.sessionCeiling {
            let budget = NotchLayout.maxCardHeight(sessionCap: cap)
            for windows in 0...NotchLayout.maxWindowCount {
                for sessions in [0, 1, cap, cap + 3] {
                    let content = NotchLayout.cardContent(
                        for: snapshot(windows: windows),
                        insights: insights(windows: windows, peaks: true),
                        sessionCount: sessions, sessionCap: cap, now: Date())
                    XCTAssertLessThanOrEqual(content.height, budget,
                                             "cap \(cap), \(windows) windows, \(sessions) sessions")
                }
            }
        }
    }

    func testTheChartGoesBeforeTheForecasts() {
        let cap = NotchLayout.defaultSessionCap
        let content = NotchLayout.cardContent(for: snapshot(windows: 4),
                                              insights: insights(windows: 4, peaks: true),
                                              sessionCount: cap + 1, sessionCap: cap, now: Date())
        XCTAssertFalse(content.showsPeaks, "a full card has no room for the chart")
        if !content.forecastIDs.isEmpty {
            XCTAssertEqual(content.forecastIDs.count, 4)
        }
    }

    @MainActor func testATooltipWithInsightsRendersAtItsBudgetedHeight() throws {
        let s = snapshot(windows: 2)
        let i = insights(windows: 2, peaks: true)
        let height = NotchLayout.cardContent(for: s, insights: i, sessionCount: 0, now: Date()).height
        let view = TooltipCard(snapshot: s, now: Date(), insights: i)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.height, height, accuracy: 1)
    }
}
