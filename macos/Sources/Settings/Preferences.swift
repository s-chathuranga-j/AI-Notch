import Combine
import Foundation
import ServiceManagement
import os

/// What the user has chosen, kept in `UserDefaults`.
@MainActor
final class Preferences: ObservableObject {
    /// Accounts the user has not enabled. Newly discovered accounts are added
    /// to this set before any provider starts, and choices persist per profile.
    ///
    /// Switching one off is not merely hiding it: the store stops fetching it,
    /// so its credential is never read at all.
    @Published var disconnectedProviders: Set<String> {
        didSet { defaults.set(Array(disconnectedProviders), forKey: Keys.disconnected) }
    }

    /// How much of itself the notch shows at rest.
    @Published var notchVisibility: NotchVisibility {
        didSet { defaults.set(notchVisibility.rawValue, forKey: Keys.visibility) }
    }

    /// Whether the notch comes out on its own when a limit reaches a chosen level.
    @Published var usageAlertsEnabled: Bool {
        didSet { defaults.set(usageAlertsEnabled, forKey: Keys.alerts) }
    }

    /// How long, in seconds, an alert holds the notch open before it goes
    /// back to the way Settings says it should look.
    @Published var usageAlertSeconds: Int {
        didSet {
            // Assigning inside `didSet` does not re-enter it, so the clamped
            // value is written on this same pass.
            let clamped = Self.clampAlertSeconds(usageAlertSeconds)
            if clamped != usageAlertSeconds { usageAlertSeconds = clamped }
            defaults.set(usageAlertSeconds, forKey: Keys.alertSeconds)
        }
    }

    /// The levels, in percent, at which a limit brings the notch out. Several
    /// can be chosen, so a 75% heads-up does not cost the 90% one.
    @Published var usageAlertThresholds: Set<Int> {
        didSet {
            let clean = Set(UsageAlertTracker.clean(usageAlertThresholds))
            if clean != usageAlertThresholds { usageAlertThresholds = clean }
            defaults.set(usageAlertThresholds.sorted(), forKey: Keys.alertThresholds)
        }
    }

    /// Warn once per window when the recent pace runs out before the reset.
    @Published var paceAlertsEnabled: Bool {
        didSet { defaults.set(paceAlertsEnabled, forKey: Keys.paceAlerts) }
    }

    /// Hours in which alerts stay quiet.
    @Published var quietHoursEnabled: Bool {
        didSet { defaults.set(quietHoursEnabled, forKey: Keys.quietEnabled) }
    }

    /// Minutes after midnight.
    @Published var quietHoursStart: Int {
        didSet { defaults.set(quietHoursStart, forKey: Keys.quietStart) }
    }

    @Published var quietHoursEnd: Int {
        didSet { defaults.set(quietHoursEnd, forKey: Keys.quietEnd) }
    }

    var quietHours: QuietHours {
        QuietHours(isEnabled: quietHoursEnabled, start: quietHoursStart, end: quietHoursEnd)
    }

    /// Post a macOS notification as well as bringing the notch out — for when
    /// you are looking at another screen.
    @Published var systemNotificationsEnabled: Bool {
        didSet { defaults.set(systemNotificationsEnabled, forKey: Keys.notifications) }
    }

    /// Which window each provider's ring stands for, by provider id. Absent
    /// means the provider's own headline.
    @Published var ringChoices: [String: String] {
        didSet { defaults.set(ringChoices, forKey: Keys.ringChoices) }
    }

    func ringChoice(for providerID: String) -> RingChoice {
        RingChoice(rawValue: ringChoices[providerID])
    }

    func setRingChoice(_ choice: RingChoice, for providerID: String) {
        ringChoices[providerID] = choice == .provider ? nil : choice.rawValue
    }

    /// The system-wide shortcut that brings the notch out for a look.
    @Published var peekShortcut: PeekShortcut {
        didSet { defaults.set(peekShortcut.rawValue, forKey: Keys.peekShortcut) }
    }

    /// Set when the shortcut could not be registered — another app holds it.
    /// Not stored: it is a fact about this launch, not a choice.
    @Published var peekShortcutProblem: String?

    nonisolated static let alertSecondsRange = 3...60
    nonisolated static let defaultAlertSeconds = 10

    nonisolated static func clampAlertSeconds(_ value: Int) -> Int {
        min(max(value, alertSecondsRange.lowerBound), alertSecondsRange.upperBound)
    }

    nonisolated static func clampMinutes(_ value: Int) -> Int {
        min(max(value, 0), 24 * 60 - 1)
    }

