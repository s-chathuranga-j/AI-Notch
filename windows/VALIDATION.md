# Validation — 2026-09-07

On macOS arm64:

- All 557 macOS tests pass after moving the project to `macos/` and regenerating the Xcode project.
- Five Windows logic/privacy tests pass: provider response parsing, disabled-account isolation, cancellation/late-result exclusion, destination restrictions, separate Claude profile discovery.
- Electron preview launched successfully. Settings, synthetic usage bars, and independently disabling the work account were checked through the native accessibility UI.
- npm dependency audit reports zero known vulnerabilities at build time.
- Both Windows ZIP payloads are checked against the current source and unpacked app archives. Executables identify as Windows PE x64 and ARM64.

Not validated here: actual Windows authentication and subprocess execution, tray rendering, screen-edge placement around the Windows taskbar, multi-monitor changes, or SmartScreen behavior. This is an unsigned initial portable release. It does not yet have full macOS feature/provider parity. See README for scope.
