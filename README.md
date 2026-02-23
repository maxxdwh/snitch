<img width="64" height="64" alt="snith-large" src="https://github.com/user-attachments/assets/4687df26-c7fe-42e6-a1ea-ced3963e5348" />

# Snitch

Snitch is a tiny macOS menu bar app that shows which local processes are listening on ports, opens localhost quickly, and kills stuck services.

## Download (Apple Silicon)

- Direct DMG download: [Snitch for Apple Silicon](https://github.com/maxxdwh/snitch/releases/latest/download/Snitch-arm64.dmg)
- All releases: [GitHub Releases](https://github.com/maxxdwh/snitch/releases)

## Install

1. Download the DMG.
2. Open it.
3. Drag `Snitch.app` into `Applications`.
4. Launch Snitch from `Applications`.

## What It Does

- Lives in your menu bar with a live process count (`🐀 N`)
- Shows local listening processes with PID, folder, and ports
- Prioritizes processes tied to real project folders
- Opens `http://localhost:<port>` from a row click
- Kills a process in one click (`SIGTERM`, then `SIGKILL` fallback)

## Auto Updates

Snitch checks GitHub Releases for updates when running as a packaged app.

- Manual: tray menu -> `Check for Updates…`
- Automatic: periodic background checks
- Install: prompted to restart when an update is downloaded

## Run From Source

Requirements:
- macOS
- Node.js + npm

```bash
npm install
npm start
```

## Build Release Artifacts (Apple Silicon)

```bash
npm run dist:mac
```

Generated files:
- `dist/Snitch-arm64.dmg`
- `dist/Snitch-arm64.zip`
- `dist/latest-mac.yml`

## Publish A New Release

1. Bump `version` in `package.json`.
2. Run `npm run dist:mac`.
3. Create GitHub release tag `v<version>` on `maxxdwh/snitch`.
4. Upload:
- `dist/Snitch-arm64.dmg`
- `dist/Snitch-arm64.zip`
- `dist/latest-mac.yml`
