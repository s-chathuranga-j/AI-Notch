import Foundation

/// Claude Code invokes the collector with its status line JSON. The app reads
/// only the two quota windows written by that collector.
struct ClaudeStatusLineProvider: UsageProvider {
    let profile: ClaudeProfile
    var id: String { profile.id }
    var displayName: String { profile.displayName }
    let glyph = ProviderGlyph.claude

    private var readingURL: URL {
        profile.configDirectory.appendingPathComponent("ai-notch-usage.json")
    }

    var signInRoute: SignInRoute {
        .guidance("Copy the status line command into this profile’s Claude Code settings, then use Claude Code normally.")
    }

    var command: String? {
        guard let executable = Bundle.main.executablePath else { return nil }
        let args = [executable, "--claude-status-line", profile.id]
        return args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            .joined(separator: " ")
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let reading: Reading
        do {
            reading = try JSONDecoder().decode(Reading.self, from: Data(contentsOf: readingURL))
        } catch {
            throw UsageProviderError.noUsageReading
        }
        let now = Date()
        let windows = reading.windows
        guard reading.observedAt <= now, !windows.isEmpty else {
            throw UsageProviderError.noUsageReading
        }

        let active = windows.filter { $0.resetsAt.map { $0 > now } ?? false }
        let stale = active.isEmpty || now.timeIntervalSince(reading.observedAt) > 15 * 60
        return ProviderSnapshot(
            id: id, displayName: displayName, glyph: glyph, fidelity: .official,
            status: stale ? .stale(since: reading.observedAt,
                                   reason: "Waiting for updated usage from Claude Code.") : .ok,
            windows: stale ? windows : active, headlineID: "session",
            observedAt: reading.observedAt
        )
    }

    func signOut() async {
        try? FileManager.default.removeItem(at: readingURL)
    }

    /// Called by Claude Code, with no UI or network access. Resolve the same
    /// profile as the app and honor the app's existing integration switch.
    static func collect(providerID: String) {
        guard let settings = UserDefaults.standard.persistentDomain(forName: "com.fourforge.ainotch"),
              let known = settings["knownProviderIDs"] as? [String], known.contains(providerID),
              let disabled = settings["hiddenProviders"] as? [String], !disabled.contains(providerID),
              let profile = ClaudeProfile.discover().first(where: { $0.id == providerID }),
              let data = try? FileHandle.standardInput.readToEnd() else { return }

        try? Self(profile: profile).save(input: data)
    }

    func save(input: Data, now: Date = Date()) throws {
        let payload = try JSONDecoder().decode(StatusLine.self, from: input)
        guard let limits = payload.rateLimits else { return }
        let fiveHour = limits.fiveHour?.isValid(at: now) == true ? limits.fiveHour : nil
        let sevenDay = limits.sevenDay?.isValid(at: now) == true ? limits.sevenDay : nil
        guard fiveHour != nil || sevenDay != nil else { return }
        let reading = Reading(observedAt: now, fiveHour: fiveHour, sevenDay: sevenDay)
        try JSONEncoder().encode(reading).write(to: readingURL, options: .atomic)
    }

    private struct StatusLine: Decodable {
        struct Limits: Decodable {
            let fiveHour: Window?
            let sevenDay: Window?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
            }
        }

        let rateLimits: Limits?
        enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }

    private struct Window: Codable {
        let usedPercentage: Double
        let resetsAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

        func isValid(at date: Date) -> Bool {
            (0...100).contains(usedPercentage) && resetsAt.isFinite && resetsAt > date.timeIntervalSince1970
        }
    }

    private struct Reading: Codable {
        let observedAt: Date
        let fiveHour: Window?
        let sevenDay: Window?

        var windows: [LimitWindow] {
            [(fiveHour, "session", "Current session"), (sevenDay, "weekly_all", "All models")]
                .compactMap { window, id, label in
                    guard let window, window.isValid(at: observedAt) else { return nil }
                    return LimitWindow(id: id, label: label, usedFraction: window.usedPercentage / 100,
                                       resetsAt: Date(timeIntervalSince1970: window.resetsAt))
                }
        }
    }
}
