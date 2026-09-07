import XCTest
import Combine
@testable import AINotch

/// Privacy regression coverage uses synthetic accounts and isolated defaults.
@MainActor
final class PrivacyRegressionTests: XCTestCase {
    private final class Probe: UsageProvider, @unchecked Sendable {
        let id: String
        let displayName = "Audit fixture"
        let glyph = ProviderGlyph.claude
        var accountReads = 0
        var fetches = 0
        var sawCancellation = false
        var forgotten = 0
        var started: XCTestExpectation?
        var block = false
        var continuation: CheckedContinuation<Void, Never>?
        init(_ id: String) { self.id = id }
        func forgetCachedCredential() { forgotten += 1 }
        func account() -> ProviderAccount? {
            accountReads += 1
            return ProviderAccount(label: "synthetic@example.invalid", plan: "fixture", source: "test", manageURL: nil)
        }
        func fetchSnapshot() async throws -> ProviderSnapshot {
            fetches += 1
            let fraction = fetches == 1 ? 0.25 : 0.75
            if block {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    self.started?.fulfill()
                }
            } else { started?.fulfill() }
            sawCancellation = Task.isCancelled
            return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                fidelity: .manual, status: .ok,
                windows: [LimitWindow(id: "fixture", label: "Synthetic", usedFraction: fraction)])
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
        first.block = true
        first.started = firstStarted
        let archive = UsageArchive(defaults: defaults)
        let store = UsageStore(providers: [first, blocked], archive: archive)
        defer { store.stop() }
        let refresh = Task { await store.refresh() }
        await fulfillment(of: [firstStarted], timeout: 3)
        store.disconnected = ["blocked"]
        first.continuation?.resume()
        await refresh.value
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

    func testDisabledInFlightResultIsDiscardedAndCredentialForgotten() async {
        let name = "PrivacyAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = Probe("a")
        provider.block = true
        let started = expectation(description: "In-flight request")
        provider.started = started
        let archive = UsageArchive(defaults: defaults)
        let store = UsageStore(providers: [provider], archive: archive)
        let task = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 3)
        store.disconnected = ["a"]
        provider.continuation?.resume()
        await task.value
        store.stop()
        XCTAssertTrue(provider.sawCancellation)
        XCTAssertGreaterThan(provider.forgotten, 0)
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertNil(archive.load()["a"])
    }

    func testSupportedProviderIDStillRejectsWrongOrAmbiguousHost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        for base in ["https://api.example.invalid", "https://api.z.ai.evil.invalid", "https://evil.z.ai", "http://api.z.ai", "https://user@api.z.ai", "https://api.z.ai:8443", ""] {
            let json: [String: Any] = ["provider": ["builtin:zai-coding-plan": ["enabled": true, "options": ["apiKey": "fixture", "baseURL": base]]]]
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            XCTAssertNil(GLMCredentials.zcodePlanKey(file), base)
        }
    }

    func testForgettingCredentialDuringReloadDoesNotRepopulateCache() throws {
        let cache = CredentialCache<String>(isExpired: { _ in false })
        XCTAssertThrowsError(try cache.value(reload: {
            cache.forget()
            return "old-key"
        }))
        let value = try cache.value(reload: { "new-key" })
        XCTAssertEqual(value, "new-key")
    }

    func testReenablingAccountCannotAcceptAnOldUncancellableResponse() async {
        let name = "PrivacyAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = Probe("a")
        provider.block = true
        let firstStarted = expectation(description: "Old request paused")
        provider.started = firstStarted
        let archive = UsageArchive(defaults: defaults)
        let store = UsageStore(providers: [provider], archive: archive)
        let first = Task { await store.refresh() }
        await fulfillment(of: [firstStarted], timeout: 3)
        store.disconnected = ["a"]
        provider.block = false
        provider.started = nil
        let newReading = expectation(description: "New request accepted")
        var observed = false
        let observation = store.$snapshots.sink { snapshots in
            if !observed, snapshots.first?.windows.first?.usedFraction == 0.75 {
                observed = true
                newReading.fulfill()
            }
        }
        store.disconnected = []
        await fulfillment(of: [newReading], timeout: 3)
        provider.continuation?.resume()
        await first.value
        observation.cancel()
        store.stop()
        XCTAssertEqual(store.snapshots.first?.windows.first?.usedFraction, 0.75)
        XCTAssertEqual(archive.load()["a"]?.snapshot.windows.first?.usedFraction, 0.75)
    }

}
