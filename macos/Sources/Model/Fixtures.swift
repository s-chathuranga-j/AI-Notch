import Foundation

/// Clearly labeled sample readings for the interactive demo.
enum Fixtures {
    static func snapshots(now: Date = Date(), calendar: Calendar = .current) -> [ProviderSnapshot] {
        let sessionReset = now.addingTimeInterval(51 * 60)
        let midnight = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))

        return [
            ProviderSnapshot(
                id: "claude",
                displayName: "Claude (demo)",
                glyph: .claude,
                fidelity: .derived,
                status: .ok,
                windows: [
                    LimitWindow(id: "claude.session", label: "Current session",
                                usedFraction: 0.73, resetsAt: sessionReset),
                    LimitWindow(id: "claude.all", label: "All models",
                                usedFraction: 0.07, resetsAt: midnight)
                ]
            ),
            ProviderSnapshot(
                id: "codex",
                displayName: "Codex (demo)",
                glyph: .openai,
                fidelity: .manual,
                status: .ok,
                windows: [
                    LimitWindow(id: "codex.session", label: "Current session",
                                usedFraction: 0.21, resetsAt: now.addingTimeInterval(3 * 60 * 60))
                ]
            ),
            ProviderSnapshot(
                id: "cursor",
                displayName: "Cursor (demo)",
                glyph: .cursor,
                fidelity: .manual,
                status: .ok,
                windows: [
                    LimitWindow(id: "cursor.daily", label: "Daily quota",
                                usedFraction: 0.52, resetsAt: midnight)
                ]
            )
        ]
    }
}
