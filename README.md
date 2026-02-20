# Snitch

Snitch is a macOS menu bar app that shows which local processes are listening on TCP ports, lets you jump to `localhost` for a process, and kill stuck services without leaving your flow.

## What The App Does

- Lives in the menu bar with a live process count (`🐀 N`)
- Lists active local listening processes (PID, folder, ports)
- Prioritizes processes tied to real project folders
- Opens `http://localhost:<port>` when you click a row
- Kills a process in one click (`SIGTERM`, then `SIGKILL` fallback)
- Refreshes automatically and resizes the panel to content

## Why Use Snitch

- Faster local debugging: see port conflicts instantly
- Fewer context switches: manage services from the menu bar, not multiple terminals
- Quicker recovery: kill hung processes immediately
- Better visibility: know what is exposed on your machine at a glance

## Requirements

- macOS
- Node.js + npm

## Run

```bash
npm install
npm start
```

## Launch From Desktop (macOS)

Build a standalone macOS app bundle and copy it to your Desktop:

```bash
npm run desktop:install
```

Then launch `Snitch.app` from your Desktop like a normal app icon.
