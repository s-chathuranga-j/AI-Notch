import Foundation

/// One remembered reading: when, and how much of the limit was used, in
/// percent. Encoded as a two-number array so a week of samples stays small.
struct UsageSample: Equatable, Codable {
    let at: Date
    var percent: Double

    init(at: Date, percent: Double) {
        self.at = at
        self.percent = percent
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let seconds = try container.decode(Double.self)
        let percent = try container.decode(Double.self)
        guard seconds.isFinite, percent.isFinite else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "not a number")
        }
        self.init(at: Date(timeIntervalSince1970: seconds), percent: percent)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(at.timeIntervalSince1970)
        try container.encode(percent)
    }
}

/// Usage over the last week, per provider and window, for the pace forecast and
/// the daily peaks.
///
/// Only percentages and timestamps are kept — never credentials, account names
/// or provider responses — so the file says how busy you were and nothing about
/// who you are or what you did. Thinned to about two samples per `sampleGap`,
/// pruned after `keep`.
struct UsageHistory: Equatable {
    static let sampleGap: TimeInterval = 5 * 60
    static let keep: TimeInterval = 8 * 24 * 60 * 60

    private(set) var series: [String: [UsageSample]] = [:]

    init() {}

    private static func key(_ providerID: String, _ windowID: String) -> String {
        "\(providerID)\u{1F}\(windowID)"
    }

    /// Records a reading. True when something was stored, so the caller knows
    /// whether there is anything to save.
    ///
    /// Readings that are not current are history already and are not recorded
    /// again as if they were new.
    @discardableResult
    mutating func add(_ snapshot: ProviderSnapshot, now: Date = Date()) -> Bool {
        guard UsageAlertTracker.isTrusted(snapshot) else { return false }
        // Stamped with when the source measured it, where it says: the store
        // re-publishes an unchanged reading whenever any provider updates, and
        // stamping that with the app's clock would keep an old number looking
        // fresh — and two copies of one reading can fake a pace.
        let at = snapshot.observedAt ?? now
        var changed = false
        for window in snapshot.windows {
            guard let used = window.usedFraction, used.isFinite else { continue }
            let percent = used * 100
            let key = Self.key(snapshot.id, window.id)
            var list = series[key] ?? []
            if let last = list.last, at <= last.at { continue }
            // Within `sampleGap` of the sample before it, the newest reading
            // replaces the trailing one — with its own timestamp, so the series
            // never backdates a reading and the forecast is not early. A drop
            // (a reset) is always kept as a new sample, so the forecast can see
            // the new window start.
            if list.count >= 2, let last = list.last,
               at.timeIntervalSince(list[list.count - 2].at) < Self.sampleGap,
               percent >= last.percent {
                list[list.count - 1] = UsageSample(at: at, percent: percent)
                series[key] = list
                changed = true
                continue
            }
            list.append(UsageSample(at: at, percent: percent))
            series[key] = list
            changed = true
        }
        return prune(now: now) || changed
    }

    @discardableResult
    mutating func prune(now: Date = Date()) -> Bool {
        var changed = false
        for (key, list) in series {
            let kept = list.filter { now.timeIntervalSince($0.at) <= Self.keep }
            guard kept.count != list.count else { continue }
            changed = true
            series[key] = kept.isEmpty ? nil : kept
        }
        return changed
    }

    /// Drops a provider's history, as when it is switched off: what is not
    /// being read should not be remembered either.
    @discardableResult
    mutating func forget(providerID: String) -> Bool {
        let prefix = "\(providerID)\u{1F}"
        let before = series.count
        series = series.filter { !$0.key.hasPrefix(prefix) }
        return series.count != before
    }

    func samples(providerID: String, windowID: String) -> [UsageSample] {
        series[Self.key(providerID, windowID)] ?? []
    }
}

extension UsageHistory: Codable {
    private enum CodingKeys: String, CodingKey { case version, series }

    /// A damaged series is dropped on its own rather than costing the whole
    /// file, and an unreadable sample is dropped from its series.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([String: Lenient<[Lenient<UsageSample>]>].self,
                                                forKey: .series) ?? [:]
        for (key, list) in raw {
            guard let list = list.value else { continue }
            let samples = list.compactMap(\.value)
            if !samples.isEmpty { series[key] = samples }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(series, forKey: .series)
    }
}

/// Decodes to nil instead of failing its parent.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// When a window will run out if the recent pace holds.
struct UsageForecast: Equatable {
    let eta: Date
    /// Nil when the provider does not say when the window resets.
    let beforeReset: Bool?
    /// Percentage points per hour, to one decimal place.
    let perHour: Double
}

/// One day's highest reading.
struct DailyPeak: Equatable {
    /// Local midnight at the start of the day.
    let day: Date
    /// Nil for a day with no reading, so a quiet day is not drawn as zero use.
    let peak: Double?
}

