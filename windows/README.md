# AI Notch for Windows

A tray application with a thin black notch at any screen edge. Hover to reveal logos and percentages, then hover a logo for account details. Hover the settings arc to reveal its gear; click to enable accounts or change placement. Close/hidden widgets can be restored through the system tray. See [v0.3.0 release notes](RELEASE-NOTES.md).

## Run on Windows

Extract the complete ZIP into a permanent folder and run **AI Notch.exe**. Keep the supporting files beside it. This is an unsigned portable build, not an installer; Windows may show an unknown-publisher prompt. Windows 10/11 x64 and ARM64 builds are packaged. Native Windows testing remains required before treating this as a stable release.

Providers are off by default. Enable Claude or Codex from settings after signing in through their own Windows CLI. Claude reads `%USERPROFILE%\.claude\.credentials.json`; Codex invokes `codex app-server` from PATH with `%USERPROFILE%\.codex` as its configuration directory. This does not read credentials from WSL. Codex is discovered as a native executable on PATH or in the standard npm global vendor-binary locations. Arbitrary shell wrappers are never executed.

For a second Claude subscription, in PowerShell:

```powershell
$env:CLAUDE_CONFIG_DIR="$HOME\.claude-work"
claude
# Run /login and sign in to your work account.
```

Restart AI Notch. The work profile appears separately and requires its own enable switch. To return the terminal to the default personal profile, run `Remove-Item Env:CLAUDE_CONFIG_DIR`. Additional `.claude-NAME` folders with credential files are discovered in the same way. Custom paths outside these home-directory profiles and multiple Codex profiles are not yet configurable.

Claude reports session and weekly windows for subscription plans. Plans billed on usage credits, including enterprise accounts, report no such windows; those show a single Credits reading taken from the reported spend against the monthly limit, with no reset date. Newer limit kinds are read from the response's `limits` array as Anthropic adds them.

Usage refreshes every two minutes. When a refresh fails, the last reading stays on screen with a warning sign and the reason, rather than disappearing; the account details give the time that reading was taken. An account that has not yet had a successful reading shows the reason alone, never a placeholder number. Expired logins produce an explicit sign-in instruction, not an indefinite waiting indicator. Right-click the tray icon to refresh, show settings, or quit.

## Development on a Mac

```sh
npm ci
npm test
npm start
npm run package
```

On macOS the app always uses synthetic sample data and never reads Mac credentials. Windows can preview the same data with `npm start -- --demo`. Packaging produces ZIPs in `dist/` for x64 and ARM64. No signing certificates or publishing service are configured.

## Scope

Implemented: experimental GitHub Copilot quotas, Claude OAuth usage, discovered personal/work Claude accounts, Codex app-server usage, per-account opt-in, retry, tray, hover expansion, four screen edges. Cursor, GLM, Antigravity, coding activity indicators, startup-at-login, display selection, and installer integration are not yet ported. Native process discovery, tray behavior, taskbar placement, and authentication must be validated on Windows.

## Privacy

Only account enablement and screen edge are saved in Electron's local user-data `settings.json`. Credentials and quota responses stay in memory; neither is logged or saved. The most recent reading for an enabled account is held in memory so a failed refresh can show it as stale, and is discarded when the account is disabled or the app quits. Claude requests go exclusively to `https://api.anthropic.com/api/oauth/usage`, with redirects forbidden. Codex CLI manages its own network access and authentication. Copilot reads `COPILOT_GITHUB_TOKEN` or runs `gh auth token --hostname github.com` locally, then calls only `https://api.github.com/copilot_internal/user`, with redirects forbidden. Tokens remain in the main process and are never passed as command-line arguments or sent to the renderer. Disabling an account cancels its work and rejects late results. The sandboxed renderer has no Node access and cannot make network requests. Narrow IPC exposes only preferences and sanitized usage, never tokens. No analytics, publisher service, updater, browser-cookie extraction, or token refresh is included.

The Electron runtime and build tools are additional dependencies compared with the native Mac implementation. Dependency updates should be reviewed before future releases.


## GitHub Copilot (experimental)

Copilot appears beside Claude and Codex, with its own enable switch. The hover overview shows the first available limited quota; unlimited-only accounts show an infinity symbol. Details show the reported quota categories and reset dates. AI-credit billing is labeled separately from legacy premium requests. Missing or unsupported quotas produce an explicit status, never an estimated allowance.

Sign into the native GitHub CLI with `gh auth login`, using the GitHub account that has your Copilot subscription, and enable Copilot in AI Notch settings. AI Notch uses the active github.com account; VS Code credentials and browser sessions are not read. An existing CLI login may not be accepted by the internal quota endpoint. If GitHub denies access, a compatible token can be supplied through `COPILOT_GITHUB_TOKEN` in the environment that launches the app. AI Notch does not create tokens, request additional scopes, or persist tokens. Enterprise-hosted GitHub accounts are not supported by this integration.

This uses an internal GitHub endpoint, not a supported public quota API. Authentication compatibility and live quota retrieval have not been verified with a real Copilot account. Demo mode uses clearly labeled sample data. GitHub can change the response format or restrict access; the app reports that failure without exposing the response body.

Implementation references: [VS Code entitlement schema](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/defaultAccount.ts), [VS Code quota handling](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/chat/common/chatEntitlementService.ts), and [VS Code endpoint configuration](https://github.com/microsoft/vscode/blob/main/extensions/copilot/CONTRIBUTING.md). The Copilot logo is from [Primer Octicons](https://github.com/primer/octicons/blob/main/icons/copilot-24.svg), under the MIT license bundled in `src/assets/OCTICONS-LICENSE`.
