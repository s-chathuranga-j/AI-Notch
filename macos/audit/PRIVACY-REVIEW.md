# AI Notch privacy and outbound-data review

Reviewed 2026-09-06. Scope: the AI Notch 0.1.0 source in this workspace and its locally built Debug app, not a blanket assessment of every CodeNotch release. Source and binary hashes are in `audited-sha256.json`.

## Conclusion

**Live mode is not offline.** AI Notch sends account credentials to provider services to request usage and subscription information. Normally, the usage percentages, reset dates and plan information flow back from those services into the app. No separate upload of a combined subscription inventory, email list, session transcripts or billing details was found in the active app paths. No AI Notch backend, advertising/analytics SDK, crash uploader or publisher update service was found in this derivative.

That conclusion is not a claim that nothing sensitive leaves the Mac: bearer tokens, a Cursor account identifier/session token, and GLM API keys do leave it. The recipient can identify the account and observe the usage checks. A conditional ZCode credential-selection bug can route an unrelated provider's key to Z.ai. This and the control/logging issues below should be fixed before treating the app as privacy-hardened.

## Active outbound paths

| Provider | Destination and operation | Outbound data | Where the credential comes from |
| --- | --- | --- | --- |
| Claude Code, including discovered profiles | HTTPS GET `api.anthropic.com/api/oauth/usage` | OAuth bearer access token; fixed `anthropic-beta` header. No request body or subscription inventory. | Claude Code login Keychain item for the profile. |
| Cursor | HTTPS GET `cursor.com/api/usage-summary` | `WorkosCursorSessionToken` cookie containing account ID and access token; JSON Accept header. No request body. | Cursor's local SQLite state. |
| Antigravity | HTTPS POST `cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` | Google bearer token and `{"metadata":{"pluginType":"GEMINI"}}`. | Keychain service `gemini`, account `antigravity`. |
| Antigravity quota fallback | HTTPS POST `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` | Google bearer token and `{}`. | Same credential. |
| Antigravity local quota bridge | HTTPS POST `127.0.0.1:<discovered port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` | Local CSRF token and `{"forceRefresh":true}`. | Language-server process arguments and discovered listening ports. This leg stays on the Mac, but refreshing can cause the language server to contact its backend. |
| GLM | HTTPS GET `api.z.ai/api/monitor/usage/quota/limit` or `open.bigmodel.cn/api/monitor/usage/quota/limit` | Raw API/access key in the Authorization header. No request body. | Claude Code settings, ZCode configuration/credentials, or OpenCode auth file. |
| Codex | Local stdin/stdout to a spawned `codex app-server` | Initialization with AI Notch client name/version, then `account/rateLimits/read`. | The subprocess manages its own credentials/configuration. AI Notch does not include a token in the pipe request. The subprocess can make network calls; their exact destinations and ancillary behavior were not verified in this audit. |

Evidence: [Claude](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/ClaudeOAuthProvider.swift>), [Cursor request](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/CursorLocalProvider.swift>), [Cursor cookie](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/CursorCredentials.swift>), [Google](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/AntigravityProvider.swift>), [local bridge](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/AntigravityBridge.swift>), [GLM request](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/GLMProvider.swift>), [credential selection](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/GLMCredentials.swift>), [Codex subprocess](</Users/chathurangajayasinghe/Workspaces/4Forge Workspace/AINotch/Sources/Providers/CodexBridge.swift>).

The Antigravity path performs its direct Google account request **before** attempting local quota; it is not a loopback-only integration. The Codex rollout fallback reads local files, but the primary Codex path is a live app-server query. Comments in `CodexLocalProvider.swift` and `CodexCredentials.swift` describing usage as having no network access are outdated.

Live startup registers all supported providers, initially enabled unless preferences disable them. It refreshes at launch, on wake and manual refresh, normally every 60 seconds while busy or every five minutes while idle, subject to errors/backoff. See `AppDelegate.swift`, `Preferences.swift` and `UsageStore.swift`.

## Confirmed findings

### 1. Conditional cross-provider key disclosure through ZCode — high priority

`GLMCredentials.zcodePlanKey` accepts any enabled provider ID containing `coding-plan`. It does not verify that the configured host belongs to Z.ai/BigModel. `consoleBase` maps other hosts to `https://api.z.ai`; `GLMProvider.fetch` sends the selected key there.

A synthetic configuration named `builtin:other-vendor-coding-plan`, with host `api.example.invalid`, was accepted and returned as a credential for `https://api.z.ai`. The test did not send the key. The source establishes the subsequent send when this credential source is selected and GLM polling is enabled. This requires a matching local configuration; no claim is made that the user's actual accounts meet that condition or that such a disclosure already occurred.

Fix: accept only explicitly supported Z.ai provider identities and validated Z.ai/BigModel hosts. Reject unrelated or ambiguous configurations rather than defaulting to a recipient.

### 2. Disabling a provider is not an immediate network/privacy boundary — high priority

`UsageStore.refresh` computes its enabled-provider list once, then awaits each provider sequentially. Switching off a queued provider does not remove it from that saved list. Its fetch can therefore begin **after** it was disabled. `snapshot(from:)` also saves its response without rechecking whether it is still enabled, restoring data that the disable action cleared. An already in-flight request is not cancelled either.

