#!/bin/bash
# Generates icon/AppIcon.icns from the slime pixel-art (icon/make-icon.swift).
set -e
cd "$(dirname "$0")"

echo "🎨 Generando ícono de la app…"
swiftc -O icon/make-icon.swift -o /tmp/flubber-mkicon -framework Cocoa

MASTER=/tmp/flubber-icon-1024.png
ICONSET=/tmp/Flubber.iconset
/tmp/flubber-mkicon "$MASTER" 1024
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

# Sizes required by iconutil (Apple).
sips -z 16   16   "$MASTER" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$MASTER" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$MASTER" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$MASTER" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$MASTER" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$MASTER" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$MASTER" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o icon/AppIcon.icns
echo "✅ icon/AppIcon.icns"
