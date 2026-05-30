#!/bin/bash
# Compila Flubber y lo empaqueta como una app de macOS (.app)
set -e
cd "$(dirname "$0")"

APP="Flubber.app"
BIN="$APP/Contents/MacOS/Flubber"

echo "🔨 Compilando Flubber..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

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
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSAppSleepDisabled</key>      <true/>
</dict>
</plist>
PLIST

# Firma AD-HOC. Es la que deja ABRIR la app sin el bloqueo de Gatekeeper
# ("no se puede verificar / Abrir de todos modos") que sí ocurre con un
# certificado de desarrollo no notarizado.
# Nota: el permiso de Grabación de pantalla SÍ sobrevive a reinicios del Mac;
# solo se reinicia si se RECOMPILA la app (cambia la huella ad-hoc).
# (Para forzar otra identidad: FLUBBER_SIGN_ID=<hash> ./build.sh)
SIGN_ID="${FLUBBER_SIGN_ID:--}"
codesign --force --deep --sign "$SIGN_ID" "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP" 2>/dev/null || true

# Quita la "cuarentena" para que Gatekeeper no lo bloquee (app local).
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✅ Listo: $(pwd)/$APP"
echo "   Ábrelo con:  open $APP"
