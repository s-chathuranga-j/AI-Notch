import Foundation

/// "At this pace: out ~3:40 PM, before reset" — the line under a window that is
/// on course to run out.
///
/// Short on purpose: it shares the card's one-line column with nothing else,
/// and a clock time is what you plan around, so it leads with that rather than
/// with a rate.
enum ForecastCopy {
    static func text(for forecast: UsageForecast, now: Date = Date(),
                     calendar: Calendar = .current) -> String {
        let when: String
        if forecast.eta.timeIntervalSince(now) < 60 {
            when = "any minute"
        } else {
            let formatter = ResetCopy.formatter(for: calendar)
            // The same literal pattern the reset copy uses, so the two clocks
            // on one card read alike.
            formatter.dateFormat = ResetCopy.daysApart(from: now, to: forecast.eta,
                                                       calendar: calendar) >= 1
                ? "E h:mm a" : "h:mm a"
            when = "~" + formatter.string(from: forecast.eta)
        }
        let tail: String
        switch forecast.beforeReset {
        case true?:  tail = ", before reset"
        case false?: tail = ", after reset"
        case nil:    tail = ""
        }
        return "At this pace: out \(when)\(tail)"
    }
}
