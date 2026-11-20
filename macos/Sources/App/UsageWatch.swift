import Foundation
import UserNotifications

/// Everything that happens to a round of readings after it lands: remembered
/// in the history, turned into forecasts, and judged worth interrupting for.
///
/// Kept out of `AppDelegate` so the sink there stays a line long and so one
/// object owns the tracker, the history and when the history was last saved.
@MainActor
final class UsageWatch {
    private var tracker = UsageAlertTracker()
    private(set) var history: UsageHistory
    private let file: UsageHistoryFile?
    private var lastSave = Date.distantPast
    private var unsaved = false
    /// The last round of readings, so a change of ring choice can be applied
    /// without waiting for the next refresh.
    private(set) var lastReadings: [ProviderSnapshot] = []

    /// Writes are batched: a reading lands every couple of minutes per
    /// provider, and the file only needs to survive a restart.
    private static let saveInterval: TimeInterval = 60

    init(file: UsageHistoryFile?) {
        self.file = file
        self.history = file?.load() ?? UsageHistory()
    }

    /// Records the readings and returns what is worth announcing. Takes the
    /// readings as the providers reported them: alerts are per window, and do
    /// not care which one the ring stands for.
    ///
    /// With `judge` false — alerts off, or quiet hours — the tracker follows
    /// the readings silently, so a limit that climbed while muted is announced
    /// when the mute ends rather than lost, and nothing stale is announced.
    func receive(_ snapshots: [ProviderSnapshot], record: Bool, judge: Bool,
                 thresholds: Set<Int>, paceAlerts: Bool,
                 now: Date = Date()) -> [UsageNotice] {
        lastReadings = snapshots
        if record {
            for snapshot in snapshots where history.add(snapshot, now: now) { unsaved = true }
            saveIfDue(now: now)
        }
        tracker.retain(providerIDs: Set(snapshots.map(\.id)))
        guard judge else {
            _ = tracker.update(snapshots, thresholds: thresholds, silent: true)
            return []
        }
        return tracker.notices(for: snapshots, thresholds: thresholds,
                               paceAlerts: paceAlerts,
                               forecasts: insights(for: snapshots, now: now).mapValues(\.forecasts),
                               now: now)
    }

    /// What the tooltip can say about each provider. The daily peaks follow
    /// the ring, so pass the readings with the user's ring choice applied.
    func insights(for snapshots: [ProviderSnapshot], now: Date = Date(),
                  guidePercent: Double = 90) -> [String: ProviderInsights] {
        var insights: [String: ProviderInsights] = [:]
        for snapshot in snapshots {
            if let made = ProviderInsights.make(for: snapshot, history: history, now: now,
                                                guidePercent: guidePercent) {
                insights[snapshot.id] = made
            }
        }
        return insights
    }

    /// A provider switched off stops being remembered as well as read.
    func forget(providerIDs: Set<String>) {
        for id in providerIDs where history.forget(providerID: id) { unsaved = true }
        for id in providerIDs { tracker.forget(providerID: id) }
        saveIfDue(now: Date(), force: true)
    }

    func saveNow() { saveIfDue(now: Date(), force: true) }

    private func saveIfDue(now: Date, force: Bool = false) {
        guard unsaved, let file,
              force || now.timeIntervalSince(lastSave) >= Self.saveInterval
        else { return }
        file.save(history)
        lastSave = now
        unsaved = false
    }
}

/// macOS notifications for the same moments the notch comes out for.
///
/// Permission is asked for only when the user turns them on in Settings — a
/// prompt at launch, before anyone knows what it is for, is one people refuse.
@MainActor
final class SystemNotifier {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted { Log.usage.info("notifications were not allowed") }
        }
    }

    func post(_ notice: UsageNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body()
        // A reset is good news: worth seeing, not worth a sound.
        if notice.kind != .reset { content.sound = .default }
        let request = UNNotificationRequest(
            identifier: "usage.\(notice.providerID).\(notice.kind.rawValue)",
            content: content, trigger: nil
        )
        center.add(request) { error in
            if error != nil { Log.usage.error("notification failed") }
        }
    }
}
