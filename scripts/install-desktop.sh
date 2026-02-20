#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

npm run pack:mac

APP_PATH="$(find "$ROOT_DIR/dist" -maxdepth 2 -type d -name 'Snitch.app' | head -n 1)"
if [[ -z "${APP_PATH:-}" ]]; then
  echo "Could not find Snitch.app in dist output." >&2
  exit 1
fi

TARGET_PATH="$HOME/Desktop/Snitch.app"
rm -rf "$TARGET_PATH"
cp -R "$APP_PATH" "$TARGET_PATH"

echo "Installed: $TARGET_PATH"
