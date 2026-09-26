import Foundation
import os

/// Antigravity's local language server already holds the Google credential and
/// serves the quota used by its own Models & Usage panel. Asking that service
/// avoids reading its rotating Keychain item, which can prompt again after each
/// rotation even if the user previously chose Always Allow.
actor AntigravityProvider: UsageProvider {
    nonisolated let id = "gemini"
    // The id stays `gemini`: it keys the archive and the user's connection
    // choice, and changing it would silently discard both.
    nonisolated let displayName = "Antigravity"
    nonisolated let glyph = ProviderGlyph.antigravity

    private let localSession: URLSession
    /// A test can supply a local quota without launching Antigravity or asking
    /// the keychain. Production uses the running language server only.
    private let readLocalQuota: (@Sendable () async -> [LimitWindow]?)?
    /// Re-discovering the port and token means spawning `ps` and `lsof`, which
    /// is not something to do every minute. Cached until it stops working.
    /// Whether the language server has ever answered.
    ///
    /// Once it has, a failure is Antigravity being closed or restarted — its
    /// port changes every launch — not an account that cannot be read. Falling
    /// back to the request count then *replaces* a percentage with a plain
    /// number, and a ring that reads 8% one minute and 31 the next looks broken
    /// rather than degraded.
    private var everBridged = false

    init(readLocalQuota: (@Sendable () async -> [LimitWindow]?)? = nil) {
        self.localSession = ProviderHTTP.session(delegate: LocalhostTrust())
        self.readLocalQuota = readLocalQuota
    }

    nonisolated var signInRoute: SignInRoute {
        .openApp(bundleID: "com.google.antigravity", name: "Antigravity")
    }

    nonisolated func forgetCachedCredential() {}

    nonisolated func account() -> ProviderAccount? {
        return ProviderAccount(
            label: nil,
            plan: nil,
            source: "Antigravity",
            manageURL: URL(string: "https://antigravity.google")
        )
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        // This is the only live quota path. Antigravity manages the token and
        // the remote refresh; AI Notch never asks macOS for its Keychain data.
        if let windows = await localQuota(), !windows.isEmpty {
            everBridged = true
            return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                    fidelity: .official, status: .ok, windows: windows,
                                    headlineID: "gemini-weekly")
        }

        // Antigravity has answered before and is not answering now: keep the
        // last percentage, dimmed and dated, rather than swapping in a count.
        // `credentialExpired` is the store's word for "still true, just old".
        if everBridged { throw UsageProviderError.credentialExpired }

        // Without the local quota service, our own count is the only number
        // available — reported as a *count*, with no
        // `usedFraction`, which is a case the model already knows: the cell
        // prints the number and the ring draws its track with no arc, because
        // there is no limit to be a fraction of.
        //
        // Better than the dash it showed before, which read as broken rather
        // than as "Google will not answer for this account".
        let activity = AntigravityActivity.read()
        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            // Ours, not Google's. The tooltip prefixes a `~` on the strength of
            // this, which is exactly the claim being made.
            fidelity: .derived,
            status: .ok,
            windows: [
                LimitWindow(id: "requests",
                            label: "Requests today · no limit published",
                            used: activity.requestsToday)
            ]
        )
    }

    /// Ask Antigravity's language server, if it is running.
    ///
    /// Returns nil rather than throwing when it is not: Antigravity being
    /// closed is the ordinary case, not a fault, and the caller has an honest
    /// answer to fall back to.
    private func localQuota() async -> [LimitWindow]? {
        try? Task.checkCancellation()
        if let readLocalQuota { return await readLocalQuota() }
        guard !Task.isCancelled, let fresh = AntigravityBridge.discover() else { return nil }
        return try? await AntigravityBridge.quota(from: fresh, session: localSession)
    }

    /// Turns a quota summary into limit windows.
    ///
    /// Written from the message names in Antigravity's own binary
    /// (`QuotaSummaryGroup`, `QuotaSummaryBucket`, `QuotaLimit`) because no
    /// licensed account was available to answer with a real body. So it is
    /// deliberately suspicious of itself: anything without a positive limit, or
    /// claiming more used than the limit allows, is dropped rather than shown.
    /// An empty result sends the caller to the honest fallback, which is the
    /// right outcome for a shape that turns out to differ.
    static func windows(in data: Data) -> [LimitWindow] {
        struct Response: Decodable {
            struct Bucket: Decodable {
                let name: String?
                let displayName: String?
                let used: Double?
                let limit: Double?
                let resetTime: String?
            }
            struct Group: Decodable {
                let displayName: String?
                let buckets: [Bucket]?
            }
            let quotaGroups: [Group]?
            let buckets: [Bucket]?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        let buckets = (decoded.quotaGroups?.flatMap { $0.buckets ?? [] } ?? []) + (decoded.buckets ?? [])

        return buckets.compactMap { bucket in
            guard let limit = bucket.limit, limit > 0,
                  let used = bucket.used, used >= 0, used <= limit * 1.5
            else { return nil }
            let label = bucket.displayName ?? bucket.name ?? "Usage"
            return LimitWindow(id: bucket.name ?? label,
                               label: label,
                               usedFraction: used / limit,
                               resetsAt: bucket.resetTime.flatMap(AntigravityCredentials.parse))
        }
    }

    /// The plan's display name, for the message the cell shows.
    static func tier(in data: Data) -> String {
        struct Response: Decodable {
            struct Tier: Decodable {
                let id: String?
                let name: String?
                let isDefault: Bool?
            }
            let allowedTiers: [Tier]?
            let currentTier: Tier?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return "Gemini"
        }
        // `currentTier` appears once a tier has been chosen; before that the
        // default among the allowed ones is what you are on.
        let tier = decoded.currentTier
            ?? decoded.allowedTiers?.first(where: { $0.isDefault == true })
            ?? decoded.allowedTiers?.first
        return tier?.name ?? "Gemini"
    }
}