    /// Which screen edge the notch is welded to.
    @Published var notchEdge: NotchEdge {
        didSet { defaults.set(notchEdge.rawValue, forKey: Keys.edge) }
    }

    /// Where the app itself shows up: Dock, menu bar, or nowhere.
    @Published var appPresence: AppPresence {
        didSet { defaults.set(appPresence.rawValue, forKey: Keys.presence) }
    }

    /// The version whose changes have already been shown.
    ///
    /// Written when the What's New dialogue is dismissed rather than when it
    /// opens, so a crash in between cannot swallow the one launch it was going
    /// to appear on.
    @Published var lastSeenVersion: String? {
        didSet { defaults.set(lastSeenVersion, forKey: Keys.lastSeenVersion) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != Self.isRegisteredForLogin else { return }
            applyLaunchAtLogin()
        }
    }

    /// Set when the login-item request was refused, so the UI can say so rather
    /// than quietly flipping the switch back.
    @Published private(set) var launchAtLoginProblem: String?

    private let defaults: UserDefaults
    private enum Keys {
        /// The old name. Kept so existing choices survive the rename.
        static let disconnected = "hiddenProviders"
        static let hasLaunched = "hasLaunchedBefore"
        static let visibility = "notchVisibility"
        static let presence = "appPresence"
        static let edge = "notchEdge"
        static let lastSeenVersion = "lastSeenVersion"
        static let alerts = "usageAlertsEnabled"
        static let alertSeconds = "usageAlertSeconds"
        static let alertThresholds = "usageAlertThresholds"
        static let paceAlerts = "paceAlertsEnabled"
        static let quietEnabled = "quietHoursEnabled"
        static let quietStart = "quietHoursStart"
        static let quietEnd = "quietHoursEnd"
        static let notifications = "systemNotificationsEnabled"
        static let ringChoices = "ringChoices"
        static let peekShortcut = "peekShortcut"
    }

    /// True the very first time this copy runs, and never again.
    ///
    /// Deliberately *not* inferred from "there are no readings yet" — that is
    /// also true of someone who switched every provider off, and re-introducing
    /// them to the app every launch would be worse than never introducing them
    /// at all.
    let isFirstLaunch: Bool

    /// The bundle identifier before the app was renamed to AI Notch.
    ///
    /// A bundle id is the name of the defaults domain, so renaming the app
    /// silently moved every setting to a new, empty one — connection choices,
    /// the notch's mode, the archived readings, all apparently lost. Copying
    /// the old domain across once is the difference between a rename and what
    /// looks like a reset.
    private static let previousDomain = "com.fourforge.ainotch.legacy"

    static func migrateFromPreviousName(into defaults: UserDefaults = .standard,
                                        from domain: String = previousDomain) {
        // The emptiness test has to be about the object being written to, not
        // about `Bundle.main` — under test those are different domains, and the
        // first version happily copied real settings into a test's scratch
        // suite. `hasLaunched` is the sentinel: `Preferences.init` sets it, so
        // its absence means nothing has ever used this domain.
        guard defaults.object(forKey: Keys.hasLaunched) == nil,
              let old = defaults.persistentDomain(forName: domain), !old.isEmpty
        else { return }

        for (key, value) in old { defaults.set(value, forKey: key) }
        Log.usage.info("migrated \(old.count) settings from the previous app name")
    }

