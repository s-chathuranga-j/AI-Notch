import Combine
import XCTest
@testable import AINotch

@MainActor
final class ActivityPrivacyTests: XCTestCase {
    private final class Monitor: AgentActivityMonitor {
        var sessions: [AgentSession] = []
        var sessionsPublisher: AnyPublisher<[AgentSession], Never> { Just(sessions).eraseToAnyPublisher() }
        var starts = 0, stops = 0
        func start() { starts += 1 }
        func stop() { stops += 1; sessions = [] }
    }

    func testSwitchesControlEachProfileIndependently() {
        let personal = Monitor(), work = Monitor()
        let controller = ActivityMonitorController(monitors: ["claude": personal, "claude-work": work])
        controller.apply(disconnected: ["claude-work"])
        XCTAssertEqual(personal.starts, 1)
        XCTAssertEqual(work.starts, 0)
        controller.apply(disconnected: ["claude"])
        XCTAssertEqual(personal.stops, 1)
        XCTAssertEqual(work.starts, 1)
        controller.apply(disconnected: ["claude"])
        XCTAssertEqual(work.starts, 1, "Repeated preferences must not create duplicate timers")
        controller.stop()
        XCTAssertEqual(work.stops, 1)
        XCTAssertTrue(controller.active.isEmpty)
    }

    func testDemoNeverStartsMonitoring() {
        let monitor = Monitor()
        let controller = ActivityMonitorController(monitors: ["claude": monitor])
        controller.apply(disconnected: [], demo: true)
        XCTAssertEqual(monitor.starts, 0)
    }

    func testFreshAccountsRequireOptInAndNewProfilesRemainOff() {
        let name = "ActivityPrivacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Preferences(defaults: defaults, providerIDs: ["claude", "cursor"])
        XCTAssertFalse(first.isConnected("claude"))
        first.setConnected(true, for: "claude")
        let next = Preferences(defaults: defaults, providerIDs: ["claude", "cursor", "claude-work"])
        XCTAssertTrue(next.isConnected("claude"))
        XCTAssertFalse(next.isConnected("cursor"))
        XCTAssertFalse(next.isConnected("claude-work"))
    }
}

@MainActor
final class PrivacyUpgradeTests: XCTestCase {
    func testUpgradeFromImplicitEnablementRequiresOneTimeOptIn() {
        let name = "PrivacyUpgrade.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "hasLaunchedBefore")
        defaults.set([String](), forKey: "hiddenProviders")
        let upgraded = Preferences(defaults: defaults, providerIDs: ["claude", "cursor"])
        XCTAssertFalse(upgraded.isConnected("claude"))
        XCTAssertFalse(upgraded.isConnected("cursor"))
        upgraded.setConnected(true, for: "claude")
        let restarted = Preferences(defaults: defaults, providerIDs: ["claude", "cursor"])
        XCTAssertTrue(restarted.isConnected("claude"))
        XCTAssertFalse(restarted.isConnected("cursor"))
    }
}
