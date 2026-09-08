# AI Notch product and implementation roadmap

This document is the shared specification for AI Notch. It records the behavior discussed so far, the current implementation, the Windows gaps, and work that can be assigned independently to another agent.

## Product goal

AI Notch is a small desktop companion that shows AI subscription usage and current coding activity without requiring the user to open each provider's dashboard. It should feel like a native part of the desktop: compact at rest, easy to reveal, visually legible at a glance, and private by default.

The repository contains separate platform applications:

- `macos/` is the native SwiftUI/AppKit implementation and the reference for behavior and visual language.
- `windows/` is the Windows implementation built with Electron. It should match the Mac product behavior while using Windows conventions for the tray, screen placement, credentials, and startup.

The two applications may use different platform frameworks, but they should share the same product language, privacy guarantees, usage semantics, and provider labels.

## Current state

### macOS

The Mac application is the mature reference implementation. It currently provides:

- Claude, Codex, Cursor, GLM/Z.ai, and Antigravity usage where the provider exposes usable local credentials or a local bridge.
- Experimental GitHub Copilot quotas, read with the GitHub CLI's login (`gh auth token`) or `COPILOT_GITHUB_TOKEN`, matching the Windows v0.2.0 integration.
- Separate discovered Claude profiles, including personal and work configurations.
- Circular provider rings with color bands and reset information.
- Current coding activity indicators for supported local tools.
- Top, bottom, left, and right screen-edge placement.
- Compact, hover-expanded, always-visible, and hidden presentation modes.
- Menu bar controls and optional Dock presence.
- Per-provider opt-in and immediate cancellation when a provider is disabled.
- Local usage history needed by the UI.
- No publisher telemetry, analytics, automatic updater, or browser-cookie extraction.
- Explicit provider destinations, redirect denial, ephemeral networking, and cancellation of subprocess/network work.

The source was moved into `macos/` without changing the installed Mac application. All 557 Mac tests passed after the move.

### Windows preview v0.1.0

The first published Windows preview contains:

- A portable x64 build for Intel/AMD Windows PCs.
- A portable ARM64 build for Windows on ARM.
- System tray controls.
- Claude personal/work profile discovery under `%USERPROFILE%`.
- Codex usage through `codex app-server`.
- Per-account enable switches and a manual retry action.
- Top, bottom, left, and right placement options.
- A sandboxed renderer with narrow IPC and no renderer network access.
- No publisher telemetry, analytics, updater, or credential persistence.

The v0.1.0 release was built and previewed on macOS. Its provider parsing and privacy tests pass, but it has not yet received full native Windows validation.

## Reported Windows problems

These are confirmed product gaps in the v0.1.0 implementation:

1. Usage is drawn as horizontal progress bars instead of the circular rings used on macOS.
2. The collapsed notch remains a visible 260 x 64 panel and therefore feels permanently open.
3. Left and right placement moves the horizontal panel to the side without changing the layout to a vertical notch.
4. Codex usage works, but Claude usage does not work for the tested Windows installation.
5. Error states need to explain the exact local action the user can take instead of leaving an empty or indefinite loading state.

The first three problems are direct consequences of the current Windows layout code and do not require more diagnosis.

Claude Code officially stores subscription credentials in `%USERPROFILE%\.claude\.credentials.json` on Windows, or in the directory selected by `CLAUDE_CONFIG_DIR`. The application only reads this file; it must never refresh, rewrite, or delete it. Some Windows Claude Code versions have written `expiresAt` as `0` or omitted expiry metadata during token rotation. AI Notch must allow Anthropic's endpoint to validate such a token instead of rejecting it locally solely because the local expiry field is zero or missing. A positive, valid-looking expiry in the past can still be reported as expired before a request.

## Windows v0.2 target

### Notch presentation

At rest, the notch should occupy only a small edge handle:

- Top/bottom: a thin horizontal handle centered on the selected display edge.
- Left/right: a thin vertical handle centered on the selected display edge.
- The compact handle expands when the pointer enters it and collapses shortly after the pointer leaves.
- Expanding and collapsing must resize and reposition the native window, not merely hide content inside a permanently large transparent window.
- Settings remain open until closed explicitly.
- The tray can restore the notch if it is hidden.

Visibility choices:

- **On hover:** show the small edge handle at rest and expand on pointer entry.
- **Always:** keep the usage presentation expanded.
- **Hidden:** hide the notch completely while retaining the tray icon. The tray is the recovery path.

The selected visibility mode and edge are local preferences. Changing either should take effect immediately and persist across launches.

### Orientation

Top and bottom placements use a horizontal flow. Left and right placements use a vertical flow.

- In the horizontal layout, enabled provider rings sit side by side.
- In the vertical layout, enabled provider rings stack from top to bottom.
- Expanded details follow the same orientation and remain readable in the narrower side panel.
- Rounded corners should attach visually to the selected edge: bottom corners for a top notch, top corners for a bottom notch, right corners for a left notch, and left corners for a right notch.
- Screen placement should respect the Windows work area so the taskbar is not covered.
- Display changes should cause the notch to recalculate its bounds.

