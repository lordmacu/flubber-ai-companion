#!/bin/bash
# Crea Flubber.dmg con la pantalla clásica de instalación:
# el ícono de Flubber con una flecha → carpeta Applications para arrastrarlo.
#
# Modos:
#   ./make-dmg.sh             -> usa Finder para componer el layout y GUARDA
#                                el resultado en dmg/DS_Store (para versionarlo).
#   ./make-dmg.sh --prebuilt  -> NO usa Finder; reutiliza dmg/DS_Store.
#                                (se activa solo también si la var CI=true, p.ej. en GitHub Actions)
set -e
cd "$(dirname "$0")"

APP="Flubber.app"
VOL="Flubber"
DMG_TMP="Flubber-tmp.dmg"
DMG_FINAL="Flubber.dmg"
STAGE="dmg-stage"
DS_STORE_SAVED="dmg/DS_Store"

# Modo sin Finder: por flag o cuando corre en CI.
PREBUILT=0
[ "$1" = "--prebuilt" ] && PREBUILT=1
[ "${CI:-}" = "true" ] && PREBUILT=1

# 1) Asegura el .app compilado.
[ -d "$APP" ] || ./build.sh

# 2) Genera el fondo de la ventana del DMG.
echo "🎨 Generando fondo del instalador…"
swiftc -O dmg/make-bg.swift -o /tmp/flubber-mkbg -framework Cocoa
/tmp/flubber-mkbg dmg/background.png

# 3) Carpeta de staging: la app + alias a /Applications + fondo oculto.
rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
cp dmg/background.png "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"

# En modo prebuilt, inyecta el layout ya capturado (sin Finder).
if [ "$PREBUILT" = "1" ]; then
  [ -f "$DS_STORE_SAVED" ] || { echo "❌ Falta $DS_STORE_SAVED (genéralo una vez en local sin --prebuilt)"; exit 1; }
  cp "$DS_STORE_SAVED" "$STAGE/.DS_Store"
fi

# 4) DMG temporal de lectura/escritura.
rm -f "$DMG_TMP" "$DMG_FINAL"
echo "📦 Creando imagen…"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
  -format UDRW -ov "$DMG_TMP" >/dev/null

# 5) Monta. En modo interactivo, compone el layout con Finder y lo guarda.
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
  cp "/Volumes/$VOL/.DS_Store" "$DS_STORE_SAVED"   # guarda el layout para CI
  echo "💾 Layout guardado en $DS_STORE_SAVED"
  hdiutil detach "$DEV" >/dev/null || hdiutil detach "$DEV" -force >/dev/null
fi

# 6) Convierte a comprimido de solo lectura (lo distribuible).
echo "🗜️  Comprimiendo…"
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" >/dev/null
rm -f "$DMG_TMP"; rm -rf "$STAGE"

# Quita la cuarentena (app local).
xattr -dr com.apple.quarantine "$DMG_FINAL" 2>/dev/null || true

echo "✅ Listo: $(pwd)/$DMG_FINAL"
echo "   Ábrelo con:  open $DMG_FINAL"
