# AI Notch for Windows v0.2.0 — Preview

The Windows notch now rests as a thin black tab. Hover to reveal subscription logos and usage percentages, then hover a provider to see that account's details.

- Added the macOS-style settings interaction: a subtle arc reveals a gear on hover; click to open settings.
- Preserved vertical provider layouts on the left and right edges, with details opening inward.
- Reduced margins and resting thickness to 6 logical pixels, and removed square shadows around rounded corners.
- Added experimental GitHub Copilot quota support, its logo, reset dates, and unlimited-quota display alongside Claude and Codex.
- Added regression coverage for hover transitions, screen-edge layout, Copilot quota parsing, cancellation, and credential handling.

## Downloads

Choose the x64 ZIP for most Intel/AMD Windows PCs, or the ARM64 ZIP for Windows on Arm. Extract the entire ZIP and run **AI Notch.exe**. Quit the previous app through its tray menu before starting the new version. `SHA256SUMS.txt` provides download checksums.

This remains an unsigned portable preview. No macOS code or release artifacts are changed.

## Copilot setup and limitations

Providers are disabled by default. For Copilot, sign in through the native GitHub CLI using `gh auth login`, then enable it in AI Notch settings. The app tries the active github.com account, or a compatible `COPILOT_GITHUB_TOKEN` supplied in its launch environment. Some GitHub CLI credentials may not have access to Copilot quotas.

Copilot uses GitHub's internal entitlement endpoint, which may change or deny access. Live Copilot authentication and usage retrieval have not been verified with a real subscription. Missing data is reported explicitly; sample data is used only when launched with `--demo`. VS Code credentials and browser sessions are not read.

## Validation

All 18 Windows tests and JavaScript syntax checks pass. Release packages are built for x64 and ARM64. ARM64 execution, live provider authentication, and full desktop hover/visual verification remain unverified in this release environment.
