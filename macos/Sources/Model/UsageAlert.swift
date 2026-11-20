import Foundation

/// Decides when a reading is worth interrupting someone for.
///
/// The notch at rest is a pill, or nothing at all, so a limit that is about to
/// run out would otherwise only be seen by someone who happened to reach for
/// it. This watches every metered window and says when one *crosses* one of the
/// chosen thresholds — once per crossing, not once per refresh, or a notch
/// sitting at 92% would pop open every two minutes until the reset.
///
/// It also says when a window that was alerted on has come back (a reset is
/// good news worth one glance), and keeps the once-per-cycle memory the pace
/// warning needs.
struct UsageAlertTracker {
    /// The share of a limit at which the notch speaks up unasked, unless the
    /// user picks other levels.
    static let threshold = 0.90

    /// The levels, in percent, that can be chosen in Settings.
    static let thresholds = [75, 90, 100]
    static let defaultThresholds: Set<Int> = [90]

    /// Below this, a window that had alerted counts as reset. Not "below the
    /// threshold": a window easing from 91% to 88% has not come back, it has
    /// only stopped climbing for a moment.
    static let recoveredBelow = 0.50

    /// A pace warning needs this much use already, and a run-out within this
    /// long. Early in a window every burst looks like it will empty it.
    static let paceMinimum = 0.50
    static let paceWithin: TimeInterval = 60 * 60

    struct Crossing: Equatable {
        let providerID: String
        let windowID: String
        let label: String
        let usedFraction: Double
        /// The highest chosen level this reading reached, in percent.
        let threshold: Int
    }

    struct Recovery: Equatable {
        let providerID: String
        let windowID: String
        let label: String
        let usedFraction: Double
    }

    struct Result: Equatable {
        var crossed: [Crossing] = []
        var recovered: [Recovery] = []
    }

    private struct WindowState {
        /// The highest chosen level the window currently sits at or above.
        var level = 0
        /// It brought the notch out at some point this cycle, so its reset is
        /// worth announcing.
        var alerted = false
        /// The pace warning has had its one say this cycle.
        var paced = false
    }

    /// Keyed by provider and window.
    private var state: [String: WindowState] = [:]

    private static func key(_ providerID: String, _ windowID: String) -> String {
        "\(providerID)\u{1F}\(windowID)"
    }

    /// Only the levels that can be chosen, and never none: an empty choice
    /// would quietly mean "no alerts", which is the other switch's job.
    static func clean(_ thresholds: Set<Int>) -> [Int] {
        let kept = thresholds.filter { Self.thresholds.contains($0) }.sorted()
        return kept.isEmpty ? defaultThresholds.sorted() : kept
    }

    /// Readings that are not current — stale, or behind a refused Keychain
    /// prompt — neither raise an alert nor clear one: the number on them is
    /// history, and opening the notch to show history would be a false alarm.
    static func isTrusted(_ snapshot: ProviderSnapshot) -> Bool {
        !snapshot.status.isStale && !snapshot.needsCredentialAccess
            && snapshot.status != .accessDenied
    }

    /// What this reading means: levels newly crossed, and windows that reset.
    ///
    /// A window re-arms as it drops back below a level, so the next climb is
    /// announced again. Jumping past two levels at once reports the higher.
    ///
    /// `silent` is for while alerts are muted — switched off, or quiet hours.
    /// The state still follows the readings downward, so a window that dropped
    /// back re-arms and a reset clears its "alerted" mark, but nothing is
    /// reported and no level is raised. Frozen instead, unmuting could announce
    /// a reset from days ago, or miss a fresh crossing of a level the window had
    /// left and come back to; and a window that climbed past a level while muted
    /// is announced when the mute ends, not lost.
    mutating func update(_ snapshots: [ProviderSnapshot],
                         thresholds: Set<Int> = defaultThresholds,
                         silent: Bool = false) -> Result {
        let levels = Self.clean(thresholds)
        var result = Result()
        for snapshot in snapshots where Self.isTrusted(snapshot) {
            for window in snapshot.windows {
                guard let used = window.usedFraction else { continue }
                let key = Self.key(snapshot.id, window.id)
                var s = state[key] ?? WindowState()
                let reached = levels.last { used >= Double($0) / 100 } ?? 0
                if silent {
                    s.level = min(s.level, reached)
                    if used < Self.recoveredBelow {
                        s.alerted = false
                        s.paced = false
                    }
                    state[key] = s
                    continue
                }
                if reached > s.level {
                    result.crossed.append(Crossing(providerID: snapshot.id, windowID: window.id,
                                                   label: window.label, usedFraction: used,
                                                   threshold: reached))
                    s.alerted = true
                }
                s.level = reached
                if used < Self.recoveredBelow {
                    if s.alerted {
                        result.recovered.append(Recovery(providerID: snapshot.id,
                                                         windowID: window.id,
                                                         label: window.label,
                                                         usedFraction: used))
                    }
                    s.alerted = false
                    s.paced = false
                }
                state[key] = s
            }
        }
        return result
    }

    /// The providers with a window that has newly reached a chosen level, each
    /// named once.
    mutating func newAlerts(in snapshots: [ProviderSnapshot],
                            thresholds: Set<Int> = defaultThresholds) -> [String] {
        var ids: [String] = []
        for crossing in update(snapshots, thresholds: thresholds).crossed
        where !ids.contains(crossing.providerID) {
            ids.append(crossing.providerID)
        }
        return ids
    }