### Usage rings

The Mac application is the visual reference.

- Each enabled account gets a circular ring.
- The ring starts at 12 o'clock and fills clockwise by percentage used.
- The center shows a rounded percentage.
- A neutral track shows the unused portion.
- Normal usage uses the provider/accent color, elevated usage uses an amber warning color, and near-exhausted usage uses a red danger color.
- Missing or failed data must show an error state instead of a fabricated zero-percent ring.
- Expanded content shows one ring per available usage window, such as Session and Weekly.
- Reset time and last-updated time appear as secondary text.
- Personal and work accounts remain separate rings even when they belong to the same provider.
- Percentages are clamped for drawing only. The parser should retain accurate provider semantics and reject malformed values.

### Claude on Windows

Credential discovery must support:

- `%USERPROFILE%\.claude\.credentials.json` for the default personal profile.
- `%USERPROFILE%\.claude-NAME\.credentials.json` for intentionally created additional profiles.
- The standard production `claudeAiOauth.accessToken` shape.
- Compatible read-only handling for known wrapper shapes when an access token is present.
- UTF-8 files with an optional byte-order mark.

Authentication behavior:

- Never log, persist, expose to the renderer, or include an access token in an error.
- Never send a refresh token anywhere.
- Never modify Claude Code's credential file.
- Send the access token only to the exact Anthropic usage endpoint already allowlisted by the application.
- Reject redirects, non-HTTPS URLs, unexpected ports, embedded usernames/passwords, and lookalike hosts.
- Treat a missing or zero expiry as unknown and let Anthropic validate the token.
- Treat a positive expiry in the past as expired and instruct the user to run `/login` in the matching Claude profile.
- On HTTP 401/403, show a clear sign-in-again action.
- On HTTP 429, show a rate-limit message and avoid aggressive retries.
- On a missing file, name the profile folder without revealing the full user path.
- Preserve the last good usage reading during a temporary network failure, mark it stale, and show the current error in expanded details.

Multiple Claude accounts:

- The default account is labeled `Claude · Personal`.
- A `.claude-work` profile is labeled `Claude · work`; other suffixes follow the same rule.
- Each account has an independent opt-in switch, request task, result, error, and cancellation generation.
- Disabling one account must not affect another.
- A disabled account must not be read, contacted, summarized, or restored by a late result.
- Profile discovery should ignore unrelated folders such as plugins that merely begin with `.claude-` unless they contain the expected credential marker.

### Codex on Windows

- Continue using `codex app-server` so Codex owns its authentication and provider communication.
- Discover native `codex.exe` on `PATH` and in standard npm-installed vendor-binary locations.
- Do not execute arbitrary shell wrappers or use `shell: true`.
- Do not retain stderr or raw provider responses in logs.
- Bound response size and request duration.
- Terminate the process when the provider is disabled or the application quits.
- Preserve the last good result and mark it stale on temporary failures.
- Distinguish missing CLI, signed-out account, timeout, malformed response, and no subscription limits.

### Settings and tray

Settings should provide:

- Per-account enable switches.
- Screen edge selection.
- Visibility selection.
- Manual refresh.
- Clear Claude personal/work setup instructions for PowerShell.
- A privacy explanation that accurately describes every outbound destination and saved field.
- An explicit statement of features not yet available on Windows.

Tray actions should provide:

- Show AI Notch.
- Open Settings.
- Refresh usage.
- Quit.

Closing the notch should hide it to the tray rather than unexpectedly terminating the process. Quitting through the tray should terminate active provider jobs before exit.

## Features planned after Windows v0.2

These features are expected for closer Mac parity but are not part of the immediate layout/Claude repair unless assigned separately:

- Cursor subscription usage using Cursor's Windows local state database and the exact Cursor usage endpoint.
- GLM/Z.ai usage from supported Windows Claude Code, ZCode, and OpenCode configuration files with strict provider and host validation.
- Antigravity quota through its local Windows language-server bridge.
- Current coding activity indicators for Claude, Codex, Cursor, and Antigravity.
- Selectable display for multi-monitor systems.
- Start at login using an explicit user preference.
- A signed Windows installer after native behavior is stable.
- Windows code signing and release provenance.
- Accessibility and keyboard navigation review on Windows.
- Light/high-contrast theme adaptation if the Windows environment requests it.

Automatic updates should not be added without a separate privacy and supply-chain design. The current release model remains manual downloads from GitHub Releases.

## Privacy and security invariants

These requirements apply to every platform and provider:

