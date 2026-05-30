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

# Firma. Prioridad:
#   1) FLUBBER_SIGN_ID (si lo exportas con una identidad válida).
#   2) Certificado self-signed local "Flubber Self-Signed" (creado con
#      setup-signing-cert.sh). Su huella es ESTABLE entre rebuilds, así que el
#      permiso de Grabación de pantalla (TCC, anclado al cert) PERSISTE. Pide un
#      único "Abrir de todos modos" la primera vez (no está notarizada).
#   3) Ad-hoc (CI / si no hay cert). Funciona, pero el permiso se reinicia en
#      cada rebuild porque la huella del binario cambia.
# (Un certificado de desarrollo REVOCADO da error 163 al abrir: no usar.)
SIGN_ID="$FLUBBER_SIGN_ID"
[ -z "$SIGN_ID" ] && SIGN_ID=$(security find-identity -p codesigning 2>/dev/null \
  | grep "Flubber Self-Signed" | grep -oE '[0-9A-F]{40}' | head -1)

if [ -n "$SIGN_ID" ] && security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "🔏 Firmando con identidad estable ($SIGN_ID) — el permiso de pantalla persiste."
  codesign --force --deep --sign "$SIGN_ID" "$APP" 2>/dev/null \
    || codesign --force --deep --sign - "$APP" 2>/dev/null || true
else
  echo "🔏 Firma ad-hoc (el permiso de pantalla se reinicia en cada rebuild)."
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

# Quita la "cuarentena" para que Gatekeeper no lo bloquee (app local).
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✅ Listo: $(pwd)/$APP"
echo "   Ábrelo con:  open $APP"