The synthetic reproduction paused the first provider, disabled the second, then resumed the first. The second was fetched once and its reading reappeared in the archive. This is stronger than merely saying an already-sent request cannot be recalled.

Fix: recheck connection state immediately before each fetch and before accepting/persisting results, invalidate old refresh generations, and cancel provider tasks when disabled.

### 3. Settings reads disabled providers' accounts — medium priority

`UsageStore.providerSummaries` unconditionally calls `provider.account()` for every provider, including disabled ones. The Claude and Antigravity implementations may read their Keychain credentials; Cursor and Codex read local identity/account state; GLM reads its configured key sources. The settings view requests these summaries when opened or brought forward.

The synthetic test confirmed one account read for a disabled provider. This is local access, not proof of an external send, but it contradicts a stronger promise that disabling a provider prevents its credentials being read. Separately, activity monitors run independently of usage-provider toggles. Disabling usage does not stop local session monitoring.

Fix: return a disabled summary without calling `account()`; make the scope of activity monitoring explicit or connect it to the same privacy control.

### 4. Subscription-related responses are logged without redaction — medium priority

`CursorLocalProvider.swift:46` writes the first 900 characters of the raw usage response to unified debug logging with `privacy: .public`. That can include plan, spending and quota information returned by Cursor. Here `public` means unredacted in local logs, not publicly posted on the Internet. No log-upload mechanism was found, but diagnostics collected or shared by another tool can carry this material off the device.

`CodexBridge.swift:95` also logs the first 400 bytes of unexpected app-server output at error level, unredacted. Its exact content depends on the subprocess. The unused WebSessionProvider logs raw response/probe data and discovered request URLs too. These are unnecessary retention/exposure paths even though they are not an AI Notch network uploader.

Fix: log status codes and sanitized categories/counts only; remove raw response and subprocess-output logging.

## Local storage, inactive code, and external links

`UsageArchive` writes JSON to local UserDefaults under the app's `com.fourforge.ainotch` domain: provider ID/name/glyph, fidelity, usage windows and fetch time, plus retry deadlines. Its archive schema does not contain access tokens, account email or a separate subscription-plan field. It is ordinary local storage, not an encrypted credential vault. Account labels/plans are otherwise read for UI display; credentials may remain in memory. The app does not add cloud synchronization, though OS backup or separately configured diagnostic tools are outside this source review.

Session monitors read local files, SQLite state, process liveness and transcript metadata/content to infer status. No network sender was found in those monitors, and no active request construction takes session titles, transcripts or source code as its payload.

`WebSessionProvider` and the Perplexity definition remain compiled source, but `AppDelegate` sets `webProviders = []`. Thus the browser provider and `AINOTCH_DISCOVER` branch have no registered provider to run against. If enabled in the future, loading the vendor webpage would also load whatever third-party resources that page uses; this audit's active-domain list would no longer be complete.

The attribution link to `x.com/hivinz_` and account-management links open only through a user action. No subscription details are appended to those URLs. The destination browser/site can still perform its ordinary network requests and tracking.

The original Sparkle dependency, feed and publisher public key are absent from the project and built Info.plist. `Updater` exposes version information only. Native binary dependencies inspected were Apple/system libraries; the tested Debug bundle also contains Apple testing frameworks. No third-party analytics framework was found. The app is unsandboxed, so its destination behavior is enforced by code, not by an OS network allowlist. Its URLSession callers do not add an app-level cross-host redirect policy. This is a hardening opportunity, not a demonstrated redirected-credential leak. LocalhostTrust's custom certificate acceptance is restricted to loopback hosts.

## Verification and limits

- Traced request construction, credential sources, provider registration, subprocess IPC, WebKit code, storage, logs and session-monitor paths.
- Inspected the built Info.plist, executable and debug-library dependencies, embedded frameworks, and code signature. Signature verification passed; this establishes bundle integrity, not a privacy guarantee.
- Sampled the already-running app PID's TCP/UDP socket inventory ten times over roughly five seconds. No sockets were observed. This is a short snapshot and does not establish historical or future absence of traffic, nor rule out traffic delegated to other processes.
- Ran three audit-only XCTest cases with synthetic keys/accounts, isolated preferences and no real provider requests. They produced four failed privacy assertions: disabled account access, post-disable fetch, restored archive entry, and incorrect GLM credential routing. See `test-results.txt` and `PrivacyAuditReproduction.swift`.
- The earlier 542-test pass did not exercise these privacy guarantees. Passing that suite was not a security audit.
- No real credentials, account databases, plaintext network payloads or historical system logs were extracted for this review. No live-provider requests were triggered. The user's current account configuration was not inspected for the conditional GLM bug.
- Codex and Antigravity subprocess/backend behavior, OS services, proxies/VPNs, DNS, provider redirects and provider-side retention were not audited end to end. Therefore “no evidence of a separate AI Notch upload” must not be read as proof that all future traffic stays within the listed domains.

No application-source fixes were made in this review. The probes were removed from the normal test target after execution and kept in `audit/` so they do not turn the ordinary test suite red. For reproduction, temporarily copy `PrivacyAuditReproduction.swift` into `Tests/`, regenerate the Xcode project, and run only `AINotchTests/PrivacyAuditReproduction` against a separate derived-data directory. They are intentionally failing checks of the current unsafe behavior, not tests that endorse it.
