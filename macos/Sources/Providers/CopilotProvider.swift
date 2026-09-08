import Foundation
import os

/// Reads GitHub Copilot quotas from GitHub's own entitlement endpoint, with
/// the token the GitHub CLI already holds — see `CopilotCredentials` for how.
///
/// The numbers are GitHub's, so this is `.official`. The endpoint is internal,
/// though: it is the one VS Code's quota banner reads, not a published API,
/// and GitHub can change it or refuse a CLI token on it. So every failure
/// degrades to a status the UI can render honestly, a 429 backs off on a
/// schedule that outlives the process, and nothing about the response is
/// logged beyond its status code.
actor CopilotProvider: UsageProvider {
    nonisolated let id = "copilot"
    nonisolated let displayName = "Copilot"
    nonisolated let glyph = ProviderGlyph.copilot

    static let endpoint = URL(string: "https://api.github.com/copilot_internal/user")!

    private let session: URLSession
    private let archive: UsageArchive
    private let loadCredentials: (CodexBridge.ProcessCancellation) throws -> CopilotCredentials.Credential
    private let environment: [String: String]
    private let hostsFile: URL

    /// The token, held between polls so gh is not spawned once a minute.
    /// Never expires on its own — GitHub is the one who knows when it is
    /// wrong, and says so with a 401, which is what `forget()` is for.
    private let credentials = CredentialCache<CopilotCredentials.Credential>(isExpired: { _ in false })

    /// Set when the endpoint returns 429. Until it passes, refreshes are
    /// skipped without touching the network — the same bargain GLM's makes.
    private var retryNoEarlierThan: Date?
    private var consecutiveRateLimits = 0

    /// Facts about the account from the last successful answer, for the
    /// settings row. `nonisolated(unsafe)` because `account()` reads them off
    /// the actor; the worst a race can do is show the previous plan for one
    /// row-draw.
    nonisolated(unsafe) private var lastKnownPlan: String?
    nonisolated(unsafe) private var lastCredentialSource: String?

    init(session: URLSession = ProviderHTTP.session(),
         archive: UsageArchive = UsageArchive(),
         environment: [String: String] = ProcessInfo.processInfo.environment,
         hostsFile: URL = CopilotCredentials.hostsFileURL,
         loadCredentials: ((CodexBridge.ProcessCancellation) throws -> CopilotCredentials.Credential)? = nil) {
        self.session = session
        self.archive = archive
        self.environment = environment
        self.hostsFile = hostsFile
        self.loadCredentials = loadCredentials
            ?? { try CopilotCredentials.load(environment: environment, cancellation: $0) }
        self.retryNoEarlierThan = archive.loadBackoffUntil(providerID: id)
    }

    nonisolated var signInRoute: SignInRoute {
        .guidance("Copilot rides on the GitHub CLI's login. Run gh auth login in Terminal with the "
                  + "account that holds your Copilot subscription, then enable Copilot here. "
                  + "A token in COPILOT_GITHUB_TOKEN is used instead when the app is launched with one.")
    }

    nonisolated func forgetCachedCredential() {
        credentials.forget()
        lastCredentialSource = nil
        lastKnownPlan = nil
    }

    /// Whose account this reads, without spawning anything.
    ///
    /// A fetch has to happen before the source is certain; until then the
    /// environment variable and gh's own `hosts.yml` are the prompt-free
    /// signs that there is a credential to borrow at all. Neither is a
    /// promise that GitHub will honour it on the quota endpoint — the fetch
    /// answers that, and the row's status follows.
    nonisolated func account() -> ProviderAccount? {
        let login = CopilotCredentials.login(hostsFile: hostsFile)
        let hasEnvironmentToken = !(environment[CopilotCredentials.environmentVariable] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let source = lastCredentialSource
            ?? (hasEnvironmentToken ? CopilotCredentials.environmentSource : nil)
            ?? (login != nil ? CopilotCredentials.cliSource : nil)
        guard let source else { return nil }
        return ProviderAccount(
            label: source == CopilotCredentials.cliSource ? login : nil,
            plan: lastKnownPlan.map(Self.planName),
            source: source,
            manageURL: URL(string: "https://github.com/settings/copilot/features")
        )
    }

    /// GitHub's plan slugs, made readable: `individual_pro` → "individual pro".
    static func planName(_ slug: String) -> String {
        slug.replacingOccurrences(of: "_", with: " ")
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        if let retryNoEarlierThan, retryNoEarlierThan > Date() {
            let remaining = retryNoEarlierThan.timeIntervalSinceNow
            Log.usage.debug("copilot: skipping fetch, backing off for \(remaining, format: .fixed(precision: 0))s")
            throw UsageProviderError.rateLimited(retryAfter: remaining)
        }

        let credential = try await currentCredential()

        do {
            let data = try await fetch(token: credential.token)
            let payload = try CopilotUsage.parse(data)
            guard !payload.windows.isEmpty else {
                throw UsageProviderError.nothingMetered("GitHub reports no Copilot quotas for this account")
            }

            consecutiveRateLimits = 0
            retryNoEarlierThan = nil
            archive.saveBackoffUntil(nil, providerID: id)
            lastKnownPlan = payload.plan
            lastCredentialSource = credential.source

            return ProviderSnapshot(
                id: id,
                displayName: displayName,
                glyph: glyph,
                fidelity: .official,
                status: .ok,
                windows: payload.windows,
                headlineID: payload.headlineID
            )
        } catch UsageProviderError.rateLimited(let retryAfter) {
            consecutiveRateLimits += 1
            retryNoEarlierThan = Date().addingTimeInterval(retryAfter)
            archive.saveBackoffUntil(retryNoEarlierThan, providerID: id)
            Log.usage.notice("copilot: rate limited (\(self.consecutiveRateLimits)x), next attempt in \(retryAfter, format: .fixed(precision: 0))s")
            throw UsageProviderError.rateLimited(retryAfter: retryAfter)
        }
    }

    /// The held token, or a fresh one from gh.
    ///
    /// Off the actor: spawning a process and waiting on its pipe is blocking
    /// work, and doing it here would stall every other read this provider
    /// owes. Cancellation — the provider switch — reaches the child process.
    private func currentCredential() async throws -> CopilotCredentials.Credential {
        let cancellation = CodexBridge.ProcessCancellation()
        let cache = credentials
        let load = loadCredentials
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let worker = Task.detached(priority: .utility) {
                try cache.value(reload: { try load(cancellation) })
            }
            let credential = try await worker.value
            try Task.checkCancellation()
            return credential
        } onCancel: { cancellation.cancel() }
    }

    private func fetch(token: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        Log.usage.debug("GET api.github.com/copilot_internal/user")
        let (data, response) = try await ProviderHTTP.data(for: request, using: session, hosts: ["api.github.com"])
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        Log.usage.debug("copilot endpoint answered \(status)")

        if status == 401 || status == 403 {
            // Refused: the held copy is wrong, or was never good enough for
            // this endpoint. Drop it so the next attempt asks gh again — a
            // fresh `gh auth login` is the fix, and it has to be picked up.
            credentials.forget()
            lastCredentialSource = nil
            throw UsageProviderError.needsAuth
        }
        if status == 404 {
            throw UsageProviderError.nothingMetered("GitHub has no Copilot quota to report for this account")
        }
        if status == 429 {
            throw UsageProviderError.rateLimited(
                retryAfter: ProviderBackoff.wait(
                    forAttempt: consecutiveRateLimits,
                    retryAfter: ProviderBackoff.retryAfter(from: response)
                )
            )
        }
        guard (200..<300).contains(status) else {
            throw UsageProviderError.badResponse(status: status)
        }
        return data
    }

    /// GitHub asks every client to say who it is.
    static var userAgent: String {
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "AI-Notch/\(version) (macOS)"
    }
}
