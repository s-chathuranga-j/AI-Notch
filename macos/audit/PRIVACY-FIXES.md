# Privacy fixes in AI Notch 0.2.0

The historical `PRIVACY-REVIEW.md` and its hashes describe the pre-fix build. This document describes the remediation; it does not overwrite that evidence.

- **Credential routing:** ZCode keys are accepted only from the supported Z.ai/BigModel coding-plan identities with an explicit, exact HTTPS host. Missing hosts, unrelated hosts, deceptive subdomains, URL credentials and nonstandard ports are rejected. There is no fallback from an unrelated provider host to Z.ai.
- **Disabling accounts:** Provider tasks are tracked and cancelled individually. A per-account generation invalidates results from before a disable/re-enable cycle. Queued disabled providers are skipped and cancelled or outdated responses cannot restore archived data. Single-provider refresh uses the same checks. Turning an account back on restores its row immediately.
- **Credential access:** Disabled summaries do not call account readers. Disabling clears held credentials. Invalidation during a Keychain reload prevents it from repopulating the cache or proceeding with the old credential. The duplicated Claude actor credential cache was removed.
- **Session monitoring:** The same provider switch starts/stops each account's monitor. Stop clears session data, and late timer/file events are ignored. Personal and work Claude profiles remain independent.
- **Logging:** Removed raw Cursor responses, Codex subprocess buffers, credential-expiry/profile-path logging, and error-description logging in the affected paths. The unused WebKit provider, JavaScript discovery hooks and Perplexity website configuration were removed entirely.
- **HTTP:** Direct provider requests use nonpersistent sessions without response caches, cookie storage or credential storage. Exact destination checks apply before sending and after receiving; redirects are rejected rather than followed with credentials. The local language-server session uses the same redirect policy. Loopback certificate handling remains scoped to loopback.
- **Subprocesses:** Codex provider cancellation reaches the spawned app server, including cancellation before process launch. Live Codex data still depends on the vendor's installed executable and its network/configuration behavior. That dependency is now described accurately, not called an offline integration. Antigravity's local CSRF endpoint is no longer retained between polls.
- **First-run consent:** Accounts require a one-time explicit enable when upgrading from the version that implicitly enabled everything. Newly discovered profiles also require enablement. Subsequent explicit choices persist.
- **UI and license:** Removed the product-facing attribution footer, its external X link, and the release-note attribution text. Preserved the MIT notice and provenance in LICENSE/UPSTREAM.md, now bundled with the application. Added personal/work Claude setup guidance to Settings and README.

Direct HTTPS authentication traffic to enabled AI providers remains necessary for live usage. Already-sent requests cannot be recalled. Old macOS logs are not purged; future raw logging stops, and AI Notch clears its legacy HTTP cache on launch. No claim is made that third-party vendor subprocesses, OS backups or previously collected diagnostics are controlled by these changes.

Regression tests cover credential routing, disabled Settings reads, queued and in-flight requests, cache invalidation, HTTP destination/redirect policy, account opt-in and monitor isolation. All provider/account fixtures used by the new tests are synthetic. The old audit reproduction file remains a record of the pre-fix investigation; `Tests/PrivacyRegressionTests.swift` is the maintained regression suite.

## Verification completed 2026-09-07

557 tests passed with zero failures. The final Debug build succeeded and its code signature verified. Both required license documents were verified byte-for-byte in the bundle. The Settings keyboard shortcut was manually checked in the running demo: it opens the real settings panel, shows the personal/work guidance, and contains no product-facing attribution footer. Live provider connectivity was not exercised.
