# AI Notch

Desktop AI subscription usage widgets, with independent platform implementations.

- **[macOS](macos/README.md)** — native SwiftUI/AppKit app. Existing features and privacy fixes are preserved.
- **[Windows](windows/README.md)** — Electron edge widget with Claude personal/work profiles and Codex usage. Initial release; Windows runtime verification is pending.

## Build

```sh
make test           # macOS tests
make package        # macOS DMG
cd windows
npm ci
npm test
npm start           # safe sample-data preview on macOS
npm run package     # Windows x64 + ARM64 ZIPs
```

The installed Mac application is independent of this source layout. Both implementations keep credentials local except for authenticated requests to the selected provider. No publisher telemetry or automatic updater is included.

Original MIT notices are retained in LICENSE and UPSTREAM.md and bundled with each platform.