    /// True once per window cycle when the recent pace runs out before the
    /// reset, within the hour.
    ///
    /// Marks the window as alerted, so its reset is announced too: having been
    /// told it would run out, you want to hear that it did not matter.
    mutating func pace(providerID: String, windowID: String, usedFraction: Double?,
                       forecast: UsageForecast?, now: Date = Date()) -> Bool {
        guard let forecast, forecast.beforeReset == true,
              let used = usedFraction, used >= Self.paceMinimum,
              forecast.eta.timeIntervalSince(now) <= Self.paceWithin
        else { return false }
        let key = Self.key(providerID, windowID)
        var s = state[key] ?? WindowState()
        guard !s.paced else { return false }
        s.paced = true
        s.alerted = true
        state[key] = s
        return true
    }

    /// Drops everything known about a provider, so switching it off and on
    /// again starts it afresh rather than from a crossing long past.
    mutating func forget(providerID: String) {
        let prefix = "\(providerID)\u{1F}"
        state = state.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Forgets every provider not in the list.
    mutating func retain(providerIDs: Set<String>) {
        state = state.filter { key, _ in
            providerIDs.contains(String(key.split(separator: "\u{1F}", maxSplits: 1).first ?? ""))
        }
    }
}

/// Hours in which nothing comes out unasked.
///
/// Kept as minutes after midnight rather than as dates, because it is a time of
/// day that repeats, not a moment.
struct QuietHours: Equatable {
    var isEnabled: Bool
    var start: Int
    var end: Int

    static let defaultStart = 22 * 60
    static let defaultEnd = 8 * 60

    /// "HH:MM" to minutes after midnight, or nil.
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        return h * 60 + m
    }

    /// May wrap midnight (22:00–07:00). The same start and end means no quiet
    /// time at all, not all day — that would be the alert switch's job.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let t = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (t >= start && t < end) : (t >= start || t < end)
    }
}

/// Which kind of notice is bringing the notch out, in the order one replaces
/// another: a limit beats a pace warning beats a reset.
enum UsageNoticeKind: Int, Comparable {
    case reset = 1
    case pace = 2
    case limit = 3

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One reason to bring the notch out, for one provider.
struct UsageNotice: Equatable {
    let providerID: String
    let displayName: String
    let kind: UsageNoticeKind
    let label: String
    let usedFraction: Double
    /// When the pace runs out, for a pace notice.
    var eta: Date?

    /// The notification's title: the provider, and for a reset, that it is
    /// back — the good news should not read like another warning.
    var title: String { kind == .reset ? "\(displayName) is back" : displayName }

    func body(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch kind {
        case .limit:
            return "\(label) is at \(Int((usedFraction * 100).rounded()))%."
        case .pace:
            let formatter = ResetCopy.formatter(for: calendar)
            formatter.dateFormat = "h:mm a"
            let when = eta.map { formatter.string(from: $0) } ?? "soon"
            return "\(label) may run out around \(when), before it resets."
        case .reset:
            return "\(label) has reset."
        }
    }
}

extension UsageAlertTracker {
    /// What a round of readings is worth saying, one notice per provider at
    /// most: a crossed limit beats a pace warning, which beats a reset.
    ///
    /// Called only while alerts may speak. While they are muted — switched off,
    /// or quiet hours — the caller feeds `update(_:thresholds:silent:)` instead,
    /// so the state still follows the readings down without announcing anything,
    /// and a limit that climbed during the mute is announced when it ends.
    mutating func notices(for snapshots: [ProviderSnapshot],
                          thresholds: Set<Int> = defaultThresholds,
                          paceAlerts: Bool,
                          forecasts: [String: [String: UsageForecast]],
                          now: Date = Date()) -> [UsageNotice] {
        let result = update(snapshots, thresholds: thresholds)
        var notices: [UsageNotice] = []
        for snapshot in snapshots {
            let name = snapshot.displayName
            // Several windows can cross in one reading: name the most serious,
            // the highest level and then the most used.
            let crossing = result.crossed
                .filter { $0.providerID == snapshot.id }
                .max { ($0.threshold, $0.usedFraction) < ($1.threshold, $1.usedFraction) }
            if let crossing {
                notices.append(UsageNotice(providerID: snapshot.id, displayName: name,
                                           kind: .limit, label: crossing.label,
                                           usedFraction: crossing.usedFraction))
                continue
            }
            if paceAlerts, Self.isTrusted(snapshot) {
                var paced: LimitWindow?
                for window in snapshot.windows
                where pace(providerID: snapshot.id, windowID: window.id,
                           usedFraction: window.usedFraction,
                           forecast: forecasts[snapshot.id]?[window.id], now: now) {
                    paced = window
                    break
                }
                if let window = paced {
                    notices.append(UsageNotice(providerID: snapshot.id, displayName: name,
                                               kind: .pace, label: window.label,
                                               usedFraction: window.usedFraction ?? 0,
                                               eta: forecasts[snapshot.id]?[window.id]?.eta))
                    continue
                }
            }
            if let recovery = result.recovered.first(where: { $0.providerID == snapshot.id }) {
                notices.append(UsageNotice(providerID: snapshot.id, displayName: name,
                                           kind: .reset, label: recovery.label,
                                           usedFraction: recovery.usedFraction))
            }
        }
        return notices
    }
}
