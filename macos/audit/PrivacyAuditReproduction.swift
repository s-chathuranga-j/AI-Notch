import XCTest
@testable import AINotch

/// Audit-only probes. These assert privacy guarantees and intentionally fail
/// against the audited version. Only synthetic accounts and isolated defaults.
@MainActor
final class PrivacyAuditReproduction: XCTestCase {
    private final class Probe: UsageProvider, @unchecked Sendable {
        let id: String
        let displayName = "Audit fixture"
        let glyph = ProviderGlyph.claude
        var accountReads = 0
        var fetches = 0
        var started: XCTestExpectation?
        var block = false
        var continuation: CheckedContinuation<Void, Never>?
        init(_ id: String) { self.id = id }
        func account() -> ProviderAccount? {
            accountReads += 1
            return ProviderAccount(label: "synthetic@example.invalid", plan: "fixture", source: "test", manageURL: nil)
        }
        func fetchSnapshot() async throws -> ProviderSnapshot {
            fetches += 1
            if block {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    self.started?.fulfill()
                }
            } else { started?.fulfill() }
            return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                fidelity: .manual, status: .ok,
                windows: [LimitWindow(id: "fixture", label: "Synthetic", usedFraction: 0.25)])
        }
    }

    func testDisabledAccountIsNotReadBySettings() {
        let name = "PrivacyAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = Probe("disabled")
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults), disconnected: ["disabled"])
        _ = store.providerSummaries
        XCTAssertEqual(provider.accountReads, 0, "Settings reads account data for a disabled provider")
    }

    func testDisablingQueuedProviderPreventsFetchAndPersistence() async {
        let name = "PrivacyAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Probe("first"), blocked = Probe("blocked")
        let firstStarted = expectation(description: "First synthetic fetch paused")
        let secondStarted = expectation(description: "Queued synthetic fetch observed")
        first.block = true
        first.started = firstStarted
        blocked.started = secondStarted
        let archive = UsageArchive(defaults: defaults)
        let store = UsageStore(providers: [first, blocked], archive: archive)
        defer { store.stop() }
        store.start()
        await fulfillment(of: [firstStarted], timeout: 3)
        store.disconnected = ["blocked"]
        first.continuation?.resume()
        await fulfillment(of: [secondStarted], timeout: 3)
        XCTAssertEqual(blocked.fetches, 0, "A provider switched off during the refresh is still fetched")
        XCTAssertNil(archive.load()["blocked"], "The disabled provider's reading is saved again")
    }
    func testNonZaiCodingPlanKeyIsNotClaimedForZai() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        let json = #"{"provider":{"builtin:other-vendor-coding-plan":{"enabled":true,"options":{"apiKey":"SYNTHETIC-NON-ZAI-KEY","baseURL":"https://api.example.invalid"}}}}"#
        try Data(json.utf8).write(to: file)
        let credential = GLMCredentials.zcodePlanKey(file)
        XCTAssertNil(credential, "An unrelated provider key was claimed and routed to \(credential?.baseURL.absoluteString ?? "none")")
    }

}
