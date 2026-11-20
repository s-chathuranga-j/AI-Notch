import Foundation

/// Decides when a reading is worth interrupting someone for.
///
/// The notch at rest is a pill, or nothing at all, so a limit that is about to
/// run out would otherwise only be seen by someone who happened to reach for
/// it. This watches every metered window and says when one *crosses* the
/// threshold — once per crossing, not once per refresh, or a notch sitting at
/// 92% would pop open every two minutes until the reset.
struct UsageAlertTracker {
    /// The share of a limit at which the notch speaks up unasked.
    static let threshold = 0.90

    /// Windows already announced, keyed by provider and window. A key leaves
    /// the set when its window drops back below the threshold — which is what
    /// a reset looks like — so the next climb is announced again.
    private(set) var announced: Set<String> = []

    /// The providers with a window that has newly reached the threshold.
    ///
    /// Readings that are not current — stale, or behind a refused Keychain
    /// prompt — neither raise an alert nor clear one: the number on them is
    /// history, and opening the notch to show history would be a false alarm.
    mutating func newAlerts(in snapshots: [ProviderSnapshot]) -> [String] {
        var fresh: [String] = []
        var stillHigh: Set<String> = []
        var untrusted: Set<String> = []

        for snapshot in snapshots {
            let trusted = !snapshot.status.isStale
                && !snapshot.needsCredentialAccess
                && snapshot.status != .accessDenied
            for window in snapshot.windows {
                let key = "\(snapshot.id)\u{1F}\(window.id)"
                guard trusted else { untrusted.insert(key); continue }
                guard let used = window.usedFraction, used >= Self.threshold else { continue }
                stillHigh.insert(key)
                if !announced.contains(key), !fresh.contains(snapshot.id) {
                    fresh.append(snapshot.id)
                }
            }
        }

        // Keep what is still high, and what we could not judge this time.
        announced = stillHigh.union(announced.intersection(untrusted))
        return fresh
    }
}
