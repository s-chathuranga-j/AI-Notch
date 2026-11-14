import XCTest
@testable import AINotch

final class ClaudeStatusLineProviderTests: XCTestCase {
    @MainActor
    func testStatusLineFeedsUsageStoreWithoutInventingFreshness() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = ClaudeProfile(slug: "work", configDirectory: home)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let provider = ClaudeStatusLineProvider(profile: profile)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClaudeStatusLineTests.\(UUID())"))
        let archive = UsageArchive(defaults: defaults)
        let store = UsageStore(providers: [provider], archive: archive)
        let now = Date()
        let reset = now.addingTimeInterval(3600).timeIntervalSince1970
        let input = Data("""
            {
              "transcript_path": "/private/transcript.jsonl",
              "rate_limits": {
                "five_hour": {"used_percentage": 0, "resets_at": \(reset)},
                "seven_day": {"used_percentage": 55.5, "resets_at": \(reset)}
              }
            }
            """.utf8)

        await store.refresh()
        XCTAssertTrue(store.snapshots.first?.statusMessage?.contains("Claude Code usage") == true)

        try provider.save(input: input, now: now)
        try provider.save(input: Data(#"{"rate_limits":{}}"#.utf8), now: now)
        await store.refresh()
        let snapshot = try XCTUnwrap(store.snapshots.first)
        XCTAssertEqual(snapshot.id, "claude-work")
        XCTAssertEqual(snapshot.headlineText, "0%")
        XCTAssertEqual(snapshot.windows.last?.usedFraction, 0.555)
        XCTAssertEqual(archive.load()[provider.id]?.fetchedAt, now)
        let saved = try String(contentsOf: home.appendingPathComponent("ai-notch-usage.json"), encoding: .utf8)
        XCTAssertFalse(saved.contains("transcript"))

        let past = now.addingTimeInterval(-16 * 60)
        try provider.save(input: input, now: past)
        await store.refresh()
        XCTAssertEqual(store.snapshots.first?.headlineText, "Stale")
        XCTAssertNil(store.snapshots.first?.ringFraction)
        XCTAssertEqual(store.snapshots.first?.status.staleSince, past)
        XCTAssertEqual(archive.load()[provider.id]?.fetchedAt, past)

        await provider.signOut()
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("ai-notch-usage.json").path))
    }
}
