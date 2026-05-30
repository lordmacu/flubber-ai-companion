#!/bin/bash
# Compila Flubber y lo empaqueta como una app de macOS (.app)
set -e
cd "$(dirname "$0")"

APP="Flubber.app"
BIN="$APP/Contents/MacOS/Flubber"

echo "🔨 Compilando Flubber..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Ícono de la app (mismo pixel-art del slime, generado por código).
./make-icon.sh
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O Sources/*.swift -o "$BIN" -framework Cocoa -framework Security -framework UserNotifications

# Info.plist — LSUIElement=true => agente en segundo plano (sin Dock)
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Flubber</string>
    <key>CFBundleDisplayName</key>     <string>Flubber</string>
    <key>CFBundleIdentifier</key>      <string>co.cristiangarcia.slimepet</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>Flubber</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSpeechRecognitionUsageDescription</key> <string>Flubber transcribe el audio de tu reunión en el dispositivo para poder resumirla.</string>
    <key>NSAppSleepDisabled</key>      <true/>
</dict>
</plist>
PLIST

# Firma: ad-hoc por defecto (así `open` funciona desde Terminal sin notarizar).
# Si exportas FLUBBER_SIGN_ID con una identidad VÁLIDA (no revocada) la usa; si
# no, cae a ad-hoc. (Un certificado de desarrollo revocado da error 163 al abrir
# por Gatekeeper, así que NO se usa ninguno por defecto.)
if [ -n "$FLUBBER_SIGN_ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$FLUBBER_SIGN_ID"; then
  echo "🔏 Firmando con $FLUBBER_SIGN_ID"
  codesign --force --deep --sign "$FLUBBER_SIGN_ID" "$APP" 2>/dev/null \
    || codesign --force --deep --sign - "$APP" 2>/dev/null || true
else
  echo "🔏 Firma ad-hoc."
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

# Quita la "cuarentena" para que Gatekeeper no lo bloquee (app local).
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✅ Listo: $(pwd)/$APP"
echo "   Ábrelo con:  open $APP"
