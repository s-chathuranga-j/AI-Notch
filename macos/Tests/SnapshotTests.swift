import XCTest
@testable import AINotch

final class SnapshotTests: XCTestCase {
    private func window(_ id: String, _ used: Double) -> LimitWindow {
        LimitWindow(id: id, label: id, usedFraction: used, resetsAt: Date())
    }

    private func snapshot(_ windows: [LimitWindow], fidelity: Fidelity = .derived) -> ProviderSnapshot {
        ProviderSnapshot(id: "p", displayName: "P", glyph: .claude,
                         fidelity: fidelity, status: .ok, windows: windows)
    }

    func testStaleFullUsageIsHistoryNotACurrentFullRing() {
        var stale = snapshot([window("session", 1)])
        stale.status = .stale(since: Date().addingTimeInterval(-86400))
        XCTAssertEqual(stale.headlineText, "Stale")
        XCTAssertNil(stale.ringFraction)
        XCTAssertEqual(stale.usedFraction, 1)
        XCTAssertTrue(stale.statusMessage!.contains("Current usage is unknown"))
        XCTAssertTrue(stale.statusMessage!.contains("Last reading: 100%"))
    }

    func testAccessDeniedWithoutHistoryHasAnActionInsteadOfAPercentage() {
        var denied = snapshot([])
        denied.status = .accessDenied
        XCTAssertEqual(denied.headlineText, "Access")
        XCTAssertNil(denied.ringFraction)
        XCTAssertTrue(denied.statusMessage!.contains("Allow access"))
        XCTAssertFalse(denied.statusMessage!.contains("Last reading"))
    }

    func testHeadlineIsThePrimaryWindow() {
        let s = snapshot([window("session", 0.73), window("all", 0.07)])
        XCTAssertEqual(s.headline?.id, "session")
        XCTAssertEqual(s.usedFraction ?? -1, 0.73, accuracy: 0.0001)
    }

    /// The headline stays on the session even when another window is higher.
    /// Picking the highest made the ring mean "session" one minute and "weekly"
    /// the next, which reads as the number being wrong — and disagrees with
    /// Claude's own panel, which always leads with the session.
    func testHeadlineDoesNotJumpToAHigherWindow() {
        let s = snapshot([window("session", 0.22), window("weekly_all", 0.24)])
        XCTAssertEqual(s.headline?.id, "session")
        XCTAssertEqual(s.usedFraction ?? -1, 0.22, accuracy: 0.0001)
    }

    /// The ring and the tooltip's top row are the same window, always.
    func testHeadlineMatchesTheFirstRowShown() {
        let s = snapshot([window("session", 0.05), window("weekly_all", 0.9)])
        XCTAssertEqual(s.headline?.id, s.windows.first?.id)
    }

    /// No windows is not "nothing used" — it is "nothing known", and the cell
    /// prints a dash rather than a confident zero.
    func testNoWindowsReadsAsNoReading() {
        XCTAssertNil(snapshot([]).usedFraction)
        XCTAssertEqual(snapshot([]).headlineText, "—")
        XCTAssertFalse(snapshot([]).hasReading)
    }

    /// A provider that reports only what is left gets a count, not a percentage.
    func testCountOnlyWindowsPrintTheCount() {
        let s = snapshot([LimitWindow(id: "remaining_pro", label: "Pro searches", remaining: 2)])
        XCTAssertNil(s.usedFraction)
        XCTAssertNil(s.ringFraction)
        XCTAssertEqual(s.headlineText, "2")
    }

    func testOnlyOfficialNumbersAreShownUnqualified() {
        XCTAssertEqual(Fidelity.official.qualifier, "")
        XCTAssertEqual(Fidelity.derived.qualifier, "~")
        XCTAssertEqual(Fidelity.manual.qualifier, "~")
    }
}
