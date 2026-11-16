<img width="128" height="128" alt="snith-large" src="https://github.com/user-attachments/assets/4687df26-c7fe-42e6-a1ea-ced3963e5348" />

# Snitch

Snitch is a tiny, native macOS menu bar app that shows what's running on your Mac's localhost, how much memory it's using, and lets you stop it in one click. Built for people who vibe-code and don't want to learn `lsof`.

## Download (Apple Silicon and Intel)

- Direct DMG download: [Snitch for macOS](https://github.com/maxxdwh/snitch/releases/latest/download/Snitch.dmg)
- All releases: [GitHub Releases](https://github.com/maxxdwh/snitch/releases)

Requires macOS 13 or later. The app is about 1.5 MB and uses roughly 50 MB of RAM.

## Install

1. Download the DMG above
2. Open it
3. Drag `Snitch.app` into `Applications`
4. Launch Snitch from `Applications`

If you get stuck installing because it's not notarised by Apple (I don't have an Apple Dev account right now), head to `System Settings` then to `Privacy & Security` and click `Open Anyway`. Use good judgement to decide if you trust me or not 🪤

## What Snitch does

- **🐀 in your menu bar**, optionally with total memory (right-click → Show Memory in Menu Bar)
- **Friendly names**: "Next.js · my-app" instead of "node, PID 4821"
- **Memory per server** (including its child processes), plus a Mac memory pressure light
- **Open** a server in your browser, copy its URL, show its folder in Finder, or open it in Cursor / VS Code / Zed
- **Stop** a server safely: asks first, tries a graceful shutdown, force-quits only if needed, and also stops the `npm run dev` wrapper so it doesn't restart
- **Network warning** when a server is visible to everyone on your Wi-Fi
- **"Forgotten?" nudge** for servers that have been running 8+ hours
- Optional notifications when a server starts or uses over 2 GB
- Launch at Login, and a global shortcut: `⌃⌥S`

## Updates

Snitch checks GitHub Releases once a day and tells you when a new version is out (right-click → `Check for Updates…` to check now). Because the app isn't notarised it can't replace itself, so you download the new DMG and drag it over the old one.

## Building from source

You do **not** need Xcode. The Command Line Tools (`xcode-select --install`) are enough.

```sh
./scripts/build-app.sh   # dist/Snitch.app (universal, ad-hoc signed)
./scripts/build-dmg.sh   # dist/Snitch.dmg
swift build && .build/debug/Snitch --dump   # print what Snitch sees, no UI
```

Snitch reads processes straight from the kernel via `libproc`, so it never spawns `lsof` or `ps`.

## Feedback

Found a bug or have an idea? Open an issue. All feedback is welcome 🧀
