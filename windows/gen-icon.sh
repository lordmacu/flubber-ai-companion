#!/bin/bash
# Generates the Windows icon (Flubber.ico + trayicon.png) using EXACTLY the
# same pixel-art render as macOS (icon/make-icon.swift). This makes the icon 100%
# identical on both platforms. Run on macOS (uses swiftc + sips).
set -e
cd "$(dirname "$0")/.."   # repo root

echo "🎨 Render maestro (mismo que macOS)…"
swiftc -O icon/make-icon.swift -o /tmp/flubber-mkicon -framework Cocoa
swiftc -O icon/make-ico.swift  -o /tmp/flubber-mkico
MASTER=/tmp/flubber-win-1024.png
/tmp/flubber-mkicon "$MASTER" 1024

TMP=$(mktemp -d)
SIZES="16 24 32 48 64 128 256"
ARGS=()
for s in $SIZES; do
  sips -z "$s" "$s" "$MASTER" --out "$TMP/$s.png" >/dev/null
  ARGS+=("$s:$TMP/$s.png")
done

echo "📦 Ensamblando Flubber.ico…"
/tmp/flubber-mkico windows/Flubber.App/Flubber.ico "${ARGS[@]}"

echo "🖼️  trayicon.png (256, para la bandeja)…"
cp "$TMP/256.png" windows/Flubber.App/trayicon.png

rm -rf "$TMP"
echo "✅ windows/Flubber.App/Flubber.ico + trayicon.png"
