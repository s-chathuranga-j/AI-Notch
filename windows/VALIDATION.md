# Windows v0.2.0 validation - 2026-09-08

- All 18 Windows tests pass, covering provider parsing, opt-in/cancellation, credential destinations, hover interactions, and all four screen edges.
- Changed JavaScript entry points pass Node syntax checks; `git diff --check` passes.
- x64 and ARM64 ZIP builds completed on Windows. ZIP integrity and PE architecture were verified for both.
- Every bundled source file matches the working source, both app archives identify version 0.2.0, and the ZIP app archives match the verified unpacked archives.
- SHA-256 checksums were generated for both ZIP downloads.
- The packaged x64 application launched successfully in demo mode; its main and renderer processes are running.
- Live Claude/Codex/Copilot account authentication, ARM64 execution, and complete desktop visual/hover verification were not performed. Copilot uses an internal GitHub endpoint and remains experimental. The portable builds remain unsigned.

## Earlier validation

# Validation — 2026-09-07

On macOS arm64:

- All 557 macOS tests pass after moving the project to `macos/` and regenerating the Xcode project.
- Five Windows logic/privacy tests pass: provider response parsing, disabled-account isolation, cancellation/late-result exclusion, destination restrictions, separate Claude profile discovery.
- Electron preview launched successfully. Settings, synthetic usage bars, and independently disabling the work account were checked through the native accessibility UI.
- npm dependency audit reports zero known vulnerabilities at build time.
- Both Windows ZIP payloads are checked against the current source and unpacked app archives. Executables identify as Windows PE x64 and ARM64.

Not validated here: actual Windows authentication and subprocess execution, tray rendering, screen-edge placement around the Windows taskbar, multi-monitor changes, or SmartScreen behavior. This is an unsigned initial portable release. It does not yet have full macOS feature/provider parity. See README for scope.
