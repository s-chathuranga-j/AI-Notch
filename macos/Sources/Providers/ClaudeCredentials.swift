import Foundation
import Security

/// The OAuth token Claude Code keeps in the login keychain.
///
/// AI Notch only ever *reads* this item. Refreshing is deliberately left to
/// Claude Code: minting a new token would mean writing a credential this app
/// does not own, so when the token expires the notch says `needsAuth` and waits
/// for Claude Code to refresh it in the ordinary course of being used.
struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date
    /// "pro", "max", and so on — enough to show which plan the readings are for.
    let subscriptionType: String?

    var isExpired: Bool { expiresAt <= Date() }

    /// The service the default profile's token is filed under. Other profiles
    /// get a suffix — see `ClaudeProfile.keychainService`.
    static let service = ClaudeProfile.defaultKeychainService

    /// Reads the default profile. Kept for callers that predate profiles.
    static func load() throws -> ClaudeCredentials { try ClaudeKeychain.default.load() }
    static func forgetCached() { ClaudeKeychain.default.forgetCached() }

    /// The keychain read itself, for one service name.
    ///
    /// `ClaudeKeychain` decides *whether* to read; this is what happens when it
    /// does. Every failure is turned into the status the UI should show, and
    /// the raw OSStatus is logged so "not found" and "refused" stay distinct.
    ///
    /// Reads the newest item under this service, rather than asking for "one"
    /// and trusting the answer. Claude Code files a new item on every token
    /// rotation instead of updating one in place, so an account used for
    /// months accumulates several under the same service name. A plain
    /// `kSecMatchLimitOne` query gives no ordering guarantee across them, and
    /// the failure it produces is silent: the app reads an old, expired
    /// duplicate, the ring shows "Waiting for the first reading…" forever, and
    /// nothing about that message suggests a valid token is sitting right next
    /// to the one that was picked. `KeychainItem.newest` finds it via
    /// attributes and a persistent reference, neither of which needs
    /// authorization to read — only this second, targeted fetch of the
    /// winner's actual data does, which is why it costs the same single prompt
    /// as before, per profile.
    fileprivate static func read(service: String) throws -> ClaudeCredentials {
        guard let winner = try KeychainItem.newest(service: service) else {
            Log.usage.error("keychain read failed: no item under \(service, privacy: .public)")
            throw UsageProviderError.needsAuth
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: winner.persistentRef,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            // Automatic checks cannot summon the password dialog. A denied
            // query becomes the Settings row's explicit Allow access action.
            Log.usage.error("keychain read of \(service, privacy: .public) failed: OSStatus \(status) (\(Self.explain(status), privacy: .public))")
            throw Self.wasRefused(status)
                ? UsageProviderError.accessDenied
                : UsageProviderError.needsAuth
        }

        struct Payload: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                /// Milliseconds since the epoch.
                let expiresAt: Double
                let subscriptionType: String?
            }
            let claudeAiOauth: OAuth
        }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw UsageProviderError.needsAuth
        }

        return ClaudeCredentials(
            accessToken: payload.claudeAiOauth.accessToken,
            expiresAt: Date(timeIntervalSince1970: payload.claudeAiOauth.expiresAt / 1000),
            subscriptionType: payload.claudeAiOauth.subscriptionType
        )
    }

    /// Which keychain refusal this was. "Not found" means Claude Code has never
    /// signed in; -25308 or -128 mean the item exists but this app is not on its
    /// access list. Those need entirely different advice, so the log says which.
    /// Whether macOS refused a credential that exists, rather than failing to
    /// find one.
    ///
    /// `errSecAuthFailed` and `userCanceled` are what Deny produces;
    /// `interactionNotAllowed` is the same refusal arriving without a prompt.
    /// All three mean the item is there and we were not let in.
    static func wasRefused(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed
            || status == errSecUserCanceled
            || status == errSecInteractionNotAllowed
            || status == errSecInDarkWake
    }

    static func explain(_ status: OSStatus) -> String {
        switch status {
        case errSecItemNotFound:          return "no such item — Claude Code has not signed in"
        case errSecInteractionNotAllowed: return "access not permitted without interaction"
        case errSecUserCanceled:          return "the access prompt was dismissed or denied"
        case errSecAuthFailed:            return "authorisation failed"
        default:
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown"
        }
    }
}

