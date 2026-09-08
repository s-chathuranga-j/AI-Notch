import Foundation

/// Parses the answer from GitHub's Copilot entitlement endpoint,
/// `GET https://api.github.com/copilot_internal/user` — the same one VS Code
/// reads its quota banner from, and the same one the Windows build uses.
///
/// It is internal, not a published API, so the shape is pinned by tests and
/// read leniently: only the fields the notch needs are looked at, and a field
/// of the wrong type drops the window rather than the whole reading.
///
/// ```json
/// { "copilot_plan": "individual_pro", "token_based_billing": false,
///   "quota_reset_date_utc": "2026-10-01T00:00:00Z",
///   "quota_snapshots": {
///     "premium_interactions": { "entitlement": 300, "remaining": 225,
///                               "percent_remaining": 75, "unlimited": false },
///     "chat":        { "unlimited": true },
///     "completions": { "unlimited": true } } }
/// ```
///
/// GitHub reports what is *left*; the notch draws what is *used*, so the
/// percentage is turned around here. Unlimited quotas are kept as windows
/// without a number: on a paid plan chat and completions are unlimited, and a
/// tooltip that hid them would look like a plan with one allowance.
enum CopilotUsage {
    struct Payload {
        /// GitHub's own name for the plan — "individual_pro", "business" —
        /// or nil when the response declines to say.
        let plan: String?
        let windows: [LimitWindow]
        /// The first window with a percentage: the one the ring means. Nil
        /// when every quota is unlimited, and the cell shows ∞.
        let headlineID: String?
    }

    /// The quota categories, in the order GitHub's own panel lists them. The
    /// key is GitHub's; the id is the archive's.
    private static let categories: [(key: String, id: String, label: String)] = [
        ("premium_interactions", "premium", "Premium requests"),
        ("chat", "chat", "Chat"),
        ("completions", "completions", "Completions")
    ]

    static func parse(_ data: Data) throws -> Payload {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.badResponse(status: 200)
        }
        return parse(root)
    }

    static func parse(_ root: [String: Any]) -> Payload {
        let windows = windows(in: root)
        return Payload(
            plan: string(root["copilot_plan"]),
            windows: windows,
            headlineID: windows.first { $0.usedFraction != nil }?.id
        )
    }

    static func windows(in root: [String: Any]) -> [LimitWindow] {
        let snapshots = root["quota_snapshots"] as? [String: Any] ?? [:]
        // The plan-wide reset, used by any quota that does not name its own.
        let planReset = [root["quota_reset_date_utc"], root["quota_reset_date"], root["limited_user_reset_date"]]
            .lazy.compactMap(date).first
        let creditBilled = root["token_based_billing"] as? Bool ?? false

        return categories.compactMap { category in
            guard let quota = snapshots[category.key] as? [String: Any] else { return nil }
            let resetsAt = date(quota["quota_reset_at"]) ?? planReset
            // Premium requests become AI credits on credit-billed plans; the
            // flag lives on the plan or on the quota, depending on the build.
            let label = category.key == "premium_interactions"
                && (creditBilled || quota["token_based_billing"] as? Bool == true)
                ? "AI credits" : category.label

            if quota["unlimited"] as? Bool == true {
                return LimitWindow(id: category.id, label: label, resetsAt: resetsAt, isUnlimited: true)
            }
            // Not entitled to any: not a quota, so not a row. A zero-wide bar
            // would read as "none used" of an allowance that does not exist.
            if isZero(quota["entitlement"]) { return nil }
            guard let used = usedFraction(of: quota) else { return nil }
            return LimitWindow(id: category.id, label: label, usedFraction: used, resetsAt: resetsAt)
        }
    }

    /// GitHub's `percent_remaining` turned around, or worked out from the
    /// counts when the percentage is missing. Nil when neither is usable —
    /// a window with no denominator is a window we would have to invent.
    static func usedFraction(of quota: [String: Any]) -> Double? {
        if let remaining = number(quota["percent_remaining"]) {
            return 1 - min(1, max(0, remaining / 100))
        }
        if let entitlement = number(quota["entitlement"]), entitlement > 0,
           let remaining = number(quota["remaining"]), remaining >= 0 {
            return min(1, max(0, 1 - remaining / entitlement))
        }
        return nil
    }

    /// Reset dates arrive as ISO 8601 strings — with or without a time — or
    /// as seconds since the epoch. Anything else is "no reset", not a guess.
    static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        guard let text = string(value) else { return nil }
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds],
            [.withFullDate]
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    // MARK: Lenient scalars

    /// A number, and only a number: `true` is an NSNumber too, and a JSON
    /// string "70" is not a percentage we are willing to read.
    ///
    /// The boolean check goes through Core Foundation on purpose. Asking
    /// `value is Bool` says yes for the NSNumbers 0 and 1 as well — Swift
    /// bridges them either way — which threw out every `percent_remaining: 0`
    /// and read a fully spent quota as no quota at all.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// Zero however GitHub spells it — the number or the string.
    private static func isZero(_ value: Any?) -> Bool {
        if let number = number(value) { return number == 0 }
        return string(value) == "0"
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
