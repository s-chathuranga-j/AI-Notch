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

    /// Writes are batched: a reading lands every couple of minutes per
    /// provider, and the file only needs to survive a restart.
    private static let saveInterval: TimeInterval = 60

    init(file: UsageHistoryFile?) {
        self.file = file
        self.history = file?.load() ?? UsageHistory()
    }

    /// Records the readings and returns what the tooltip can now say about
    /// each provider, and what is worth announcing.
    func receive(_ snapshots: [ProviderSnapshot], record: Bool,
                 thresholds: Set<Int>, paceAlerts: Bool,
                 now: Date = Date()) -> (insights: [String: ProviderInsights], notices: [UsageNotice]) {
        if record {
            for snapshot in snapshots where history.add(snapshot, now: now) { unsaved = true }
            saveIfDue(now: now)
        }
        var insights: [String: ProviderInsights] = [:]
        for snapshot in snapshots {
            if let made = ProviderInsights.make(for: snapshot, history: history, now: now) {
                insights[snapshot.id] = made
            }
        }
        tracker.retain(providerIDs: Set(snapshots.map(\.id)))
        let notices = tracker.notices(for: snapshots, thresholds: thresholds,
                                      paceAlerts: paceAlerts,
                                      forecasts: insights.mapValues(\.forecasts), now: now)
        return (insights, notices)
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
