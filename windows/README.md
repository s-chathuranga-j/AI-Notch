# AI Notch for Windows

A tray application with a compact usage widget at any screen edge. Hover to expand; use the gear to enable accounts, change placement, or retry. Close/hidden widgets can be restored through the system tray.

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

Usage refreshes every two minutes. Expired logins produce an explicit sign-in instruction, not an indefinite waiting indicator. Right-click the tray icon to refresh, show settings, or quit.

## Development on a Mac

```sh
npm ci
npm test
npm start
npm run package
```

On macOS the app always uses synthetic sample data and never reads Mac credentials. Windows can preview the same data with `npm start -- --demo`. Packaging produces ZIPs in `dist/` for x64 and ARM64. No signing certificates or publishing service are configured.

## Scope

Implemented: Claude OAuth usage, discovered personal/work Claude accounts, Codex app-server usage, per-account opt-in, retry, tray, hover expansion, four screen edges. Cursor, GLM, Antigravity, coding activity indicators, startup-at-login, display selection, and installer integration are not yet ported. Native process discovery, tray behavior, taskbar placement, and authentication must be validated on Windows.

## Privacy

Only account enablement and screen edge are saved in Electron's local user-data `settings.json`. Credentials and quota responses stay in memory; neither is logged or saved. Claude requests go exclusively to `https://api.anthropic.com/api/oauth/usage`, with redirects forbidden. Codex CLI manages its own network access and authentication. Disabling an account cancels its work and rejects late results. The sandboxed renderer has no Node access and cannot make network requests. Narrow IPC exposes only preferences and sanitized usage, never tokens. No analytics, publisher service, updater, browser-cookie extraction, or token refresh is included.

The Electron runtime and build tools are additional dependencies compared with the native Mac implementation. Dependency updates should be reviewed before future releases.
