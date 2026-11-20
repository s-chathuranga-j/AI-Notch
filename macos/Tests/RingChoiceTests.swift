import XCTest
@testable import AINotch

final class RingChoiceTests: XCTestCase {
    private let snapshot = ProviderSnapshot(
        id: "claude", displayName: "Claude", glyph: .claude, fidelity: .official, status: .ok,
        windows: [
            LimitWindow(id: "session", label: "Session", usedFraction: 0.3),
            LimitWindow(id: "weekly", label: "Weekly", usedFraction: 0.8),
            LimitWindow(id: "credits", label: "Credits", remaining: 4),
        ],
        headlineID: "session"
    )

    func testTheDefaultKeepsTheProvidersHeadline() {
        XCTAssertEqual(snapshot.applying(.provider).headline?.id, "session")
    }

    func testClosestPicksTheMostUsedMeteredWindow() {
        XCTAssertEqual(snapshot.applying(.closest).headline?.id, "weekly")
    }

    func testANamedWindowIsUsedAndAMissingOneFallsBack() {
        XCTAssertEqual(snapshot.applying(.window("weekly")).usedFraction, 0.8)
        XCTAssertEqual(snapshot.applying(.window("gone")).headline?.id, "session",
                       "a window that disappeared must not blank the ring")
    }

    func testANamedWindowWithoutAReadingFallsBack() {
        XCTAssertEqual(snapshot.applying(.window("credits")).headline?.id, "session",
                       "a window with no percentage would draw an empty ring")
    }

    func testChoicesRoundTripThroughTheirStoredForm() {
        for choice in [RingChoice.provider, .closest, .window("weekly")] {
            XCTAssertEqual(RingChoice(rawValue: choice.rawValue), choice)
        }
        XCTAssertEqual(RingChoice(rawValue: nil), .provider)
        XCTAssertEqual(RingChoice(rawValue: "nonsense"), .provider)
    }

    @MainActor
    func testRingChoicesAndTheShortcutPersist() {
        let name = "RingChoiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.ringChoice(for: "claude"), .provider)
        XCTAssertEqual(preferences.peekShortcut, .controlOptionN)
        preferences.setRingChoice(.window("weekly"), for: "claude")
        preferences.peekShortcut = .off

        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.ringChoice(for: "claude"), .window("weekly"))
        XCTAssertEqual(again.peekShortcut, .off)
        again.setRingChoice(.provider, for: "claude")
        XCTAssertNil(again.ringChoices["claude"], "the default is not stored")
    }

    func testEveryShortcutButOffHasKeys() {
        for shortcut in PeekShortcut.allCases {
            XCTAssertEqual(shortcut.keys == nil, shortcut == .off, shortcut.title)
        }
    }
}