/// One profile's token, read as rarely as the keychain allows.
///
/// One of these per `ClaudeProfile`, because each profile's token is a separate
/// keychain item with its own access list: macOS prompts once per item, and a
/// cache shared between them would hand the personal token to the work ring.
final class ClaudeKeychain: @unchecked Sendable {
    let service: String

    /// Read once, then held until the token expires — see `CredentialCache`.
    /// Claude Code rotates this roughly hourly, so this is about one keychain
    /// read an hour instead of two a minute.
    private let cache = CredentialCache<ClaudeCredentials> { $0.isExpired }

    /// Where the learned token lifetime is kept. Only a duration — never the
    /// token, never anything read from inside the item.
    private let defaults: UserDefaults

    init(service: String, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    convenience init(profile: ClaudeProfile) {
        self.init(service: profile.keychainService)
    }

    /// The default profile's reader, shared so that every caller that predates
    /// profiles keeps sharing one cache — and so one prompt.
    static let `default` = ClaudeKeychain(service: ClaudeProfile.defaultKeychainService)

    /// Reads whatever is stored, expired or not. Judging expiry is the caller's
    /// job, because "signed out" and "the token has aged out overnight" call for
    /// different behaviour and only one of them is worth alarming anyone about.
    ///
    /// Before a read that could prompt, this asks whether the token can still
    /// be valid at all. Claude Code files a new item each time it renews, so the
    /// newest item's modification date is when the token in it was issued, and
    /// after one successful read we know how long such a token lasts. An item
    /// older than that holds a token that has certainly expired: asking for the
    /// password to read it could only end in "expired", so it is not asked. A
    /// forced reload ("Allow access…") still always reads.
    func load(allowingInteraction: Bool = false, forceReload: Bool = false) throws -> ClaudeCredentials {
        try KeychainItem.withInteraction(allowed: allowingInteraction) {
            if forceReload {
                cache.forget()
            } else if !(cache.cached.map { !$0.isExpired } ?? false),
                      let lifetime = learnedLifetime,
                      let issued = KeychainItem.modifiedAt(service: service),
                      Self.mustHaveExpired(issuedAt: issued, lifetime: lifetime, now: Date()) {
                throw UsageProviderError.credentialExpired
            }
            var stamp: Date?
            let credentials = try cache.value(
                itemModifiedAt: {
                    stamp = KeychainItem.modifiedAt(service: service)
                    return stamp
                },
                reload: { try ClaudeCredentials.read(service: service) }
            )
            if let stamp, let lifetime = Self.lifetime(expiresAt: credentials.expiresAt,
                                                       issuedAt: stamp, previous: learnedLifetime) {
                defaults.set(lifetime, forKey: lifetimeKey)
            }
            return credentials
        }
    }

    private var lifetimeKey: String { "claudeTokenLifetime.\(service)" }

    private var learnedLifetime: TimeInterval? {
        let value = defaults.double(forKey: lifetimeKey)
        return value > 0 ? value : nil
    }

    /// The longest lifetime seen. Longest, because an item rewritten after
    /// its token was issued makes one observation look shorter than the
    /// truth, and underestimating would skip a read that could have worked.
    /// Values outside five minutes to thirty days are not believed.
    static func lifetime(expiresAt: Date, issuedAt: Date, previous: TimeInterval?) -> TimeInterval? {
        let observed = expiresAt.timeIntervalSince(issuedAt)
        guard observed >= 5 * 60, observed <= 30 * 24 * 3600 else { return nil }
        return max(observed, previous ?? 0)
    }

    /// True when a token issued at `issuedAt` cannot still be valid. A minute
    /// of slack covers the gap between issuing and filing the item.
    static func mustHaveExpired(issuedAt: Date, lifetime: TimeInterval, now: Date) -> Bool {
        issuedAt.addingTimeInterval(lifetime + 60) <= now
    }

    var cachedCredential: ClaudeCredentials? { cache.cached }

    /// Forget the held copy. Call when the server rejects it: signing into a
    /// different account replaces the keychain item, and the copy in hand is
    /// then wrong despite not having expired.
    func forgetCached() { cache.forget() }
}
