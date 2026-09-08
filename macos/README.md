# AI Notch

A native macOS companion that places AI coding usage and session activity on a screen edge. Built with SwiftUI and AppKit.

## Features

- Usage rings and reset windows for Claude Code, Cursor, Codex, Antigravity, GLM and GitHub Copilot (experimental).
- Busy and waiting indicators for supported coding sessions.
- Top, bottom, left or right placement, including hardware-notch alignment.
- Hover expansion, always-visible and hidden modes.
- Provider controls, launch at login, Dock and menu-bar options.
- Explicit stale, unavailable and authentication states when readings fail.

## Install on this Mac

Run `make package` to build the Release app and create a verified disk image under `build/releases/`. Open the `.dmg`, then drag **AI Notch** into **Applications**. Quit any running development copy before launching the installed app. Enable the desired accounts in Settings.

This locally built package is ad-hoc signed for this Mac and is not notarized for public distribution.

## Build and run

Requires macOS 26+, Xcode 26+ and XcodeGen (`brew install xcodegen`).

```sh
make build  # build/Build/Products/Debug/AI Notch.app
make demo   # sample usage; no provider polling or session monitoring
make run    # live readings using accounts already signed in locally
make test   # model, adapter, geometry and rendering tests
```

Quit an already running AI Notch before switching between demo and live mode. Open the app again or use the notch's gear to access Settings. Demo provider rows are empty because no real adapters are registered.

## Privacy and account access

Accounts start disabled on the first launch of version 0.2.0, including upgrades from the earlier preview. Enable only the accounts you want in Settings. Future choices are saved; newly discovered profiles remain off until enabled.

Enabling an account allows local credential/account reads, usage requests and session monitoring for that account. Live usage sends authentication to the relevant provider over HTTPS. Codex launches its installed app server; Antigravity can ask its local language server to refresh remotely; Copilot runs `gh auth token --hostname github.com` to borrow the GitHub CLI’s login. These tools manage their own backend connections.

Disabling an account cancels its active usage task, prevents queued requests, discards late results, clears its archived readings and credential cache, and stops/clears session monitoring. A request that has already reached the provider cannot be recalled. Other enabled accounts keep operating.

Direct provider HTTP requests use exact destination checks, reject redirects, and have no persistent response, cookie or credential store. No raw usage responses, tokens or subprocess output are written to app logs. There is no AI Notch telemetry service or embedded browser. Previous OS diagnostic logs are not retroactively erased; the app clears its old HTTP response cache at launch.

Usage history (percentages, reset windows and fetch times) is stored locally in app preferences while the account is enabled. Account credentials remain owned by the installed coding tools. The app does not implement cloud synchronization; system backups and vendor-tool network behavior are outside AI Notch's control.

Internal provider endpoints and local data formats can change. Fixture tests do not establish live account connectivity. See `audit/PRIVACY-FIXES.md` for the privacy changes and verification.

## Personal and work subscriptions

Claude Code supports separate profiles. To use the default profile for personal and another for work, start Claude Code in Terminal and sign into the corresponding account in each:

```sh
# Personal (default profile)
claude

# Work (separate profile)
CLAUDE_CONFIG_DIR=~/.claude-work claude
```

Use `/login` inside the relevant Claude Code session if it needs a different account. Do not copy credentials between profiles. Restart AI Notch after creating a profile, then enable `Claude` and `Claude (work)` separately in Settings. Other names such as `~/.claude-personal` are also discovered, provided Claude Code has initialized them. Arbitrary directory locations are not currently discovered. This integration reads Claude Code OAuth subscriptions; API-key or cloud-provider billing is a different integration.

Cursor, Codex, Antigravity, GLM and Copilot currently expose one account each. Switch accounts in the owning tool to change which one AI Notch reads; simultaneous personal/work rings for these providers are not implemented. GLM uses the first valid credential source in its documented order.

Claude's profile configuration is documented in the [official environment-variable reference](https://code.claude.com/docs/en/env-vars).

## GitHub Copilot (experimental)

Copilot appears beside the other providers with its own enable switch. Sign in to the GitHub CLI with the account that holds your Copilot subscription, then enable Copilot in Settings:

```sh
gh auth login
```

AI Notch reads the token with `gh auth token --hostname github.com` — never as a command-line argument, never from VS Code or a browser — and sends it only to `https://api.github.com/copilot_internal/user`, with redirects refused. The GitHub CLI is looked for in the Homebrew and `/usr/local/bin` locations and on `PATH`. If GitHub refuses the CLI's token, a compatible token in `COPILOT_GITHUB_TOKEN` in the environment that launches AI Notch is used instead. The account label comes from the CLI's `hosts.yml` login name; no token is read from that file.

The ring shows the first limited quota (premium requests, or AI credits on credit-billed plans); unlimited quotas such as chat and completions are listed as **Unlimited** and never drawn as a percentage. This uses an internal GitHub entitlement endpoint rather than a supported public API, so GitHub can change the response or deny access at any time; AI Notch then reports the failure without exposing the response body. Live retrieval has not been verified against a real Copilot subscription. Enterprise-hosted GitHub accounts are not supported. The Copilot logo is from [Primer Octicons](https://github.com/primer/octicons), MIT licensed; the notice is in `UPSTREAM.md`.

## Independent build

AI Notch uses bundle ID `com.fourforge.ainotch` and separate preferences. The original publisher's update service and signing configuration are removed. This preview is ad-hoc signed for local use, with no automatic updates. Public distribution will require your own Developer ID signing and notarization.

## License

See `LICENSE` and `UPSTREAM.md` for the required open-source notices. Both are included in the app bundle.
