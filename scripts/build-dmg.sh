#!/usr/bin/env bash
# Wraps dist/Snitch.app in a drag-to-Applications DMG. Needs only built-in macOS tools.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d dist/Snitch.app ]] || ./scripts/build-app.sh

STAGE="$(mktemp -d)"
OUT="dist/Snitch.dmg"
rm -f "$OUT" dist/rw.dmg
cp -R dist/Snitch.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background" && cp assets/dmg-background.png "$STAGE/.background/bg.png"

hdiutil create -volname "Snitch" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ dist/rw.dmg >/dev/null
DEV=$(hdiutil attach dist/rw.dmg -noverify -noautoopen | grep -E '^/dev/' | head -1 | awk '{print $1}')

# Pretty window layout; skipped silently if Finder scripting isn't permitted.
osascript <<OSA >/dev/null 2>&1 || echo "(skipped DMG window styling)"
tell application "Finder"
  tell disk "Snitch"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:bg.png"
    set position of item "Snitch.app" of container window to {180, 185}
    set position of item "Applications" of container window to {480, 185}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync; hdiutil detach "$DEV" >/dev/null
hdiutil convert dist/rw.dmg -format UDZO -o "$OUT" >/dev/null
rm -f dist/rw.dmg; rm -rf "$STAGE"
echo "Built $OUT ($(du -sh "$OUT" | cut -f1))"
