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

Enabling an account allows local credential/account reads, usage requests and session monitoring where that provider needs them. Live usage sends authentication to the relevant provider over HTTPS. Codex launches its installed app server; Antigravity asks its local language server for quota without reading the rotating Antigravity Keychain item; Copilot runs `gh auth token --hostname github.com` to borrow the GitHub CLI’s login. These tools manage their own backend connections.

AI Notch uses a fresh Claude Code status line reading when available. Otherwise it reads the profile’s Claude Code credential from Keychain and requests usage from Anthropic’s private usage endpoint. macOS may prompt for access when Claude Code rotates the Keychain item. See [Claude Code usage](#claude-code-usage) for setup.

Disabling an account cancels its active usage task, prevents queued requests, discards late results, clears its archived readings and credential cache, and stops/clears session monitoring. A request that has already reached the provider cannot be recalled. Other enabled accounts keep operating.

Direct provider HTTP requests use exact destination checks, reject redirects, and have no persistent response, cookie or credential store. No raw usage responses, tokens or subprocess output are written to app logs. There is no AI Notch telemetry service or embedded browser. Update checks contact GitHub for the appcast and release downloads; Sparkle system profiling and embedded release notes are disabled. Previous OS diagnostic logs are not retroactively erased; the app clears its old HTTP response cache at launch.

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

Use `/login` inside the relevant Claude Code session if it needs a different account. Do not copy credentials between profiles. Restart AI Notch after creating a profile, then enable `Claude` and `Claude (work)` separately in Settings. Other names such as `~/.claude-personal` are also discovered, provided Claude Code has initialized them. Arbitrary directory locations are not currently discovered. The status line integration reads subscription limits for each configured profile.

Cursor, Codex, Antigravity, GLM and Copilot currently expose one account each. Switch accounts in the owning tool to change which one AI Notch reads; simultaneous personal/work rings for these providers are not implemented. GLM uses the first valid credential source in its documented order.

Claude's profile configuration is documented in the [official environment-variable reference](https://code.claude.com/docs/en/env-vars).

## Claude Code usage

1. Enable Claude in AI Notch Settings and click **Copy status line settings**.
2. Merge the copied `statusLine` entry into `~/.claude/settings.json`. For a work profile, use its own settings file (for example, `~/.claude-work/settings.json`) and copy the command from that profile’s row.
3. Use Claude Code normally. Its [status line](https://code.claude.com/docs/en/statusline#rate-limit-usage) receives five-hour and weekly usage after the first API response in a session. AI Notch updates on its next refresh and marks old readings stale while Claude Code is idle.

If you already have a status line, keep its settings and add the collector to that script. For a shell script, read stdin once, then pass it independently to the AI Notch command and your existing status line logic. Copy the command for your profile from AI Notch and substitute it for the placeholder below:

```sh
payload=$(/bin/cat)
printf '%s' "$payload" | <copied AI Notch command>
printf '%s' "$payload" | /absolute/path/to/existing-statusline
```

Only usage percentages, reset times, and the observation time are saved to `ai-notch-usage.json` in the configured profile. Turning the integration off clears its readings and stops the collector from recording. To remove setup entirely, remove the collector command from Claude Code settings. Update the command if you move AI Notch to a different location.

## GitHub Copilot (experimental)

Copilot appears beside the other providers with its own enable switch. Sign in to the GitHub CLI with the account that holds your Copilot subscription, then enable Copilot in Settings:

```sh
gh auth login
```

AI Notch reads the token with `gh auth token --hostname github.com` — never as a command-line argument, never from VS Code or a browser — and sends it only to `https://api.github.com/copilot_internal/user`, with redirects refused. The GitHub CLI is looked for in the Homebrew and `/usr/local/bin` locations and on `PATH`. If GitHub refuses the CLI's token, a compatible token in `COPILOT_GITHUB_TOKEN` in the environment that launches AI Notch is used instead. The account label comes from the CLI's `hosts.yml` login name; no token is read from that file.

The ring shows the first limited quota (premium requests, or AI credits on credit-billed plans); unlimited quotas such as chat and completions are listed as **Unlimited** and never drawn as a percentage. This uses an internal GitHub entitlement endpoint rather than a supported public API, so GitHub can change the response or deny access at any time; AI Notch then reports the failure without exposing the response body. Live retrieval has not been verified against a real Copilot subscription. Enterprise-hosted GitHub accounts are not supported. The Copilot logo is from [Primer Octicons](https://github.com/primer/octicons), MIT licensed; the notice is in `UPSTREAM.md`.

## Independent build

AI Notch uses bundle ID `com.fourforge.ainotch` and separate preferences. The original publisher’s update service and signing configuration are removed. Sparkle checks this repository’s macOS update feed daily and prompts before downloading and installing. Settings includes an automatic-check toggle and **Check for Updates…**. Demo mode does not start the updater. This preview is ad-hoc signed for local use. Public distribution will require your own Developer ID signing and notarization.

## License

See `LICENSE` and `UPSTREAM.md` for the required open-source notices. Both are included in the app bundle.

## Publishing macOS updates

Existing versions without Sparkle need one manual install of the first updater-enabled release. After that, users can install subsequent releases from the update prompt.

1. Increase both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, and add the release notes. Sparkle compares the build number (`CURRENT_PROJECT_VERSION`), so it must increase for every published update.
2. Run `make test` and `make package`. Packaging builds a universal Apple Silicon/Intel app, verifies the app and disk image, signs the update archive, and creates `build/releases/appcast.xml`. It fails if the signing key does not match the public key embedded in the app.
3. Upload the generated universal `.dmg` and `.dmg.sha256` to the GitHub release tagged `macos-v<VERSION>`. Verify the download is available before updating the feed. Do not overwrite an already published version with different binaries.
4. Copy `build/releases/appcast.xml` to `updates/appcast.xml`, then commit and push the feed to `main`. The app reads that exact path on GitHub. Only publish a feed after its matching installer is uploaded. The live feed offers the latest published macOS installer.
5. Test from an older installed build: check, download, install, and relaunch. Confirm preferences remain intact. The feed intentionally contains only the newest full installer; delta updates are not generated.

The Sparkle Ed25519 private key lives in the release Mac’s login Keychain under account `com.fourforge.ainotch`; only its public key is in the repository. Preserve a secure backup of this key before distributing the first updater-enabled release. On a replacement release Mac, restore the same key using Sparkle’s `generate_keys` tool; generating a different key breaks updates for existing installations. The tools are in `build/SourcePackages/artifacts/sparkle/Sparkle/bin/` after building.

Archive signatures protect update integrity; they do not replace Apple Developer ID signing or notarization. Local ad-hoc preview builds disable hardened runtime because they have no Team ID for loading Sparkle. For Developer ID distribution, enable hardened runtime, sign the app and nested frameworks with the same identity, and notarize the result. Those require an Apple Developer account and are still needed for public distribution without Gatekeeper warnings. See [Sparkle’s distribution documentation](https://sparkle-project.org/documentation/).