enum UsageInsights {
    static let lookback: TimeInterval = 90 * 60
    static let minimumSpan: TimeInterval = 15 * 60
    static let maximumAge: TimeInterval = 30 * 60
    static let horizon: TimeInterval = 2 * 24 * 60 * 60
    /// A drop at least this large, in points, is a reset.
    static let resetDrop = 10.0

    /// Extends the recent pace to 100%.
    ///
    /// Uses only samples since the last reset and within `lookback`, and needs
    /// at least `minimumSpan` of rising use — two readings a minute apart are
    /// noise, not a pace. Least squares rather than first-to-last, so one
    /// burst does not swing the answer.
    static func forecast(_ samples: [UsageSample], now: Date = Date(),
                         resetsAt: Date? = nil) -> UsageForecast? {
        guard samples.count >= 2 else { return nil }
        var start = 0
        for i in 1..<samples.count where samples[i].percent <= samples[i - 1].percent - resetDrop {
            start = i
        }
        let recent = samples[start...].filter { now.timeIntervalSince($0.at) <= lookback }
        guard recent.count >= 2, let first = recent.first, let last = recent.last,
              last.at.timeIntervalSince(first.at) >= minimumSpan,
              now.timeIntervalSince(last.at) <= maximumAge
        else { return nil }

        // Relative to the first sample, so the squares stay well inside a
        // Double's precision.
        let n = Double(recent.count)
        let ts = recent.map { $0.at.timeIntervalSince(first.at) }
        let ps = recent.map(\.percent)
        let mt = ts.reduce(0, +) / n, mp = ps.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (t, p) in zip(ts, ps) {
            num += (t - mt) * (p - mp)
            den += (t - mt) * (t - mt)
        }
        let rate = den > 0 ? num / den : 0   // percent per second
        guard rate > 0, last.percent < 100 else { return nil }

        let eta = last.at.addingTimeInterval((100 - last.percent) / rate)
        guard eta.timeIntervalSince(now) <= horizon else { return nil }
        return UsageForecast(
            eta: max(now, eta),
            beforeReset: resetsAt.map { eta < $0 },
            perHour: (rate * 3600 * 10).rounded() / 10
        )
    }

    /// The highest reading on each of the last `days` local days, oldest first.
    static func dailyPeaks(_ samples: [UsageSample], now: Date = Date(), days: Int = 7,
                           calendar: Calendar = .current) -> [DailyPeak] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { back -> DailyPeak? in
            guard let start = calendar.date(byAdding: .day, value: -back, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { return nil }
            let peak = samples.filter { $0.at >= start && $0.at < end }.map(\.percent).max()
            return DailyPeak(day: start, peak: peak)
        }
    }
}

/// What the tooltip can say beyond the current reading.
struct ProviderInsights: Equatable {
    /// Keyed by window id.
    var forecasts: [String: UsageForecast] = [:]
    /// The headline window's last seven days, in percent, when at least two of
    /// them have a reading — one bar is not a trend.
    var peaks: [DailyPeak]?
    /// Which window the peaks are for.
    var peaksLabel: String?
    /// Where the chart's dotted guide sits, in percent: the lowest alert level,
    /// so a bar crossing it is a day that would have alerted.
    var guidePercent: Double = 90

    var isEmpty: Bool { forecasts.isEmpty && peaks == nil }

    /// Works out what can be said about a provider from its history.
    static func make(for snapshot: ProviderSnapshot, history: UsageHistory,
                     now: Date = Date(), calendar: Calendar = .current,
                     guidePercent: Double = 90) -> ProviderInsights? {
        guard UsageAlertTracker.isTrusted(snapshot), snapshot.statusMessage == nil else { return nil }
        var insights = ProviderInsights()
        insights.guidePercent = guidePercent
        for window in snapshot.windows where window.usedFraction != nil {
            let samples = history.samples(providerID: snapshot.id, windowID: window.id)
            if let f = UsageInsights.forecast(samples, now: now, resetsAt: window.resetsAt) {
                insights.forecasts[window.id] = f
            }
        }
        if let headline = snapshot.headline, headline.usedFraction != nil {
            let days = UsageInsights.dailyPeaks(
                history.samples(providerID: snapshot.id, windowID: headline.id),
                now: now, calendar: calendar
            )
            if days.filter({ $0.peak != nil }).count >= 2 {
                insights.peaks = days
                insights.peaksLabel = headline.label
            }
        }
        return insights.isEmpty ? nil : insights
    }
}

/// Where the history lives between launches: a small JSON file in Application
/// Support, written atomically and readable only by its owner.
struct UsageHistoryFile {
    let url: URL

    static var standard: UsageHistoryFile? {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.fourforge.ainotch"
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first
        else { return nil }
        return UsageHistoryFile(url: support.appendingPathComponent(bundleID)
            .appendingPathComponent("history.json"))
    }

    func load() -> UsageHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(UsageHistory.self, from: data)
        else { return UsageHistory() }
        return history
    }

    func save(_ history: UsageHistory) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: url.path)
        } catch {
            Log.usage.error("history save failed")
        }
    }
}
