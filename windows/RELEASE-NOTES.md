# AI Notch for Windows v0.3.0 — Preview

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
