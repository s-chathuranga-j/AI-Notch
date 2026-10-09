# AI Notch for Windows v0.3.2 — Preview

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
