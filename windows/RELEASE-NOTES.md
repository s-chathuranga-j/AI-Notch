# AI Notch for Windows v0.3.6 — Preview

AI Notch now receives Claude’s five-hour and weekly usage from normal Claude Code sessions through its status line. The collector saves quota figures locally without reading Claude credentials or sending background requests.

- In AI Notch Settings, enable your Claude profile and choose **Copy status line settings**. Merge the entry into that profile’s Claude Code settings, then use Claude Code normally. See the [setup guide](https://github.com/s-chathuranga-j/AI-Notch/blob/main/windows/README.md#claude-code-usage) if you already use a status line.
- An old usage reading displays **Stale** with an empty ring. The details show the previous figures and their timestamp.

The Setup EXE selects the native x64 or ARM64 version. Portable ZIPs are also available. This is an unsigned preview.

All 48 tests passed. Live Claude Code usage and installer execution on Windows remain unverified.

## Earlier release: Windows v0.3.5

The Windows notch now uses the Mac's flared outline and 44-pixel circular usage rings on all four screen edges.

- Added **Start with Windows** in Settings. Enable it once to register the installed executable, replacing any old Startup-folder shortcut to a ZIP copy. The switch reflects Windows startup approval; the app does not silently re-enable a disabled registration.
- Recreates a lost window, reloads a crashed or unresponsive renderer, and repositions and refreshes after sleep, unlock, or display changes. Intentional Quit and Windows shutdown remain respected.
- Handles unexpected JavaScript failures with a bounded restart and a visible message if recovery repeatedly fails.
- Fixed Codex output handling: null messages, invalid reset timestamps, and broken output streams no longer escape the provider error handler and crash the app.
- “Show AI Notch” genuinely restores Hidden mode. Preferences are written atomically.
- Local rotating lifecycle logs record fixed event/error categories, never account names, credentials, provider responses, raw exception messages, or stacks. They are never uploaded.

54 tests pass. The real Electron demo on macOS was checked at all four edges and recovered from a deliberately crashed renderer with its four usage readings intact. Native Windows boot, sleep/GPU-driver behavior, installer execution, and live account authentication remain untested on this Mac. The installer and app remain unsigned previews.

## Earlier release: Windows v0.3.4

Windows now has a Setup EXE. Run it to install AI Notch for your Windows user, create Start menu and desktop shortcuts, and launch the app. The same installer selects the native x64 or ARM64 app. Uninstall from Windows Settings; saved preferences are preserved during upgrades and uninstall.

Quit any existing copy from its tray menu before installing. Previous portable installations share the same saved preferences, and their extracted folders are left untouched. Portable ZIPs remain available. The installer and app remain unsigned previews.

All 29 Windows tests pass. The installer and ZIPs passed integrity checks; both embedded native payloads match the verified app builds. Product/version, icons, app identity, and non-elevating manifests were checked for the installer and uninstaller. Native Windows install, upgrade, and uninstall execution remain untested.

## Earlier release: Windows v0.3.3

A small brain replaces the star in AI Notch's icon. The N monogram, screen-notch cutout, and dark tile remain, shared with the macOS app. The executable, window, and tray use the updated artwork at all nine Windows icon sizes.

Quit AI Notch through the tray menu, extract the complete x64 or ARM64 ZIP into your app folder, and run **AI Notch.exe**. Preferences are retained. This remains an unsigned portable preview.

All 29 Windows tests pass. Both ZIPs passed integrity checks, and their architecture, version, nine embedded brain icons, and bundled sources match the verified build. Native Windows desktop rendering was not tested for this artwork edit.

## Earlier release: Windows v0.3.2

Original AI Notch artwork replaces the inherited Code Notch icon. The executable, window, and system tray now use AI Notch's own icon, shared with the macOS app. The Windows executable includes nine sizes from 16 to 256 pixels for different display scales.

Quit AI Notch through the tray menu, extract the complete x64 or ARM64 ZIP into your app folder, and run **AI Notch.exe**. Existing preferences are retained. This remains an unsigned portable preview.

All 29 Windows tests pass. Both ZIPs passed integrity checks, and their executable architecture, version, nine embedded icon images, and bundled source files match the verified build. Native Windows desktop rendering was not tested for this artwork update.

## Earlier release: Windows v0.3.1

The Windows app now uses the AI Notch artwork from macOS for its executable, window, and system tray icon. The executable embeds icon sizes from 16 to 256 pixels for different display scales, along with the app name and version metadata.

Download the x64 ZIP for Intel/AMD PCs or the ARM64 ZIP for Windows on Arm. Quit AI Notch from the tray, extract the complete ZIP into your app folder, and run **AI Notch.exe**. Existing preferences are retained. This remains an unsigned portable preview.

All 29 Windows tests pass. Both ZIPs were built on macOS and checked for ZIP integrity, correct executable architecture and version, all nine embedded icon sizes, and matching bundled source and artwork. The runtime icon paths were checked for Windows and the macOS preview. Native Windows desktop rendering remains unverified for this icon update.

## Earlier release: Windows v0.3.0

Claude usage now reads correctly on plans that do not use session and weekly windows, and a reading that cannot be refreshed stays on screen instead of disappearing.

- Read Claude's `limits` array, the forward-compatible shape the macOS app already used, so newer limit kinds such as Opus and Sonnet weeks appear as Anthropic adds them.
- Kept the named `five_hour` and `seven_day` windows merged in, since a window leaves `limits` the moment its reset passes.
- Added a Credits reading for plans billed on usage credits, including enterprise accounts, which report no rate-limit windows at all. These previously failed with "Claude returned no usage windows".
- Kept the last successful reading visible when a refresh fails, marked with a warning sign, the reason, and the time the reading was taken. Rate limits and transient errors no longer blank the percentage.
- Discarded the cached reading when an account is disabled, so it cannot reappear on re-enable.

This release also carries the in-progress Windows work merged alongside it:

- Added a visibility preference (On hover, Always, Hidden) in settings, saved with the screen edge. Always keeps the overview open and never collapses on pointer leave; Hidden takes the window off screen and ignores the mouse, with the tray as the way back.
- Tray click now opens Settings, and "Show AI Notch" expands the notch.
- Tolerated rotated Claude credentials: a UTF-8 byte order mark is stripped, known wrapper shapes are accepted when an access token is present, the missing-file error names the profile folder, and a zero or missing `expiresAt` is treated as unknown so Anthropic validates the token rather than a local check rejecting it.

## Downloads

Choose the x64 ZIP for most Intel/AMD Windows PCs, or the ARM64 ZIP for Windows on Arm. Extract the entire ZIP and run **AI Notch.exe**. Quit the previous app through its tray menu before starting the new version. `SHA256SUMS.txt` provides download checksums.

This remains an unsigned portable preview. No macOS code or release artifacts are changed.

## Notes and limitations

An account with no successful reading yet shows the failure reason alone, never a placeholder number. The cached reading is held only in memory, so it does not survive a restart; nothing new is written to disk.

Credit-billed plans report spend against a monthly limit with no reset date, so the Credits row shows a percentage without a reset time. Undocumented code-named fields in the usage response are ignored rather than guessed at.

There is no backoff after a rate limit; the app continues its two-minute refresh.

## Validation

All 29 Windows tests pass, including new coverage for the `limits` array, credit-billed plans, stale-reading display, cache handling on disable, and the Always visibility mode. The x64 package was installed and run on Windows 11, where the Claude reading was verified against a live enterprise account. ARM64 execution remains unverified in this release environment.
