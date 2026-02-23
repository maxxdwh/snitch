<img width="128" height="128" alt="snith-large" src="https://github.com/user-attachments/assets/4687df26-c7fe-42e6-a1ea-ced3963e5348" />

# Snitch

Snitch is a tiny macOS menu bar app that shows which local processes are listening on ports, opens localhost quickly, and kills stuck services.

## Download (Apple Silicon)

- Latest version: [Snitch for Apple Silicon](https://github.com/maxxdwh/snitch/releases/latest/download/Snitch-arm64.dmg)
- All releases: [GitHub Releases](https://github.com/maxxdwh/snitch/releases)

## Install

1. Download the DMG above
2. Open it
3. Drag `Snitch.app` into `Applications`
4. Launch Snitch from `Applications`

## What Snitch does

- Lives in your menu bar with a live process count (`🐀 N`)
- Shows local listening processes with PID, folder, and ports
- Prioritises processes tied to real project folders (vibe-coder friendly)
- Opens `http://localhost:<port>` from a row click
- Kills a process in one click (`SIGTERM`, then `SIGKILL` fallback)

## Automatic updates

Snitch checks GitHub Releases for updates when running as a packaged app.

- Automatic: periodic background checks
- Manual: Right-click 🐀 in your menu bar -> `Check for Updates…`
- Install: prompted to restart when an update is downloaded

## Feedback

Found a bug or have an idea? Open an issue. All feedback is welcome 🧀