1. Accounts and providers are disabled until the user explicitly enables them.
2. Disabled providers perform no credential reads, filesystem monitoring, subprocess execution, or network requests.
3. Disabling a provider cancels in-flight work and invalidates queued/late results.
4. Credentials never enter renderer state, logs, settings, usage history, crash text, or release artifacts.
5. Usage response bodies are not logged or written to disk.
6. Network sessions do not use persistent HTTP caches, cookie stores, or credential stores.
7. Remote destinations are exact, documented HTTPS hosts and paths. Redirects are denied.
8. Localhost exceptions are restricted to a discovered local provider bridge and cannot be generalized to remote hosts.
9. Provider credential files and keychain entries are read-only. AI Notch never refreshes, replaces, or deletes credentials owned by another application.
10. The application has no analytics, advertising, publisher telemetry, browser automation, or browser-cookie extraction.
11. The renderer remains sandboxed, uses context isolation, has no Node integration, and receives only a narrow validated IPC surface.
12. New dependencies and update mechanisms require a privacy and supply-chain review before release.

## Persistence model

Windows AI Notch may save only product preferences needed across launches:

- Enabled account identifiers.
- Selected screen edge.
- Selected visibility mode.
- Future display identifier and start-at-login choice if those features are added.

Credentials, tokens, raw responses, account email addresses, and subscription usage must not be persisted by the Windows application. If stale-display history is added, it must contain only normalized percentages/timestamps and must be documented before release.

## Testing and release acceptance

Tests that can run on macOS:

- Claude and Codex response parsing, including zero percent and malformed values.
- Missing/zero/expired Claude expiry handling with synthetic credentials.
- Strict network destination and redirect rejection.
- Separate personal/work profile discovery.
- Disabled-account isolation, cancellation, and stale-result rejection.
- Preference validation and migration from v0.1 settings.
- Window dimension/orientation calculations as pure functions.
- Renderer checks for circular rings, error states, orientation classes, and accessible labels.
- Source-to-package integrity and ZIP checksums.

Checks required on a real Windows 10/11 machine before a stable release:

- Claude usage with a current personal subscription login.
- Claude usage with personal and work profiles enabled independently.
- Claude behavior after token rotation and after `/login`.
- Codex usage with native and npm installations.
- Hover expansion and collapse at all four screen edges.
- Vertical left/right rendering.
- Taskbar behavior for each taskbar edge and auto-hide setting.
- Tray restoration after Hidden mode.
- Multi-monitor scaling at 100%, 125%, 150%, and mixed DPI.
- Sleep/wake, display disconnect/reconnect, and Explorer restart.
- Keyboard navigation, screen-reader labels, and high-contrast legibility.
- SmartScreen behavior for the unsigned preview.

A Windows release is ready when automated tests pass, the two architectures package successfully, SHA-256 checksums match, no credential-like strings appear in tracked files/artifacts, and the applicable native checks above are recorded in `windows/VALIDATION.md`.

## Parallel work areas

Agents should state which area they own before editing and avoid broad formatting changes outside that area.

### Area A — Windows notch UI and window geometry

Primary files:

- `windows/src/main.cjs`
- `windows/src/index.html`
- `windows/src/renderer.js`
- `windows/src/style.css`
- `windows/src/preload.cjs` only when a validated UI preference requires IPC

Scope: rings, hover/always/hidden behavior, horizontal and vertical layouts, edge geometry, settings presentation, and renderer accessibility. This area is currently in progress.

### Area B — Claude Windows authentication and usage

Primary files:

- `windows/src/providers.cjs`
- `windows/test/privacy.test.cjs`

Scope: safe profile discovery, read-only credential decoding, expiry edge cases, Anthropic response parsing, actionable errors, stale-result behavior, and synthetic tests. Do not add token refresh or credential writes.

### Area C — Additional Windows providers

Preferred new files:

- `windows/src/providers/cursor.cjs`
- `windows/src/providers/glm.cjs`
- `windows/src/providers/antigravity.cjs`
- matching files under `windows/test/`

Scope: port one provider at a time with an explicit credential source, exact destinations, cancellation, synthetic fixtures, and documentation. Avoid expanding `providers.cjs` into a single large file.

### Area D — Windows native validation and packaging

Primary files:

- `windows/package.json`
- `windows/README.md`
- `windows/VALIDATION.md`
- optional CI workflow under `.github/workflows/`

Scope: run the app on Windows x64/ARM64, record observed results, test taskbar/DPI behavior, produce reproducible packages, and prepare signing/installer options. Never commit signing secrets.

### Area E — Activity indicators

Preferred new files under `windows/src/activity/` and `windows/test/`.

Scope: identify active local sessions without reading prompt content, message content, source files, or unrelated processes. Activity monitoring must be opt-in with the provider and stop immediately when disabled.

## Coordination notes

- The published GitHub release `windows-v0.1.0` is a preview and should remain available for comparison.
- The immediate replacement release should be `windows-v0.2.0` and remain marked as a prerelease until native Windows checks pass.
- Do not overwrite an existing release asset in place. Build a new version with new checksums.
- Keep generated directories (`build/`, `dist/`, `node_modules/`, Xcode projects, and derived data) out of Git history. Attach distributable ZIPs to GitHub Releases.
- Preserve the root and per-platform MIT license and upstream attribution files.
- Do not remove required license attribution from distributed bundles, even though product-facing “based on Code Notch” text has been removed.
- Before merging parallel work, rerun both `npm test --prefix windows` and `make test` from the repository root when the Mac source was touched.
