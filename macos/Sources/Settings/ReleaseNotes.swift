import Foundation

/// What one release changed, in the app's own words.
struct ReleaseNote: Equatable {
    /// Matched against `CFBundleShortVersionString`, so it has to be exactly
    /// the string `MARKETING_VERSION` is set to.
    let version: String
    /// One line under the title. What this release is *about*.
    let headline: String
    let changes: [Change]

    /// A title carries the change; the detail is optional, so a small fix can
    /// be a single line rather than a line padded out to match its neighbours.
    struct Change: Equatable {
        let title: String
        let detail: String

        init(title: String, detail: String = "") {
            self.title = title
            self.detail = detail
        }
    }
}

/// The release history the app ships with.
///
/// Written here rather than fetched from the appcast: it has to be there on a
/// first launch with no network, and it belongs to the build it describes.
/// Bumping `MARKETING_VERSION` without adding an entry is caught by
/// `testTheCurrentVersionHasANote`.
enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(version: "0.2.0", headline: "Meet AI Notch.", changes: [
            .init(title: "Your AI usage, at a glance", detail: "Usage rings and reset times for Claude Code, Cursor, Codex, Antigravity and GLM."),
            .init(title: "GitHub Copilot, experimentally", detail: "Copilot quotas read through the GitHub CLI’s login, with reset dates and unlimited allowances shown as GitHub reports them."),
            .init(title: "Keep sessions in sight", detail: "See when your coding agents are working or waiting for you."),
            .init(title: "Make it fit your Mac", detail: "Choose any screen edge, hover to expand, and manage providers in Settings."),
            .init(title: "Private by choice", detail: "Enable only the accounts you want. Disabling an account stops its reads and monitoring. Usage responses are never written to app logs.")
        ])
    ]

    static func note(for version: String) -> ReleaseNote? {
        all.first { $0.version == version }
    }

    /// The note worth showing on this launch, if there is one.
    ///
    /// `notes` is a parameter so the rule can be tested against a fixed history
    /// rather than against whatever the app happens to ship this week.
    static func unseen(in version: String,
                       lastSeen: String?,
                       notes: [ReleaseNote] = ReleaseNotes.all) -> ReleaseNote? {
        guard lastSeen != version else { return nil }
        return notes.first { $0.version == version }
    }
}