    init(defaults: UserDefaults = .standard, providerIDs: Set<String> = []) {
        self.defaults = defaults
        self.isFirstLaunch = !defaults.bool(forKey: Keys.hasLaunched)
        defaults.set(true, forKey: Keys.hasLaunched)
        var disconnected = Set(defaults.stringArray(forKey: Keys.disconnected) ?? [])
        let known = defaults.stringArray(forKey: "knownProviderIDs")
        // The first privacy-aware launch also requires affirmative consent:
        // the older build enabled every provider implicitly.
        if known == nil { disconnected.formUnion(providerIDs) }
        else if let known { disconnected.formUnion(providerIDs.subtracting(known)) }
        self.disconnectedProviders = disconnected
        defaults.set(Array(disconnected), forKey: Keys.disconnected)
        if !providerIDs.isEmpty { defaults.set(Array(providerIDs), forKey: "knownProviderIDs") }
        // Absent means never chosen, which is the hover behaviour the app was
        // designed around — not hidden, which would make a fresh install look
        // like it failed to start.
        self.notchVisibility = defaults.string(forKey: Keys.visibility)
            .flatMap(NotchVisibility.init(rawValue:)) ?? .onHover
        // On unless turned off: the point is to hear about a limit you were
        // not watching, and an opt-in alert is one nobody finds until too late.
        self.usageAlertsEnabled = defaults.object(forKey: Keys.alerts) as? Bool ?? true
        self.usageAlertSeconds = Self.clampAlertSeconds(
            defaults.object(forKey: Keys.alertSeconds) as? Int ?? Self.defaultAlertSeconds
        )
        self.usageAlertThresholds = Set(UsageAlertTracker.clean(
            Set(defaults.array(forKey: Keys.alertThresholds) as? [Int] ?? [])
        ))
        // On, like the alerts themselves: it only ever speaks once per window,
        // and only when the limit would otherwise run out before the reset.
        self.paceAlertsEnabled = defaults.object(forKey: Keys.paceAlerts) as? Bool ?? true
        self.quietHoursEnabled = defaults.bool(forKey: Keys.quietEnabled)
        self.quietHoursStart = Self.clampMinutes(
            defaults.object(forKey: Keys.quietStart) as? Int ?? QuietHours.defaultStart)
        self.quietHoursEnd = Self.clampMinutes(
            defaults.object(forKey: Keys.quietEnd) as? Int ?? QuietHours.defaultEnd)
        // Off until asked for: turning it on is what prompts macOS for
        // permission, and a prompt nobody asked for is one people refuse.
        self.systemNotificationsEnabled = defaults.bool(forKey: Keys.notifications)
        self.ringChoices = defaults.dictionary(forKey: Keys.ringChoices) as? [String: String] ?? [:]
        self.peekShortcut = defaults.string(forKey: Keys.peekShortcut)
            .flatMap(PeekShortcut.init(rawValue:)) ?? .controlOptionN
        // Absent means never chosen. The Dock is the default because it is the
        // findable one — a new user who cannot see the app anywhere has no way
        // to learn it is running.
        self.appPresence = defaults.string(forKey: Keys.presence)
            .flatMap(AppPresence.init(rawValue:)) ?? .dock
        // The right edge is where the notch has always been, and it is the one
        // side of a Mac that no system chrome claims by default.
        self.notchEdge = defaults.string(forKey: Keys.edge)
            .flatMap(NotchEdge.init(rawValue:)) ?? .right
        // Absent means nothing has been shown yet, which is true of a fresh
        // install — so the current release reads as new to it.
        self.lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion)
        // Read from the system rather than from our own store: the user can turn
        // this off in System Settings, and a remembered `true` would then be a lie.
        self.launchAtLogin = Self.isRegisteredForLogin
    }

    func isConnected(_ providerID: String) -> Bool {
        !disconnectedProviders.contains(providerID)
    }

    func setConnected(_ connected: Bool, for providerID: String) {
        if connected {
            disconnectedProviders.remove(providerID)
        } else {
            disconnectedProviders.insert(providerID)
        }
    }

    /// Forget everything this app has stored and quit.
    ///
    /// Deleting an app on macOS leaves `~/Library` untouched, so reinstalling
    /// brings back the old readings, the old connection choices and the old
    /// first-launch flag — which is exactly what makes a reinstall look broken.
    /// Nothing but the app itself can clean that up, so the app has to offer it.
    ///
    /// Not tied to uninstalling: a reinstall is indistinguishable from an
    /// update, and wiping data on every Sparkle update would be catastrophic.
    /// It has to be something the user asks for.
    static func eraseAllData() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.fourforge.ainotch"
        // Before anything is deleted: the save on quit would otherwise write
        // history.json straight back.
        UsageHistoryFile.isDisabled = true
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        for relative in ["Caches/\(bundleID)",
                         // The usage history: percentages and times only, but still yours.
                         "Application Support/\(bundleID)",
                         "WebKit/\(bundleID)",
                         "HTTPStorages/\(bundleID)",
                         "HTTPStorages/\(bundleID).binarycookies",
                         "Saved Application State/\(bundleID).savedState"] {
            if let url = library?.appendingPathComponent(relative) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Login item

    static var isRegisteredForLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginProblem = nil
        } catch {
            // Commonly refused for an app running from a build directory rather
            // than /Applications, which is worth saying plainly.
            Log.usage.error("launch at login request failed")
            launchAtLoginProblem = "macOS refused this — try moving AI Notch to /Applications."
            launchAtLogin = Self.isRegisteredForLogin
        }
    }
}
