#!/bin/bash
# Creates Flubber.dmg with the classic install screen:
# the Flubber icon with an arrow → Applications folder to drag it into.
#
# Modes:
#   ./make-dmg.sh             -> uses Finder to compose the layout and SAVES
#                                the result to dmg/DS_Store (to version it).
#   ./make-dmg.sh --prebuilt  -> does NOT use Finder; reuses dmg/DS_Store.
#                                (also enabled automatically if CI=true, e.g. on GitHub Actions)
set -e
cd "$(dirname "$0")"

APP="Flubber.app"
VOL="Flubber"
DMG_TMP="Flubber-tmp.dmg"
DMG_FINAL="Flubber.dmg"
STAGE="dmg-stage"
DS_STORE_SAVED="dmg/DS_Store"

# Finder-less mode: via flag or when running in CI.
PREBUILT=0
[ "$1" = "--prebuilt" ] && PREBUILT=1
[ "${CI:-}" = "true" ] && PREBUILT=1

# 1) Ensure the .app is built.
[ -d "$APP" ] || ./build.sh

# 2) Generate the DMG window background.
echo "🎨 Generando fondo del instalador…"
swiftc -O dmg/make-bg.swift -o /tmp/flubber-mkbg -framework Cocoa
/tmp/flubber-mkbg dmg/background.png

# 3) Staging folder: the app + alias to /Applications + hidden background.
rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
cp dmg/background.png "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"

# In prebuilt mode, inject the already-captured layout (without Finder).
if [ "$PREBUILT" = "1" ]; then
  [ -f "$DS_STORE_SAVED" ] || { echo "❌ Falta $DS_STORE_SAVED (genéralo una vez en local sin --prebuilt)"; exit 1; }
  cp "$DS_STORE_SAVED" "$STAGE/.DS_Store"
fi

# 4) Temporary read/write DMG.
rm -f "$DMG_TMP" "$DMG_FINAL"
echo "📦 Creando imagen…"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
  -format UDRW -ov "$DMG_TMP" >/dev/null

# 5) Mount. In interactive mode, compose the layout with Finder and save it.
if [ "$PREBUILT" = "0" ]; then
  DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" | grep -E '^/dev/' | head -1 | awk '{print $1}')
  sleep 2
  echo "🪟 Aplicando layout con Finder…"
  osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 110
    set text size of vo to 12
    set background picture of vo to file ".background:background.png"
    set position of item "$APP" of container window to {180, 210}
    set position of item "Applications" of container window to {480, 210}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
  sync
  cp "/Volumes/$VOL/.DS_Store" "$DS_STORE_SAVED"   # save the layout for CI
  echo "💾 Layout guardado en $DS_STORE_SAVED"
  hdiutil detach "$DEV" >/dev/null || hdiutil detach "$DEV" -force >/dev/null
fi

# 6) Convert to read-only compressed (the distributable one).
echo "🗜️  Comprimiendo…"
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" >/dev/null
rm -f "$DMG_TMP"; rm -rf "$STAGE"

# Remove the quarantine (local app).
xattr -dr com.apple.quarantine "$DMG_FINAL" 2>/dev/null || true

echo "✅ Listo: $(pwd)/$DMG_FINAL"
echo "   Ábrelo con:  open $DMG_FINAL"
