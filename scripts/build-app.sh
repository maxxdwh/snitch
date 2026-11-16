#!/usr/bin/env bash
# Builds dist/Snitch.app (universal: Apple Silicon + Intel) using only the Swift
# toolchain from the Command Line Tools. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Snitch.app"
rm -rf dist/Snitch.app dist/.build-arm64 dist/.build-x86_64
mkdir -p dist

BINS=()
for arch in arm64 x86_64; do
  ARGS=(-c release --triple "$arch-apple-macosx13.0" --scratch-path "dist/.build-$arch")
  swift build "${ARGS[@]}" 2>&1 | grep -E "error|Build complete" | tail -3
  BINS+=("$(swift build "${ARGS[@]}" --show-bin-path)/Snitch")
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Snitch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f assets/icon.icns ]] && cp assets/icon.icns "$APP/Contents/Resources/icon.icns"

# Ad-hoc sign (free). Apple Silicon refuses to run completely unsigned code.
codesign --force --sign - "$APP"
rm -rf dist/.build-arm64 dist/.build-x86_64
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
